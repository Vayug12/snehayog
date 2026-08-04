// Backend Configuration File
export const config = {
  // Server Configuration
  server: {
    port: process.env.PORT || 5001,
    host: process.env.HOST || '0.0.0.0',
    environment: process.env.NODE_ENV || 'development'
  },

  // Database Configuration
  database: {
    uri: process.env.MONGO_URI || 'mongodb://localhost:27017/snehayog',
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      serverSelectionTimeoutMS: 5000,
      socketTimeoutMS: 45000
    }
  },

  // Authentication Configuration
  auth: {
    jwtSecret: process.env.JWT_SECRET || 'snehayog_jwt_secret_key_2024_change_in_production',
    googleClientId: process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com'
  },

  // File Upload Configuration
  upload: {
    maxFileSize: 700 * 1024 * 1024, // 700MB
    allowedVideoTypes: ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
    allowedImageTypes: ['jpg', 'jpeg', 'png', 'gif', 'webp']
  },

  // CORS Configuration
  cors: {
    origin: process.env.CORS_ORIGIN || ['http://localhost:3000', 'https://api.snehayog.site'],
    credentials: true
  },

};

// Helper function to get server URL
export const getServerUrl = () => {
  const { host, port } = config.server;
  return `http://${host}:${port}`;
};

// Helper function to get API base URL
export const getApiBaseUrl = () => {
  return `${getServerUrl()}/api`;
};

// Helper function to check if running in development
export const isDevelopment = () => {
  return config.server.environment === 'development';
};

// Helper function to check if running in production
export const isProduction = () => {
  return config.server.environment === 'production';
};

  // Cloudinary configuration check
export const isCloudinaryConfigured = () => {
  const cloudName = process.env.CLOUD_NAME;
  const apiKey = process.env.CLOUD_KEY;
  const apiSecret = process.env.CLOUD_SECRET;
  
  // Check if all required Cloudinary environment variables are set
  const isConfigured = !!(cloudName && apiKey && apiSecret);
  
  if (!isConfigured) {
    console.warn('⚠️ Cloudinary not properly configured - video uploads will fail');
    console.warn('   Missing environment variables:');
    if (!cloudName) console.warn('     - CLOUD_NAME');
    if (!apiKey) console.warn('     - CLOUD_KEY');
    if (!apiSecret) console.warn('     - CLOUD_SECRET');
  } else {
    console.log('✅ Cloudinary properly configured');
  }
  
  return isConfigured;
};

// Export default config
export default config;
