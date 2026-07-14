import '../../config/env.js';
import { Queue } from 'bullmq';
import axios from 'axios';

// Initializing Redis connection options from URL or individual parts
export let redisOptions = {
  host: process.env.REDISHOST || process.env.REDIS_HOST || 'localhost',
  port: process.env.REDISPORT || process.env.REDIS_PORT || 6379,
  password: process.env.REDISPASSWORD || process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: null, // Required by BullMQ
  // Default to IPv4 for local, but Fly.io internal needs IPv6
  family: process.env.FLY_APP_NAME ? 6 : 4,
};

// **FIX: Prioritize REDIS_URL for internal Fly.io networking**
const redisUrl = process.env.REDIS_URL || process.env.REDIS_PUBLIC_URL;
if (redisUrl) {
  try {
    const parsedUrl = new URL(redisUrl);
    const isRedisSecure = redisUrl.startsWith('rediss://');
    
    // Determine if this is an internal Fly address (they don't support TLS on port 6379)
    const isInternalFly = parsedUrl.hostname.includes('.internal');

    redisOptions = {
      host: parsedUrl.hostname,
      port: parseInt(parsedUrl.port, 10),
      password: parsedUrl.password,
      username: parsedUrl.username,
      maxRetriesPerRequest: null,
      connectTimeout: 60000,   // 60s (Increased for Fly.io cold starts)
      commandTimeout: 30000,   // 30s
      keepAlive: 2000,        // Every 2s
      enableReadyCheck: false,
      // **CRITICAL: IPv6 (family 6) is ONLY mandatory for internal Fly.io networking**
      family: process.env.FLY_APP_NAME ? 6 : undefined, 
      retryStrategy: (times) => Math.min(times * 200, 5000),
      // **FIX: Explicitly disable TLS on Fly.io to prevent ERR_SSL_WRONG_VERSION_NUMBER**
      // On Fly.io, internal/IPv6 routes usually prefer plaintext on port 6379.
      tls: (isRedisSecure && !process.env.FLY_APP_NAME) ? { rejectUnauthorized: false } : false,
    };

    console.log(`📡 QueueService: Redis Configured → ${parsedUrl.hostname}:${parsedUrl.port}`);
    console.log(`🔒 Security: ${isRedisSecure ? 'TLS Enabled' : 'Plaintext (Internal)'} | 🌐 Network: IPv${redisOptions.family || 4}`);
    
    if (isRedisSecure && isInternalFly) {
      console.warn('⚠️ WARNING: Using rediss:// on an internal Fly address may cause SSL version errors.');
    }
  } catch (err) {
    console.error('❌ QueueService: URL Parse failed:', err.message);
  }
} else {
  console.log(`🔧 QueueService: Using individual env variables | 🌐 Network: IPv${redisOptions.family}`);
}

// Create the video processing queue
const videoQueue = new Queue('video-processing', {
  connection: redisOptions
});


class FeedQueueService {
    constructor() {
        // **FIX: Skip automatic scheduling in test mode**
        if (process.env.NODE_ENV !== 'test') {
            this.addRankCalculationJob(); 
        }
    }

    /**
     * **NEW: Close the queue connection (for Clean Teardown)**
     */
    async close() {
        try {
            await videoQueue.close();
        } catch (error) {
            // Silently fail if already closed
        }
    }

    /**
     * **NEW: Add rank calculation job to the queue**
     * This is a repeatable job that runs every 2 hours to prevent
     * API thundering herd on cache misses.
     */
    async addRankCalculationJob() {
        try {
            await videoQueue.add('recalculate-ranks', {}, {
                repeat: {
                    every: 12 * 60 * 60 * 1000 // Every 12 hours instead of 2
                },
                removeOnComplete: true,
                priority: 10 // Low priority (Videos are priority 1)
            });
            console.log('✅ QueueService: Rank calculation scheduled (every 12h)');
        } catch (error) {
            console.error('❌ QueueService: Failed to schedule rank calculation:', error);
        }
    }

