import express from 'express';
import multer from 'multer';
import { verifyToken } from '../utils/verifytoken.js';
import * as agentUploadController from '../controllers/agent/agentUploadController.js';
import rateLimit from 'express-rate-limit';

const router = express.Router();

const agentUploadLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 50,
  message: { error: 'Too many agent uploads, please try again after 1 hour' }
});

/**
 * Multer error handler middleware
 */
const handleMulterError = (err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({
        error: 'File too large. Maximum size for direct upload is 400MB.',
        maxSize: '400MB',
        hint: 'For larger files, use presigned URL upload instead.'
      });
    }
    if (err.code === 'LIMIT_UNEXPECTED_FILE') {
      return res.status(400).json({ error: 'Unexpected field name. Use "video" as the field name.' });
    }
    return res.status(400).json({ error: `Upload error: ${err.message}` });
  }

  if (err && err.statusCode === 400 && err.message?.includes('Invalid file type')) {
    return res.status(400).json({
      error: err.message,
      allowed: ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm']
    });
  }

  if (err && err.message?.includes('Failed to create upload directory')) {
    return res.status(500).json({ error: 'Server configuration error. Please try again later.' });
  }

  next(err);
};

router.get('/upload/presigned-url', verifyToken, agentUploadController.getPresignedUrl);

router.post('/upload/register', verifyToken, agentUploadLimiter, agentUploadController.registerUpload);

router.post('/upload/direct',
  verifyToken,
  agentUploadLimiter,
  (req, res, next) => {
    agentUploadController.agentUpload.single('video')(req, res, (err) => {
      if (err) return handleMulterError(err, req, res, next);
      next();
    });
  },
  agentUploadController.directUpload
);

router.get('/upload/status/:videoId', verifyToken, agentUploadController.getUploadStatus);

router.get('/upload/status/sse/:videoId', verifyToken, agentUploadController.streamUploadStatus);

export default router;
