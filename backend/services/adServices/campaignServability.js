/**
 * Single definition of "this campaign may still be served".
 *
 * A campaign is servable while it is active, inside its flight dates, and has
 * budget left. Spend is accrued per delivered view by adStatsBuffer, which also
 * completes campaigns once they are exhausted — this filter is the real-time
 * half of that guard, closing the window between flushes.
 *
 * Every ad-serving path must use one of these helpers. A path that queries
 * AdCreative directly without them serves ads the advertiser never paid for.
 */

/**
 * Budget predicate, shared by both query shapes.
 *
 * A missing totalBudget is treated as zero rather than unlimited, so a campaign
 * that was never funded is excluded instead of being served for free.
 */
const withinBudget = (spentField, budgetField) => ({
  $lt: [
    { $ifNull: [spentField, 0] },
    { $ifNull: [budgetField, 0] }
  ]
});

/**
 * Match fragment for querying the AdCampaign collection directly — use in
 * `.populate({ path: 'campaignId', match: servableCampaignMatch() })`.
 */
export const servableCampaignMatch = () => ({
  status: 'active',
  startDate: { $lte: new Date() },
  endDate: { $gte: new Date() },
  $expr: withinBudget('$spentINR', '$totalBudget')
});

/**
 * Aggregation `$match` stage for pipelines that `$lookup` the campaign into a
 * field (default `campaign`) and `$unwind` it.
 */
export const servableCampaignStage = (as = 'campaign') => ({
  $match: {
    [`${as}.status`]: 'active',
    [`${as}.startDate`]: { $lte: new Date() },
    [`${as}.endDate`]: { $gte: new Date() },
    $expr: withinBudget(`$${as}.spentINR`, `$${as}.totalBudget`)
  }
});

/**
 * In-memory guard for paths that already hold populated campaign documents.
 * @param {object|null} campaign
 * @returns {boolean}
 */
export const isCampaignServable = (campaign) => {
  if (!campaign) return false;
  const now = Date.now();
  if (campaign.status !== 'active') return false;
  if (campaign.startDate && new Date(campaign.startDate).getTime() > now) return false;
  if (campaign.endDate && new Date(campaign.endDate).getTime() < now) return false;
  return (campaign.spentINR || 0) < (campaign.totalBudget || 0);
};
