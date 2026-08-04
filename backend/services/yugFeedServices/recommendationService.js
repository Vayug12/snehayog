import Video from '../../models/Video.js';
import User from '../../models/User.js';
import AdImpression from '../../models/AdImpression.js';
import WatchHistory from '../../models/WatchHistory.js';
import redisService from '../caching/redisService.js';
import { AD_CONFIG } from '../../constants/index.js';
import recEngine from './recommendationEngine/index.js';
import { billableMatch } from '../adServices/impressionCounting.js';

/**
 * Balanced Recommendation System Service
 * Now refactored to use a modular, plug-and-play architecture.
 */
class RecommendationService {
  /**
   * Calculate final recommendation score using the modular engine
   */
  static async calculateScoreWithEngine(videoData, context = {}) {
    const results = await recEngine.recommend([videoData], context);
    return results[0]?.finalScore || 0.01;
  }

  /**
   * Legacy method kept for internal compatibility
   * Redirects to the modular logic
   */
  static calculateFinalScore(videoData) {
    const {
      totalWatchTime = 0,
      duration = 0,
      likes = 0,
      comments = 0,
      shares = 0,
      views = 0,
      skipCount = 0,
      uploadedAt
    } = videoData;

    const commentCount = Array.isArray(comments) ? comments.length : (comments || 0);

    const watchScore = this._legacyCalculateWatchScore(totalWatchTime, duration, views);
    const engagementScore = this._legacyCalculateWilsonScore(likes + commentCount, views);
    const shareScore = Math.min((shares / (views || 1)) / 0.1, 1);
    
    const now = new Date();
    const ageInHours = (now - new Date(uploadedAt)) / (1000 * 60 * 60);
    const freshnessBoost = ageInHours < 120 ? 3.0 * (1 - (ageInHours / 120)) : 0;
    
    const skipPenalty = Math.max(0, (views > 0 ? skipCount / views : 0) * 2.0);
    const baseScore = 0.6 * watchScore + 0.2 * engagementScore + 0.2 * shareScore;
    const recencyBoost = 0.1 + (0.9 / (1 + (ageInHours / 24) * 0.1));

    return Math.max((baseScore + freshnessBoost - skipPenalty) * recencyBoost, 0.01);
  }

  static _legacyCalculateWatchScore(totalWatchTime, videoDuration, totalViews) {
    if (!videoDuration || totalViews <= 0) return 0;
    const avgWatchTime = totalWatchTime / totalViews;
    return 0.5 * (avgWatchTime / videoDuration) + 0.5 * (Math.min(avgWatchTime, 15) / 15);
  }

  static _legacyCalculateWilsonScore(positive, total) {
    if (total <= 0) return 0;
    const p = (positive + 0.5) / (total + 5);
    const z = 1.96;
    return (p + (z * z) / (2 * total) - z * Math.sqrt((p * (1 - p) + (z * z) / (4 * total)) / total)) / (1 + (z * z) / total);
  }

  /**
   * Weighted Shuffle (Delegates to Engine)
   */
  static weightedShuffle(videos, count) {
    return recEngine._weightedShuffle(videos, count);
  }

  /**
   * Aggregate total watch time for a video
   */
  static async aggregateTotalWatchTime(videoId) {
    try {
      const result = await WatchHistory.aggregate([
        { $match: { videoId: videoId } },
        { $group: { _id: null, totalWatchTime: { $sum: '$watchDuration' } } }
      ]);
      return result.length > 0 ? (result[0].totalWatchTime || 0) : 0;
    } catch (error) {
      return 0;
    }
  }

  /**
   * Calculate and update score for a single video
   */
  static async calculateAndUpdateVideoScore(videoId) {
    try {
      const video = await Video.findById(videoId);
      if (!video) throw new Error(`Video not found: ${videoId}`);

      const totalWatchTime = await this.aggregateTotalWatchTime(videoId);
      const finalScore = await this.calculateScoreWithEngine(video, { user: 'anon' });

      video.totalWatchTime = totalWatchTime;
      video.finalScore = finalScore;
      video.scoreUpdatedAt = new Date();
      await video.save();

      return { videoId: video._id, finalScore };
    } catch (error) {
      console.error(`❌ Error updating score for ${videoId}:`, error);
      throw error;
    }
  }

  /**
   * Order feed with diversity (Delegates to Engine)
   */
  static async orderFeedWithDiversity(videos, options = {}) {
    return recEngine.recommend(videos, options);
  }

