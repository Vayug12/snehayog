import express from 'express';
import mongoose from 'mongoose';
import User from '../models/User.js';
import Follower from '../models/Follower.js';
import SavedVideo from '../models/SavedVideo.js';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js'; // Added passiveVerifyToken
import jwt from 'jsonwebtoken'; // Added for token info endpoint
import redisService from '../services/caching/redisService.js';
import { getGlobalLeaderboard, MIN_SUBSCRIPTIONS } from '../controllers/video/videoFeedController.js';
import RecommendationService from '../services/yugFeedServices/recommendationService.js';
import Notice from '../models/Notice.js';
import Video from '../models/Video.js';
import { billableMatch } from '../services/adServices/impressionCounting.js';

const router = express.Router();

const TOP_EARNERS_CACHE_TTL = 120; // seconds

const getProfileCacheKey = (userId) =>
  userId ? `profile:${userId}` : null;

const getTopEarnersCacheKey = (userId) =>
  userId ? `top_earners_following:${userId}` : null;

const getIsFollowingCacheKey = (currentUserId, targetUserId) =>
  (currentUserId && targetUserId) ? `isfollowing:${currentUserId}:${targetUserId}` : null;

const IS_FOLLOWING_CACHE_TTL = 30; // 30 seconds

const ACTIVE_CREATORS_CACHE_TTL = 600; // 10 minutes

const getActiveCreatorsCacheKey = (videoType) => `creators:active:${videoType}`;

const cacheResponse = async (key, data, ttl) => {
  if (!key || !data) return;
  try {
    await redisService.set(key, data, ttl);
  } catch (err) {
    console.error('❌ Redis cache set error:', err.message);
  }
};

const getCachedResponse = async (key) => {
  if (!key) return null;
  try {
    return await redisService.get(key);
  } catch (err) {
    console.error('❌ Redis cache get error:', err.message);
    return null;
  }
};

const invalidateProfileCache = async (userIds) => {
  const ids = Array.isArray(userIds) ? userIds : [userIds];
  for (const id of ids) {
    if (!id) continue;
    const profileKey = getProfileCacheKey(id);
    const topKey = getTopEarnersCacheKey(id);
    try {
      if (profileKey) await redisService.del(profileKey);
      if (topKey) await redisService.del(topKey);
    } catch (err) {
      console.error('❌ Redis cache invalidate error:', err.message);
    }
  }
};

/**
 * **NEW: Logic to synchronize user performance counters**
 * Recalculates followerCount, followingCount, savedVideosCount, and videos array.
 * @param {string} userId - MongoDB _id of the user
 */
const syncUserCounters = async (userId) => {
  try {
    if (!userId) return;
    
    // Import models directly since they are already imported at the top
    // 1. Calculate counts in parallel
    const [followerCount, followingCount, savedVideosCount, videoIds] = await Promise.all([
      Follower.countDocuments({ following: userId }),
      Follower.countDocuments({ follower: userId }),
      SavedVideo.countDocuments({ user: userId }),
      mongoose.model('Video').find({ uploader: userId }).select('_id').lean().then(docs => docs.map(d => d._id))
    ]);

    // 2. Update User document atomically
    await User.findByIdAndUpdate(userId, {
      $set: {
        followerCount,
        followingCount,
        savedVideosCount,
        videos: videoIds
      }
    });

    console.log(`✅ syncUserCounters: Synced ${userId} (Fow: ${followerCount}, Fol: ${followingCount}, SV: ${savedVideosCount}, V: ${videoIds.length})`);
    
    // 3. Invalidate relevant caches
    await invalidateProfileCache(userId);
    
    return { followerCount, followingCount, savedVideosCount, videoCount: videoIds.length };
  } catch (err) {
    console.error(`❌ syncUserCounters Error for ${userId}:`, err.message);
    throw err;
  }
};

// ✅ Route to register/create user (for Google OAuth)
router.post('/register', async (req, res) => {
  try {
    
    const { googleId, name, email, profilePicture, profilePic } = req.body;
    const profilePictureUrl = profilePicture || profilePic || '';
    
    if (!googleId || !name || !email) {
      return res.status(400).json({ 
        error: 'Missing required fields: googleId, name, email' 
      });
    }
    
    // Check if user already exists
    const existingUser = await User.findOne({ googleId });
    if (existingUser) {
      console.log('✅ User already exists, checking for missing data...');
      
      // **FIXED: Update user profile data if it's missing**
      let needsUpdate = false;
      if (!existingUser.name || existingUser.name.trim() === '') {
        console.log('📝 Updating missing name from Google account');
        existingUser.name = name;
        needsUpdate = true;
      }
      if (!existingUser.profilePic || existingUser.profilePic.trim() === '') {
        console.log('📸 Updating missing profile picture from Google account');
        existingUser.profilePic = profilePictureUrl;
        needsUpdate = true;
      }
      if (needsUpdate) {
        await existingUser.save();
        console.log('✅ User profile updated with Google account data');
      }
      
      return res.json({
        success: true,
        user: {
          _id: existingUser._id,
          googleId: existingUser.googleId,
          name: existingUser.name,
          email: existingUser.email,
          profilePic: existingUser.profilePic,
          profilePicture: existingUser.profilePic, // Keep for backwards compatibility
          isNewUser: false
        }
      });
    }
    
    // Create new user
    const newUser = new User({
      googleId,
      name,
      email,
      profilePic: profilePictureUrl, // Use extracted value
      isActive: true
    });
    
    await newUser.save();
    console.log('✅ New user created successfully');
    
    res.status(201).json({
      success: true,
      user: {
        _id: newUser._id,
        googleId: newUser.googleId,
        name: newUser.name,
        email: newUser.email,
        profilePicture: newUser.profilePic, // **FIXED: Use correct field name**
        isNewUser: true
      }
    });
    
  } catch (error) {
    console.error('❌ Error in user registration:', error);
    res.status(500).json({ 
      error: 'User registration failed', 
      details: error.message 
    });
  }
});

