import mongoose from 'mongoose';
import AdWallet from '../../models/AdWallet.js';
import AdCreditTransaction from '../../models/AdCreditTransaction.js';

/**
 * Ad-credit wallet ledger.
 *
 * 1 credit = ₹1 of ad spend. Balances are whole integers; rounding always
 * favours the platform (refunds are floored) so the ledger can never
 * manufacture money.
 *
 * Two rules hold this together:
 *
 *  1. **Every balance change is ledgered.** The wallet balance is a rollup of
 *     AdCreditTransaction, not an independent number. Money that moves without
 *     a row is unauditable and unrecoverable.
 *
 *  2. **Credits are two-phase; debits are atomic.** A credit writes an
 *     unapplied ledger row *first*, then moves the balance — so a crash leaves
 *     a row the reconcile sweep can finish, never a silent loss. A debit moves
 *     the balance in a single conditional update — so two parallel spends can
 *     never both pass an overdraft check.
 *
 * No Mongo transactions are used deliberately: the `applied` flag plus the
 * unique `externalId` index give idempotency and crash recovery without
 * requiring a replica set.
 */

const MONGO_DUPLICATE_KEY = 11000;

/** Types that increase a balance. Campaign spend goes through `debit()`. */
const CREDIT_TYPES = new Set(['purchase', 'refund', 'grant']);

/**
 * Types `applyTransaction` can settle. `reversal` is the store-refund case: it
 * decreases a balance but, unlike `debit`, it must land even when the balance
 * does not cover it — the money has already gone back to the buyer.
 */
const APPLIABLE_TYPES = new Set([...CREDIT_TYPES, 'reversal']);

export class InsufficientCreditsError extends Error {
  constructor(required, available) {
    super('Insufficient ad credits');
    this.name = 'InsufficientCreditsError';
    this.code = 'INSUFFICIENT_CREDITS';
    this.statusCode = 402;
    this.required = required;
    this.available = available;
    this.shortfall = Math.max(0, required - available);
  }
}

export class WalletFrozenError extends Error {
  constructor() {
    super('Ad credit wallet is frozen');
    this.name = 'WalletFrozenError';
    this.code = 'WALLET_FROZEN';
    this.statusCode = 403;
  }
}

const isDuplicateKeyError = (err) => err?.code === MONGO_DUPLICATE_KEY || err?.code === '11000';

/**
 * Credits and debits are always whole, positive credits.
 *
 * Rejecting non-integers here rather than rounding is deliberate: a caller
 * that produced 99.999 credits has a bug, and silently rounding it hides the
 * bug inside the money path.
 */
const assertValidAmount = (amount) => {
  if (!Number.isFinite(amount) || !Number.isInteger(amount) || amount < 1) {
    throw new Error(`Invalid credit amount: ${amount} (must be a positive integer)`);
  }
};

const toObjectId = (userId) => {
  if (userId instanceof mongoose.Types.ObjectId) return userId;
  if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
    throw new Error(`Invalid userId for wallet operation: ${userId}`);
  }
  return new mongoose.Types.ObjectId(String(userId));
};

const assertMatchingTransaction = (existing, { userId, type, amount }) => {
  if (
    existing.type !== type
    || String(existing.userId) !== String(userId)
    || existing.amount !== amount
  ) {
    throw new Error('Idempotency key was already used for a different wallet transaction');
  }
};

/**
 * Fetch the caller's wallet, creating it on first touch.
 *
 * `$setOnInsert` keeps this safe to call on every read — it never resets an
 * existing balance. Two concurrent first-requests can still collide on the
 * unique index, which is not a failure: the loser just re-reads the winner's
 * document.
 */
