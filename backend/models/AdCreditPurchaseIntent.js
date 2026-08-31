import mongoose from 'mongoose';

/**
 * Short-lived record that a signed-in user is about to open Play Billing.
 *
 * It gives reconciliation a bounded list of customers to inspect even when
 * the webhook for a user's very first purchase never reaches this server.
 */
const AdCreditPurchaseIntentSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  productId: {
    type: String,
    required: true,
    trim: true
  },
  expiresAt: {
    type: Date,
    required: true,
    default: () => new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
  }
}, {
  timestamps: true
});

AdCreditPurchaseIntentSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
AdCreditPurchaseIntentSchema.index({ userId: 1, createdAt: -1 });

export default mongoose.models.AdCreditPurchaseIntent
  || mongoose.model('AdCreditPurchaseIntent', AdCreditPurchaseIntentSchema);
