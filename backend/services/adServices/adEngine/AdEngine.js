import { BannerAdSource } from './sources/BannerAdSource.js';
import { CarouselAdSource } from './sources/CarouselAdSource.js';
import { ContextualTargeter } from './targeters/ContextualTargeter.js';
import { DemographicTargeter } from './targeters/DemographicTargeter.js';

/**
 * **AdEngine**
 * Central orchestrator for Vayu's plug-and-play Ad engine.
 * Manages active ad sources and scores candidates through targeting pipelines.
 */
export class AdEngine {
  constructor(sources = [], targeters = []) {
    // Register default sources if none are passed in
    this.sources = sources.length > 0 ? sources : [
      new BannerAdSource(),
      new CarouselAdSource()
    ];

    // Register targeting pipelines
    this.targeters = targeters.length > 0 ? targeters : [
      new ContextualTargeter(),
      new DemographicTargeter()
    ];
  }

  /**
   * Fetch, score, and filter ads for a specific video feed and user context
   * @param {Object} context Context signals (e.g. videoData, userProfile, location, platform, adType)
   * @param {Object} options Configuration parameters (e.g. limit, useFallback)
   * @returns {Promise<Array<Object>>} Standardized and targeted ad creatives for the frontend
   */
  async getTargetedFeed(context = {}, options = {}) {
    const {
      limit = 3,
      useFallback = true,
      adType = 'banner'
    } = options;

    try {
      console.log(`🎯 AdEngine: Requesting ${adType} ads for feed context...`);

      // 1. Locate the correct registered source for the requested adType
      const activeSource = this.sources.find(source => {
        const sourceName = source.constructor.name.toLowerCase();
        return sourceName.includes(adType);
      });

      if (!activeSource) {
        console.warn(`⚠️ AdEngine: No active source registered for adType: ${adType}`);
        return [];
      }

      // 2. Fetch candidates from the source
      const candidates = await activeSource.getActiveAds({ limit: 50 });
      if (candidates.length === 0) {
        console.log(`🔄 AdEngine: No ad candidates found in source for adType: ${adType}`);
        return [];
      }

      // Prepare scoring context
      const videoData = context.videoData || {};
      const targeterContext = {
        videoCategory: videoData.category || context.category,
        videoTags: videoData.tags || context.tags || [],
        videoKeywords: videoData.keywords || context.keywords || [],
        location: context.location,
        platform: context.platform,
        deviceType: context.deviceType
      };

      // 3. Score all candidates in parallel using targeter plugins
      const scoredCandidates = await Promise.all(
        candidates.map(async (ad) => {
          let totalScore = 50; // Base baseline score
          const matchReasons = [];

          for (const targeter of this.targeters) {
            try {
              const evaluation = await targeter.evaluate(ad, targeterContext);
              totalScore += evaluation.scoreModifier;
              if (evaluation.scoreModifier > 0 && evaluation.reason) {
                matchReasons.push(evaluation.reason);
              }
            } catch (err) {
              console.warn(`⚠️ Targeter ${targeter.constructor.name} failed:`, err.message);
            }
          }

          // Backport campaign data for formatting
          const campaign = ad.campaignId || {};
          
          return {
            ...ad,
            campaign,
            targetingScore: Math.min(Math.max(totalScore, 0), 100),
            matchReasons
          };
        })
      );

      // 4. Filter, sort, and slice matches
      // A score > 50 indicates positive matching signals
      const matchingAds = scoredCandidates
        .filter(item => item.targetingScore > 50)
        .sort((a, b) => b.targetingScore - a.targetingScore || b.impressions - a.impressions)
        .slice(0, limit);

      if (matchingAds.length > 0) {
        console.log(`✅ AdEngine: Found ${matchingAds.length} highly matched targeted ads`);
        return this.transformAdsForFrontend(matchingAds);
      }

      // 5. Final Fallback: Sorted by impressions if no targeted ads match
      if (useFallback) {
        console.log('🔄 AdEngine: No high-relevance ads found. Triggering impressions-based fallback...');
        const generalFallback = scoredCandidates
          .sort((a, b) => (b.impressions || 0) - (a.impressions || 0) || b.createdAt - a.createdAt)
          .slice(0, limit);
        return this.transformAdsForFrontend(generalFallback);
      }

      return [];
    } catch (error) {
      console.error('❌ AdEngine: Failed to compile targeted feed:', error);
      return [];
    }
  }

  /**
   * Standardize backend creative schema into expected frontend contract.
   * Ensures absolute backward compatibility.
   */
  transformAdsForFrontend(ads) {
    return ads.map(ad => {
      const campaign = ad.campaign || ad.campaignId || {};
      
      // Determine the image/thumbnail source exactly like the legacy method
      let imageUrl = '';
      if (ad.adType === 'carousel') {
        imageUrl = ad.slides?.[0]?.thumbnail || ad.slides?.[0]?.mediaUrl || '';
      } else {
        imageUrl = ad.thumbnail || ad.cloudinaryUrl || '';
      }

      return {
        _id: ad._id ? ad._id.toString() : '',
        id: ad._id ? ad._id.toString() : '',
        adType: ad.adType,
        imageUrl: imageUrl,
        link: ad.callToAction?.url || '',
        cloudinaryUrl: ad.cloudinaryUrl || '',
        thumbnail: ad.thumbnail || '',
        title: ad.title || campaign.name || 'Untitled Ad',
        description: ad.adType === 'banner' ? '' : (campaign.objective || ad.description || ''),
        callToAction: ad.callToAction?.label || 'Learn More',
        targetingScore: ad.targetingScore || 0,
        impressions: ad.impressions || 0,
        clicks: ad.clicks || 0,
        ctr: ad.ctr || 0,
        createdAt: ad.createdAt || new Date(),
        updatedAt: ad.updatedAt || new Date(),
        campaign: {
          id: campaign._id ? campaign._id.toString() : '',
          name: campaign.name || '',
          objective: campaign.objective || '',
          status: campaign.status || ''
        }
      };
    });
  }
}

// Export pre-initialized shared default instance
export default new AdEngine();
