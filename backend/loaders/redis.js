import redisService from '../services/caching/redisService.js';

export default async () => {
  // In test mode, setup.js handles the redis connection
  if (process.env.NODE_ENV === 'test') {
    return redisService;
  }

  try {
    const redisConnected = await redisService.connect();
    if (redisConnected) {
      console.log('✅ Redis connected successfully - Caching enabled');
    } else {
      console.log('⚠️ Redis connection failed - App will continue without caching');
    }
    return redisService;
  } catch (error) {
    console.error('❌ Redis loader failed:', error.message);
    console.log('⚠️ App will continue without Redis caching');
    return null;
  }
};
