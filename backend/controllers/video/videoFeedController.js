import mongoose from 'mongoose';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import Follower from '../../models/Follower.js';
import RemovedVideoRecord from '../../models/RemovedVideoRecord.js';
import RecommendationService from '../../services/yugFeedServices/recommendationService.js';
import FeedQueueService from '../../services/yugFeedServices/feedQueueService.js';
import redisService from '../../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';
import { serializeVideo, serializeVideos } from '../../utils/serializers/videoSerializer.js';
import RevenueService from '../../services/adServices/revenueService.js';

/**
 * Helper to populate episodes for a list of videos
 */
const populateEpisodesForVideos = async (videos) => {
  if (!videos || videos.length === 0) return;
  
  const seriesIds = new Set();
  videos.forEach(v => { if (v.seriesId) seriesIds.add(v.seriesId); });

  if (seriesIds.size > 0) {
    try {
      const allEpisodes = await Video.find({ 
        seriesId: { $in: Array.from(seriesIds) }, 
        processingStatus: 'completed'
      })
        .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
        .sort({ episodeNumber: 1 }).lean();
        
      const episodesMap = new Map();
      allEpisodes.forEach(ep => {
        if (!episodesMap.has(ep.seriesId)) episodesMap.set(ep.seriesId, []);
        ep._id = ep._id.toString();
        episodesMap.get(ep.seriesId).push(ep);
      });

      videos.forEach(v => {
        if (v.seriesId && episodesMap.has(v.seriesId)) {
          v.episodes = episodesMap.get(v.seriesId);
        }
      });
    } catch (err) { 
      console.error('⚠️ Error populating series episodes:', err); 
    }
  }
};

/**
 * Video Retrieval Controllers
 */
