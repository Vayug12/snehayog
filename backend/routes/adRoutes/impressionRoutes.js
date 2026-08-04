import express from 'express';
import mongoose from 'mongoose';
import AdCreative from '../../models/AdCreative.js';
import AdImpression from '../../models/AdImpression.js';
import User from '../../models/User.js';
import Video from '../../models/Video.js'; // Import Video model to fetch creatorId
import { recordCreativeCounter, recordCreatorEarning, recordCampaignSpend } from '../../services/adServices/adStatsBuffer.js';
import { renderedMatch, billableMatch } from '../../services/adServices/impressionCounting.js';

const router = express.Router();
const DAILY_VIEW_FREQUENCY_CAP = 3;

// **OPTIMIZATION: In-memory cache for Google ID to Mongo ObjectID mapping**
// This reduces redundant User.findOne calls which were taking ~95ms each
const userIdCache = new Map();
const USER_CACHE_TTL = 10 * 60 * 1000; // 10 minutes

// **FIXED: Helper function to normalize userId (Google ID to MongoDB ObjectId)**
async function normalizeUserId(userId) {
  if (!userId) return null;
  
  // If it's already a valid MongoDB ObjectId, return it as ObjectId
  if (mongoose.isValidObjectId(userId)) {
    return new mongoose.Types.ObjectId(userId);
  }
  
  // Check in-memory cache first
  const cached = userIdCache.get(userId);
  if (cached && (Date.now() - cached.timestamp < USER_CACHE_TTL)) {
    return cached.objectId;
  }
  
  // Otherwise, try to find user by Google ID and return MongoDB ObjectId
  try {
    const user = await User.findOne({ googleId: userId }).select('_id').lean();
    if (user) {
      // Store in cache
      userIdCache.set(userId, {
        objectId: user._id,
        timestamp: Date.now()
      });
      return user._id; // Return ObjectId directly
    }
  } catch (error) {
    console.error('⚠️ Error looking up user by Google ID:', error);
  }
  
  // If user not found, return null (will be stored as anonymous)
  return null;
}

// **Helper to book a delivered view on both sides of the ledger**
// Buffered: the writes are batched by adStatsBuffer and flushed every few
// seconds instead of hitting Mongo once per impression.
//
// Creator credit and advertiser spend are booked together, at the same CPM —
// splitting them would let a campaign fund creator payouts past its budget.
function bookDeliveredView(creatorId, adId, adType) {
  if (creatorId) recordCreatorEarning(creatorId, adType);
  recordCampaignSpend(adId, adType);
}

