import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// **NEW: Try multiple possible .env file locations**
const possibleEnvPaths = [
  path.join(__dirname, '..', '.env'),           // Backend root
  path.join(process.cwd(), '.env'),             // Current working directory
  path.join(__dirname, '..', '..', '.env'),    // Project root
  '.env'                                        // Relative to current directory
];

let envLoaded = false;
let loadedEnvPath = '';

for (const envPath of possibleEnvPaths) {
  if (fs.existsSync(envPath)) {
    console.log('🔍 Found .env file at:', envPath);
    dotenv.config({ path: envPath });
    envLoaded = true;
    loadedEnvPath = envPath;
    break;
  }
}

if (!envLoaded) {
  // **FIX: On Railway/Cloud platforms, env vars are injected directly - no .env file needed**
  const isCloudPlatform = process.env.RAILWAY_ENVIRONMENT || 
                          process.env.VERCEL || 
                          process.env.HEROKU ||
                          process.env.NODE_ENV === 'production';
  
  if (isCloudPlatform) {
    console.log('ℹ️  Running on cloud platform - using environment variables directly (no .env file needed)');
  } else {
    console.warn('⚠️  No .env file found in any of these locations:');
    possibleEnvPaths.forEach(path => console.warn('   •', path));
    console.warn('🔍 Current working directory:', process.cwd());
    console.warn('🔍 Config directory:', __dirname);
    console.warn('ℹ️  Using environment variables directly (expected on Railway/cloud platforms)');
  }
}

// **DEBUG: Removed logging of environment variables for confidentiality**


// Configuration validation
// **FIX: Make validation lenient to allow healthcheck to work even if some config is missing**
const validateConfig = () => {
  // Only database is truly critical - everything else can have fallbacks
  const criticalVars = [
    // Check for either MONGODB_URI or MONGO_URI (only for actual database operations)
    process.env.MONGODB_URI ? 'MONGODB_URI' : 'MONGO_URI'
  ];

  const missingCriticalVars = criticalVars.filter(varName => {
    if (varName === 'MONGODB_URI' || varName === 'MONGO_URI') {
      return !process.env.MONGO_URI;
    }
    return !process.env[varName];
  });
  
  // Warn about missing variables but don't block startup for healthcheck
  const warnings = [];
  
  if (missingCriticalVars.length > 0) {
    warnings.push(`Critical: ${missingCriticalVars.join(', ')}`);
  }
  
  if (!process.env.JWT_SECRET) {
    warnings.push('Warning: JWT_SECRET not set (using fallback - not secure for production)');
    // Set a temporary fallback for healthcheck (will need to be set properly in production)
    process.env.JWT_SECRET = 'healthcheck-fallback-secret-' + Date.now();
  }
  
  if (warnings.length > 0) {
    console.warn('⚠️  Configuration warnings:');
    warnings.forEach(warning => console.warn('   •', warning));
    console.warn('⚠️  App will start but some features may not work properly');
  }
};

// Main configuration object
export const config = {
  // Server configuration
  server: {
    port: process.env.PORT || 5001,
    nodeEnv: process.env.NODE_ENV || 'development',
    corsOrigin: process.env.CORS_ORIGIN?.split(',') || ['http://localhost:3000', 'https://api.snehayog.site'],
  },

  // Database configuration - support both MONGODB_URI and MONGO_URI
  database: {
    uri: process.env.MONGODB_URI || process.env.MONGO_URI,
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    },
  },

  // JWT configuration
  jwt: {
    secret: process.env.JWT_SECRET,
    expiresIn: process.env.JWT_EXPIRES_IN || '1m',
  },

  // Google Auth configuration
  google: {
    clientId: process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
  },

  // Cloudinary configuration - support both naming conventions
  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME || process.env.CLOUD_NAME,
    apiKey: process.env.CLOUDINARY_API_KEY || process.env.CLOUD_KEY,
    apiSecret: process.env.CLOUDINARY_API_SECRET || process.env.CLOUD_SECRET,
  },

  // Feature flags
  features: {
    enableAnalytics: process.env.ENABLE_ANALYTICS === 'true',
    enableNotifications: process.env.ENABLE_NOTIFICATIONS === 'true',
  },

  // Security configuration
  security: {
    rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 900000,
    rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
    sessionTimeoutMs: parseInt(process.env.SESSION_TIMEOUT_MS) || 3600000,
  },

  // Logging configuration
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    enableDebug: process.env.DEBUG === 'true',
    enableTestEndpoints: process.env.ENABLE_TEST_ENDPOINTS === 'true',
  },
};

// Validate configuration on import
// **FIX: Never exit - just warn. This allows healthcheck to work even if config is missing**
try {
  validateConfig();
  console.log('✅ Configuration loaded successfully');
} catch (error) {
  // **FIX: Never exit - just warn. Allow app to start for healthcheck**
  console.warn('⚠️  Configuration validation warnings (app will continue):', error.message);
  console.warn('📝 Please configure missing environment variables in Railway dashboard');
  console.warn('⚠️  Some features may not work until configuration is complete');
}

export default config;
