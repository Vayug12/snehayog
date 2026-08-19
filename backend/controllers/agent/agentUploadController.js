import fs from 'fs';
import path from 'path';
import multer from 'multer';
import mongoose from 'mongoose';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import RecommendationService from '../../services/yugFeedServices/recommendationService.js';
import queueService from '../../services/yugFeedServices/queueService.js';
import cloudflareR2Service from '../../services/uploadServices/cloudflareR2Service.js';
import redisService from '../../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';
import eventBus from '../../utils/eventBus.js';
import {
  DAILY_UPLOAD_LIMIT_CODE,
  sendDailyUploadLimitResponse,
} from '../../services/uploadServices/dailyUploadQuotaService.js';
import {
  markVideoUploadFailed,
  saveVideoWithDailyQuota,
} from '../../services/uploadServices/videoUploadLifecycleService.js';

let hybridVideoService;

const AGENT_MAX_FILE_SIZE = 400 * 1024 * 1024;

const ALLOWED_VIDEO_EXTENSIONS = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'];
const ALLOWED_MIME_TYPES = ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'];

/**
 * Safe file deletion - never throws
 */
const safeUnlink = (filePath) => {
  if (!filePath) return;
  try {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }
  } catch (e) {
    console.warn(`⚠️ Failed to delete temp file: ${filePath}`, e.message);
  }
};

/**
 * Multer config for agent direct uploads (400MB limit)
 */
const agentStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = 'uploads/agent/';
    try {
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    } catch (err) {
      cb(new Error('Failed to create upload directory'), false);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, uniqueSuffix + '-' + safeName);
  },
});

export const agentUpload = multer({
  storage: agentStorage,
  limits: { fileSize: AGENT_MAX_FILE_SIZE },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      const err = new Error(`Invalid file type. Allowed: ${ALLOWED_MIME_TYPES.join(', ')}`);
      err.statusCode = 400;
      return cb(err, false);
    }
    cb(null, true);
  }
});

/**
 * GET /api/agent/upload/presigned-url
 * Generate presigned URL for direct R2 upload
 */
export const getPresignedUrl = async (req, res) => {
  try {
    const { filename, contentType } = req.query;
    const userId = req.user._id;

    if (!filename || typeof filename !== 'string' || filename.trim() === '') {
      return res.status(400).json({ error: 'filename query parameter is required' });
    }

    const sanitizedFilename = path.basename(filename.trim());
    const ext = path.extname(sanitizedFilename).toLowerCase().replace('.', '');

    if (!ext) {
      return res.status(400).json({ error: 'Filename must have a valid extension (e.g., .mp4)' });
    }

    if (!ALLOWED_VIDEO_EXTENSIONS.includes(ext)) {
      return res.status(400).json({
        error: `Invalid file extension '.${ext}'. Allowed: ${ALLOWED_VIDEO_EXTENSIONS.join(', ')}`
      });
    }

    const mime = contentType || `video/${ext === 'mov' ? 'quicktime' : ext}`;
    const key = `agent_uploads/${userId}/${Date.now()}_${sanitizedFilename}`;

    const uploadUrl = await cloudflareR2Service.getPresignedUploadUrl(key, mime, 3600);

    return res.status(200).json({
      success: true,
      uploadUrl,
      key,
      expiresIn: 3600,
      method: 'PUT',
      headers: { 'Content-Type': mime }
    });
  } catch (error) {
    console.error('❌ Agent Presigned URL Error:', error.message);
    return res.status(500).json({ error: 'Failed to generate upload URL. Please try again.' });
  }
};

/**
 * GET /api/agent/upload/download-url
 * Presigned URL for a DURABLE MP4 copy used for gallery download.
 *
 * Unlike the normal upload key (agent_uploads/…), this key lives under
 * ai_downloads/… and is NEVER handed to the processing pipeline, so the
 * CleanupStep does not delete it. The returned downloadUrl is a public R2
 * URL the app can save directly to the device gallery.
 */
