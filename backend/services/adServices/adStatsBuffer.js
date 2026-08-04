import AdCreative from '../../models/AdCreative.js';
import AdCampaign from '../../models/AdCampaign.js';
import CreatorMonthlyStat from '../../models/CreatorMonthlyStat.js';
import { AD_CONFIG } from '../../constants/index.js';
import { settleCampaign } from './campaignSettlement.js';

/**
 * Batches ad counter increments so the impression hot path performs a single
 * Mongo write (the AdImpression insert) instead of three.
 *
 * AdCreative counters and CreatorMonthlyStat totals are pure $inc deltas, so
 * they are commutative and safe to accumulate in memory and flush periodically.
 * AdImpression rows stay synchronous — they remain the source of truth from
 * which these aggregates can be recomputed within the TTL window.
 */

const FLUSH_INTERVAL_MS = Number(process.env.AD_STATS_FLUSH_MS) || 5000;
const PENDING_WARN_THRESHOLD = Number(process.env.AD_STATS_PENDING_WARN) || 5000;

// adId -> { id, inc: { impressions, views, clicks } }
const creativeDeltas = new Map();
// `${creatorId}|${yearMonth}` -> { creatorId, yearMonth, inc: {...} }
const monthlyDeltas = new Map();
// adId -> rupees of advertiser spend awaiting attribution to its campaign
const spendDeltas = new Map();
// adId -> campaignId. A creative never changes campaign, so this is cached for
// the process lifetime and keeps the flush from re-reading AdCreative.
const campaignOfAd = new Map();

let flushTimer = null;
let flushing = false;
let stopped = false;

/** Current year-month in IST, matching the format CreatorMonthlyStat stores. */
export function istYearMonth(date = new Date()) {
  const ist = new Date(date.getTime() + 5.5 * 60 * 60 * 1000);
  return `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}`;
}

function accumulate(map, key, base, inc) {
  const existing = map.get(key);
  if (!existing) {
    map.set(key, { ...base, inc: { ...inc } });
    return;
  }
  for (const [field, amount] of Object.entries(inc)) {
    existing.inc[field] = (existing.inc[field] || 0) + amount;
  }
}

/** Rupees per 1000 delivered views for an ad type. */
function cpmFor(adType) {
  return adType === 'banner'
    ? (AD_CONFIG?.BANNER_CPM ?? 20)
    : (AD_CONFIG?.DEFAULT_CPM ?? 30);
}

function ensureTimer() {
  if (flushTimer || stopped) return;
  flushTimer = setInterval(() => {
    flush().catch((err) => console.error('⚠️ adStatsBuffer timer flush failed:', err?.message));
  }, FLUSH_INTERVAL_MS);
  // Never hold the process open just for the flush timer.
  if (typeof flushTimer.unref === 'function') flushTimer.unref();
}

/**
 * Queue an AdCreative counter increment.
 * @param {string} adId
 * @param {'impressions'|'views'|'clicks'} field
 * @param {number} amount
 */
export function recordCreativeCounter(adId, field, amount = 1) {
  if (!adId || !field || !Number.isFinite(amount) || amount === 0) return;
  accumulate(creativeDeltas, String(adId), { id: adId }, { [field]: amount });
  ensureTimer();
}

/**
 * Queue a creator revenue increment for the current IST month.
 * @param {string|object} creatorId
 * @param {'banner'|'carousel'} adType
 * @param {number} count
 */
export function recordCreatorEarning(creatorId, adType, count = 1) {
  if (!creatorId || !Number.isFinite(count) || count <= 0) return;
  if (adType !== 'banner' && adType !== 'carousel') return;

  const yearMonth = istYearMonth();
  const cpm = cpmFor(adType);

  const inc = {
    grossRevenue: (count / 1000) * cpm,
    [adType === 'banner' ? 'bannerImpressions' : 'carouselImpressions']: count,
  };

  accumulate(
    monthlyDeltas,
    `${creatorId}|${yearMonth}`,
    { creatorId, yearMonth },
    inc,
  );
  ensureTimer();
}

/**
 * Queue advertiser spend for a delivered view.
 *
 * Charged at the same CPM that credits the creator, so a campaign's spentINR
 * and the creator revenue it funded always move together. Attribution to the
 * campaign happens at flush time — the hot path stays free of extra reads.
 *
 * @param {string} adId Creative that was shown
 * @param {'banner'|'carousel'} adType
 * @param {number} count Delivered views
 */
export function recordCampaignSpend(adId, adType, count = 1) {
  if (!adId || !Number.isFinite(count) || count <= 0) return;
  if (adType !== 'banner' && adType !== 'carousel') return;

  const key = String(adId);
  const amount = (count / 1000) * cpmFor(adType);
  spendDeltas.set(key, (spendDeltas.get(key) || 0) + amount);
  ensureTimer();
}

/**
 * Resolve creative -> campaign for any ad ids not already cached.
 * One query per flush at most, and only for creatives seen for the first time.
 */
async function resolveCampaignIds(adIds) {
  const unknown = adIds.filter((id) => !campaignOfAd.has(id));
  if (unknown.length === 0) return;

  const creatives = await AdCreative.find({ _id: { $in: unknown } })
    .select('campaignId')
    .lean();

  for (const creative of creatives) {
    if (creative.campaignId) {
      campaignOfAd.set(String(creative._id), String(creative.campaignId));
    }
  }
}

