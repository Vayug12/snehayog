/**
 * Recover ad-credit purchases whose webhook or wallet apply step was missed.
 * Safe to run at startup, on a schedule, or manually; every write is
 * idempotent on the store transaction ID.
 */
import mongoose from 'mongoose';
import dotenv from 'dotenv';
import AdCampaign from '../models/AdCampaign.js';
import AdCreative from '../models/AdCreative.js';
import AdCreditTransaction from '../models/AdCreditTransaction.js';
import walletService from '../services/adServices/walletService.js';
import {
  findReconciliationCandidates,
  syncRevenueCatPurchasesForUser
} from '../services/adServices/revenueCatPurchaseSyncService.js';

dotenv.config();

const dryRun = process.argv.includes('--dry-run');
const daysArg = process.argv.find((arg) => arg.startsWith('--days='));
const lookbackDays = daysArg ? Number(daysArg.split('=')[1]) : 7;
const graceMinutes = 5;

const stats = {
  applied: 0,
  refundsRepaired: 0,
  buyersChecked: 0,
  purchasesChecked: 0,
  recovered: 0,
  creditsRecovered: 0,
  failed: 0
};

const repairPendingCampaignRefunds = async () => {
  const cutoff = new Date(Date.now() - graceMinutes * 60 * 1000);
  const pendingSpends = await AdCreditTransaction.find({
    type: 'spend',
    source: 'campaign',
    'metadata.creationState': { $in: ['started', 'refund_pending'] },
    createdAt: { $lt: cutoff }
  }).sort({ createdAt: 1 }).limit(200);

  const campaignLookups = pendingSpends
    .filter((spend) => spend.metadata?.idempotencyKey)
    .map((spend) => ({
      advertiserUserId: spend.userId,
      idempotencyKey: spend.metadata.idempotencyKey
    }));
  const campaigns = campaignLookups.length > 0
    ? await AdCampaign.find({ $or: campaignLookups })
      .select('_id advertiserUserId idempotencyKey')
      .lean()
    : [];
  const creativeCampaignIds = campaigns.length > 0
    ? await AdCreative.distinct('campaignId', {
      campaignId: { $in: campaigns.map((campaign) => campaign._id) }
    })
    : [];
  const creativeCampaignIdSet = new Set(creativeCampaignIds.map(String));
  const completeCampaigns = campaigns.filter((campaign) => (
    creativeCampaignIdSet.has(String(campaign._id))
  ));
  const orphanCampaignIds = campaigns
    .filter((campaign) => !creativeCampaignIdSet.has(String(campaign._id)))
    .map((campaign) => campaign._id);
  if (!dryRun && orphanCampaignIds.length > 0) {
    await AdCampaign.deleteMany({ _id: { $in: orphanCampaignIds } });
  }

  const campaignByRequest = new Map(completeCampaigns.map((campaign) => [
    `${campaign.advertiserUserId}:${campaign.idempotencyKey}`,
    campaign
  ]));
  const ledgerUpdates = [];

  for (const spend of pendingSpends) {
    const campaign = campaignByRequest.get(
      `${spend.userId}:${spend.metadata?.idempotencyKey}`
    );
    if (campaign) {
      ledgerUpdates.push({
        updateOne: {
          filter: { _id: spend._id },
          update: {
            $set: {
              campaignId: campaign._id,
              'metadata.creationState': 'completed'
            }
          }
        }
      });
      continue;
    }

    if (dryRun) {
      stats.refundsRepaired += 1;
      continue;
    }

    try {
      await walletService.refund({
        userId: spend.userId,
        amount: spend.amount,
        reason: 'campaign_creation_failed',
        externalId: `campaign_create_rollback:${spend._id}`,
        metadata: {
          failedWith: spend.metadata?.creationError || 'campaign creation failed',
          originalSpendTransactionId: String(spend._id),
          repairedByReconciliation: true
        }
      });
      ledgerUpdates.push({
        updateOne: {
          filter: {
            _id: spend._id,
            'metadata.creationState': { $in: ['started', 'refund_pending'] }
          },
          update: { $set: { 'metadata.creationState': 'failed' } }
        }
      });
      stats.refundsRepaired += 1;
    } catch (error) {
      stats.failed += 1;
      console.error(`Campaign refund repair failed (${spend._id}): ${error.message}`);
    }
  }

  if (!dryRun && ledgerUpdates.length > 0) {
    await AdCreditTransaction.bulkWrite(ledgerUpdates, { ordered: false });
  }
};

const applyOrphanedRows = async () => {
  const cutoff = new Date(Date.now() - graceMinutes * 60 * 1000);
  const stale = await AdCreditTransaction.find({
    applied: false,
    createdAt: { $lt: cutoff }
  }).sort({ createdAt: 1 }).limit(200);

  for (const transaction of stale) {
    if (dryRun) {
      stats.applied += 1;
      continue;
    }

    try {
      const applied = await walletService.applyTransaction(transaction);
      if (applied?.$locals?.appliedNow) stats.applied += 1;
    } catch (error) {
      stats.failed += 1;
      console.error(`Ad-credit apply failed (${transaction._id}): ${error.message}`);
    }
  }
};

const recoverMissedPurchases = async (since, apiKey) => {
  const users = await findReconciliationCandidates(since);
  stats.buyersChecked = users.length;

  for (const user of users) {
    try {
      const result = await syncRevenueCatPurchasesForUser(user, {
        apiKey,
        since,
        dryRun
      });
      stats.purchasesChecked += result.checked;
      stats.recovered += result.recovered;
      stats.creditsRecovered += result.creditsRecovered;
    } catch (error) {
      stats.failed += 1;
      console.error(`RevenueCat sync failed (${user.googleId}): ${error.message}`);
    }
  }
};

const main = async () => {
  if (!Number.isFinite(lookbackDays) || lookbackDays <= 0) {
    throw new Error(`Invalid --days value: ${lookbackDays}`);
  }

  const uri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!uri) throw new Error('MONGO_URI is not set');

  await mongoose.connect(uri);
  await applyOrphanedRows();
  await repairPendingCampaignRefunds();

  const apiKey = process.env.REVENUECAT_API_KEY;
  if (!apiKey) {
    console.warn('REVENUECAT_API_KEY is not set; missed webhooks cannot be recovered.');
  } else {
    const since = new Date(Date.now() - lookbackDays * 24 * 60 * 60 * 1000);
    await recoverMissedPurchases(since, apiKey);
  }

  console.log('RevenueCat reconciliation summary', { ...stats, dryRun });
  await mongoose.disconnect();
  process.exit(stats.failed > 0 ? 1 : 0);
};

main().catch(async (error) => {
  console.error('RevenueCat reconciliation failed:', error);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
