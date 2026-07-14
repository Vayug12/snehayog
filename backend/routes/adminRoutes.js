import express from 'express';
import mongoose from 'mongoose';
import Feedback from '../models/Feedback.js';
import requireAdminDashboardKey from '../middleware/adminDashboardAuth.js';
import User from '../models/User.js';
import Video from '../models/Video.js';
import CreatorPayout from '../models/CreatorPayout.js';
import AdImpression from '../models/AdImpression.js';
import Notice from '../models/Notice.js';
import RemovedVideoRecord from '../models/RemovedVideoRecord.js';
import { AD_CONFIG } from '../constants/index.js';
import RecommendationService from '../services/yugFeedServices/recommendationService.js';
import WatchHistory from '../models/WatchHistory.js';
import RevenueService from '../services/adServices/revenueService.js';
import brevoService from '../services/notificationServices/brevoService.js';
import queueService from '../services/yugFeedServices/queueService.js';

const router = express.Router();






// Admin feedback endpoints
router.get('/feedback', requireAdminDashboardKey, async (req, res) => {
  try {
    const {
      limit = 50,
      rating,
      search,
      sort = 'desc',
      unread,
      replied,
      type
    } = req.query;

    const query = {};

    if (rating) {
      const parsedRating = parseInt(rating, 10);
      if (!Number.isNaN(parsedRating)) {
        query.rating = parsedRating;
      }
    }

    if (type) {
      query.type = type;
    }

    if (unread === 'true') {
      query.isRead = false;
    } else if (unread === 'false') {
      query.isRead = true;
    }

    if (replied === 'true') {
      query.isReplied = true;
    } else if (replied === 'false') {
      query.isReplied = false;
    }

    if (search && search.trim()) {
      const regex = new RegExp(search.trim(), 'i');
      query.$or = [
        { comments: regex },
        { userEmail: regex },
        { adminReply: regex }
      ];
    }

    const sortOrder = sort === 'asc' ? 1 : -1;
    const normalizedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 200);

    const feedback = await Feedback.find(query)
      .sort({ createdAt: sortOrder })
      .limit(normalizedLimit)
      .lean();

    // **NEW: Populate User Names**
    const emails = [...new Set(feedback.map(f => f.userEmail).filter(Boolean))];
    const users = await User.find({ email: { $in: emails } }).select('email name').lean();
    
    const userMap = {};
    users.forEach(u => {
      userMap[u.email.toLowerCase()] = u.name;
    });

    // Attach names
    feedback.forEach(f => {
      if (f.userEmail) {
        f.userName = userMap[f.userEmail.toLowerCase()] || 'Unknown User';
      }
    });

    res.json({
      success: true,
      count: feedback.length,
      feedback
    });
  } catch (error) {
    console.error('❌ Error loading feedback:', error);
    res.status(500).json({ success: false, error: 'Failed to load feedback' });
  }
});

router.get('/feedback/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    const stats = await Feedback.getStats();
    res.json({ success: true, stats });
  } catch (error) {
    console.error('❌ Error loading feedback stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load feedback stats' });
  }
});

router.get('/feedback/:id', requireAdminDashboardKey, async (req, res) => {
  try {
    const feedback = await Feedback.findById(req.params.id).lean();
    if (!feedback) {
      return res.status(404).json({ success: false, error: 'Feedback not found' });
    }
    res.json(feedback);
  } catch (error) {
    console.error('❌ Error loading feedback detail:', error);
    res.status(500).json({ success: false, error: 'Failed to load feedback detail' });
  }
});

router.put('/feedback/:id/read', requireAdminDashboardKey, async (req, res) => {
  try {
    const feedback = await Feedback.findById(req.params.id);
    if (!feedback) {
      return res.status(404).json({ success: false, error: 'Feedback not found' });
    }

    if (!feedback.isRead) {
      feedback.isRead = true;
      feedback.readAt = new Date();
      await feedback.save();
    }

    res.json({ success: true, message: 'Feedback marked as read' });
  } catch (error) {
    console.error('❌ Error marking feedback as read:', error);
    res.status(500).json({ success: false, error: 'Failed to mark feedback as read' });
  }
});

router.post('/feedback/:id/reply', requireAdminDashboardKey, async (req, res) => {
  try {
    const { reply } = req.body;
    if (!reply || !reply.trim()) {
      return res.status(400).json({ success: false, error: 'Reply is required' });
    }

    const feedback = await Feedback.findById(req.params.id);
    if (!feedback) {
      return res.status(404).json({ success: false, error: 'Feedback not found' });
    }

    feedback.adminReply = reply.trim();
    feedback.isReplied = true;
    feedback.repliedAt = new Date();
    await feedback.save();

    res.json({ success: true, message: 'Reply recorded successfully' });
  } catch (error) {
    console.error('❌ Error replying to feedback:', error);
    res.status(500).json({ success: false, error: 'Failed to reply to feedback' });
  }
});

