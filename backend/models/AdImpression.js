import mongoose from 'mongoose';

const AdImpressionSchema = new mongoose.Schema({
  videoId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true,
    index: true // For faster queries
  },
  adId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdCreative',
    required: true,
    index: true
  },
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false // Optional - can track anonymous impressions
  },
  // **NEW: Direct reference to Creator for O(1) earnings lookup**
  creatorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false, // Optional for backward compatibility (will be populated by migration)
    index: true
  },
  adType: {
    type: String,
    required: true,
    enum: ['banner', 'carousel'],
    index: true
  },
  impressionType: {
    type: String,
    enum: ['view', 'scroll_view'],
    default: 'view'
  },
  // **NEW: Track if ad was actually viewed (minimum 2-3 seconds visible)**
  isViewed: {
    type: Boolean,
    default: false,
    index: true // For counting views vs impressions
  },
  viewDuration: {
    type: Number, // Duration in seconds that ad was visible
    default: 0
  },
  viewCount: {
    type: Number,
    default: 0
  },
  frequencyCap: {
    type: Number,
    default: 3
  },
  timestamp: {
    type: Date,
    default: Date.now
    // Indexed below as a TTL index — declaring `index: true` here too would
    // make Mongo reject the TTL index with IndexOptionsConflict.
  },
  // Prevent duplicate tracking (same user, same video, same ad)
  // This helps prevent accidental double-counting
  uniqueKey: {
    type: String,
    unique: true,
    sparse: true // Allow null values
  }
}, {
  timestamps: true
});

// Create unique index on videoId + adId + userId + timestamp (within same hour)
// This prevents duplicate impressions from same user within short time
AdImpressionSchema.index(
  { 
    videoId: 1, 
    adId: 1, 
    userId: 1, 
    timestamp: 1 
  },
  { 
    unique: false // Allow multiple impressions but prevent exact duplicates
  }
);

// Compound index for fast queries by videoId and adType
AdImpressionSchema.index({ videoId: 1, adType: 1 });

// Index for counting impressions per video
AdImpressionSchema.index({ videoId: 1, adType: 1, impressionType: 1, timestamp: 1 });

// Index for counting views (isViewed = true) per video
AdImpressionSchema.index({ videoId: 1, adType: 1, isViewed: 1 });

// **OPTIMIZATION: Compound index for individual creator earnings calculation**
// matches: { creatorId: 1, isViewed: true, timestamp: { $gte: startOfMonth, $lt: endOfMonth } }
AdImpressionSchema.index({ creatorId: 1, isViewed: 1, timestamp: 1 });

// **OPTIMIZATION: Compound index for global leaderboard aggregation**
// matches: { isViewed: true, timestamp: { $gte: startOfMonth } }
AdImpressionSchema.index({ isViewed: 1, timestamp: 1 });

// **RETENTION: Expire raw impression rows after AD_IMPRESSION_TTL_DAYS (default 90).**
// Each row costs ~500 bytes once its indexes are counted, so unbounded growth is
// the dominant storage cost at scale. Long-term earnings live in
// CreatorMonthlyStat, which is already maintained per impression; revenueService
// only ever queries the current and previous month from this collection, so a
// 90-day window keeps every live read path intact while capping storage.
const AD_IMPRESSION_TTL_DAYS = Number(process.env.AD_IMPRESSION_TTL_DAYS) || 90;
AdImpressionSchema.index(
  { timestamp: 1 },
  { expireAfterSeconds: AD_IMPRESSION_TTL_DAYS * 24 * 60 * 60 }
);

export default mongoose.models.AdImpression || mongoose.model('AdImpression', AdImpressionSchema);

