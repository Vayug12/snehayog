import '../config/env.js';
import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import Notice from '../models/Notice.js';
import queueService from '../services/yugFeedServices/queueService.js';
import { redisOptions } from '../services/yugFeedServices/queueService.js'; 
import recommendationService from '../services/yugFeedServices/recommendationService.js';
import redisService from '../services/caching/redisService.js';
import geminiService from '../services/geminiService.js';
import { sendNotificationToUser } from '../services/notificationServices/notificationService.js';

// Connect to MongoDB & Redis (If not already connected)
const initializeWorkerConnections = async () => {
  try {
    if (mongoose.connection.readyState !== 1) {
      await mongoose.connect(process.env.MONGO_URI);
      console.log('📦 Worker MongoDB Connected');
    }
    
    // Connect to Redis for cache invalidation
    if (!redisService.getConnectionStatus || !redisService.getConnectionStatus()) {
      await redisService.connect();
      console.log('📦 Worker Redis Connected');
    }
  } catch (error) {
    console.error('❌ Worker Connection Error:', error);
    // Don't exit if it's integrated, just log
    if (!process.env.FLY_APP_NAME) process.exit(1);
  }
};

initializeWorkerConnections();

import videoPipeline from '../services/videoProcessing/index.js';

async function handleVideoProcessing(job) {
  const { videoId, rawVideoKey, videoName, userId, crossPostPlatforms, thumbnailKey } = job.data;
  
  try {
    const videoExists = await Video.findById(videoId);
    if (!videoExists) {
      console.warn(`⚠️ Worker: Video ${videoId} has been deleted before processing. Skipping.`);
      return { status: 'skipped', reason: 'video_deleted' };
    }

    console.log(`👷 Worker: Dispatching video ${videoId} to pipeline...`);
    
    // Initial status update
    await Video.findByIdAndUpdate(videoId, { 
      processingStatus: 'processing',
      processingProgress: 5 
    });

    const result = await videoPipeline.run({
      videoId,
      rawVideoKey,
      videoName,
      userId,
      thumbnailKey,
      crossPostPlatforms
    });

    // Final status update (already handled by pipeline steps, but ensures completion)
    await Video.findByIdAndUpdate(videoId, { 
      processingStatus: 'completed',
      processingProgress: 100 
    });

    // Send push notification & Notice
    try {
      await sendNotificationToUser(userId, {
        title: 'Video Processing Completed',
        body: `Your video "${videoName}" has been successfully processed!`,
        data: {
          type: 'video_processed',
          videoId: videoId,
          status: 'completed',
          videoName: videoName
        }
      });

      await Notice.create({
        userId: userId,
        title: `Video Processed: ${videoName}`,
        type: 'notice'
      });
      console.log(`✅ Worker: Sent success push notification and created DB Notice for user: ${userId}`);
    } catch (notifyErr) {
      console.error('⚠️ Worker: Failed to send success notification/notice:', notifyErr.message);
    }

    try {
      const user = await mongoose.model('User').findById(userId).select('googleId').lean();
      if (user && redisService.getConnectionStatus && redisService.getConnectionStatus()) {
        const { invalidateCache, VideoCacheKeys } = await import('../middleware/cacheMiddleware.js');
        const cacheKeysToInvalidate = [
          `user:feed:${user.googleId}:*`,
          `videos:user:${user.googleId}`,
          VideoCacheKeys.all()
        ];
        if (videoExists && !videoExists.isSubscriberOnly) {
           cacheKeysToInvalidate.push('videos:feed:*');
        }
        await invalidateCache(cacheKeysToInvalidate);
        console.log(`🧹 Worker: Invalidated cache for user ${user.googleId}`);
      }
    } catch (cacheErr) {
      console.error('⚠️ Worker: Failed to invalidate cache after success:', cacheErr.message);
    }

    return { status: 'completed', videoId, result };

  } catch (error) {
    console.error(`❌ Worker Error for ${videoId}:`, error);
    
    // Only attempt database updates if the video still exists
    const videoExists = await Video.findById(videoId);
    if (videoExists) {
      await Video.findByIdAndUpdate(videoId, { 
          processingStatus: 'failed',
          processingError: error.message 
      });

      // Send failure push notification & Notice
      try {
        await sendNotificationToUser(userId, {
          title: 'Video Processing Failed',
          body: `Failed to process your video "${videoName}".`,
          data: {
            type: 'video_processed',
            videoId: videoId,
            status: 'failed',
            videoName: videoName
          }
        });

        await Notice.create({
          userId: userId,
          title: `Video Processing Failed: ${videoName}`,
          type: 'warning'
        });
        console.log(`✅ Worker: Sent failure push notification and created DB Notice for user: ${userId}`);
      } catch (notifyErr) {
        console.error('⚠️ Worker: Failed to send failure notification/notice:', notifyErr.message);
      }

      try {
        const user = await mongoose.model('User').findById(userId).select('googleId').lean();
        if (user && redisService.getConnectionStatus && redisService.getConnectionStatus()) {
          const { invalidateCache, VideoCacheKeys } = await import('../middleware/cacheMiddleware.js');
          await invalidateCache([`videos:user:${user.googleId}`, VideoCacheKeys.all()]);
          console.log(`🧹 Worker: Invalidated cache for user ${user.googleId} after failure`);
        }
      } catch (cacheErr) {
        console.error('⚠️ Worker: Failed to invalidate cache after failure:', cacheErr.message);
      }
    } else {
      console.warn(`⚠️ Worker: Video ${videoId} was deleted during processing. Skipped failure updates.`);
    }

    throw error;
  }
}


