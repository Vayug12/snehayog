import express from 'express';
import crypto from 'crypto';
import User from '../../models/User.js';
import walletService from '../../services/adServices/walletService.js';
import { creditsForProduct } from '../../config/adCreditProducts.js';
import { purchaseExternalId } from '../../services/adServices/revenueCatPurchaseSyncService.js';

/**
 * RevenueCat webhook — the only path by which purchased credits enter a wallet.
 *
 * Design rules, all of which exist because this endpoint mints money:
 *
 *  1. **The shared secret is compared in constant time.** A `!==` on a secret
 *     leaks it one byte at a time to anyone who can measure response latency.
 *  2. **Sandbox events are refused in production.** Without this, anyone with a
 *     test device on the app mints unlimited real credits.
 *  3. **Credits come from a server-side product map**, never from any price or
 *     amount in the payload.
 *  4. **Anything durably recorded answers 200 — including duplicates.** A
 *     non-2xx makes RevenueCat retry, and the ledger's unique `externalId`
 *     index already makes a retry harmless. Answering 500 to a duplicate would
 *     produce a retry storm over something that already succeeded.
 *  5. **A 200 is only sent once the credit is written.** Anything we could not
 *     record gets a 5xx so RevenueCat retries it, and `reconcile-revenuecat.js`
 *     catches whatever the retries still miss.
 *
 * Mounted with `express.raw` before the global `express.json()`, because the
 * signature check needs the exact bytes that were signed.
 */

const router = express.Router();

/** Purchase events. Consumables arrive as NON_RENEWING_PURCHASE. */
const PURCHASE_EVENTS = new Set(['NON_RENEWING_PURCHASE', 'INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE_EVENT']);

/** Money going back to the buyer. */
const REVERSAL_EVENTS = new Set(['CANCELLATION', 'REFUND', 'SUBSCRIPTION_PAUSED']);

/**
 * Constant-time secret comparison.
 *
 * `timingSafeEqual` throws on length mismatch, which would itself leak the
 * secret's length, so both sides are hashed to a fixed width first.
 */
const secretMatches = (provided, expected) => {
  if (!provided || !expected) return false;
  const a = crypto.createHash('sha256').update(String(provided)).digest();
  const b = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(a, b);
};

const signatureMatches = (rawBody, header, secret) => {
  if (!Buffer.isBuffer(rawBody) || !header || !secret) return false;

  const parts = Object.fromEntries(
    String(header)
      .split(',')
      .map((part) => part.trim().split('='))
      .filter(([key, value]) => key && value)
  );
  const timestamp = Number(parts.t);
  if (!Number.isFinite(timestamp)) return false;

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestamp) > 5 * 60) return false;

  const expectedSignature = crypto
    .createHmac('sha256', secret)
    .update(`${timestamp}.`)
    .update(rawBody)
    .digest('hex');

  return secretMatches(parts.v1, expectedSignature);
};

/**
 * Resolve the buyer.
 *
 * `app_user_id` is whatever the client passed to `Purchases.logIn()`. We log in
 * with the Google ID, but RevenueCat also carries `original_app_user_id` and
 * aliases, so all of them are tried before giving up.
 */
const resolveUser = async (event) => {
  const candidates = [
    event?.app_user_id,
    event?.original_app_user_id,
    ...(Array.isArray(event?.aliases) ? event.aliases : [])
  ]
    .map((id) => (typeof id === 'string' ? id.trim() : ''))
    .filter(Boolean)
    // RevenueCat prefixes ids it generated itself; those are anonymous
    // purchases and cannot be attributed to an account.
    .filter((id) => !id.startsWith('$RCAnonymousID:'));

  if (candidates.length === 0) return null;

  return User.findOne({ googleId: { $in: candidates } }).select('_id googleId').lean();
};

