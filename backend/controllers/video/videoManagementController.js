import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import redisService from '../../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';
import { logger } from '../../middleware/traceMiddleware.js';
import { serializeVideo } from '../../utils/serializers/videoSerializer.js';
import queueService from '../../services/yugFeedServices/queueService.js';

/**
 * **Update Video Metadata**
 */
export const updateVideo = async (req, res) => {
  try {
    const videoId = req.params.id;
    const googleId = req.user.googleId;
    const { videoName, link, tags, seriesId, episodeNumber, quizzes, thumbnailKey } = req.body;

    if (!videoName || videoName.trim() === '') {
      return res.status(400).json({ error: 'Video name is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = await Video.findById(videoId).populate('uploader', 'name profilePic googleId');
    if (!video) {
      logger.warn(req.traceId, 'Video not found for update', { videoId });
      return res.status(404).json({ error: 'Video not found' });
    }

    if (video.uploader._id.toString() !== user._id.toString()) {
      return res.status(403).json({ error: 'Not authorized to update this video' });
    }

    video.videoName = videoName.trim();
    if (link !== undefined) video.link = link.trim();
    if (seriesId !== undefined) video.seriesId = seriesId;
    if (episodeNumber !== undefined) video.episodeNumber = parseInt(episodeNumber) || 0;

    if (tags !== undefined) {
      if (Array.isArray(tags)) {
        video.tags = tags.map(t => t.trim().toLowerCase()).filter(t => t.length > 0);
      } else if (typeof tags === 'string') {
        video.tags = tags.split(',').map(t => t.trim().toLowerCase()).filter(t => t.length > 0);
      }
    }
 
    if (quizzes !== undefined && Array.isArray(quizzes)) {
      video.quizzes = quizzes;
    }

    if (thumbnailKey) {
      // Lazy load cloudflareR2Service if needed or import it at top
      // For consistency with direct-complete, we'll assume it's available or we use a helper
      const { default: cloudflareR2Service } = await import('../../services/uploadServices/cloudflareR2Service.js');
      video.thumbnailUrl = cloudflareR2Service.getPublicUrl(thumbnailKey);
      logger.info(req.traceId, 'Video thumbnail updated', { videoId, thumbnailKey });
    }

    video.updatedAt = new Date();
    await video.save();
    
    if (redisService.getConnectionStatus()) {
      const keysToInvalidate = [
        'videos:feed:*',
        `videos:user:${googleId}`,
        VideoCacheKeys.all(),
        VideoCacheKeys.single(videoId),
        `video:data:${videoId}`
      ];

      if (video.seriesId) {
        try {
          const siblings = await Video.find({ seriesId: video.seriesId }).select('_id').lean();
          siblings.forEach(s => {
            keysToInvalidate.push(VideoCacheKeys.single(s._id.toString()));
            keysToInvalidate.push(`video:data:${s._id.toString()}`);
          });
        } catch (e) {}
      }

      await invalidateCache(keysToInvalidate);
    }

    const videoObj = video.toObject();
    const transformedVideo = serializeVideo(videoObj, req.apiVersion, user._id.toString(), req.traceId);

    res.json({ 
      success: true, 
      message: 'Video updated successfully',
      video: transformedVideo
    });
  } catch (error) {
    logger.error(req.traceId, 'Error updating video', error, { videoId: req.params.id });
    res.status(500).json({ error: 'Failed to update video' });
  }
};

/**
 * **Update Video Series**
 */
export const updateVideoSeries = async (req, res) => {
  try {
    const videoId = req.params.id;
    const googleId = req.user.googleId;
    const { episodeIds, seriesId } = req.body;

    if (!Array.isArray(episodeIds) || episodeIds.length === 0) {
      return res.status(400).json({ error: 'episodeIds array is required' });
    }

    const user = await User.findOne({ googleId }).select('_id').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    const uniqueVideoIds = [...new Set([videoId, ...episodeIds])];
    const videos = await Video.find({ _id: { $in: uniqueVideoIds } });

    if (videos.length === 0) return res.status(404).json({ error: 'Videos not found' });

    for (const v of videos) {
      if (v.uploader.toString() !== user._id.toString()) {
        return res.status(403).json({ error: `Not authorized to update video: ${v._id}` });
      }
    }

    const targetSeriesId = seriesId || `series_${Date.now()}`;

    await Video.updateMany(
      { 
        seriesId: targetSeriesId, 
        uploader: user._id,
        _id: { $nin: uniqueVideoIds } 
      },
      { 
        $set: { 
          seriesId: null, 
          episodeNumber: 0,
          updatedAt: new Date()
        } 
      }
    );

    const bulkOps = episodeIds.map((id, index) => ({
      updateOne: {
        filter: { _id: id },
        update: { 
          $set: { 
            seriesId: targetSeriesId, 
            episodeNumber: index + 1,
            updatedAt: new Date()
          } 
        }
      }
    }));

    if (!episodeIds.includes(videoId)) {
      bulkOps.push({
        updateOne: {
          filter: { _id: videoId },
          update: { 
            $set: { 
              seriesId: targetSeriesId,
              updatedAt: new Date()
            } 
          }
        }
      });
    }

    if (bulkOps.length > 0) await Video.bulkWrite(bulkOps);

    if (redisService.getConnectionStatus()) {
      const keysToInvalidate = [
        'videos:feed:*',
        `videos:user:${googleId}`,
        VideoCacheKeys.all(),
        VideoCacheKeys.single(videoId),
        `video:data:${videoId}`
      ];

      uniqueVideoIds.forEach(id => {
        keysToInvalidate.push(VideoCacheKeys.single(id.toString()));
        keysToInvalidate.push(`video:data:${id.toString()}`);
      });
      
      await invalidateCache(keysToInvalidate);
    }

    let episodes = await Video.find({ 
      seriesId: targetSeriesId, 
      processingStatus: 'completed' 
    })
    .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
    .sort({ episodeNumber: 1 }).lean();

    episodes = episodes.map(ep => ({ ...ep, _id: ep._id.toString() }));

    res.json({
      success: true,
      message: 'Series linked and updated successfully',
      seriesId: targetSeriesId,
      episodes: episodes
    });

  } catch (error) {
    console.error('❌ Error updating video series:', error);
    res.status(500).json({ error: 'Failed to update video series', message: error.message });
  }
};

/**
 * Video Deletion Controllers
 */
export const deleteVideo = async (req, res) => {
  try {
    const videoId = req.params.id;
    const googleId = req.user.googleId;

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = await Video.findById(videoId);
    if (!video) return res.status(404).json({ error: 'Video not found' });

    if (video.uploader.toString() !== user._id.toString()) {
      return res.status(403).json({ error: 'Not authorized to delete this video' });
    }

    await Video.findByIdAndDelete(videoId);
    await User.findByIdAndUpdate(user._id, { $pull: { videos: videoId } });

    // Clean up queue jobs
    await queueService.removeVideoJob(videoId);

    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*', 
        `videos:user:${googleId}`, 
        `user:feed:${googleId}:*`,
        VideoCacheKeys.all(), 
        VideoCacheKeys.single(videoId)
      ]);
    }

    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    console.error('❌ Error deleting video:', error);
    res.status(500).json({ error: 'Failed to delete video' });
  }
};

