import AdCampaign from '../../models/AdCampaign.js';
import AdCreative from '../../models/AdCreative.js';
import walletService from './walletService.js';

/**
 * Closing a campaign and returning what it did not spend.
 *
 * A campaign's whole budget is debited from the wallet up front, at creation.
 * Everything that budget does not deliver has to come back, or the advertiser
 * has paid for impressions nobody served. There are three ways a campaign ends:
 *
 *   - it exhausts its budget      → nothing to return
 *   - it reaches its end date     → return the remainder  (expireEndedCampaigns)
 *   - it is rejected by an admin  → return the remainder  (rejectCreative)
 *
 * All three funnel through `settleCampaign` so there is one definition of
 * "closed and paid out", and one place where the double-refund guard lives.
 */

/** Refunds below one whole credit are dropped — the wallet is integral. */
const MIN_REFUNDABLE = 1;

/** How many ended campaigns one sweep will settle. Keeps a backlog bounded. */
const EXPIRY_BATCH_SIZE = 500;

/**
 * Close a campaign and return its unspent budget.
 *
 * Idempotent twice over, because refunding twice is minting money:
 *
 *  1. The status transition filters on `budgetRefundedAt: null`, so exactly one
 *     caller can claim a campaign — concurrent sweeps cannot both proceed.
 *  2. The refund carries `externalId: 'campaign_refund:<id>'`, so even if the
 *     claim flag were somehow cleared, the ledger's unique index rejects the
 *     second credit.
 *
 * If the refund itself fails, the claim is released so a later sweep retries.
 * Leaving it claimed would strand the advertiser's money with no retry path.
 *
 * @returns {{settled: boolean, refunded: number, campaign?: object}}
 *   `settled: false` means another caller had already closed it.
 */
export const settleCampaign = async (campaignId, { reason, status = 'completed' } = {}) => {
  // `{ budgetRefundedAt: null }` matches both null and missing, so campaigns
  // created before this field existed are still claimable.
  const campaign = await AdCampaign.findOneAndUpdate(
    { _id: campaignId, budgetRefundedAt: null },
    { $set: { budgetRefundedAt: new Date(), status } },
    { new: true }
  );

  if (!campaign) {
    return { settled: false, refunded: 0 };
  }

  const unspent = Math.floor((campaign.totalBudget || 0) - (campaign.spentINR || 0));
  if (unspent < MIN_REFUNDABLE) {
    return { settled: true, refunded: 0, campaign };
  }

  try {
    await walletService.refund({
      userId: campaign.advertiserUserId,
      amount: unspent,
      campaignId: campaign._id,
      reason: reason || 'campaign_settled',
      externalId: `campaign_refund:${campaign._id}`
    });

    console.log(`💸 campaignSettlement: refunded ${unspent} credits for campaign ${campaign._id} (${reason})`);
    return { settled: true, refunded: unspent, campaign };
  } catch (err) {
    // Release the claim so this campaign is picked up again. Safe to retry:
    // the externalId above makes a repeated refund a no-op.
    await AdCampaign.updateOne(
      { _id: campaign._id },
      { $set: { budgetRefundedAt: null } }
    ).catch((releaseErr) => {
      console.error('❌ CRITICAL: campaign settled but refund failed and claim could not be released', {
        campaignId: String(campaign._id),
        unspent,
        releaseError: releaseErr?.message
      });
    });

    throw err;
  }
};

/**
 * Close every campaign whose flight window has passed.
 *
 * Nothing else does this. The serving filter stops delivering past `endDate`,
 * but the campaign stays `active` with the advertiser's money inside it, so
 * without this sweep an ad that ends early simply keeps the budget. That is
 * the single most likely support ticket, hence a scheduled job rather than a
 * best-effort call somewhere on the request path.
 *
 * `paused` is included: a paused campaign past its end date is just as over as
 * an active one.
 */
export const expireEndedCampaigns = async () => {
  const ended = await AdCampaign.find({
    status: { $in: ['active', 'paused'] },
    endDate: { $lt: new Date() },
    budgetRefundedAt: null
  })
    .select('_id')
    .limit(EXPIRY_BATCH_SIZE)
    .lean();

  if (ended.length === 0) {
    return { examined: 0, settled: 0, refunded: 0, failed: 0 };
  }

  let settled = 0;
  let refunded = 0;
  let failed = 0;

  // Sequential on purpose: each iteration is a wallet write, and firing 500 of
  // them at once only adds contention on the advertisers' wallet documents.
  for (const { _id } of ended) {
    try {
      const result = await settleCampaign(_id, { reason: 'campaign_ended' });
      if (result.settled) {
        settled += 1;
        refunded += result.refunded;
      }
    } catch (err) {
      failed += 1;
      console.error(`⚠️ campaignSettlement: failed to settle campaign ${_id}: ${err.message}`);
    }
  }

  console.log(`📅 campaignSettlement: ${settled} campaign(s) closed, ${refunded} credits refunded, ${failed} failed`);
  return { examined: ended.length, settled, refunded, failed };
};

/**
 * Take a creative out of the feed and, if it was the last one running, close
 * and refund its campaign.
 *
 * The campaign is only settled once no other servable creative depends on it —
 * refunding a budget that a sibling creative is still spending would let the
 * campaign overdeliver against money the advertiser already got back.
 *
 * @returns {{creative: object, campaignSettled: boolean, refunded: number}}
 */
export const rejectCreative = async (creativeId, { reason }) => {
  const creative = await AdCreative.findById(creativeId);
  if (!creative) return null;

  creative.isActive = false;
  creative.reviewStatus = 'rejected';
  creative.rejectionReason = reason || 'Rejected by moderation';
  await creative.save();

  const siblingsStillRunning = await AdCreative.countDocuments({
    campaignId: creative.campaignId,
    _id: { $ne: creative._id },
    isActive: true,
    reviewStatus: 'approved'
  });

  if (siblingsStillRunning > 0) {
    return { creative, campaignSettled: false, refunded: 0 };
  }

  const { settled, refunded } = await settleCampaign(creative.campaignId, {
    reason: 'creative_rejected'
  });

  return { creative, campaignSettled: settled, refunded };
};

export default { settleCampaign, expireEndedCampaigns, rejectCreative };
