import fs from 'fs';
import path from 'path';
import mongoose from 'mongoose';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import RecommendationService from '../../services/yugFeedServices/recommendationService.js';
import queueService from '../../services/yugFeedServices/queueService.js';
import cloudflareR2Service from '../../services/uploadServices/cloudflareR2Service.js';
import redisService from '../../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';
import { calculateVideoHash } from '../../utils/videoUtils.js';
import {
  DAILY_UPLOAD_LIMIT_CODE,
  sendDailyUploadLimitResponse,
} from '../../services/uploadServices/dailyUploadQuotaService.js';
import {
  markVideoUploadFailed,
  saveVideoWithDailyQuota,
} from '../../services/uploadServices/videoUploadLifecycleService.js';

let hybridVideoService;

/**
 * Upload and Duplicate Check Controllers
 */
export const checkDuplicate = async (req, res) => {
  try {
    const { videoHash } = req.body;
    const googleId = req.user.googleId;

    if (!videoHash) {
      return res.status(400).json({ error: 'Video hash is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash,
      processingStatus: { $ne: 'failed' } // Ignore failed uploads
    });

    if (existingVideo) {
      console.log('⚠️ Duplicate check: Duplicate video found:', existingVideo.videoName);
      return res.json({
        isDuplicate: true,
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName,
        message: 'You have already uploaded this video.'
      });
    }

    console.log('✅ Duplicate check: No duplicate found');
    return res.json({ isDuplicate: false });
  } catch (error) {
    console.error('❌ Error checking duplicate:', error);
    res.status(500).json({ error: 'Failed to check duplicate' });
  }
};

export const uploadVideo = async (req, res) => {
  let createdVideo = null;
  try {
    console.log('🎬 Upload: Starting video upload process with HLS streaming...');
    
    // Google ID is available from verifyToken middleware
    const googleId = req.user.googleId;
    if (!googleId) {
      console.log('❌ Upload: Google ID not found in token');
      if (req.file) fs.unlinkSync(req.file.path);
      return res.status(401).json({ error: 'Google ID not found in token' });
    }

    const { videoName, description, videoType, link, category, tags, allowedSubscribers } = req.body;

    // 1. Validate file
    if (!req.file || !req.file.path) {
      console.log('❌ Upload: No video file uploaded');
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    // 2. Validate required fields
    if (!videoName || videoName.trim() === '') {
      console.log('❌ Upload: Missing video name');
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Video name is required' });
    }

    // 3. Validate user
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ Upload: User not found with Google ID:', googleId);
      fs.unlinkSync(req.file.path);
      return res.status(404).json({ error: 'User not found' });
    }

    // 4. Calculate video hash for duplicate detection
    let videoHash;
    try {
      videoHash = await calculateVideoHash(req.file.path);
    } catch (hashError) {
      console.error('❌ Upload: Error calculating video hash:', hashError);
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Failed to calculate video hash' });
    }

    // 5. Check if same video already exists for this user
    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash,
      processingStatus: { $ne: 'failed' } // Ignore failed uploads
    });

    if (existingVideo) {
      fs.unlinkSync(req.file.path);
      return res.status(409).json({
        error: 'Duplicate video detected',
        message: 'You have already uploaded this video.',
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName
      });
    }

    // 6. Determine video type based on aspect ratio (landscape vs portrait)
    if (!hybridVideoService) {
      const { default: service } = await import('../../services/uploadServices/hybridVideoService.js');
      hybridVideoService = service;
    }

    let detectedDuration = 0;
    let detectedWidth = 0;
    let detectedHeight = 0;

    try {
      const videoInfo = await hybridVideoService.getOriginalVideoInfo(req.file.path);
      detectedDuration = videoInfo.duration || 0;
      detectedWidth = videoInfo.width || 0;
      detectedHeight = videoInfo.height || 0;
    } catch (infoError) {
      console.warn('⚠️ Upload: Failed to get video info:', infoError.message);
    }

    // **SOURCE OF TRUTH: Classify based on aspect ratio ONLY**
    let finalVideoType = videoType || 'yog';
    if (detectedWidth > 0 && detectedHeight > 0) {
      const aspectRatio = detectedWidth / detectedHeight;
      if (aspectRatio > 1.0) {
        // Landscape/Horizontal video (e.g., 16:9 = 1.778)
        finalVideoType = 'vayu';
      } else {
        // Portrait/Vertical video (e.g., 9:16 = 0.5625)
        finalVideoType = 'yog';
      }
    } else {
      // Fallback to default if dimensions not detected
      finalVideoType = videoType || 'yog';
    }

    // 7. Create initial video record
    const initialScore = RecommendationService.calculateFinalScore({
      totalWatchTime: 0,
      duration: detectedDuration || 0,
      likes: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

    const isSubOnly = Array.isArray(allowedSubscribers) && allowedSubscribers.length > 0;

    const video = new Video({
      videoName: videoName,
      description: description || '',
      link: link || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (detectedWidth && detectedHeight) ? detectedWidth / detectedHeight : undefined,
      duration: detectedDuration || 0,
      originalResolution: { width: detectedWidth || 0, height: detectedHeight || 0 },
      thumbnailUrl: isSubOnly ? 'https://placehold.co/600x400/1e1e24/ffffff?text=Subscriber+Only+🔒' : '',
      processingStatus: isSubOnly ? 'completed' : 'pending',
      processingProgress: isSubOnly ? 100 : 0,
      isHLSEncoded: false,
      videoHash: videoHash,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      category: category || 'others',
      tags: Array.isArray(tags) ? tags : [],
      seriesId: req.body.seriesId || null,
      episodeNumber: parseInt(req.body.episodeNumber) || 0,
      finalScore: initialScore,
      // **NEW: Subscriber-only access control**
      allowedSubscribers: Array.isArray(allowedSubscribers) ? allowedSubscribers : [],
      isSubscriberOnly: isSubOnly
    });

    await saveVideoWithDailyQuota(video);
    createdVideo = video;
    user.videos.push(video._id);
    await user.save();

    // 9. Background Processing - Respond immediately to user for better speed
    const rawVideoKey = `temp_raw/${user._id}/${Date.now()}_${path.basename(req.file.path)}`;
    const tempFilePath = req.file.path;
    const tempMimeType = req.file.mimetype;

    // We do NOT await this block - it runs in background
    (async () => {
      try {
        // **NEW: Invalidate cache in background to avoid blocking the response**
        if (redisService.getConnectionStatus()) {
          const cacheKeysToInvalidate = [
            `user:feed:${user.googleId}:*`,
            `videos:user:${user.googleId}`,
            VideoCacheKeys.all()
          ];
          if (!video.isSubscriberOnly) {
            cacheKeysToInvalidate.push('videos:feed:*');
          }
          invalidateCache(cacheKeysToInvalidate).catch(err => console.error('⚠️ Upload: Cache invalidation failed:', err.message));
        }

        if (video.isSubscriberOnly) {
          // E2EE: Upload file directly to R2 and set videoUrl
          await cloudflareR2Service.uploadFileToR2(tempFilePath, rawVideoKey, tempMimeType);
          const finalVideoUrl = cloudflareR2Service.getPublicUrl(rawVideoKey);
          await Video.findByIdAndUpdate(video._id, { videoUrl: finalVideoUrl });
          console.log(`🔒 E2EE: Uploaded subscriber-only file to R2 and updated videoUrl for ${video._id}`);
        } else {
          await cloudflareR2Service.uploadFileToR2(tempFilePath, rawVideoKey, tempMimeType);
          
          await queueService.addVideoJob({
              videoId: video._id,
              rawVideoKey: rawVideoKey,
              videoName: videoName,
              userId: user._id.toString()
          });

          console.log(`✅ Upload: Background processing started for video ${video._id}`);
        }
      } catch (bgError) {
        console.error(`❌ Upload: Background processing failed for video ${video._id}:`, bgError);
        await markVideoUploadFailed(video._id, bgError).catch((quotaError) => {
          console.error(`Upload quota release failed for video ${video._id}:`, quotaError.message);
        });
      } finally {
        // Cleanup temp file AFTER background processing
        try { 
          if (fs.existsSync(tempFilePath)) {
            fs.unlinkSync(tempFilePath); 
          }
        } catch (e) { 
          console.warn('Failed to cleanup upload', e); 
        }
      }
    })();

    return res.status(201).json({
      success: true,
      message: video.isSubscriberOnly 
        ? 'Subscriber-only E2EE video uploaded successfully!' 
        : 'Video upload received! Processing will begin in background.',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.isSubscriberOnly ? 'completed' : 'queued',
        estimatedTime: video.isSubscriberOnly ? 'immediate' : '2-5 minutes',
        costBreakdown: { processing: '$0 (FREE!)', storage: '$0.015/GB/month (R2)', bandwidth: '$0 (FREE forever!)' },
        isSubscriberOnly: video.isSubscriberOnly || false
      }
    });

  } catch (error) {
    console.error('❌ Upload: Error:', error);
    if (req.file) {
      try { fs.unlinkSync(req.file.path); } catch (_) { }
    }
    if (error.code === DAILY_UPLOAD_LIMIT_CODE) {
      return sendDailyUploadLimitResponse(res, error);
    }
    if (createdVideo) {
      await markVideoUploadFailed(createdVideo._id, error).catch((quotaError) => {
        console.error(`Upload quota release failed for video ${createdVideo._id}:`, quotaError.message);
      });
    }
    return res.status(500).json({ error: 'Video upload failed', details: error.message });
  }
};

