import User from '../../models/User.js';
import UserActivity from '../../models/UserActivity.js';

/**
 * Retention, habit and activation analytics for the admin dashboard.
 *
 * Everything here reads the UserActivity day log rather than User.lastActive.
 * lastActive only holds the newest timestamp, which can answer "did they ever
 * come back" but not "were they active in week 2" or "how often do they open
 * the app" — the two questions that actually indicate whether users like the
 * product.
 *
 * Three metrics, deliberately no more:
 *   1. Cohort retention  — does the retention curve flatten (product-market fit)
 *   2. Habit             — distribution of active days + DAU/MAU stickiness
 *   3. Activation        — which day-0 behaviour predicts week-1 retention
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const BIG_UPPER_BOUND = 1e9; // $bucket needs a finite top boundary

/**
 * Weekly windows instead of exact D1/D7/D30: on a small user base a single-day
 * bucket swings wildly on a handful of users, while a 7-day window keeps the
 * shape of the curve without the noise.
 */
const RETENTION_WINDOWS = [
  { key: 'week1', label: 'Week 1', fromDay: 1, toDay: 7 },
  { key: 'week2', label: 'Week 2', fromDay: 8, toDay: 14 },
  { key: 'week4', label: 'Week 4', fromDay: 22, toDay: 28 }
];
const ACTIVATION_WINDOW = RETENTION_WINDOWS[0]; // Activation is judged on week-1 retention

const DAILY_COHORT_DAYS = 31;
const MONTHLY_COHORT_MONTHS = 12;

const HABIT_WINDOW_DAYS = 28;
const HABIT_BUCKETS = [
  { min: 1, label: '1 day' },
  { min: 2, label: '2-3 days' },
  { min: 4, label: '4-7 days' },
  { min: 8, label: '8-14 days' },
  { min: 15, label: '15-28 days' }
];

// WatchHistory has a 90-day TTL, so day-0 watch counts older than that are
// already partially deleted. 60 days keeps the sample honest.
const ACTIVATION_LOOKBACK_DAYS = 60;
const ACTIVATION_BUCKETS = [
  { min: 0, label: 'No videos' },
  { min: 1, label: '1-9 videos' },
  { min: 10, label: '10-24 videos' },
  { min: 25, label: '25-49 videos' },
  { min: 50, label: '50+ videos' }
];
const MIN_ACTIVATION_SAMPLE = 20; // Below this a bucket's rate is noise, not signal

const EMPTY_ANALYTICS = {
  hasActivityData: false,
  cohorts: { unit: 'month', rows: [], totals: {} },
  curve: [],
  habit: { windowDays: HABIT_WINDOW_DAYS, buckets: [], stickiness: { dau: 0, wau: 0, mau: 0, dauOverMau: 0 } },
  activation: { windowLabel: ACTIVATION_WINDOW.label, lookbackDays: ACTIVATION_LOOKBACK_DAYS, buckets: [], insight: null }
};

const rate = (part, total) => (total > 0 ? (part / total) * 100 : 0);
const boundariesOf = (buckets) => [...buckets.map(b => b.min), BIG_UPPER_BOUND];
const labelOfBucket = (buckets, id) => buckets.find(b => b.min === id)?.label || String(id);

/** Truncates a date expression to UTC midnight, matching UserActivity.date. */
const utcDayExpr = (dateField) => ({
  $dateFromString: { dateString: { $dateToString: { format: '%Y-%m-%d', date: dateField } } }
});

/** True when the user has at least one active day inside [fromDay, toDay]. */
const retainedInWindow = (offsetsField, { fromDay, toDay }) => ({
  $gt: [
    {
      $size: {
        $filter: {
          input: offsetsField,
          as: 'offset',
          cond: { $and: [{ $gte: ['$$offset', fromDay] }, { $lte: ['$$offset', toDay] }] }
        }
      }
    },
    0
  ]
});

/**
 * Last calendar day covered by a cohort key ('2026-08-18' or '2026-08').
 * Used for maturity: a cohort is only comparable once its *newest* member has
 * had the full window to come back.
 */
function cohortEndDate(cohortKey, isDaily) {
  const [year, month, day] = cohortKey.split('-').map(Number);
  return isDaily
    ? new Date(Date.UTC(year, month - 1, day))
    : new Date(Date.UTC(year, month, 0)); // Day 0 of next month === last day of this one
}

function cohortWindowStart(isDaily, now) {
  return isDaily
    ? new Date(now.getTime() - DAILY_COHORT_DAYS * DAY_MS)
    : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (MONTHLY_COHORT_MONTHS - 1), 1));
}

/**
 * Signup cohorts with real week-by-week retention, read from the activity log.
 */
