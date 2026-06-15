import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import fsSync from 'fs';
import crypto from 'crypto';
import mongoose from 'mongoose';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
let hybridVideoService;
import { verifyToken } from '../../utils/verifytoken.js';
import cloudflareR2Service from '../../services/uploadServices/cloudflareR2Service.js';
import { uploadLimiter } from '../../middleware/rateLimiter.js';
import AdmZip from 'adm-zip';
import { addSocialJob } from '../../services/socialQueue.js';
import queueService from '../../services/yugFeedServices/queueService.js';
import redisService from '../../services/caching/redisService.js';

const router = express.Router();

/**
 * Calculate SHA256 hash of a file
 * @param {string} filePath - Path to the file
 * @returns {Promise<string>} - Hex string of the hash
 */
async function calculateFileHash(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fsSync.createReadStream(filePath);

    stream.on('data', (data) => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', (error) => reject(error));
  });
}

// **NEW: Configure multer for image uploads**
const imageStorage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(process.cwd(), 'uploads', 'ads');
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    cb(null, `ad-image-${uniqueSuffix}${ext}`);
  }
});

const imageUpload = multer({
  storage: imageStorage,
  limits: {
    fileSize: 40 * 1024 * 1024, // 40MB limit for ad images
    files: 1
  },
  fileFilter: (req, file, cb) => {
    const allowedMimeTypes = [
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/heic',
      'image/heif',
      'image/avif',
      'image/bmp',
      'image/tiff'
    ];

    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
});

// **NEW: Configure multer for video uploads**
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    // Determine upload directory based on field name
    let uploadDir = path.join(process.cwd(), 'uploads', 'temp');
    
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    const prefix = 'video-';
    cb(null, `${prefix}${uniqueSuffix}${ext}`);
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 700 * 1024 * 1024, // 700MB limit (Updated to match videoRoutes)
    files: 1
  },
  fileFilter: (req, file, cb) => {
    // **NEW: Allow only video files**
    const allowedMimeTypes = [
      'video/mp4',
      'video/mov',
      'video/avi',
      'video/mkv',
      'video/webm',
      'video/flv',
      // Removed ZIP support
    ];

    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only video files are allowed'), false);
    }
  }
});

// **NEW: Direct-to-R2 Upload Routes (USED BY FRONTEND)**

/**
 * @route POST /api/upload/video/presigned
 * @desc Generate a presigned URL for direct R2 upload
 * @access Private
 */
router.post('/video/presigned', verifyToken, uploadLimiter, async (req, res) => {
  try {
    const { fileName, fileType, fileSize } = req.body;
    const userId = req.user.id;

    if (!fileName || !fileType) {
      return res.status(400).json({ error: 'FileName and FileType are required' });
    }

    // Validate file type (basic check)
    if (!fileType.startsWith('video/') && !fileType.startsWith('image/')) {
       return res.status(400).json({ error: 'Only video or image files are allowed' });
    }
    
    // Max size check (700MB)
    if (fileSize && fileSize > 700 * 1024 * 1024) {
        return res.status(400).json({ error: 'File too large (Max 700MB)' });
    }

    // Generate unique R2 key
    const timestamp = Date.now();
    const cleanFileName = fileName.replace(/[^a-zA-Z0-9]/g, '_');
    const folder = fileType.startsWith('image/') ? 'uploads/thumbnails' : 'uploads/raw';
    const key = `${folder}/${userId}/${timestamp}_${cleanFileName}`;

    // Get presigned URL
    const uploadUrl = await cloudflareR2Service.getPresignedUploadUrl(key, fileType);

    res.json({
      uploadUrl,
      key,
      headers: {
        'Content-Type': fileType,
      }
    });

  } catch (error) {
    console.error('❌ Error generating presigned URL:', error);
    res.status(500).json({ error: 'Failed to generate upload URL' });
  }
});

/**
 * @route POST /api/upload/video/direct-complete
 * @desc Notify backend that direct upload is complete and trigger processing
 * @access Private
 */
