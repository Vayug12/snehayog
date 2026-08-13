import { verifyGoogleToken, generateJWT } from '../utils/verifytoken.js';
import User from '../models/User.js';
import RefreshToken from '../models/RefreshToken.js';
import AnonymousDevice from '../models/AnonymousDevice.js';
import brevoService from '../services/notificationServices/brevoService.js';
import { OAuth2Client } from 'google-auth-library';

/**
 * Google Sign-In (First Time / Re-authentication)
 * Verifies Google ID Token, creates/finds user, issues device-bound tokens
 */
export const googleSignIn = async (req, res) => {
  const { idToken, serverAuthCode, deviceId, deviceName, platform, appVersion } = req.body;

  try {
    if (!idToken) {
      return res.status(400).json({ error: 'Google ID Token is required' });
    }

    // Verify Google ID Token
    const userData = await verifyGoogleToken(idToken);
    console.log('🔐 Google Sign-In: Verified user');

    // **Tier 4 Google Offline Access: Exchange serverAuthCode for Google Refresh Token**
    let googleRefreshToken = null;
    if (serverAuthCode) {
      try {
        const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';
        const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
        
        const oauth2Client = new OAuth2Client(
          GOOGLE_CLIENT_ID,
          GOOGLE_CLIENT_SECRET,
          'postmessage'
        );
        const { tokens } = await oauth2Client.getToken(serverAuthCode);
        if (tokens.refresh_token) {
          googleRefreshToken = tokens.refresh_token;
          console.log('✅ Google Offline Access: Acquired Google Refresh Token');
        }
      } catch (err) {
        console.error('⚠️ Google Offline Access: Failed to exchange serverAuthCode:', err.message);
      }
    }

    // Find or create user
    let user = await User.findOne({ googleId: userData.sub })
      .select('googleId name email profilePic videos appVersion googleRefreshToken');
    
    let isNewUser = false;

    if (!user) {
      isNewUser = true;
      user = new User({
        googleId: userData.sub,
        name: userData.name,
        email: userData.email,
        profilePic: userData.picture,
        videos: [],
        lastActive: new Date(),
        isAppUninstalled: false,
        appVersion: appVersion || 'unknown',
        googleRefreshToken: googleRefreshToken || undefined
      });
      await user.save();
      console.log('✅ Created new user:', user.email);

      // **AUTOMATION: Send Welcome Email via Brevo**
      brevoService.sendWelcomeEmail(user.email, user.name).catch(err => {
        console.error('⚠️ Brevo: Failed to send welcome email to', user.email, err.message);
      });
    } else {
      // Update profile pic if missing, update lastActive and isAppUninstalled
      user.lastActive = new Date();
      user.isAppUninstalled = false;
      
      if (!user.profilePic || user.profilePic.trim() === '') {
        user.profilePic = userData.picture;
      }
      if (appVersion) {
        user.appVersion = appVersion;
      }
      if (googleRefreshToken) {
        user.googleRefreshToken = googleRefreshToken;
      }
      await user.save();
      console.log('✅ Found existing user:', user.email);
    }

    // Generate Access Token (JWT, 30 days)
    const accessToken = generateJWT(user.googleId, '30d');

    // Generate Device-Bound Refresh Token (stored in MongoDB)
    const refreshToken = await RefreshToken.createForDevice(
      user._id,
      deviceId,
      deviceName || 'Unknown Device',
      platform || 'unknown'
    );

    console.log('🔐 Issued tokens for device:', deviceId?.substring?.(0, 8) + '...');

    // **NEW: Merge Guest History from Device ID to User ID**
    if (deviceId && deviceId !== 'anon') {
      import('../services/yugFeedServices/feedQueueService.js').then(module => {
        const FeedQueueService = module.default;
        FeedQueueService.mergeGuestHistory(deviceId, user.googleId).catch(err => {
          console.error('⚠️ AuthController: mergeGuestHistory error:', err.message);
        });
      });

      // **NEW: Merge anonymous device attribution to user**
      try {
        const anonymousDevice = await AnonymousDevice.findOne({ deviceId: deviceId.trim() });
        if (anonymousDevice && anonymousDevice.attribution && anonymousDevice.attribution.source) {
          anonymousDevice.mergedToUser = user.googleId;
          await anonymousDevice.save();
          console.log(`✅ Attribution merged: device ${deviceId.substring(0, 8)}... → user ${user.googleId}`);
        }
      } catch (attrErr) {
        console.error('⚠️ AuthController: attribution merge error:', attrErr.message);
      }
    }

    res.json({
      accessToken,
      refreshToken,
      user: {
        id: user.googleId,
        _id: user._id,
        googleId: user.googleId,
        name: user.name,
        email: user.email,
        profilePic: user.profilePic,
        videos: user.videos,
        isNewUser
      }
    });

  } catch (error) {
    console.error('❌ Google Sign-In error:', error);
    res.status(400).json({ error: 'Google Sign-In failed', details: error.message });
  }
};

