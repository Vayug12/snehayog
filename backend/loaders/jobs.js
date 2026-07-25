import cron from 'node-cron';
import automatedPayoutService from '../services/payoutServices/automatedPayoutService.js';
import monthlyNotificationCron from '../services/notificationServices/monthlyNotificationCron.js';
import recommendationScoreCron from '../services/yugFeedServices/recommendationScoreCron.js';
import adCleanupService from '../services/adServices/adCleanupService.js';

export default async () => {
  try {
    // Start services that require database
    automatedPayoutService.startScheduler();

    // Start ad cleanup cron job (run monthly on the 1st day of every month at midnight 00:00)
    cron.schedule('0 0 1 * *', async () => {
      try {
        await adCleanupService.runCleanup();
      } catch (error) {
        console.error('❌ Error in scheduled ad cleanup:', error);
      }
    });

    // Start monthly notification cron job (runs on 1st of every month at 9:00 AM)
    monthlyNotificationCron.start();

    // Start recommendation score recalculation cron job (runs every 15 minutes)
    recommendationScoreCron.start();

    // Lazy load exclusiveVideoCleanupService — only loads @aws-sdk + cloudflareR2Service when cron runs
    cron.schedule('0 0 * * *', async () => {
      try {
        const { default: exclusiveVideoCleanupService } = await import('../services/uploadServices/exclusiveVideoCleanupService.js');
        await exclusiveVideoCleanupService.runCleanup();
      } catch (error) {
        console.error('❌ Error in exclusive video cleanup:', error);
      }
    });

    console.log('✅ Background jobs initialized');
  } catch (error) {
    console.error('❌ Jobs loader failed:', error);
  }
};