export const getUserVideos = async (req, res) => {
  try {
    const { googleId } = req.params;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 9;
    const videoType = (req.query.videoType || 'all').toLowerCase();
    const mediaType = (req.query.mediaType || 'all').toLowerCase();
    
    // **FIX: Include pagination and filter parameters in the cache key**
    // This prevents different pages/filters from returning the same cached data.
    const cacheKey = `${VideoCacheKeys.user(googleId)}:p${page}:l${limit}:t${videoType}:m${mediaType}`;
    
    res.set('Cache-Control', 'public, max-age=300');

    const shouldRefresh = req.query.refresh === 'true';

    if (shouldRefresh && redisService.getConnectionStatus()) {
        // Clear ALL pages/filters for this user using a wildcard pattern
        await invalidateCache(`${VideoCacheKeys.user(googleId)}*`);
        await invalidateCache(`user:profile:${googleId}`);
    }

    if (!shouldRefresh && redisService.getConnectionStatus()) {
      const cached = await redisService.get(cacheKey);
      if (cached) return res.json(cached);
    }

    const userProfileCacheKey = `user:profile:${googleId}`;
    let user = null;

    if (req.user && (req.user.googleId === googleId || req.user.id === googleId) && req.user._id) {
       user = { _id: req.user._id, googleId: googleId };
    }

    if (!user && redisService.getConnectionStatus()) {
      const cached = await redisService.get(userProfileCacheKey);
      if (cached && cached._id && /^[a-f0-9]{24}$/i.test(cached._id.toString())) {
        user = cached;
      }
    }

    if (!user) {
      user = await User.findOne({ googleId: googleId }).select('_id googleId').lean();
      if (!user) {
        try {
          if (mongoose.Types.ObjectId.isValid(googleId)) {
            user = await User.findById(googleId).select('_id googleId').lean();
          }
        } catch (e) {
          // Ignore invalid ObjectId errors
        }
      }
      if (!user) return res.status(404).json({ error: 'User not found' });

      if (redisService.getConnectionStatus()) {
        await redisService.set(userProfileCacheKey, user, 600);
      }
    }

    let skip = req.query.skip !== undefined ? parseInt(req.query.skip) : (page - 1) * limit;

    const query = {
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' },
      processingStatus: { $nin: ['failed', 'error'] }
    };

    if (req.query.videoType) {
      query.videoType = req.query.videoType.toLowerCase();
    }
    if (req.query.mediaType) {
      query.mediaType = req.query.mediaType.toLowerCase();
    }

    const requestingGoogleId = req.user?.googleId || req.user?.id;
    const isOwner = requestingGoogleId === googleId;

    // ENFORCE: Subscriber-Only Filtering (STRICT)
    // Only the owner can see exclusive content on the profile.
    // Everyone else only sees public content.
    if (!isOwner) {
      query.isSubscriberOnly = { $ne: true };
    }

    const [videos, rank, cachedEarnings] = await Promise.all([
      Video.find(query)
        .populate('uploader', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .select('-description -shares')
        .lean(),
      (!isOwner) ? RecommendationService.getGlobalCreatorRank(user._id) : Promise.resolve(0),
      (isOwner && redisService.getConnectionStatus()) ? redisService.get(`creator:earnings:${user._id}`) : Promise.resolve(null)
    ]);

    const validVideos = videos.filter(video => video.uploader && video.uploader.name);

    if (validVideos.length !== videos.length) {
      const validVideoIds = validVideos.map(v => v._id);
      User.findByIdAndUpdate(user._id, { $set: { videos: validVideoIds } }).catch(e => console.error('Data sync error:', e));
    }

    const seriesIds = new Set();
    validVideos.forEach(v => { if (v.seriesId) seriesIds.add(v.seriesId); });

    let currentMonthEarnings = 0;
    if (isOwner) {
      if (cachedEarnings !== null) {
        currentMonthEarnings = typeof cachedEarnings === 'object' ? cachedEarnings.amount : parseFloat(cachedEarnings);
      } else {
        try {
            const now = new Date();
            const summary = await RevenueService.getCreatorRevenueSummary(user._id, now.getUTCMonth(), now.getUTCFullYear());
            
            if (summary.success) {
              currentMonthEarnings = summary.thisMonth;
              if (redisService.getConnectionStatus()) {
                await redisService.set(`creator:earnings:${user._id}`, { amount: currentMonthEarnings, updatedAt: new Date() }, 900);
              }
            }
        } catch (err) { console.error('⚠️ Error calculating monthly earnings (unified):', err); }
      }
    }

    const episodesMap = new Map();
    if (seriesIds.size > 0) {
      try {
        const allEpisodes = await Video.find({ 
          seriesId: { $in: Array.from(seriesIds) }, 
          processingStatus: 'completed'
        })
          .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
          .sort({ episodeNumber: 1 }).lean();
        allEpisodes.forEach(ep => {
          if (!episodesMap.has(ep.seriesId)) episodesMap.set(ep.seriesId, []);
          ep._id = ep._id.toString();
          episodesMap.get(ep.seriesId).push(ep);
        });
      } catch (err) { console.error('⚠️ Error fetching series episodes:', err); }
    }

    const videosWithMetadata = validVideos.map(v => {
      if (v.uploader) {
        if (isOwner) {
          v.uploader.earnings = parseFloat(currentMonthEarnings.toFixed(2));
        } else {
          v.uploader.earnings = 0;
          v.uploader.rank = rank;
        }
      }
      
      if (v.seriesId && episodesMap.has(v.seriesId)) {
        v.episodes = episodesMap.get(v.seriesId);
      }
      return v;
    });

    if (videosWithMetadata.length === 0) return res.json([]);

    const requestingUserGoogleId = req.user?.googleId;
    let requestingUserObjectIdStr = null;
    if (requestingUserGoogleId) {
      const rqUser = await User.findOne({ googleId: requestingUserGoogleId }).select('_id').lean();
      if (rqUser) requestingUserObjectIdStr = rqUser._id.toString();
    }

    const videosSerialized = serializeVideos(videosWithMetadata, req.apiVersion, requestingUserObjectIdStr, req.traceId);
    
    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, videosSerialized, 600);
    }

    return res.json(videosSerialized);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ error: 'Error fetching videos', details: error.message });
  }
};