/**
 * Device Login (Auto-login after app reinstall)
 * Uses device ID to find existing session and issue new tokens
 */
export const deviceLogin = async (req, res) => {
  res.status(410).json({ error: 'Device login is no longer supported. Please use Google Sign-In.' });
};
/*
export const deviceLogin = async (req, res) => {
  const { deviceId } = req.body;
  // ... (rest of the code)
};
*/

/**
 * Refresh Access Token
 * Uses refresh token + device ID to issue new tokens
 */
export const refreshAccessToken = async (req, res) => {
  const { refreshToken, deviceId } = req.body;

  try {
    if (!refreshToken) {
      return res.status(401).json({ error: 'Refresh token required' });
    }

    // Verify and rotate refresh token (deviceId no longer required for rotation check)
    const result = await RefreshToken.verifyAndRotate(refreshToken);

    if (!result) {
      console.log('❌ Invalid or expired refresh token');
      return res.status(403).json({ 
        error: 'Invalid or expired refresh token',
        requiresLogin: true 
      });
    }

    const { newToken: newRefreshToken, user } = result;

    // Generate new Access Token (30 days)
    const accessToken = generateJWT(user.googleId, '30d');

    console.log('✅ Token refreshed for:', user.email);

    res.json({
      accessToken,
      refreshToken: newRefreshToken
    });

  } catch (error) {
    console.error('❌ Refresh token error:', error);
    res.status(500).json({ error: 'Failed to refresh token' });
  }
};

/**
 * Logout (Current Device)
 * Revokes refresh token for the current device
 */
