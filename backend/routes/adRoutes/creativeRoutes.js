import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { adUpload, cleanupTempFile } from '../../config/upload.js';
import AdCreative from '../../models/AdCreative.js';
import AdCampaign from '../../models/AdCampaign.js';
import User from '../../models/User.js';
import cloudflareR2Service from '../../services/uploadServices/cloudflareR2Service.js';
import { servableCampaignMatch } from '../../services/adServices/campaignServability.js';

const router = express.Router();

// **NEW: Manual upload endpoint (Bypass Worker but upload to Cloudflare R2)**
router.post('/upload-manual', adUpload.single('media'), asyncHandler(async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }
  
  try {
    const filename = req.file.filename;
    const filePath = req.file.path;
    const mimeType = req.file.mimetype;
    
    // Define the key for R2
    const key = `snehayog/ads/images/${filename}`;
    
    console.log(`📤 Uploading manual ad creative file to R2: ${key}`);
    const uploadResult = await cloudflareR2Service.uploadFileToR2(filePath, key, mimeType);
    
    // Clean up local temp file immediately after upload
    cleanupTempFile(filePath);
    
    console.log('✅ Manual upload to R2 success:', uploadResult.url);
    
    res.json({ 
      url: uploadResult.url,
      publicUrl: uploadResult.url,
      key: uploadResult.key
    });
  } catch (error) {
    console.error('❌ Error during manual upload to R2:', error);
    // Cleanup local file in case of error
    if (req.file && req.file.path) {
      cleanupTempFile(req.file.path);
    }
    res.status(500).json({ error: 'Failed to upload creative to Cloudflare R2' });
  }
}));

// POST /ads/campaigns/:id/creatives - Upload ad creative
router.post('/campaigns/:id/creatives', adUpload.single('creative'), asyncHandler(async (req, res) => {
  const campaignId = req.params.id;
  const {
    adType,
    type,
    durationSec,
    title
  } = req.body;

  // Validate campaign exists
  const campaign = await AdCampaign.findById(campaignId);
  if (!campaign) {
    cleanupTempFile(req.file?.path);
    return res.status(404).json({ error: 'Campaign not found' });
  }

  // Validate adType
  if (!adType || !['banner', 'carousel'].includes(adType)) {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Invalid adType. Must be one of: banner, carousel' 
    });
  }

  // Validate file upload
  if (!req.file) {
    return res.status(400).json({ error: 'No creative file uploaded' });
  }

  // Validate media type based on adType
  if (adType === 'banner' && type !== 'image') {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Banner ads can only use images' 
    });
  }

  // Validate required fields based on adType
  if (!type || !['image', 'video'].includes(type)) {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Invalid media type. Must be image or video' 
    });
  }

  // Validate title for banner ads
  if (adType === 'banner') {
    if (!title || title.trim().length === 0) {
      cleanupTempFile(req.file?.path);
      return res.status(400).json({ 
        error: 'Banner ads require a title' 
      });
    }
    
    // Check word count (max 30 words)
    const wordCount = title.trim().split(/\s+/).length;
    if (wordCount > 30) {
      cleanupTempFile(req.file?.path);
      return res.status(400).json({ 
        error: 'Title must be 30 words or less' 
      });
    }
  }

  // Validate duration for video ads (non-carousel)
  if (type === 'video' && (!durationSec || durationSec < 1 || durationSec > 60)) {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Video ads require duration between 1-60 seconds' 
    });
  }

}));

