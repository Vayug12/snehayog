import express from 'express';
import cors from 'cors';
import path from 'path';
import compression from 'compression';
import morgan from 'morgan';
import { fileURLToPath } from 'url';

// Import routes
import videoRoutes from '../routes/videoRoutes.js';
import userRoutes from '../routes/userRoutes.js';
import authRoutes from '../routes/authRoutes.js';
import adRoutes from '../routes/adRoutes/index.js';
import creatorPayoutRoutes from '../routes/billing/creatorPayoutRoutes.js';
import adminRoutes from '../routes/adminRoutes.js';
import feedbackRoutes from '../routes/feedback/feedbackRoutes.js';
import referralRoutes from '../routes/referralRoutes.js';
import reportRoutes from '../routes/report/reportRoutes.js';
import notificationRoutes from '../routes/notification/notificationRoutes.js';
import searchRoutes from '../routes/searchRoutes.js';
import appConfigRoutes from '../routes/appConfigRoutes.js';
import systemRoutes from '../routes/systemRoutes.js';
// uploadRoutes → LAZY loaded (only when /upload is hit)
import dubbingRoutes from '../routes/dubbingRoutes.js';
import e2eeRoutes from '../routes/e2ee/e2eeRoutes.js';
import agentRoutes from '../routes/agentRoutes.js';
import videoGenRoutes from '../routes/videoGenRoutes.js';

// Import middleware
import { errorHandler, notFoundHandler } from '../middleware/errorHandler.js';
import { apiVersioning } from '../middleware/apiVersioning.js';
import { versionTracking } from '../middleware/versionTracking.js';
import { globalLimiter, apiLimiter } from '../middleware/rateLimiter.js';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';
import { traceMiddleware } from '../middleware/traceMiddleware.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.join(__dirname, '..');

const createCacheMiddleware = (cacheHeader) => (req, res, next) => {
  if (req.method !== 'GET') {
    return next();
  }
  if (req.headers.authorization && !cacheHeader.includes('public')) {
    return next();
  }
  res.set('Cache-Control', cacheHeader);
  res.set('Vary', 'Authorization');
  return next();
};

