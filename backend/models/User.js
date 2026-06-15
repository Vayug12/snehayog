import mongoose from 'mongoose';

const UserSchema = new mongoose.Schema({
  googleId: {
    type: String,
    required: true,
    unique: true
  },
  // **NEW: Ed25519 Public Key for E2EE**
  publicKey: {
    type: String,
    default: null
  },
  name: {
    type: String,
    required: true
  },
  email: {
    type: String,
    required: true,
    unique: true
  },
  profilePic: {
    type: String
  },
  websiteUrl: {
    type: String,
    trim: true
  },
  videos: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video'
  }],
  // **NEW: Performance Counters for relationships**
  followingCount: {
    type: Number,
    default: 0
  },
  followerCount: {
    type: Number,
    default: 0
  },
  savedVideosCount: {
    type: Number,
    default: 0
  },
  preferredCurrency: {
    type: String,
    enum: ['INR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD'],
    default: 'INR'
  },
  preferredPaymentMethod: {
    type: String,
    enum: [
      'upi', 'card_payment',
      'paypal', 'stripe', 'wise', 'payoneer'
    ]
  },
  paymentDetails: {
    // UPI
    upiId: String,
    // **NEW: Card Payment Details**
    cardDetails: {
      cardNumber: String,
      expiryDate: String,
      cvv: String,
      cardholderName: String
    },
    // International
    paypalEmail: String,
    stripeAccountId: String,
    wiseEmail: String
  },
  country: {
    type: String,
    default: 'IN'
  },
  // **NEW: Tax Information**
  taxInfo: {
    panNumber: String,    // For Indians
    gstNumber: String,    // For Indians
    w8benSubmitted: Boolean, // For non-US
    w9Submitted: Boolean,    // For US
    taxResidency: String
  },
  // **NEW: Track payout count**
  payoutCount: {
    type: Number,
    default: 0
  },
  // **NEW: Device IDs - Store device IDs that have logged in with this account**
  // This allows skipping login screen after app reinstall
  deviceIds: [{
    type: String,
    trim: true,
    index: true
  }],
  // **NEW: FCM Token for push notifications**
  fcmToken: {
    type: String,
    default: null
  },
  // **NEW: Google OAuth Offline Refresh Token for Tier 4 auto-login recovery**
  googleRefreshToken: {
    type: String,
    default: null
  },
  // **NEW: Track last active time for identifying inactive users**
  lastActive: {
    type: Date,
    default: Date.now,
    index: true
  },
  isAppUninstalled: {
    type: Boolean,
    default: false
  },
  lastInstallCheck: {
    type: Date
  },
  // **NEW: Location Data**
  location: {
    latitude: {
      type: Number,
      required: false
    },
    longitude: {
      type: Number,
      required: false
    },
    address: {
      type: String,
      required: false
    },
    city: {
      type: String,
      required: false
    },
    state: {
      type: String,
      required: false
    },
    country: {
      type: String,
      required: false
    },
    lastUpdated: {
      type: Date,
      default: Date.now
    },
    permissionGranted: {
      type: Boolean,
      default: false
    }
  },
  preferredLanguages: [{
    type: String,
    trim: true,
    lowercase: true,
    default: ['english', 'hindi', 'hinglish']
  }],
  
  // **NEW: Social Media Accounts for Cross-Posting**
  // Stores OAuth tokens and basic profile info for linked accounts
  socialAccounts: {
    youtube: {
      connected: { type: Boolean, default: false },
      accessToken: String,
      refreshToken: String,
      expiryDate: Number,
      channelId: String,
      channelTitle: String
    },
    instagram: {
      connected: { type: Boolean, default: false },
      accessToken: String,
      instagramUserId: String,
      userName: String
    },
    facebook: {
      connected: { type: Boolean, default: false },
      accessToken: String,
      pageId: String,
      pageName: String
    },
    linkedin: {
      connected: { type: Boolean, default: false },
      accessToken: String,
      urn: String,
      name: String
    }
  },
  appVersion: {
    type: String,
    trim: true,
    default: 'unknown'
  },
  // **NEW: Creator Alert Preferences**
  notificationPreferences: {
    globalCreatorAlerts: { 
      type: Boolean, 
      default: true 
    },
    disabledCreators: [{ 
      type: mongoose.Schema.Types.ObjectId, 
      ref: 'User' 
    }]
  }
}, {
  timestamps: true
});

// Add method to get user's videos
UserSchema.methods.getVideos = async function() {
  await this.populate({
    path: 'videos',
    populate: { path: 'uploader', select: 'name profilePic' }
  });
  return this.videos;
};

// **REFACTORED: Follow/Unfollow Methods (Now use Follower collection)**
UserSchema.methods.isFollowing = async function(userId) {
  const Follower = mongoose.model('Follower');
  const follow = await Follower.findOne({ follower: this._id, following: userId }).lean();
  return !!follow;
};

UserSchema.methods.follow = async function(targetUserId) {
  const Follower = mongoose.model('Follower');
  try {
    const follow = new Follower({ follower: this._id, following: targetUserId });
    await follow.save();
    
    // Increment counters atomically
    await Promise.all([
      this.constructor.updateOne({ _id: this._id }, { $inc: { followingCount: 1 } }),
      this.constructor.updateOne({ _id: targetUserId }, { $inc: { followerCount: 1 } })
    ]);
    return true;
  } catch (err) {
    if (err.code === 11000) return false; // Already following
    throw err;
  }
};

UserSchema.methods.unfollow = async function(targetUserId) {
  const Follower = mongoose.model('Follower');
  const result = await Follower.deleteOne({ follower: this._id, following: targetUserId });
  
  if (result.deletedCount > 0) {
    // Decrement counters atomically
    await Promise.all([
      this.constructor.updateOne({ _id: this._id }, { $inc: { followingCount: -1 } }),
      this.constructor.updateOne({ _id: targetUserId }, { $inc: { followerCount: -1 } })
    ]);
    return true;
  }
  return false;
};

// **REFACTORED: Saved Video Methods (Now use SavedVideo collection)**
UserSchema.methods.isSaved = async function(videoId) {
  const SavedVideo = mongoose.model('SavedVideo');
  const save = await SavedVideo.findOne({ user: this._id, video: videoId }).lean();
  return !!save;
};

UserSchema.methods.saveVideo = async function(videoId) {
  const SavedVideo = mongoose.model('SavedVideo');
  try {
    const save = new SavedVideo({ user: this._id, video: videoId });
    await save.save();
    
    await this.constructor.updateOne({ _id: this._id }, { $inc: { savedVideosCount: 1 } });
    return true;
  } catch (err) {
    if (err.code === 11000) return false; // Already saved
    throw err;
  }
};

UserSchema.methods.unsaveVideo = async function(videoId) {
  const SavedVideo = mongoose.model('SavedVideo');
  const result = await SavedVideo.deleteOne({ user: this._id, video: videoId });
  
  if (result.deletedCount > 0) {
    await this.constructor.updateOne({ _id: this._id }, { $inc: { savedVideosCount: -1 } });
    return true;
  }
  return false;
};

export default mongoose.models.User || mongoose.model('User', UserSchema);