export const bulkDeleteVideos = async (req, res) => {
  try {
    const { videoIds } = req.body;
    const googleId = req.user.googleId;

    if (!Array.isArray(videoIds) || videoIds.length === 0) {
      return res.status(400).json({ error: 'No video IDs provided' });
    }

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const objectIds = videoIds.map(id => new mongoose.Types.ObjectId(id));

    const result = await Video.deleteMany({ 
      _id: { $in: objectIds }, 
      uploader: user._id 
    });

    await User.findByIdAndUpdate(user._id, { 
      $pull: { videos: { $in: objectIds } } 
    });

    // Clean up queue jobs for all deleted videos
    try {
      await Promise.all(videoIds.map(id => queueService.removeVideoJob(id)));
    } catch (err) {
      console.error('❌ Failed to clean up bulk queue jobs:', err);
    }

    if (redisService.getConnectionStatus()) {
      const patterns = [
        'videos:feed:*',
        `videos:user:${googleId}`,
        `user:feed:${googleId}:*`,
        VideoCacheKeys.all()
      ];
      
      for (const id of videoIds) patterns.push(VideoCacheKeys.single(id));

      await invalidateCache(patterns);
    }

    res.json({ 
      success: true, 
      message: `Successfully deleted ${result.deletedCount} videos`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('❌ Bulk delete error:', error);
    res.status(500).json({ error: 'Failed to delete videos' });
  }
};

/**
 * Utility & Cleanup Controllers
 */
export const cleanupTempHLS = async (req, res) => {
  try {
    const tempDir = path.join(process.cwd(), 'temp', 'hls');
    if (fs.existsSync(tempDir)) {
      const folders = fs.readdirSync(tempDir);
      let count = 0;
      for (const folder of folders) {
        const folderPath = path.join(tempDir, folder);
        if (fs.statSync(folderPath).isDirectory()) {
          fs.rmSync(folderPath, { recursive: true, force: true });
          count++;
        }
      }
      res.json({ success: true, message: `Cleaned up ${count} temp HLS folders` });
    } else {
      res.json({ success: true, message: 'Temp HLS directory does not exist' });
    }
  } catch (error) {
    res.status(500).json({ error: 'Failed to cleanup temp HLS' });
  }
};

export const cleanupOrphaned = async (req, res) => {
  try {
    const videos = await Video.find({}).select('uploader').lean();
    const videoIds = videos.map(v => v._id);
    const users = await User.find({ videos: { $in: videoIds } });
    
    let updatedCount = 0;
    for (const user of users) {
      const validVideos = user.videos.filter(id => videoIds.some(vid => vid.equals(id)));
      if (validVideos.length !== user.videos.length) {
        user.videos = validVideos;
        await user.save();
        updatedCount++;
      }
    }
    res.json({ success: true, message: `Checked ${users.length} users, updated ${updatedCount}` });
  } catch (error) {
    res.status(500).json({ error: 'Cleanup failed' });
  }
};

export const cleanupBrokenVideos = async (req, res) => {
  try {
    const result = await Video.deleteMany({
      $or: [
        { videoUrl: { $exists: false } },
        { videoUrl: '' },
        { thumbnailUrl: { $exists: false } },
        { thumbnailUrl: '' }
      ],
      processingStatus: 'completed'
    });
    res.json({ success: true, message: `Deleted ${result.deletedCount} broken videos` });
  } catch (error) {
    res.status(500).json({ error: 'Cleanup failed' });
  }
};

export const syncUserVideoArrays = async (req, res) => {
  try {
    const users = await User.find({});
    let totalUpdated = 0;
    for (const user of users) {
      const activeVideos = await Video.find({ uploader: user._id }).select('_id').lean();
      user.videos = activeVideos.map(v => v._id.toString());
      await user.save();
      totalUpdated++;
    }
    res.json({ success: true, updatedUsers: totalUpdated });
  } catch (error) {
    res.status(500).json({ error: 'Sync failed' });
  }
};
