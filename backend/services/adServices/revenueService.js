import mongoose from 'mongoose';
import User from '../../models/User.js';
import Video from '../../models/Video.js';
import { AD_CONFIG } from '../../constants/index.js';
import AdImpression from '../../models/AdImpression.js';
import View from '../../models/View.js';
import { billableMatch } from './impressionCounting.js';

/**
 * Unified service for calculating creator revenue and engagement metrics.
 * Ensures consistency between Public Profile and Admin Dashboard.
 */
class RevenueService {
  /**
   * Calculates revenue and engagement for a specific user and month.
   * 
   * @param {String} userId - Google ID or MongoDB _id of the user
   * @param {Number} month - 0-11 index of the month
   * @param {Number} year - Full year (e.g. 2026)
   * @returns {Object} - Calculated revenue and engagement data
   */
  static async getCreatorRevenueSummary(userId, month, year) {
    try {
      // 1. Resolve User (handle both Google ID and _id)
      let user = await User.findOne({ googleId: userId });
      if (!user && mongoose.Types.ObjectId.isValid(userId)) {
        user = await User.findById(userId);
      }

      if (!user) {
        throw new Error(`User not found: ${userId}`);
      }

      // 2. Resolve Videos (Hybrid Lookup using raw collection to avoid CastError)
      const uploaderIds = [user._id];
      if (user.googleId) uploaderIds.push(user.googleId);

      // Use .collection.find to bypass Mongoose schema casting for Google IDs
      const userVideos = await Video.collection.find({
        $or: [
          { uploader: { $in: uploaderIds } },
          { uploader: String(user._id) }
        ]
      }).project({ _id: 1, views: 1, likes: 1, shares: 1, videoType: 1 }).toArray();
      
      const videoIds = userVideos.map(v => v._id);

      // 3. Define Date Range (UTC)
      const startDate = new Date(Date.UTC(year, month, 1));
      const endDate = new Date(Date.UTC(year, month + 1, 1));

      // 4. Query Ad Impressions (Hybrid Lookup for creatorId)
      // Use raw collection to allow searching for Google ID strings in creatorId
      const bannerCount = await AdImpression.collection.countDocuments({
        adType: 'banner',
        ...billableMatch(),
        timestamp: { $gte: startDate, $lt: endDate },
        $or: [
          { creatorId: user._id },
          { creatorId: user.googleId },
          { creatorId: String(user._id) },
          { videoId: { $in: videoIds } }
        ]
      });

      // No `impressionType` filter: carousel rows are written as 'scroll_view',
      // so requiring 'view' here paid every creator zero for carousel inventory.
      const carouselCount = await AdImpression.collection.countDocuments({
        adType: 'carousel',
        ...billableMatch(),
        timestamp: { $gte: startDate, $lt: endDate },
        $or: [
          { creatorId: user._id },
          { creatorId: user.googleId },
          { creatorId: String(user._id) },
          { videoId: { $in: videoIds } }
        ]
      });

      // 5. Query Historical Impressions (Hybrid Lookup)
      const lastMonthDate = new Date(Date.UTC(year, month - 1, 1));
      const lastMonthEnd = startDate;
      
      const lastMonthBanner = await AdImpression.collection.countDocuments({
        adType: 'banner',
        ...billableMatch(),
        timestamp: { $gte: lastMonthDate, $lt: lastMonthEnd },
        $or: [
          { creatorId: user._id },
          { creatorId: user.googleId },
          { creatorId: String(user._id) },
          { videoId: { $in: videoIds } }
        ]
      });

      const lastMonthCarousel = await AdImpression.collection.countDocuments({
        adType: 'carousel',
        ...billableMatch(),
        timestamp: { $gte: lastMonthDate, $lt: lastMonthEnd },
        $or: [
          { creatorId: user._id },
          { creatorId: user.googleId },
          { creatorId: String(user._id) },
          { videoId: { $in: videoIds } }
        ]
      });

      // 6. Calculate Revenue
      const bannerCpm = AD_CONFIG.BANNER_CPM || 20; 
      const carouselCpm = AD_CONFIG.DEFAULT_CPM || 30; 
      const creatorShare = AD_CONFIG.CREATOR_REVENUE_SHARE || 0.8;

      const currentGross = ((bannerCount / 1000) * bannerCpm) + ((carouselCount / 1000) * carouselCpm);
      const currentNet = currentGross * creatorShare;

      const lastGross = ((lastMonthBanner / 1000) * bannerCpm) + ((lastMonthCarousel / 1000) * carouselCpm);
      const lastNet = lastGross * creatorShare;

      // 7. Calculate Lifetime Totals
      const totalEarningsINR = user.totalEarningsINR || 0;

      // 8. Build Engagement Stats (Lifetime)
      let lifetimeViews = 0;
      let totalLikes = 0;
      let totalShares = 0;
      userVideos.forEach(v => {
        lifetimeViews += (v.views || 0);
        totalLikes += (v.likes || 0);
        totalShares += (v.shares || 0);
      });

      // 9. NEW: Real Monthly Views (Combined from View and WatchHistory)
      // We use a hybrid approach to match both ObjectId and String IDs across different possible field names
      const videoIdStrings = videoIds.map(id => String(id));
      
      const [viewCount, watchStats] = await Promise.all([
        // Check legacy View collection (matches 'video' field)
        mongoose.connection.collection('views').countDocuments({
          $or: [
            { video: { $in: videoIds } },
            { video: { $in: videoIdStrings } },
            { videoId: { $in: videoIds } },
            { videoId: { $in: videoIdStrings } }
          ],
          viewedAt: { $gte: startDate, $lt: endDate }
        }),
        // Check professional WatchHistory collection (matches 'videoId' field and sums 'watchCount')
        mongoose.connection.collection('watchhistories').aggregate([
          {
            $match: {
              $or: [
                { videoId: { $in: videoIds } },
                { videoId: { $in: videoIdStrings } },
                { video: { $in: videoIds } },
                { video: { $in: videoIdStrings } }
              ],
              watchedAt: { $gte: startDate, $lt: endDate }
            }
          },
          {
            $group: {
              _id: null,
              totalViews: { $sum: { $ifNull: ["$watchCount", 1] } }
            }
          }
        ]).toArray()
      ]);

      const monthlyViews = viewCount + (watchStats[0]?.totalViews || 0);

      return {
        success: true,
        userId: user.googleId,
        userName: user.name,
        month: month,
        year: year,
        dateRange: { start: startDate, end: endDate },
        
        thisMonth: Math.round(currentNet * 100) / 100,
        lastMonth: Math.round(lastNet * 100) / 100,
        grossRevenue: Math.round(currentGross * 100) / 100,
        netRevenue: Math.round(currentNet * 100) / 100,
        platformShare: Math.round((currentGross - currentNet) * 100) / 100,
        
        banner: {
          views: bannerCount,
          cpm: bannerCpm,
          revenue: Math.round(((bannerCount / 1000) * bannerCpm) * 100) / 100
        },
        carousel: {
          views: carouselCount,
          cpm: carouselCpm,
          revenue: Math.round(((carouselCount / 1000) * carouselCpm) * 100) / 100
        },

        monthlyViews,
        lifetimeViews,
        totalLikes,
        totalShares,
        videoCount: userVideos.length,
        
        availableForPayout: Math.round(totalEarningsINR * 100) / 100,
        
        videosUploaded: await Video.collection.countDocuments({
          $or: [
            { uploader: { $in: uploaderIds } },
            { uploader: String(user._id) }
          ],
          createdAt: { $gte: startDate, $lt: endDate },
          processingStatus: 'completed'
        })
      };

    } catch (error) {
      console.error('❌ RevenueService Error:', error);
      return { 
        success: false, 
        error: error.message,
        thisMonth: 0,
        lastMonth: 0,
        netRevenue: 0,
        banner: { views: 0 },
        carousel: { views: 0 },
        monthlyViews: 0,
        lifetimeViews: 0,
        videosUploaded: 0
      };
    }
  }
}

export default RevenueService;
