import cron from 'node-cron';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import apiRateLimiter from '../services/rateLimiting/apiRateLimiter.js';

/**
 * Auto-Resume Cron
 * 
 * Runs daily at 00:00 UTC to:
 * 1. Reset API rate limiter counters (Gemini + Groq daily quotas)
 * 2. Find videos stuck in 'pending' state (quota exhausted)
 * 3. Re-enqueue them for processing
 * 
 * This ensures videos that failed due to Gemini daily quota exhaustion
 * are automatically retried when quotas reset at midnight UTC.
 */
class AutoResumeCron {
  constructor() {
    this.task = null;
    this.isRunning = false;
  }

  start() {
    if (this.task) {
      console.log('ℹ️ AutoResumeCron: Already started');
      return;
    }

    // Run at 00:00 UTC daily
    this.task = cron.schedule('0 0 * * *', async () => {
      if (this.isRunning) {
        console.log('⏳ AutoResumeCron: Previous run still in progress, skipping');
        return;
      }

      this.isRunning = true;
      console.log('🔄 AutoResumeCron: Starting daily reset and retry...');

      try {
        await this._resetRateLimiters();
        await this._retryPendingVideos();
        console.log('✅ AutoResumeCron: Daily reset complete');
      } catch (error) {
        console.error('❌ AutoResumeCron: Failed:', error);
      } finally {
        this.isRunning = false;
      }
    }, {
      timezone: 'UTC'
    });

    console.log('📅 AutoResumeCron: Scheduled daily at 00:00 UTC');
  }

  stop() {
    if (this.task) {
      this.task.stop();
      this.task = null;
      console.log('🛑 AutoResumeCron: Stopped');
    }
  }

  /**
   * Reset all rate limiter daily counters
   */
  async _resetRateLimiters() {
    apiRateLimiter.reset();
    console.log('🔄 AutoResumeCron: Rate limiter counters reset');

    // Log current stats
    const stats = apiRateLimiter.getStats();
    for (const [provider, data] of Object.entries(stats)) {
      console.log(`   ${provider}: ${data.dailyCount}/${data.dailyLimit} used today`);
    }
  }

  /**
   * Find videos with embeddingVersion='pending' and re-enqueue them
   */
  async _retryPendingVideos() {
    try {
      // Find videos that were marked pending (quota exhausted)
      const pendingVideos = await Video.find({
        embeddingVersion: 'pending',
        processingStatus: { $ne: 'failed' }
      }).select('_id videoName').limit(100).lean();

      if (pendingVideos.length === 0) {
        console.log('ℹ️ AutoResumeCron: No pending videos to retry');
        return;
      }

      console.log(`🔄 AutoResumeCron: Found ${pendingVideos.length} pending videos, re-enqueuing...`);

      // Dynamically import queueService to avoid circular deps
      const { default: queueService } = await import('../services/yugFeedServices/queueService.js');

      let requeued = 0;
      let failed = 0;

      for (const video of pendingVideos) {
        try {
          // Re-enqueue as a lightweight AI-only job (skip re-downloading)
          await queueService.addVideoJob({
            videoId: video._id,
            rawVideoKey: null, // No re-download needed
            videoName: video.videoName,
            userId: null,
            retryOnly: true // Flag for worker to skip download/HLS steps
          });
          requeued++;
        } catch (error) {
          console.warn(`⚠️ AutoResumeCron: Failed to re-enqueue ${video._id}: ${error.message}`);
          failed++;
        }
      }

      console.log(`✅ AutoResumeCron: Re-enqueued ${requeued} videos (${failed} failed)`);
    } catch (error) {
      console.error('❌ AutoResumeCron: Failed to retry pending videos:', error);
    }
  }

  /**
   * Get stats for admin dashboard
   */
  async getStats() {
    try {
      const pendingCount = await Video.countDocuments({ embeddingVersion: 'pending' });
      const rateLimitStats = apiRateLimiter.getStats();

      return {
        pendingVideos: pendingCount,
        rateLimits: rateLimitStats,
        lastRun: this._lastRun || null
      };
    } catch (error) {
      return { error: error.message };
    }
  }
}

export default new AutoResumeCron();