router.post('/video/direct-complete', verifyToken, uploadLimiter, async (req, res) => {
  try {
    const { key, videoName, description, link, size, category, tags, videoType, crossPostPlatforms, seriesId, episodeNumber, thumbnailKey, quizzes, allowedSubscribers } = req.body;
    const userId = req.user.id;

    if (!key || !videoName) {
      return res.status(400).json({ success: false, error: 'Key and VideoName are required' });
    }

    console.log('🚀 Direct Upload Complete received for:', key);

    // Find user by Google ID to get proper ObjectId
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    // **FIX: Resolve allowedSubscribers from googleIds/strings → MongoDB ObjectIds**
    // Flutter sends MongoDB _id strings (from /api/users/subscribers response).
    // The subscriber-videos query uses ObjectId matching, so we must store ObjectIds.
    let resolvedSubscriberIds = [];
    if (Array.isArray(allowedSubscribers) && allowedSubscribers.length > 0) {
      const subscriberDocs = await User.find({
        $or: [
          { _id: { $in: allowedSubscribers.filter(id => mongoose.Types.ObjectId.isValid(id)) } },
          { googleId: { $in: allowedSubscribers } }
        ]
      }).select('_id').lean();
      resolvedSubscriberIds = subscriberDocs.map(doc => doc._id);
      console.log(`✅ direct-complete: Resolved ${resolvedSubscriberIds.length}/${allowedSubscribers.length} subscriber IDs to ObjectIds`);
    }

    const isSubOnly = resolvedSubscriberIds.length > 0;

    // 1. Create Video Record (Processing State)
    const newVideo = new Video({
      uploader: user._id,
      videoName: videoName,
      description: description || '',
      category: category || 'others',
      tags: Array.isArray(tags) ? tags : [],
      videoType: videoType || 'yog',
      link: link || '',
      videoUrl: cloudflareR2Service.getPublicUrl(key),
      thumbnailUrl: isSubOnly 
        ? 'https://placehold.co/600x400/1e1e24/ffffff?text=Subscriber+Only+🔒' 
        : (thumbnailKey ? cloudflareR2Service.getPublicUrl(thumbnailKey) : ''),
      processingStatus: isSubOnly ? 'completed' : 'processing',
      processingProgress: isSubOnly ? 100 : 0,
      processingError: null,
      originalSize: size || 0,
      views: 0,
      likes: 0,
      isHLSEncoded: false,
      seriesId: seriesId || null,
      episodeNumber: episodeNumber ? parseInt(episodeNumber) : 0,
      quizzes: Array.isArray(quizzes) ? quizzes : [],
      // **FIX: Store resolved ObjectIds so subscriber-videos query works correctly**
      allowedSubscribers: resolvedSubscriberIds,
      isSubscriberOnly: isSubOnly
    });

    if (crossPostPlatforms && Array.isArray(crossPostPlatforms)) {
      crossPostPlatforms.forEach(platform => {
        newVideo.set(`crossPostStatus.${platform}`, 'pending');
      });
    }

    await newVideo.save();

    // Lazy load hybrid service
    if (!hybridVideoService) {
      const { default: service } = await import('../../services/uploadServices/hybridVideoService.js');
      hybridVideoService = service;
    }

    // **FIX: Invalidate user's video cache so the new video appears immediately**
    if (redisService.getConnectionStatus()) {
      const { invalidateCache, VideoCacheKeys } = await import('../../middleware/cacheMiddleware.js');
      const cacheKeysToInvalidate = [
        `user:feed:${user.googleId}:*`,
        `videos:user:${user.googleId}`,
        VideoCacheKeys.all()
      ];
      if (!newVideo.isSubscriberOnly) {
        cacheKeysToInvalidate.push('videos:feed:*');
      }
      invalidateCache(cacheKeysToInvalidate).catch(err => console.error('⚠️ direct-complete: Cache invalidation failed:', err.message));
    }

    // 2. Trigger Background Processing via BullMQ
    // We add the job to the queue instead of processing it locally, unless subscriber-only
    if (!newVideo.isSubscriberOnly) {
      await queueService.addVideoJob({
        videoId: newVideo._id.toString(),
        rawVideoKey: key,
        videoName: videoName,
        userId: userId,
        crossPostPlatforms: crossPostPlatforms || [],
        thumbnailKey: thumbnailKey
      });
    } else {
      console.log(`🔒 Video ${newVideo._id} is subscriber-only/E2EE. Bypassing processing queue and publishing immediately.`);
    }

    // 3. Return success immediately
    res.status(201).json({
      success: true,
      message: 'Video upload received and processing started',
      video: newVideo
    });

  } catch (error) {
    console.error('❌ Error finishing direct upload:', error);
    res.status(500).json({ success: false, error: 'Failed to complete upload process' });
  }
});

