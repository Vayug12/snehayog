import '../config/config.js';
import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import Notice from '../models/Notice.js';
import queueService from '../services/yugFeedServices/queueService.js';
import { redisOptions } from '../services/yugFeedServices/queueService.js'; 
import recommendationService from '../services/yugFeedServices/recommendationService.js';
import redisService from '../services/caching/redisService.js';
import { sendNotificationToUser } from '../services/notificationServices/notificationService.js';
import { beat, msSinceBeat } from '../utils/progressHeartbeat.js';
import { markVideoUploadFailed } from '../services/uploadServices/videoUploadLifecycleService.js';

// Connect to MongoDB & Redis only if not already connected (reuses API server connections when in-process)
const initializeWorkerConnections = async () => {
  try {
    if (mongoose.connection.readyState !== 1) {
      await mongoose.connect(process.env.MONGO_URI);
      console.log('📦 Worker MongoDB Connected');
    } else {
      console.log('📦 Worker: Reusing existing MongoDB connection');
    }
    
    if (!redisService.getConnectionStatus || !redisService.getConnectionStatus()) {
      await redisService.connect();
      console.log('📦 Worker Redis Connected');
    } else {
      console.log('📦 Worker: Reusing existing Redis connection');
    }
  } catch (error) {
    console.error('❌ Worker Connection Error:', error);
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
      await markVideoUploadFailed(videoId, error);

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


// In-flight job count, owned by the processor rather than by the 'active' /
// 'completed' / 'failed' listeners.
//
// Those three have to stay perfectly balanced for the count to mean anything,
// and they did not: it drifted up to 3 and never came back down, so the idle
// shutdown below — which only exits at 0 — never fired and the worker VM billed
// around the clock for days. Incrementing on entry and decrementing in a finally
// cannot drift, however a job ends.
let activeJobsCount = 0;
let shutdownTimeout = null;

// **OPTIMIZED: Multi-Job Type Dispatcher**
const videoWorker = new Worker('video-processing', async (job) => {
  activeJobsCount++;
  beat();

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

      default:
        console.warn(`⚠️ Worker: Unknown job type ${job.name}`);
        return { status: 'ignored' };
    }
  } catch (error) {
    console.error(`❌ Worker Job ${job.id} failed:`, error);
    throw error;
  } finally {
    activeJobsCount = Math.max(0, activeJobsCount - 1);
    beat();
  }
}, {
  connection: redisOptions,
  concurrency: 1 // CRITICAL: Only 1 job at a time on the 2GB Fly.io worker machine
});

videoWorker.on('active', (job) => {
  if (shutdownTimeout) {
    console.log('🚀 Worker: New job active. Cancelling idle shutdown timer.');
    clearTimeout(shutdownTimeout);
    shutdownTimeout = null;
  }

  // job.timestamp = when the job was enqueued. A large gap here means the video
  // was not being processed at all, it was waiting for a free/awake worker.
  const waitSec = (Date.now() - job.timestamp) / 1000;
  console.log(`🚀 Worker: Started job ${job.id} (${job.name}) | Queue wait: ${waitSec.toFixed(1)}s | attempt ${job.attemptsMade + 1}/${job.opts.attempts ?? 1}`);
});

videoWorker.on('completed', (job) => {
  const finishedOn = job.finishedOn ?? Date.now();
  const processSec = (finishedOn - (job.processedOn ?? job.timestamp)) / 1000;
  const queueSec = ((job.processedOn ?? finishedOn) - job.timestamp) / 1000;
  const totalSec = (finishedOn - job.timestamp) / 1000;
  console.log(
    `✅ Job ${job.id} completed | Queue wait: ${queueSec.toFixed(1)}s | Processing: ${processSec.toFixed(1)}s | Total: ${totalSec.toFixed(1)}s`
  );
});

