import User from '../../models/User.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// ES module equivalents of __filename/__dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Lazy-loaded firebase-admin instance
let admin = null;
let firebaseInitialized = false;

const initializeFirebase = async () => {
  if (firebaseInitialized) return;

  try {
    // Dynamic import — firebase-admin (~30MB) only loads when first notification is sent
    const firebaseAdmin = await import('firebase-admin');
    admin = firebaseAdmin.default;

    let serviceAccountJson = null;

    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
      try {
        serviceAccountJson = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
        console.log('✅ Firebase Admin: Loaded service account from FIREBASE_SERVICE_ACCOUNT env');
      } catch (e) {
        console.error('❌ Firebase Admin: Invalid FIREBASE_SERVICE_ACCOUNT JSON:', e.message);
      }
    }

    if (!serviceAccountJson) {
      try {
        const jsonPath = path.join(__dirname, '../../config/firebaseServiceAccount.json');
        if (fs.existsSync(jsonPath)) {
          const raw = fs.readFileSync(jsonPath, 'utf8');
          serviceAccountJson = JSON.parse(raw);
          console.log('✅ Firebase Admin: Loaded service account from firebaseServiceAccount.json');
        }
      } catch (e) {
        console.error('❌ Firebase Admin: Error reading firebaseServiceAccount.json:', e.message);
      }
    }

    if (!serviceAccountJson) {
      console.warn(
        '⚠️ Firebase Admin: No service account configured. Notifications will be disabled.'
      );
      return;
    }

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccountJson)
    });

    firebaseInitialized = true;
    console.log('✅ Firebase Admin initialized successfully');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin:', error.message);
    console.warn('⚠️ Push notifications will be disabled');
  }
};

/**
 * Send a batch of FCM tokens and clean up invalid ones
 */
const sendBatch = async (tokens, message) => {
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    ...message,
  });

  if (response.failureCount > 0) {
    const invalidTokens = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        invalidTokens.push(tokens[idx]);
      }
    });

    if (invalidTokens.length > 0) {
      await User.updateMany(
        { fcmToken: { $in: invalidTokens } },
        {
          $set: {
            fcmToken: null,
            isAppUninstalled: true,
            lastInstallCheck: new Date()
          }
        }
      );
      console.log(`🗑️ Removed ${invalidTokens.length} invalid FCM tokens and marked as uninstalled`);
    }
  }

  return { successCount: response.successCount, failureCount: response.failureCount };
};

/**
 * Build standard FCM message payload
 */
const buildMessage = (notification) => ({
  notification: {
    title: notification.title,
    body: notification.body,
  },
  data: notification.data || {},
  android: {
    priority: 'high',
    notification: {
      sound: 'default',
      channelId: 'default',
    },
  },
  apns: {
    payload: {
      aps: {
        sound: 'default',
      },
    },
  },
});

const BATCH_SIZE = 500;

/**
 * Send notification to a single user by their Google ID
 */
export const sendNotificationToUser = async (googleId, notification) => {
  await initializeFirebase();
  if (!firebaseInitialized) {
    console.warn('⚠️ Firebase not initialized. Cannot send notification.');
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const user = await User.findOne({ googleId });
    
    if (!user || !user.fcmToken) {
      return { 
        success: false, 
        error: 'User not found or no FCM token registered' 
      };
    }

    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      token: user.fcmToken,
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log('✅ Notification sent successfully:', response);
    
    return { success: true, messageId: response };
  } catch (error) {
    console.error('❌ Error sending notification:', error);
    
    // If token is invalid, remove it from user
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      await User.updateOne(
        { googleId },
        { 
          $set: { 
            fcmToken: null,
            isAppUninstalled: true,
            lastInstallCheck: new Date()
          } 
        }
      );
      console.log('🗑️ Removed invalid FCM token and marked as uninstalled for user:', googleId);
    }
    
    return { success: false, error: error.message };
  }
};

/**
 * Send notification to multiple users
 */