// Original Server-Side Upload Route (Keep as fallback)
router.post('/video', verifyToken, uploadLimiter, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No video file uploaded' });
    }

    const { videoName, description, link, crossPostPlatforms, category, tags, quizzes } = req.body;
    const userId = req.user.id;
    const videoPath = req.file.path;

    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../../services/uploadServices/hybridVideoService.js');
      hybridVideoService = service;
    }

    const videoValidation = await hybridVideoService.validateVideo(videoPath);
    if (!videoValidation.isValid) {
      await fs.unlink(videoPath);
      return res.status(400).json({
        success: false,
        error: 'Invalid video file',
        details: videoValidation.error
      });
    }


    // **NEW: Find user by Google ID to get proper ObjectId**
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      await fs.unlink(videoPath);
      return res.status(404).json({ success: false, error: 'User not found' });
    }

    // **NEW: Calculate file hash for duplicate detection**
    let videoHash;
    try {
      videoHash = await calculateFileHash(videoPath);
    } catch (hashError) {
      console.error('❌ Error calculating file hash:', hashError);
      await fs.unlink(videoPath);
      return res.status(500).json({
        success: false,
        error: 'Failed to process video file',
        details: 'Error calculating file hash'
      });
    }

    // **NEW: Check for duplicate video (same user, same hash)**
    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash,
      processingStatus: { $ne: 'failed' } // Allow retry if previous attempt failed
    });

    if (existingVideo) {
      console.log('⚠️ Duplicate video detected:', {
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName,
        hash: videoHash.substring(0, 16) + '...'
      });

      // Clean up uploaded file
      await fs.unlink(videoPath);

      return res.status(409).json({
        success: false,
        error: 'Duplicate video detected',
        message: 'You have already uploaded this video',
        existingVideo: {
          id: existingVideo._id,
          videoName: existingVideo.videoName,
          uploadedAt: existingVideo.uploadedAt
        }
      });
    }

    // **NEW: Get video dimensions safely**
    const videoInfo = await hybridVideoService.getOriginalVideoInfo(videoPath);
    const aspectRatio = videoInfo.width && videoInfo.height ?
      videoInfo.width / videoInfo.height : 9 / 16; // Default to 9:16 if dimensions unavailable

    // **NEW: Create initial video record with pending status**
    // **FIX: Use proper URL format instead of local file path**
    const baseUrl = process.env.SERVER_URL || 'http://192.168.0.199:5001';
    const relativePath = videoPath.replace(/\\/g, '/').replace(process.cwd().replace(/\\/g, '/'), '');
    const tempVideoUrl = `${baseUrl}${relativePath}`;

    console.log('🔗 Generated temp video URL:', tempVideoUrl);

    const video = new Video({
      videoName: videoName || req.file.originalname,
      description: description || '',
      videoUrl: tempVideoUrl, // Proper URL format, will be updated after processing
      thumbnailUrl: '', // Will be generated during processing
      uploader: user._id, // Use user's ObjectId, not Google ID
      // **SOURCE OF TRUTH: Classify based on aspect ratio**
      // Landscape (AR > 1.0) = Vayu, Portrait (AR <= 1.0) = Yog
      videoType: aspectRatio > 1.0 ? 'vayu' : 'yog',
      aspectRatio: aspectRatio,
      duration: videoInfo.duration || 0,
      originalSize: videoValidation.size,
      originalFormat: path.extname(req.file.originalname).substring(1),
      originalResolution: {
        width: videoInfo.width || 0,
        height: videoInfo.height || 0
      },
      processingStatus: 'pending',
      processingProgress: 0,
      link: link || '', // **FIX: Include link field from request body**
      videoHash: videoHash, // **NEW: Save hash for duplicate detection**
      episodeNumber: req.body.episodeNumber ? parseInt(req.body.episodeNumber) : 0, // **NEW: Save episode number**
      category: category || 'others',
      tags: Array.isArray(tags) ? tags : [],
      quizzes: Array.isArray(quizzes) ? quizzes : []
    });

    if (crossPostPlatforms && Array.isArray(crossPostPlatforms)) {
        crossPostPlatforms.forEach(platform => {
            video.set(`crossPostStatus.${platform}`, 'pending');
        });
    }

    // **NEW: Save video record first**
    await video.save();

    // Start processing in background via BullMQ
    // In fallback mode, we still add to queue for processing
    // Note: Local worker will handle downloading from the temp URL if it's a localhost URL,
    // but typically we want to upload to R2 first then process.
    // For now, let's just queue the job.
    await queueService.addVideoJob({
      videoId: video._id.toString(),
      rawVideoKey: tempVideoUrl, // Passing the temp URL as the source
      videoName: videoName || req.file.originalname,
      userId: userId,
      crossPostPlatforms: crossPostPlatforms || []
    });
    
    console.log('✅ Video queued for worker processing:', video._id);

    // **NEW: Return immediate response with processing status**
    res.status(201).json({
      success: true,
      message: 'Video upload started successfully',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        estimatedTime: '2-5 minutes depending on video length'
      }
    });

  } catch (error) {
    console.error('❌ Error in video upload:', error);

    // **NEW: Clean up uploaded file on error**
    if (req.file) {
      try {
        await fs.unlink(req.file.path);
      } catch (cleanupError) {
        console.warn('⚠️ Failed to cleanup file:', cleanupError);
      }
    }

    res.status(500).json({
      success: false,
      error: 'Video upload failed',
      details: error.message
    });
  }
});

