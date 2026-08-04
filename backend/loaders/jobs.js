import cron from 'node-cron';
import automatedPayoutService from '../services/payoutServices/automatedPayoutService.js';
import monthlyNotificationCron from '../services/notificationServices/monthlyNotificationCron.js';
import recommendationScoreCron from '../services/yugFeedServices/recommendationScoreCron.js';
import adCleanupService from '../services/adServices/adCleanupService.js';
import { expireEndedCampaigns } from '../services/adServices/campaignSettlement.js';

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

    // Close campaigns whose flight window has passed and return the budget
    // they never spent. Nothing else transitions a campaign off its end date,
    // so until this runs the advertiser's unspent credits sit locked inside a
    // campaign that has stopped serving.
    //
    // Two triggers, because neither alone is enough here:
    //
    //  - On boot. fly.toml runs with `auto_stop_machines = 'stop'` and
    //    `min_machines_running = 0`, so a scheduled job only fires if the
    //    machine happens to be awake at that minute — on a low-traffic app it
    //    usually is not. Boot is the one moment we know we are running, and it
    //    costs no extra wakeup: the machine is already up because a real user
    //    asked for something.
    //  - Weekly, as a backstop for a machine that stays up for days.
    //
    // The sweep is a single indexed query that matches nothing in the normal
    // case, so running it on every cold start is effectively free.
    const settleEndedCampaigns = async (trigger) => {
      try {
        await expireEndedCampaigns();
      } catch (error) {
        console.error(`❌ Error in campaign expiry settlement (${trigger}):`, error);
      }
    };

    // Deferred so a slow sweep cannot hold up the rest of boot.
    setTimeout(() => { settleEndedCampaigns('startup'); }, 10_000).unref?.();

    cron.schedule('0 3 * * 0', () => settleEndedCampaigns('weekly'));

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
