import express from 'express';
import { fileURLToPath } from 'url';
import path from 'path';

// Loaders
import loaders from './loaders/index.js';

// Services/Managers needed for shutdown and status
import databaseManager from './config/database.js';
import redisService from './services/caching/redisService.js';
import monthlyNotificationCron from './services/notificationServices/monthlyNotificationCron.js';
import recommendationScoreCron from './services/yugFeedServices/recommendationScoreCron.js';
import autoResumeCron from './workers/autoResume.js';
import { shutdownAdStatsBuffer } from './services/adServices/adStatsBuffer.js';

// **FIX: Don't disable console.log in production - we need it for Railway debugging**
if (process.env.DISABLE_CONSOLE_LOG === 'true') {
  // eslint-disable-next-line no-console
  console.log = () => { };
}

const app = express();

// ES Module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initial Environment Checks
const mongoUri = process.env.MONGO_URI;
if (!mongoUri) {
  console.warn('⚠️ Missing environment variable: MONGO_URI');
  console.warn('⚠️ Server will start but database features will be unavailable');
}

const PORT = parseInt(process.env.PORT, 10) || 5001;
const HOST = '0.0.0.0'; 

if (isNaN(PORT) || PORT < 1 || PORT > 65535) {
  console.error(`❌ Invalid PORT: ${PORT}. Must be 1-65535`);
  process.exit(1);
}

// Graceful shutdown logic
const gracefulShutdown = async (signal) => {
  console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);

  try {
    // Drain buffered ad counters BEFORE closing Mongo — Fly auto-stops idle
    // machines, so anything still in the buffer would be lost revenue.
    await shutdownAdStatsBuffer();

    // Stop cron jobs
    if (monthlyNotificationCron && monthlyNotificationCron.stop) monthlyNotificationCron.stop();
    if (recommendationScoreCron && recommendationScoreCron.stop) recommendationScoreCron.stop();
    if (autoResumeCron && autoResumeCron.stop) autoResumeCron.stop();

    // Disconnect Redis
    if (redisService.getConnectionStatus && redisService.getConnectionStatus()) {
      await redisService.disconnect();
    }

    // Disconnect database
    if (databaseManager.disconnect) {
      await databaseManager.disconnect();
    }

    console.log('✅ Graceful shutdown complete');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
};

// Handle shutdown signals
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start server
const startServer = async () => {
    try {
        console.log('🔍 Initializing loaders...');
        await loaders({ expressApp: app });
        console.log('✅ Loaders initialized');

        // Start auto-resume cron (resets Gemini/Groq quotas daily at 00:00 UTC)
        autoResumeCron.start();

        // Start HTTP server
        const server = app.listen(PORT, HOST, () => {
            const addr = server.address();
            console.log(`🚀 Server running on ${addr.address}:${addr.port}`);
            console.log('✅ Server is ready and healthy');
        });

        // Handle server binding errors
        server.on('error', (error) => {
            if (error.code === 'EADDRINUSE') {
                console.error(`❌ Port ${PORT} is already in use`);
                process.exit(1);
            } else if (error.code === 'EACCES') {
                console.error(`❌ Permission denied binding to port ${PORT}`);
                process.exit(1);
            } else {
                console.error(`❌ Server binding error: ${error.message}`);
                throw error;
            }
        });

    } catch (error) {
        console.error('❌ Failed to start server:', error);
        if (error.code === 'EADDRINUSE' || error.code === 'EACCES') {
            process.exit(1);
        }
    }
};

// Start the application
if (process.env.NODE_ENV !== 'test') {
  startServer().then(() => {
    // Start background video worker in same process if not explicitly disabled
    const shouldRunIntegratedWorker = (process.env.FLY_APP_NAME || process.env.NODE_ENV === 'production') &&
                                     process.env.DISABLE_INTEGRATED_WORKER !== 'true';
    if (shouldRunIntegratedWorker) {
      console.log('🎬 Starting integrated Video Worker...');
      import('./workers/videoWorker.js').catch(err => {
        console.error('❌ Failed to start integrated Video Worker:', err);
      });
    } else {
      console.log('ℹ️ Integrated Video Worker is disabled (running in decoupled worker process).');
    }
  });
} else {
  // In test mode, initialize loaders so supertest has access to all registered routes
  console.log('🧪 Test Mode: Initializing Express loaders in-memory...');
  await loaders({ expressApp: app });
  console.log('✅ Test Mode: Express loaders initialized');
}

export default app;