// POST /ads/campaigns/:id/creatives/carousel - Upload carousel ad with multiple images
router.post('/campaigns/:id/creatives/carousel', adUpload.array('creatives', 10), asyncHandler(async (req, res) => {
  const campaignId = req.params.id;
  const {
    type,
    callToActionLabel,
    callToActionUrl,
    slideTitles, // Optional: JSON string array of titles for each slide
    slideDescriptions // Optional: JSON string array of descriptions
  } = req.body;

  // Validate campaign exists
  const campaign = await AdCampaign.findById(campaignId);
  if (!campaign) {
    req.files?.forEach(file => cleanupTempFile(file.path));
    return res.status(404).json({ error: 'Campaign not found' });
  }

  // Validate file upload
  if (!req.files || req.files.length === 0) {
    return res.status(400).json({ error: 'No creative files uploaded' });
  }

  if (req.files.length > 10) {
    req.files?.forEach(file => cleanupTempFile(file.path));
    return res.status(400).json({ 
      error: 'Carousel ads can have maximum 10 slides' 
    });
  }

  // Validate media type
  if (!type || !['image', 'video'].includes(type)) {
    req.files?.forEach(file => cleanupTempFile(file.path));
    return res.status(400).json({ 
      error: 'Invalid media type. Must be image or video' 
    });
  }

  try {
    // Parse optional slide metadata
    try {
      titles = slideTitles ? JSON.parse(slideTitles) : [];
      descriptions = slideDescriptions ? JSON.parse(slideDescriptions) : [];
    } catch (e) {
      console.log('⚠️ Could not parse slide metadata, using defaults');
    }

    // Upload all files and create slides array
    const slides = [];

    // Create carousel ad creative with slides
    const creative = new AdCreative({
      campaignId,
      adType: 'carousel',
      type,
      slides,
      callToAction: {
        label: callToActionLabel || 'Learn More',
        url: callToActionUrl
      },
      reviewStatus: 'approved', // Auto-approve carousel ads
      isActive: true, // **FIX: Activate carousel ads immediately**
      activatedAt: new Date() // **FIX: Set activation timestamp**
    });

    await creative.save();

    console.log(`✅ Carousel ad created with ${slides.length} slides`);

    res.status(201).json({
      message: `Carousel ad created successfully with ${slides.length} slides`,
      creative,
      slidesCount: slides.length
    });

  } catch (error) {
    console.error('Carousel creative upload error:', error);
    throw error;
  } finally {
    // Clean up temp files
    req.files?.forEach(file => cleanupTempFile(file.path));
  }
}));

// GET /ads/creatives - Get ad creatives with optional filtering
router.get('/', asyncHandler(async (req, res) => {
  const { adType, type, campaignId, status } = req.query;
  
  // Build filter object
  const filter = {};
  
  if (adType) {
    filter.adType = adType;
  }
  
  if (type) {
    filter.type = type;
  }
  
  if (campaignId) {
    filter.campaignId = campaignId;
  }
  
  if (status) {
    filter.reviewStatus = status;
  }

  const creatives = await AdCreative.find(filter)
    .populate('campaignId', 'name status')
    .sort({ createdAt: -1 });

  res.json({
    message: 'Ad creatives retrieved successfully',
    count: creatives.length,
    creatives
  });
}));

// GET /ads/creatives/types - Get available ad types and their media type restrictions
router.get('/types', asyncHandler(async (req, res) => {
  const adTypes = [
    {
      type: 'banner',
      name: 'Banner Ads',
      description: 'Static image ads displayed at the top or bottom of screens',
      allowedMediaTypes: ['image'],
      restrictions: 'Only images allowed',
      useCase: 'Brand awareness, promotions, announcements'
    },
    {
      type: 'carousel',
      name: 'Carousel Ads',
      description: 'Multiple images or videos that users can swipe through',
      allowedMediaTypes: ['image', 'video'],
      restrictions: 'Both images and videos allowed',
      useCase: 'Product showcases, story-based content, multiple offerings'
    },
  ];

  res.json({
    message: 'Available ad types and their specifications',
    adTypes
  });
}));

// **NEW: Carousel Ad Endpoints**