router.post(
  '/revenuecat',
  express.raw({ type: '*/*', limit: '1mb' }),
  async (req, res) => {
    const expected = process.env.REVENUECAT_WEBHOOK_SECRET;

    // Fail closed. An unconfigured secret would otherwise mean an open,
    // unauthenticated endpoint that creates credits.
    if (!expected) {
      console.error('❌ RevenueCat webhook hit but REVENUECAT_WEBHOOK_SECRET is not set');
      return res.status(503).json({ error: 'Webhook not configured' });
    }

    if (!secretMatches(req.get('authorization'), expected)) {
      console.warn('⚠️ RevenueCat webhook rejected: bad Authorization header');
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const signingSecret = process.env.REVENUECAT_WEBHOOK_SIGNING_SECRET;
    if (signingSecret && !signatureMatches(
      req.body,
      req.get('x-revenuecat-webhook-signature'),
      signingSecret
    )) {
      console.warn('RevenueCat webhook rejected: invalid HMAC signature');
      return res.status(401).json({ error: 'Invalid webhook signature' });
    }

    let payload;
    try {
      payload = JSON.parse(Buffer.isBuffer(req.body) ? req.body.toString('utf8') : String(req.body));
    } catch {
      // Malformed and unfixable by retrying.
      return res.status(400).json({ error: 'Invalid JSON' });
    }

    const event = payload?.event || payload;
    const eventId = event?.id;
    const eventType = event?.type;

    if (!eventId || !eventType) {
      return res.status(400).json({ error: 'Missing event id or type' });
    }

    // A sandbox purchase costs nothing. Crediting one in production is free
    // money for anyone who can install a test build.
    if (event.environment === 'SANDBOX' && process.env.NODE_ENV === 'production') {
      console.warn(`⚠️ RevenueCat: ignoring SANDBOX ${eventType} (${eventId}) in production`);
      return res.status(200).json({ received: true, ignored: 'sandbox_in_production' });
    }

    const isPurchase = PURCHASE_EVENTS.has(eventType);
    const isReversal = REVERSAL_EVENTS.has(eventType);

    if (!isPurchase && !isReversal) {
      // Transfers, billing issues, test events… nothing to do, but 200 so it
      // is not retried forever.
      return res.status(200).json({ received: true, ignored: `unhandled_type:${eventType}` });
    }

    const credits = creditsForProduct(event.product_id);
    if (credits === null) {
      // 200 stops the retries — no amount of retrying makes a product we do
      // not sell resolvable. Logged loudly because it means a Play Console
      // product exists that this server has never been told about.
      console.error(`🚨 RevenueCat: unknown product_id "${event.product_id}" on ${eventType} (${eventId})`);
      return res.status(200).json({ received: true, ignored: 'unknown_product' });
    }

    const user = await resolveUser(event);
    if (!user) {
      // Also a 200: an unattributable purchase will not become attributable on
      // retry. The reconcile script re-checks these later, by which time the
      // user may have signed in.
      console.error(`🚨 RevenueCat: no user for app_user_id "${event.app_user_id}" on ${eventType} (${eventId})`);
      return res.status(200).json({ received: true, ignored: 'unknown_user' });
    }

    try {
      if (isPurchase) {
        const { wallet, duplicate } = await walletService.credit({
          userId: user._id,
          amount: credits,
          type: 'purchase',
          source: 'revenuecat',
          // Store transaction identity is shared with REST reconciliation, so
          // either path can arrive first without minting the purchase twice.
          externalId: purchaseExternalId(
            event.transaction_id || event.original_transaction_id || eventId
          ),
          productId: event.product_id,
          reason: eventType,
          metadata: {
            store: event.store,
            environment: event.environment,
            purchasedAtMs: event.purchased_at_ms,
            transactionId: event.transaction_id
          }
        });

        console.log(`💳 RevenueCat: ${duplicate ? 'duplicate' : 'credited'} ${credits} to ${user.googleId} (balance ${wallet?.balance})`);
        return res.status(200).json({ received: true, duplicate, balance: wallet?.balance });
      }

      const { wallet, duplicate, frozen } = await walletService.reverse({
        userId: user._id,
        amount: credits,
        source: 'revenuecat',
        externalId: `revenuecat_reversal:${
          event.transaction_id || event.original_transaction_id || eventId
        }`,
        productId: event.product_id,
        reason: eventType,
        metadata: {
          store: event.store,
          environment: event.environment,
          cancelReason: event.cancel_reason
        }
      });

      console.log(`↩️ RevenueCat: ${duplicate ? 'duplicate' : 'reversed'} ${credits} from ${user.googleId} (balance ${wallet?.balance}${frozen ? ', wallet frozen' : ''})`);
      return res.status(200).json({ received: true, duplicate, balance: wallet?.balance, frozen });
    } catch (err) {
      // A 5xx is the right answer here: we could not durably record it, so we
      // want RevenueCat to try again.
      console.error(`❌ RevenueCat: failed to apply ${eventType} (${eventId}): ${err.message}`);
      return res.status(500).json({ error: 'Could not record event' });
    }
  }
);

export default router;