export const registerUpload = async (req, res) => {
  let createdVideo = null;
  try {
    const { 
      videoName, 
      description, 
      videoType, 
      link, 
      r2Key, 
      videoHash, 
      duration,
      width,
      height,
      category,
      tags
    } = req.body;

    const googleId = req.user.googleId;
    if (!googleId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    if (!r2Key) {
       return res.status(400).json({ error: 'R2 storage key is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (videoHash) {
      const existingVideo = await Video.findOne({
        uploader: user._id,
        videoHash: videoHash,
        processingStatus: { $ne: 'failed' }
      });

      if (existingVideo) {
        return res.status(409).json({
          error: 'Duplicate video detected',
          message: 'You have already uploaded this video.',
          existingVideoId: existingVideo._id
        });
      }
    }

    let finalVideoType = videoType || 'yog';
    if (width && height) {
      finalVideoType = (width > height) ? 'vayu' : 'yog';
    }

    const initialScore = RecommendationService.calculateFinalScore({
      totalWatchTime: 0,
      duration: duration || 0,
      likes: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

    const video = new Video({
      videoName: videoName || 'Untitled Video',
      description: description || '',
      link: link || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (width && height) ? (width / height) : undefined,
      duration: duration || 0,
      originalResolution: { width: width || 0, height: height || 0 },
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false,
      videoHash: videoHash,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      category: category || 'others',
      tags: Array.isArray(tags) ? tags : [],
      finalScore: initialScore
    });

    await saveVideoWithDailyQuota(video);
    createdVideo = video;
    user.videos.push(video._id);
    await user.save();

    // Non-blocking: Add to queue
    (async () => {
       try {
         await queueService.addVideoJob({
            videoId: video._id,
            rawVideoKey: r2Key,
            videoName: video.videoName,
            userId: user._id.toString()
         });
       } catch (err) {
         console.error('❌ RegisterUpload Background Error:', err);
         await markVideoUploadFailed(video._id, err).catch((quotaError) => {
           console.error(`Upload quota release failed for video ${video._id}:`, quotaError.message);
         });
       }
    })();

    // Non-blocking: Invalidate cache in background
    if (redisService.getConnectionStatus()) {
      const cacheKeysToInvalidate = [
        `user:feed:${user.googleId}:*`,
        VideoCacheKeys.all()
      ];
      if (!video.isSubscriberOnly) {
        cacheKeysToInvalidate.push('videos:feed:*');
      }
      invalidateCache(cacheKeysToInvalidate).catch(err => console.error('⚠️ RegisterUpload: Cache invalidation failed:', err.message));
    }

    return res.status(201).json({
      success: true,
      message: 'Video registered successfully. Processing started.',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: 'queued'
      }
    });

  } catch (error) {
    console.error('❌ Register Upload Error:', error);
    if (error.code === DAILY_UPLOAD_LIMIT_CODE) {
      return sendDailyUploadLimitResponse(res, error);
    }
    if (createdVideo) {
      await markVideoUploadFailed(createdVideo._id, error).catch((quotaError) => {
        console.error(`Upload quota release failed for video ${createdVideo._id}:`, quotaError.message);
      });
    }
    return res.status(500).json({ error: 'Failed to register video' });
  }
};

export const r2Callback = async (req, res) => {
  try {
    const { event, key } = req.body;
    const workerSecret = req.headers['x-worker-secret'];

    if (workerSecret !== process.env.WORKER_SECRET && process.env.NODE_ENV === 'production') {
      return res.status(403).json({ error: 'Unauthorized worker callback' });
    }

    console.log(`📡 R2 Callback received for ${key} (${event})`);
    
    const video = await Video.findOne({ 'rawVideoKey': key });
    if (video) {
      video.processingStatus = 'processing';
      await video.save();
      console.log(`✅ Video ${video._id} status updated to processing`);
    }

    return res.json({ success: true });
  } catch (error) {
    console.error('❌ R2 Callback Error:', error);
    return res.status(500).json({ error: 'Callback processing failed' });
  }
};

export const createImageFeedEntry = async (req, res) => {
  try {
    const { imageUrl, videoName, link, videoType, category, tags } = req.body || {};

    if (!imageUrl || typeof imageUrl !== 'string' || !imageUrl.trim()) {
      return res.status(400).json({ error: 'imageUrl is required' });
    }

    const trimmedUrl = imageUrl.trim();
    if (!/^https?:\/\//i.test(trimmedUrl)) {
      return res.status(400).json({ error: 'imageUrl must be a valid HTTP/HTTPS URL' });
    }

    const googleId = req.user.googleId;
    if (!googleId) {
      return res.status(401).json({ error: 'Google ID not found in token' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const now = new Date();

    const video = new Video({
      videoName: (videoName && String(videoName).trim()) || 'Product Image',
      description: '',
      link: (link && String(link).trim()) || '',
      videoUrl: trimmedUrl,
      thumbnailUrl: trimmedUrl,
      uploader: user._id,
      videoType: (videoType && String(videoType).toLowerCase() === 'vayu') ? 'vayu' : 'yog',
      mediaType: 'image',
      aspectRatio: 9 / 16,
      duration: 0,
      processingStatus: 'completed',
      processingProgress: 100,
      isHLSEncoded: false,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: now,
      createdAt: now,
      updatedAt: now,
      ...(category ? { category: String(category).toLowerCase().trim() } : {}),
      ...(Array.isArray(tags) && tags.length
        ? { tags: tags.map((t) => String(t).toLowerCase().trim()).filter(Boolean) }
        : {}),
    });

    await saveVideoWithDailyQuota(video);
    user.videos.push(video._id);
    await user.save();

    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*',
        `videos:user:${user.googleId}`,
        VideoCacheKeys.all(),
      ]);
    }

    return res.status(201).json({
      success: true,
      message: 'Image feed entry created successfully',
      video: {
        id: video._id,
        videoName: video.videoName,
        videoUrl: video.processingStatus === 'completed' ? video.videoUrl : null,
        thumbnailUrl: video.processingStatus === 'completed' ? video.thumbnailUrl : null,
        crossPostStatus: video.crossPostStatus || {},
        crossPostProgress: video.crossPostProgress || {},
        crossPostDetails: video.crossPostDetails || {},
        link: video.link,
        videoType: video.videoType,
        mediaType: video.mediaType,
        uploadedAt: video.uploadedAt,
      },
    });
  } catch (error) {
    console.error('❌ Error creating image feed entry:', error);
    if (error.code === DAILY_UPLOAD_LIMIT_CODE) {
      return sendDailyUploadLimitResponse(res, error);
    }
    return res.status(500).json({ error: 'Failed to create image feed entry', details: error.message });
  }
};