async function aggregateCohorts(isDaily, now) {
  const retainedCounters = Object.fromEntries(
    RETENTION_WINDOWS.map(w => [w.key, { $sum: { $cond: [retainedInWindow('$dayOffsets', w), 1, 0] } }])
  );

  const rows = await User.aggregate([
    {
      $match: {
        googleId: { $exists: true, $ne: null },
        createdAt: { $gte: cohortWindowStart(isDaily, now) }
      }
    },
    {
      $project: {
        googleId: 1,
        cohort: { $dateToString: { format: isDaily ? '%Y-%m-%d' : '%Y-%m', date: '$createdAt' } },
        signupDay: utcDayExpr('$createdAt')
      }
    },
    {
      $lookup: {
        from: 'useractivities',
        localField: 'googleId',
        foreignField: 'googleId',
        as: 'activity'
      }
    },
    {
      $addFields: {
        // Whole days between signup and each active day
        dayOffsets: {
          $map: {
            input: '$activity',
            as: 'entry',
            in: { $floor: { $divide: [{ $subtract: ['$$entry.date', '$signupDay'] }, DAY_MS] } }
          }
        }
      }
    },
    { $group: { _id: '$cohort', newUsers: { $sum: 1 }, ...retainedCounters } },
    { $sort: { _id: 1 } }
  ]);

  return rows.map(row => {
    const cohortEnd = cohortEndDate(row._id, isDaily);
    const windows = {};

    RETENTION_WINDOWS.forEach(w => {
      const retained = row[w.key] || 0;
      // Mature only once every member of the cohort has lived through the window
      const isMature = now.getTime() >= cohortEnd.getTime() + (w.toDay + 1) * DAY_MS;
      windows[w.key] = { retained, rate: rate(retained, row.newUsers), isMature };
    });

    return { period: row._id, newUsers: row.newUsers, windows };
  });
}

/**
 * Headline rates, averaged over mature cohorts only — immature cohorts would
 * otherwise drag every number toward zero purely because time has not passed.
 */
function summariseCohorts(rows) {
  const totals = { newUsers: rows.reduce((sum, r) => sum + r.newUsers, 0), windows: {} };

  RETENTION_WINDOWS.forEach(w => {
    const mature = rows.filter(r => r.windows[w.key].isMature);
    const base = mature.reduce((sum, r) => sum + r.newUsers, 0);
    const retained = mature.reduce((sum, r) => sum + r.windows[w.key].retained, 0);

    totals.windows[w.key] = {
      label: w.label,
      retained,
      base,
      rate: rate(retained, base),
      matureCohorts: mature.length
    };
  });

  return totals;
}

/**
 * Habit: how many distinct days each user opened the app in the last 28 days,
 * as a distribution rather than an average (averages hide the split between a
 * few power users and a long tail of one-time visitors), plus DAU/WAU/MAU.
 */
async function aggregateHabit(now) {
  const windowStart = UserActivity.toUtcDay(new Date(now.getTime() - HABIT_WINDOW_DAYS * DAY_MS));
  const weekStart = UserActivity.toUtcDay(new Date(now.getTime() - 7 * DAY_MS));
  const todayStart = UserActivity.toUtcDay(now);

  const [result] = await UserActivity.aggregate([
    { $match: { date: { $gte: windowStart } } },
    { $group: { _id: '$googleId', activeDays: { $sum: 1 }, lastSeen: { $max: '$date' } } },
    {
      $facet: {
        distribution: [
          {
            $bucket: {
              groupBy: '$activeDays',
              boundaries: boundariesOf(HABIT_BUCKETS),
              default: 'other',
              output: { users: { $sum: 1 } }
            }
          }
        ],
        stickiness: [
          {
            $group: {
              _id: null,
              mau: { $sum: 1 },
              wau: { $sum: { $cond: [{ $gte: ['$lastSeen', weekStart] }, 1, 0] } },
              dau: { $sum: { $cond: [{ $gte: ['$lastSeen', todayStart] }, 1, 0] } }
            }
          }
        ]
      }
    }
  ]);

  const distribution = result?.distribution || [];
  const totalUsers = distribution.reduce((sum, b) => sum + b.users, 0);
  const { dau = 0, wau = 0, mau = 0 } = result?.stickiness?.[0] || {};

  return {
    windowDays: HABIT_WINDOW_DAYS,
    // Keep every bucket, including empty ones, so the chart shape stays stable
    buckets: HABIT_BUCKETS.map(bucket => {
      const match = distribution.find(b => b._id === bucket.min);
      const users = match?.users || 0;
      return { label: bucket.label, users, share: rate(users, totalUsers) };
    }),
    stickiness: { dau, wau, mau, dauOverMau: rate(dau, mau) }
  };
}

/**
 * Activation: how many videos a user watched in their first 24 hours versus
 * whether they came back in week 1. This is the one metric here that can be
 * moved *this week* — onboarding and cold-start feed quality both feed it.
 */