export const getRemovedVideos = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    if (!googleId) return res.status(401).json({ error: 'Unauthorized' });

    const removedStats = await RemovedVideoRecord.find({ uploaderId: googleId })
      .sort({ removedAt: -1 })
      .lean();

    const result = removedStats.map(v => {
      const removedDate = v.removedAt instanceof Date ? v.removedAt : new Date(v.removedAt);
      const expiresAt = new Date(removedDate.getTime() + (3 * 24 * 60 * 60 * 1000));

      return {
        _id: v._id.toString(),
        id: v._id.toString(),
        videoName: v.videoName,
        thumbnailUrl: v.thumbnailUrl,
        reason: v.reason || 'Violation of Terms',
        removedAt: removedDate.toISOString(),
        expiresAt: expiresAt.toISOString()
      };
    });

    return res.json(result);
  } catch (error) {
    console.error('❌ Error fetching removed videos:', error);
    res.status(500).json({ error: 'Failed to fetch removed videos' });
  }
};

export const getGlobalLeaderboard = async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 20;
    const leaderboard = await RecommendationService.getGlobalLeaderboard(limit);
    res.set('Cache-Control', 'public, max-age=3600');
    return res.json(leaderboard);
  } catch (error) {
    console.error('❌ Error in getGlobalLeaderboard controller:', error);
    res.status(500).json({ error: 'Failed to fetch global leaderboard' });
  }
};

