import Video from '../../models/Video.js';
import FeedHistory from '../../models/FeedHistory.js';
import redisService from '../caching/redisService.js';
import RecommendationService from './recommendationService.js';
import mongoose from 'mongoose';
import {
  isVideoEligibleForProfession,
  withProfessionEligibility,
} from '../audienceEligibilityService.js';

/**
 * Feed Queue Service
 * Implements Event Driven Feed Generation architecture.
 * Manages per-user video queues in Redis lists for instant playback.
 */
class FeedQueueService {
  constructor() {
    this.QUEUE_SIZE_LIMIT = 150;  // Max videos to hold in Redis per user
    this.REFILL_THRESHOLD = 40;   // Trigger refill when videos drop below this number
    this.BATCH_SIZE = 110;        // Number of videos to fetch during refill (Threshold + Batch = Limit)
  }

  getQueueKey(userId, videoType = 'yog') {
    return `user:feed:${userId}:${videoType}`;
  }

  async clearQueue(userId, videoType = 'yog') {
    const queueKey = this.getQueueKey(userId, videoType);
    if (!redisService.getConnectionStatus()) return false;
    try {
      await redisService.del(queueKey);
      return true;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Clear queue failed:`, e.message);
      return false;
    }
  }

  async popFromQueue(userId, videoType = 'yog', limit = 5, knownProfessionId = undefined) {
    // OPTIMIZATION: Skip Redis entirely for anonymous users to save commands.
    if (!userId || userId === 'anon' || userId === 'anonymous' || userId === 'undefined') {
      return [];
    }

    const professionId = knownProfessionId === undefined
      ? await this.getUserProfessionId(userId)
      : knownProfessionId;
    const queueKey = this.getQueueKey(userId, videoType);
    const videos = [];
    const tStart = Date.now();
    let currentLength = 0;
    let poppedIds = [];

    try {
      const [len, popped] = await Promise.all([
        redisService.lLen(queueKey),
        redisService.lPop(queueKey, limit)
      ]);
      
      currentLength = len || 0;
      if (popped) {
        poppedIds = Array.isArray(popped) ? popped : [popped];
      }
    } catch (e) {
      console.error(`⚠️ FeedQueue: Redis lPop failed:`, e.message);
    }

    videos.push(...poppedIds);

    if (poppedIds.length > 0 && userId !== 'undefined' && userId !== 'anon') {
       const bfSeenKey = `user:bf_seen:${userId}`;
       await redisService.bfMAdd(bfSeenKey, poppedIds);
       
       const rsKey = `user:recent_served:${userId}`;
       await Promise.all([
         redisService.lPush(rsKey, poppedIds),
         redisService.lTrim(rsKey, 0, 199),
         redisService.expire(rsKey, 86400)
       ]);
    }

    const projectedLength = Math.max(0, currentLength - poppedIds.length);
    if (projectedLength < this.REFILL_THRESHOLD) {
      this.generateAndPushFeed(userId, videoType).catch(() => {});
    }

    if (videos.length < limit) {
       const needed = limit - videos.length;
       const remainingQueued = projectedLength > 0 ? await redisService.lRange(queueKey, 0, -1) : [];
       const initialExcludes = new Set([...videos, ...remainingQueued]);

       const fallbackIds = await this.getFallbackIds(userId, videoType, needed, Array.from(initialExcludes), professionId);
       if (fallbackIds.length > 0) {
          videos.push(...fallbackIds);
       }
    }

    let result = (await this.populateVideos(videos))
      .filter((video) => isVideoEligibleForProfession(video, professionId));

    // A profession change can leave incompatible IDs in an existing Redis queue.
    // Refill the response from an eligibility-aware Mongo query without scoring boosts.
    if (result.length < limit) {
      const replacementIds = await this.getFallbackIds(
        userId,
        videoType,
        limit - result.length,
        videos,
        professionId,
      );
      if (replacementIds.length > 0) {
        const replacements = await this.populateVideos(replacementIds);
        result = [
          ...result,
          ...replacements.filter((video) => isVideoEligibleForProfession(video, professionId)),
        ].slice(0, limit);
      }
    }

    if (result.length > 0 && userId !== 'anon' && userId !== 'undefined') {
       FeedHistory.markAsSeen(userId, result).catch(() => {});
       const hashes = result.map(v => v.videoHash).filter(Boolean);
       if (hashes.length > 0) {
          const bfHashKey = `user:bf_hashes:${userId}`;
          redisService.bfMAdd(bfHashKey, hashes).catch(() => {});
       }
    }

    console.log(`⏱️ Feed Latency: Total ${Date.now() - tStart}ms [${result.length} videos]`);
    return result;
  }

  async getUserProfessionId(userId) {
    if (!userId || ['anon', 'anonymous', 'undefined', 'null'].includes(userId)) return null;
    const cacheKey = `user:profession:${userId}`;
    if (redisService.getConnectionStatus()) {
      const cached = await redisService.get(cacheKey);
      if (cached !== null && cached !== undefined) {
        return cached === '__none__' ? null : String(cached);
      }
    }

    const User = mongoose.model('User');
    const user = await User.findOne({ googleId: userId }).select('professionId').lean();
    const professionId = user?.professionId || null;
    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, professionId || '__none__', 300);
    }
    return professionId;
  }

  async ensureBloomFilterSeeded(userId) {
    if (!userId || userId === 'anon' || userId === 'anonymous' || userId === 'undefined' || userId === 'null') return;
    const seededKey = `user:bf_seeded:${userId}`;
    if (await redisService.exists(seededKey)) return;

    const lockKey = `lock:seed:${userId}`;
    if (!(await redisService.setLock(lockKey, '1', 10))) return;

    try {
      const bfSeenKey = `user:bf_seen:${userId}`;
      const bfHashKey = `user:bf_hashes:${userId}`;
      const history = await FeedHistory.find({ userId }).sort({ seenAt: -1 }).limit(1000).select('videoId videoHash').lean();

      if (history.length > 0) {
          const ids = history.map(h => h.videoId.toString());
          const hashes = history.map(h => h.videoHash).filter(Boolean);
          await Promise.all([
            redisService.bfMAdd(bfSeenKey, ids),
            hashes.length > 0 ? redisService.bfMAdd(bfHashKey, hashes) : Promise.resolve(),
          ]);
      }
      await redisService.set(seededKey, 'true', 86400);
    } catch (e) {
      console.error('⚠️ FeedQueue: Seeding failed:', e.message);
    }
  }

  async generateAndPushFeed(userId, videoType = 'yog') {
    if (!userId || userId === 'anon' || userId === 'anonymous' || userId === 'undefined' || userId === 'null') return 0;
    const lockKey = `lock:refill:${userId}:${videoType}`;

    if (!(await redisService.setLock(lockKey, '1', 15))) return 0;

    try {
      await this.ensureBloomFilterSeeded(userId);
      let uploaderObjectId = null;
      // Fetch full user data for personalization
      let userProfile = null;
      if (userId && userId !== 'anon') {
        const User = mongoose.model('User');
        userProfile = await User.findOne({ googleId: userId }).select('_id preferredLanguages location professionId').lean();
        if (userProfile) uploaderObjectId = userProfile._id;
      }

      const queueKey = this.getQueueKey(userId, videoType);
      const seenVideoIds = new Set();

      const [queuedIds, recentServed] = await Promise.all([
        redisService.lRange(queueKey, 0, -1),
        redisService.lRange(`user:recent_served:${userId}`, 0, 200)
      ]);

      queuedIds.forEach(id => seenVideoIds.add(id));
      recentServed.forEach(id => seenVideoIds.add(id));

      const matchQuery = withProfessionEligibility({
          processingStatus: 'completed', 
          videoType,
          uploader: uploaderObjectId ? { $ne: uploaderObjectId } : { $exists: true },
          isSubscriberOnly: { $ne: true }
      }, userProfile?.professionId);

      const [popularCandidates, freshCandidates] = await Promise.all([
          Video.find(matchQuery).sort({ finalScore: -1 }).limit(600).select('_id uploader createdAt score finalScore videoType videoHash vectorEmbedding language detectedRegion targetProfessionIds').lean(),
          Video.find(matchQuery).sort({ createdAt: -1 }).limit(400).select('_id uploader createdAt score finalScore videoType videoHash vectorEmbedding language detectedRegion targetProfessionIds').lean()
      ]);

      let semanticCandidates = [];
      const userVector = await RecommendationService.getUserInterestVector(userId);
      
      if (userVector) {
          const semanticPool = await Video.find({ ...matchQuery, vectorEmbedding: { $exists: true, $ne: [] } })
            .sort({ createdAt: -1 }).limit(1000).select('_id uploader createdAt score finalScore videoType videoHash vectorEmbedding language detectedRegion targetProfessionIds').lean();
          semanticCandidates = RecommendationService.findTopSemanticMatches(userVector, semanticPool, 500);
      }

      const allCandidatesMap = new Map();
      [...popularCandidates, ...freshCandidates, ...semanticCandidates].forEach(v => {
          allCandidatesMap.set(v._id.toString(), v);
      });
      
      const candidates = Array.from(allCandidatesMap.values());

      if (candidates.length > 0) {
          const memFiltered = candidates.filter(v => !seenVideoIds.has(v._id.toString()));
          const bfSeenKey = `user:bf_seen:${userId}`;
          const bfHashKey = `user:bf_hashes:${userId}`;

          const [sFlags, hFlags] = await Promise.all([
              redisService.bfMExists(bfSeenKey, memFiltered.map(v => v._id.toString())),
              redisService.bfMExists(bfHashKey, memFiltered.map(v => v.videoHash).filter(Boolean))
          ]);

          const hashFlagsMap = new Map(memFiltered.map(v => v.videoHash).filter(Boolean).map((h, i) => [h, hFlags[i]]));
          const finalBatch = [];

          for (let i = 0; i < memFiltered.length; i++) {
              const video = memFiltered[i];
              if (sFlags[i] || (video.videoHash && hashFlagsMap.get(video.videoHash))) continue;
              
              // **APPLY PERSONALIZATION BOOST**
              const pBoost = RecommendationService.calculatePersonalizedBoost(video, userProfile);
              
              let score = video.finalScore || 0.1;
              if (video.semanticSimilarity) {
                  score += (video.semanticSimilarity * 0.5);
              }
              
              video.finalScore = score * pBoost;
              finalBatch.push(video);
              if (finalBatch.length >= 1000) break;
          }

          if (finalBatch.length > 0) {
              const randomized = RecommendationService.weightedShuffle(finalBatch, this.BATCH_SIZE);
              const ordered = await RecommendationService.orderFeedWithDiversity(randomized, { minCreatorSpacing: 4 });
              const pushIds = ordered.map(v => v._id.toString());
              const hashes = ordered.map(v => v.videoHash).filter(Boolean);
              await Promise.all([
                redisService.rPush(queueKey, pushIds),
                redisService.lTrim(queueKey, 0, this.QUEUE_SIZE_LIMIT - 1),
                redisService.bfMAdd(bfSeenKey, pushIds),
                hashes.length > 0 ? redisService.bfMAdd(bfHashKey, hashes) : Promise.resolve(),
              ]);
          }
      }
      return 1;
    } catch (error) {
      console.error('❌ FeedQueue: Refill Error:', error);
      return 0;
    }
  }

  async getFallbackIds(userId, videoType = 'yog', count = 10, excludedIds = [], knownProfessionId = undefined) {
    await this.ensureBloomFilterSeeded(userId);
    const excludeSet = new Set(excludedIds.map(id => id.toString()));
    const finalIds = [];
    const redisAvailable = redisService.getConnectionStatus();

    if (userId && userId !== 'anon' && userId !== 'undefined' && userId !== 'null') {
      try {
        const recentHistory = await FeedHistory.find({ userId }).sort({ seenAt: -1 }).limit(300).select('videoId').lean();
        recentHistory.forEach(h => { if (h?.videoId) excludeSet.add(h.videoId.toString()); });
      } catch (e) {}
    }

    try {
      const professionId = knownProfessionId === undefined
        ? await this.getUserProfessionId(userId)
        : knownProfessionId;
      const matchStage = withProfessionEligibility({
        processingStatus: 'completed',
        videoType,
        isSubscriberOnly: { $ne: true },
        _id: { $nin: Array.from(excludeSet).map(id => { try { return new mongoose.Types.ObjectId(id); } catch(e) { return null; } }).filter(Boolean) }
      }, professionId);

      const candidates = await Video.find(matchStage).sort({ finalScore: -1, createdAt: -1 }).limit(200).select('_id videoHash uploader finalScore createdAt targetProfessionIds').lean();

      if (candidates.length > 0) {
          let filtered = candidates;
          if (redisAvailable) {
            const sFlags = await redisService.bfMExists(`user:bf_seen:${userId}`, candidates.map(v => v._id.toString()));
            filtered = candidates.filter((v, i) => !sFlags[i]);
          }
          const randomized = RecommendationService.weightedShuffle(filtered, Math.min(filtered.length, count * 3));
          const ordered = await RecommendationService.orderFeedWithDiversity(randomized, { minCreatorSpacing: 3 });
          finalIds.push(...ordered.slice(0, count).map(v => v._id.toString()));
      }
    } catch (e) {}

    if (finalIds.length < count && userId && userId !== 'anon') {
       const need = count - finalIds.length;
       const lruOldestIds = await FeedHistory.getLRUVideos(userId, 50, [], 48);
       if (lruOldestIds.length > 0) {
          const filtered = lruOldestIds.filter(id => !excludeSet.has(id.toString()) && !finalIds.includes(id.toString())).slice(0, need);
          finalIds.push(...filtered.map(id => id.toString()));
       }
    }
    return finalIds;
  }

  async populateVideos(videoIds) {
    if (!videoIds || videoIds.length === 0) return [];
    const ids = videoIds.map(id => id.toString()).filter(Boolean);
    const videos = new Array(ids.length).fill(null);
    const missingIds = [];
    const missingIndices = [];

    // v2 includes targetProfessionIds; old cached documents cannot be trusted
    // for hard eligibility checks.
    const cacheKeys = ids.map(id => `video:data:v2:${id}`);
    const cachedDocs = await redisService.mget(cacheKeys);
    
    cachedDocs.forEach((doc, index) => {
      if (doc) videos[index] = doc;
      else { missingIndices.push(index); missingIds.push(ids[index]); }
    });

    if (missingIds.length > 0) {
      const dbDocs = await Video.find({ _id: { $in: missingIds } })
        .select('videoUrl thumbnailUrl description uploader views likes shares comments duration processingStatus createdAt videoHash videoName tags seriesId episodeNumber videoType aspectRatio quizzes link targetProfessionIds')
        .populate('uploader', 'name profilePic googleId username').lean();

      const dbMap = new Map(dbDocs.map(v => [v._id.toString(), v]));
      const toCache = [];
      missingIndices.forEach((origIdx) => {
        const video = dbMap.get(ids[origIdx]);
        if (video) {
          video._id = video._id.toString();
          videos[origIdx] = video;
          toCache.push([`video:data:v2:${video._id}`, video]);
        }
      });
      if (toCache.length > 0) redisService.mset(toCache, 3600).catch(() => {});
    }
    return videos.filter(Boolean);
  }

  async addRecentCreators(userId, creatorIds) {
    if (!creatorIds || creatorIds.length === 0) return;
    const key = `user:recent_creators:${userId}`;
    await Promise.all([
      redisService.lPush(key, creatorIds),
      redisService.lTrim(key, 0, 19),
      redisService.expire(key, 3600),
    ]);
  }

  async getRecentCreators(userId) {
    try { return await redisService.lRange(`user:recent_creators:${userId}`, 0, -1); }
    catch (e) { return []; }
  }

  checkBatchDiversity(candidate, existingBatch) {
    if (!candidate.vectorEmbedding || candidate.vectorEmbedding.length === 0) return false;
    const lastFew = existingBatch.slice(-10);
    for (const v of lastFew) {
        if (v.vectorEmbedding && RecommendationService.calculateCosineSimilarity(candidate.vectorEmbedding, v.vectorEmbedding) > 0.85) return true;
    }
    return false;
  }

  async mergeGuestHistory(deviceId, userId) {
    if (!deviceId || !userId || deviceId === userId || deviceId === 'anon') return;
    try {
      const guestSeenKey = `user:bf_seen:${deviceId}`;
      const guestHashKey = `user:bf_hashes:${deviceId}`;
      const userSeenKey = `user:bf_seen:${userId}`;
      const userHashKey = `user:bf_hashes:${userId}`;

      const guestHistory = await FeedHistory.find({ userId: deviceId }).select('videoId videoHash').lean();
      if (guestHistory.length > 0) {
        await FeedHistory.markAsSeen(userId, guestHistory);
        const ids = guestHistory.map(h => h.videoId.toString());
        const hashes = guestHistory.map(h => h.videoHash).filter(Boolean);

        await Promise.all([
          redisService.bfMAdd(userSeenKey, ids),
          hashes.length > 0 ? redisService.bfMAdd(userHashKey, hashes) : Promise.resolve(),
          redisService.del(guestSeenKey),
          redisService.del(guestHashKey),
          FeedHistory.deleteMany({ userId: deviceId })
        ]);
      }
    } catch (e) {
      console.error('❌ FeedQueue: mergeGuestHistory failed:', e.message);
    }
  }
}

export default new FeedQueueService();
