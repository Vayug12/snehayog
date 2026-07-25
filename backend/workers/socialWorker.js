import '../config/config.js';
import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';
import Video from '../models/Video.js';
import User from '../models/User.js';
import { redisOptions } from '../services/yugFeedServices/queueService.js';
import cloudflareR2Service from '../services/uploadServices/cloudflareR2Service.js';
import youtubeService from '../services/platforms/youtubeService.js';

// Connect to MongoDB
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('📦 Social Worker: MongoDB Connected');
  } catch (error) {
    console.error('❌ Social Worker: MongoDB Connection Error:', error);
    process.exit(1);
  }
};

connectDB();

/**
 * Handle platform-specific publishing logic
 */
async function handlePublishingJob(job) {
  const { platform, videoId, userId, title, description, tags, privacyStatus } = job.data;
  console.log(`📡 Social Worker: Processing ${platform} job for video ${videoId}`);

  let localFilePath = null;

  try {
    // 1. Update status to 'processing'
    await Video.findByIdAndUpdate(videoId, {
      $set: { [`crossPostStatus.${platform}`]: 'processing' }
    });

    // 2. Get video metadata to find the R2 key
    const video = await Video.findById(videoId).populate('uploader');
    if (!video) throw new Error('Video not found');
    
    const user = await User.findOne({ googleId: userId });
    if (!user) throw new Error('User not found');

    const tempDir = path.join(process.cwd(), 'temp_social_uploads');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    
    localFilePath = path.join(tempDir, `${videoId}_${platform}.mp4`);
    
    // Download the video file
    console.log(`📥 Social Worker: Downloading video for ${platform}...`);
    
    // **NEW: Use canonical MP4 key if available (much more reliable)**
    if (video.canonicalMp4Key) {
        console.log(`🔑 Using canonical MP4 key: ${video.canonicalMp4Key}`);
        await cloudflareR2Service.downloadFile(video.canonicalMp4Key, localFilePath);
    } else if (video.videoUrl.includes('cdn.snehayog.site')) {
        // Fallback to parsing if canonical key is missing (for older videos)
        const publicDomain = 'cdn.snehayog.site';
        const key = video.videoUrl.split(publicDomain).pop().replace(/^\//, '');
        console.log(`🔑 Parsed key from URL: ${key}`);
        await cloudflareR2Service.downloadFile(key, localFilePath);
    } else {
        // Fallback or handle different CDN
        throw new Error('Could not resolve video R2 key for download');
    }

    let result;
    if (platform === 'youtube') {
      let lastProgress = 0;
      result = await youtubeService.uploadVideo(userId, localFilePath, { title, description, tags, privacyStatus }, async (progress) => {
          // **OPTIMIZATION: Only update DB every 5% to avoid excessive writes**
          if (progress >= lastProgress + 5 || progress === 100) {
              lastProgress = progress;
              await Video.findByIdAndUpdate(videoId, {
                  $set: { [`crossPostProgress.${platform}`]: progress }
              });
              console.log(`📡 Social Worker: ${platform} upload progress for ${videoId}: ${progress}%`);
          }
      });
    } else {
      throw new Error(`Platform ${platform} not supported or removed`);
    }

    // 3. Update status to 'completed'
    await Video.findByIdAndUpdate(videoId, {
      $set: { 
        [`crossPostStatus.${platform}`]: 'completed',
        [`crossPostDetails.${platform}`]: result
      }
    });

    console.log(`✅ Social Worker: Successfully published to ${platform} for video ${videoId}`);

  } catch (error) {
    console.error(`❌ Social Worker Error (${platform}):`, error.message);
    
    // Update status to 'failed'
    await Video.findByIdAndUpdate(videoId, {
      $set: { 
        [`crossPostStatus.${platform}`]: 'failed',
        [`crossPostDetails.${platform}`]: { error: error.message }
      }
    });
    
    throw error; // Let Bull handle retries if configured
  } finally {
    // Cleanup local file
    if (localFilePath && fs.existsSync(localFilePath)) {
      try {
        fs.unlinkSync(localFilePath);
      } catch (e) {
        console.error('⚠️ Social Worker: Failed to cleanup local file:', e.message);
      }
    }
  }
}

// **Social Worker Instance**
const socialWorker = new Worker('social-publishing', async (job) => {
  return await handlePublishingJob(job);
}, {
  connection: redisOptions,
  concurrency: 2 // Keep it low to avoid platform rate limits
});

socialWorker.on('completed', (job) => {
  console.log(`✅ Social Job ${job.id} completed!`);
});

socialWorker.on('failed', (job, err) => {
  console.log(`❌ Social Job ${job.id} failed: ${err.message}`);
});

console.log('👷 Social Publishing Worker Started and Listening...');
