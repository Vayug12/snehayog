/**
 * Finish ad-credit transactions that were recorded but never applied.
 *
 * Credits are written in two phases — ledger row first, balance second — so a
 * process that dies in between leaves an `applied: false` row and a balance
 * that is short by that amount. This script is the other half of that design:
 * without it, a dropped RevenueCat webhook or a crashed request means a user
 * paid and got nothing.
 *
 * It applies rows through `walletService.applyTransaction`, the same path the
 * live credit uses, so there is exactly one definition of "apply". That call
 * claims each row atomically, so running this concurrently with live traffic
 * (or with a second copy of itself) cannot double-credit.
 *
 * Rows younger than the grace window are skipped — an in-flight credit is
 * `applied: false` for a few milliseconds by design, and racing it wins nothing.
 *
 * Usage:
 *   node scripts/reconcile-ad-credits.js              # apply
 *   node scripts/reconcile-ad-credits.js --dry-run    # report only
 *   node scripts/reconcile-ad-credits.js --minutes=30 # widen the grace window
 *
 * Safe to re-run. Phase 4 wires this to an hourly cron.
 */

import mongoose from 'mongoose';
import dotenv from 'dotenv';
import AdCreditTransaction from '../models/AdCreditTransaction.js';
import walletService from '../services/adServices/walletService.js';

dotenv.config();

const DRY_RUN = process.argv.includes('--dry-run');

const minutesArg = process.argv.find((a) => a.startsWith('--minutes='));
const GRACE_MINUTES = minutesArg ? Number(minutesArg.split('=')[1]) : 5;

const BATCH_SIZE = 200;

async function main() {
  if (!Number.isFinite(GRACE_MINUTES) || GRACE_MINUTES < 0) {
    console.error(`❌ Invalid --minutes value: ${GRACE_MINUTES}`);
    process.exit(1);
  }

  const uri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!uri) {
    console.error('❌ MONGO_URI is not set');
    process.exit(1);
  }

  await mongoose.connect(uri);
  console.log(`✅ Connected to MongoDB${DRY_RUN ? ' (dry run)' : ''}`);

  const cutoff = new Date(Date.now() - GRACE_MINUTES * 60 * 1000);

  const stale = await AdCreditTransaction.find({
    applied: false,
    createdAt: { $lt: cutoff }
  })
    .sort({ createdAt: 1 })
    .limit(BATCH_SIZE);

  if (stale.length === 0) {
    console.log(`✅ Nothing to reconcile (no unapplied rows older than ${GRACE_MINUTES}m)`);
    await mongoose.disconnect();
    return;
  }

  console.log(`🔎 Found ${stale.length} unapplied transaction(s) older than ${GRACE_MINUTES}m`);

  let applied = 0;
  let alreadyDone = 0;
  let failed = 0;
  let creditsApplied = 0;

  for (const txn of stale) {
    const label = `${txn.type} ${txn.amount} (${txn.source}) user=${txn.userId} id=${txn._id}`;

    if (DRY_RUN) {
      console.log(`   would apply: ${label}`);
      creditsApplied += txn.amount;
      applied += 1;
      continue;
    }

    try {
      // Applied one at a time, not in parallel: these are all balance writes
      // and a burst of them against the same wallet only adds contention.
      const result = await walletService.applyTransaction(txn);

      if (result?.applied) {
        // `appliedNow` is set only by the call that won the atomic claim, so a
        // row another worker was finishing at the same moment is not counted
        // as credits this run moved.
        if (result.$locals?.appliedNow) {
          applied += 1;
          creditsApplied += txn.amount;
          console.log(`   ✅ applied: ${label} → balance ${result.balanceAfter}`);
        } else {
          alreadyDone += 1;
          console.log(`   ↩️  already applied elsewhere: ${label}`);
        }
      } else {
        failed += 1;
        console.warn(`   ⚠️  still unapplied after attempt: ${label}`);
      }
    } catch (err) {
      failed += 1;
      console.error(`   ❌ failed: ${label} — ${err.message}`);
    }
  }

  console.log('\n📊 Summary');
  console.log(`   applied:        ${applied}`);
  console.log(`   already applied:${alreadyDone}`);
  console.log(`   failed:         ${failed}`);
  console.log(`   credits moved:  ${creditsApplied}${DRY_RUN ? ' (dry run — nothing written)' : ''}`);

  if (stale.length === BATCH_SIZE) {
    console.log(`\n⚠️  Hit the ${BATCH_SIZE}-row batch limit — run again to process the rest.`);
  }

  await mongoose.disconnect();
  console.log('✅ Done');
}

main().catch(async (err) => {
  console.error('❌ Reconcile failed:', err);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
