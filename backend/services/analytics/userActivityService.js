import UserActivity from '../../models/UserActivity.js';

/**
 * Write path for the daily active-user log.
 *
 * Cost control: this runs on every authenticated API request, so an unguarded
 * upsert would add one DB round trip per request. Instead each process keeps
 * the set of users it has already recorded for the current UTC day and skips
 * the write entirely after the first hit — at most one write per user per day
 * per process, and nothing at all for the rest of their session.
 *
 * The set is rebuilt when the day rolls over, so it stays bounded by daily
 * active users rather than growing forever.
 */

const DUPLICATE_KEY_ERROR = 11000;

let memoDayKey = null;
let recordedToday = new Set();

function alreadyRecorded(googleId, dayKey) {
  if (dayKey !== memoDayKey) {
    // New UTC day (or first call): drop yesterday's memo
    memoDayKey = dayKey;
    recordedToday = new Set();
    return false;
  }
  return recordedToday.has(googleId);
}

/**
 * Records that a user was active today. Idempotent and safe to call on every
 * request — never throws, so callers can fire and forget.
 *
 * @param {String} googleId - User.googleId of the authenticated user
 * @param {Date} [when] - Activity timestamp, defaults to now
 */
export async function recordDailyActive(googleId, when = new Date()) {
  if (!googleId) return;

  const day = UserActivity.toUtcDay(when);
  const dayKey = day.getTime();

  if (alreadyRecorded(googleId, dayKey)) return;

  // Marked before the await so concurrent requests in the same tick collapse
  // into a single write instead of racing.
  recordedToday.add(googleId);

  try {
    await UserActivity.updateOne(
      { googleId, date: day },
      { $setOnInsert: { googleId, date: day } },
      { upsert: true }
    );
  } catch (error) {
    // Another process inserted the same day first — that is the desired state
    if (error?.code === DUPLICATE_KEY_ERROR) return;

    // Anything else: forget the memo so the next request retries
    recordedToday.delete(googleId);
    console.log('⚠️ Failed to record daily activity:', error.message);
  }
}

export default { recordDailyActive };