// ✅ Route to get current user profile (requires authentication)
// **IMPORTANT: This must come before /:id route**
// **SECURITY FIX: Disabled caching to prevent data leaks between users**
router.get('/profile', verifyToken, async (req, res) => {
  try {
    const currentUserId = req.user.id; // This is the Google user ID
    
    // Find current user with selective fields and lean query for performance
    // **IDENTITY OPTIMIZATION: Use req.user._id if available**
    const query = req.user?._id ? { _id: req.user._id } : { googleId: currentUserId };
    const currentUser = await User.findOne(query)
      .select('_id googleId name email profilePic websiteUrl videos followingCount followerCount preferredCurrency preferredPaymentMethod country authProvider phoneNumber phoneVerifiedAt isSyntheticEmail')
      .lean();
    
    if (!currentUser) {
      console.log('❌ Profile API: User not found with googleId:', currentUserId);
      return res.status(404).json({ 
        error: 'User not found'
      });
    }

    // **NEW: Update app version and last active in background**
    const appVersion = req.headers['x-app-version'];
    const platform = req.headers['x-platform']; // Optional, could be used for analytics
    
    // Always update lastActive, and update appVersion if provided
    User.updateOne(query, { 
      $set: { 
        lastActive: new Date(),
        ...(appVersion ? { appVersion } : {})
      } 
    }).catch(err => console.error('⚠️ Profile API: Failed to update background stats:', err.message));

    // **FIX: Automatic Sync for 0-count profiles**
    // If counts are 0, trigger a background sync to ensure accuracy
    if (currentUser.followerCount === 0 || currentUser.followingCount === 0 || (currentUser.videos || []).length === 0) {
      console.log(`ℹ️ GET /profile: Triggering background sync for ${currentUser.googleId} due to zero counts`);
      syncUserCounters(currentUser._id).catch(() => {});
    }
    
    // **SAFE: Wrap rank call so any failure doesn't cause a 500**
    let ownRank = 0;
    try {
      ownRank = await RecommendationService.getGlobalCreatorRank(currentUser._id);
    } catch (rankErr) {
      console.error('⚠️ GET /profile: Failed to get creator rank (non-fatal):', rankErr.message);
    }

    // currentUser is already a plain object due to .lean()
    const payload = {
      _id: currentUser._id,
      id: currentUser.googleId,
      googleId: currentUser.googleId,
      name: currentUser.name,
      email: currentUser.isSyntheticEmail ? '' : currentUser.email,
      profilePic: currentUser.profilePic,
      authProvider: currentUser.authProvider || 'google',
      phoneNumber: currentUser.phoneNumber
        ? `${currentUser.phoneNumber.substring(0, 3)}******${currentUser.phoneNumber.slice(-4)}`
        : null,
      phoneVerified: !!currentUser.phoneVerifiedAt,
      websiteUrl: currentUser.websiteUrl, // Adding websiteUrl to payload
      videos: currentUser.videos,
      preferredCurrency: currentUser.preferredCurrency,
      preferredPaymentMethod: currentUser.preferredPaymentMethod,
      country: currentUser.country,
      rank: ownRank,
    };

    // **API VERSIONING: Backward Compatibility for Legacy Versions**
    if (req.apiVersion < '2026-03-02') {
      // Legacy versions expect arrays of user IDs
      const [followingDocs, followerDocs, savedDocs] = await Promise.all([
        Follower.find({ follower: currentUser._id }).select('following').lean(),
        Follower.find({ following: currentUser._id }).select('follower').lean(),
        SavedVideo.find({ user: currentUser._id }).select('video').lean()
      ]);
      
      payload.following = followingDocs.map(f => f.following);
      payload.followers = followerDocs.map(f => f.follower);
      payload.savedVideos = savedDocs.map(s => s.video);
    } else {
      // Modern versions use performance counters
      payload.following = currentUser.followingCount || 0;
      payload.followers = currentUser.followerCount || 0;
      payload.savedVideos = currentUser.savedVideosCount || 0;
    }

    res.json(payload);

  } catch (err) {
    console.error('Get profile error:', err);
    res.status(500).json({ error: 'Failed to get profile', details: err.message });
  }
});

// **NEW: Route to fetch active notices for the user**
router.get('/notices', verifyToken, async (req, res) => {
  try {
    const googleId = req.user.id;
    
    // Find notices for this user
    const notices = await Notice.find({ userId: googleId }).lean();
    
    // Filter out expired ones (1 hour after seen)
    const now = Date.now();
    const hourInMs = 60 * 60 * 1000;
    
    const activeNotices = notices.filter(notice => {
      if (!notice.firstSeenAt) return true; // Not seen yet
      
      const firstSeenTime = new Date(notice.firstSeenAt).getTime();
      if (isNaN(firstSeenTime)) return true; // Fallback for invalid dates
      
      const elapsed = now - firstSeenTime;
      const isExpired = elapsed >= hourInMs;
      
      if (isExpired) {
        console.log(`👤 Notice API: Notice ${notice._id} for ${googleId} has expired (${Math.round(elapsed/60000)}m elapsed)`);
      }
      
      return !isExpired;
    });

    res.json({ success: true, notices: activeNotices });
  } catch (error) {
    console.error('❌ Error fetching notices:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch notices' });
  }
});