// POST /ads/impressions/batch - Sync impressions captured while the app was offline.
router.post('/impressions/batch', async (req, res) => {
  try {
    const impressions = req.body?.impressions;
    if (!Array.isArray(impressions) || impressions.length === 0) {
      return res.status(400).json({ error: 'A non-empty impressions array is required' });
    }
    if (impressions.length > 50) {
      return res.status(400).json({ error: 'A maximum of 50 impressions can be synced at once' });
    }

    let processed = 0;
    let ignored = 0;

    // Pass 1 — validate input and split clicks from view impressions.
    const clickAdIds = [];
    const candidates = [];

    for (const impression of impressions) {
      const { videoId, adId, userId, adType, impressionType } = impression || {};
      const supportedType = adType === 'banner' || adType === 'carousel';
      const supportedImpression = impressionType === 'view' ||
        impressionType === 'scroll_view' || impressionType === 'click';

      if (!supportedType || !supportedImpression || !mongoose.isValidObjectId(adId)) {
        ignored += 1;
        continue;
      }

      if (impressionType === 'click') {
        clickAdIds.push(adId);
        continue;
      }

      if (!mongoose.isValidObjectId(videoId)) {
        ignored += 1;
        continue;
      }

      candidates.push({ videoId, adId, userId, adType, timestamp: impression.timestamp });
    }

    // Pass 2 — resolve every referenced document in one round trip each,
    // instead of three queries per impression inside a loop.
    const adIds = [...new Set([...candidates.map((c) => String(c.adId)), ...clickAdIds.map(String)])];
    const videoIds = [...new Set(candidates.map((c) => String(c.videoId)))];
    const userIds = [...new Set(candidates.map((c) => c.userId).filter(Boolean))];

    const [creatives, videos, normalizedUserIds] = await Promise.all([
      adIds.length ? AdCreative.find({ _id: { $in: adIds } }).select('_id').lean() : [],
      videoIds.length ? Video.find({ _id: { $in: videoIds } }).select('uploader').lean() : [],
      Promise.all(userIds.map((id) => normalizeUserId(id))),
    ]);

    const knownAdIds = new Set(creatives.map((c) => String(c._id)));
    const videoUploaders = new Map(videos.map((v) => [String(v._id), v.uploader || null]));
    const userIdMap = new Map(userIds.map((id, i) => [id, normalizedUserIds[i]]));

    // Pass 3 — build the impression documents.
    const docs = [];
    const impressionCounts = new Map();

    for (const candidate of candidates) {
      const adIdKey = String(candidate.adId);
      const videoIdKey = String(candidate.videoId);

      if (!knownAdIds.has(adIdKey) || !videoUploaders.has(videoIdKey)) {
        ignored += 1;
        continue;
      }

      const creatorId = videoUploaders.get(videoIdKey);
      const normalizedUserId = candidate.userId ? (userIdMap.get(candidate.userId) ?? null) : null;

      if (normalizedUserId && creatorId && normalizedUserId.toString() === creatorId.toString()) {
        ignored += 1;
        continue;
      }

      const parsedTimestamp = new Date(candidate.timestamp);
      docs.push({
        videoId: candidate.videoId,
        adId: candidate.adId,
        userId: normalizedUserId,
        creatorId,
        adType: candidate.adType,
        impressionType: candidate.adType === 'carousel' ? 'scroll_view' : 'view',
        timestamp: Number.isNaN(parsedTimestamp.getTime()) ? new Date() : parsedTimestamp,
      });
      impressionCounts.set(adIdKey, (impressionCounts.get(adIdKey) || 0) + 1);
    }

    // Single insert for the whole payload.
    if (docs.length > 0) {
      try {
        const inserted = await AdImpression.insertMany(docs, { ordered: false });
        processed += inserted.length;
      } catch (bulkError) {
        // ordered:false continues past individual failures (e.g. duplicate keys),
        // so count what actually landed rather than failing the whole sync.
        const insertedCount = bulkError?.insertedDocs?.length
          ?? bulkError?.result?.insertedCount
          ?? bulkError?.result?.nInserted
          ?? 0;
        processed += insertedCount;
        ignored += docs.length - insertedCount;
        console.error('⚠️ Partial failure syncing offline impressions:', bulkError?.message);
      }

      for (const [adId, count] of impressionCounts) {
        recordCreativeCounter(adId, 'impressions', count);
      }
    }

    for (const adId of clickAdIds) {
      if (!knownAdIds.has(String(adId))) {
        ignored += 1;
        continue;
      }
      recordCreativeCounter(adId, 'clicks');
      processed += 1;
    }

    return res.status(200).json({ success: true, processed, ignored });
  } catch (error) {
    console.error('Error syncing offline ad impressions:', error);
    return res.status(500).json({ error: 'Failed to sync offline ad impressions' });
  }
});

