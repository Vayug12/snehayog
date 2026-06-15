import express from 'express';
import mongoose from 'mongoose';
import { verifyToken } from '../../utils/verifytoken.js';
import User from '../../models/User.js';
import EncryptedVideoKey from '../../models/EncryptedVideoKey.js';
import Follower from '../../models/Follower.js';

const router = express.Router();

/**
 * ============================================================
 * E2EE (End-to-End Encryption) Routes for Subscriber-Only Videos
 * ============================================================
 * 
 * These routes manage the cryptographic key exchange between
 * creators and subscribers. Vayug servers NEVER see or store
 * the raw symmetric video decryption key.
 */

// ─────────────────────────────────────────────────────────────
// 1. PUBLIC KEY MANAGEMENT
// ─────────────────────────────────────────────────────────────

/**
 * POST /api/e2ee/public-key
 * Upload or update the user's Ed25519 public key.
 * Called once during registration/login from the Flutter app.
 */
router.post('/public-key', verifyToken, async (req, res) => {
  try {
    const { publicKey } = req.body;
    const googleId = req.user?.googleId || req.user?.id;

    if (!publicKey || typeof publicKey !== 'string' || publicKey.length < 10) {
      return res.status(400).json({ error: 'A valid public key is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    user.publicKey = publicKey;
    await user.save();

    console.log(`🔐 E2EE: Public key saved for user ${user.name}`);
    res.json({ success: true, message: 'Public key saved successfully' });

  } catch (error) {
    console.error('❌ E2EE: Error saving public key:', error);
    res.status(500).json({ error: 'Failed to save public key' });
  }
});

/**
 * GET /api/e2ee/subscribers-keys
 * Fetch the public keys of all active subscribers of the creator.
 * Called by the creator's app right before uploading an E2EE video.
 */
router.get('/subscribers-keys', verifyToken, async (req, res) => {
  try {
    const googleId = req.user?.googleId || req.user?.id;

    const creator = await User.findOne({ googleId }).select('_id').lean();
    if (!creator) {
      return res.status(404).json({ error: 'Creator not found' });
    }

    // Get all followers (subscribers) of this creator
    const followerDocs = await Follower.find({ following: creator._id })
      .select('follower')
      .lean();

    const subscriberIds = followerDocs.map(f => f.follower);

    // Fetch their public keys
    const subscribers = await User.find({
      _id: { $in: subscriberIds },
      publicKey: { $ne: null } // Only users who have uploaded a public key
    })
    .select('_id publicKey')
    .lean();

    console.log(`🔐 E2EE: Fetched ${subscribers.length} subscriber keys for creator`);

    res.json({
      success: true,
      subscribers: subscribers.map(s => ({
        subscriberId: s._id.toString(),
        publicKey: s.publicKey
      })),
      total: subscribers.length
    });

  } catch (error) {
    console.error('❌ E2EE: Error fetching subscriber keys:', error);
    res.status(500).json({ error: 'Failed to fetch subscriber keys' });
  }
});

// ─────────────────────────────────────────────────────────────
// 2. ENCRYPTED VIDEO KEY MANAGEMENT
// ─────────────────────────────────────────────────────────────

/**
 * POST /api/e2ee/video-keys
 * Store the encrypted symmetric keys for all subscribers of a video.
 * Called by the creator's app after encrypting the video and its key.
 * 
 * Body: {
 *   videoId: "...",
 *   keys: [
 *     { subscriberId: "...", encryptedSymmetricKey: "base64..." },
 *     ...
 *   ]
 * }
 */
router.post('/video-keys', verifyToken, async (req, res) => {
  try {
    const { videoId, keys } = req.body;
    const googleId = req.user?.googleId || req.user?.id;

    if (!videoId || !Array.isArray(keys) || keys.length === 0) {
      return res.status(400).json({ error: 'videoId and keys array are required' });
    }

    // Verify the uploader owns this video
    const creator = await User.findOne({ googleId }).select('_id').lean();
    if (!creator) {
      return res.status(404).json({ error: 'User not found' });
    }

    const Video = (await import('../../models/Video.js')).default;
    const video = await Video.findById(videoId).select('uploader isSubscriberOnly').lean();

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    if (video.uploader.toString() !== creator._id.toString()) {
      return res.status(403).json({ error: 'You are not the owner of this video' });
    }

    if (!video.isSubscriberOnly) {
      return res.status(400).json({ error: 'This video is not subscriber-only. E2EE keys are not needed.' });
    }

    // Validate and build bulk ops
    const bulkOps = [];
    for (const k of keys) {
      if (!k.subscriberId || !k.encryptedSymmetricKey) {
        return res.status(400).json({ error: 'Each key must have subscriberId and encryptedSymmetricKey' });
      }

      let subId = k.subscriberId;
      // If subscriberId is not a valid ObjectId, assume it's a googleId and resolve it
      if (!mongoose.Types.ObjectId.isValid(subId)) {
        const resolvedUser = await User.findOne({ googleId: subId }).select('_id').lean();
        if (resolvedUser) {
          subId = resolvedUser._id;
        } else {
          console.warn(`⚠️ E2EE: Could not resolve subscriber ID ${subId} to MongoDB ObjectId`);
          continue; // skip this key
        }
      }

      bulkOps.push({
        updateOne: {
          filter: { videoId, subscriberId: subId },
          update: {
            $set: {
              videoId,
              subscriberId: subId,
              encryptedSymmetricKey: k.encryptedSymmetricKey
            }
          },
          upsert: true
        }
      });
    }

    if (bulkOps.length === 0) {
      return res.status(400).json({ error: 'No valid subscriber keys could be processed' });
    }

    const result = await EncryptedVideoKey.bulkWrite(bulkOps);

    console.log(`🔐 E2EE: Stored ${bulkOps.length} encrypted keys for video ${videoId}`);

    res.json({
      success: true,
      message: `${bulkOps.length} encrypted keys saved`,
      upserted: result.upsertedCount,
      modified: result.modifiedCount
    });

  } catch (error) {
    console.error('❌ E2EE: Error storing video keys:', error);
    res.status(500).json({ error: 'Failed to store encrypted video keys' });
  }
});

/**
 * GET /api/e2ee/video-key/:videoId
 * Fetch the encrypted symmetric key for the current subscriber for a specific video.
 * Called by the subscriber's app when they attempt to play an E2EE video.
 */
router.get('/video-key/:videoId', verifyToken, async (req, res) => {
  try {
    const { videoId } = req.params;
    const googleId = req.user?.googleId || req.user?.id;

    const user = await User.findOne({ googleId }).select('_id').lean();
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const keyDoc = await EncryptedVideoKey.findOne({
      videoId,
      subscriberId: user._id
    }).lean();

    if (!keyDoc) {
      return res.status(403).json({
        error: 'No decryption key found. You may not have access to this encrypted video.',
        hasAccess: false
      });
    }

    console.log(`🔐 E2EE: Delivered encrypted key for video ${videoId} to subscriber ${user._id}`);

    res.json({
      success: true,
      hasAccess: true,
      encryptedSymmetricKey: keyDoc.encryptedSymmetricKey
    });

  } catch (error) {
    console.error('❌ E2EE: Error fetching video key:', error);
    res.status(500).json({ error: 'Failed to fetch video key' });
  }
});

export default router;