export const getFeed = async (req, res) => {
  try {
    let userId = null;
    const userIdFromToken = req.user?.googleId || req.user?.id;
    if (userIdFromToken) {
      userId = userIdFromToken;
    }

    const { videoType: queryVideoType, type: queryType, limit = 10, page = 1, clearSession, cursor } = req.query;
    const videoType = queryVideoType || queryType;
    const limitNum = parseInt(limit) || 5;
    const pageNum = parseInt(page) || 1;
    const deviceId = req.headers['x-device-id'];
    const userIdentifier = userId || deviceId || 'anon';
    
    const requestedType = (videoType || 'yog').toLowerCase();
    const type = requestedType;
    
    // DIAGNOSTIC LOG: Trace the feed request lifecycle for Vayu/Yug replenishment
    console.log(`[FeedRequest] User: ${userIdentifier}, Type: ${type}, Page: ${pageNum}, Cursor: ${cursor || 'none'}, Personalized: ${userId ? 'Yes' : 'No'}`);
    
    let finalVideos = [];
    let hasMore = false;
    let total = 0;

    if (clearSession === 'true') {
      await FeedQueueService.clearQueue(userIdentifier, type);
    }
    
    finalVideos = await FeedQueueService.popFromQueue(userIdentifier, type, limitNum);
    
    if (finalVideos.length === 0) {
      console.log(`[FeedQueue] Queue empty for ${userIdentifier} (${type}), falling back to MongoDB with scoring`);
      const query = {
        videoType: type,
        processingStatus: 'completed'
      };

      // STRICT: Main feed NEVER shows subscriber-only videos
      query.isSubscriberOnly = { $ne: true };

      const poolLimit = cursor ? 30 : 60;
      const queryCursor = cursor ? { createdAt: { $lt: new Date(cursor) } } : {};
      
      let skip = 0;
      if (!cursor && pageNum > 1) {
        skip = (pageNum - 1) * limitNum;
      }

      // 1. Fetch a larger pool of candidate videos
      const candidates = await Video.find({
        ...query,
        ...queryCursor
      })
        .populate('uploader', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(poolLimit)
        .lean();

      if (candidates.length > 0) {
        // 2. Load context (user profile + interest vector) for scoring
        let userProfile = null;
        let userVector = null;
        
        if (userId && userId !== 'anon') {
          userProfile = await User.findOne({ googleId: userId }).select('_id preferredLanguages location').lean();
          userVector = await RecommendationService.getUserInterestVector(userId);
        }

        const context = {
          user: userProfile || 'anon',
          userVector: userVector
        };

        // 3. Score and rank candidates using modular RecommendationEngine (utilizes Gemini analysis)
        const rankedCandidates = await RecommendationService.orderFeedWithDiversity(candidates, context);

        // 4. Perform weighted shuffle to ensure variety and prevent identical feed order
        finalVideos = RecommendationService.weightedShuffle(rankedCandidates, limitNum);
        console.log(`[FeedFallback] Scored & shuffled ${finalVideos.length} fallback videos from pool of ${candidates.length}`);
      } else {
        finalVideos = [];
      }
    }

    // SECONDARY SAFETY: Strictly filter out any exclusive content from the main feed results
    finalVideos = finalVideos.filter(v => !v.isSubscriberOnly);
    
    finalVideos = RecommendationService.enforceMaxConsecutive(finalVideos, 2);
    await populateEpisodesForVideos(finalVideos);

    let rqUserObjectIdStr = req.user?._id;
    if (!rqUserObjectIdStr && userId) {
      const rqUser = await User.findOne({ googleId: userId }).select('_id').lean();
      if (rqUser) rqUserObjectIdStr = rqUser._id.toString();
    }

    const serializedVideos = serializeVideos(finalVideos, req.apiVersion, rqUserObjectIdStr, req.traceId);

    let nextCursor = null;
    if (finalVideos.length > 0) {
      const lastVideo = finalVideos[finalVideos.length - 1];
      nextCursor = lastVideo.createdAt || lastVideo.uploadedAt;
      if (nextCursor instanceof Date) nextCursor = nextCursor.toISOString();
    }
    
    // Fix: set hasMore to true if we returned videos, so frontend asks for more
    hasMore = finalVideos.length > 0;

    res.json({
      videos: serializedVideos,
      hasMore: hasMore,
      total: total,
      currentPage: pageNum,
      nextCursor: nextCursor,
      totalPages: Math.ceil(total / limitNum),
      isPersonalized: userIdentifier !== 'anon'
    });

  } catch (error) {
    console.error('❌ Error fetching videos:', error);
    res.status(500).json({ error: 'Failed to fetch videos', message: error.message });
  }
};

/**
 * Minimum creators a user must subscribe to before the following feed unlocks.
 * Shared with /api/users/suggested-creators so both ends agree on the gate.
 */
export const MIN_SUBSCRIPTIONS = 5;

const FOLLOWING_FEED_TTL = 60; // seconds — short, so new uploads surface quickly

/**
 * Resolve the requesting user's Mongo _id from the verified token.
 * verifyToken memoizes _id, so this usually costs no DB round trip.
 */
const resolveUserObjectId = async (req) => {
  const cachedId = req.user?._id;
  if (cachedId && mongoose.Types.ObjectId.isValid(cachedId)) {
    return new mongoose.Types.ObjectId(cachedId);
  }

  const googleId = req.user?.googleId || req.user?.id;
  if (!googleId) return null;

  const user = await User.findOne({ googleId }).select('_id').lean();
  return user?._id || null;
};

/**
 * Feed built exclusively from creators the user subscribes to.
 * Stays locked until the user follows MIN_SUBSCRIPTIONS creators, so the
 * response always carries the gate state and the client never has to guess.
 */
export const getFollowingFeed = async (req, res) => {
  try {
    const userId = await resolveUserObjectId(req);
    if (!userId) return res.status(404).json({ error: 'User not found' });

    const videoType = (req.query.videoType || 'vayu').toLowerCase();
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 10, 1), 30);
    const cursor = req.query.cursor;
    const forceRefresh = req.query.refresh === 'true';

    const followDocs = await Follower.find({ follower: userId })
      .select('following')
      .lean();
    const followingIds = followDocs
      .map((doc) => doc.following)
      .filter(Boolean);

    if (followingIds.length < MIN_SUBSCRIPTIONS) {
      return res.json({
        videos: [],
        hasMore: false,
        nextCursor: null,
        gate: {
          unlocked: false,
          required: MIN_SUBSCRIPTIONS,
          followingCount: followingIds.length,
        },
      });
    }

    const cacheKey = `feed:following:${userId}:${videoType}:${cursor || 'head'}:l${limit}`;
    if (!forceRefresh && redisService.getConnectionStatus()) {
      const cached = await redisService.get(cacheKey);
      if (cached) return res.json(cached);
    }

    const query = {
      uploader: { $in: followingIds },
      videoType,
      processingStatus: 'completed',
      // Exclusive uploads are visible only to the creator's allowed subscribers.
      $or: [
        { isSubscriberOnly: { $ne: true } },
        { allowedSubscribers: userId },
      ],
    };

    if (cursor) {
      const cursorDate = new Date(cursor);
      if (!isNaN(cursorDate.getTime())) {
        query.createdAt = { $lt: cursorDate };
      }
    }

    // Over-fetch by one to know whether another page exists without a count().
    const candidates = await Video.find(query)
      .populate('uploader', 'name profilePic googleId')
      .sort({ createdAt: -1 })
      .limit(limit + 1)
      .lean();

    const hasMore = candidates.length > limit;
    const pageVideos = hasMore ? candidates.slice(0, limit) : candidates;

    await populateEpisodesForVideos(pageVideos);

    let nextCursor = null;
    if (pageVideos.length > 0) {
      const last = pageVideos[pageVideos.length - 1];
      nextCursor = last.createdAt || last.uploadedAt;
      if (nextCursor instanceof Date) nextCursor = nextCursor.toISOString();
    }

    const payload = {
      videos: serializeVideos(pageVideos, req.apiVersion, userId.toString(), req.traceId),
      hasMore,
      nextCursor,
      gate: {
        unlocked: true,
        required: MIN_SUBSCRIPTIONS,
        followingCount: followingIds.length,
      },
    };

    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, payload, FOLLOWING_FEED_TTL);
    }

    return res.json(payload);
  } catch (error) {
    console.error('❌ Error fetching following feed:', error);
    return res.status(500).json({ error: 'Failed to fetch subscribed videos' });
  }
};

