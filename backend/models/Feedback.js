import mongoose from 'mongoose';

const feedbackSchema = new mongoose.Schema({
  rating: {
    type: Number,
    required: function() { return this.type !== 'suggestion'; },
    min: 1,
    max: 5
  },
  comments: {
    type: String,
    maxlength: 2000,
    trim: true
  },
  type: {
    type: String,
    enum: ['general', 'bug', 'feature', 'performance', 'ui', 'suggestion', 'other'],
    default: 'general'
  },
  videoId: {
    type: String,
    trim: true
  },
  userEmail: {
    type: String,
    required: true,
    trim: true,
    lowercase: true
  },
  userId: {
    type: String,
    trim: true
  },
  isRead: {
    type: Boolean,
    default: false
  },
  readAt: {
    type: Date
  },
  isReplied: {
    type: Boolean,
    default: false
  },
  adminReply: {
    type: String,
    maxlength: 1000,
    trim: true
  },
  repliedAt: {
    type: Date
  },
  // Additional metadata
  userAgent: {
    type: String,
    trim: true
  },
  ipAddress: {
    type: String,
    trim: true
  },
  attribution: {
    source: {
      type: String,
      trim: true,
      lowercase: true
    },
    medium: {
      type: String,
      trim: true,
      lowercase: true
    },
    campaign: {
      type: String,
      trim: true,
      lowercase: true
    },
    content: {
      type: String,
      trim: true,
      lowercase: true
    },
    term: {
      type: String,
      trim: true,
      lowercase: true
    },
    rawReferrer: {
      type: String,
      trim: true,
      maxlength: 1000
    }
  }
}, {
  timestamps: true
});

// Index for better query performance
feedbackSchema.index({ createdAt: -1 });
feedbackSchema.index({ rating: 1 });
feedbackSchema.index({ isRead: 1 });
feedbackSchema.index({ isReplied: 1 });
feedbackSchema.index({ userEmail: 1 });
feedbackSchema.index({ 'attribution.source': 1 });

// Virtual for formatted date
feedbackSchema.virtual('formattedDate').get(function() {
  return this.createdAt.toLocaleDateString();
});

// Method to mark as read
feedbackSchema.methods.markAsRead = function() {
  this.isRead = true;
  this.readAt = new Date();
  return this.save();
};

// Method to add admin reply
feedbackSchema.methods.addReply = function(reply) {
  this.adminReply = reply;
  this.isReplied = true;
  this.repliedAt = new Date();
  return this.save();
};

// Static method to get feedback statistics
feedbackSchema.statics.getStats = async function() {
  const total = await this.countDocuments();
  const unread = await this.countDocuments({ isRead: false });
  const unreadFeedback = await this.countDocuments({ isRead: false, type: { $ne: 'suggestion' } });
  const unreadSuggestions = await this.countDocuments({ isRead: false, type: 'suggestion' });
  const replied = await this.countDocuments({ isReplied: true });
  
  const avgRatingResult = await this.aggregate([
    { $match: { type: { $ne: 'suggestion' } } },
    { $group: { _id: null, avgRating: { $avg: '$rating' } } }
  ]);
  const avgRating = avgRatingResult.length > 0 ? avgRatingResult[0].avgRating : 0;

  const ratingDistribution = await this.aggregate([
    { $match: { type: { $ne: 'suggestion' } } },
    { $group: { _id: '$rating', count: { $sum: 1 } } },
    { $sort: { _id: -1 } }
  ]);

  return {
    total,
    unread,
    unreadFeedback,
    unreadSuggestions,
    replied,
    avgRating: Math.round(avgRating * 10) / 10,
    ratingDistribution
  };
};

const Feedback = mongoose.model('Feedback', feedbackSchema);

export default Feedback;
