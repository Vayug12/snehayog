/**
 * Catch purchases the webhook never delivered.
 *
 * Webhooks get dropped — a deploy mid-request, a machine asleep, a network
 * blip, a 500 that outlived RevenueCat's retry schedule. Every one of those is
 * a user who paid Google and got no credits, and who will not find out from us.
 * This script is the safety net, and it is the reason the webhook is allowed to
 * fail at all.
 *
 * Two passes:
 *   1. Apply any ledger row still sitting `applied: false` (the same sweep as
 *      reconcile-ad-credits.js — a crash between the two phases of a credit).
 *   2. Ask RevenueCat for each recent buyer's transactions and credit anything
 *      with no ledger row.
 *
 * Pass 2 needs `REVENUECAT_API_KEY` (a v1 secret key). Without it the script
 * still runs pass 1 and says what it skipped.
 *
 * Idempotent: everything is keyed on `revenuecat:<id>`, and the ledger's unique
 * index rejects a second credit for the same id. Safe to re-run and safe to run
 * concurrently with live webhooks.
 *
 * Usage:
 *   node scripts/reconcile-revenuecat.js                 # apply
 *   node scripts/reconcile-revenuecat.js --dry-run       # report only
 *   node scripts/reconcile-revenuecat.js --days=7        # lookback (default 3)
 */

import mongoose from 'mongoose';
import dotenv from 'dotenv';
import AdCreditTransaction from '../models/AdCreditTransaction.js';
import User from '../models/User.js';
import walletService from '../services/adServices/walletService.js';
import { creditsForProduct } from '../config/adCreditProducts.js';

dotenv.config();

const DRY_RUN = process.argv.includes('--dry-run');
const daysArg = process.argv.find((a) => a.startsWith('--days='));
const LOOKBACK_DAYS = daysArg ? Number(daysArg.split('=')[1]) : 3;

const GRACE_MINUTES = 5;
const RC_API = 'https://api.revenuecat.com/v1';

const stats = {
  applied: 0,
  recovered: 0,
  creditsRecovered: 0,
  checked: 0,
  failed: 0
};

/** Pass 1 — finish credits whose ledger row exists but never moved a balance. */
async function applyOrphanedRows() {
  const cutoff = new Date(Date.now() - GRACE_MINUTES * 60 * 1000);
  const stale = await AdCreditTransaction.find({
    applied: false,
    createdAt: { $lt: cutoff }
  })
    .sort({ createdAt: 1 })
    .limit(200);

  if (stale.length === 0) {
    console.log('✅ Pass 1: no unapplied ledger rows');
    return;
  }

  console.log(`🔎 Pass 1: ${stale.length} unapplied row(s)`);

  for (const txn of stale) {
    if (DRY_RUN) {
      console.log(`   would apply: ${txn.type} ${txn.amount} (${txn.externalId || txn._id})`);
      stats.applied += 1;
      continue;
    }

    try {
      const result = await walletService.applyTransaction(txn);
      if (result?.$locals?.appliedNow) {
        stats.applied += 1;
        console.log(`   ✅ applied ${txn.type} ${txn.amount} → balance ${result.balanceAfter}`);
      }
    } catch (err) {
      stats.failed += 1;
      console.error(`   ❌ ${txn._id}: ${err.message}`);
    }
  }
}

/**
 * Buyers worth re-checking: anyone with a RevenueCat ledger row inside the
 * lookback window. A user who has never purchased has nothing to reconcile, so
 * this avoids walking the whole user table for one dropped webhook.
 */
async function recentBuyers(since) {
  const userIds = await AdCreditTransaction.distinct('userId', {
    source: 'revenuecat',
    createdAt: { $gte: since }
  });

  if (userIds.length === 0) return [];
  return User.find({ _id: { $in: userIds } }).select('_id googleId').lean();
}

