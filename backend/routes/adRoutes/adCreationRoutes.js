import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { verifyToken } from '../../utils/verifytoken.js';
import { requireConfiguredAdminDashboardKey } from '../../middleware/adminDashboardAuth.js';
import User from '../../models/User.js';
import AdCreative from '../../models/AdCreative.js';
import walletService from '../../services/adServices/walletService.js';
import campaignSettlement from '../../services/adServices/campaignSettlement.js';
import {
  createAdWithCredits,
  AdValidationError,
  AdCreationConflictError
} from '../../services/adServices/adCreationService.js';

const router = express.Router();

// /api/ads/* is served behind a `public, max-age=180` cache header. Both routes
// here are per-caller and change a balance, so neither may be cached anywhere.
router.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});

/**
 * POST /api/ads/creatives/:id/reject — pull a creative and refund its campaign.
 *
 * The counterweight to auto-approval. Ads go live at creation because credits
 * cost real money, which makes spam expensive but not impossible; this is how
 * something that slips through gets removed. Refunding the remaining budget is
 * part of the same action — pulling an ad while keeping the money would be a
 * chargeback waiting to happen.
 *
 * Declared before `router.use(verifyToken)`: the admin dashboard authenticates
 * with a key, not a user token, like every other admin route in the repo.
 */
router.post('/creatives/:id/reject', requireConfiguredAdminDashboardKey, asyncHandler(async (req, res) => {
  const { reason } = req.body || {};

  const result = await campaignSettlement.rejectCreative(req.params.id, { reason });
  if (!result) {
    return res.status(404).json({ error: 'Creative not found' });
  }

  return res.json({
    success: true,
    creativeId: result.creative._id,
    campaignId: result.creative.campaignId,
    campaignSettled: result.campaignSettled,
    refundedCredits: result.refunded,
    message: result.campaignSettled
      ? `Creative rejected; ${result.refunded} credits refunded`
      : 'Creative rejected; campaign still has other running creatives'
  });
}));

// Everything below acts as the signed-in advertiser.
router.use(verifyToken);

/**
 * POST /api/ads/create-with-credits
 *
 * Debits the campaign's full budget from the advertiser's credit wallet, then
 * creates the campaign and creative. The client has been pointed at this
 * endpoint since Phase 0; it is the only way to create an ad.
 */
router.post('/create-with-credits', asyncHandler(async (req, res) => {
  // AdCampaign.advertiserUserId is an ObjectId ref, so the Google ID on the
  // token is the wrong key. `_id` is memoised by verifyToken and is absent only
  // when the token is valid but the user row is gone.
  const userObjectId = req.user?._id;
  const googleId = req.user?.googleId || req.user?.id;

  if (!userObjectId || !googleId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  try {
    const { campaign, creative, spec } = await createAdWithCredits(req.body, {
      googleId,
      userObjectId
    });

    // Display fields only — ownership already came from the token. Looked up
    // after creation so a slow profile read cannot hold the debit open.
    const user = await User.findById(userObjectId).select('name profilePic').lean();
    const wallet = await walletService.getBalance(userObjectId);

    return res.status(201).json({
      success: true,
      message: 'Ad created and funded from your credit balance',
      wallet: { balance: wallet.balance },
      ad: {
        _id: creative._id,
        creativeId: creative._id,
        campaignId: campaign._id,
        title: creative.title,
        description: req.body?.description,
        imageUrl: creative.thumbnail || creative.cloudinaryUrl || null,
        videoUrl: creative.type === 'video' ? creative.cloudinaryUrl : null,
        link: creative.callToAction?.url || null,
        adType: creative.adType,
        status: campaign.status,
        budget: campaign.totalBudget,
        spend: campaign.spentINR,
        startDate: campaign.startDate,
        endDate: campaign.endDate,
        createdAt: campaign.createdAt,
        estimatedImpressions: spec.estimatedImpressions,
        cpm: spec.cpmINR,
        uploaderId: googleId,
        uploaderName: user?.name || '',
        uploaderProfilePic: user?.profilePic || null,
        targetAudience: req.body?.targetAudience || 'all',
        targetKeywords: Array.isArray(req.body?.targetKeywords) ? req.body.targetKeywords : [],
        minAge: campaign.target?.age?.min,
        maxAge: campaign.target?.age?.max,
        gender: campaign.target?.gender,
        locations: campaign.target?.locations || [],
        interests: campaign.target?.interests || [],
        platforms: campaign.target?.platforms || [],
        deviceType: campaign.target?.deviceType,
        optimizationGoal: campaign.optimizationGoal,
        frequencyCap: campaign.frequencyCap,
        timeZone: campaign.timeZone
      }
    });
  } catch (err) {
    if (err instanceof AdValidationError) {
      return res.status(400).json({ error: err.message, code: err.code, field: err.field });
    }

    if (err instanceof AdCreationConflictError) {
      return res.status(409).json({ error: err.message, code: err.code });
    }

    if (err instanceof walletService.InsufficientCreditsError) {
      // The client uses `shortfall` to size its top-up prompt, so it is sent
      // explicitly rather than left as arithmetic for the caller.
      return res.status(402).json({
        error: 'Not enough ad credits for this budget',
        code: 'INSUFFICIENT_CREDITS',
        required: err.required,
        available: err.available,
        shortfall: err.shortfall
      });
    }

    if (err instanceof walletService.WalletFrozenError) {
      return res.status(403).json({
        error: 'Your ad credit wallet is on hold. Contact support to resume spending.',
        code: 'WALLET_FROZEN'
      });
    }

    throw err;
  }
}));

/**
 * GET /api/ads/creatives/:id/status — has this ad been rejected?
 *
 * Cheap enough for the client to poll after creation without hitting the
 * heavier campaign endpoints.
 */
router.get('/creatives/:id/status', asyncHandler(async (req, res) => {
  const ownerId = req.user?._id;
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  const creative = await AdCreative.findById(req.params.id)
    .select('reviewStatus rejectionReason isActive campaignId')
    .populate({ path: 'campaignId', select: 'advertiserUserId' })
    .lean();

  // 404 rather than 403 for someone else's creative — a 403 would confirm the
  // id exists to anyone probing.
  const owner = creative?.campaignId?.advertiserUserId;
  if (!creative || !owner || String(owner) !== String(ownerId)) {
    return res.status(404).json({ error: 'Creative not found' });
  }

  return res.json({
    success: true,
    reviewStatus: creative.reviewStatus,
    rejectionReason: creative.rejectionReason || null,
    isActive: creative.isActive,
    campaignId: creative.campaignId?._id || creative.campaignId
  });
}));

export default router;
