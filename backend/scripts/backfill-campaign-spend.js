/**
 * One-time migration: populate AdCampaign.spentINR from delivered views, and
 * report campaigns that the new budget gate will stop serving.
 *
 * Why this is needed: ad serving now refuses to deliver a campaign once
 * spentINR reaches totalBudget. Existing campaigns have no spentINR, so
 * without this they would restart from zero spend and over-deliver by however
 * much they had already served.
 *
 * Spend is reconstructed from AdCreative.views at the same CPM adStatsBuffer
 * charges live, so backfilled and future spend use one rule.
 *
 * The gate treats a missing totalBudget as zero — an unfunded campaign is
 * excluded rather than served for free. That is deliberate, but it means any
 * campaign without a budget goes dark, so this script lists them explicitly.
 *
 * Usage:
 *   node scripts/backfill-campaign-spend.js            # apply
 *   node scripts/backfill-campaign-spend.js --dry-run  # report only
 *
 * Safe to re-run: spentINR is recomputed from views, not incremented.
 */

import mongoose from 'mongoose';
import dotenv from 'dotenv';
import AdCreative from '../models/AdCreative.js';
import AdCampaign from '../models/AdCampaign.js';
import { AD_CONFIG } from '../constants/index.js';

dotenv.config();

const DRY_RUN = process.argv.includes('--dry-run');

const cpmFor = (adType) => (adType === 'banner'
  ? (AD_CONFIG?.BANNER_CPM ?? 20)
  : (AD_CONFIG?.DEFAULT_CPM ?? 30));

async function main() {
  const uri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!uri) {
    console.error('❌ MONGO_URI is not set');
    process.exit(1);
  }

  await mongoose.connect(uri);
  console.log(`📋 Backfilling AdCampaign.spentINR${DRY_RUN ? ' (dry run)' : ''}\n`);

  // Sum delivered views per campaign, priced by the creative's own ad type.
  const creatives = await AdCreative.find({})
    .select('campaignId adType views')
    .lean();

  const spendByCampaign = new Map();
  for (const creative of creatives) {
    if (!creative.campaignId) continue;
    const views = creative.views || 0;
    if (views <= 0) continue;
    const key = String(creative.campaignId);
    const amount = (views / 1000) * cpmFor(creative.adType);
    spendByCampaign.set(key, (spendByCampaign.get(key) || 0) + amount);
  }

  const campaigns = await AdCampaign.find({})
    .select('name status totalBudget spentINR')
    .lean();

  const unfunded = [];
  const exhausted = [];
  const writes = [];

  for (const campaign of campaigns) {
    const id = String(campaign._id);
    const spend = Number((spendByCampaign.get(id) || 0).toFixed(2));
    const budget = campaign.totalBudget || 0;

    if (!budget) unfunded.push({ ...campaign, spend });
    else if (spend >= budget) exhausted.push({ ...campaign, spend });

    if (spend !== (campaign.spentINR || 0)) {
      writes.push({
        updateOne: { filter: { _id: campaign._id }, update: { $set: { spentINR: spend } } },
      });
    }
  }

  console.log(`Campaigns scanned:      ${campaigns.length}`);
  console.log(`spentINR values to set: ${writes.length}`);

  if (unfunded.length > 0) {
    console.log(`\n⚠️  ${unfunded.length} campaign(s) have no totalBudget — these will STOP serving:`);
    for (const c of unfunded) {
      console.log(`   • ${c.name} [${c.status}] — reconstructed spend ₹${c.spend}`);
    }
    console.log('   Set a totalBudget on any of these that should keep running.');
  }

  if (exhausted.length > 0) {
    console.log(`\n💰 ${exhausted.length} campaign(s) have already spent their budget — these will STOP serving:`);
    for (const c of exhausted) {
      console.log(`   • ${c.name} [${c.status}] — ₹${c.spend} spent of ₹${c.totalBudget}`);
    }
  }

  if (DRY_RUN) {
    console.log('\n🔍 Dry run — nothing written.');
  } else if (writes.length > 0) {
    const result = await AdCampaign.bulkWrite(writes, { ordered: false });
    console.log(`\n✅ Updated ${result.modifiedCount} campaign(s).`);
  } else {
    console.log('\n✅ Already up to date — nothing to write.');
  }

  await mongoose.disconnect();
}

main().catch(async (error) => {
  console.error('❌ Backfill failed:', error);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