    /**
     * Wakes up the Fly.io worker machine on-demand if env variables are configured.
     */
    async _wakeWorker() {
        const flyAppName = process.env.FLY_APP_NAME;
        const flyApiToken = process.env.FLY_API_TOKEN;

        if (!flyAppName || !flyApiToken) {
            console.log('ℹ️ QueueService: Standalone worker wake-up skipped (missing FLY_API_TOKEN or FLY_APP_NAME in env)');
            return;
        }

        try {
            console.log('📡 QueueService: Fetching app machines list from Fly.io...');
            // 1. Get all machines for the app
            const listResponse = await axios.get(
                `https://api.machines.dev/v1/apps/${flyAppName}/machines`,
                {
                    headers: {
                        Authorization: `Bearer ${flyApiToken}`,
                        'Content-Type': 'application/json'
                    },
                    timeout: 5000
                }
            );

            // 2. Filter for the machine(s) in the 'worker' process group
            const workerMachines = listResponse.data.filter(
                m => m.config?.metadata?.["fly_process_group"] === 'worker'
            );

            if (workerMachines.length === 0) {
                console.warn('⚠️ QueueService: No worker machines found to start');
                return;
            }

            // 3. Wake up the worker machines if they are not already started
            for (const machine of workerMachines) {
                if (machine.state !== 'started') {
                    console.log(`📡 QueueService: Waking up worker machine (${machine.id}) in state ${machine.state}...`);
                    const response = await axios.post(
                        `https://api.machines.dev/v1/apps/${flyAppName}/machines/${machine.id}/start`,
                        {},
                        {
                            headers: {
                                Authorization: `Bearer ${flyApiToken}`,
                                'Content-Type': 'application/json'
                            },
                            timeout: 5000
                        }
                    );
                    console.log(`✅ QueueService: Worker machine ${machine.id} wake-up triggered: status ${response.status}`);
                } else {
                    console.log(`ℹ️ QueueService: Worker machine ${machine.id} is already running.`);
                }
            }
        } catch (error) {
            console.error('❌ QueueService: Failed to wake up worker machine:', error.response?.data || error.message);
        }
    }

    /**
     * Add a video processing job to the queue
     * @param {Object} data - Job data
     * @param {string} data.videoId - Video ID
     * @param {string} data.rawVideoKey - R2 key for the raw video
     * @param {string} data.videoName - Video name
     * @param {string} data.userId - User ID
     */
    async addVideoJob(data) {
        try {
            console.log('📥 QueueService: Adding video job to queue:', data.videoId);
            await videoQueue.add('process-video', data, {
                jobId: `process-video_${data.videoId}`,
                attempts: 3,
                backoff: { type: 'exponential', delay: 5000 },
                removeOnComplete: true,
                removeOnFail: false,
                priority: 1, // High Priority
                jobTimeout: 15 * 60 * 1000, // 15 minutes timeout for FFmpeg processing
                removeOnFail: {
                    age: 24 * 60 * 60 * 1000, // Keep failed jobs for 24 hours
                    count: 10
                }
            });
            console.log('✅ QueueService: Job added successfully');
            
            // Wake up background worker on Fly.io (async - don't block API response)
            this._wakeWorker().catch(err => console.error('Error waking worker:', err));

            return true;
        } catch (error) {
            console.error('❌ QueueService: Failed to add job:', error);
            throw error;
        }
    }

    /**
     * Add a background video analysis job (Gemini)
     * @param {Object} data - { videoId }
     */
    async addAnalysisJob(data) {
        try {
            console.log('📥 QueueService: Adding analysis job for video:', data.videoId);
            await videoQueue.add('analyze-video', data, {
                jobId: `analyze-video_${data.videoId}`,
                attempts: 3,
                backoff: { type: 'exponential', delay: 10000 },
                removeOnComplete: true,
                removeOnFail: false,
                priority: 3 // Lower priority than video processing
            });
            return true;
        } catch (error) {
            console.error('❌ QueueService: Failed to add analysis job:', error);
            throw error;
        }
    }

    /**
     * Remove video processing and analysis jobs from the queue if they exist
     * @param {string} videoId - Video ID
     */
    async removeVideoJob(videoId) {
        try {
            console.log(`🧹 QueueService: Attempting to remove jobs for video ${videoId} from queue...`);
            const jobTypes = [`process-video_${videoId}`, `analyze-video_${videoId}`];
            for (const jobId of jobTypes) {
                try {
                    const job = await videoQueue.getJob(jobId);
                    if (job) {
                        const state = await job.getState();
                        console.log(`   Found job ${jobId} in state: ${state}. Removing...`);
                        await job.remove();
                        console.log(`   Removed job ${jobId} successfully.`);
                    } else {
                        console.log(`   No job found with ID: ${jobId}`);
                    }
                } catch (jobErr) {
                    console.warn(`⚠️ QueueService: Could not remove job ${jobId} (it may be active/locked by a worker):`, jobErr.message);
                }
            }
            return true;
        } catch (error) {
            console.error(`❌ QueueService: Error removing job for video ${videoId}:`, error);
            return false;
        }
    }

    
    // Legacy FanOut method (stub or move existing logic here if needed)
    async fanOutToFollowers(userId, videoId, videoType) {
        // Implementation can stay as is if it's already working directly via DB
        // Or we can move it to a background job too later.
        // For now, let's focus on video processing.
        console.log('fanOutToFollowers placeholder called');
        return 0;
    }
}

export default new FeedQueueService();
export { videoQueue };