/**
 * Apply buffered spend to campaigns, then retire any campaign whose budget is
 * now exhausted. The serving path also filters on budget, so this is the
 * durable half of the guard rather than the only one.
 */
async function flushSpend(batch) {
  const adIds = [...batch.keys()];
  await resolveCampaignIds(adIds);

  // Fold per-creative spend up to per-campaign totals.
  const perCampaign = new Map();
  for (const [adId, amount] of batch) {
    const campaignId = campaignOfAd.get(adId);
    if (!campaignId) continue; // Creative deleted — spend has nowhere to land.
    perCampaign.set(campaignId, (perCampaign.get(campaignId) || 0) + amount);
  }
  if (perCampaign.size === 0) return;

  await AdCampaign.bulkWrite(
    [...perCampaign].map(([id, amount]) => ({
      updateOne: { filter: { _id: id }, update: { $inc: { spentINR: amount } } },
    })),
    { ordered: false },
  );

  const exhausted = await AdCampaign.find({
    _id: { $in: [...perCampaign.keys()] },
    status: 'active',
    $expr: { $gte: [{ $ifNull: ['$spentINR', 0] }, { $ifNull: ['$totalBudget', 0] }] },
  })
    .select('_id')
    .lean();

  if (exhausted.length === 0) return;

  // Closed through the settlement path rather than a bare status update, so
  // every completed campaign reaches the same end state regardless of how it
  // ended. A campaign that hit its budget has nothing left to refund, but
  // routing it here keeps "completed" and "settled" from drifting apart.
  for (const { _id } of exhausted) {
    try {
      await settleCampaign(_id, { reason: 'budget_exhausted' });
    } catch (err) {
      console.error(`⚠️ adStatsBuffer: failed to settle exhausted campaign ${_id}: ${err.message}`);
    }
  }

  console.log(`💰 adStatsBuffer: ${exhausted.length} campaign(s) hit budget and were completed`);
}

/**
 * Write all buffered deltas. Failed batches are merged back so no counts are
 * lost — the next flush retries them.
 */
export async function flush() {
  if (flushing) return;
  if (creativeDeltas.size === 0 && monthlyDeltas.size === 0 && spendDeltas.size === 0) return;

  flushing = true;
  const creativeBatch = [...creativeDeltas.values()];
  const monthlyBatch = [...monthlyDeltas.values()];
  const spendBatch = new Map(spendDeltas);
  creativeDeltas.clear();
  monthlyDeltas.clear();
  spendDeltas.clear();

  try {
    const writes = [];

    if (creativeBatch.length > 0) {
      writes.push(AdCreative.bulkWrite(
        creativeBatch.map(({ id, inc }) => ({
          updateOne: { filter: { _id: id }, update: { $inc: inc } },
        })),
        { ordered: false },
      ));
    }

    if (monthlyBatch.length > 0) {
      writes.push(CreatorMonthlyStat.bulkWrite(
        monthlyBatch.map(({ creatorId, yearMonth, inc }) => ({
          updateOne: {
            filter: { creatorId, yearMonth },
            update: { $inc: inc },
            upsert: true,
          },
        })),
        { ordered: false },
      ));
    }

    if (spendBatch.size > 0) {
      writes.push(flushSpend(spendBatch));
    }

    await Promise.all(writes);
  } catch (error) {
    // Re-queue so the deltas survive a transient Mongo failure or an upsert
    // duplicate-key race between machines.
    for (const entry of creativeBatch) {
      accumulate(creativeDeltas, String(entry.id), { id: entry.id }, entry.inc);
    }
    for (const entry of monthlyBatch) {
      accumulate(
        monthlyDeltas,
        `${entry.creatorId}|${entry.yearMonth}`,
        { creatorId: entry.creatorId, yearMonth: entry.yearMonth },
        entry.inc,
      );
    }
    for (const [adId, amount] of spendBatch) {
      spendDeltas.set(adId, (spendDeltas.get(adId) || 0) + amount);
    }

    const pending = creativeDeltas.size + monthlyDeltas.size + spendDeltas.size;
    console.error(`⚠️ adStatsBuffer flush failed (${pending} pending, re-queued):`, error?.message);
    if (pending > PENDING_WARN_THRESHOLD) {
      console.error(`🚨 adStatsBuffer backlog above ${PENDING_WARN_THRESHOLD} — Mongo writes may be failing persistently`);
    }
  } finally {
    flushing = false;
  }
}

/**
 * Stop the timer and drain the buffer. Must run before the process exits —
 * Fly auto-stops idle machines, so an unflushed buffer means lost revenue.
 */
export async function shutdownAdStatsBuffer() {
  stopped = true;
  if (flushTimer) {
    clearInterval(flushTimer);
    flushTimer = null;
  }

  // Let an in-flight flush finish (max ~5s) before draining the remainder.
  for (let i = 0; i < 50 && flushing; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  await flush();
}

export function getPendingCount() {
  return {
    creatives: creativeDeltas.size,
    monthlyStats: monthlyDeltas.size,
    campaignSpend: spendDeltas.size,
  };
}