// **NEW: Route to mark notice as seen**
router.put('/notices/:id/seen', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    const googleId = req.user.id;

    const notice = await Notice.findOne({ _id: id, userId: googleId });
    if (!notice) {
      console.log(`⚠️ Notice API: Notice ${id} not found for user ${googleId}`);
      return res.status(404).json({ success: false, error: 'Notice not found' });
    }

    if (!notice.firstSeenAt) {
      const now = new Date();
      notice.firstSeenAt = now;
      await notice.save();
      console.log(`✅ Notice API: Marked notice ${id} as seen at ${now.toISOString()}`);
    } else {
      console.log(`ℹ️ Notice API: Notice ${id} already marked as seen at ${notice.firstSeenAt.toISOString()}`);
    }

    res.json({ success: true, message: 'Notice marked as seen', notice });
  } catch (error) {
    console.error('❌ Error marking notice as seen:', error);
    res.status(500).json({ success: false, error: 'Failed to mark notice as seen' });
  }
});

// ✅ TEST: Simple test endpoint (no auth) to verify route is accessible
// **IMPORTANT: Must come BEFORE /:id route to avoid route conflicts**
router.get('/top-earners-test', (req, res) => {
  console.log('🧪 TEST: Top Earners test endpoint hit!');
  console.log('🧪 Request URL:', req.originalUrl);
  console.log('🧪 Request method:', req.method);
  res.json({ message: 'Top Earners route is working!', timestamp: new Date().toISOString() });
});

// ✅ Route to get global leaderboard (public)
// Reuses the bulk ranking logic from RecommendationService but masks earnings.
router.get('/leaderboard/global', getGlobalLeaderboard);

// ✅ Route to get top earners from user's following list
router.get('/top-earners-from-following', verifyToken, async (req, res) => {
  try {
    console.log('========================================');
    
    // Try both id and googleId from req.user
    const currentUserId = req.user.id || req.user.googleId;
    console.log('💰 Top Earners API: Current user ID:', currentUserId);
    console.log('💰 Top Earners API: Current user ID type:', typeof currentUserId);

    if (!currentUserId) {
      return res.status(401).json({ error: 'Invalid token - no user ID' });
    }

    // Find current user - try multiple methods
    let currentUser = await User.findOne({ googleId: currentUserId });
    
    if (!currentUser && req.user.email) {
      // Fallback: Try finding by email
      console.log('🔍 Top Earners API: Trying to find user by email:', req.user.email);
      currentUser = await User.findOne({ email: req.user.email });
    }
    
    if (!currentUser) {
      // Try finding by MongoDB _id if currentUserId is ObjectId
      try {
        const mongoose = (await import('mongoose')).default;
        if (mongoose.Types.ObjectId.isValid(currentUserId)) {
          currentUser = await User.findById(currentUserId);
        }
      } catch (e) {
        console.log('⚠️ Top Earners API: Error trying ObjectId lookup:', e);
      }
    }
    
    if (!currentUser) {
      console.log('❌ Top Earners API: User not found');
      console.log('🔍 Top Earners API: Searched with googleId:', currentUserId);
      console.log('🔍 Top Earners API: Searched with email:', req.user.email);
      // Debug: Show sample users
      const sampleUsers = await User.find({}).select('googleId name email').limit(3);
      console.log('🔍 Top Earners API: Sample users in DB:', sampleUsers.map(u => ({ 
        googleId: u.googleId, 
        name: u.name,
        email: u.email
      })));
      return res.status(404).json({ 
        error: 'User not found',
        debug: {
          searchedFor: currentUserId,
          searchedForType: typeof currentUserId,
          searchedEmail: req.user.email
        }
      });
    }
    console.log('✅ Top Earners API: User found:', currentUser.name);

    // Attempt cache
    const topEarnersCacheKey = getTopEarnersCacheKey(currentUser.googleId);
    if (topEarnersCacheKey) {
      const cachedTopEarners = await getCachedResponse(topEarnersCacheKey);
      if (cachedTopEarners) {
        console.log('⚡ Top Earners API: Cache hit for', currentUser.googleId);
        return res.json(cachedTopEarners);
      }
    }

    // **FIXED: Get following list from Follower collection (user.following is deprecated)**
    const followerDocs = await Follower.find({ follower: currentUser._id }).select('following').lean();
    const followingIds = followerDocs.map(f => f.following);
    
    console.log('💰 Top Earners API: Following IDs from Doc:', followingIds);
    console.log('💰 Top Earners API: Following count:', followingIds.length);

    // **DEBUG: Check if all following IDs exist in User collection**
    const followedUsersCount = await User.countDocuments({ _id: { $in: followingIds } });
    console.log(`💰 Top Earners API: Found ${followedUsersCount}/${followingIds.length} users in DB`);

    if (followingIds.length === 0) {
      console.log('ℹ️ Top Earners API: User is not following anyone');
      return res.json({ topEarners: [], message: 'Not following anyone' });
    }

    // Calculate earnings for each user in following list
    // **OPTIMIZED: Use a single aggregation to calculate earnings for ALL following users in one query**
    const now = new Date();
    const startOfMonth = new Date(Date.UTC(now.getFullYear(), now.getMonth(), 1));

    // Import models
    const AdImpression = (await import('../models/AdImpression.js')).default;
    const Video = (await import('../models/Video.js')).default;

    // 1. Get user metadata and video count
    const followingUsers = await User.find({
      _id: { $in: followingIds }
    }).select('googleId name email profilePic videos').lean();

    // 2. Aggregate earnings for all following users at once
    const earningsStats = await AdImpression.aggregate([
      { 
        $match: { 
          creatorId: { $in: followingIds },
          ...billableMatch(),
          timestamp: { $gte: startOfMonth }
        } 
      },
      {
        $group: {
          _id: { creator: '$creatorId', adType: '$adType' },
          totalViews: { 
            $sum: { $cond: [{ $gt: ['$viewCount', 0] }, '$viewCount', 1] } 
          }
        }
      },
      {
        $group: {
          _id: '$_id.creator',
          bannerViews: {
            $sum: { $cond: [{ $eq: ['$_id.adType', 'banner'] }, '$totalViews', 0] }
          },
          carouselViews: {
            $sum: { $cond: [{ $eq: ['$_id.adType', 'carousel'] }, '$totalViews', 0] }
          }
        }
      }
    ]);

    // 3. Create a map for quick lookup
    const bannerCpm = 10;
    const carouselCpm = 30;
    const creatorShare = 0.80;

    const earningsMap = new Map();
    earningsStats.forEach(stat => {
      const earnings = (
        (stat.bannerViews / 1000) * bannerCpm + 
        (stat.carouselViews / 1000) * carouselCpm
      ) * creatorShare;
      earningsMap.set(stat._id.toString(), earnings);
    });

    // 4. Combine metadata with earnings
    const topEarners = followingUsers.map(user => {
      const earnings = earningsMap.get(user._id.toString()) || 0;
      return {
        userId: user.googleId,
        name: user.name,
        profilePic: user.profilePic || null,
        totalEarnings: earnings,
        videoCount: user.videos?.length || 0
      };
    })
    .sort((a, b) => b.totalEarnings - a.totalEarnings)
    .map((earner, index) => ({
      ...earner,
      rank: index + 1,
      // Mask actual earnings for privacy in this public-facing list
      totalEarnings: 0
    }));

    console.log(`✅ Top Earners API: Found ${topEarners.length} top earners with optimized query`);

    const payload = {
      topEarners,
      totalCount: topEarners.length
    };

    res.json(payload);

    if (topEarnersCacheKey) {
      await cacheResponse(topEarnersCacheKey, payload, TOP_EARNERS_CACHE_TTL);
    }
  } catch (err) {
    console.error('❌ Top earners error:', err);
    console.error('❌ Top earners error stack:', err.stack);
    res.status(500).json({ 
      error: 'Failed to get top earners',
      details: err.message 
    });
  }
});