router.get('/feedback/export', requireAdminDashboardKey, async (req, res) => {
  try {
    const feedback = await Feedback.find().sort({ createdAt: -1 }).lean();

    const headers = [
      'id',
      'rating',
      'comments',
      'userEmail',
      'userId',
      'isRead',
      'readAt',
      'isReplied',
      'adminReply',
      'repliedAt',
      'createdAt',
      'updatedAt'
    ];

    const escapeCsv = (value) => {
      if (value === null || value === undefined) return '';
      const stringValue = String(value).replace(/"/g, '""');
      if (/[",\n]/.test(stringValue)) {
        return `"${stringValue}"`;
      }
      return stringValue;
    };

    const rows = feedback.map((item) => [
      item._id,
      item.rating,
      item.comments || '',
      item.userEmail,
      item.userId || '',
      item.isRead,
      item.readAt ? item.readAt.toISOString() : '',
      item.isReplied,
      item.adminReply || '',
      item.repliedAt ? item.repliedAt.toISOString() : '',
      item.createdAt ? item.createdAt.toISOString() : '',
      item.updatedAt ? item.updatedAt.toISOString() : ''
    ]);

    const csvContent = [
      headers.join(','),
      ...rows.map((row) => row.map(escapeCsv).join(','))
    ].join('\n');

    res.setHeader(
      'Content-Disposition',
      `attachment; filename="feedback-export-${new Date().toISOString().split('T')[0]}.csv"`
    );
    res.setHeader('Content-Type', 'text/csv');
    res.send(csvContent);
  } catch (error) {
    console.error('❌ Error exporting feedback:', error);
    res.status(500).json({ success: false, error: 'Failed to export feedback' });
  }
});

router.get('/creators', requireAdminDashboardKey, async (req, res) => {
  try {
    const [creators, videoStats, adStats, payoutStats, earningsStats] = await Promise.all([
      User.find({}, 'name email preferredPaymentMethod paymentDetails country payoutCount createdAt googleId lastActive isAppUninstalled lastInstallCheck fcmToken appVersion').lean(),
      Video.aggregate([
        {
          $group: {
            _id: '$uploader',
            totalViews: { $sum: '$views' },
            totalVideos: {
              $sum: {
                $cond: [{ $eq: ['$processingStatus', 'completed'] }, 1, 0]
              }
            }
          }
        }
      ]),
      AdImpression.aggregate([
        {
          $group: {
            _id: '$videoId',
            totalAdViews: {
              $sum: {
                $cond: [
                  { $gt: ['$viewCount', 0] },
                  '$viewCount',
                  { $cond: ['$isViewed', 1, 0] }
                ]
              }
            },
            totalAdImpressions: { $sum: 1 }
          }
        },
        {
          $lookup: {
            from: 'videos',
            localField: '_id',
            foreignField: '_id',
            as: 'video'
          }
        },
        { $unwind: '$video' },
        {
          $group: {
            _id: '$video.uploader',
            totalAdViews: { $sum: '$totalAdViews' },
            totalAdImpressions: { $sum: '$totalAdImpressions' }
          }
        }
      ]),
      CreatorPayout.aggregate([
        {
          $group: {
            _id: '$creatorId',
            totalEarningsINR: { $sum: '$payableINR' },
            pendingEarningsINR: {
              $sum: {
                $cond: [{ $eq: ['$status', 'pending'] }, '$payableINR', 0]
              }
            },
            processingEarningsINR: {
              $sum: {
                $cond: [{ $eq: ['$status', 'processing'] }, '$payableINR', 0]
              }
            },
            paidEarningsINR: {
              $sum: {
                $cond: [{ $eq: ['$status', 'paid'] }, '$payableINR', 0]
              }
            },
            eligiblePendingINR: {
              $sum: {
                $cond: [
                  {
                    $and: [
                      { $eq: ['$status', 'pending'] },
                      '$isEligibleForPayout'
                    ]
                  },
                  '$payableINR',
                  0
                ]
              }
            },
            lastPayoutAt: { $max: '$paymentDate' }
          }
        }
      ]),
      AdImpression.aggregate([
        { $match: { isViewed: true } },
        {
          $lookup: {
            from: 'videos',
            localField: 'videoId',
            foreignField: '_id',
            as: 'video'
          }
        },
        { $unwind: '$video' },
        {
          $group: {
            _id: { creator: '$video.uploader', adType: '$adType' },
            viewSum: {
              $sum: {
                $cond: [
                  { $gt: ['$viewCount', 0] },
                  '$viewCount',
                  1
                ]
              }
            }
          }
        },
        {
          $group: {
            _id: '$_id.creator',
            bannerViews: {
              $sum: {
                $cond: [
                  { $eq: ['$_id.adType', 'banner'] },
                  '$viewSum',
                  0
                ]
              }
            },
            carouselViews: {
              $sum: {
                $cond: [
                  { $eq: ['$_id.adType', 'carousel'] },
                  '$viewSum',
                  0
                ]
              }
            },
            totalAdViews: { $sum: '$viewSum' }
          }
        }
      ])
    ]);

    const videoMap = new Map();
    videoStats.forEach((stat) => {
      videoMap.set(String(stat._id), {
        totalViews: stat.totalViews || 0,
        totalVideos: stat.totalVideos || 0
      });
    });

    const adMap = new Map();
    adStats.forEach((stat) => {
      adMap.set(String(stat._id), {
        totalAdViews: stat.totalAdViews || 0,
        totalAdImpressions: stat.totalAdImpressions || 0
      });
    });

    const payoutMap = new Map();
    payoutStats.forEach((stat) => {
      payoutMap.set(String(stat._id), {
        totalEarningsINR: stat.totalEarningsINR || 0,
        pendingEarningsINR: stat.pendingEarningsINR || 0,
        processingEarningsINR: stat.processingEarningsINR || 0,
        paidEarningsINR: stat.paidEarningsINR || 0,
        eligiblePendingINR: stat.eligiblePendingINR || 0,
        lastPayoutAt: stat.lastPayoutAt || null
      });
    });

    const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10;
    const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30;
    const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8;
    const platformShare = AD_CONFIG?.PLATFORM_REVENUE_SHARE ?? 0.2;

    const earningsMap = new Map();
    earningsStats.forEach((stat) => {
      const totalViews = stat.totalAdViews || 0;
      const bannerViews = stat.bannerViews || 0;
      const carouselViews = stat.carouselViews || 0;
      const bannerRevenue = (bannerViews / 1000) * bannerCpm;
      const carouselRevenue = (carouselViews / 1000) * carouselCpm;
      const grossRevenueINR = bannerRevenue + carouselRevenue;
      const creatorRevenueINR = grossRevenueINR * creatorShare;
      const platformRevenueINR = grossRevenueINR * platformShare;

      earningsMap.set(String(stat._id), {
        totalAdViews: totalViews,
        bannerViews,
        carouselViews,
        grossRevenueINR,
        creatorRevenueINR,
        platformRevenueINR
      });
    });

    const creatorSummaries = creators.map((creator) => {
      const id = String(creator._id);
      const videos = videoMap.get(id) || { totalViews: 0, totalVideos: 0 };
      const ads = adMap.get(id) || {
        totalAdViews: 0,
        totalAdImpressions: 0
      };
      const payouts = payoutMap.get(id) || {
        totalEarningsINR: 0,
        pendingEarningsINR: 0,
        processingEarningsINR: 0,
        paidEarningsINR: 0,
        eligiblePendingINR: 0,
        lastPayoutAt: null
      };

      const upiId = creator?.paymentDetails?.upiId || null;
      const paymentSummary = {
        preferredPaymentMethod: creator.preferredPaymentMethod || null,
        upiId,
        paypalEmail: creator?.paymentDetails?.paypalEmail || null,
        stripeAccountId: creator?.paymentDetails?.stripeAccountId || null,
        wiseEmail: creator?.paymentDetails?.wiseEmail || null
      };

      const earnings = earningsMap.get(id) || {
        totalAdViews: ads.totalAdViews || 0,
        bannerViews: 0,
        carouselViews: 0,
        grossRevenueINR: 0,
        creatorRevenueINR: 0,
        platformRevenueINR: 0
      };

      const creatorRevenueINR =
        earnings.creatorRevenueINR && earnings.creatorRevenueINR > 0
          ? earnings.creatorRevenueINR
          : payouts.totalEarningsINR || 0;


      return {
        id,
        googleId: creator.googleId,
        name: creator.name,
        email: creator.email,
        country: creator.country || 'IN',
        totalVideos: videos.totalVideos,
        totalViews: videos.totalViews,
        totalAdViews: earnings.totalAdViews,
        bannerAdViews: earnings.bannerViews,
        carouselAdViews: earnings.carouselViews,
        totalAdImpressions: ads.totalAdImpressions,
        grossRevenueINR: earnings.grossRevenueINR,
        creatorRevenueINR,
        platformRevenueINR: earnings.platformRevenueINR,
        reportedPayoutINR: payouts.totalEarningsINR,
        totalEarningsINR: creatorRevenueINR,
        pendingEarningsINR: payouts.pendingEarningsINR,
        processingEarningsINR: payouts.processingEarningsINR,
        paidEarningsINR: payouts.paidEarningsINR,
        eligiblePendingINR: payouts.eligiblePendingINR,
        payoutCount: creator.payoutCount || 0,
        paymentDetails: paymentSummary,
        createdAt: creator.createdAt,
        lastActive: creator.lastActive || null, // **NEW: Track last active time**
        isAppUninstalled: creator.isAppUninstalled || false, // **NEW: Uninstall tracker**
        lastInstallCheck: creator.lastInstallCheck || null,   // **NEW: Uninstall tracker**
        appVersion: creator.appVersion || 'unknown',          // **NEW: App Version Tracker**
        lastPayoutAt: payouts.lastPayoutAt,
        // **NEW: Include videos for frontend revenue calculation**
        videos: [] // Will be populated separately if needed (empty for now to save bandwidth)
      };
    });

    // Removed filter to show all creators regardless of video count
    const creatorsWithVideos = creatorSummaries;

    creatorsWithVideos.sort(
      (a, b) => (b.creatorRevenueINR || 0) - (a.creatorRevenueINR || 0)
    );

    res.json({
      success: true,
      count: creatorsWithVideos.length,
      creators: creatorsWithVideos
    });
  } catch (error) {
    console.error('❌ Error loading creator summaries:', error);
    res
      .status(500)
      .json({ success: false, error: 'Failed to load creator data' });
  }
});

// **NEW: Route to get list of videos uploaded today**
router.get('/videos/daily', requireAdminDashboardKey, async (req, res) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const videos = await Video.find({
      createdAt: {
        $gte: today,
        $lt: tomorrow
      },
      processingStatus: 'completed'
    })
    .populate('uploader', 'name email') // Populate uploader details
    .sort({ createdAt: -1 })
    .lean();

    res.json({
      success: true,
      count: videos.length,
      videos
    });
  } catch (error) {
    console.error('❌ Error loading daily videos:', error);
    res.status(500).json({ success: false, error: 'Failed to load daily videos' });
  }
});

