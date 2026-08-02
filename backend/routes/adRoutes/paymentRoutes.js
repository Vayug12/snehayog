import express from 'express';
import mongoose from 'mongoose';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { validatePaymentData } from '../../middleware/errorHandler.js';
import adService from '../../services/adServices/adService.js';
import User from '../../models/User.js';
import Video from '../../models/Video.js';
import { verifyToken } from '../../utils/verifytoken.js';
import { AD_CONFIG } from '../../constants/index.js';

const router = express.Router();

// POST /ads/create-with-payment - Create ad with payment processing
router.post('/create-with-payment', asyncHandler(async (req, res) => {
  const result = await adService.createAdWithPayment(req.body);
  
  res.status(201).json({
    message: 'Ad created successfully. Payment required to activate.',
    ...result
  });
}));

// POST /ads/process-payment - Process Razorpay payment
router.post('/process-payment', validatePaymentData, asyncHandler(async (req, res) => {
  const result = await adService.processPayment(req.body);
  
  res.json({
    message: 'Payment processed successfully. Ad is now active!',
    ...result
  });
}));

import RevenueService from '../../services/adServices/revenueService.js';

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
