import express from 'express';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';
import * as uploadController from '../controllers/video/videoUploadController.js';
import * as feedController from '../controllers/video/videoFeedController.js';
import * as interactionController from '../controllers/video/videoInteractionController.js';
import * as managementController from '../controllers/video/videoManagementController.js';
import * as analyticsController from '../controllers/video/videoAnalyticsController.js';
import { validateVideoData, upload } from '../middleware/videoMiddleware.js';
import rateLimit from 'express-rate-limit';

const router = express.Router();

// Rate limiter for video uploads
const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // limit each IP to 10 uploads per window
  message: 'Too many video uploads from this IP, please try again after 15 minutes'
});

/**
 * Cache Management Routes
 */
router.get('/cache/status', analyticsController.getCacheStatus);
router.post('/cache/clear', analyticsController.clearCache);

/**
 * Video Upload & Processing Routes
 */
router.post('/check-duplicate', verifyToken, uploadController.checkDuplicate);
router.post('/upload', verifyToken, uploadLimiter, validateVideoData, upload.single('video'), uploadController.uploadVideo);
router.post('/register-upload', verifyToken, uploadController.registerUpload);
router.post('/r2-callback', uploadController.r2Callback);
router.post('/image', verifyToken, uploadController.createImageFeedEntry);

/**
 * Video Retrieval Routes
 */
router.get('/', feedController.getFeed);
// **MUST stay above '/:id'** — Express would otherwise match 'following' as an id
router.get('/following', verifyToken, feedController.getFollowingFeed);
router.get('/user/:googleId', passiveVerifyToken, feedController.getUserVideos);
router.get('/saved', verifyToken, interactionController.getSavedVideos);
router.get('/removed', verifyToken, feedController.getRemovedVideos);
router.get('/:id', feedController.getVideoById);
router.get('/creator/analytics/:userId', verifyToken, analyticsController.getCreatorAnalytics);


/**
 * Video Interaction Routes
 */
router.post('/:id/save', verifyToken, interactionController.toggleSave);
router.post('/sync-watch-history', verifyToken, interactionController.syncWatchHistory);
router.post('/watch/batch', passiveVerifyToken, interactionController.syncWatchEvents);
router.post('/:id/watch', passiveVerifyToken, interactionController.trackWatch);
router.post('/:id/skip', passiveVerifyToken, interactionController.trackSkip);
router.post('/:id/like', verifyToken, interactionController.toggleLike);
router.delete('/:id/like', verifyToken, interactionController.deleteLike);
router.post('/:id/increment-view', interactionController.incrementView);

/**
 * Video Deletion Routes
 */
router.delete('/:id', verifyToken, managementController.deleteVideo);
router.patch('/:id', verifyToken, managementController.updateVideo);
router.post('/:id/series', verifyToken, managementController.updateVideoSeries);
router.post('/bulk-delete', verifyToken, managementController.bulkDeleteVideos);

/**
 * Utility & Cleanup Routes
 */
router.post('/cleanup-temp-hls', managementController.cleanupTempHLS);
router.post('/generate-signed-url', verifyToken, managementController.generateSignedUrl);
router.get('/cloudinary-config', managementController.getCloudinaryConfig);
router.post('/cleanup-orphaned', managementController.cleanupOrphaned);
router.post('/cleanup-broken-videos', managementController.cleanupBrokenVideos);
router.post('/sync-user-video-arrays', managementController.syncUserVideoArrays);

export default router;
