import cron from 'node-cron';
import RecommendationService from './recommendationService.js';
import redisService from '../caching/redisService.js';

/**
 * Recommendation Score Recalculation Cron Job
 *
 * Har run poore completed-video set par chalta hai (~2500 videos, ~86s, har video
 * ka ek read + ek write). Isliye cadence hi asli cost control hai — kaam ka size
 * fix hai, sirf frequency hamare haath me hai.
 *
 * Do trigger hain aur dono ek hi 6-ghante ke window ko share karte hain:
 *
 *   cron    → 00:00 / 06:00 / 12:00 / 18:00 UTC. Sirf tab chalta hai jab app
 *             machine us waqt jaag rahi ho (node-cron in-process hai, aur machine
 *             idle pe auto-stop ho jaati hai).
 *   startup → boot ke 30s baad. Ye catch-up hai: 6-hourly schedule aksar tab aata
 *             hai jab machine soyi hoti hai, to boot hi wo mauka hai jab missed
 *             window pakda ja sake.
 *
 * Window ka record Redis me hai, in-memory nahi — machine ghante me ~4 baar boot
 * hoti hai, to process-local timestamp har baar reset ho jaata aur startup run
 * har boot pe poora sweep chala deta (yehi pehle ho raha tha).
 */

const INTERVAL_MS = 6 * 60 * 60 * 1000;
const LAST_RUN_KEY = 'cron:recoScores:lastRunAt';
const LAST_RUN_TTL_SECONDS = 7 * 24 * 60 * 60;
const STARTUP_DELAY_MS = 30 * 1000;

class RecommendationScoreCron {
  constructor() {
    this.job = null;
    this.startupTimer = null;
    this.isRecalculating = false;
    this.lastRunAt = 0;
  }

  start() {
    if (this.job) {
      console.log('⚠️ Recommendation score cron job is already running');
      return;
    }

    this.job = cron.schedule('0 */6 * * *', () => this.recalculateScores('cron'), {
      scheduled: true,
      timezone: 'UTC'
    });

    this.startupTimer = setTimeout(() => {
      this.startupTimer = null;
      this.recalculateScores('startup');
    }, STARTUP_DELAY_MS);

    console.log('✅ Recommendation score cron job started');
    console.log('📅 Will recalculate scores every 6 hours (00/06/12/18 UTC), plus a gated catch-up on boot');
  }

  stop() {
    if (this.startupTimer) {
      clearTimeout(this.startupTimer);
      this.startupTimer = null;
    }
    if (this.job) {
      this.job.stop();
      this.job = null;
      console.log('⏹️ Recommendation score cron job stopped');
    }
  }

  /**
   * Decide karta hai ki is trigger ko 6-ghante ka window mila ya nahi.
   *
   * @param {'cron'|'startup'} trigger
   */
  async _shouldRun(trigger) {
    const now = Date.now();

    // Same boot me dobara na chale (cron aur startup ka overlap).
    if (now - this.lastRunAt < INTERVAL_MS) return false;

    const raw = await redisService.get(LAST_RUN_KEY);
    const lastRunAt = Number(raw);

    if (!Number.isFinite(lastRunAt) || lastRunAt <= 0) {
      // Koi record nahi — ya to pehli baar hai, ya Redis down hai. Dono me farak
      // nahi kar sakte, isliye trigger ke hisaab se decide karte hain:
      // 'cron' schedule khud hi din me 4 baar se zyada aa nahi sakta, to use
      // chalne dena safe hai. 'startup' har boot pe aata hai — bina durable gate
      // ke wahi purana behaviour wapas aa jayega, isliye use rok dete hain.
      if (trigger === 'startup') {
        console.log('⏭️ Score recalculation skipped: koi durable last-run record nahi (Redis down?)');
        return false;
      }
      return true;
    }

    const elapsedMs = now - lastRunAt;
    if (elapsedMs < INTERVAL_MS) {
      const mins = Math.round(elapsedMs / 60000);
      console.log(`⏭️ Score recalculation skipped (${trigger}): pichhle run ko sirf ${mins} min hue, window 360 min ka hai`);
      return false;
    }

    return true;
  }

  /**
   * Recalculate scores for all videos
   *
   * @param {'cron'|'startup'|'manual'} trigger - 'manual' window ko bypass karta hai
   */
  async recalculateScores(trigger = 'manual') {
    if (this.isRecalculating) {
      console.log('⚠️ Score recalculation already in progress, skipping...');
      return;
    }

    try {
      if (trigger !== 'manual' && !(await this._shouldRun(trigger))) return;
    } catch (error) {
      console.error('❌ Score recalculation gate check failed:', error.message);
      return;
    }

    this.isRecalculating = true;
    const startTime = Date.now();

    // Window ko run se PEHLE claim karo. Baad me karte to har crash agle boot pe
    // dobara poora sweep trigger kar deta — 4 boots/hour par ye loop ban jaata.
    this.lastRunAt = startTime;
    await redisService.set(LAST_RUN_KEY, String(startTime), { ex: LAST_RUN_TTL_SECONDS });

    try {
      console.log(`🔄 Score recalculation starting (trigger: ${trigger})`);

      // NOTE: onlyOutdated/maxAgeMinutes filhaal RecommendationService.recalculateAllScores
      // me implement nahi hain — wo sirf batchSize aur limit padhta hai. Yaani har run
      // poora sweep hai, incremental nahi. Intent yahan chhoda hai taaki wo fix hone par
      // ye call site sahi rahe.
      const stats = await RecommendationService.recalculateAllScores({
        batchSize: 100,
        onlyOutdated: true,
        maxAgeMinutes: INTERVAL_MS / 60000
      });

      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      console.log(`✅ Score recalculation completed in ${duration}s`);
      console.log(`📊 Video Stats: ${stats.processed} processed`);
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