// ✅ Export subscriber emails (Substack-style)
router.get('/my-subscribers/export', verifyToken, async (req, res) => {
  try {
    const creatorGoogleId = req.user.id;
    let creator = await User.findOne({ googleId: creatorGoogleId }).lean();
    
    if (!creator && req.user._id) {
       creator = await User.findById(req.user._id).lean();
    }
    
    if (!creator) {
      return res.status(404).json({ error: 'Creator not found' });
    }

    const creatorId = creator._id;
    
    // Get all followers of this creator
    const followerDocs = await Follower.find({ following: creatorId })
      .select('follower createdAt')
      .populate('follower', 'name email profilePic')
      .lean();
    
    const subscribers = followerDocs
      .filter(f => f.follower && f.follower.email) // Safety check
      .map(f => ({
        name: f.follower.name,
        email: f.follower.email,
        profilePic: f.follower.profilePic || '',
        subscribedAt: f.createdAt,
      }));
    
    // Return as JSON (frontend will convert to CSV)
    res.json({
      success: true,
      totalSubscribers: subscribers.length,
      subscribers,
      exportedAt: new Date().toISOString(),
    });
  } catch (err) {
    console.error('❌ Export subscribers error:', err);
    res.status(500).json({ error: 'Failed to export subscribers' });
  }
});

/**
 * GET /api/users/following/list
 * Get list of creators the current user is following with metadata
 */
