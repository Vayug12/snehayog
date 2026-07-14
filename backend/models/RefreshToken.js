import mongoose from 'mongoose';
import crypto from 'crypto';

const RefreshTokenSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  tokenHash: {
    type: String,
    required: true,
    unique: true
  },
  deviceId: {
    type: String,
    required: false, // Made optional
    index: true
  },
  deviceName: {
    type: String,
    default: 'Unknown Device'
  },
  platform: {
    type: String,
    enum: ['android', 'ios', 'web', 'unknown'],
    default: 'unknown'
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  expiresAt: {
    type: Date,
    required: true,
    index: true
  },
  lastUsedAt: {
    type: Date,
    default: Date.now
  },
  isRevoked: {
    type: Boolean,
    default: false,
    index: true
  }
});

// Compound index for efficient user sessions lookup
RefreshTokenSchema.index({ userId: 1, isRevoked: 1 });
RefreshTokenSchema.index({ tokenHash: 1, isRevoked: 1 });

// Static method to generate a secure refresh token
RefreshTokenSchema.statics.generateToken = function() {
  return crypto.randomBytes(64).toString('hex');
};

// Static method to hash a token for storage
RefreshTokenSchema.statics.hashToken = function(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
};

// Static method to create a new refresh token for a user/device
RefreshTokenSchema.statics.createForDevice = async function(userId, deviceId, deviceName, platform) {
  // **SECURITY FIX: "Loose" Device Validation**
  // Only revoke existing tokens if the deviceId is reliable.
  // We skip revocation for generic/fallback IDs to avoid "Session Collision" bugs.
  const unreliableIds = ['unknown', 'fallback', 'emergency', 'generic', '9774d56d682e549c'];
  const isReliableId = deviceId && 
                       deviceId.length > 5 && 
                       !unreliableIds.some(u => deviceId.toLowerCase().includes(u));

  if (isReliableId) {
    await this.updateMany(
      { userId, deviceId, isRevoked: false },
      { $set: { isRevoked: true } }
    );
  } else {
    // If ID is unreliable, we just continue. This allows multiple "unknown" sessions 
    // without them kicking each other out.
  }

  // Generate new token
  const rawToken = this.generateToken();
  const tokenHash = this.hashToken(rawToken);
  
  // Production-ready: Set expiry to 180 days (configurable via env)
  const refreshExpiryDays = parseInt(process.env.REFRESH_TOKEN_EXPIRY_DAYS) || 180;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + refreshExpiryDays);

  // Create and save
  const refreshToken = new this({
    userId,
    tokenHash,
    deviceId,
    deviceName: deviceName || 'Unknown Device',
    platform: platform || 'unknown',
    expiresAt,
    lastUsedAt: new Date()
  });

  await refreshToken.save();

  // Return the raw token (only time it's available unhashed)
  return rawToken;
};

// Static method to verify and rotate a refresh token
RefreshTokenSchema.statics.verifyAndRotate = async function(rawToken) {
  const tokenHash = this.hashToken(rawToken);

  // Find valid token by hash (include expired to distinguish revocation vs expiry)
  const existingToken = await this.findOne({
    tokenHash,
    isRevoked: false,
  }).populate('userId', 'googleId name email profilePic');

  if (!existingToken) {
    return null;
  }

  // Check if token is expired but not revoked — treat as expired, not revoked
  // This avoids revoking a token that merely expired due to normal passage of time,
  // which would otherwise prevent the client from attempting Google fallback.
  if (existingToken.expiresAt <= new Date()) {
    console.log(`⚠️ Refresh token expired at ${existingToken.expiresAt.toISOString()} for device ${existingToken.deviceId}`);
    // Do NOT revoke — let it expire naturally. Return null so caller knows it's invalid.
    return null;
  }

  // Revoke the old token (rotation)
  existingToken.isRevoked = true;
  await existingToken.save();

  // Generate new token (rotation)
  const newRawToken = this.generateToken();
  const newTokenHash = this.hashToken(newRawToken);

  // Production-ready: Set expiry to 180 days (configurable via env)
  const refreshExpiryDays = parseInt(process.env.REFRESH_TOKEN_EXPIRY_DAYS) || 180;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + refreshExpiryDays);

  const newToken = new this({
    userId: existingToken.userId._id,
    tokenHash: newTokenHash,
    deviceId: existingToken.deviceId, // Preserve if existed
    deviceName: existingToken.deviceName,
    platform: existingToken.platform,
    expiresAt,
    lastUsedAt: new Date()
  });

  await newToken.save();

  return {
    newToken: newRawToken,
    user: existingToken.userId
  };
};

// Static method to find valid session (most recent)
RefreshTokenSchema.statics.findValidSession = async function(tokenHash) {
  const session = await this.findOne({
    tokenHash,
    isRevoked: false,
    expiresAt: { $gt: new Date() }
  }).populate('userId', 'googleId name email profilePic');

  return session;
};

// Static method to find valid session by device ID (optional helper)
RefreshTokenSchema.statics.findValidSessionByDevice = async function(deviceId) {
  if (!deviceId) return null;
  const session = await this.findOne({
    deviceId,
    isRevoked: false,
    expiresAt: { $gt: new Date() }
  }).populate('userId', 'googleId name email profilePic').sort({ lastUsedAt: -1 });

  return session;
};

// Static method to revoke all tokens for a user
RefreshTokenSchema.statics.revokeAllForUser = async function(userId) {
  const result = await this.updateMany(
    { userId, isRevoked: false },
    { $set: { isRevoked: true } }
  );
  return result.modifiedCount;
};

// Static method to revoke token for specific device
RefreshTokenSchema.statics.revokeForDevice = async function(userId, deviceId) {
  const result = await this.updateMany(
    { userId, deviceId, isRevoked: false },
    { $set: { isRevoked: true } }
  );
  return result.modifiedCount;
};

// Static method to get all active sessions for a user
RefreshTokenSchema.statics.getActiveSessions = async function(userId) {
  const sessions = await this.find({
    userId,
    isRevoked: false,
    expiresAt: { $gt: new Date() }
  }).select('deviceId deviceName platform createdAt lastUsedAt').sort({ lastUsedAt: -1 });

  return sessions;
};

// Cleanup expired tokens (can be run as a cron job)
RefreshTokenSchema.statics.cleanupExpired = async function() {
  const result = await this.deleteMany({
    $or: [
      { expiresAt: { $lt: new Date() } },
      { isRevoked: true, lastUsedAt: { $lt: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) } } // Revoked > 30 days ago
    ]
  });
  return result.deletedCount;
};

export default mongoose.models.RefreshToken || mongoose.model('RefreshToken', RefreshTokenSchema);
