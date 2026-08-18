import { recordDailyActive } from '../services/analytics/userActivityService.js';

/**
 * Records one "active day" per authenticated user for retention analytics.
 *
 * Mounted globally after passiveVerifyToken so it sees every authenticated
 * request regardless of route. The write itself is memoised per user per day
 * inside the service, so this costs nothing after a user's first request of
 * the day.
 *
 * Never blocks or fails a request — analytics must not affect app traffic.
 */
export const activityTracking = (req, res, next) => {
  const googleId = req.user?.googleId || req.user?.id;

  if (googleId) {
    recordDailyActive(googleId).catch(() => {}); // Fire and forget
  }

  next();
};

export default activityTracking;
