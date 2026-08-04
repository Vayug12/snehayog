import mongoose from 'mongoose';

/**
 * Prepaid ad-credit balance. One wallet per user.
 *
 * 1 credit = ₹1 of ad spend, and balances are whole integers only — campaign
 * budgets are integers, so a fractional balance could never be fully spent.
 * (Campaign `spentINR` stays fractional because it accrues per impression;
 * only the wallet is integral.)
 *
 * This document holds the *balance*. Every change to it is also written to
 * AdCreditTransaction, which is the append-only audit trail. The balance is a
 * cached rollup of that ledger — Phase 4 asserts the two agree.
 */
const AdWalletSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    unique: true,
    index: true
  },
  // Whole credits. What prevents an overdraft is the `balance: { $gte: amount }`
  // filter on the atomic debit in walletService, not a schema bound — a
  // read-check-write here would be a race.
  //
  // Deliberately **not** `min: 0`. A store refund of credits the user has
  // already spent has to land as a negative balance, or "buy, spend, refund"
  // is free advertising. Spending is blocked while negative both by that
  // `$gte` filter and by the freeze the reversal applies.
  balance: {
    type: Number,
    default: 0
  },
  lifetimePurchased: {
    type: Number,
    default: 0,
    min: 0
  },
  lifetimeSpent: {
    type: Number,
    default: 0,
    min: 0
  },
  currency: {
    type: String,
    default: 'INR'
  },
  // `frozen` stops spend during a chargeback or fraud review without deleting
  // history. The debit filter requires status 'active', so freezing is enough.
  status: {
    type: String,
    enum: ['active', 'frozen'],
    default: 'active'
  }
}, {
  timestamps: true
});

const AdWallet = mongoose.models.AdWallet || mongoose.model('AdWallet', AdWalletSchema);

export default AdWallet;
