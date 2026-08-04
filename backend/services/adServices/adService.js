import mongoose from 'mongoose';
import AdCreative from '../../models/AdCreative.js';
import AdCampaign from '../../models/AdCampaign.js';
import { calculateCategoryRelevance } from '../../config/categoryMap.js';
import adEngine from './adEngine/index.js';
import { renderedSum, billableSum } from './impressionCounting.js';

class AdService {
  /**
   * Get active ads for serving with proper targeting
   * Delegated entirely to VayuAdEngine plugins
   */
  async getActiveAds(targetingCriteria = {}) {
    try {
      const { adType = 'banner' } = targetingCriteria;
      
      const context = {
        category: targetingCriteria.videoCategory,
        tags: targetingCriteria.videoTags,
        keywords: targetingCriteria.videoKeywords,
        location: targetingCriteria.location,
        platform: targetingCriteria.platform,
        videoData: {
          category: targetingCriteria.videoCategory,
          tags: targetingCriteria.videoTags,
          keywords: targetingCriteria.videoKeywords,
          videoName: targetingCriteria.videoKeywords?.[0] || ''
        }
      };

      const options = {
        adType: adType,
        limit: 10,
        useFallback: true
      };

      return await adEngine.getTargetedFeed(context, options);
    } catch (error) {
      console.error('❌ AdService: Error delegating to AdEngine:', error);
      return [];
    }
  }

  /**
   * Transform raw AdCreative document to frontend-expected format
   */
  transformAdForFrontend(adCreative) {
    const campaign = adCreative.campaignId;
    
    // Extract image URL based on ad type
    let imageUrl = null;
    if (adCreative.adType === 'carousel') {
      imageUrl = adCreative.slides?.[0]?.thumbnail || adCreative.slides?.[0]?.mediaUrl || null;
    } else {
      imageUrl = adCreative.thumbnail || adCreative.cloudinaryUrl || null;
    }
    
    // Extract call-to-action link
    const link = adCreative.callToAction?.url || null;
    
    // Base response object
    const response = {
      _id: adCreative._id.toString(),
      id: adCreative._id.toString(),
      adType: adCreative.adType,
      imageUrl: imageUrl,
      link: link,
      cloudinaryUrl: adCreative.cloudinaryUrl,
      thumbnail: adCreative.thumbnail,
      impressions: adCreative.impressions || 0,
      clicks: adCreative.clicks || 0,
      createdAt: adCreative.createdAt,
      updatedAt: adCreative.updatedAt,
    };
    
    // Add title for all ad types, description only for non-banner ads
    response.title = adCreative.title || campaign?.name || 'Untitled Ad';
    if (adCreative.adType !== 'banner') {
      response.description = campaign?.objective || '';
    }
    
    return response;
  }