// ✅ Route to get platform-wide statistics
router.get('/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    // Get total videos count (completed only)
    const totalVideos = await Video.countDocuments({ processingStatus: 'completed' });

    // **NEW: Get total users count for App Install data**
    const totalUsers = await User.countDocuments({});

    // **NEW: Get daily upload count (videos uploaded today)**
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const dailyUploadCount = await Video.countDocuments({
      createdAt: {
        $gte: today,
        $lt: tomorrow
      },
      processingStatus: 'completed'
    });

    // **NEW: Daily breakdown by type**
    const dailyVayuCount = await Video.countDocuments({
      createdAt: {
        $gte: today,
        $lt: tomorrow
      },
      videoType: 'vayu',
      processingStatus: 'completed'
    });

    const dailyYogCount = await Video.countDocuments({
      createdAt: {
        $gte: today,
        $lt: tomorrow
      },
      videoType: 'yog',
      processingStatus: 'completed'
    });

    // Calculate total earnings across all creators
    // Get all creators and their earnings
    const creators = await User.find({}).select('_id').lean();
    const creatorIds = creators.map(c => c._id);

    // Get all videos for all creators
    const allVideos = await Video.find({ uploader: { $in: creatorIds } }).select('_id').lean();
    const allVideoIds = allVideos.map(v => v._id);

    // Calculate total ad impressions and earnings
    const bannerImpressions = await AdImpression.countDocuments({
      videoId: { $in: allVideoIds },
      adType: 'banner',
      impressionType: 'view'
    });

    const carouselImpressions = await AdImpression.countDocuments({
      videoId: { $in: allVideoIds },
      adType: 'carousel',
      impressionType: 'view'
    });

    // Calculate revenue (same logic as revenue API)
    const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10; // ₹10 per 1000 impressions
    const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30; // ₹30 per 1000 impressions
    const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8; // 80% to creator

    const bannerRevenueINR = (bannerImpressions / 1000) * bannerCpm;
    const carouselRevenueINR = (carouselImpressions / 1000) * carouselCpm;
    const totalGrossRevenueINR = bannerRevenueINR + carouselRevenueINR;
    const totalCreatorEarningsINR = totalGrossRevenueINR * creatorShare;

    // **NEW: Count flagged videos**
    const flaggedCount = await Video.countDocuments({
      $or: [
        { processingStatus: 'flagged' },
        { 'moderationResult.isFlagged': true }
      ]
    });

    res.json({
      success: true,
      totalVideos,
      totalUsers,
      flaggedCount,
      dailyUploadCount,
      dailyVayuCount, // **NEW**
      dailyYogCount,  // **NEW**
      totalCreatorEarningsINR: Math.round(totalCreatorEarningsINR * 100) / 100,
      totalGrossRevenueINR: Math.round(totalGrossRevenueINR * 100) / 100,
      bannerImpressions,
      carouselImpressions,
      totalAdImpressions: bannerImpressions + carouselImpressions
    });
  } catch (error) {
    console.error('❌ Error loading platform stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load platform stats' });
  }
});