router.get('/following/list', verifyToken, async (req, res) => {
  try {
    const currentUserIdFromToken = req.user.id;
    const user = await User.findOne({ googleId: currentUserIdFromToken });
    
    if (!user) {
      console.log(`❌ following/list: User not found for googleId: ${currentUserIdFromToken}`);
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    console.log(`🔍 following/list: Fetching following for user _id: ${user._id} (${user.name})`);
    const followingDocs = await Follower.find({ follower: user._id })
      .populate('following', 'name profilePic googleId')
      .lean();

    const following = followingDocs
      .filter(doc => doc.following) // Ensure user exists
      .map(doc => ({
        id: doc.following._id,
        googleId: doc.following.googleId,
        name: doc.following.name,
        profilePic: doc.following.profilePic
      }));

    console.log(`✅ following/list: Found ${following.length} creators for ${user.name}`);
    res.status(200).json({ success: true, following });
  } catch (error) {
    console.error('Error fetching following list:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// ✅ Route to update user profile (name and profilePic)
router.post('/update-profile', async (req, res) => {
  try {
    const { googleId, name, profilePic, websiteUrl } = req.body;
    
    if (!googleId || !name) {
      return res.status(400).json({ error: 'Google ID and name are required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Update user fields
    user.name = name;
    if (profilePic) {
      user.profilePic = profilePic;
    }
    if (websiteUrl !== undefined) {
      user.websiteUrl = websiteUrl;
    }

    await user.save();

    await invalidateProfileCache(user.googleId);

    res.json({ 
      message: 'Profile updated successfully',
      user: {
        id: user._id,
        name: user.name,
        profilePic: user.profilePic,
        email: user.email
      }
    });
  } catch (err) {
    console.error('Update profile error:', err);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// ✅ Route to follow a user
router.post('/follow', verifyToken, async (req, res) => {
  try {
    const { userIdToFollow } = req.body;
    const currentUserId = req.user.id;

    if (!userIdToFollow) {
      return res.status(400).json({ error: 'User ID to follow is required' });
    }

    if (currentUserId === userIdToFollow) {
      return res.status(400).json({ error: 'Cannot follow yourself' });
    }

    // Find current user - MUST fetch full Mongoose document to use .follow() method
    const currentUser = await User.findOne({ googleId: currentUserId });
    
    // Find target user - support both googleId and MongoDB _id
    let userToFollow = await User.findOne({ googleId: userIdToFollow });
    if (!userToFollow) {
      try {
        const mongoose = (await import('mongoose')).default;
        if (mongoose.Types.ObjectId.isValid(userIdToFollow)) {
          userToFollow = await User.findById(userIdToFollow);
        }
      } catch (e) {
        // Ignore invalid ObjectId errors
      }
    }

    if (!currentUser) return res.status(404).json({ error: 'Current user not found' });
    if (!userToFollow) return res.status(404).json({ error: 'User to follow not found' });

    // Use the NEW async follow method
    const success = await currentUser.follow(userToFollow._id);
    
    if (!success) {
      return res.status(400).json({ error: 'Already following this user' });
    }

    // Re-fetch counts for accurate response (or use incremented values)
    const [updatedCurrentUser, updatedUserToFollow] = await Promise.all([
      User.findById(currentUser._id).select('followingCount').lean(),
      User.findById(userToFollow._id).select('followerCount').lean()
    ]);

    await invalidateProfileCache([currentUser.googleId, userToFollow.googleId]);

    // **PROACTIVE SYNC: Ensure counts are perfectly accurate in background**
    syncUserCounters(currentUser._id).catch(() => {});
    syncUserCounters(userToFollow._id).catch(() => {});

    res.json({ 
      message: 'Successfully followed user',
      following: updatedCurrentUser.followingCount,
      followers: updatedUserToFollow.followerCount
    });
  } catch (err) {
    console.error('Follow user error:', err);
    res.status(500).json({ error: 'Failed to follow user' });
  }
});

// ✅ Route to unfollow a user
router.post('/unfollow', verifyToken, async (req, res) => {
  try {
    const { userIdToUnfollow } = req.body;
    const currentUserId = req.user.id;

    if (!userIdToUnfollow) {
      return res.status(400).json({ error: 'User ID to unfollow is required' });
    }

    // Find current user - MUST fetch full Mongoose document to use .unfollow() method
    const currentUser = await User.findOne({ googleId: currentUserId });
    
    // Find target user - support both googleId and MongoDB _id
    let userToUnfollow = await User.findOne({ googleId: userIdToUnfollow });
    if (!userToUnfollow) {
      try {
        const mongoose = (await import('mongoose')).default;
        if (mongoose.Types.ObjectId.isValid(userIdToUnfollow)) {
          userToUnfollow = await User.findById(userIdToUnfollow);
        }
      } catch (e) {
        // Ignore invalid ObjectId errors
      }
    }

    if (!currentUser || !userToUnfollow) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Use the NEW async unfollow method
    const success = await currentUser.unfollow(userToUnfollow._id);
    
    if (!success) {
      return res.status(400).json({ error: 'Not following this user' });
    }

    const [updatedCurrentUser, updatedUserToUnfollow] = await Promise.all([
      User.findById(currentUser._id).select('followingCount').lean(),
      User.findById(userToUnfollow._id).select('followerCount').lean()
    ]);

    await invalidateProfileCache([currentUser.googleId, userToUnfollow.googleId]);

    // **PROACTIVE SYNC: Ensure counts are perfectly accurate in background**
    syncUserCounters(currentUser._id).catch(() => {});
    syncUserCounters(userToUnfollow._id).catch(() => {});

    res.json({ 
      message: 'Successfully unfollowed user',
      following: updatedCurrentUser.followingCount,
      followers: updatedUserToUnfollow.followerCount
    });
  } catch (err) {
    console.error('Unfollow user error:', err);
    res.status(500).json({ error: 'Failed to unfollow user' });
  }
});

// ✅ Route to check if current user is following another user
router.get('/isfollowing/:userId', verifyToken, async (req, res) => {
  try {
    // console.log('🔍 IsFollowing API: Request received');
    // console.log('🔍 IsFollowing API: Request params:', req.params);
    // console.log('🔍 IsFollowing API: Current user from token:', req.user);
    
    const { userId } = req.params;
    const currentUserId = req.user.id; // This is now the Google user ID

    // console.log('🔍 IsFollowing API: userId to check:', userId);
    // console.log('🔍 IsFollowing API: currentUserId:', currentUserId);

    if (currentUserId === userId) {
      return res.json({ isFollowing: false });
    }

    const cacheKey = getIsFollowingCacheKey(currentUserId, userId);
    const cachedStatus = await getCachedResponse(cacheKey);
    if (cachedStatus !== null) {
      return res.json(cachedStatus);
    }

    const currentUser = await User.findOne({ googleId: currentUserId });
    if (!currentUser) {
      const response = { isFollowing: false };
      await cacheResponse(cacheKey, response, IS_FOLLOWING_CACHE_TTL);
      return res.json(response);
    }

    // Find target user - support both googleId and MongoDB _id
    let userToCheck = await User.findOne({ googleId: userId });
    if (!userToCheck) {
      try {
        const mongoose = (await import('mongoose')).default;
        if (mongoose.Types.ObjectId.isValid(userId)) {
          userToCheck = await User.findById(userId);
        }
      } catch (e) {
        // Ignore invalid ObjectId errors
      }
    }

    if (!userToCheck) {
      const response = { isFollowing: false };
      await cacheResponse(cacheKey, response, IS_FOLLOWING_CACHE_TTL);
      return res.json(response);
    }

    // Check if following via the NEW async method
    const isFollowing = await currentUser.isFollowing(userToCheck._id);
    
    const response = { isFollowing };
    await cacheResponse(cacheKey, response, IS_FOLLOWING_CACHE_TTL);
    res.json(response);
  } catch (err) {
    console.error('Check follow status error:', err);
    res.status(500).json({ error: 'Failed to check follow status' });
  }
});

// ✅ **OPTIMIZED: Batch check follow status for multiple users in one call**
router.post('/isfollowing/batch', verifyToken, async (req, res) => {
  try {
    const { userIds } = req.body;
    const currentUserId = req.user.id;

    if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
      return res.json({ statuses: {} });
    }

    const limitedIds = userIds.slice(0, 50);

    const currentUser = await User.findOne({ googleId: currentUserId }).select('_id').lean();
    if (!currentUser) return res.json({ statuses: {} });

    // Find all target users by googleId in one query
    const targetUsers = await User.find({ googleId: { $in: limitedIds } })
      .select('_id googleId')
      .lean();

    const targetMap = new Map(targetUsers.map(u => [u.googleId, u._id.toString()]));
    const targetMongoIds = Array.from(targetMap.values());

    // Query Follower collection for all relationships at once
    const existingFollows = await Follower.find({
      follower: currentUser._id,
      following: { $in: targetMongoIds }
    }).select('following').lean();

    const followedSet = new Set(existingFollows.map(f => f.following.toString()));

    const statuses = {};
    for (const id of limitedIds) {
      const mongoId = targetMap.get(id);
      statuses[id] = mongoId ? followedSet.has(mongoId) : false;
    }

    res.json({ statuses });
  } catch (err) {
    console.error('Batch follow status error:', err);
    res.status(500).json({ error: 'Failed to check batch follow status' });
  }
});

// **NEW: JWT Token validation endpoint (for debugging)**
router.get('/validate-token', verifyToken, async (req, res) => {
  try {
    console.log('🔍 Token validation request received');
    console.log('🔍 User from token:', req.user);
    
    res.json({
      valid: true,
      user: req.user,
      message: 'Token is valid',
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('❌ Token validation error:', err);
    res.status(401).json({ 
      valid: false, 
      error: 'Invalid token',
      timestamp: new Date().toISOString()
    });
  }
});

// **NEW: JWT Token info endpoint (for debugging)**
router.get('/token-info', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Bearer token required' });
    }
    
    const token = authHeader.split(' ')[1];
    console.log('🔍 Token info request for token:', token.substring(0, 20) + '...');
    
    // Decode JWT without verification (for info only)
    const decoded = jwt.decode(token);
    if (!decoded) {
      return res.status(400).json({ error: 'Invalid token format' });
    }
    
    const now = Math.floor(Date.now() / 1000);
    const isExpired = decoded.exp && decoded.exp < now;
    const expiresIn = decoded.exp ? decoded.exp - now : null;
    
    res.json({
      tokenInfo: {
        userId: decoded.id,
        issuedAt: decoded.iat ? new Date(decoded.iat * 1000).toISOString() : null,
        expiresAt: decoded.exp ? new Date(decoded.exp * 1000).toISOString() : null,
        isExpired: isExpired,
        expiresInSeconds: expiresIn,
        expiresInMinutes: expiresIn ? Math.floor(expiresIn / 60) : null,
        tokenType: 'JWT'
      },
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('❌ Token info error:', err);
    res.status(500).json({ error: 'Failed to decode token' });
  }
});

// **NEW: Location Data Endpoints**

// ✅ Route to update user location data
router.post('/update-location', verifyToken, async (req, res) => {
  try {
    console.log('📍 Update Location API: Request received');
    console.log('📍 Update Location API: Request body:', req.body);
    console.log('📍 Update Location API: Current user from token:', req.user);
    
    const { latitude, longitude, address, city, state, country } = req.body;
    const currentUserId = req.user.id; // Google user ID

    console.log('📍 Update Location API: currentUserId:', currentUserId);
    console.log('📍 Update Location API: Location data:', { latitude, longitude, address, city, state, country });

    if (!latitude || !longitude) {
      return res.status(400).json({ error: 'Latitude and longitude are required' });
    }

    // Find current user
    const user = await User.findOne({ googleId: currentUserId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Update location data
    user.location = {
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      address: address || '',
      city: city || '',
      state: state || '',
      country: country || '',
      lastUpdated: new Date(),
      permissionGranted: true
    };

    await user.save();

    console.log('✅ Update Location API: Location updated successfully');

    res.json({
      message: 'Location updated successfully',
      location: user.location
    });
  } catch (err) {
    console.error('❌ Update location error:', err);
    res.status(500).json({ error: 'Failed to update location' });
  }
});

// ✅ Route to get user location data
router.get('/location', verifyToken, async (req, res) => {
  try {
    console.log('📍 Get Location API: Request received');
    console.log('📍 Get Location API: Current user from token:', req.user);
    
    const currentUserId = req.user.id; // Google user ID

    console.log('📍 Get Location API: currentUserId:', currentUserId);

    // Find current user
    const user = await User.findOne({ googleId: currentUserId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('📍 Get Location API: User location data:', user.location);

    res.json({
      location: user.location,
      hasLocation: !!(user.location && user.location.latitude && user.location.longitude)
    });
  } catch (err) {
    console.error('❌ Get location error:', err);
    res.status(500).json({ error: 'Failed to get location' });
  }
});

// ✅ Route to check if user has location permission
router.get('/location-permission', verifyToken, async (req, res) => {
  try {
    console.log('📍 Location Permission API: Request received');
    console.log('📍 Location Permission API: Current user from token:', req.user);
    
    const currentUserId = req.user.id; // Google user ID

    console.log('📍 Location Permission API: currentUserId:', currentUserId);

    // Find current user
    const user = await User.findOne({ googleId: currentUserId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const hasLocationPermission = user.location && user.location.permissionGranted;
    const hasLocationData = user.location && user.location.latitude && user.location.longitude;

    console.log('📍 Location Permission API: Permission status:', { hasLocationPermission, hasLocationData });

    res.json({
      hasLocationPermission,
      hasLocationData,
      needsLocationPermission: !hasLocationPermission,
      needsLocationData: !hasLocationData
    });
  } catch (err) {
    console.error('❌ Get location permission error:', err);
    res.status(500).json({ error: 'Failed to check location permission' });
  }
});

// Duplicate routes removed - moved before /:id route (see line 164)

// ✅ Route to manually trigger profile sync
router.post('/sync-profile', verifyToken, async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const user = await User.findOne({ googleId }).select('_id').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    const stats = await syncUserCounters(user._id);
    res.json({ success: true, stats });
  } catch (err) {
    res.status(500).json({ error: 'Sync failed', details: err.message });
  }
});

// ✅ Route to sync ALL user counters (Admin only)
router.post('/sync-all-counters', async (req, res) => {
  try {
    // Check for admin key in headers
    const adminKey = req.headers['x-admin-key'];
    if (adminKey !== process.env.ADMIN_KEY) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const users = await User.find({}).select('_id').lean();
    let count = 0;
    
    // Serial processing to avoid overwhelming DB, but could be chunked
    for (const user of users) {
      await syncUserCounters(user._id);
      count++;
    }

    res.json({ success: true, processed: count });
  } catch (err) {
    res.status(500).json({ error: 'Bulk sync failed', details: err.message });
  }
});

// ✅ Route to get creator's subscribers (for subscriber-only content)
router.get('/subscribers', verifyToken, async (req, res) => {
  try {
    let user = null;
    if (req.user?._id) {
      user = await User.findById(req.user._id).select('_id').lean();
    }
    if (!user) {
      const googleId = req.user?.googleId || req.user?.id;
      if (googleId) {
        user = await User.findOne({ googleId }).select('_id').lean();
      }
    }
    if (!user) {
      console.log(`❌ /subscribers: User not found for search`);
      return res.status(404).json({ error: 'User not found' });
    }

    const userId = user._id;
    console.log(`🔍 /subscribers: Fetching subscribers for creator _id: ${userId}`);

    // Get all followers (subscribers) of this creator
    const followers = await Follower.find({ following: userId })
      .populate('follower', 'name email profilePic profilePicture')
      .lean();

    const subscribers = followers.map(f => ({
      _id: f.follower._id,
      id: f.follower._id.toString(),
      name: f.follower.name,
      email: f.follower.email,
      profilePic: f.follower.profilePic || f.follower.profilePicture,
    }));

    console.log(`✅ /subscribers: Found ${subscribers.length} subscribers for creator`);
    res.json({
      success: true,
      subscribers,
      total: subscribers.length,
    });
  } catch (err) {
    console.error('❌ Get subscribers error:', err);
    res.status(500).json({ error: 'Failed to fetch subscribers', details: err.message });
  }
});

// ✅ Route to get subscriber-only videos for current user
router.get('/subscriber-videos', verifyToken, async (req, res) => {
  try {
    let user = null;
    if (req.user?._id) {
      user = await User.findById(req.user._id).select('_id').lean();
    }
    if (!user) {
      const googleId = req.user?.googleId || req.user?.id;
      if (googleId) {
        user = await User.findOne({ googleId }).select('_id').lean();
      }
    }
    if (!user) return res.status(404).json({ error: 'User not found' });

    const userId = user._id;

    // Get videos where this user is in allowedSubscribers
    const videos = await Video.find({
      isSubscriberOnly: true,
      allowedSubscribers: userId,
      processingStatus: 'completed'
    })
    .populate('uploader', 'name profilePic profilePicture')
    .sort({ uploadedAt: -1 })
    .limit(50)
    .lean();

    res.json({
      success: true,
      videos,
      total: videos.length,
    });
  } catch (err) {
    console.error('❌ Get subscriber videos error:', err);
    res.status(500).json({ error: 'Failed to fetch subscriber videos', details: err.message });
  }
});

/**
 * Creators who actually publish the requested feed type.
 * Cached because the distinct scan is far heavier than the follow lookup.
 */
const getActiveCreatorIds = async (videoType) => {
  const cacheKey = getActiveCreatorsCacheKey(videoType);
  const cached = await getCachedResponse(cacheKey);
  if (Array.isArray(cached)) return cached;

  const ids = await Video.distinct('uploader', {
    videoType,
    processingStatus: 'completed',
    isSubscriberOnly: { $ne: true },
  });

  const creatorIds = ids.filter(Boolean).map((id) => id.toString());
  if (creatorIds.length > 0) {
    await cacheResponse(cacheKey, creatorIds, ACTIVE_CREATORS_CACHE_TTL);
  }
  return creatorIds;
};

/**
 * GET /api/users/suggested-creators
 * Creators the user can subscribe to in order to unlock the following feed.
 * Already-followed creators and the user themself are never suggested.
 */
router.get('/suggested-creators', verifyToken, async (req, res) => {
  try {
    let userObjectId = null;
    if (req.user?._id && mongoose.Types.ObjectId.isValid(req.user._id)) {
      userObjectId = new mongoose.Types.ObjectId(req.user._id);
    } else {
      const googleId = req.user?.googleId || req.user?.id;
      const user = googleId
        ? await User.findOne({ googleId }).select('_id').lean()
        : null;
      if (!user) return res.status(404).json({ error: 'User not found' });
      userObjectId = user._id;
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 50);
    const videoType = (req.query.videoType || 'vayu').toLowerCase();

    const [followDocs, activeCreatorIds] = await Promise.all([
      Follower.find({ follower: userObjectId }).select('following').lean(),
      getActiveCreatorIds(videoType),
    ]);

    const excludedIds = new Set([
      userObjectId.toString(),
      ...followDocs.map((doc) => doc.following?.toString()).filter(Boolean),
    ]);

    const candidateIds = activeCreatorIds.filter((id) => !excludedIds.has(id));

    let creators = [];
    if (candidateIds.length > 0) {
      creators = await User.find({ _id: { $in: candidateIds } })
        .select('googleId name profilePic followerCount')
        .sort({ followerCount: -1 })
        .limit(limit)
        .lean();
    }

    // Top up with other publishing creators so a new user always has enough
    // choices to clear the gate, even before the platform has long-form uploads.
    if (creators.length < limit) {
      creators.forEach((c) => excludedIds.add(c._id.toString()));
      const fillers = await User.find({
        _id: { $nin: Array.from(excludedIds) },
        'videos.0': { $exists: true },
      })
        .select('googleId name profilePic followerCount')
        .sort({ followerCount: -1 })
        .limit(limit - creators.length)
        .lean();
      creators = creators.concat(fillers);
    }

    res.json({
      success: true,
      creators: creators.map((c) => ({
        id: c.googleId || c._id.toString(),
        name: c.name || 'Creator',
        profilePic: c.profilePic || '',
        followerCount: c.followerCount || 0,
      })),
      followingCount: followDocs.length,
      required: MIN_SUBSCRIPTIONS,
    });
  } catch (err) {
    console.error('❌ Get suggested creators error:', err);
    res.status(500).json({ error: 'Failed to fetch suggested creators' });
  }
});

// ✅ Route to check if user has access to a video
router.get('/video-access/:videoId', verifyToken, async (req, res) => {
  try {
    const { videoId } = req.params;
    const googleId = req.user.googleId;
    const user = await User.findOne({ googleId }).select('_id').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    const userId = user._id;

    const video = await Video.findById(videoId).lean();
    if (!video) return res.status(404).json({ error: 'Video not found' });

    // Check if video is subscriber-only
    if (video.isSubscriberOnly) {
      // Check if user is in allowedSubscribers
      const hasAccess = video.allowedSubscribers.some(id => id.toString() === userId.toString());

      return res.json({
        success: true,
        hasAccess,
        isSubscriberOnly: true,
      });
    }

    // Video is public
    res.json({
      success: true,
      hasAccess: true,
      isSubscriberOnly: false,
    });
  } catch (err) {
    console.error('❌ Check video access error:', err);
    res.status(500).json({ error: 'Failed to check video access', details: err.message });
  }
});

// ✅ Route to get user profile by ID
// **IMPORTANT: This must come AFTER all specific routes**
// **SECURITY FIX: Disabled caching and added privacy filter**
router.get('/:id', passiveVerifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    // First try to find by Google ID (primary identifier)
    let user = await User.findOne({ googleId: id })
      .select('_id googleId name email profilePic websiteUrl videos followingCount followerCount preferredCurrency preferredPaymentMethod country paymentDetails')
      .lean();

    // If not found, try by MongoDB ObjectId
    if (!user) {
      try {
        const mongoose = (await import('mongoose')).default;
        // **IDENTITY OPTIMIZATION: Support pre-resolved ObjectIds**
        if (mongoose.Types.ObjectId.isValid(id)) {
          user = await User.findById(id)
            .select('_id googleId name email profilePic websiteUrl videos followingCount followerCount preferredCurrency preferredPaymentMethod country paymentDetails')
            .lean();
        }
      } catch (e) {
        // ignore invalid ObjectId errors
      }
    }

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // **PRIVACY CHECK**: Check if the requester is the owner of the profile
    const requesterId = req.user?.googleId || req.user?.id;
    const isOwner = requesterId && (requesterId === user.googleId || requesterId === user._id.toString());
    
    // console.log(`🔒 Profile Access Check: Requester=${requesterId}, Target=${user.googleId}, IsOwner=${isOwner}`);

    // **SAFE: Wrap rank call so any failure doesn't cause a 500**
    let rank = 0;
    try {
      rank = await RecommendationService.getGlobalCreatorRank(user._id);
    } catch (rankErr) {
      console.error('⚠️ GET /:id: Failed to get creator rank (non-fatal):', rankErr.message);
    }

    const payload = {
      _id: user._id, // MongoDB ObjectID
      id: user.googleId,
      googleId: user.googleId,
      name: user.name,
      profilePic: user.profilePic,
      websiteUrl: user.websiteUrl, // Adding websiteUrl to payload
      videos: user.videos,
      rank,
      // **SENSITIVE FIELDS**: Only include if owner
      email: isOwner ? user.email : null,
      preferredCurrency: isOwner ? user.preferredCurrency : null,
      preferredPaymentMethod: isOwner ? user.preferredPaymentMethod : null,
      country: isOwner ? user.country : null,
      paymentDetails: isOwner ? user.paymentDetails : null,
    };

    // **API VERSIONING: Backward Compatibility for Legacy Versions**
    if (req.apiVersion < '2026-03-02') {
      const [followingDocs, followerDocs] = await Promise.all([
        Follower.find({ follower: user._id }).select('following').lean(),
        Follower.find({ following: user._id }).select('follower').lean()
      ]);
      
      payload.following = followingDocs.map(f => f.following);
      payload.followers = followerDocs.map(f => f.follower);
    } else {
      payload.following = user.followingCount || 0;
      payload.followers = user.followerCount || 0;
    }

    res.json(payload);

  } catch (err) {
    console.error('Get user by ID error:', err);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// ✅ Route to delete account (MANDATORY for Google Play)
router.delete('/delete-account', verifyToken, async (req, res) => {
  try {
    const userId = req.user._id;
    const googleId = req.user.id;

    console.log(`🗑️ Delete Account: Starting for user ${googleId} (${userId})`);

    // 1. Delete user's videos (or mark as deleted)
    const Video = (await import('../models/Video.js')).default;
    await Video.deleteMany({ uploader: userId });

    // 2. Delete followers/following relationships
    const Follower = (await import('../models/Follower.js')).default;
    await Follower.deleteMany({ $or: [{ follower: userId }, { following: userId }] });

    // 3. Delete saved videos
    const SavedVideo = (await import('../models/SavedVideo.js')).default;
    await SavedVideo.deleteMany({ user: userId });

    // 4. Delete notices
    const Notice = (await import('../models/Notice.js')).default;
    await Notice.deleteMany({ userId: googleId });

    // 5. Delete user document
    const user = await User.findByIdAndDelete(userId);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    console.log(`✅ Delete Account: Completed for user ${googleId}`);

    res.json({ 
      success: true, 
      message: 'Account and all associated data deleted successfully. Please note that it may take up to 30 days for data to be fully purged from backups.' 
    });
  } catch (err) {
    console.error('❌ Delete account error:', err);
    res.status(500).json({ error: 'Failed to delete account', details: err.message });
  }
});

export default router;
