import mongoose from 'mongoose';

/**
 * Append-only ledger of every credit movement. Rows are never updated in place
 * except to flip `applied` (and stamp `balanceAfter`) once the wallet `$inc`
 * has landed — that is the two-phase write walletService performs.
 *
 * Why append-only: the wallet balance is derived money. If a balance ever
 * disagrees with the sum of this ledger, the ledger is the truth and the
 * balance is the bug.
 */
const AdCreditTransactionSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  // Sign is implied by type, never stored: purchase/refund/grant add,
  // spend/reversal subtract. `amount` is always positive.
  type: {
    type: String,
    required: true,
    enum: ['purchase', 'spend', 'refund', 'grant', 'reversal']
  },
  amount: {
    type: Number,
    required: true,
    min: 1
  },
  // Wallet balance immediately after this row was applied. Null until applied.
  balanceAfter: {
    type: Number
  },
  source: {
    type: String,
    required: true,
    enum: ['revenuecat', 'admin', 'campaign', 'system']
  },
  // Idempotency key. For RevenueCat this is the webhook event id; for admin
  // grants it is 'admin:<uuid>'. Unique+sparse index below is what makes a
  // retried webhook credit nothing instead of minting free money.
  externalId: {
    type: String
  },
  campaignId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdCampaign'
  },
  productId: {
    type: String
  },
  // False means "recorded but the wallet has not moved yet". The reconcile
  // sweep (scripts/reconcile-ad-credits.js) finishes these, which is why a
  // crash between the two phases loses nothing.
  applied: {
    type: Boolean,
    default: false,
    index: true
  },
  appliedAt: {
    type: Date
  },
  reason: {
    type: String
  },
  metadata: {
    type: Object
  }
}, {
  timestamps: true
});

// Idempotency: two rows can never share an externalId. Sparse so the many
// rows without one (spend, refund) don't collide on null.
AdCreditTransactionSchema.index({ externalId: 1 }, { unique: true, sparse: true });
// History listing, newest first.
AdCreditTransactionSchema.index({ userId: 1, createdAt: -1 });
// Reconcile sweep: unapplied rows, oldest first.
AdCreditTransactionSchema.index({ applied: 1, createdAt: 1 });

const AdCreditTransaction = mongoose.models.AdCreditTransaction
  || mongoose.model('AdCreditTransaction', AdCreditTransactionSchema);

export default AdCreditTransaction;