// **NEW: Route to get recommendation system effectiveness**
router.get('/recommender/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    const stats = await RecommendationService.getRecommendationStats();
    if (!stats) {
      return res.status(500).json({ success: false, error: 'Failed to generate metrics' });
    }
    res.json({ success: true, stats });
  } catch (error) {
    console.error('❌ Error loading recommendation stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load recommendation stats' });
  }
});

// **NEW: Route to get detailed user behavior metrics**
router.get('/user-behavior/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    const { range = 'all' } = req.query;
    let matchStage = {};

    if (range === 'month') {
      const now = new Date();
      const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
      matchStage = { createdAt: { $gte: startOfMonth } };
    }

    // 1. Global Metrics
    const globalMetricsAgg = await WatchHistory.aggregate([
      { $match: matchStage },
      {
        $group: {
          _id: null,
          totalWatchTime: { $sum: '$watchDuration' },
          totalEntries: { $sum: 1 },
          avgWatchDuration: { $avg: '$watchDuration' }
        }
      }
    ]);

    const globalMetrics = globalMetricsAgg[0] || { totalWatchTime: 0, totalEntries: 0, avgWatchDuration: 0 };
    
    // Count unique users across watch history
    const uniqueUsersCountAgg = await WatchHistory.aggregate([
      { $match: matchStage },
      { $group: { _id: '$userId' } },
      { $count: 'count' }
    ]);
    const totalUniqueUsers = uniqueUsersCountAgg[0]?.count || 0;

    // 2. Skip Distribution (Bucketed watch duration for skips)
    const skipDistribution = await WatchHistory.aggregate([
      { 
        $match: { 
          ...matchStage,
          isSkip: true 
        } 
      },
      {
        $bucket: {
          groupBy: '$watchDuration',
          boundaries: [0, 3, 10, 30, 60],
          default: '60+'
        }
      }
    ]);

    // 3. Interest & Category Performance
    const interestStats = await WatchHistory.aggregate([
      { $match: matchStage },
      {
        $lookup: {
          from: 'videos',
          localField: 'videoId',
          foreignField: '_id',
          as: 'video'
        }
      },
      { $unwind: '$video' },
      {
        $group: {
          _id: '$video.category',
          totalDuration: { $sum: '$watchDuration' },
          viewCount: { $sum: 1 },
          skipCount: {
            $sum: { $cond: ['$isSkip', 1, 0] }
          }
        }
      },
      { $sort: { totalDuration: -1 } },
      { $limit: 15 }
    ]);

    // 4. User-Specific Usage Table (Top 100 most active users)
    const userUsageTable = await WatchHistory.aggregate([
      { $match: matchStage },
      {
        $group: {
          _id: '$userId',
          totalWatchTime: { $sum: '$watchDuration' },
          videoCount: { $sum: 1 },
          lastActivity: { $max: '$updatedAt' }
        }
      },
      { $sort: { totalWatchTime: -1 } },
      { $limit: 100 }
    ]);

    // Fetch user details (names/emails) to populate the table
    const userIds = userUsageTable.map(u => u._id);
    // Find by either googleId or _id (depending on how userId is stored in WatchHistory)
    const users = await User.find({
      $or: [
        { googleId: { $in: userIds } },
        { _id: { $in: userIds.filter(id => mongoose.Types.ObjectId.isValid(id)) } }
      ]
    }).select('name email googleId appVersion location').lean();

    const userMap = new Map();
    users.forEach(u => {
      userMap.set(u.googleId || String(u._id), u);
    });

    const populatedUserTable = userUsageTable.map(u => {
      const userData = userMap.get(u._id) || { name: 'Anonymous/Deleted', email: '—' };
      return {
        ...u,
        name: userData.name,
        email: userData.email,
        googleId: userData.googleId || u._id,
        appVersion: userData.appVersion || 'unknown',
        location: userData.location || null
      };
    });

    res.json({
      success: true,
      metrics: {
        totalWatchTime: globalMetrics.totalWatchTime,
        totalUniqueUsers,
        avgDurationPerUser: totalUniqueUsers > 0 ? (globalMetrics.totalWatchTime / totalUniqueUsers) : 0,
        avgDurationPerView: globalMetrics.avgWatchDuration,
        totalViews: globalMetrics.totalEntries
      },
      skipDistribution,
      interests: interestStats,
      userTable: populatedUserTable
    });

  } catch (error) {
    console.error('❌ Error loading user behavior stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load user behavior statistics' });
  }
});

