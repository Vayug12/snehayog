/**
 * One-time migration: convert AdImpression's plain `timestamp_1` index into a
 * TTL index.
 *
 * Why this is needed: the collection already carries a non-TTL `timestamp_1`
 * index. Mongo refuses to create a second index with the same key pattern but
 * different options (IndexOptionsConflict), so the TTL index declared in
 * models/AdImpression.js can never be built until the old one is converted.
 *
 * This uses collMod where possible (in-place, no index rebuild). If the index
 * predates TTL support or collMod is unavailable, it falls back to drop+create.
 *
 * Usage:
 *   node scripts/migrate-ad-impression-ttl.js            # apply
 *   node scripts/migrate-ad-impression-ttl.js --dry-run  # report only
 *
 * Safe to re-run: it exits early if the TTL is already correct.
 */

import mongoose from 'mongoose';
import dotenv from 'dotenv';

dotenv.config();

const TTL_DAYS = Number(process.env.AD_IMPRESSION_TTL_DAYS) || 90;
const TTL_SECONDS = TTL_DAYS * 24 * 60 * 60;
const COLLECTION = 'adimpressions';
const INDEX_NAME = 'timestamp_1';
const DRY_RUN = process.argv.includes('--dry-run');

async function main() {
  const uri = process.env.MONGO_URI;
  if (!uri) {
    console.error('❌ MONGO_URI is not set');
    process.exit(1);
  }

  await mongoose.connect(uri);
  const db = mongoose.connection.db;
  const collection = db.collection(COLLECTION);

  const indexes = await collection.indexes();
  const existing = indexes.find((idx) => idx.name === INDEX_NAME);

  console.log(`📋 Collection: ${COLLECTION}`);
  console.log(`📋 Target TTL: ${TTL_DAYS} days (${TTL_SECONDS}s)`);
  console.log(`📋 Existing ${INDEX_NAME}:`, existing ? JSON.stringify(existing) : 'none');

  if (existing && existing.expireAfterSeconds === TTL_SECONDS) {
    console.log('✅ Already migrated — nothing to do.');
    return;
  }

  // Report how much data the TTL will reclaim on first sweep.
  const cutoff = new Date(Date.now() - TTL_SECONDS * 1000);
  const [total, expiring] = await Promise.all([
    collection.estimatedDocumentCount(),
    collection.countDocuments({ timestamp: { $lt: cutoff } }),
  ]);
  console.log(`📊 Documents: ${total} total, ${expiring} older than ${TTL_DAYS} days`);
  console.log(`📊 First TTL sweep will delete ~${expiring} rows (~${Math.round(expiring * 500 / 1024 / 1024)} MB incl. indexes)`);

  if (DRY_RUN) {
    console.log('🔍 --dry-run: no changes written.');
    return;
  }

  if (!existing) {
    console.log('🔧 Creating TTL index...');
    await collection.createIndex({ timestamp: 1 }, { expireAfterSeconds: TTL_SECONDS });
  } else {
    try {
      console.log('🔧 Converting existing index in place via collMod...');
      await db.command({
        collMod: COLLECTION,
        index: { name: INDEX_NAME, expireAfterSeconds: TTL_SECONDS },
      });
    } catch (error) {
      console.warn(`⚠️ collMod failed (${error.message}) — falling back to drop + create`);
      await collection.dropIndex(INDEX_NAME);
      await collection.createIndex({ timestamp: 1 }, { expireAfterSeconds: TTL_SECONDS });
    }
  }

  const after = (await collection.indexes()).find((idx) => idx.name === INDEX_NAME);
  console.log('✅ Migration complete:', JSON.stringify(after));
  console.log('ℹ️  Mongo\'s TTL monitor sweeps every 60s; deletion of the backlog is gradual.');
}

main()
  .catch((error) => {
    console.error('❌ Migration failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect();
  });
