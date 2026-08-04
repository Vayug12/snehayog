import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { validateCampaignData, validatePagination } from '../../middleware/validation.js';
import { verifyToken } from '../../utils/verifytoken.js';
import AdCampaign from '../../models/AdCampaign.js';
import AdCreative from '../../models/AdCreative.js';
import Invoice from '../../models/Invoice.js';

const router = express.Router();

// Every campaign route is advertiser-scoped: a campaign is money, so it is
// only ever readable or mutable by the advertiser who owns it.
router.use(verifyToken);

// /api/ads/* is mounted behind a `public, max-age=180` cache header. That is
// fine for ad serving but not for per-advertiser data — a shared cache could
// hand one advertiser's campaigns to another. Mounted after the router's own
// middleware so it overrides the header set upstream.
router.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});

/**
 * Resolve the caller's User._id.
 *
 * verifyToken memoises this alongside the token, so it costs nothing here.
 * It is absent only when the token is valid but the user row is gone.
 */
const advertiserId = (req) => req.user?._id;

/**
 * Load `:id` and confirm the caller owns it, attaching it as `req.campaign`.
 *
 * Returns 404 rather than 403 for someone else's campaign — a 403 would
 * confirm the id exists to anyone probing.
 */
const loadOwnedCampaign = asyncHandler(async (req, res, next) => {
  const ownerId = advertiserId(req);
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  const campaign = await AdCampaign.findById(req.params.id);
  if (!campaign || campaign.advertiserUserId.toString() !== ownerId.toString()) {
    return res.status(404).json({ error: 'Campaign not found' });
  }

  req.campaign = campaign;
  next();
});

// POST /ads/campaigns - Create draft campaign
router.post('/', validateCampaignData, asyncHandler(async (req, res) => {
  const {
    name,
    objective,
    startDate,
    endDate,
    dailyBudget,
    totalBudget,
    bidType,
    cpmINR,
    target,
    pacing,
    frequencyCap
  } = req.body;

  // Use default CPM for carousel/video feed ads (₹30)
  // Banner ads will use ₹10 CPM when created through ad creation
  const defaultCpm = 30; // ₹30 per 1000 impressions for carousel and video feed ads

  const ownerId = advertiserId(req);
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  const campaign = new AdCampaign({
    name,
    // Ownership comes from the token, never from the request body.
    advertiserUserId: ownerId,
    objective,
    startDate: new Date(startDate),
    endDate: new Date(endDate),
    dailyBudget,
    totalBudget,
    bidType: bidType || 'CPM',
    cpmINR: cpmINR || defaultCpm,
    target: target || {},
    pacing: pacing || 'smooth',
    frequencyCap: frequencyCap || 3
  });

  await campaign.save();

  res.status(201).json({
    message: 'Campaign created successfully',
    campaign
  });
}));

// GET /ads/campaigns - List campaigns with pagination
router.get('/', validatePagination, asyncHandler(async (req, res) => {
  const { status } = req.query;
  const { page, limit } = req.pagination;
  const skip = (page - 1) * limit;

  const ownerId = advertiserId(req);
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  // Always scoped to the caller. This previously listed every advertiser's
  // campaigns — including their name and email — whenever `me=true` was omitted.
  const query = { advertiserUserId: ownerId };

  if (status) {
    query.status = status;
  }

  const campaigns = await AdCampaign.find(query)
    .sort({ createdAt: -1 })
    .skip(skip)
    .limit(limit);

  const total = await AdCampaign.countDocuments(query);

  res.json({
    campaigns,
    pagination: {
      currentPage: page,
      totalPages: Math.ceil(total / limit),
      total,
      hasMore: (page * limit) < total
    }
  });
}));

// GET /ads/campaigns/:id - Get campaign details
router.get('/:id', loadOwnedCampaign, asyncHandler(async (req, res) => {
  const creative = await AdCreative.findOne({ campaignId: req.campaign._id });

  res.json({
    campaign: req.campaign,
    creative
  });
}));

// POST /ads/campaigns/:id/submit - Submit for review
router.post('/:id/submit', loadOwnedCampaign, asyncHandler(async (req, res) => {
  const campaign = req.campaign;
  const campaignId = campaign._id;

  // Check if campaign has creative
  const creative = await AdCreative.findOne({ campaignId });
  if (!creative) {
    return res.status(400).json({ error: 'Campaign must have a creative before submission' });
  }

  // Update status
  campaign.status = 'pending_review';
  await campaign.save();

  res.json({
    message: 'Campaign submitted for review',
    campaign
  });
}));

// POST /ads/campaigns/:id/activate - Activate campaign
router.post('/:id/activate', loadOwnedCampaign, asyncHandler(async (req, res) => {
  const campaign = req.campaign;
  const campaignId = campaign._id;

  // Check if campaign is approved
  if (campaign.status !== 'pending_review') {
    return res.status(400).json({ error: 'Campaign must be pending review to activate' });
  }

  // Check if payment is completed
  const invoice = await Invoice.findOne({ 
    campaignId, 
    status: 'paid' 
  });
  
  if (!invoice) {
    return res.status(400).json({ 
      error: 'Payment required before activation',
      paymentRequired: true
    });
  }

  // Activate campaign
  campaign.status = 'active';
  await campaign.save();

  // Activate creative consistently
  await AdCreative.findOneAndUpdate(
    { campaignId },
    { $set: { isActive: true, reviewStatus: 'approved' } }
  );

  res.json({
    message: 'Campaign activated successfully',
    campaign
  });
}));

export default router;