// **NEW: Admin endpoint to get monthly earnings for all creators**
router.get('/creators/monthly-earnings', requireAdminDashboardKey, async (req, res) => {
  try {
    const { month, year } = req.query; // **NEW: Support filtering by month/year**

    const creators = await User.find({}).select('_id googleId name email').lean();
    
    // Calculate current month and last month (or requested month)
    const now = new Date();
    const targetMonth = month !== undefined ? parseInt(month) : now.getUTCMonth();
    const targetYear = year !== undefined ? parseInt(year) : now.getUTCFullYear();

    console.log(`📊 Admin Unified Fetch: Month=${targetMonth}, Year=${targetYear}`);

    // Calculate last month for labels
    const lastMonth = targetMonth === 0 ? 11 : targetMonth - 1;
    const lastMonthYear = targetMonth === 0 ? targetYear - 1 : targetYear;

    // Calculate monthly earnings for ALL creators using Unified RevenueService
    const monthlyEarnings = await Promise.all(
      creators.map(async (creator) => {
        const summary = await RevenueService.getCreatorRevenueSummary(creator._id, targetMonth, targetYear);
        
        if (summary.success) {
          return {
            creatorId: creator._id,
            googleId: creator.googleId,
            name: creator.name,
            email: creator.email,
            thisMonth: summary.thisMonth,
            lastMonth: summary.lastMonth,
            currentMonthGrossRevenue: summary.grossRevenue,
            currentMonthBannerViews: summary.banner?.views || 0,
            currentMonthCarouselViews: summary.carousel?.views || 0,
            currentMonthTotalAdViews: (summary.banner?.views || 0) + (summary.carousel?.views || 0),
            currentMonthTotalViews: summary.monthlyViews || 0,
            lifetimeViews: summary.lifetimeViews || 0,
            videosUploaded: summary.videosUploaded || 0,
            // Additional fields for admin list view
            lastActive: creator.lastActive,
            appVersion: creator.appVersion,
            isAppUninstalled: creator.isAppUninstalled
          };
        }
        
        // Fallback for failed/empty summary
        return {
          creatorId: creator._id,
          googleId: creator.googleId,
          name: creator.name,
          email: creator.email,
          thisMonth: 0,
          lastMonth: 0,
          videosUploaded: 0
        };
      })
    );

    // Sort by current month earnings (descending)
    monthlyEarnings.sort((a, b) => b.thisMonth - a.thisMonth);

    // Calculate totals
    const totalThisMonth = monthlyEarnings.reduce((sum, c) => sum + c.thisMonth, 0);
    const totalLastMonth = monthlyEarnings.reduce((sum, c) => sum + c.lastMonth, 0);

    res.json({
      success: true,
      currentMonth: `${targetYear}-${String(targetMonth + 1).padStart(2, '0')}`,
      lastMonth: `${lastMonthYear}-${String(lastMonth + 1).padStart(2, '0')}`,
      totalThisMonth: Math.round(totalThisMonth * 100) / 100,
      totalLastMonth: Math.round(totalLastMonth * 100) / 100,
      creators: monthlyEarnings
    });
  } catch (error) {
    console.error('❌ Error loading monthly earnings:', error);
    res.status(500).json({ success: false, error: 'Failed to load monthly earnings' });
  }
});

