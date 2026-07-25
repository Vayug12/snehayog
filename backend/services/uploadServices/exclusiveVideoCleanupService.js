import cron from 'node-cron';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import redisService from '../caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';

/**
 * Parses a public URL to extract the corresponding Cloudflare R2 storage key.
 */
const getR2KeyFromUrl = (url) => {
  if (!url || typeof url !== 'string' || !url.startsWith('http')) return null;
  
  // Safety check: ensure it is a SnehaYog R2 URL to prevent deleting external resources
  if (!url.includes('snehayog') && !url.includes('cloudflarestorage.com')) {
    return null;
  }
  
  try {
    const parsedUrl = new URL(url);
    let key = decodeURIComponent(parsedUrl.pathname);
    if (key.startsWith('/')) {
      key = key.substring(1);
    }
    return key;
  } catch (e) {
    console.error('⚠️ Failed to parse R2 URL:', url, e);
    return null;
  }
};

/**
 * Deletes all objects (playlists, segments, etc.) under an HLS folder directory prefix.
 */
const deleteFolderFromR2 = async (prefix) => {
  if (!prefix) return;
  try {
    const { ListObjectsV2Command } = await import('@aws-sdk/client-s3');
    const { default: cloudflareR2Service } = await import('./cloudflareR2Service.js');
    
    console.log(`🧹 Listing and deleting all objects under R2 prefix folder: ${prefix}`);
    const listCommand = new ListObjectsV2Command({
      Bucket: cloudflareR2Service.bucketName,
      Prefix: prefix
    });
    const listResponse = await cloudflareR2Service.s3Client.send(listCommand);
    
    if (listResponse.Contents && listResponse.Contents.length > 0) {
      for (const obj of listResponse.Contents) {
        await cloudflareR2Service.deleteFile(obj.Key);
        console.log(`  🗑️ Deleted HLS resource segment: ${obj.Key}`);
      }
    }
  } catch (error) {
    console.error(`❌ Error deleting folder prefix ${prefix} from R2:`, error);
  }
};

/**
 * Main function to find and permanently delete exclusive/private videos older than 7 days.
 */
export const runCleanup = async () => {
  try {
    // Lazy load heavy dependencies only when cleanup actually runs
    const { default: cloudflareR2Service } = await import('./cloudflareR2Service.js');
    const { default: queueService } = await import('../yugFeedServices/queueService.js');

    console.log('⏰ Starting Exclusive/Private Video 7-Day Auto-Cleanup Job...');
    
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    
    // Find all subscriber-only videos created more than 7 days ago
    const expiredVideos = await Video.find({
      isSubscriberOnly: true,
      createdAt: { $lt: sevenDaysAgo }
    }).populate('uploader', '_id googleId');
    
    console.log(`🔍 Found ${expiredVideos.length} expired exclusive/private videos.`);
    
    let deletedCount = 0;
    
    for (const video of expiredVideos) {
      const videoId = video._id.toString();
      console.log(`🚨 Processing cleanup for expired private video: "${video.videoName}" (${videoId}) by creator: ${video.uploader?._id}`);
      
      const keysToDelete = new Set();
      
      const addUrlToKeys = (url) => {
        const key = getR2KeyFromUrl(url);
        if (key) keysToDelete.add(key);
      };
      
      // Collect all regular file keys
      addUrlToKeys(video.videoUrl);
      addUrlToKeys(video.thumbnailUrl);
      addUrlToKeys(video.preloadQualityUrl);
      addUrlToKeys(video.lowQualityUrl);
      addUrlToKeys(video.mediumQualityUrl);
      addUrlToKeys(video.highQualityUrl);
      addUrlToKeys(video.canonicalMp4Url);
      
      if (video.qualitiesGenerated && Array.isArray(video.qualitiesGenerated)) {
        video.qualitiesGenerated.forEach(q => addUrlToKeys(q.url));
      }
      
      if (video.hlsVariants && Array.isArray(video.hlsVariants)) {
        video.hlsVariants.forEach(v => addUrlToKeys(v.url));
      }
      
      // Delete collected R2 file keys
      for (const key of keysToDelete) {
        try {
          await cloudflareR2Service.deleteFile(key);
          console.log(`  🗑️ Successfully deleted R2 file: ${key}`);
        } catch (err) {
          console.error(`  ❌ Failed to delete R2 file: ${key}`, err);
        }
      }
      
      // Delete HLS folders if present
      if (video.hlsMasterPlaylistUrl) {
        const masterKey = getR2KeyFromUrl(video.hlsMasterPlaylistUrl);
        if (masterKey) {
          const lastSlash = masterKey.lastIndexOf('/');
          if (lastSlash !== -1) {
            const prefix = masterKey.substring(0, lastSlash + 1);
            await deleteFolderFromR2(prefix);
          }
        }
      }
      
      if (video.hlsPlaylistUrl) {
        const playlistKey = getR2KeyFromUrl(video.hlsPlaylistUrl);
        if (playlistKey) {
          const lastSlash = playlistKey.lastIndexOf('/');
          if (lastSlash !== -1) {
            const prefix = playlistKey.substring(0, lastSlash + 1);
            await deleteFolderFromR2(prefix);
          }
        }
      }
      
      // Delete the video document permanently from MongoDB
      await Video.findByIdAndDelete(video._id);

      // Clean up queue jobs
      await queueService.removeVideoJob(videoId);
      
      // Remove video ID from the creator's upload history
      if (video.uploader) {
        await User.findByIdAndUpdate(video.uploader._id, {
          $pull: { videos: video._id }
        });
      }
      
      // Invalidate Redis caches for this video
      if (redisService.getConnectionStatus()) {
        const uploaderGoogleId = video.uploader?.googleId;
        const cacheKeys = [
          'videos:feed:*',
          VideoCacheKeys.all(),
          VideoCacheKeys.single(videoId),
          `video:data:${videoId}`
        ];
        
        if (uploaderGoogleId) {
          cacheKeys.push(`videos:user:${uploaderGoogleId}`);
          cacheKeys.push(`user:feed:${uploaderGoogleId}:*`);
        }
        
        await invalidateCache(cacheKeys);
        console.log(`  🧹 Invalidated cache for deleted video: ${videoId}`);
      }
      
      deletedCount++;
      console.log(`✅ Finished permanent cleanup for video: ${videoId}`);
    }
    
    console.log(`🎉 Exclusive video cleanup job completed. Total videos permanently deleted: ${deletedCount}`);
  } catch (error) {
    console.error('❌ Error in exclusive video cleanup job:', error);
  }
};

// Scheduler setup
let cleanupJob = null;

export const startScheduler = () => {
  if (cleanupJob) {
    console.log('⚠️ Exclusive video cleanup cron is already running');
    return;
  }
  
  // Run daily at midnight (00:00)
  cleanupJob = cron.schedule('0 0 * * *', async () => {
    await runCleanup();
  });
  
  console.log('📅 Exclusive video cleanup cron scheduled to run daily at 00:00');
};

export const stopScheduler = () => {
  if (cleanupJob) {
    cleanupJob.stop();
    cleanupJob = null;
    console.log('⏹️ Exclusive video cleanup cron stopped');
  }
};

export default {
  runCleanup,
  startScheduler,
  stopScheduler
};
