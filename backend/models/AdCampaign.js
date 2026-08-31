import mongoose from 'mongoose';

const AdCampaignSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true
  },
  advertiserUserId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  objective: {
    type: String,
    required: true,
    enum: ['awareness', 'consideration', 'conversion']
  },
  status: {
    type: String,
    required: true,
    enum: ['draft', 'pending_review', 'active', 'paused', 'completed'],
    default: 'draft'
  },
  startDate: {
    type: Date,
    required: true
  },
  endDate: {
    type: Date,
    required: true
  },
  dailyBudget: {
    type: Number,
    required: true,
    min: 1
  },
  totalBudget: {
    type: Number,
    min: 30
  },
  // Stable per advertiser. It lets a client safely retry after a timeout
  // without paying for or creating the same campaign twice.
  idempotencyKey: {
    type: String,
    trim: true,
    maxlength: 128
  },
  // Running total of what this campaign has been charged for delivered views.
  // Accrued in batches by adStatsBuffer at the same CPM used to credit
  // creators, so advertiser spend and creator revenue never drift apart.
  // A campaign stops being served once spentINR reaches totalBudget.
  spentINR: {
    type: Number,
    default: 0,
    min: 0
  },
  // Set when the campaign's unspent budget has been returned to the
  // advertiser's credit wallet. Doubles as the claim flag for settlement:
  // the transition to a settled state filters on this being null, so a
  // re-run of the expiry sweep cannot refund the same campaign twice.
  budgetRefundedAt: {
    type: Date,
    default: null
  },
  bidType: {
    type: String,
    default: 'CPM',
    enum: ['CPM', 'CPC']
  },
  cpmINR: {
    type: Number,
    default: 30,
    min: 10,
    max: 1000
  },
  target: {
    age: {
      min: { type: Number, min: 13, max: 65 },
      max: { type: Number, min: 13, max: 65 }
    },
    gender: {
      type: String,
      enum: ['all', 'male', 'female', 'other']
    },
    locations: [{
      type: String,
      trim: true
    }],
    interests: [{
      type: String,
      trim: true
    }],
    platforms: [{
      type: String,
      enum: ['android', 'ios', 'web']
    }],

    deviceType: {
      type: String,
      enum: ['mobile', 'tablet', 'desktop', 'all'],
      default: 'all'
    }
  },

  optimizationGoal: {
    type: String,
    enum: ['clicks', 'impressions', 'conversions'],
    default: 'impressions'
  },
  timeZone: {
    type: String,
    default: 'Asia/Kolkata'
  },
  dayParting: {
    type: Map,
    of: Boolean,
    default: {}
  },
  hourParting: {
    type: Map,
    of: String,
    default: {}
  },
  pacing: {
    type: String,
    default: 'smooth',
    enum: ['smooth', 'asap']
  },
  frequencyCap: {
    type: Number,
    default: 3,
    min: 1,
    max: 10
  },
  // **ENHANCED: Performance tracking fields**
  impressions: {
    type: Number,
    default: 0
  },
  clicks: {
    type: Number,
    default: 0
  },
  spend: {
    type: Number,
    default: 0
  },
  ctr: {
    type: Number,
    default: 0
  },
  cpm: {
    type: Number,
    default: 0
  },
  // **NEW: Additional performance metrics**
  conversions: {
    type: Number,
    default: 0
  },
  conversionRate: {
    type: Number,
    default: 0
  },
  costPerConversion: {
    type: Number,
    default: 0
  },
  reach: {
    type: Number,
    default: 0
  },
  frequency: {
    type: Number,
    default: 0
  },
  engagementRate: {
    type: Number,
    default: 0
  },
  roas: { // Return on Ad Spend
    type: Number,
    default: 0
  }
}, {
  timestamps: true
});

// Serves the expiry sweep, which runs on every cold start. Without this it
// would collection-scan on each boot; with it, the normal "nothing to settle"
// case is an index lookup that matches no documents.
AdCampaignSchema.index({ status: 1, endDate: 1, budgetRefundedAt: 1 });
AdCampaignSchema.index(
  { advertiserUserId: 1, idempotencyKey: 1 },
  {
    unique: true,
    partialFilterExpression: { idempotencyKey: { $type: 'string' } }
  }
);

// Calculate CTR
AdCampaignSchema.virtual('calculatedCtr').get(function() {
  if (this.impressions === 0) return 0;
  return (this.clicks / this.impressions) * 100;
});

// Calculate CPM
AdCampaignSchema.virtual('calculatedCpm').get(function() {
  if (this.impressions === 0) return 0;
  return (this.spend / this.impressions) * 1000;
});

// Pre-save middleware to update calculated fields
AdCampaignSchema.pre('save', function(next) {
  this.ctr = this.calculatedCtr;
  this.cpm = this.calculatedCpm;
  next();
});

export default mongoose.models.AdCampaign || mongoose.model('AdCampaign', AdCampaignSchema);