// POST /ads/impressions/banner - Track banner ad impression
router.post('/impressions/banner', async (req, res) => {
  try {
    const { videoId, adId, userId, creatorId: providedCreatorId } = req.body;
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      // Don't log spam for every request, just keep track
    }

    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }

    if (!videoId) {
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Verify the creative exists. The counter itself is incremented atomically
    // via the batched $inc below, so only the id is needed here.
    const creative = await AdCreative.findById(adId).select('impressions').lean();
    if (!creative) {
      console.error('❌ Ad creative not found:', adId);
      return res.status(404).json({ error: 'Ad not found' });
    }

    // **FIXED: Track video-specific impression in AdImpression collection**
    try {
      // **OPTIMIZATION: Get creatorId from request or fetch from Video**
      let creatorId = providedCreatorId;
        
      if (!creatorId) {
        const video = await Video.findById(videoId).select('uploader').lean();
        creatorId = video ? video.uploader : null;
      }

      // **NEW: PREVENT SELF-IMPRESSION**
      // If the viewer matches the video owner, do NOT count it as an impression
      if (normalizedUserId && creatorId && normalizedUserId.toString() === creatorId.toString()) {
        console.log(`🚫 Self-impression prevented: User ${normalizedUserId} viewing own video ${videoId}`);
        // We still return success to the frontend so it doesn't think something broke, 
        // but we don't record the impression.
        return res.status(200).json({ 
          success: true,
          message: 'Self-impression ignored',
          ignored: true 
        });
      }

      // Create new impression record
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        creatorId: creatorId, // **NEW: Save creatorId for fast lookup**
        adType: 'banner',
        impressionType: 'view',
        timestamp: new Date()
      });
    } catch (impressionError) {
      // Log error but don't fail the request
      console.error('⚠️ Error creating impression record:', impressionError);
    }

    // Increment global impressions count (for backward compatibility).
    // Buffered $inc — atomic and batched, unlike the previous read-modify-write
    // save() which silently lost counts under concurrent impressions.
    recordCreativeCounter(adId, 'impressions');

    res.status(200).json({
      success: true,
      message: 'Banner ad impression tracked successfully',
      impressions: (creative.impressions || 0) + 1
    });
  } catch (error) {
    console.error('❌ Error tracking banner ad impression:', error);
    res.status(500).json({ 
      error: 'Failed to track banner ad impression',
      message: error.message 
    });
  }
});

// POST /ads/impressions/carousel - Track carousel ad impression
router.post('/impressions/carousel', async (req, res) => {
  try {
    const { videoId, adId, userId, scrollPosition, creatorId: providedCreatorId } = req.body;
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      // Minimal logging
    }

    // console.log('📊 Tracking carousel ad impression:');
    // console.log('   Video ID:', videoId);
    // console.log('   Ad ID:', adId);
    // console.log('   User ID:', userId);
    // console.log('   Scroll Position:', scrollPosition);

    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }

    if (!videoId) {
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Verify the creative exists. The counter itself is incremented atomically
    // via the batched $inc below, so only the id is needed here.
    const creative = await AdCreative.findById(adId).select('impressions').lean();
    if (!creative) {
      console.error('❌ Ad creative not found:', adId);
      return res.status(404).json({ error: 'Ad not found' });
    }

    // **FIXED: Track video-specific impression in AdImpression collection**
    try {
      // **OPTIMIZATION: Get creatorId from request or fetch from Video**
      let creatorId = providedCreatorId;
        
      if (!creatorId) {
        const video = await Video.findById(videoId).select('uploader').lean();
        creatorId = video ? video.uploader : null;
      }

      // **NEW: PREVENT SELF-IMPRESSION**
      if (normalizedUserId && creatorId && normalizedUserId.toString() === creatorId.toString()) {
        console.log(`🚫 Self-impression prevented (carousel): User ${normalizedUserId} viewing own video ${videoId}`);
        return res.status(200).json({ 
          success: true,
          message: 'Self-impression ignored',
          ignored: true 
        });
      }

      // Create new impression record
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        creatorId: creatorId, // **NEW: Save creatorId for fast lookup**
        adType: 'carousel',
        impressionType: 'scroll_view',
        timestamp: new Date()
      });
    } catch (impressionError) {
      // Log error but don't fail the request
      console.error('⚠️ Error creating impression record:', impressionError);
    }

    // Increment global impressions count (for backward compatibility).
    // Buffered $inc — atomic and batched, unlike the previous read-modify-write
    // save() which silently lost counts under concurrent impressions.
    recordCreativeCounter(adId, 'impressions');

    res.status(200).json({
      success: true,
      message: 'Carousel ad impression tracked successfully',
      impressions: (creative.impressions || 0) + 1
    });
  } catch (error) {
    console.error('❌ Error tracking carousel ad impression:', error);
    res.status(500).json({ 
      error: 'Failed to track carousel ad impression',
      message: error.message 
    });
  }
});