async function aggregateActivation(now) {
  const cohortStart = new Date(now.getTime() - ACTIVATION_LOOKBACK_DAYS * DAY_MS);
  // Only users who have already had the full week-1 window to return
  const cohortEnd = new Date(now.getTime() - (ACTIVATION_WINDOW.toDay + 1) * DAY_MS);

  if (cohortEnd <= cohortStart) {
    return { windowLabel: ACTIVATION_WINDOW.label, lookbackDays: ACTIVATION_LOOKBACK_DAYS, buckets: [], insight: null };
  }

  const rows = await User.aggregate([
    {
      $match: {
        googleId: { $exists: true, $ne: null },
        createdAt: { $gte: cohortStart, $lte: cohortEnd }
      }
    },
    { $project: { googleId: 1, createdAt: 1, signupDay: utcDayExpr('$createdAt') } },
    {
      $lookup: {
        from: 'watchhistories',
        let: { gid: '$googleId', from: '$createdAt', to: { $add: ['$createdAt', DAY_MS] } },
        pipeline: [
          {
            $match: {
              $expr: {
                $and: [
                  { $eq: ['$userId', '$$gid'] },
                  { $gte: ['$watchedAt', '$$from'] },
                  { $lt: ['$watchedAt', '$$to'] }
                ]
              }
            }
          },
          { $count: 'videos' }
        ],
        as: 'firstDay'
      }
    },
    {
      $lookup: {
        from: 'useractivities',
        let: {
          gid: '$googleId',
          from: { $add: ['$signupDay', ACTIVATION_WINDOW.fromDay * DAY_MS] },
          to: { $add: ['$signupDay', (ACTIVATION_WINDOW.toDay + 1) * DAY_MS] }
        },
        pipeline: [
          {
            $match: {
              $expr: {
                $and: [
                  { $eq: ['$googleId', '$$gid'] },
                  { $gte: ['$date', '$$from'] },
                  { $lt: ['$date', '$$to'] }
                ]
              }
            }
          },
          { $limit: 1 }
        ],
        as: 'returnWindow'
      }
    },
    {
      $addFields: {
        day0Videos: { $ifNull: [{ $arrayElemAt: ['$firstDay.videos', 0] }, 0] },
        returned: { $gt: [{ $size: '$returnWindow' }, 0] }
      }
    },
    {
      $bucket: {
        groupBy: '$day0Videos',
        boundaries: boundariesOf(ACTIVATION_BUCKETS),
        default: 'other',
        output: { users: { $sum: 1 }, returned: { $sum: { $cond: ['$returned', 1, 0] } } }
      }
    }
  ]);

  const buckets = ACTIVATION_BUCKETS.map(bucket => {
    const match = rows.find(r => r._id === bucket.min);
    const users = match?.users || 0;
    const returned = match?.returned || 0;
    return { label: bucket.label, users, returned, rate: rate(returned, users) };
  });

  return {
    windowLabel: ACTIVATION_WINDOW.label,
    lookbackDays: ACTIVATION_LOOKBACK_DAYS,
    buckets,
    insight: buildActivationInsight(buckets)
  };
}

/**
 * Only claims a pattern when both ends of the comparison have a real sample —
 * a 100% bucket built on three users is noise, and acting on it is worse than
 * having no insight at all.
 */
function buildActivationInsight(buckets) {
  const usable = buckets.filter(b => b.users >= MIN_ACTIVATION_SAMPLE);
  if (usable.length < 2) return null;

  const baseline = usable[0];
  const best = usable[usable.length - 1];
  if (baseline.rate <= 0 || best.rate <= baseline.rate) return null;

  return {
    baselineLabel: baseline.label,
    baselineRate: baseline.rate,
    bestLabel: best.label,
    bestRate: best.rate,
    lift: best.rate / baseline.rate
  };
}

/**
 * Single entry point for the admin dashboard.
 *
 * @param {Object} options
 * @param {String} options.range - 'month' => daily cohorts, otherwise monthly
 * @returns {Promise<Object>} Never throws — returns an empty payload on failure
 *                            so one slow aggregation cannot break the dashboard.
 */
export async function getRetentionAnalytics({ range = 'all' } = {}) {
  const isDaily = range === 'month';
  const now = new Date();

  try {
    // The activity log only starts filling once tracking is deployed (or the
    // backfill script runs). Without this the UI would show a confident 0%.
    const activityCount = await UserActivity.estimatedDocumentCount();

    const [cohortRows, habit, activation] = await Promise.all([
      aggregateCohorts(isDaily, now),
      activityCount > 0 ? aggregateHabit(now) : Promise.resolve(EMPTY_ANALYTICS.habit),
      activityCount > 0 ? aggregateActivation(now) : Promise.resolve(EMPTY_ANALYTICS.activation)
    ]);

    const totals = summariseCohorts(cohortRows);

    return {
      hasActivityData: activityCount > 0,
      cohorts: { unit: isDaily ? 'day' : 'month', rows: cohortRows, totals },
      curve: [
        { label: 'Day 0', rate: 100, base: totals.newUsers },
        ...RETENTION_WINDOWS.map(w => ({
          label: w.label,
          rate: totals.windows[w.key].rate,
          base: totals.windows[w.key].base
        }))
      ],
      habit,
      activation
    };
  } catch (error) {
    console.error('❌ Retention analytics failed:', error);
    return { ...EMPTY_ANALYTICS, cohorts: { ...EMPTY_ANALYTICS.cohorts, unit: isDaily ? 'day' : 'month' } };
  }
}

export default { getRetentionAnalytics };