// **NEW: Admin endpoint to get ad impressions for a specific creator (for frontend calculation)**
router.get('/creators/:creatorId/ad-impressions', requireAdminDashboardKey, async (req, res) => {
  try {
    const { creatorId } = req.params;
    const { month, year } = req.query;

    // Find creator by googleId
    const creator = await User.findOne({ googleId: creatorId }).select('_id').lean();
    if (!creator) {
      return res.status(404).json({
        success: false,
        error: 'Creator not found',
        bannerViews: 0,
        carouselViews: 0
      });
    }

    // Get creator's videos
    const videos = await Video.find({ uploader: creator._id }).select('_id').lean();
    const videoIds = videos.map(v => v._id);

    if (videoIds.length === 0) {
      return res.json({
        success: true,
        bannerViews: 0,
        carouselViews: 0,
        month: parseInt(month),
        year: parseInt(year)
      });
    }

    // Parse month and year
    const monthNum = parseInt(month);
    const yearNum = parseInt(year);

    // Calculate month start and end dates
    const monthStart = new Date(yearNum, monthNum, 1);
    const monthEnd = new Date(yearNum, monthNum + 1, 1);

    // Count banner ad impressions for the specified month
    const bannerViews = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'banner',
      impressionType: 'view',
      isViewed: true, // **FIX: Only count verified views**
      timestamp: {
        $gte: monthStart,
        $lt: monthEnd
      }
    });

    // Count carousel ad impressions for the specified month
    const carouselViews = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'carousel',
      impressionType: 'view',
      isViewed: true, // **FIX: Only count verified views**
      timestamp: {
        $gte: monthStart,
        $lt: monthEnd
      }
    });

    res.json({
      success: true,
      creatorId,
      month: monthNum,
      year: yearNum,
      bannerViews,
      carouselViews,
      totalAdViews: bannerViews + carouselViews
    });
  } catch (error) {
    console.error('❌ Error fetching creator ad impressions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch ad impressions',
      bannerViews: 0,
      carouselViews: 0
    });
  }
});

// **NEW: Admin endpoint to get all videos with search/filter**

router.get('/videos', requireAdminDashboardKey, async (req, res) => {
  try {
    const { search, limit = 50, skip = 0 } = req.query;
    const query = {};

    if (search && search.trim()) {
      const searchRegex = new RegExp(search.trim(), 'i');
      query.$or = [
        { videoName: searchRegex },
        { description: searchRegex }
      ];
    }

    const videos = await Video.find(query)
      .populate('uploader', 'name email googleId')
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .lean();

    const totalCount = await Video.countDocuments(query);

    res.json({
      success: true,
      videos: videos.map(v => ({
        _id: v._id,
        videoName: v.videoName,
        description: v.description,
        views: v.views || 0,
        likes: v.likes || 0,
        createdAt: v.createdAt,
        uploader: v.uploader ? {
          name: v.uploader.name,
          email: v.uploader.email,
          googleId: v.uploader.googleId
        } : null,
        videoUrl: v.videoUrl,
        thumbnailUrl: v.thumbnailUrl
      })),
      totalCount,
      limit: parseInt(limit),
      skip: parseInt(skip)
    });
  } catch (error) {
    console.error('❌ Error loading videos:', error);
    res.status(500).json({ success: false, error: 'Failed to load videos' });
  }
});

// **NEW: Admin endpoint to delete any video**
router.delete('/videos/:videoId', requireAdminDashboardKey, async (req, res) => {
  try {
    const { videoId } = req.params;

    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ success: false, error: 'Video not found' });
    }

    // Remove video from user's videos array
    if (video.uploader) {
      await User.findByIdAndUpdate(video.uploader, {
        $pull: { videos: videoId }
      });
    }

    // Delete the video
    await Video.findByIdAndDelete(videoId);

    // Clean up queue jobs
    await queueService.removeVideoJob(videoId);

    console.log(`✅ Admin deleted video: ${videoId} - ${video.videoName}`);

    res.json({
      success: true,
      message: 'Video deleted successfully',
      deletedVideo: {
        id: videoId,
        name: video.videoName
      }
    });
  } catch (error) {
    console.error('❌ Error deleting video:', error);
    res.status(500).json({ success: false, error: 'Failed to delete video' });
  }
});

// **NEW: Video Soft-Removal (Transparency Logging then Permanent Deletion)**
router.post('/videos/:videoId/remove', requireAdminDashboardKey, async (req, res) => {
  try {
    const { videoId } = req.params;
    const { reason } = req.body;

    if (!reason) {
      return res.status(400).json({ error: 'Reason for removal is required' });
    }

    const video = await Video.findById(videoId).populate('uploader');
    if (!video) {
        return res.status(404).json({ error: 'Video not found' });
    }

    const uploaderId = video.uploader ? video.uploader.googleId : null;
    
    if (!uploaderId) {
      return res.status(400).json({ error: 'Uploader information not found' });
    }

    // 1. Create a record in RemovedVideoRecord for transparency (3-day history)
    await RemovedVideoRecord.create({
      originalVideoId: video._id,
      uploaderId: uploaderId,
      videoName: video.videoName,
      thumbnailUrl: video.thumbnailUrl,
      reason: reason,
      removedAt: new Date()
    });

    // 2. Notify the creator via Notice system
    try {
      await Notice.create({
        userId: uploaderId,
        title: `Content Removed: ${video.videoName}`,
        type: 'warning'
      });
    } catch (noticeError) {
      console.warn('⚠️ Admin Moderation: Failed to create notice', noticeError);
    }

    // 3. Remove the video ID from the user's videos array
    await User.findOneAndUpdate(
      { googleId: uploaderId },
      { $pull: { videos: video._id } }
    );

    // 4. PERMANENTLY DELETE the video from the database
    await Video.findByIdAndDelete(videoId);

    // Clean up queue jobs
    await queueService.removeVideoJob(videoId);

    res.json({
      success: true,
      message: 'Video permanently removed and logged for creator transparency.',
      removalInfo: {
        id: videoId,
        name: video.videoName,
        reason: reason
      }
    });

  } catch (error) {
    console.error('❌ Admin Moderation Error:', error);
    res.status(500).json({ error: 'Internal server error during removal' });
  }
});