  /**
   * Recalculate scores for all videos
   */
  static async recalculateAllScores(options = {}) {
    const { batchSize = 100, limit = null } = options;
    try {
      console.log('🔄 Recalculating scores using Modular Engine...');
      const query = { processingStatus: 'completed' };
      const totalVideos = await Video.countDocuments(query);
      const actualLimit = limit || totalVideos;

      let processed = 0;
      let skip = 0;

      while (skip < actualLimit) {
        const videos = await Video.find(query).limit(batchSize).skip(skip);
        if (videos.length === 0) break;

        for (const video of videos) {
          await this.calculateAndUpdateVideoScore(video._id);
          processed++;
        }
        skip += batchSize;
        console.log(`✅ Progress: ${processed}/${actualLimit}`);
      }
      return { processed, success: true };
    } catch (error) {
      console.error('❌ Batch recalculation failed:', error);
      throw error;
    }
  }

  /**
   * Get User Interest Vector (Context Generation)
   */
  static async getUserInterestVector(userId) {
    try {
      if (!userId || userId === 'anon') return null;
      const cacheKey = `user:interest_vector:${userId}`;
      const cached = await redisService.get(cacheKey);
      if (cached) return cached;

      const recentWatches = await WatchHistory.find({ userId, isSkip: false })
        .sort({ watchedAt: -1 })
        .limit(15)
        .populate('videoId')
        .lean();

      if (recentWatches.length === 0) return null;
      
      const embeddings = recentWatches
        .map(w => w.videoId?.vectorEmbedding)
        .filter(e => e && e.length > 0);

      if (embeddings.length === 0) return null;
      
      const dim = embeddings[0].length;
      const avg = new Array(dim).fill(0);
      embeddings.forEach(e => e.forEach((v, i) => avg[i] += v));
      const finalVector = avg.map(v => v / embeddings.length);

      await redisService.set(cacheKey, finalVector, 1800);
      return finalVector;
    } catch (e) {
      return null;
    }
  }

  /**
   * Find top semantic matches for a user vector in a pool of videos
   */
  static findTopSemanticMatches(userVector, semanticPool, limit = 500) {
    if (!userVector || !Array.isArray(semanticPool) || semanticPool.length === 0) {
      return [];
    }

    const matches = [];
    const len = userVector.length;
    
    for (const video of semanticPool) {
      if (video.vectorEmbedding && video.vectorEmbedding.length === len) {
        let dotProduct = 0;
        let normA = 0;
        let normB = 0;
        const emb = video.vectorEmbedding;
        
        for (let i = 0; i < len; i++) {
          dotProduct += userVector[i] * emb[i];
          normA += userVector[i] * userVector[i];
          normB += emb[i] * emb[i];
        }
        
        const similarity = (normA === 0 || normB === 0) ? 0 : dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
        
        video.semanticSimilarity = similarity;
        matches.push(video);
      }
    }

    // Sort descending by similarity
    matches.sort((a, b) => b.semanticSimilarity - a.semanticSimilarity);

    return matches.slice(0, limit);
  }

  /**
   * Global Creator Rank & Leaderboard Logic
   */
  static async _calculateAndCacheRanks() {
    const cacheKey = 'global_creator_ranks';
    try {
      const now = new Date();
      const startOfMonth = new Date(Date.UTC(now.getFullYear(), now.getMonth(), 1));
      
      const stats = await AdImpression.aggregate([
        { $match: { ...billableMatch(), timestamp: { $gte: startOfMonth } } },
        {
          $group: {
            _id: { creator: '$creatorId', adType: '$adType' },
            totalViews: { $sum: { $cond: [{ $gt: ['$viewCount', 0] }, '$viewCount', 1] } }
          }
        },
        {
          $group: {
            _id: '$_id.creator',
            bannerViews: { $sum: { $cond: [{ $eq: ['$_id.adType', 'banner'] }, '$totalViews', 0] } },
            carouselViews: { $sum: { $cond: [{ $eq: ['$_id.adType', 'carousel'] }, '$totalViews', 0] } }
          }
        }
      ]);

      const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10;
      const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30;
      const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8;

      const rankedList = stats.map(s => {
        const earnings = ((s.bannerViews / 1000) * bannerCpm + (s.carouselViews / 1000) * carouselCpm) * creatorShare;
        return { id: s._id?.toString(), earnings };
      })
      .filter(item => item.id)
      .sort((a, b) => b.earnings - a.earnings);

      const rankMap = {};
      rankedList.forEach((item, index) => { rankMap[item.id] = index + 1; });

      if (redisService.getConnectionStatus()) {
        await redisService.set(cacheKey, rankMap, 3600);
      }
      return { rankMap, rankedList };
    } catch (error) {
      console.error('❌ Rank calculation failed:', error);
      return { rankMap: {}, rankedList: [] };
    }
  }