export const getVideoById = async (req, res) => {
  try {
    const videoId = req.params.id;
    const video = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId');

    if (!video) return res.status(404).json({ error: 'Video not found' });

    const videoObj = video.toObject();

    // **NEW: Check access for subscriber-only videos**
    if (videoObj.isSubscriberOnly) {
      const requestingGoogleId = req.user?.googleId || req.user?.id;
      if (!requestingGoogleId) {
        return res.status(403).json({ error: 'This video is only available to subscribers' });
      }

      const requestingUser = await User.findOne({ googleId: requestingGoogleId }).select('_id').lean();
      if (!requestingUser) {
        return res.status(403).json({ error: 'This video is only available to subscribers' });
      }

      const hasAccess = videoObj.allowedSubscribers.some(id => id.toString() === requestingUser._id.toString());
      if (!hasAccess) {
        return res.status(403).json({ error: 'This video is only available to subscribers' });
      }
    }

    const requestingGoogleId = req.user?.googleId || req.user?.id;
    const rqUserObjectIdStr = req.user?._id;

    const [episodes, rank, isLiked] = await Promise.all([
      videoObj.seriesId ?
        Video.find({ seriesId: videoObj.seriesId, processingStatus: 'completed' })
          .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
          .sort({ episodeNumber: 1 }).lean().then(eps => eps.map(ep => ({ ...ep, _id: ep._id.toString() })))
        : Promise.resolve([]),
      (requestingGoogleId !== videoObj.uploader?.googleId?.toString())
        ? RecommendationService.getGlobalCreatorRank(videoObj.uploader?._id)
        : Promise.resolve(0),
      (rqUserObjectIdStr)
        ? Promise.resolve((videoObj.likedBy || []).some(id => id.toString() === rqUserObjectIdStr))
        : Promise.resolve(false)
    ]);

    const transformedVideo = serializeVideo(videoObj, req.apiVersion, rqUserObjectIdStr, req.traceId);
    res.json(transformedVideo);
  } catch (error) {
    console.error('❌ Error getting video by ID:', error);
    res.status(500).json({ error: 'Failed to get video', details: error.message });
  }
};