videoWorker.on('failed', async (job, err) => {
  // BullMQ emits this with no job for failures it cannot attribute to one.
  // Reading job.id unguarded threw here, which killed the rest of the handler.
  if (!job) {
    console.log(`❌ Worker failure with no associated job: ${err?.message}`);
    return;
  }

  console.log(`❌ Job ${job.id} failed: ${err.message}`);

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

// Cost control: stop paying for the worker VM once there is nothing to encode.
//
// Guarded on FLY_PROCESS_GROUP === 'worker', NOT on FLY_APP_NAME: that variable is
// also set on the app machine, so if DISABLE_INTEGRATED_WORKER is ever flipped back
// to "false" the exit below would kill the API instead of a worker. Fly sets
// FLY_PROCESS_GROUP per process group, so only the dedicated worker VM can exit here.
const IDLE_SHUTDOWN_MS = parseInt(process.env.WORKER_IDLE_SHUTDOWN_MS, 10) || 120000;
const isDedicatedWorkerMachine = process.env.FLY_PROCESS_GROUP === 'worker';

if (isDedicatedWorkerMachine && process.env.DISABLE_AUTO_SHUTDOWN !== 'true') {
  videoWorker.on('drained', () => {
    console.log(`🧹 Worker: Queue drained. Scheduling idle shutdown in ${(IDLE_SHUTDOWN_MS / 1000).toFixed(0)}s...`);

    if (shutdownTimeout) clearTimeout(shutdownTimeout);

    shutdownTimeout = setTimeout(() => {
      if (activeJobsCount === 0) {
        console.log('😴 Worker: Idle with 0 active jobs. Exiting to stop this VM and save cost.');
        process.exit(0); // Exiting signals Fly.io to stop this Machine.
      } else {
        console.log(`ℹ️ Worker: Shutdown cancelled. Active jobs: ${activeJobsCount}`);
      }
    }, IDLE_SHUTDOWN_MS);
  });
} else {
  console.log(`ℹ️ Worker: Idle auto-shutdown disabled (process group: ${process.env.FLY_PROCESS_GROUP || 'local'}).`);
}

// Upar wale 'drained' shutdown ke neeche ek independent floor.
//
// Wo path poori tarah BullMQ events par tika hai, aur us par akela bharosa nahi
// kiya ja sakta: 'active' shutdown timer clear kar deta hai, aur agar job hang ho
// jaaye (FFmpeg stall, R2 download atka) to 'drained' dobara kabhi fire nahi hota
// — timer phir kabhi set hi nahi hota aur 2GB ki VM chalti rehti hai. 7 Aug 2026
// ko exactly yahi hua: ek job 3h05m latka raha, jo us hafte ke poore worker bill
// ka ~83% tha.
//
// Ye watchdog events nahi, PROGRESS dekhta hai. Dheema encode bhi ~1 tick/second
// deta hai, isliye ghanton lamba genuine job isse kabhi nahi marta — sirf wahi
// marta hai jahan clock chal raha ho par kaam aage na badh raha ho.
//
// Poll 5 min ka hai aur threshold 15 min, to hang 15-20 min ke beech pakda jaata
// hai. Ye jaan-boojh kar dheela rakha gaya hai: DownloadSource jaisa silent step
// bade file par kuch minute le sakta hai, aur false-kill hang se zyada mehnga hai.
const STALL_MS = parseInt(process.env.WORKER_STALL_MS, 10) || 15 * 60 * 1000;
const WATCHDOG_INTERVAL_MS = 5 * 60 * 1000;

if (isDedicatedWorkerMachine && process.env.DISABLE_AUTO_SHUTDOWN !== 'true') {
  const watchdog = setInterval(() => {
    const stalledMs = msSinceBeat();
    if (stalledMs < STALL_MS) return;

    console.error(
      `🛑 Worker: ${(stalledMs / 60000).toFixed(1)} min se zero progress ` +
      `(activeJobs=${activeJobsCount}). Hang maan kar VM band ki ja rahi hai. ` +
      `Job ka lock expire hone par BullMQ use stalled maanega aur ek baar retry karega.`
    );
    process.exit(0);
  }, WATCHDOG_INTERVAL_MS);

  // Watchdog khud event loop ko zinda na rakhe — warna ye khud hi wahi cheez ban
  // jaata hai jise rokne ke liye banaya gaya hai.
  watchdog.unref();

  console.log(`🐕 Worker: Stall watchdog on — ${(STALL_MS / 60000).toFixed(0)} min bina progress ke exit.`);
}

console.log('👷 Video Worker Started and Listening for jobs...');