export const sendNotificationToUsers = async (googleIds, notification) => {
  await initializeFirebase();
  if (!firebaseInitialized) {
    console.warn('⚠️ Firebase not initialized. Cannot send notifications.');
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const message = buildMessage(notification);

    const cursor = User.find({
      googleId: { $in: googleIds },
      fcmToken: { $ne: null }
    }).select('fcmToken').batchSize(BATCH_SIZE).cursor();

    let tokens = [];
    let totalSuccess = 0;
    let totalFailure = 0;

    for await (const user of cursor) {
      if (user.fcmToken) tokens.push(user.fcmToken);

      if (tokens.length >= BATCH_SIZE) {
        const result = await sendBatch(tokens, message);
        totalSuccess += result.successCount;
        totalFailure += result.failureCount;
        tokens = [];
      }
    }

    if (tokens.length > 0) {
      const result = await sendBatch(tokens, message);
      totalSuccess += result.successCount;
      totalFailure += result.failureCount;
    }

    console.log(`✅ Sent ${totalSuccess} notifications, ${totalFailure} failed`);

    return {
      success: true,
      successCount: totalSuccess,
      failureCount: totalFailure
    };
  } catch (error) {
    console.error('❌ Error sending notifications:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Send notification to all users (broadcast)
 */
export const sendNotificationToAll = async (notification) => {
  await initializeFirebase();
  if (!firebaseInitialized) {
    console.warn('⚠️ Firebase not initialized. Cannot send notifications.');
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const message = buildMessage(notification);

    const cursor = User.find({
      fcmToken: { $ne: null }
    }).select('fcmToken').batchSize(BATCH_SIZE).cursor();

    let tokens = [];
    let totalSuccess = 0;
    let totalFailure = 0;

    for await (const user of cursor) {
      if (user.fcmToken) tokens.push(user.fcmToken);

      if (tokens.length >= BATCH_SIZE) {
        const result = await sendBatch(tokens, message);
        totalSuccess += result.successCount;
        totalFailure += result.failureCount;
        tokens = [];
      }
    }

    if (tokens.length > 0) {
      const result = await sendBatch(tokens, message);
      totalSuccess += result.successCount;
      totalFailure += result.failureCount;
    }

    console.log(`✅ Broadcast sent: ${totalSuccess} success, ${totalFailure} failed`);

    return {
      success: true,
      successCount: totalSuccess,
      failureCount: totalFailure
    };
  } catch (error) {
    console.error('❌ Error broadcasting notifications:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Verify if a user's app is still installed by checking their FCM token
 * Uses dry-run mode to validate the token without sending a real notification
 */
export const verifyInstallationStatus = async (googleId) => {
  await initializeFirebase();
  if (!firebaseInitialized) {
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const user = await User.findOne({ googleId });
    if (!user || !user.fcmToken) {
      console.log(`ℹ️ No FCM token found for user ${googleId}`);
      return { success: false, error: 'No FCM token' };
    }

    const message = {
      token: user.fcmToken,
      data: { ping: 'check' } // Silent data-only message
    };

    console.log(`🔌 Verifying installation for ${user.name} (${googleId})...`);
    const startTime = Date.now();
    
    // Use dryRun = true to only validate the token
    await admin.messaging().send(message, true);
    
    console.log(`✅ Verification successful for ${user.name} (${Date.now() - startTime}ms)`);
    
    // If successful, update user as installed
    await User.updateOne(
      { googleId },
      { 
        $set: { 
          isAppUninstalled: false,
          lastInstallCheck: new Date()
        } 
      }
    );

    return { success: true, isInstalled: true };
  } catch (error) {
    // If token is invalid/unregistered, mark as uninstalled
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      
      await User.updateOne(
        { googleId },
        { 
          $set: { 
            isAppUninstalled: true,
            lastInstallCheck: new Date()
          } 
        }
      );
      
      return { success: true, isInstalled: false };
    }

    console.error('❌ Error verifying install status:', error);
    return { success: false, error: error.message };
  }
};