// GET /ads/impressions/video/:videoId/banner - Get banner impressions for a video
router.get('/impressions/video/:videoId/banner', async (req, res) => {
  try {
    const { videoId } = req.params;

    console.log(`📊 Getting banner impressions for video: ${videoId}`);

    // Rendered rows only — a delivered ad also writes a second, `isViewed` row,
    // and counting both reports twice the ads that were actually shown.
    const count = await AdImpression.countDocuments({
      videoId: videoId,
      adType: 'banner',
      ...renderedMatch()
    });

    console.log(`✅ Banner impressions for video ${videoId}: ${count}`);

    res.status(200).json({ count: count });
  } catch (error) {
    console.error('❌ Error getting banner impressions:', error);
    res.status(500).json({ 
      error: 'Failed to get banner impressions',
      message: error.message 
    });
  }
});

// GET /ads/impressions/video/:videoId/carousel - Get carousel impressions for a video
router.get('/impressions/video/:videoId/carousel', async (req, res) => {
  try {
    const { videoId } = req.params;

    console.log(`📊 Getting carousel impressions for video: ${videoId}`);

    // Rendered rows only — see the banner endpoint above.
    const count = await AdImpression.countDocuments({
      videoId: videoId,
      adType: 'carousel',
      ...renderedMatch()
    });

    console.log(`✅ Carousel impressions for video ${videoId}: ${count}`);

    res.status(200).json({ count: count });
  } catch (error) {
    console.error('❌ Error getting carousel impressions:', error);
    res.status(500).json({ 
      error: 'Failed to get carousel impressions',
      message: error.message 
    });
  }
});

// **NEW: POST /ads/impressions/banner/view - Track banner ad view (minimum 2-3 seconds)**
router.post('/impressions/banner/view', async (req, res) => {
  try {
    const { videoId, adId, userId, viewDuration, creatorId: providedCreatorId } = req.body;
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      // Minimal logging
    }

    // console.log('👁️ Tracking banner ad VIEW (minimum duration):');
    // console.log('   Video ID:', videoId);
    // console.log('   Ad ID:', adId);
    // console.log('   User ID:', userId);
    // console.log('   View Duration:', viewDuration);

    if (!adId || !videoId) {
      return res.status(400).json({ error: 'Ad ID and Video ID are required' });
    }

    // Minimum view duration: 2 seconds
    const minViewDuration = 2.0;
    if (!viewDuration || viewDuration < minViewDuration) {
      return res.status(400).json({ 
        error: `View duration must be at least ${minViewDuration} seconds`,
        viewDuration: viewDuration 
      });
    }

    let dailyViewCount = 0;
    if (normalizedUserId) {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);
      dailyViewCount = await AdImpression.countDocuments({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        adType: 'banner',
        ...billableMatch(),
        timestamp: { $gte: startOfDay }
      });

      if (dailyViewCount >= DAILY_VIEW_FREQUENCY_CAP) {
        return res.status(200).json({
          success: false,
          message: 'Daily ad view cap reached for this user',
          dailyViews: dailyViewCount,
          frequencyCap: DAILY_VIEW_FREQUENCY_CAP
        });
      }
    }

      // **OPTIMIZATION: Get creatorId from request or fetch from Video**
      let creatorId = providedCreatorId;
      
      if (!creatorId) {
        const video = await Video.findById(videoId).select('uploader').lean();
        creatorId = video ? video.uploader : null;
      }

      // **NEW: PREVENT SELF-VIEW**
      if (normalizedUserId && creatorId && normalizedUserId.toString() === creatorId.toString()) {
        return res.status(200).json({ 
          success: true,
          message: 'Self-view ignored',
          ignored: true 
        });
      }

      // Create new viewed impression record
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        creatorId: creatorId, // **NEW: Save creatorId for fast lookup**
        adType: 'banner',
        impressionType: 'view',
        isViewed: true,
        viewDuration: viewDuration,
        viewCount: 1,
        frequencyCap: DAILY_VIEW_FREQUENCY_CAP,
        timestamp: new Date()
      });
      
      // Increment views on AdCreative (buffered $inc, flushed in batches)
      recordCreativeCounter(adId, 'views');

      bookDeliveredView(creatorId, adId, 'banner');

    res.status(200).json({ 
      success: true,
      message: 'Banner ad view tracked successfully',
      viewDuration: viewDuration,
      dailyViews: normalizedUserId ? dailyViewCount + 1 : undefined,
      frequencyCap: normalizedUserId ? DAILY_VIEW_FREQUENCY_CAP : undefined
    });
  } catch (error) {
    console.error('❌ Error tracking banner ad view:', error);
    res.status(500).json({ 
      error: 'Failed to track banner ad view',
      message: error.message 
    });
  }
});

