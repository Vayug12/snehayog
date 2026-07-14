/**
 * Centralized API Rate Limiter for Free-Tier Providers
 * 
 * Enforces per-provider rate limits to stay within free-tier quotas:
 * - Gemini (chat/embedding): 2 RPM → 30s min interval, 1000/day
 * - Groq Whisper (transcription): 180 RPM → 350ms min interval, 7000/day
 * 
 * Usage:
 *   await apiRateLimiter.wait('gemini');
 *   const { allowed, retryAfter } = apiRateLimiter.canProceed('gemini');
 */

class APIRateLimiter {
  constructor() {
    // Per-provider state: { lastCall, dailyCount, dailyResetTime }
    this.providers = {
      gemini: {
        minIntervalMs: 30000,    // 2 RPM = 30s between calls
        dailyLimit: 1000,
        dailyCount: 0,
        dailyResetTime: this._getNextMidnightUTC(),
        lastCall: 0,
        waiting: false,
        waitQueue: []
      },
      groq: {
        minIntervalMs: 350,      // 180 RPM ≈ 333ms, use 350ms for safety
        dailyLimit: 7000,
        dailyCount: 0,
        dailyResetTime: this._getNextMidnightUTC(),
        lastCall: 0,
        waiting: false,
        waitQueue: []
      }
    };

    // Reset counters at midnight UTC
    this._scheduleMidnightReset();
  }

  _getNextMidnightUTC() {
    const now = new Date();
    const midnight = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate() + 1,
      0, 0, 0, 0
    ));
    return midnight.getTime();
  }

  _scheduleMidnightReset() {
    const now = Date.now();
    const msUntilMidnight = this._getNextMidnightUTC() - now;

    setTimeout(() => {
      this._resetDailyCounts();
      this._scheduleMidnightReset(); // Schedule next reset
    }, msUntilMidnight);
  }

  _resetDailyCounts() {
    for (const [name, provider] of Object.entries(this.providers)) {
      provider.dailyCount = 0;
      provider.dailyResetTime = this._getNextMidnightUTC();
      console.log(`🔄 APIRateLimiter: Reset daily counter for ${name}`);
    }
  }

  /**
   * Check if a call is allowed without blocking
   */
  canProceed(provider) {
    const p = this.providers[provider];
    if (!p) return { allowed: false, retryAfter: 0, dailyRemaining: 0 };

    const now = Date.now();
    const timeSinceLastCall = now - p.lastCall;
    const dailyRemaining = Math.max(0, p.dailyLimit - p.dailyCount);

    if (dailyRemaining <= 0) {
      const msUntilReset = p.dailyResetTime - now;
      return {
        allowed: false,
        retryAfter: Math.ceil(msUntilReset / 1000),
        dailyRemaining: 0,
        reason: 'daily_quota_exhausted'
      };
    }

    if (timeSinceLastCall < p.minIntervalMs) {
      return {
        allowed: false,
        retryAfter: Math.ceil((p.minIntervalMs - timeSinceLastCall) / 1000),
        dailyRemaining,
        reason: 'rate_limit'
      };
    }

    return { allowed: true, retryAfter: 0, dailyRemaining };
  }

  /**
   * Wait until a call can be made. Returns immediately if allowed, 
   * otherwise waits the required interval.
   * @returns {{ allowed: boolean, dailyRemaining: number }}
   */
  async wait(provider) {
    const p = this.providers[provider];
    if (!p) return { allowed: false, dailyRemaining: 0 };

    // Check daily quota
    if (p.dailyCount >= p.dailyLimit) {
      const msUntilReset = p.dailyResetTime - Date.now();
      console.warn(`⏳ APIRateLimiter: ${provider} daily quota exhausted (${p.dailyCount}/${p.dailyLimit}). Resets in ${Math.ceil(msUntilReset / 60000)}min`);
      return { allowed: false, dailyRemaining: 0 };
    }

    // Wait for interval if needed
    const timeSinceLastCall = Date.now() - p.lastCall;
    if (timeSinceLastCall < p.minIntervalMs) {
      const waitMs = p.minIntervalMs - timeSinceLastCall;
      console.log(`⏳ APIRateLimiter: Waiting ${waitMs}ms for ${provider} rate limit...`);
      await new Promise(resolve => setTimeout(resolve, waitMs));
    }

    // Record call
    p.lastCall = Date.now();
    p.dailyCount++;

    const dailyRemaining = p.dailyLimit - p.dailyCount;
    if (dailyRemaining <= 10) {
      console.warn(`⚠️ APIRateLimiter: ${provider} running low — ${dailyRemaining} requests remaining today`);
    }

    return { allowed: true, dailyRemaining };
  }

  /**
   * Get current stats for monitoring
   */
  getStats() {
    const stats = {};
    for (const [name, p] of Object.entries(this.providers)) {
      stats[name] = {
        dailyCount: p.dailyCount,
        dailyLimit: p.dailyLimit,
        dailyRemaining: Math.max(0, p.dailyLimit - p.dailyCount),
        lastCallAgo: p.lastCall ? Math.round((Date.now() - p.lastCall) / 1000) + 's' : 'never',
        resetsAt: new Date(p.dailyResetTime).toISOString()
      };
    }
    return stats;
  }

  /**
   * Manually reset (for testing or forced reset)
   */
  reset() {
    this._resetDailyCounts();
  }
}

export default new APIRateLimiter();