export default async ({ app }) => {
  // App settings
  app.set('etag', 'strong');

  // Middleware
  app.use(traceMiddleware);
  app.use(compression());
  app.use(express.static(path.join(backendRoot, 'public')));
  app.use('/.well-known', express.static(path.join(backendRoot, 'public/.well-known')));

  // CORS Configuration
  app.use(cors({
    origin: function (origin, callback) {
      if (!origin) return callback(null, true);

      const allowedOrigins = [
        'https://snehayog.site',
        'https://vayug.fly.dev',
        'http://localhost',
        'http://localhost:5001',
        'http://localhost:8080',
        /^http:\/\/localhost:\d+$/,
        'http://127.0.0.1',
        /^http:\/\/127\.0\.0\.1:\d+$/,
        'http://10.164.35.18/:5001',
        'http://172.20.10.2:5001',
        'http://10.78.84.104:5001',
        'http://192.168.0.198:5001',
        'http://10.78.84.18:5001',
        /^http:\/\/192\.168\.\d+\.\d+:\d+$/,
        'http://10.0.2.2:5001',
      ];

      const isAllowed = allowedOrigins.some(allowed => {
        if (allowed instanceof RegExp) return allowed.test(origin);
        return allowed === origin;
      });

      if (isAllowed) {
        callback(null, true);
      } else {
        if (process.env.NODE_ENV === 'development' || !process.env.NODE_ENV) {
          callback(null, true);
        } else {
          callback(new Error('Not allowed by CORS'));
        }
      }
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
    allowedHeaders: [
      'Content-Type', 'Authorization', 'X-Requested-With', 'Accept', 'Origin',
      'Access-Control-Request-Method', 'Access-Control-Request-Headers',
      'x-admin-key', 'X-Admin-Key', 'x-api-version', 'X-API-Version',
      'x-device-id', 'X-Device-ID', 'x-api-key', 'X-API-Key',
      'x-trace-id', 'X-Trace-ID',
      'x-app-screen', 'X-App-Screen', 'x-feature', 'X-Feature',
      'x-ui-action', 'X-UI-Action',
      'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-RateLimit-Reset', 'Retry-After'
    ],
    exposedHeaders: ['Content-Length', 'Content-Range', 'Accept-Ranges', 'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'Retry-After'],
    maxAge: 86400
  }));

  // Apply Global Rate Limiter
  app.use(globalLimiter);

  // Body Parsing
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // Strip redundant /api prefixes
  app.use((req, res, next) => {
    if (req.url.startsWith('/api/api')) {
      req.url = req.url.replace(/^\/api(\/api)+/, '/api');
    }
    next();
  });

  // Logging
  morgan.token('trace-id', (req) => req.traceId || '-');
  morgan.token('app-screen', (req) => req.get('x-app-screen') || '-');
  morgan.token('feature', (req) => req.get('x-feature') || '-');
  morgan.token('ui-action', (req) => req.get('x-ui-action') || '-');

  if (process.env.NODE_ENV === 'production') {
    app.use(morgan(':remote-addr - :remote-user [:date[clf]] ":method :url HTTP/:http-version" :status :res[content-length] ":referrer" ":user-agent" - :response-time ms trace=:trace-id screen=:app-screen feature=:feature action=:ui-action'));
  } else {
    app.use(morgan('dev trace=:trace-id screen=:app-screen feature=:feature action=:ui-action'));
  }

  // Static files serving
  app.use('/uploads', express.static(path.join(backendRoot, 'uploads')));
  app.use('/admin', express.static(path.join(backendRoot, 'admin')));

  // HLS serving
  app.use('/hls', (req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Range, Accept-Ranges, Content-Range');
    res.setHeader('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');

    if (req.path.endsWith('.m3u8')) {
      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
    } else if (req.path.endsWith('.ts')) {
      res.setHeader('Content-Type', 'video/mp2t');
    }
    next();
  }, express.static(path.join(backendRoot, 'uploads/hls'), {
    fallthrough: false,
    setHeaders: (res, path) => {
      if (path.endsWith('.m3u8')) {
        res.setHeader('Cache-Control', 'public, max-age=300');
      } else if (path.endsWith('.ts')) {
        res.setHeader('Cache-Control', 'public, max-age=86400');
      }
    }
  }));

  // API Routes
  app.use('/api/app-config', appConfigRoutes);

  const apiRouter = express.Router();
  apiRouter.use('/users', userRoutes);
  apiRouter.use('/auth', authRoutes);
  apiRouter.use('/ads', createCacheMiddleware('public, max-age=180, stale-while-revalidate=600'), adRoutes);
  apiRouter.use('/creator-payouts', creatorPayoutRoutes);
  apiRouter.use('/videos', createCacheMiddleware('public, max-age=180, stale-while-revalidate=600'), videoRoutes);
  apiRouter.use('/admin', adminRoutes);

  // LAZY: uploadRoutes — @aws-sdk, bullmq, adm-zip sirf upload pe load hoga
  let _uploadRouter = null;
  apiRouter.use('/upload', async (req, res, next) => {
    if (!_uploadRouter) {
      const mod = await import('../routes/uploadRoutes/uploadRoutes.js');
      _uploadRouter = mod.default;
    }
    _uploadRouter(req, res, next);
  });

  apiRouter.use('/feedback', feedbackRoutes);
  apiRouter.use('/referrals', referralRoutes);
  apiRouter.use('/report', reportRoutes);
  apiRouter.use('/notifications', notificationRoutes);
  apiRouter.use('/search', searchRoutes);
  apiRouter.use('/dubbing', dubbingRoutes);
  apiRouter.use('/e2ee', e2eeRoutes);
  apiRouter.use('/agent', agentRoutes);
  apiRouter.use('/video-gen', videoGenRoutes);

  // Apply Passive Auth BEFORE Rate Limiter
  app.use('/api', apiVersioning, passiveVerifyToken, versionTracking, apiLimiter, apiRouter);

  // System Routes (APK, ads.txt, health, landing page)
  app.use(systemRoutes);

  // 404 handler
  app.use(notFoundHandler);

  // Error handling middleware
  app.use(errorHandler);

  console.log('✅ Express configured');
};