export const logout = async (req, res) => {
  const { deviceId } = req.body;
  const googleId = req.user?.googleId;

  try {
    if (!googleId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const user = await User.findOne({ googleId }).select('_id');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (deviceId) {
      const count = await RefreshToken.revokeForDevice(user._id, deviceId);
      console.log(`✅ Revoked ${count} token(s) for device`);
    }

    res.json({ success: true, message: 'Logged out successfully' });

  } catch (error) {
    console.error('❌ Logout error:', error);
    res.status(500).json({ error: 'Logout failed' });
  }
};

/**
 * Logout All Devices
 * Revokes all refresh tokens for the user
 */
export const logoutAllDevices = async (req, res) => {
  const googleId = req.user?.googleId;

  try {
    if (!googleId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const user = await User.findOne({ googleId }).select('_id');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const count = await RefreshToken.revokeAllForUser(user._id);
    console.log(`✅ Revoked ${count} token(s) for user ${googleId}`);

    res.json({ success: true, message: `Logged out from ${count} device(s)` });

  } catch (error) {
    console.error('❌ Logout all error:', error);
    res.status(500).json({ error: 'Logout failed' });
  }
};

/**
 * Get Active Sessions
 * Returns list of devices with active sessions
 */
export const getActiveSessions = async (req, res) => {
  const googleId = req.user?.googleId;

  try {
    if (!googleId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const user = await User.findOne({ googleId }).select('_id');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const sessions = await RefreshToken.getActiveSessions(user._id);

    res.json({
      sessions: sessions.map(s => ({
        deviceId: s.deviceId,
        deviceName: s.deviceName,
        platform: s.platform,
        createdAt: s.createdAt,
        lastUsedAt: s.lastUsedAt
      }))
    });

  } catch (error) {
    console.error('❌ Get sessions error:', error);
    res.status(500).json({ error: 'Failed to get sessions' });
  }
};

// Legacy endpoint - kept for backward compatibility during migration
export const checkDeviceId = async (req, res) => {
  const { platformId, deviceId } = req.body;
  const identifier = platformId || deviceId;

  try {
    if (!identifier || identifier.trim() === '') {
      return res.status(400).json({ 
        error: 'Device ID is required',
        hasLoggedIn: false 
      });
    }

    // Check RefreshToken collection first (new system)
    const session = await RefreshToken.findValidSessionByDevice(identifier);
    
    if (session && session.userId) {
      const user = session.userId;
      return res.json({
        hasLoggedIn: true,
        userId: user.googleId,
        userName: user.name,
        userEmail: user.email,
        profilePic: user.profilePic
      });
    }

    // Fallback: Check legacy deviceIds array in User model
    const user = await User.findOne({ deviceIds: identifier })
      .select('googleId name email profilePic');

    if (user) {
      return res.json({
        hasLoggedIn: true,
        userId: user.googleId,
        userName: user.name,
        userEmail: user.email,
        profilePic: user.profilePic
      });
    }

    return res.json({ hasLoggedIn: false });

  } catch (error) {
    console.error('Check Device ID error:', error);
    res.status(500).json({ error: 'Check failed', hasLoggedIn: false });
  }
};

/**
 * Recover Session (Tier 4 Google Offline Access)
 * Exchanges stored googleRefreshToken directly with Google for a fresh token
 * and issues new local access/refresh tokens.
 */
export const recoverSession = async (req, res) => {
  const { googleId, deviceId, deviceName, platform } = req.body;

  try {
    if (!googleId) {
      return res.status(400).json({ error: 'Google ID is required' });
    }

    const user = await User.findOne({ googleId })
      .select('_id googleId email googleRefreshToken');

    if (!user || !user.googleRefreshToken) {
      console.log(`⚠️ Tier 4: Recovery attempted but no stored Google Refresh Token for ${googleId}`);
      return res.status(401).json({ 
        error: 'No offline session found or Google offline token missing',
        requiresLogin: true
      });
    }

    const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';
    const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;

    // Exchange stored googleRefreshToken with Google
    const oauth2Client = new OAuth2Client(
      GOOGLE_CLIENT_ID,
      GOOGLE_CLIENT_SECRET
    );
    oauth2Client.setCredentials({
      refresh_token: user.googleRefreshToken
    });

    console.log(`🔄 Tier 4: Silently requesting fresh credentials from Google on behalf of ${user.email}...`);
    
    // Request a refreshed access token from Google
    const { token } = await oauth2Client.getAccessToken();

    if (!token) {
      console.log(`❌ Tier 4: Google rejected refresh token for ${user.email}`);
      return res.status(401).json({ 
        error: 'Google offline session is no longer valid. User must sign in again.',
        requiresLogin: true 
      });
    }

    // Success! Generate fresh local Snehayog session
    const accessToken = generateJWT(user.googleId, '30d');
    const newRefreshToken = await RefreshToken.createForDevice(
      user._id,
      deviceId,
      deviceName || 'Unknown Device',
      platform || 'unknown'
    );

    console.log(`✅ Tier 4 Recovery Successful: Silently logged in ${user.email}`);

    res.json({
      accessToken,
      refreshToken: newRefreshToken
    });

  } catch (error) {
    console.error('❌ Tier 4: Session recovery error:', error);
    res.status(500).json({ error: 'Failed to silently recover session' });
  }
};
