import 'dotenv/config';
import databaseManager from '../config/database.js';
import redisService from '../services/caching/redisService.js';
import FeedQueueService from '../services/yugFeedServices/queueService.js';
import socialPublishingQueue from '../services/socialQueue.js';
import mongoose from 'mongoose';

/**
 * 🧪 GLOBAL TEST SETUP
 * 
 * This file runs before every test suite. It ensures that 
 * MongoDB and Redis are connected so that tests don't time out.
 */

// Ensure NODE_ENV is set for server.js conditional logic
process.env.NODE_ENV = 'test';

beforeAll(async () => {
  console.log('🧪 Test Setup: Connecting to databases...');
  
  // 1. Ensure we use a separate test database to avoid messing up dev data
  const originalUri = process.env.MONGO_URI;
  if (!originalUri.includes('_test')) {
     // Append _test to the database name if not already there
     // This is a safety measure
     const parts = originalUri.split('/');
     const dbName = parts.pop().split('?')[0];
     process.env.MONGO_URI = originalUri.replace(dbName, 'snehayog_test');
  }

  // 2. Connect to MongoDB
  await databaseManager.connect();
  
  // 3. Connect to Redis
  await redisService.connect();
  
  console.log('✅ Test Setup: Databases ready');
});

afterAll(async () => {
  console.log('🧪 Test Teardown: Cleaning up...');
  
  // 1. Disconnect MongoDB
  if (databaseManager.getConnectionStatus().isConnected) {
    await databaseManager.disconnect();
  }
  
  // 2. Disconnect Redis & Queues
  await FeedQueueService.close();
  try {
    await socialPublishingQueue.close();
  } catch (error) {
    // Silently fail if already closed
  }
  if (redisService.getConnectionStatus()) {
    await redisService.disconnect();
  }

  // Double check mongoose shutdown
  await mongoose.disconnect();
  
  console.log('✅ Test Teardown: Complete');
});