// GET /ads/carousel - Get all active carousel ads
router.get('/carousel', asyncHandler(async (req, res) => {
  try {
    console.log('🎯 Fetching carousel ads...');
    
    // **DEBUG: Check ALL carousel ads regardless of status**
    const allCarouselCreatives = await AdCreative.find({
      adType: 'carousel'
    }).populate('campaignId', 'name advertiserUserId status');
    
    console.log(`🔍 Total carousel ads in database: ${allCarouselCreatives.length}`);
    if (allCarouselCreatives.length > 0) {
      allCarouselCreatives.forEach(ad => {
        console.log(`   📍 Carousel Ad ID: ${ad._id}`);
        console.log(`      - isActive: ${ad.isActive}`);
        console.log(`      - reviewStatus: ${ad.reviewStatus}`);
        console.log(`      - campaign: ${ad.campaignId ? ad.campaignId.name : 'NO CAMPAIGN'}`);
      });
    }
    
    // Find all active carousel ads whose campaign is still servable — an
    // exhausted or expired campaign must not be surfaced here either.
    const carouselCreatives = (await AdCreative.find({
      adType: 'carousel',
      isActive: true,
      reviewStatus: 'approved'
    }).populate({
      path: 'campaignId',
      select: 'name advertiserUserId status startDate endDate spentINR totalBudget',
      match: servableCampaignMatch()
    })).filter(creative => creative.campaignId !== null);
    
    console.log(`🎯 Found ${carouselCreatives.length} ACTIVE & APPROVED carousel ads`);
    
    if (carouselCreatives.length === 0) {
      console.log('⚠️ No carousel ads available yet');
      console.log('💡 Create a carousel ad in the app - it will be auto-approved and visible immediately!');
    }
    
    // Transform to carousel ad format
    const carouselAds = [];
    
    for (const creative of carouselCreatives) {
      try {
        // **FIX: Skip if campaign was deleted (campaignId is null)**
        if (!creative.campaignId) {
          console.log(`⚠️ Skipping creative ${creative._id} - campaign was deleted`);
          continue;
        }

        // Get advertiser info
        const advertiser = await User.findById(creative.campaignId.advertiserUserId);
        
        // **FIX: Use default values if advertiser not found**
        const advertiserName = advertiser?.name || 'Unknown Advertiser';
        const advertiserProfilePic = advertiser?.profilePic || '';
        
        // Create carousel ad object with all slides
        const carouselAd = {
          id: creative._id,
          campaignId: creative.campaignId._id,
          advertiserName: advertiserName,
          advertiserProfilePic: advertiserProfilePic,
          slides: creative.slides && creative.slides.length > 0 
            ? creative.slides.map(slide => ({
                id: slide._id || creative._id,
                mediaUrl: slide.mediaUrl,
                thumbnailUrl: slide.thumbnail,
                mediaType: slide.mediaType || 'image',
                aspectRatio: slide.aspectRatio || '9:16',
                durationSec: slide.durationSec,
                title: slide.title,
                description: slide.description
              }))
            : [{
                // Fallback for old carousel ads without slides array
                id: creative._id,
                mediaUrl: creative.cloudinaryUrl,
                thumbnailUrl: creative.thumbnail,
                mediaType: creative.type,
                aspectRatio: creative.aspectRatio,
                durationSec: creative.durationSec
              }],
          callToActionLabel: creative.callToAction?.label || 'Learn More',
          callToActionUrl: creative.callToAction?.url || '',
          isActive: creative.isActive,
          createdAt: creative.createdAt,
          impressions: creative.impressions,
          clicks: creative.clicks,
        };
        
        carouselAds.push(carouselAd);
        console.log(`✅ Processed carousel ad: ${creative._id} with ${carouselAd.slides.length} slides`);
      } catch (error) {
        console.error(`❌ Error processing carousel ad ${creative._id}:`, error);
        continue;
      }
    }
    
    console.log(`✅ Successfully processed ${carouselAds.length} carousel ads`);
    
    res.json(carouselAds);
    
  } catch (error) {
    console.error('❌ Error fetching carousel ads:', error);
    res.status(500).json({ 
      error: 'Failed to fetch carousel ads',
      message: error.message 
    });
  }
}));

