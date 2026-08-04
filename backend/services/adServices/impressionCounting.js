/**
 * Single definition of what a row in `adimpressions` counts as.
 *
 * A delivered ad writes **two** rows, not one:
 *
 *   1. `POST /impressions/:type`      — the ad rendered.       `isViewed: false`
 *   2. `POST /impressions/:type/view` — it survived 2 seconds. `isViewed: true`
 *
 * Both are real events worth keeping, but it means a bare
 * `countDocuments({ adType })` returns roughly twice the number of ads actually
 * shown. Every count therefore has to declare which of the two it means, and
 * has to declare it the same way: an advertiser reading "impressions" and a
 * creator reading "views" are looking at one collection from opposite ends, and
 * those two numbers have to reconcile or someone is being quoted a number
 * nobody can back up.
 *
 * `impressionType` is **not** a substitute for these filters. It records the
 * placement — `'view'` for banner, `'scroll_view'` for carousel — not the
 * stage, and it carries the same value on both rows. Filtering a count by
 * `impressionType: 'view'` therefore matches both stages of a banner and
 * neither stage of a carousel.
 */

/**
 * The ad was put on screen. This is reach — what "impressions" means to an
 * advertiser, and the denominator of CTR.
 *
 * `$ne: true` rather than `false` so rows written before `isViewed` existed
 * still count as rendered instead of silently vanishing from reach.
 */
export const renderedMatch = () => ({ isViewed: { $ne: true } });

/**
 * The ad was visible long enough to bill for. The only count money may be
 * derived from — creator earnings, campaign spend, and platform revenue all
 * resolve to this row and no other.
 */
export const billableMatch = () => ({ isViewed: true });

/**
 * The same two definitions as `$group` accumulators.
 *
 * A pipeline that needs reach *and* views in one pass cannot `$match` for
 * either, so it has to branch per row instead. These exist so that branch is
 * written once: an aggregation that hand-rolls its own `$cond` is free to drift
 * from the matchers above, and a reach number that disagrees with the reach
 * number on the next screen is worse than no number at all.
 */
export const renderedSum = () => ({ $sum: { $cond: [{ $eq: ['$isViewed', true] }, 0, 1] } });

export const billableSum = () => ({ $sum: { $cond: [{ $eq: ['$isViewed', true] }, 1, 0] } });

export default { renderedMatch, billableMatch, renderedSum, billableSum };
