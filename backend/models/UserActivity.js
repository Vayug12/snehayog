import mongoose from 'mongoose';

/**
 * UserActivity Model
 * One document per user per day they used the app.
 *
 * Why this exists: User.lastActive only keeps the *latest* timestamp, so it can
 * answer "did this user ever come back" but never "how often" or "were they
 * active in week 2". Cohort retention, habit/frequency and activation metrics
 * all need the full set of active days, which is exactly what this stores.
 *
 * Deliberately minimal — one small doc per active user per day, written at most
 * once per user per day (see services/analytics/userActivityService.js).
 */

const ACTIVITY_TTL_DAYS = 400; // Keeps a full year of history for cohort analysis

const userActivitySchema = new mongoose.Schema({
  googleId: {
    type: String, // Matches User.googleId / WatchHistory.userId so cohorts can join
    required: true,
    index: true
  },
  date: {
    type: Date, // Always UTC midnight — see UserActivity.toUtcDay()
    required: true,
    expires: ACTIVITY_TTL_DAYS * 24 * 60 * 60 // TTL index doubles as the date-range index
  }
}, {
  timestamps: true
});

// One row per user per day; also the lookup index for per-user cohort joins
userActivitySchema.index({ googleId: 1, date: 1 }, { unique: true });

/**
 * Normalises any timestamp to UTC midnight so a "day" means the same thing
 * everywhere — writers, aggregations and the backfill script.
 */
userActivitySchema.statics.toUtcDay = function (value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
};

const UserActivity = mongoose.model('UserActivity', userActivitySchema);

export default UserActivity;
