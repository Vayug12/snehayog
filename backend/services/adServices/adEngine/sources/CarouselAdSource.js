import { IAdSource } from '../IAdSource.js';
import AdCreative from '../../../../models/AdCreative.js';
import { servableCampaignMatch } from '../../campaignServability.js';

/**
 * **CarouselAdSource**
 * Pluggable source that fetches active, approved carousel ads with active campaigns from the database.
 */
export class CarouselAdSource extends IAdSource {
  /**
   * Fetch active carousel ads
   * @param {Object} context Context parameters
   * @returns {Promise<Array<Object>>} Standardized carousel ad creatives
   */
  async getActiveAds(context = {}) {
    const limit = context.limit || 50;

    const query = {
      isActive: true,
      reviewStatus: 'approved',
      adType: 'carousel'
    };

    // Retrieve creative documents and populate their campaigns
    const activeCreatives = await AdCreative.find(query)
      .sort({ createdAt: -1 })
      .populate({
        path: 'campaignId',
        match: servableCampaignMatch()
      })
      .limit(limit)
      .lean();

    // Filter out creatives where the associated campaign is not active/valid
    return activeCreatives.filter(ad => ad.campaignId !== null);
  }
}