/**
 * Handle AI Video Analysis asynchronously in the background
 */
async function handleVideoAnalysis(data) {
  const { videoId } = data;
  try {
    const video = await Video.findById(videoId);
    if (!video || !video.thumbnailUrl) {
      console.warn(`⚠️ handleVideoAnalysis: Video or thumbnail missing for ${videoId}`);
      return { status: 'skipped' };
    }

    if (!process.env.GEMINI_API_KEY) {
      console.warn('⚠️ handleVideoAnalysis: Skipping because GEMINI_API_KEY is not set');
      return { status: 'skipped' };
    }

    console.log(`🧠 Worker: Starting background Gemini analysis for ${videoId}...`);
    
    // We use the generated thumbnail as the primary input to save extraction latency
    const analysisInput = [video.thumbnailUrl];

    const metadata = await geminiService.getVideoContext(analysisInput, {
      title: video.videoName,
      category: video.category,
      description: video.description
    });
    
    if (metadata) {
      await Video.findByIdAndUpdate(videoId, { 
        aiSummary: metadata.summary,
        language: metadata.language,
        detectedRegion: metadata.region,
        tags: [...new Set([...(video.tags || []), ...(metadata.keywords || [])])],
        aiContextGenerated: true 
      });
      
      // Update recommendation score with new metadata
      await recommendationService.calculateAndUpdateVideoScore(videoId);
      console.log(`✅ Worker: Background metadata enriched for ${videoId}`);
    }
    return { status: 'completed', videoId };
  } catch (error) {
    console.error(`❌ Worker: Background analysis failed for ${videoId}:`, error);
    throw error;
  }
}

// **OPTIMIZED: Multi-Job Type Dispatcher**
const videoWorker = new Worker('video-processing', async (job) => {
  
  try {
    switch (job.name) {
      case 'process-video':
        return await handleVideoProcessing(job);
        
      case 'sync-counts':
        console.log('🔄 Worker: Syncing user counts...');
        return { status: 'done' };
        
      case 'cleanup-orphaned':
        console.log('🧹 Worker: Cleaning up orphaned R2 files...');
        return { status: 'done' };
        
      case 'recalculate-ranks':
        console.log('🏆 Worker: Recalculating global creator ranks...');
        await recommendationService._calculateAndCacheRanks();
        return { status: 'completed' };

      case 'analyze-video':
        return await handleVideoAnalysis(job.data);
        
      default:
        console.warn(`⚠️ Worker: Unknown job type ${job.name}`);
        return { status: 'ignored' };
    }
  } catch (error) {
    console.error(`❌ Worker Job ${job.id} failed:`, error);
    throw error;
  }
}, {
  connection: redisOptions,
  concurrency: 1 // CRITICAL: Only 1 job at a time on 1GB Fly.io machine
});

let activeJobsCount = 0;
let shutdownTimeout = null;

videoWorker.on('active', (job) => {
  activeJobsCount++;
  if (shutdownTimeout) {
    console.log('🚀 Worker: New job active. Cancelling idle shutdown timer.');
    clearTimeout(shutdownTimeout);
    shutdownTimeout = null;
  }
});

videoWorker.on('completed', (job) => {
  console.log(`✅ Job ${job.id} completed!`);
  activeJobsCount = Math.max(0, activeJobsCount - 1);
});

videoWorker.on('failed', async (job, err) => {
  console.log(`❌ Job ${job.id} failed: ${err.message}`);
  activeJobsCount = Math.max(0, activeJobsCount - 1);
  
  // Clean up R2 on permanent failure
  try {
    if (job.attemptsMade >= job.opts.attempts) {
      console.log(`🚨 Job ${job.id} failed permanently after ${job.attemptsMade} attempts. Cleaning up R2...`);
      const rawVideoKey = job.data?.rawVideoKey;
      if (rawVideoKey) {
        const { default: storageManager } = await import('../services/storageSystem/StorageManager.js');
        await storageManager.active.delete(rawVideoKey);
        console.log(`🧹 Worker: Cleaned up orphaned R2 file: ${rawVideoKey}`);
      }
    }
  } catch (cleanupError) {
    console.error(`❌ Worker: Failed to clean up R2 after permanent failure:`, cleanupError);
  }
});

// Cost optimization: Automatically shut down worker VM when idle
if (process.env.FLY_APP_NAME && process.env.DISABLE_AUTO_SHUTDOWN !== 'true') {
  videoWorker.on('drained', () => {
    console.log('🧹 Worker: Queue is drained. Scheduling idle shutdown in 2 minutes...');
    
    if (shutdownTimeout) clearTimeout(shutdownTimeout);
    
    shutdownTimeout = setTimeout(() => {
      if (activeJobsCount === 0) {
        console.log('😴 Worker: Machine is idle with 0 active jobs. Shutting down to save cost...');
        process.exit(0); // Exit command signals Fly.io to stop this VM
      } else {
        console.log(`ℹ️ Worker: Shutdown cancelled. Active: ${activeJobsCount}`);
      }
    }, 600000); // 10 minutes (600,000 ms) idle buffer
  });
}

console.log('👷 Video Worker Started and Listening for jobs...');