  static async getGlobalLeaderboard(limit = 20) {
    const cacheKey = 'global_leaderboard_list';
    try {
      if (redisService.getConnectionStatus()) {
        const cached = await redisService.get(cacheKey);
        if (cached) return cached.slice(0, limit);
      }

      const { rankedList } = await this._calculateAndCacheRanks();
      const topCreatorIds = rankedList.slice(0, 50).map(item => item.id);
      
      const users = await User.find({ _id: { $in: topCreatorIds } })
        .select('googleId name profilePic videos')
        .lean();

      const userMap = {};
      users.forEach(u => { userMap[u._id.toString()] = u; });

      const leaderboard = rankedList.slice(0, 50).map((item, index) => {
        const user = userMap[item.id];
        if (!user) return null;
        return {
          rank: index + 1,
          googleId: user.googleId,
          name: user.name,
          profilePic: user.profilePic,
          videoCount: user.videos?.length || 0
        };
      }).filter(Boolean);

      if (redisService.getConnectionStatus() && leaderboard.length > 0) {
        await redisService.set(cacheKey, leaderboard, 3600);
      }
      return leaderboard.slice(0, limit);
    } catch (error) {
      return [];
    }
  }

  /**
   * Get Global Creator Rank for a given user ID
   */
  static async getGlobalCreatorRank(creatorId) {
    if (!creatorId) return 0;
    const cidStr = creatorId.toString();
    const cacheKey = 'global_creator_ranks';
    try {
      let rankMap = null;
      if (redisService.getConnectionStatus()) {
        rankMap = await redisService.get(cacheKey);
      }
      
      if (!rankMap) {
        const result = await this._calculateAndCacheRanks();
        rankMap = result.rankMap;
      }
      
      return rankMap[cidStr] || 0;
    } catch (error) {
      console.error(`❌ Error in getGlobalCreatorRank for ${creatorId}:`, error);
      return 0;
    }
  }

  /**
   * Enforces that no more than maxConsecutive videos from the same creator appear consecutively in the feed.
   */
  static enforceMaxConsecutive(videos, maxConsecutive = 2) {
    if (!Array.isArray(videos) || videos.length <= maxConsecutive) return videos;

    const result = [];
    const pool = [...videos];

    while (pool.length > 0) {
      let foundIndex = -1;

      for (let i = 0; i < pool.length; i++) {
        const video = pool[i];
        const uploaderId = video.uploader?._id?.toString() || video.uploader?.toString() || 'unknown';

        let consecutiveCount = 0;
        for (let j = result.length - 1; j >= 0; j--) {
          const prevUploaderId = result[j].uploader?._id?.toString() || result[j].uploader?.toString() || 'unknown';
          if (prevUploaderId === uploaderId) {
            consecutiveCount++;
          } else {
            break;
          }
        }

        if (consecutiveCount < maxConsecutive) {
          foundIndex = i;
          break;
        }
      }

      if (foundIndex !== -1) {
        result.push(pool.splice(foundIndex, 1)[0]);
      } else {
        result.push(pool.shift());
      }
    }

    return result;
  }

  /**
   * Calculate personalized boost for a video and user profile (Language & Region match)
   */
  static calculatePersonalizedBoost(video, userProfile) {
    if (!userProfile || userProfile === 'anon' || userProfile === 'anonymous') return 1.0;
    
    let boost = 1.0;
    
    // 1. Language Match
    if (video.language && userProfile.preferredLanguages && userProfile.preferredLanguages.length > 0) {
      const isPreferred = userProfile.preferredLanguages.some(lang => 
        lang.toLowerCase() === video.language.toLowerCase()
      );
      if (isPreferred) boost += 0.3;
    }
    
    // 2. Region Match
    if (video.detectedRegion && userProfile.location && userProfile.location.state) {
      const videoRegion = video.detectedRegion.toLowerCase();
      const userState = (userProfile.location.state || '').toLowerCase();
      
      if (videoRegion.includes(userState) || userState.includes(videoRegion)) {
        boost += 0.15;
      }
    }
    
    return boost;
  }
}

export default RecommendationService;
