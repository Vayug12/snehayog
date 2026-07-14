import mongoose from 'mongoose';

const PhoneOtpChallengeSchema = new mongoose.Schema({
  phoneNumber: {
    type: String,
    required: true,
    index: true
  },
  otpHash: {
    type: String,
    required: true
  },
  attempts: {
    type: Number,
    default: 0
  },
  consumedAt: {
    type: Date,
    default: null,
    index: true
  },
  provider: {
    type: String,
    enum: ['2factor', 'mock'],
    required: true
  },
  providerReference: String,
  expiresAt: {
    type: Date,
    required: true,
    index: { expires: 0 }
  }
}, {
  timestamps: true
});

PhoneOtpChallengeSchema.index({ phoneNumber: 1, createdAt: -1 });

export default mongoose.models.PhoneOtpChallenge ||
  mongoose.model('PhoneOtpChallenge', PhoneOtpChallengeSchema);
