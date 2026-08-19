import mongoose from 'mongoose';

const FollowerSchema = new mongoose.Schema({
  follower: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  following: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  }
}, {
  timestamps: true
});

// Unique index to prevent duplicate follows
FollowerSchema.index({ follower: 1, following: 1 }, { unique: true });

// Newest-first subscriber listing + "new since last seen" counting for a creator
FollowerSchema.index({ following: 1, createdAt: -1 });

export default mongoose.models.Follower || mongoose.model('Follower', FollowerSchema);