async function fetchSubscriber(googleId, apiKey) {
  const res = await fetch(`${RC_API}/subscribers/${encodeURIComponent(googleId)}`, {
    headers: { Authorization: `Bearer ${apiKey}` }
  });

  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(`RevenueCat ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }

  return res.json();
}

/**
 * Pass 2 — compare RevenueCat's record of what was bought against ours.
 *
 * `non_subscriptions` is where consumables live: a map of product id to the
 * list of times it was purchased, each with its own id. That per-purchase id is
 * what the webhook would have used, so it is what we key on here.
 */
async function recoverMissedPurchases(since, apiKey) {
  const buyers = await recentBuyers(since);
  if (buyers.length === 0) {
    console.log('✅ Pass 2: no recent RevenueCat activity to check');
    return;
  }

  console.log(`🔎 Pass 2: checking ${buyers.length} recent buyer(s) against RevenueCat`);

  for (const user of buyers) {
    stats.checked += 1;

    let subscriber;
    try {
      const body = await fetchSubscriber(user.googleId, apiKey);
      subscriber = body?.subscriber;
    } catch (err) {
      stats.failed += 1;
      console.error(`   ❌ ${user.googleId}: ${err.message}`);
      continue;
    }

    if (!subscriber?.non_subscriptions) continue;

    for (const [productId, purchases] of Object.entries(subscriber.non_subscriptions)) {
      const credits = creditsForProduct(productId);
      if (credits === null) continue;

      for (const purchase of purchases) {
        const purchasedAt = new Date(purchase.purchase_date);
        if (Number.isNaN(purchasedAt.getTime()) || purchasedAt < since) continue;

        // Sandbox purchases are free; crediting them in production is an exploit.
        if (purchase.is_sandbox && process.env.NODE_ENV === 'production') continue;

        const externalId = `revenuecat:${purchase.id}`;
        const already = await AdCreditTransaction.exists({
          $or: [{ externalId }, { externalId: `revenuecat:${purchase.store_transaction_id}` }]
        });
        if (already) continue;

        if (DRY_RUN) {
          console.log(`   would recover ${credits} for ${user.googleId} (${productId}, ${purchase.id})`);
          stats.recovered += 1;
          stats.creditsRecovered += credits;
          continue;
        }

        try {
          const { duplicate, wallet } = await walletService.credit({
            userId: user._id,
            amount: credits,
            type: 'purchase',
            source: 'revenuecat',
            externalId,
            productId,
            reason: 'reconciled_missed_webhook',
            metadata: { purchaseId: purchase.id, purchasedAt: purchase.purchase_date }
          });

          if (!duplicate) {
            stats.recovered += 1;
            stats.creditsRecovered += credits;
            console.log(`   💳 recovered ${credits} for ${user.googleId} → balance ${wallet?.balance}`);
          }
        } catch (err) {
          stats.failed += 1;
          console.error(`   ❌ ${user.googleId} ${purchase.id}: ${err.message}`);
        }
      }
    }
  }
}

async function main() {
  if (!Number.isFinite(LOOKBACK_DAYS) || LOOKBACK_DAYS <= 0) {
    console.error(`❌ Invalid --days value: ${LOOKBACK_DAYS}`);
    process.exit(1);
  }

  const uri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!uri) {
    console.error('❌ MONGO_URI is not set');
    process.exit(1);
  }

  await mongoose.connect(uri);
  console.log(`✅ Connected to MongoDB${DRY_RUN ? ' (dry run)' : ''}`);

  await applyOrphanedRows();

  const apiKey = process.env.REVENUECAT_API_KEY;
  if (!apiKey) {
    console.warn('⚠️ Pass 2 skipped: REVENUECAT_API_KEY is not set.');
    console.warn('   Dropped webhooks will NOT be recovered until it is configured.');
  } else {
    const since = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000);
    await recoverMissedPurchases(since, apiKey);
  }

  console.log('\n📊 Summary');
  console.log(`   orphaned rows applied: ${stats.applied}`);
  console.log(`   buyers checked:        ${stats.checked}`);
  console.log(`   purchases recovered:   ${stats.recovered}`);
  console.log(`   credits recovered:     ${stats.creditsRecovered}${DRY_RUN ? ' (dry run — nothing written)' : ''}`);
  console.log(`   failures:              ${stats.failed}`);

  await mongoose.disconnect();
  console.log('✅ Done');
  process.exit(stats.failed > 0 ? 1 : 0);
}

main().catch(async (err) => {
  console.error('❌ Reconcile failed:', err);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
