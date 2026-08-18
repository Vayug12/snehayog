/**
 * One-time backfill: seed UserActivity (the daily active-day log) from data we
 * already have, so retention/habit/activation analytics work on day one instead
 * of starting empty and needing a month before they say anything.
 *
 * Sources, best-effort and in order of quality:
 *   1. WatchHistory.watchedAt / lastWatchedAt — a watch on a day proves the user
 *      was active that day. Best source, but WatchHistory has a 90-day TTL, so
 *      history older than that is simply gone.
 *   2. User.createdAt  — signup day is by definition an active day.
 *   3. User.lastActive — the single most recent active day we kept per user.
 *
 * This is an approximation and undercounts: a day where a user opened the app
 * but watched nothing leaves no trace in any of these sources. It therefore
 * makes historical retention look slightly *worse* than reality, never better.
 * Days recorded from live traffic after deploy are exact.
 *
 * Usage:
 *   node scripts/backfill-user-activity.js            # apply
 *   node scripts/backfill-user-activity.js --dry-run  # report only
 *
 * Safe to re-run: every write is an idempotent upsert on (googleId, date).
 */

import mongoose from 'mongoose';
import dotenv from 'dotenv';
import User from '../models/User.js';
import WatchHistory from '../models/WatchHistory.js';
import UserActivity from '../models/UserActivity.js';

dotenv.config();

const DRY_RUN = process.argv.includes('--dry-run');
const BATCH_SIZE = 1000;

/**
 * Collects unique (googleId, UTC-day) pairs. A Set keyed by both fields keeps
 * the job single-pass and avoids sending duplicate upserts to Mongo.
 */
class ActivityCollector {
  constructor(knownGoogleIds) {
    this.knownGoogleIds = knownGoogleIds;
    this.pairs = new Set();
    this.skipped = 0;
  }

  add(googleId, value) {
    if (!googleId || !value) return;
    // WatchHistory.userId is a deviceId for anonymous users — those have no
    // signup cohort, so they cannot take part in retention analysis.
    if (!this.knownGoogleIds.has(googleId)) {
      this.skipped += 1;
      return;
    }
    const day = UserActivity.toUtcDay(value);
    if (Number.isNaN(day.getTime())) return;
    this.pairs.add(`${googleId}|${day.toISOString()}`);
  }

  toOperations() {
    return [...this.pairs].map(pair => {
      const [googleId, iso] = pair.split('|');
      const date = new Date(iso);
      return {
        updateOne: {
          filter: { googleId, date },
          update: { $setOnInsert: { googleId, date } },
          upsert: true
        }
      };
    });
  }
}

async function flush(operations) {
  let inserted = 0;
  for (let i = 0; i < operations.length; i += BATCH_SIZE) {
    const batch = operations.slice(i, i + BATCH_SIZE);
    const result = await UserActivity.bulkWrite(batch, { ordered: false });
    inserted += result.upsertedCount || 0;
    console.log(`   ...${Math.min(i + BATCH_SIZE, operations.length)}/${operations.length} processed`);
  }
  return inserted;
}

async function main() {
  const uri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!uri) {
    console.error('❌ MONGO_URI is not set');
    process.exit(1);
  }

  await mongoose.connect(uri);
  console.log(`✅ Connected${DRY_RUN ? ' (dry run — nothing will be written)' : ''}`);

  console.log('📥 Loading users...');
  const users = await User.find({ googleId: { $exists: true, $ne: null } })
    .select('googleId createdAt lastActive')
    .lean();

  const knownGoogleIds = new Set(users.map(u => u.googleId));
  const collector = new ActivityCollector(knownGoogleIds);

  users.forEach(user => {
    collector.add(user.googleId, user.createdAt);
    collector.add(user.googleId, user.lastActive);
  });
  console.log(`   ${users.length} users → ${collector.pairs.size} day-pairs from signup/lastActive`);

  console.log('📥 Scanning watch history (this is the slow part)...');
  const beforeWatch = collector.pairs.size;
  const cursor = WatchHistory.find({ isAuthenticated: true })
    .select('userId watchedAt lastWatchedAt')
    .lean()
    .cursor();

  let scanned = 0;
  for await (const entry of cursor) {
    collector.add(entry.userId, entry.watchedAt);
    collector.add(entry.userId, entry.lastWatchedAt);
    scanned += 1;
    if (scanned % 50000 === 0) console.log(`   ...${scanned} watch entries scanned`);
  }
  console.log(`   ${scanned} watch entries → +${collector.pairs.size - beforeWatch} additional day-pairs`);

  const operations = collector.toOperations();
  console.log(`\n📊 Total unique active days to write: ${operations.length}`);
  if (collector.skipped > 0) {
    console.log(`   (${collector.skipped} anonymous/device rows skipped — no signup cohort)`);
  }

  if (DRY_RUN) {
    console.log('🔍 Dry run complete — no writes performed.');
  } else {
    console.log('✍️  Writing...');
    const inserted = await flush(operations);
    console.log(`✅ Done. ${inserted} new activity records inserted (${operations.length - inserted} already existed).`);
  }

  await mongoose.disconnect();
}

main().catch(async (error) => {
  console.error('❌ Backfill failed:', error);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