// **NEW: URL normalization function**
function normalizeVideoUrl(url) {
  if (!url) return url;

  // **FIX: Replace backslashes with forward slashes**
  let normalizedUrl = url.replace(/\\/g, '/');

  // **FIX: Ensure proper URL format**
  if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
    // If it's a relative path, make it absolute
    const baseUrl = process.env.SERVER_URL;
    normalizedUrl = `${baseUrl}/${normalizedUrl}`;
  }

  // **FIX: Ensure single forward slashes between path segments (but preserve protocol slashes)**
  // Only normalize multiple slashes in the path part, not the protocol
  if (normalizedUrl.includes('://')) {
    const [protocol, rest] = normalizedUrl.split('://');
    const normalizedRest = rest.replace(/\/+/g, '/');
    normalizedUrl = `${protocol}://${normalizedRest}`;
  } else {
    normalizedUrl = normalizedUrl.replace(/\/+/g, '/');
  }

  console.log('🔧 URL normalization:');
  console.log('   Original:', url);
  console.log('   Normalized:', normalizedUrl);

  return normalizedUrl;
}

// DISMISSED: Local processVideoHybrid removed to avoid OOM on main server.
// Processing is now handled exclusively by background workers.

// **NEW: Get video processing status**
router.get('/video/:videoId/status', verifyToken, async (req, res) => {
  try {
    const video = await Video.findById(req.params.videoId);
    if (!video) {
      return res.status(404).json({ success: false, error: 'Video not found' });
    }

    // **FIX: Compare against the user's ObjectId, not Google ID**
    const owner = await User.findOne({ googleId: req.user.id });
    if (!owner || video.uploader.toString() !== owner._id.toString()) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    res.json({
      success: true,
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        processingError: video.processingError,
        hasMultipleQualities: video.hasMultipleQualities,
        qualitiesGenerated: video.qualitiesGenerated.length,
        isHLSEncoded: video.isHLSEncoded || false,
        hlsPlaylistUrl: video.hlsPlaylistUrl || null,
        // Include URLs when processing is completed
        videoUrl: video.processingStatus === 'completed' ? video.videoUrl : null,
        thumbnailUrl: video.processingStatus === 'completed' ? video.thumbnailUrl : null,
        // **NEW: Cross-post information**
        crossPostStatus: video.crossPostStatus || {},
        crossPostProgress: video.crossPostProgress || {},
        crossPostDetails: video.crossPostDetails || {},
        isSubscriberOnly: video.isSubscriberOnly || false
      }
    });

  } catch (error) {
    console.error('❌ Error getting video status:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get video status',
      details: error.message
    });
  }
});

