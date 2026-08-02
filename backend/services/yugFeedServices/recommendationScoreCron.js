import cron from 'node-cron';
import RecommendationService from './recommendationService.js';

/**
 * Recommendation Score Recalculation Cron Job
 * Recalculates video recommendation scores every 60 minutes
 * 
 * Cron expression runs every 15 minutes
 * Format: minute hour day month dayOfWeek
 */
class RecommendationScoreCron {
  constructor() {
    this.job = null;
    this.isRunning = false;
  }

  /**
   * Start the recommendation score recalculation cron job
   */
  start() {
    if (this.job) {
      console.log('⚠️ Recommendation score cron job is already running');
      return;
    }

    // Schedule job to run every 60 minutes
    // Cron format: minute hour day month dayOfWeek
    this.job = cron.schedule('0 * * * *', async () => {
      await this.recalculateScores();
    }, {
      scheduled: true,
      timezone: 'UTC'
    });

    this.isRunning = true;
    console.log('✅ Recommendation score cron job started');
    console.log('📅 Will recalculate scores every 60 minutes');
    
    // Also run once immediately on startup to initialize scores
    setTimeout(async () => {
      console.log('🚀 Running initial score calculation on startup...');
      await this.recalculateScores();
    }, 30000); // Wait 30 seconds after server starts
  }

  /**
   * Stop the recommendation score cron job
   */
  stop() {
    if (this.job) {
      this.job.stop();
      this.job = null;
      this.isRunning = false;
      console.log('⏹️ Recommendation score cron job stopped');
    }
  }

  /**
   * Recalculate scores for all videos
   */
  async recalculateScores() {
    if (this.isRecalculating) {
      console.log('⚠️ Score recalculation already in progress, skipping...');
      return;
    }

    this.isRecalculating = true;
    const startTime = Date.now();

    try {
      // 1. Recalculate Video Recommendation Scores
      const stats = await RecommendationService.recalculateAllScores({
        batchSize: 100,
        onlyOutdated: true,
        maxAgeMinutes: 60
      });

      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      console.log(`✅ Score recalculation completed in ${duration}s`);
      console.log(`📊 Video Stats: ${stats.processed} processed, ${stats.errors} errors`);
    } catch (error) {
      console.error('❌ Error in recommendation score recalculation:', error);
    } finally {
      this.isRecalculating = false;
    }
  }
}

// Export singleton instance
const recommendationScoreCron = new RecommendationScoreCron();
export default recommendationScoreCron;

