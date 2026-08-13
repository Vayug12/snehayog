import mongoose from 'mongoose';

const anonymousDeviceSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true,
    index: true,
    trim: true
  },
  attribution: {
    source: {
      type: String,
      trim: true,
      lowercase: true,
      maxlength: 120
    },
    medium: {
      type: String,
      trim: true,
      lowercase: true,
      maxlength: 120
    },
    campaign: {
      type: String,
      trim: true,
      lowercase: true,
      maxlength: 120
    },
    content: {
      type: String,
      trim: true,
      lowercase: true,
      maxlength: 120
    },
    term: {
      type: String,
      trim: true,
      lowercase: true,
      maxlength: 120
    },
    rawReferrer: {
      type: String,
      trim: true,
      maxlength: 1000
    }
  },
  mergedToUser: {
    type: String,
    default: null,
    trim: true
  },
  appVersion: {
    type: String,
    default: 'unknown'
  },
  firstSeenAt: {
    type: Date,
    default: Date.now
  },
  lastSeenAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

anonymousDeviceSchema.index({ createdAt: -1 });
anonymousDeviceSchema.index({ mergedToUser: 1 });

const AnonymousDevice = mongoose.model('AnonymousDevice', anonymousDeviceSchema);

export default AnonymousDevice;
