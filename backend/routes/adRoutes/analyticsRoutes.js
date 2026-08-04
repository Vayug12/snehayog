import express from 'express';
import mongoose from 'mongoose';
import { asyncHandler } from '../../middleware/errorHandler.js';
import adService from '../../services/adServices/adService.js';
import redisService from '../../services/caching/redisService.js';
import RevenueService from '../../services/adServices/revenueService.js';
import User from '../../models/User.js';
import { verifyToken } from '../../utils/verifytoken.js';
import { AD_CONFIG } from '../../constants/index.js';

const router = express.Router();

// GET /ads/serve - Get active ads for serving with targeting
// **NEW: Redis caching integrated for faster ad serving**
router.get('/serve', asyncHandler(async (req, res) => {
  const { userId, platform, location, videoCategory, videoTags, videoKeywords, adType } = req.query;
  
  // Parse comma-separated tags and keywords
  const parsedTags = videoTags ? videoTags.split(',').map(t => t.trim()) : [];
  const parsedKeywords = videoKeywords ? videoKeywords.split(',').map(k => k.trim()) : [];
  
  // **NEW: Generate cache key based on targeting parameters**
  const cacheKey = `ads:serve:${adType || 'all'}:${videoCategory || 'all'}:${parsedTags.join(',')}:${parsedKeywords.join(',')}`;
  
  // **NEW: Try to get from Redis cache first (cache for 2 minutes)**
  if (redisService.getConnectionStatus()) {
    const cached = await redisService.get(cacheKey);
    if (cached) {
      console.log(`✅ Ad Cache HIT: ${cacheKey}`);
      return res.json(cached);
    }
    console.log(`❌ Ad Cache MISS: ${cacheKey}`);
  }

  
  const activeAds = await adService.getActiveAds({ 
    userId, 
    platform, 
    location,
    videoCategory,
    videoTags: parsedTags,
    videoKeywords: parsedKeywords,
    adType
  });
  
  const response = {
    ads: activeAds,
    count: activeAds.length,
    targeting: {
      videoCategory,
      videoTags: parsedTags,
      videoKeywords: parsedKeywords,
      adType: adType || 'all'
    }
  };
  
  // **NEW: Cache the response for 2 minutes (120 seconds)**
  if (redisService.getConnectionStatus()) {
    await redisService.set(cacheKey, response, 120);
    console.log(`✅ Cached ad response: ${cacheKey}`);
  }
  
  res.json(response);
}));

// POST /ads/track-click/:adId - Track ad clicks
router.post('/track-click/:adId', asyncHandler(async (req, res) => {
  const { adId } = req.params;
  const { userId, platform, location } = req.body;
  
  const result = await adService.trackAdClick(adId, { userId, platform, location });
  
  res.json(result);
}));

// GET /ads/analytics/:adId - Get ad analytics
router.get('/analytics/:adId', asyncHandler(async (req, res) => {
  try {
    const { adId } = req.params;
    const { userId } = req.query;
    
    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }
    
    const result = await adService.getAdAnalytics(adId, userId);
    
    if (result.error) {
      return res.status(404).json(result);
    }
    
    res.json(result);
  } catch (error) {
    console.error('❌ Analytics Route Error:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to get ad analytics',
      details: error.message 
    });
  }
}));

// GET /api/ads/analytics/:adId/video-breakdown - Get granular breakdown of ad performance per video
router.get('/analytics/:adId/video-breakdown', asyncHandler(async (req, res) => {
  try {
    const { adId } = req.params;
    
    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }
    
    const breakdown = await adService.getAdVideoBreakdown(adId);
    res.json(breakdown);
  } catch (error) {
    console.error('❌ Analytics Breakdown Route Error:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to get ad video breakdown' 
    });
  }
}));

// GET /ads/creator/revenue/:userId - Get creator revenue summary (UNIFIED)
router.get('/creator/revenue/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;
    const now = new Date();

    // Parse month/year from query if provided, else default to current
    const month = req.query.month !== undefined ? parseInt(req.query.month) : now.getUTCMonth();
    const year = req.query.year !== undefined ? parseInt(req.query.year) : now.getUTCFullYear();

    console.log(`💰 Fetching unified revenue for ${userId} [${month}/${year}]...`);

    const summary = await RevenueService.getCreatorRevenueSummary(userId, month, year);

    if (!summary.success) {
      return res.status(404).json({ error: summary.error || 'User not found' });
    }

    // Fetch monthly earnings history from CreatorMonthlyStat
    const CreatorMonthlyStat = (await import('../../models/CreatorMonthlyStat.js')).default;
    let user = await User.findOne({ googleId: userId });
    if (!user && mongoose.Types.ObjectId.isValid(userId)) {
      user = await User.findById(userId);
    }

    let monthlyEarnings = [];
    if (user) {
      const allStats = await CreatorMonthlyStat.find({ creatorId: user._id }).lean();
      console.log(`📊 Monthly stats for ${userId}: found ${allStats.length} month(s) — ${allStats.map(s => s.yearMonth).join(', ') || 'none'}`);

      const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8;
      monthlyEarnings = allStats
        .map(s => ({
          yearMonth: s.yearMonth,
          grossRevenue: parseFloat((s.grossRevenue || 0).toFixed(2)),
          creatorRevenue: parseFloat(((s.grossRevenue || 0) * creatorShare).toFixed(2)),
          bannerImpressions: s.bannerImpressions || 0,
          carouselImpressions: s.carouselImpressions || 0,
        }))
        .sort((a, b) => b.yearMonth.localeCompare(a.yearMonth));

      console.log(`✅ Monthly earnings sorted (newest first): ${monthlyEarnings.map(e => `${e.yearMonth}=₹${e.creatorRevenue}`).join(', ') || 'empty'}`);
    }

    // Map the unified summary to the response format the App expects
    const response = {
      ...summary,
      // Map breakdown to the explicit format used by the frontend
      revenueBreakdown: {
        bannerAds: summary.banner,
        carouselAds: summary.carousel,
        total: {
          impressions: summary.banner.views + summary.carousel.views,
          revenue: summary.grossRevenue,
          creatorShare: summary.netRevenue
        }
      },
      // Ensure specific fields required by current ProfileScreen are present
      totalRevenue: summary.netRevenue,
      netRevenue: summary.netRevenue,
      thisMonth: summary.thisMonth,
      lastMonth: summary.lastMonth,
      // Monthly earnings history for the bottom sheet
      monthlyEarnings
    };

    res.json(response);

  } catch (error) {
    console.error('❌ Creator revenue error:', error);
    res.status(500).json({
      error: 'Failed to fetch creator revenue',
      details: error.message
    });
  }
});

export default router;