export const getOrCreateWallet = async (userId) => {
  const _id = toObjectId(userId);

  try {
    return await AdWallet.findOneAndUpdate(
      { userId: _id },
      {
        $setOnInsert: {
          userId: _id,
          balance: 0,
          lifetimePurchased: 0,
          lifetimeSpent: 0,
          currency: 'INR',
          status: 'active'
        }
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
  } catch (err) {
    if (isDuplicateKeyError(err)) {
      const existing = await AdWallet.findOne({ userId: _id });
      if (existing) return existing;
    }
    throw err;
  }
};

/**
 * Balance update expressed as an aggregation pipeline so the lifetime
 * counters can be clamped at zero in the same atomic write.
 *
 * A refund reduces `lifetimeSpent` rather than inflating `lifetimePurchased`:
 * the credits were never bought a second time, they were only returned.
 */
const walletDeltaPipeline = (type, amount) => {
  // A reversal is the only appliable type that moves the balance down, and it
  // is not clamped at zero: it may legitimately overdraw.
  const signed = type === 'reversal' ? -amount : amount;
  const set = {
    balance: { $add: [{ $ifNull: ['$balance', 0] }, signed] }
  };

  if (type === 'purchase') {
    set.lifetimePurchased = { $add: [{ $ifNull: ['$lifetimePurchased', 0] }, amount] };
  }

  if (type === 'reversal') {
    // The purchase was undone, so it should stop counting as purchased.
    set.lifetimePurchased = {
      $max: [0, { $subtract: [{ $ifNull: ['$lifetimePurchased', 0] }, amount] }]
    };
  }

  if (type === 'refund') {
    set.lifetimeSpent = {
      $max: [0, { $subtract: [{ $ifNull: ['$lifetimeSpent', 0] }, amount] }]
    };
  }

  return [{ $set: set }];
};

/**
 * Exact inverse of `walletDeltaPipeline`, used to undo a lost apply race.
 *
 * The balance term is unclamped on purpose: this only ever runs immediately
 * after the matching delta was applied, so subtracting it back is always
 * arithmetically correct — and clamping would corrupt a legitimately negative
 * balance left by a reversal.
 */
const walletRevertPipeline = (type, amount) => {
  const signed = type === 'reversal' ? -amount : amount;
  const set = {
    balance: { $subtract: [{ $ifNull: ['$balance', 0] }, signed] }
  };

  if (type === 'purchase') {
    set.lifetimePurchased = {
      $max: [0, { $subtract: [{ $ifNull: ['$lifetimePurchased', 0] }, amount] }]
    };
  }

  if (type === 'reversal') {
    set.lifetimePurchased = { $add: [{ $ifNull: ['$lifetimePurchased', 0] }, amount] };
  }

  if (type === 'refund') {
    set.lifetimeSpent = { $add: [{ $ifNull: ['$lifetimeSpent', 0] }, amount] };
  }

  return [{ $set: set }];
};

/**
 * Phase 2 of a credit: move the balance, then claim the row.
 *
 * Exported because the reconcile sweep applies orphaned rows through exactly
 * this path — there must be only one implementation of "apply".
 *
 * The order matters. Moving money first and claiming second means a crash in
 * between leaves the row unapplied, so the sweep retries it: the failure mode
 * is "credited twice at most, never lost". The double-credit half is then
 * closed by the claim itself — `{ _id, applied: false }` can only succeed for
 * one caller, and whoever loses reverses the increment it just made.
 */
export const applyTransaction = async (transaction) => {
  if (!transaction) throw new Error('applyTransaction called without a transaction');
  if (transaction.applied) return transaction;

  const { type, amount, userId } = transaction;
  if (!APPLIABLE_TYPES.has(type)) {
    throw new Error(`applyTransaction cannot settle type: ${type}`);
  }
  assertValidAmount(amount);

  await getOrCreateWallet(userId);

  const wallet = await AdWallet.findOneAndUpdate(
    { userId },
    walletDeltaPipeline(type, amount),
    { new: true }
  );

  if (!wallet) {
    throw new Error(`Wallet vanished while applying transaction ${transaction._id}`);
  }

  let balanceReverted = false;
  try {
    const claimed = await AdCreditTransaction.findOneAndUpdate(
      { _id: transaction._id, applied: false },
      { $set: { applied: true, appliedAt: new Date(), balanceAfter: wallet.balance } },
      { new: true }
    );

    if (claimed) {
      // Not persisted — tells the caller *this* call is what moved the money,
      // so the reconcile sweep can report real work separately from rows a
      // concurrent worker had already handled.
      claimed.$locals.appliedNow = true;
      return claimed;
    }

    // Someone else (the sweep, or a concurrent retry) applied this row first.
    // Our increment was a duplicate — undo it and report their result.
    await AdWallet.updateOne({ userId }, walletRevertPipeline(type, amount));
    balanceReverted = true;
    return await AdCreditTransaction.findById(transaction._id);
  } catch (err) {
    // The balance moved but we could not record that it did. Roll it back so
    // the ledger stays the source of truth.
    if (!balanceReverted) {
      await AdWallet.updateOne({ userId }, walletRevertPipeline(type, amount))
        .catch((revertErr) => {
          console.error('❌ CRITICAL: failed to revert wallet after apply failure', {
            transactionId: String(transaction._id),
            userId: String(userId),
            amount,
            revertError: revertErr?.message
          });
        });
    }
    throw err;
  }
};

/**
 * Add credits to a wallet. Idempotent on `externalId`.
 *
 * @returns {{ transaction, wallet, duplicate: boolean }} `duplicate: true`
 *   means an earlier call with this `externalId` already credited — nothing
 *   was added. Callers should treat that as success; it is what makes a
 *   retried payment webhook harmless.
 */
export const credit = async ({
  userId,
  amount,
  type = 'purchase',
  source,
  externalId = null,
  campaignId = null,
  productId = null,
  reason = null,
  metadata = null
}) => {
  if (!CREDIT_TYPES.has(type)) {
    throw new Error(`Invalid credit type: ${type}`);
  }
  if (!source) throw new Error('credit() requires a source');
  assertValidAmount(amount);

  const _id = toObjectId(userId);

  let transaction;
  try {
    // Phase 1: record the intent before any money moves.
    transaction = await AdCreditTransaction.create({
      userId: _id,
      type,
      amount,
      source,
      externalId,
      campaignId,
      productId,
      reason,
      metadata,
      applied: false
    });
  } catch (err) {
    if (isDuplicateKeyError(err) && externalId) {
      // A retry of a credit we have already recorded. Not an error — return
      // the original row and credit nothing.
      const existing = await AdCreditTransaction.findOne({ externalId });
      if (existing) {
        assertMatchingTransaction(existing, { userId: _id, type, amount });
        // The original may have died before phase 2; finish it if so.
        const settled = existing.applied ? existing : await applyTransaction(existing);
        const wallet = await getOrCreateWallet(_id);
        return { transaction: settled, wallet, duplicate: true };
      }
    }
    throw err;
  }

  // Phase 2: move the balance and mark the row applied.
  const applied = await applyTransaction(transaction);
  const wallet = await AdWallet.findOne({ userId: _id });

  return { transaction: applied, wallet, duplicate: false };
};

/**
 * Remove credits from a wallet. Throws rather than overdrawing.
 *
 * The `balance: { $gte: amount }` lives in the *filter*, not in a preceding
 * `if`. That is the entire overdraft defence: twenty parallel debits against
 * one balance are serialised by the document write, and only the ones the
 * balance covers match.
 */
export const debit = async ({
  userId,
  amount,
  campaignId = null,
  reason = null,
  source = 'campaign',
  externalId = null,
  metadata = null
}) => {
  assertValidAmount(amount);
  const _id = toObjectId(userId);

  if (externalId) {
    const existing = await AdCreditTransaction.findOne({ externalId });
    if (existing) {
      assertMatchingTransaction(existing, {
        userId: _id,
        type: 'spend',
        amount
      });
      return {
        transaction: existing,
        wallet: await getOrCreateWallet(_id),
        duplicate: true
      };
    }
  }

  await getOrCreateWallet(_id);

  const wallet = await AdWallet.findOneAndUpdate(
    { userId: _id, status: 'active', balance: { $gte: amount } },
    { $inc: { balance: -amount, lifetimeSpent: amount } },
    { new: true }
  );

  if (!wallet) {
    // Distinguish "no money" from "frozen" — they are different fixes for the
    // user, and this read only happens on the failure path.
    const current = await AdWallet.findOne({ userId: _id });
    if (current?.status === 'frozen') throw new WalletFrozenError();
    throw new InsufficientCreditsError(amount, current?.balance ?? 0);
  }

  let debitReverted = false;
  try {
    const transaction = await AdCreditTransaction.create({
      userId: _id,
      type: 'spend',
      amount,
      source,
      externalId,
      campaignId,
      reason,
      metadata,
      applied: true,
      appliedAt: new Date(),
      balanceAfter: wallet.balance
    });

    return { transaction, wallet, duplicate: false };
  } catch (err) {
    if (isDuplicateKeyError(err) && externalId) {
      // Two identical requests may both pass the initial lookup and debit the
      // wallet. Only one can insert the unique ledger key; undo this request's
      // debit and return the winner.
      await AdWallet.updateOne(
        { userId: _id },
        { $inc: { balance: amount, lifetimeSpent: -amount } }
      );
      debitReverted = true;

      const existing = await AdCreditTransaction.findOne({ externalId });
      if (existing) {
        assertMatchingTransaction(existing, {
          userId: _id,
          type: 'spend',
          amount
        });
        return {
          transaction: existing,
          wallet: await getOrCreateWallet(_id),
          duplicate: true
        };
      }
    }

    // The debit landed but is unrecorded. Give the credits back rather than
    // keep money we cannot account for.
    if (!debitReverted) {
      await AdWallet.updateOne(
        { userId: _id },
        { $inc: { balance: amount, lifetimeSpent: -amount } }
      ).catch((revertErr) => {
        console.error('❌ CRITICAL: failed to revert debit after ledger write failure', {
          userId: String(_id),
          amount,
          revertError: revertErr?.message
        });
      });
    }
    throw err;
  }
};

/**
 * Return unspent credits — a campaign that ended under budget, or a support
 * correction.
 *
 * Floored, because a campaign accrues fractional spend but the wallet is
 * integral. The fraction is kept by the platform; refunding a rounded-up
 * credit would let repeated create/cancel cycles mint money.
 */
export const refund = async ({
  userId,
  amount,
  campaignId = null,
  reason = null,
  externalId = null,
  metadata = null
}) => {
  const whole = Math.floor(amount);
  if (whole < 1) {
    return { transaction: null, wallet: await getOrCreateWallet(userId), skipped: true };
  }

  return credit({
    userId,
    amount: whole,
    type: 'refund',
    source: 'campaign',
    campaignId,
    reason,
    externalId,
    metadata
  });
};

/**
 * Take back credits from a purchase the store refunded or revoked.
 *
 * This is the counterpart to `credit({ type: 'purchase' })` and it is what
 * stops the obvious exploit: buy credits, spend them on a campaign, then ask
 * Google for a refund. Absorbing that silently is free advertising, so the
 * reversal lands **even when the balance does not cover it** — the wallet goes
 * negative and the user has to make it whole before they can spend again.
 *
 * Two mechanisms hold that, because arithmetic alone would be fragile:
 *  - `debit()` filters on `balance: { $gte: amount }`, which no positive amount
 *    can satisfy against a negative balance;
 *  - the wallet is frozen, which `debit()` also filters on, and which forces a
 *    human to look at the account before spending resumes.
 *
 * A reversal that the balance *does* cover is an ordinary correction — an
 * accidental purchase refunded before it was spent — and does not freeze.
 *
 * Idempotent on `externalId`, like `credit`: RevenueCat retries cancellations
 * too, and applying one twice would double the debt.
 */
export const reverse = async ({
  userId,
  amount,
  source = 'revenuecat',
  externalId = null,
  productId = null,
  reason = null,
  metadata = null
}) => {
  assertValidAmount(amount);
  const _id = toObjectId(userId);

  let transaction;
  try {
    transaction = await AdCreditTransaction.create({
      userId: _id,
      type: 'reversal',
      amount,
      source,
      externalId,
      productId,
      reason,
      metadata,
      applied: false
    });
  } catch (err) {
    if (isDuplicateKeyError(err) && externalId) {
      const existing = await AdCreditTransaction.findOne({ externalId });
      if (existing) {
        assertMatchingTransaction(existing, {
          userId: _id,
          type: 'reversal',
          amount
        });
        const settled = existing.applied ? existing : await applyTransaction(existing);
        const wallet = await getOrCreateWallet(_id);
        return { transaction: settled, wallet, duplicate: true, frozen: wallet.status === 'frozen' };
      }
    }
    throw err;
  }

  const applied = await applyTransaction(transaction);
  let wallet = await AdWallet.findOne({ userId: _id });

  if (wallet && wallet.balance < 0 && wallet.status !== 'frozen') {
    wallet = await AdWallet.findOneAndUpdate(
      { userId: _id },
      { $set: { status: 'frozen' } },
      { new: true }
    );
    console.warn(`🧊 walletService: wallet ${_id} frozen at ${wallet?.balance} after a ${amount}-credit reversal`);
  }

  return {
    transaction: applied,
    wallet,
    duplicate: false,
    frozen: wallet?.status === 'frozen'
  };
};

/** Balance read. Creates the wallet lazily so a first-time user sees zero, not a 404. */
export const getBalance = async (userId) => {
  const wallet = await getOrCreateWallet(userId);
  return {
    balance: wallet.balance,
    currency: wallet.currency,
    status: wallet.status,
    lifetimePurchased: wallet.lifetimePurchased,
    lifetimeSpent: wallet.lifetimeSpent
  };
};

/** Paginated ledger history, newest first. Served by the `{ userId, createdAt }` index. */
export const getTransactions = async (userId, { page = 1, limit = 20 } = {}) => {
  const _id = toObjectId(userId);
  const skip = (page - 1) * limit;

  const [items, total] = await Promise.all([
    AdCreditTransaction.find({ userId: _id })
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean(),
    AdCreditTransaction.countDocuments({ userId: _id })
  ]);

  return {
    items,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit) || 1,
      hasMore: skip + items.length < total
    }
  };
};

export default {
  getOrCreateWallet,
  getBalance,
  getTransactions,
  credit,
  debit,
  refund,
  reverse,
  applyTransaction,
  InsufficientCreditsError,
  WalletFrozenError
};
