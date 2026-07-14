import express from 'express';
import { 
  googleSignIn, 
  refreshAccessToken, 
  logout, 
  logoutAllDevices, 
  getActiveSessions,
  checkDeviceId,
  recoverSession
} from '../controllers/authController.js';
import { authLimiter, refreshLimiter } from '../middleware/rateLimiter.js';
import { phoneOtpSendLimiter, phoneOtpVerifyLimiter } from '../middleware/rateLimiter.js';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';
import { requestPhoneOtp, verifyPhoneOtp } from '../controllers/phoneAuthController.js';

const router = express.Router();

/**
 * Public Auth Routes (No auth required)
 */

// Google Sign-In (first-time login / re-authentication)
router.post('/', authLimiter, googleSignIn);
router.post('/google', authLimiter, googleSignIn);

// Phone Sign-In. Verification accepts an optional existing Vayu JWT so a
// signed-in Google user can link the verified number instead of creating a duplicate.
router.post('/phone/request', phoneOtpSendLimiter, requestPhoneOtp);
router.post('/phone/verify', phoneOtpVerifyLimiter, passiveVerifyToken, verifyPhoneOtp);

// Silent session recovery using Google Refresh Token (Tier 4)
router.post('/recover-session', authLimiter, recoverSession);

// Device Auto-Login (after app reinstall)
// router.post('/device-login', authLimiter, deviceLogin);

// Refresh Access Token
router.post('/refresh', refreshLimiter, refreshAccessToken);

// Legacy: Check if device has logged in before
router.post('/check-device', authLimiter, checkDeviceId);

/**
 * Protected Auth Routes (Auth required)
 */

// Logout current device
router.post('/logout', verifyToken, logout);

// Logout all devices
router.post('/logout-all', verifyToken, logoutAllDevices);

// Get active sessions
router.get('/sessions', verifyToken, getActiveSessions);

export default router;