// **NEW: Admin endpoint to manually trigger recommendation score recalculation**
router.post('/recalculate-scores', requireAdminDashboardKey, async (req, res) => {
  try {
    const { onlyOutdated = false, maxAgeMinutes = 15, limit = null } = req.body;

    console.log('🔄 Admin triggered score recalculation:', {
      onlyOutdated,
      maxAgeMinutes,
      limit
    });

    const stats = await RecommendationService.recalculateAllScores({
      batchSize: 100,
      onlyOutdated: onlyOutdated === true,
      maxAgeMinutes: parseInt(maxAgeMinutes) || 15,
      limit: limit ? parseInt(limit) : null
    });

    res.json({
      success: true,
      message: 'Score recalculation completed',
      stats
    });
  } catch (error) {
    console.error('❌ Error in admin score recalculation:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to recalculate scores',
      message: error.message
    });
  }
});

// **NEW: Admin endpoint to get flagged (NSFW) videos**
router.get('/videos/flagged', requireAdminDashboardKey, async (req, res) => {
  try {
    const flaggedVideos = await Video.find({
      $or: [
        { processingStatus: 'flagged' },
        { 'moderationResult.isFlagged': true }
      ]
    })
    .populate('uploader', 'name email googleId')
    .sort({ updatedAt: -1 })
    .limit(100)
    .lean();

    res.json({
      success: true,
      count: flaggedVideos.length,
      videos: flaggedVideos.map(v => ({
        _id: v._id,
        videoName: v.videoName,
        description: v.description,
        thumbnailUrl: v.thumbnailUrl,
        videoUrl: v.videoUrl,
        views: v.views || 0,
        processingStatus: v.processingStatus,
        moderationResult: v.moderationResult || {},
        createdAt: v.createdAt,
        updatedAt: v.updatedAt,
        uploader: v.uploader ? {
          name: v.uploader.name,
          email: v.uploader.email,
          googleId: v.uploader.googleId
        } : null
      }))
    });
  } catch (error) {
    console.error('❌ Error loading flagged videos:', error);
    res.status(500).json({ success: false, error: 'Failed to load flagged videos' });
  }
});

// **NEW: Admin endpoint to unflag a video (approve it)**
router.post('/videos/:videoId/unflag', requireAdminDashboardKey, async (req, res) => {
  try {
    const { videoId } = req.params;
    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ success: false, error: 'Video not found' });
    }

    video.processingStatus = 'completed';
    video.moderationResult = {
      ...video.moderationResult,
      isFlagged: false,
      processedAt: new Date(),
      provider: 'admin-override'
    };
    await video.save();

    console.log(`✅ Admin unflagged video: ${videoId} - ${video.videoName}`);
    res.json({ success: true, message: 'Video unflagged and approved' });
  } catch (error) {
    console.error('❌ Error unflagging video:', error);
    res.status(500).json({ success: false, error: 'Failed to unflag video' });
  }
});

// **NEW: Admin endpoint to get video reports**
router.get('/reports', requireAdminDashboardKey, async (req, res) => {
  try {
    const { status = 'open', limit = 100 } = req.query;
    
    // We only care about video reports for this dashboard
    const query = { targetType: 'video' };
    if (status !== 'all') {
      query.status = status;
    }

    const Report = mongoose.model('Report');
    const reports = await Report.find(query)
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .lean();

    // Populate video details manually since targetId is a string and potentially not a valid ObjectId if corrupted
    // but usually it is. We can't use .populate() directly on targetId easily without refactoring models.
    const reportsWithDetails = await Promise.all(reports.map(async (report) => {
      let videoDetails = null;
      try {
        if (mongoose.Types.ObjectId.isValid(report.targetId)) {
          videoDetails = await Video.findById(report.targetId)
            .populate('uploader', 'name email googleId')
            .select('videoName uploader videoUrl thumbnailUrl')
            .lean();
        }
      } catch (e) {
        console.error(`Error fetching video for report ${report._id}:`, e);
      }
      
      return {
        ...report,
        video: videoDetails
      };
    }));

    res.json({
      success: true,
      count: reportsWithDetails.length,
      reports: reportsWithDetails
    });
  } catch (error) {
    console.error('❌ Error loading reports:', error);
    res.status(500).json({ success: false, error: 'Failed to load reports' });
  }
});

// **NEW: Admin endpoint to get stats including report counts**
router.get('/report-stats', requireAdminDashboardKey, async (req, res) => {
  try {
    const Report = mongoose.model('Report');
    const openReportsCount = await Report.countDocuments({ targetType: 'video', status: 'open' });
    
    // For "Deleted Videos", we can maybe count videos with a specific flag or just placeholder
    // If there's no "isDeleted" flag in Video model (usually they are removed), 
    // we might need a separate log or just return 0 for now.
    // Let's check if there's any 'deleted' status or similar.
    const deletedCount = 0; // Placeholder until we have a way to track deleted videos

    res.json({
      success: true,
      openReportsCount,
      deletedCount
    });
  } catch (error) {
    console.error('❌ Error loading report stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load report stats' });
  }
});