// GET /ads/carousel/:id - Get specific carousel ad
router.get('/carousel/:id', asyncHandler(async (req, res) => {
  try {
    const { id } = req.params;
    console.log('🎯 Fetching carousel ad:', id);
    
    const creative = await AdCreative.findById(id)
      .populate('campaignId', 'name advertiserUserId status');
    
    if (!creative) {
      return res.status(404).json({ error: 'Carousel ad not found' });
    }
    
    if (creative.adType !== 'carousel ads') {
      return res.status(400).json({ error: 'Not a carousel ad' });
    }
    
    // Get advertiser info
    const advertiser = await User.findById(creative.campaignId.advertiserUserId);
    
    const carouselAd = {
      id: creative._id,
      campaignId: creative.campaignId._id,
      advertiserName: advertiser?.name || 'Unknown Advertiser',
      advertiserProfilePic: advertiser?.profilePic || '',
      slides: creative.slides && creative.slides.length > 0 
        ? creative.slides.map(slide => ({
            id: slide._id || creative._id,
            mediaUrl: slide.mediaUrl,
            thumbnailUrl: slide.thumbnail,
            mediaType: slide.mediaType || 'image',
            aspectRatio: slide.aspectRatio || '9:16',
            durationSec: slide.durationSec,
            title: slide.title,
            description: slide.description
          }))
        : [{
            // Fallback for old carousel ads without slides array
            id: creative._id,
            mediaUrl: creative.cloudinaryUrl,
            thumbnailUrl: creative.thumbnail,
            mediaType: creative.type,
            aspectRatio: creative.aspectRatio,
            durationSec: creative.durationSec
          }],
      callToActionLabel: creative.callToAction?.label || 'Learn More',
      callToActionUrl: creative.callToAction?.url || '',
      isActive: creative.isActive,
      createdAt: creative.createdAt,
      impressions: creative.impressions,
      clicks: creative.clicks,
    };
    
    console.log(`✅ Fetched carousel ad with ${carouselAd.slides.length} slides`);
    res.json(carouselAd);
    
  } catch (error) {
    console.error('❌ Error fetching carousel ad:', error);
    res.status(500).json({ 
      error: 'Failed to fetch carousel ad',
      message: error.message 
    });
  }
}));

// POST /ads/carousel/:id/impression - Track carousel ad impression
router.post('/carousel/:id/impression', asyncHandler(async (req, res) => {
  try {
    const { id } = req.params;
    console.log('📊 Tracking impression for carousel ad:', id);
    
    const creative = await AdCreative.findById(id);
    if (!creative) {
      return res.status(404).json({ error: 'Carousel ad not found' });
    }
    
    // Increment impression count
    creative.impressions = (creative.impressions || 0) + 1;
    await creative.save();
    
    console.log(`✅ Impression tracked for carousel ad ${id}. New count: ${creative.impressions}`);
    
    res.json({ 
      message: 'Impression tracked successfully',
      impressions: creative.impressions 
    });
    
  } catch (error) {
    console.error('❌ Error tracking impression:', error);
    res.status(500).json({ 
      error: 'Failed to track impression',
      message: error.message 
    });
  }
}));

// POST /ads/carousel/:id/click - Track carousel ad click
router.post('/carousel/:id/click', asyncHandler(async (req, res) => {
  try {
    const { id } = req.params;
    console.log('🖱️ Tracking click for carousel ad:', id);
    
    const creative = await AdCreative.findById(id);
    if (!creative) {
      return res.status(404).json({ error: 'Carousel ad not found' });
    }
    
    // Increment click count
    creative.clicks = (creative.clicks || 0) + 1;
    await creative.save();
    
    console.log(`✅ Click tracked for carousel ad ${id}. New count: ${creative.clicks}`);
    
    res.json({ 
      message: 'Click tracked successfully',
      clicks: creative.clicks 
    });
    
  } catch (error) {
    console.error('❌ Error tracking click:', error);
    res.status(500).json({ 
      error: 'Failed to track click',
      message: error.message 
    });
  }
}));

export default router;