// **NEW: Retry failed video processing**
router.post('/video/:videoId/retry', verifyToken, async (req, res) => {
  try {
    const video = await Video.findById(req.params.videoId);
    if (!video) {
      return res.status(404).json({ success: false, error: 'Video not found' });
    }

    // **NEW: Check if user owns the video**
    if (video.uploader.toString() !== req.user.id) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    // **NEW: Check if video processing failed**
    if (video.processingStatus !== 'failed') {
      return res.status(400).json({
        success: false,
        error: 'Video is not in failed state'
      });
    }

    // **NEW: Reset processing status and retry**
    video.processingStatus = 'pending';
    video.processingProgress = 0;
    video.processingError = null;
    await video.save();

    // **NEW: Start processing again**
    const videoPath = video.videoUrl; // Use original path
    processVideoHybrid(video._id, videoPath, video.videoName, video.uploader).catch(err => {
        console.error('❌ Retry background processing failed:', err);
    });

    res.json({
      success: true,
      message: 'Video processing restarted',
      video: {
        id: video._id,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress
      }
    });

  } catch (error) {
    console.error('❌ Error retrying video processing:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retry video processing',
      details: error.message
    });
  }
});

// **NEW: Get all user's videos with processing status**
router.get('/videos', verifyToken, async (req, res) => {
  try {
    const videos = await Video.find({ uploader: req.user.id })
      .sort({ uploadedAt: -1 })
      .select('videoName processingStatus processingProgress uploadedAt');

    res.json({
      success: true,
      videos: videos
    });

  } catch (error) {
    console.error('❌ Error getting user videos:', error);
    res.status(500).json({
      error: 'Failed to get videos',
      details: error.message
    });
  }
});

// **NEW: Upload image for ads (Cloudflare R2 instead of Cloudinary)**
router.post('/image', verifyToken, imageUpload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded' });
    }

    const imagePath = req.file.path;
    const mimeType = req.file.mimetype || 'image/jpeg';
    const ext = path.extname(imagePath).toLowerCase();

    console.log('🖼️ Starting ad image upload to Cloudflare R2...');
    console.log('📁 File path:', imagePath);
    console.log('📊 File size:', (req.file.size / 1024 / 1024).toFixed(2), 'MB');
    console.log('📄 MIME type:', mimeType);

    try {
      // Determine uploader for directory structure
      const userId = req.user?.id || req.user?.googleId || 'anonymous';
      const fileName = path.basename(imagePath, ext);
      const key = `ads/images/${userId}/${fileName}${ext}`;

      const result = await cloudflareR2Service.uploadFileToR2(
        imagePath,
        key,
        mimeType
      );

      console.log('✅ Ad image uploaded to Cloudflare R2 successfully');
      console.log('🔗 Image URL:', result.url);
      console.log('🗝️ R2 Key:', result.key);

      // Clean up temp file
      await fs.unlink(imagePath);

      res.status(200).json({
        success: true,
        url: result.url,
        key: result.key,
        message: 'Image uploaded successfully',
      });
    } catch (r2Error) {
      console.error('❌ Cloudflare R2 upload failed:', r2Error);

      // Clean up temp file on error
      try {
        await fs.unlink(imagePath);
      } catch (unlinkError) {
        console.error('❌ Error cleaning up temp file:', unlinkError);
      }

      let userFriendlyError = 'Failed to upload image to cloud storage';
      const msg = r2Error.message || '';
      if (msg.includes('timeout')) {
        userFriendlyError =
          'Upload timeout. Please check your internet connection and try again.';
      } else if (msg.includes('file size') || msg.includes('too large')) {
        userFriendlyError =
          'Image file is too large. Please use an image smaller than 10MB.';
      } else if (msg.includes('Only image files are allowed')) {
        userFriendlyError =
          'Invalid image format. Please use JPG, PNG, GIF, or WebP.';
      }

      res.status(500).json({
        error: userFriendlyError,
        details: msg,
      });
    }
  } catch (error) {
    console.error('❌ Error in image upload route:', error);
    res.status(500).json({
      error: 'Image upload failed',
      details: error.message,
    });
  }
});