export const getDownloadPresignedUrl = async (req, res) => {
  try {
    const { filename, contentType } = req.query;
    const userId = req.user._id;

    if (!filename || typeof filename !== 'string' || filename.trim() === '') {
      return res.status(400).json({ error: 'filename query parameter is required' });
    }

    const sanitizedFilename = path.basename(filename.trim());
    const ext = path.extname(sanitizedFilename).toLowerCase().replace('.', '');

    if (!ext) {
      return res.status(400).json({ error: 'Filename must have a valid extension (e.g., .mp4)' });
    }

    if (!ALLOWED_VIDEO_EXTENSIONS.includes(ext)) {
      return res.status(400).json({
        error: `Invalid file extension '.${ext}'. Allowed: ${ALLOWED_VIDEO_EXTENSIONS.join(', ')}`
      });
    }

    const mime = contentType || `video/${ext === 'mov' ? 'quicktime' : ext}`;
    const key = `ai_downloads/${userId}/${Date.now()}_${sanitizedFilename}`;

    const uploadUrl = await cloudflareR2Service.getPresignedUploadUrl(key, mime, 3600);
    const downloadUrl = cloudflareR2Service.getPublicUrl(key);

    return res.status(200).json({
      success: true,
      uploadUrl,
      downloadUrl,
      key,
      expiresIn: 3600,
      method: 'PUT',
      headers: { 'Content-Type': mime }
    });
  } catch (error) {
    console.error('❌ Agent Download Presigned URL Error:', error.message);
    return res.status(500).json({ error: 'Failed to generate download upload URL. Please try again.' });
  }
};

/**
 * POST /api/agent/upload/register
 * Register a video after direct R2 upload
 */
