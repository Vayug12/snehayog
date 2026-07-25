import fs from 'fs';
import path from 'path';
import AdCampaign from '../../models/AdCampaign.js';
import AdCreative from '../../models/AdCreative.js';
import Invoice from '../../models/Invoice.js';

class AdCleanupService {
  /**
   * Helper to delete local file or R2 file from URL
   */
  async deleteAdAsset(url) {
    if (!url) return;
    
    try {
      // 1. Check if it's a local file path or local server URL
      if (url.startsWith('/') || url.includes('/uploads/ads/')) {
        let relativePath = url;
        if (url.startsWith('http')) {
          try {
            const parsed = new URL(url);
            relativePath = parsed.pathname;
          } catch (urlErr) {
            console.error('⚠️ URL parsing error for local asset:', urlErr.message);
          }
        }
        // Strip leading slash
        if (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
        const absolutePath = path.join(process.cwd(), relativePath);
        if (fs.existsSync(absolutePath)) {
          fs.unlinkSync(absolutePath);
          console.log(`🧹 Deleted local temp file: ${absolutePath}`);
        }
        return;
      }
      
      // 2. Check if it's a Cloudflare R2 URL — lazy load only when needed
      const { default: cloudflareR2Service } = await import('../uploadServices/cloudflareR2Service.js');
      try {
        const parsed = new URL(url);
        const pathname = decodeURIComponent(parsed.pathname);
        const key = pathname.startsWith('/') ? pathname.substring(1) : pathname;
        
        if (
          key.startsWith('snehayog/') || 
          key.startsWith('videos/') || 
          key.startsWith('thumbnails/') || 
          key.startsWith('hls/') || 
          key.startsWith('ads/')
        ) {
          console.log(`🧹 Deleting asset from R2: ${key}`);
          await cloudflareR2Service.deleteFile(key);
        }
      } catch (r2Err) {
        console.warn('⚠️ Cloudflare R2 URL key parsing/deleting error:', r2Err.message);
      }
    } catch (e) {
      console.error(`⚠️ Error deleting asset for URL ${url}:`, e.message);
    }
  }

  /**
   * Automatically deletes expired campaigns, their creatives, invoices, and associated R2/local assets
   */
  async runCleanup() {
    console.log('🧹 Starting ad cleanup job...');
    const now = new Date();

    try {
      // Find campaigns that have expired (endDate in the past) or are marked completed
      const expiredCampaigns = await AdCampaign.find({
        $or: [
          { endDate: { $lt: now } },
          { status: 'completed' }
        ]
      });

      console.log(`🔍 Found ${expiredCampaigns.length} expired or completed campaigns to clean up`);

      if (expiredCampaigns.length === 0) {
        return { processed: 0, success: true };
      }

      let processedCount = 0;
      for (const campaign of expiredCampaigns) {
        console.log(`📦 Processing deletion for expired campaign: ${campaign._id} (${campaign.name})`);

        // 1. Find all creatives associated with this campaign
        const creatives = await AdCreative.find({ campaignId: campaign._id });
        const creativeIds = creatives.map(c => c._id);

        for (const creative of creatives) {
          console.log(`  🖼️ Cleaning assets for creative: ${creative._id} (${creative.adType})`);

          // Delete main media URL (cloudinaryUrl)
          if (creative.cloudinaryUrl) {
            await this.deleteAdAsset(creative.cloudinaryUrl);
          }

          // Delete thumbnail
          if (creative.thumbnail) {
            await this.deleteAdAsset(creative.thumbnail);
          }

          // Delete carousel slides
          if (creative.slides && creative.slides.length > 0) {
            for (const slide of creative.slides) {
              if (slide.mediaUrl) {
                await this.deleteAdAsset(slide.mediaUrl);
              }
              if (slide.thumbnail) {
                await this.deleteAdAsset(slide.thumbnail);
              }
            }
          }

          // Delete the creative record from the database
          await AdCreative.findByIdAndDelete(creative._id);
          console.log(`  ✅ Creative ${creative._id} document deleted`);
        }

        // 2. Delete related Invoice records
        const invoiceDeleteResult = await Invoice.deleteMany({
          $or: [
            { campaignId: campaign._id },
            { campaignId: { $in: creativeIds } }
          ]
        });
        if (invoiceDeleteResult.deletedCount > 0) {
          console.log(`  🧾 Deleted ${invoiceDeleteResult.deletedCount} invoices associated with the campaign/creatives`);
        }

        // 3. Finally, delete the campaign record itself
        await AdCampaign.findByIdAndDelete(campaign._id);
        console.log(`🎉 Campaign ${campaign._id} metadata and records completely deleted`);

        processedCount++;
      }

      console.log(`🎉 Expired ad cleanup complete. Fully deleted ${processedCount} campaigns and their assets.`);
      return { processed: processedCount, success: true };
    } catch (error) {
      console.error('❌ Error during expired ad cleanup:', error);
      throw error;
    }
  }
}

const adCleanupService = new AdCleanupService();
export default adCleanupService;
