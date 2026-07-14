import mongoose from 'mongoose';

/**
 * Tracks AI video generation jobs initiated by users.
 * The actual video generation happens in the VayugAI FastAPI agent.
 */
const VideoGenJobSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  prompt: {
    type: String,
    required: true,
    maxlength: 1000,
    trim: true
  },
  category: {
    type: String,
    trim: true,
    default: null
  },
  audience: {
    type: String,
    trim: true,
    default: null
  },
  /**
   * Status flow:
   *   pending → processing → completed
   *                        ↘ failed
   */
  status: {
    type: String,
    enum: ['pending', 'processing', 'completed', 'failed'],
    default: 'pending',
    index: true
  },
  // The video document ID once published to Vayug
  videoId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    default: null
  },
  // HLS/streaming URL of the published video (used for feed playback)
  videoUrl: {
    type: String,
    default: null
  },
  // Direct MP4 URL used for saving the video to the device gallery
  downloadUrl: {
    type: String,
    default: null
  },
  // R2 object key for the downloadable MP4, so it can be deleted after download
  downloadKey: {
    type: String,
    default: null
  },
  // Error message if generation failed
  errorMessage: {
    type: String,
    default: null
  },
  // Raw response from agent (title, tags, etc.)
  agentMetadata: {
    type: mongoose.Schema.Types.Mixed,
    default: null
  }
}, {
  timestamps: true  // createdAt, updatedAt auto-added
});

// Auto-expire jobs after 24 hours (TTL index)
VideoGenJobSchema.index({ createdAt: 1 }, { expireAfterSeconds: 86400 });

export default mongoose.model('VideoGenJob', VideoGenJobSchema);