// **NEW: POST /ads/impressions/carousel/view - Track carousel ad view (minimum 2-3 seconds)**
router.post('/impressions/carousel/view', async (req, res) => {
  try {
    const { videoId, adId, userId, viewDuration, creatorId: providedCreatorId } = req.body;
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      // Minimal logging
    }

    // console.log('👁️ Tracking carousel ad VIEW (minimum duration):');
    // console.log('   Video ID:', videoId);
    // console.log('   Ad ID:', adId);
    // console.log('   User ID:', userId);
    // console.log('   View Duration:', viewDuration);

    if (!adId || !videoId) {
      return res.status(400).json({ error: 'Ad ID and Video ID are required' });
    }

    // Minimum view duration: 2 seconds
    const minViewDuration = 2.0;
    if (!viewDuration || viewDuration < minViewDuration) {
      return res.status(400).json({ 
        error: `View duration must be at least ${minViewDuration} seconds`,
        viewDuration: viewDuration 
      });
    }

    let dailyViewCount = 0;
    if (normalizedUserId) {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);
      dailyViewCount = await AdImpression.countDocuments({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        adType: 'carousel',
        ...billableMatch(),
        timestamp: { $gte: startOfDay }
      });

      if (dailyViewCount >= DAILY_VIEW_FREQUENCY_CAP) {
        return res.status(200).json({
          success: false,
          message: 'Daily ad view cap reached for this user',
          dailyViews: dailyViewCount,
          frequencyCap: DAILY_VIEW_FREQUENCY_CAP
        });
      }
    }

      // **OPTIMIZATION: Get creatorId from request or fetch from Video**
      let creatorId = providedCreatorId;
      
      if (!creatorId) {
        const video = await Video.findById(videoId).select('uploader').lean();
        creatorId = video ? video.uploader : null;
      }

      // **NEW: PREVENT SELF-VIEW**
      if (normalizedUserId && creatorId && normalizedUserId.toString() === creatorId.toString()) {
        return res.status(200).json({ 
          success: true,
          message: 'Self-view ignored',
          ignored: true 
        });
      }

      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        creatorId: creatorId, // **NEW: Save creatorId for fast lookup**
        adType: 'carousel',
        impressionType: 'scroll_view',
        isViewed: true,
        viewDuration: viewDuration,
        viewCount: 1,
        frequencyCap: DAILY_VIEW_FREQUENCY_CAP,
        timestamp: new Date()
      });
      
      // Increment views on AdCreative (buffered $inc, flushed in batches)
      recordCreativeCounter(adId, 'views');

      bookDeliveredView(creatorId, adId, 'carousel');

    res.status(200).json({ 
      success: true,
      message: 'Carousel ad view tracked successfully',
      viewDuration: viewDuration,
      dailyViews: normalizedUserId ? dailyViewCount + 1 : undefined,
      frequencyCap: normalizedUserId ? DAILY_VIEW_FREQUENCY_CAP : undefined
    });
  } catch (error) {
    console.error('❌ Error tracking carousel ad view:', error);
    res.status(500).json({ 
      error: 'Failed to track carousel ad view',
      message: error.message 
    });
  }
});