// **NEW: Route to broadcast emails to users (via Brevo)**
router.post('/email/blast', requireAdminDashboardKey, async (req, res) => {
  try {
    const { target, customEmail, subject, htmlContent } = req.body;

    if (!subject || !htmlContent) {
      return res.status(400).json({ success: false, error: 'Subject and content are required' });
    }

    let recipients = [];

    if (target === 'individual') {
      if (!customEmail) return res.status(400).json({ success: false, error: 'Email is required for individual target' });
      recipients = [customEmail];
    } else if (target === 'all') {
      const users = await User.find({ email: { $exists: true, $ne: '' } }).select('email').lean();
      recipients = users.map(u => u.email).filter(Boolean);
    } else {
      return res.status(400).json({ success: false, error: 'Invalid target specified' });
    }

    if (recipients.length === 0) {
      return res.status(404).json({ success: false, error: 'No recipients found' });
    }

    console.log(`📧 Email Blast: Sending to ${recipients.length} recipients...`);

    // In a massive blast, we should batch these or use a worker
    // For now, if < 100, we can do it in a loop
    const results = {
      total: recipients.length,
      successCount: 0,
      failCount: 0
    };

    // Parallel execution for small batches, sequential for large to avoid rate limits
    if (recipients.length < 50) {
       await Promise.all(recipients.map(async (email) => {
         const res = await brevoService.sendEmail({ to: email, subject, htmlContent });
         if (res.success) results.successCount++;
         else results.failCount++;
       }));
    } else {
       // Batch processing for large lists
       for (const email of recipients) {
         const res = await brevoService.sendEmail({ to: email, subject, htmlContent });
         if (res.success) results.successCount++;
         else results.failCount++;
         // Slight pause to respect API
         await new Promise(r => setTimeout(r, 100));
       }
    }

    res.json({
      success: true,
      message: `Email blast completed. Sent ${results.successCount} successfully, ${results.failCount} failed.`,
      results
    });

  } catch (error) {
    console.error('❌ Error in email blast:', error);
    res.status(500).json({ success: false, error: 'Failed to complete email blast' });
  }
});

// **NEW: Admin endpoint — Embedding status of all videos**
router.get('/videos/embedding-status', requireAdminDashboardKey, async (req, res) => {
  try {
    const { filter, limit = 50, skip = 0 } = req.query;

    const query = {};
    if (filter === 'success') {
      query.vectorEmbedding = { $exists: true, $ne: [], $not: { $size: 0 } };
    } else if (filter === 'failed') {
      query.$or = [
        { vectorEmbedding: { $exists: false } },
        { vectorEmbedding: null },
        { vectorEmbedding: { $size: 0 } }
      ];
    }

    const videos = await Video.find(query)
      .populate('uploader', 'name email googleId')
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .lean();

    const totalCount = await Video.countDocuments(query);

    const totalVideos = await Video.countDocuments();
    const successCount = await Video.countDocuments({
      vectorEmbedding: { $exists: true, $ne: [], $not: { $size: 0 } }
    });
    const failedCount = totalVideos - successCount;

    res.json({
      success: true,
      summary: { totalVideos, successCount, failedCount },
      videos: videos.map(v => ({
        _id: v._id,
        videoName: v.videoName,
        description: (v.description || '').substring(0, 80),
        embeddingPresent: !!(v.vectorEmbedding && v.vectorEmbedding.length > 0),
        embeddingVersion: v.embeddingVersion || 'none',
        embeddingDimension: v.vectorEmbedding ? v.vectorEmbedding.length : 0,
        createdAt: v.createdAt,
        uploader: v.uploader ? {
          name: v.uploader.name,
          email: v.uploader.email,
          googleId: v.uploader.googleId
        } : null
      })),
      totalCount,
      limit: parseInt(limit),
      skip: parseInt(skip)
    });
  } catch (error) {
    console.error('❌ Error loading embedding status:', error);
    res.status(500).json({ success: false, error: 'Failed to load embedding status' });
  }
});

// **NEW: Admin endpoint — AI Context generation status of all videos**
router.get('/videos/ai-context-status', requireAdminDashboardKey, async (req, res) => {
  try {
    const { filter, limit = 50, skip = 0 } = req.query;

    const query = {};
    if (filter === 'generated') {
      query.aiContextGenerated = true;
    } else if (filter === 'not-generated') {
      query.$or = [
        { aiContextGenerated: false },
        { aiContextGenerated: { $exists: false } }
      ];
    }

    const videos = await Video.find(query)
      .populate('uploader', 'name email googleId')
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .lean();

    const totalCount = await Video.countDocuments(query);

    const totalVideos = await Video.countDocuments();
    const generatedCount = await Video.countDocuments({ aiContextGenerated: true });
    const notGeneratedCount = totalVideos - generatedCount;

    res.json({
      success: true,
      summary: { totalVideos, generatedCount, notGeneratedCount },
      videos: videos.map(v => ({
        _id: v._id,
        videoName: v.videoName,
        description: (v.description || '').substring(0, 80),
        aiContextGenerated: !!v.aiContextGenerated,
        aiContextPreview: v.aiContext ? v.aiContext.substring(0, 120) + (v.aiContext.length > 120 ? '...' : '') : '',
        hasAiSummary: !!v.aiSummary,
        embeddingVersion: v.embeddingVersion || 'none',
        createdAt: v.createdAt,
        uploader: v.uploader ? {
          name: v.uploader.name,
          email: v.uploader.email,
          googleId: v.uploader.googleId
        } : null
      })),
      totalCount,
      limit: parseInt(limit),
      skip: parseInt(skip)
    });
  } catch (error) {
    console.error('❌ Error loading AI context status:', error);
    res.status(500).json({ success: false, error: 'Failed to load AI context status' });
  }
});

export default router;