// **NEW: Game Upload Route**
// Uploads a ZIP file, extracts, validates index.html, and uploads to R2
router.post('/game', verifyToken, upload.single('game'), async (req, res) => {
  let extractDir = null;
  
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No game ZIP file uploaded' });
    }

    const { title, description, orientation } = req.body;
    const userId = req.user.id;
    const zipPath = req.file.path;
    
    console.log('🎮 Starting Game Upload...');
    console.log('📁 ZIP Path:', zipPath);
    console.log('👤 Developer:', userId);

    // 1. Extract ZIP
    const zipName = path.basename(zipPath, path.extname(zipPath));
    extractDir = path.join(path.dirname(zipPath), zipName);
    
    try {
      const zip = new AdmZip(zipPath);
      zip.extractAllTo(extractDir, true);
      console.log('📦 Extracted to:', extractDir);
    } catch (zipError) {
      throw new Error(`Failed to extract ZIP: ${zipError.message}`);
    }

    // 2. Validate Structure (Must have index.html)
    // Recursive search for index.html
    async function findIndexHtml(dir) {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isFile() && entry.name === 'index.html') {
          return fullPath;
        }
        if (entry.isDirectory()) {
          const found = await findIndexHtml(fullPath);
          if (found) return found;
        }
      }
      return null;
    }

    const indexHtmlPath = await findIndexHtml(extractDir);
    if (!indexHtmlPath) {
      throw new Error('Invalid Game: "index.html" not found in ZIP');
    }

    // Determine root folder (where index.html is)
    const gameRootDir = path.dirname(indexHtmlPath);
    console.log('🎯 Game Root found at:', gameRootDir);

    // 3. Upload to R2
    // We upload everything relative to gameRootDir
    
    // Create Game Record first to get ID
    const game = new Game({
      title: title || 'Untitled Game',
      description: description || '',
      thumbnailUrl: 'pending', // Will update after upload
      gameUrl: 'pending',
      developer: userId, // verifyToken populates req.user.id
      orientation: orientation || 'portrait',
      status: 'pending'
    });
    
    await game.save();
    
    // Recursive upload function
    let fileCount = 0;
    async function uploadDirToR2(currentDir, baseRelPath = '') {
      const entries = await fs.readdir(currentDir, { withFileTypes: true });
      
      for (const entry of entries) {
        const fullPath = path.join(currentDir, entry.name);
        const relPath = path.join(baseRelPath, entry.name).replace(/\\/g, '/');
        const r2Key = `games/${game._id}/${relPath}`;
        
        if (entry.isDirectory()) {
          await uploadDirToR2(fullPath, relPath);
        } else {
          // Upload file
          let contentType = 'application/octet-stream';
          if (entry.name.endsWith('.html')) contentType = 'text/html';
          else if (entry.name.endsWith('.js')) contentType = 'application/javascript';
          else if (entry.name.endsWith('.css')) contentType = 'text/css';
          else if (entry.name.endsWith('.json')) contentType = 'application/json';
          else if (entry.name.endsWith('.png')) contentType = 'image/png';
          else if (entry.name.endsWith('.jpg')) contentType = 'image/jpeg';
          
          await cloudflareR2Service.uploadFileToR2(fullPath, r2Key, contentType);
          fileCount++;
        }
      }
    }

    console.log('☁️ Uploading files to R2...');
    await uploadDirToR2(gameRootDir);
    console.log(`✅ Uploaded ${fileCount} files to R2`);

    // 4. Update Game Record
    const cdnBase = cloudflareR2Service.publicDomain 
      ? `https://${cloudflareR2Service.publicDomain}` 
      : `https://${cloudflareR2Service.bucketName}.${cloudflareR2Service.accountId}.r2.cloudflarestorage.com`;
      
    game.gameUrl = `${cdnBase}/games/${game._id}/index.html`;
    game.thumbnailUrl = `${cdnBase}/games/${game._id}/icon.png`; // Assumption: icon.png exists, or we use a default
    // TODO: Better thumbnail handling (allow separate upload or look for specific file)
    
    game.status = 'active'; // Auto-publish for now
    await game.save();

    // 5. Cleanup
    try {
      await fs.unlink(zipPath); // Delete ZIP
      await fs.rm(extractDir, { recursive: true, force: true }); // Delete extracted folder
    } catch (cleanupErr) {
      console.warn('⚠️ Cleanup warning:', cleanupErr.message);
    }

    res.status(201).json({
      success: true,
      message: 'Game uploaded successfully',
      game: {
        id: game._id,
        title: game.title,
        url: game.gameUrl
      }
    });

  } catch (error) {
    console.error('❌ Game Upload Error:', error);
    
    // Cleanup on error
    if (req.file) {
      try {
        await fs.unlink(req.file.path);
        if (extractDir) await fs.rm(extractDir, { recursive: true, force: true });
      } catch (e) { /* ignore */ }
    }

    res.status(500).json({
      error: 'Game upload failed',
      details: error.message
    });
  }
});

// **MODERATION WEBHOOK REMOVED - Using Local Moderation Instead**

export default router;
