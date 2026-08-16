import mongoose from 'mongoose';

const dailyUploadQuotaSchema = new mongoose.Schema({
  _id: {
    type: String,
    required: true,
  },
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true,
  },
  dayKey: {
    type: String,
    required: true,
  },
  uploadIds: {
    type: [String],
    default: [],
  },
  expiresAt: {
    type: Date,
    required: true,
  },
}, {
  timestamps: true,
});

dailyUploadQuotaSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export default mongoose.models.DailyUploadQuota
  || mongoose.model('DailyUploadQuota', dailyUploadQuotaSchema);