export const registerUpload = async (req, res) => {
  let user = null;
  let createdVideo = null;
  try {
    const { r2Key, videoName, description, category, tags, duration, width, height, link } = req.body;
    const googleId = req.user.googleId;

    if (!googleId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    if (!r2Key || typeof r2Key !== 'string' || r2Key.trim() === '') {
      return res.status(400).json({ error: 'r2Key is required' });
    }

    if (!videoName || typeof videoName !== 'string' || videoName.trim() === '') {
      return res.status(400).json({ error: 'videoName is required' });
    }

    if (videoName.trim().length > 500) {
      return res.status(400).json({ error: 'videoName must be 500 characters or less' });
    }

    if (!r2Key.startsWith('agent_uploads/')) {
      return res.status(403).json({ error: 'Invalid R2 key. Must start with agent_uploads/' });
    }

    if (!r2Key.includes(`/${req.user._id}/`)) {
      return res.status(403).json({ error: 'R2 key does not belong to this user' });
    }

    user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const parsedWidth = width ? parseInt(width, 10) : 0;
    const parsedHeight = height ? parseInt(height, 10) : 0;
    const parsedDuration = duration ? parseInt(duration, 10) : 0;

    let finalVideoType = 'yog';
    if (parsedWidth > 0 && parsedHeight > 0) {
      finalVideoType = (parsedWidth > parsedHeight) ? 'vayu' : 'yog';
    }

    const initialScore = RecommendationService.calculateFinalScore({
      totalWatchTime: 0,
      duration: parsedDuration,
      likes: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

    const video = new Video({
      videoName: videoName.trim(),
      description: (typeof description === 'string' && description.trim()) || '',
      link: (typeof link === 'string' && link.trim()) || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (parsedWidth > 0 && parsedHeight > 0) ? parsedWidth / parsedHeight : undefined,
      duration: parsedDuration,
      originalResolution: { width: parsedWidth, height: parsedHeight },
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      category: (typeof category === 'string' && category.trim()) || 'others',
      tags: Array.isArray(tags) ? tags.filter(t => typeof t === 'string').map(t => t.trim().toLowerCase()).filter(Boolean) : [],
      finalScore: initialScore,
      originalFormat: path.extname(r2Key).replace('.', '').toLowerCase() || 'mp4'
    });

    await saveVideoWithDailyQuota(video);
    createdVideo = video;

    user.videos.push(video._id);
    await user.save();

    (async () => {
      try {
        await queueService.addVideoJob({
          videoId: video._id,
          rawVideoKey: r2Key,
          videoName: video.videoName,
          userId: user._id.toString()
        });

        console.log(`✅ Agent RegisterUpload: Background processing started for video ${video._id}`);
      } catch (err) {
        console.error(`❌ Agent RegisterUpload Background Error for video ${video._id}:`, err.message);

        await markVideoUploadFailed(video._id, `Background processing failed: ${err.message}`).catch(() => {});
      }
    })();

    if (redisService.getConnectionStatus()) {
      const cacheKeysToInvalidate = [
        `user:feed:${user.googleId}:*`,
        VideoCacheKeys.all(),
        'videos:feed:*'
      ];
      invalidateCache(cacheKeysToInvalidate).catch(err => console.error('⚠️ Agent RegisterUpload: Cache invalidation failed:', err.message));
    }

    return res.status(201).json({
      success: true,
      message: 'Video registered. Processing started.',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: 'queued',
        estimatedTime: '2-5 minutes'
      }
    });

  } catch (error) {
    console.error('❌ Agent Register Upload Error:', error.message);

    if (error.code === DAILY_UPLOAD_LIMIT_CODE) {
      return sendDailyUploadLimitResponse(res, error);
    }

    if (createdVideo) {
      await markVideoUploadFailed(createdVideo._id, error).catch(() => {});
    }

    if (error.name === 'ValidationError') {
      const messages = Object.values(error.errors).map(e => e.message);
      return res.status(400).json({ error: 'Validation failed', details: messages });
    }

    if (error.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid data format' });
    }

    return res.status(500).json({ error: 'Failed to register video. Please try again.' });
  }
};

/**
 * POST /api/agent/upload/direct
 * Direct multipart video upload (max 400MB)
 */
export const directUpload = async (req, res) => {
  const tempFilePath = req.file ? req.file.path : null;
  let createdVideo = null;

  try {
    const googleId = req.user.googleId;
    if (!googleId) {
      safeUnlink(tempFilePath);
      return res.status(401).json({ error: 'User not authenticated' });
    }

    if (!req.file || !req.file.path) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    const { videoName, description, category, tags, link, width, height } = req.body;

    if (!videoName || typeof videoName !== 'string' || videoName.trim() === '') {
      safeUnlink(tempFilePath);
      return res.status(400).json({ error: 'videoName is required' });
    }

    if (videoName.trim().length > 500) {
      safeUnlink(tempFilePath);
      return res.status(400).json({ error: 'videoName must be 500 characters or less' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      safeUnlink(tempFilePath);
      return res.status(404).json({ error: 'User not found' });
    }

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
      console.warn('⚠️ Agent Upload: Failed to detect video info:', infoError.message);
    }

    const parsedWidth = width ? parseInt(width, 10) : detectedWidth;
    const parsedHeight = height ? parseInt(height, 10) : detectedHeight;

    let finalVideoType = 'yog';
    if (parsedWidth > 0 && parsedHeight > 0) {
      finalVideoType = (parsedWidth > parsedHeight) ? 'vayu' : 'yog';
    }

    const initialScore = RecommendationService.calculateFinalScore({
      totalWatchTime: 0,
      duration: detectedDuration || 0,
      likes: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

    const video = new Video({
      videoName: videoName.trim(),
      description: (typeof description === 'string' && description.trim()) || '',
      link: (typeof link === 'string' && link.trim()) || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (parsedWidth > 0 && parsedHeight > 0) ? parsedWidth / parsedHeight : undefined,
      duration: detectedDuration || 0,
      originalResolution: { width: parsedWidth, height: parsedHeight },
      thumbnailUrl: '',
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      category: (typeof category === 'string' && category.trim()) || 'others',
      tags: Array.isArray(tags) ? tags.filter(t => typeof t === 'string').map(t => t.trim().toLowerCase()).filter(Boolean) : [],
      finalScore: initialScore,
      originalFormat: path.extname(req.file.path).replace('.', '').toLowerCase() || 'mp4'
    });

    await saveVideoWithDailyQuota(video);
    createdVideo = video;
    user.videos.push(video._id);
    await user.save();

    const rawVideoKey = `agent_uploads/${user._id}/${Date.now()}_${path.basename(req.file.path)}`;
    const tempMimeType = req.file.mimetype;

    (async () => {
      try {
        await cloudflareR2Service.uploadFileToR2(tempFilePath, rawVideoKey, tempMimeType);

        await queueService.addVideoJob({
          videoId: video._id,
          rawVideoKey: rawVideoKey,
          videoName: video.videoName,
          userId: user._id.toString()
        });

        console.log(`✅ Agent DirectUpload: Background processing started for video ${video._id}`);
      } catch (bgError) {
        console.error(`❌ Agent DirectUpload: Background processing failed for video ${video._id}:`, bgError.message);

        await markVideoUploadFailed(video._id, `Background processing failed: ${bgError.message}`).catch(() => {});
      } finally {
        safeUnlink(tempFilePath);
      }
    })();

    return res.status(201).json({
      success: true,
      message: 'Video upload received. Processing started.',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: 'queued',
        estimatedTime: '2-5 minutes'
      }
    });

  } catch (error) {
    console.error('❌ Agent Direct Upload Error:', error.message);
    safeUnlink(tempFilePath);

    if (error.code === DAILY_UPLOAD_LIMIT_CODE) {
      return sendDailyUploadLimitResponse(res, error);
    }

    if (createdVideo) {
      await markVideoUploadFailed(createdVideo._id, error).catch(() => {});
    }

    if (error.name === 'ValidationError') {
      const messages = Object.values(error.errors).map(e => e.message);
      return res.status(400).json({ error: 'Validation failed', details: messages });
    }

    if (error.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid data format' });
    }

    return res.status(500).json({ error: 'Video upload failed. Please try again.' });
  }
};

/**
 * GET /api/agent/upload/status/:videoId
 * Check processing status of an uploaded video
 */
export const getUploadStatus = async (req, res) => {
  try {
    const { videoId } = req.params;

    if (!videoId) {
      return res.status(400).json({ error: 'videoId parameter is required' });
    }

    if (!mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid videoId format' });
    }

    const video = await Video.findById(videoId)
      .select('videoName uploader processingStatus processingProgress videoUrl thumbnailUrl processingError uploadedAt category tags duration')
      .lean();

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    if (!video.uploader || video.uploader.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Access denied. You can only check your own videos.' });
    }

    return res.status(200).json({
      success: true,
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        videoUrl: video.processingStatus === 'completed' ? video.videoUrl : null,
        thumbnailUrl: video.processingStatus === 'completed' ? video.thumbnailUrl : null,
        error: video.processingError || null,
        uploadedAt: video.uploadedAt,
        category: video.category,
        tags: video.tags,
        duration: video.duration
      }
    });
  } catch (error) {
    console.error('❌ Agent Status Check Error:', error.message);

    if (error.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid videoId format' });
    }

    return res.status(500).json({ error: 'Failed to get upload status' });
  }
};

/**
 * GET /api/agent/upload/status/sse/:videoId
 * SSE stream for real-time processing status updates
 */
export const streamUploadStatus = async (req, res) => {
  const { videoId } = req.params;

  if (!videoId) {
    return res.status(400).json({ error: 'videoId parameter is required' });
  }

  if (!mongoose.Types.ObjectId.isValid(videoId)) {
    return res.status(400).json({ error: 'Invalid videoId format' });
  }

  try {
    const video = await Video.findById(videoId).select('uploader').lean();
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    if (!video.uploader || video.uploader.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Access denied' });
    }
  } catch (error) {
    if (error.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid videoId format' });
    }
    return res.status(500).json({ error: 'Failed to verify video' });
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  });

  const onStatusUpdate = (update) => {
    if (update.jobId && update.jobId.toString() === videoId.toString()) {
      res.write(`data: ${JSON.stringify(update)}\n\n`);
      if (typeof res.flush === 'function') res.flush();
      if (update.status === 'completed' || update.status === 'failed') {
        setTimeout(() => res.end(), 1000);
      }
    }
  };

  eventBus.on('clipping-status', onStatusUpdate);

  res.write('retry: 10000\n');
  res.write(':keep-alive\n\n');

  const cleanup = () => {
    eventBus.removeListener('clipping-status', onStatusUpdate);
  };

  req.on('close', cleanup);
};
