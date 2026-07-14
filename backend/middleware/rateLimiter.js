import rateLimit from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';
import redisService from '../services/caching/redisService.js';

/**
 * Rate Limiter Configuration
 * Implements a tiered hybrid approach:
 * - Uses Redis for distributed storage (persists across restarts/instances)
 * - Hybrid Keying: Uses User ID if logged in, IP otherwise (Solves shared Wi-Fi)
 */

// Helper to create a store linked to our existing Redis service
const getStore = (prefix) => {
  // If Redis is not connected yet (common at startup), we return undefined.
  // express-rate-limit will then use the default MemoryStore.
  // We've improved the startup sequence in loaders/index.js to minimize this.
  if (!redisService.getConnectionStatus()) {
    return undefined;
  }

  return new RedisStore({
    sendCommand: (...args) => redisService.call(...args),
    prefix: `rate_limit:${prefix}:`,
  });
};

// Key Generator: The core logic for "Smart" limiters
// Prioritizes User ID > IP Address
const keyGenerator = (req) => {
  if (req.user) {
    // Prefer Google ID as it's the stable external ID
    if (req.user.googleId) return req.user.googleId.toString();
    if (req.user._id) return req.user._id.toString();
    if (req.user.id) return req.user.id.toString();
  }
  return req.ip; // Limit per IP Address (Guest/Login)
};

// Unified Error Handler
const handler = (req, res, next, options) => {
  res.status(options.statusCode).json({
    error: 'Too Many Requests',
    message: options.message,
    retryAfter: Math.ceil(options.windowMs / 1000) + ' seconds'
  });
};

// 1. GLOBAL LIMITER (Catch-all Safety Net)
// Applies to everything to prevent total server crash
export const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 20000, // **INCREASED**: 20000 requests per IP (User requested 4x increase)
  // This is just a safety net for DoS. The specific API limiters handle per-user logic.
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('global'),
  message: 'Too many requests from this IP, please try again later.',
  handler: handler,
  skip: (req) => {
    // **FIX: Skip rate limiting in test mode**
    if (process.env.NODE_ENV === 'test') return true;
    // Skip static files/HLS which are naturally high-volume
    if (req.path.startsWith('/hls') || req.path.startsWith('/uploads')) return true;
    return false;
  }
});

// 2. STANDARD API LIMITER (General Usage)
// Generous limit for normal app usage (feed scrolling, etc.)
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 4000, // **INCREASED**: 4000 requests per 15 mins (User requested 4x increase)
  // vayu-feed scroll consumes ~10 requests per scroll.
  // 4000 allows for very heavy usage without blocking legit users.
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('api'),
  keyGenerator: keyGenerator, // Use User ID if available
  message: 'You are sending too many requests. Please slow down.',
  handler: handler,
});

// 3. STRICT AUTH LIMITER (Login/Register/OTP)
// Strict limit to prevent brute-force password guessing
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 60, // **INCREASED**: 60 attempts (Slightly more headroom for active sessions)
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('auth'),
  message: 'Too many login attempts. Please try again in 15 minutes.',
  handler: handler,
});

// Phone OTP sends cost money, so keep this substantially stricter than Google login.
export const phoneOtpSendLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('phone_otp_send'),
  message: 'Too many OTP requests. Please wait before trying again.',
  handler: handler,
});

export const phoneOtpVerifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('phone_otp_verify'),
  message: 'Too many OTP verification attempts. Please wait before trying again.',
  handler: handler,
});

// 3.1 REFRESH LIMITER: More lenient for background token rotation
export const refreshLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100, // Background refreshes can be frequent in multi-tab/active usage
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('refresh'),
  keyGenerator: keyGenerator,
  message: 'Too many session refresh requests. Please slow down.',
  handler: handler,
});

// 4. UPLOAD LIMITER (Heavy Operations)
// Prevents storage exhaustion and bandwidth abuse
export const uploadLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 15, // **INCREASED**: 15 uploads per minute (Was 5, increased to handle retries/polling better)
  standardHeaders: true,
  legacyHeaders: false,
  store: getStore('upload'),
  keyGenerator: keyGenerator, // Use User ID (Users must be logged in to upload)
  message: 'Upload limit reached. You can only upload 5 videos per minute.',
  handler: handler,
});
