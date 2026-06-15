import mongoose from 'mongoose';

/**
 * EncryptedVideoKey Model
 * 
 * Stores the encrypted symmetric video key for each subscriber.
 * The symmetric key is encrypted with the subscriber's public key (ECIES).
 * Only the subscriber's private key (stored on their device) can decrypt it.
 * 
 * Vayug servers NEVER have access to the raw symmetric key.
 */
const EncryptedVideoKeySchema = new mongoose.Schema({
  videoId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true,
    index: true
  },
  subscriberId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  // The symmetric video key, encrypted with the subscriber's public key.
  // Base64 encoded string.
  encryptedSymmetricKey: {
    type: String,
    required: true
  }
}, {
  timestamps: true
});

// Compound index for fast lookup: "Get key for this video for this subscriber"
EncryptedVideoKeySchema.index({ videoId: 1, subscriberId: 1 }, { unique: true });

export default mongoose.models.EncryptedVideoKey || mongoose.model('EncryptedVideoKey', EncryptedVideoKeySchema);
