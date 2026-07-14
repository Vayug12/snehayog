import express from 'express';
import rateLimit from 'express-rate-limit';
import { verifyToken } from '../utils/verifytoken.js';
import { verifyWebhookSecret } from '../middleware/verifyWebhookSecret.js';
import * as videoGenController from '../controllers/videoGen/videoGenController.js';

const router = express.Router();

/**
 * Strict rate limit: max 5 video generations per hour per user
 */
const videoGenLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  keyGenerator: (req) => req.user?._id?.toString() || req.ip,
  message: { error: 'Too many video generation requests. Please try again after 1 hour.' }
});

/**
 * POST /api/video-gen/generate
 * Send a prompt to the AI agent to generate a video
 */
router.post('/generate', verifyToken, videoGenLimiter, videoGenController.generateVideo);

/**
 * GET /api/video-gen/status/:jobId
 * Get the current status of an AI video generation job (single poll).
 */
router.get('/status/:jobId', verifyToken, videoGenController.getJobStatus);

/**
 * GET /api/video-gen/stream/:jobId
 * SSE stream of job status — primary channel; client falls back to /status polling.
 */
router.get('/stream/:jobId', verifyToken, videoGenController.streamJobStatus);

/**
 * POST /api/video-gen/downloaded/:jobId
 * App confirms the MP4 was saved to gallery; delete the R2 download copy.
 */
router.post('/downloaded/:jobId', verifyToken, videoGenController.confirmDownloaded);

/**
 * POST /api/video-gen/webhook/:jobId
 * Called by the VayugAI agent (server-to-server) when generation finishes.
 * Authenticated by shared secret, NOT a user JWT.
 */
router.post('/webhook/:jobId', verifyWebhookSecret, videoGenController.handleAgentWebhook);

export default router;