  /**
   * Track ad click
   */
  async trackAdClick(adId, clickData = {}) {
    try {
      console.log('🖱️ AdService: Tracking click for ad:', adId);
      
      const ad = await AdCreative.findById(adId);
      if (!ad) {
        throw new Error('Ad not found');
      }
      
      // Increment click count
      ad.clicks = (ad.clicks || 0) + 1;
      await ad.save();
      
      // Also increment campaign clicks if available
      if (ad.campaignId) {
        const campaign = await AdCampaign.findById(ad.campaignId);
        if (campaign) {
          campaign.clicks = (campaign.clicks || 0) + 1;
          await campaign.save();
        }
      }
      
      console.log('✅ AdService: Click tracked successfully');
      return { success: true, clicks: ad.clicks };
      
    } catch (error) {
      console.error('❌ AdService: Error tracking click:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Get ad analytics
   */
  async getAdAnalytics(adId, userId = null) {
    try {
      console.log('📊 AdService: Getting analytics for ad:', adId, 'userId:', userId);
      
      // **FIX: Try to find by AdCreative ID first, then by Campaign ID**
      let ad = await AdCreative.findById(adId).populate('campaignId');
      
      // If not found as AdCreative, try finding by Campaign ID
      if (!ad) {
        console.log('🔍 AdService: Not found as AdCreative, trying Campaign ID...');
        const campaign = await AdCampaign.findById(adId);
        if (campaign) {
          // Find the creative for this campaign
          ad = await AdCreative.findOne({ campaignId: campaign._id }).populate('campaignId');
        }
      }
      
      if (!ad) {
        console.error('❌ AdService: Ad not found for ID:', adId);
        throw new Error('Ad not found');
      }

      console.log('✅ AdService: Found ad:', ad._id, 'Campaign:', ad.campaignId?._id);

      // **FIX: Verify user owns this ad via campaign's advertiserUserId**
      if (userId) {
        const campaign = ad.campaignId;
        if (!campaign) {
          throw new Error('Campaign not found for this ad');
        }

        // Get user's googleId to match with advertiserUserId
        const User = mongoose.model('User');
        const user = await User.findOne({ googleId: userId });
        
        if (!user) {
          console.error('❌ AdService: User not found for googleId:', userId);
          throw new Error('User not found');
        }

        // Compare campaign's advertiserUserId with user's _id
        if (campaign.advertiserUserId.toString() !== user._id.toString()) {
          console.error('❌ AdService: Access denied. Campaign advertiserUserId:', campaign.advertiserUserId, 'User _id:', user._id);
          throw new Error('Access denied');
        }

        console.log('✅ AdService: User verification passed');
      }

      // **FIX: Get campaign data for proper metrics**
      const campaign = ad.campaignId;
      const cpm = campaign?.cpmINR || 30;
      const ctr = this.calculateCTR(ad.clicks || 0, ad.impressions || 0);
      const spend = this.calculateSpend((ad.adType === 'carousel' ? (ad.views || 0) : (ad.impressions || 0)), cpm);
      const revenue = spend * 0.7; // 70% to advertiser, 30% to platform

      // **FIX: Get imageUrl based on ad type**
      let imageUrl = null;
      if (ad.adType === 'carousel' && ad.slides && ad.slides.length > 0) {
        imageUrl = ad.slides[0].thumbnail || ad.slides[0].mediaUrl || null;
      } else {
        imageUrl = ad.thumbnail || ad.cloudinaryUrl || null;
      }

      const result = {
        ad: {
          id: ad._id.toString(),
          campaignId: campaign?._id?.toString(),
          title: ad.title || campaign?.name || 'Unknown Ad',
          status: ad.isActive ? 'active' : 'inactive',
          impressions: ad.impressions || 0,
          views: ad.views || 0,
          clicks: ad.clicks || 0,
          ctr: ctr.toFixed(2),
          spend: spend.toFixed(2),
          revenue: revenue.toFixed(2),
          cpm: cpm.toFixed(2),
          adType: ad.adType || 'banner',
          imageUrl: imageUrl, // **FIX: Include imageUrl for proper display**
          createdAt: ad.createdAt,
          updatedAt: ad.updatedAt
        }
      };

      console.log('✅ AdService: Analytics calculated successfully:', result);
      return result;
      
    } catch (error) {
      console.error('❌ AdService: Error getting analytics:', error);
      throw error; // Re-throw to let route handle it
    }
  }

  /**
   * Get granular breakdown of ad performance per video
   */
  async getAdVideoBreakdown(adId) {
    try {
      console.log('📊 AdService: Getting video breakdown for ad:', adId);
      
      const AdImpression = mongoose.model('AdImpression');
      const Video = mongoose.model('Video');
      
      const adObjectId = new mongoose.Types.ObjectId(adId);
      
      // Aggregate impressions and views grouped by videoId
      const breakdownData = await AdImpression.aggregate([
        { $match: { adId: adObjectId } },
        {
          $group: {
            _id: '$videoId',
            // Rendered and billable are separate rows, so `$sum: 1` here was
            // reach + views — an impression count the advertiser's own CTR
            // could never be reconciled against.
            impressions: renderedSum(),
            views: billableSum(),
            totalDuration: { $sum: '$viewDuration' }
          }
        },
        { $sort: { impressions: -1 } }
      ]);
      
      if (!breakdownData || breakdownData.length === 0) {
        return [];
      }
      
      // Populate video titles and info
      const results = [];
      const cpm = 30; // Default CPM for calculation
      
      for (const item of breakdownData) {
        const video = await Video.findById(item._id).select('title uploader').lean();
        if (video) {
          const spend = (item.views / 1000) * cpm;
          results.push({
            videoId: item._id,
            videoTitle: video.title || 'Untitled Video',
            impressions: item.impressions,
            views: item.views,
            spend: spend.toFixed(2),
            ctr: item.impressions > 0 ? ((item.views / item.impressions) * 100).toFixed(2) : '0.00'
          });
        }
      }
      
      return results;
    } catch (error) {
      console.error('❌ AdService: Error getting video breakdown:', error);
      throw error;
    }
  }

  /**
   * Calculate CTR
   */
  calculateCTR(clicks, impressions) {
    if (impressions === 0) return 0;
    return (clicks / impressions) * 100;
  }

  /**
   * Calculate spend
   */
  calculateSpend(impressions, cpm) {
    return (impressions / 1000) * cpm;
  }
}

export default new AdService();