// **NEW: GET /ads/views/video/:videoId/banner - Get banner ad VIEWS (not impressions) for revenue**
router.get('/views/video/:videoId/banner', async (req, res) => {
  try {
    const { videoId } = req.params;
    const { month, year } = req.query; // Optional month/year filtering

    // console.log(`👁️ Getting banner ad VIEWS (for revenue) for video: ${videoId}`);

    // Build query with optional month filtering
    const query = {
      videoId: videoId,
      adType: 'banner',
      ...billableMatch()
    };

    // **NEW: Add month filtering if month and year provided**
    if (month && year) {
      const monthNum = parseInt(month);
      const yearNum = parseInt(year);
      const startDate = new Date(yearNum, monthNum, 1);
      const endDate = new Date(yearNum, monthNum + 1, 1);
      query.timestamp = {
        $gte: startDate,
        $lt: endDate
      };
      // console.log(`📅 Filtering banner views for month ${month}/${year}`);
    }

    // **FIXED: Count only VIEWS (isViewed = true), not impressions**
    const viewCount = await AdImpression.countDocuments(query);

    // console.log(`✅ Banner VIEWS for video ${videoId}: ${viewCount}${month && year ? ` (Month: ${month}/${year})` : ' (All-time)'}`);

    res.status(200).json({ count: viewCount });
  } catch (error) {
    console.error('❌ Error getting banner ad views:', error);
    res.status(500).json({ 
      error: 'Failed to get banner ad views',
      message: error.message 
    });
  }
});

// **NEW: GET /ads/views/video/:videoId/carousel - Get carousel ad VIEWS (not impressions) for revenue**
router.get('/views/video/:videoId/carousel', async (req, res) => {
  try {
    const { videoId } = req.params;
    const { month, year } = req.query; // Optional month/year filtering

    // console.log(`👁️ Getting carousel ad VIEWS (for revenue) for video: ${videoId}`);

    // Build query with optional month filtering
    const query = {
      videoId: videoId,
      adType: 'carousel',
      ...billableMatch()
    };

    // **NEW: Add month filtering if month and year provided**
    if (month && year) {
      const monthNum = parseInt(month);
      const yearNum = parseInt(year);
      const startDate = new Date(yearNum, monthNum, 1);
      const endDate = new Date(yearNum, monthNum + 1, 1);
      query.timestamp = {
        $gte: startDate,
        $lt: endDate
      };
      // console.log(`📅 Filtering carousel views for month ${month}/${year}`);
    }

    // **FIXED: Count only VIEWS (isViewed = true), not impressions**
    const viewCount = await AdImpression.countDocuments(query);

    // console.log(`✅ Carousel VIEWS for video ${videoId}: ${viewCount}${month && year ? ` (Month: ${month}/${year})` : ' (All-time)'}`);

    res.status(200).json({ count: viewCount });
  } catch (error) {
    console.error('❌ Error getting carousel ad views:', error);
    res.status(500).json({ 
      error: 'Failed to get carousel ad views',
      message: error.message 
    });
  }
});

export default router;

