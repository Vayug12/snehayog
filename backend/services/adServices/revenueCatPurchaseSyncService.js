import AdCreditPurchaseIntent from '../../models/AdCreditPurchaseIntent.js';
import AdCreditTransaction from '../../models/AdCreditTransaction.js';
import User from '../../models/User.js';
import { creditsForProduct } from '../../config/adCreditProducts.js';
import walletService from './walletService.js';

const RC_API = 'https://api.revenuecat.com/v1';
const REQUEST_TIMEOUT_MS = 10_000;

export const purchaseExternalId = (transactionId) => (
  `revenuecat_purchase:${String(transactionId).trim()}`
);

const fetchSubscriber = async (googleId, apiKey) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  timeout.unref?.();

  try {
    const response = await fetch(
      `${RC_API}/subscribers/${encodeURIComponent(googleId)}`,
      {
        headers: { Authorization: `Bearer ${apiKey}` },
        signal: controller.signal
      }
    );

    if (response.status === 404) return null;
    if (!response.ok) {
      throw new Error(
        `RevenueCat ${response.status}: ${(await response.text()).slice(0, 200)}`
      );
    }
    return response.json();
  } finally {
    clearTimeout(timeout);
  }
};

export const syncRevenueCatPurchasesForUser = async (
  user,
  {
    apiKey = process.env.REVENUECAT_API_KEY,
    since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    dryRun = false
  } = {}
) => {
  if (!apiKey) throw new Error('REVENUECAT_API_KEY is not configured');
  if (!user?._id || !user?.googleId) throw new Error('A persisted user is required');

  const body = await fetchSubscriber(user.googleId, apiKey);
  const nonSubscriptions = body?.subscriber?.non_subscriptions;
  const result = { checked: 0, recovered: 0, creditsRecovered: 0 };

  if (!nonSubscriptions || typeof nonSubscriptions !== 'object') return result;

  const candidates = [];

  for (const [productId, purchases] of Object.entries(nonSubscriptions)) {
    const credits = creditsForProduct(productId);
    if (credits === null || !Array.isArray(purchases)) continue;

    for (const purchase of purchases) {
      const purchasedAt = new Date(purchase?.purchase_date);
      if (Number.isNaN(purchasedAt.getTime()) || purchasedAt < since) continue;
      if (purchase?.is_sandbox && process.env.NODE_ENV === 'production') continue;
      // RevenueCat keeps refunded non-subscription transactions in customer
      // history. Recovery must not turn a refunded purchase back into credits.
      if (purchase?.refunded_at) continue;

      result.checked += 1;
      const transactionId = purchase?.store_transaction_id || purchase?.id;
      if (!transactionId) continue;

      candidates.push({ productId, purchase, credits, transactionId: String(transactionId) });
    }
  }

  if (candidates.length === 0) return result;

  const identifiers = candidates.flatMap(({ purchase, transactionId }) => [
    transactionId,
    purchase?.id ? String(purchase.id) : null,
    purchase?.store_transaction_id ? String(purchase.store_transaction_id) : null
  ]).filter(Boolean);

  const existingRows = await AdCreditTransaction.find({
    $or: [
      { externalId: { $in: identifiers.flatMap((id) => [
        purchaseExternalId(id),
        `revenuecat:${id}`
      ]) } },
      { 'metadata.purchaseId': { $in: identifiers } },
      { 'metadata.transactionId': { $in: identifiers } }
    ]
  }).select('externalId metadata').lean();

  const recordedIds = new Set();
  for (const row of existingRows) {
    if (row.externalId) recordedIds.add(String(row.externalId));
    if (row.metadata?.purchaseId) recordedIds.add(String(row.metadata.purchaseId));
    if (row.metadata?.transactionId) recordedIds.add(String(row.metadata.transactionId));
  }

  for (const { productId, purchase, credits, transactionId } of candidates) {
    const purchaseId = purchase?.id ? String(purchase.id) : null;
    const alreadyRecorded = recordedIds.has(transactionId)
      || (purchaseId && recordedIds.has(purchaseId))
      || recordedIds.has(purchaseExternalId(transactionId))
      || recordedIds.has(`revenuecat:${transactionId}`);
    if (alreadyRecorded) continue;

    if (!dryRun) {
      const { duplicate } = await walletService.credit({
        userId: user._id,
        amount: credits,
        type: 'purchase',
        source: 'revenuecat',
        externalId: purchaseExternalId(transactionId),
        productId,
        reason: 'reconciled_missed_webhook',
        metadata: {
          purchaseId: purchase?.id || null,
          transactionId: purchase?.store_transaction_id || null,
          purchasedAt: purchase?.purchase_date || null
        }
      });
      if (duplicate) continue;
    }

    recordedIds.add(transactionId);
    recordedIds.add(purchaseExternalId(transactionId));
    result.recovered += 1;
    result.creditsRecovered += credits;
  }

  return result;
};

export const findReconciliationCandidates = async (since) => {
  const [ledgerUserIds, intentUserIds] = await Promise.all([
    AdCreditTransaction.distinct('userId', {
      source: 'revenuecat',
      createdAt: { $gte: since }
    }),
    AdCreditPurchaseIntent.distinct('userId', {
      createdAt: { $gte: since }
    })
  ]);

  const userIds = [...new Set(
    [...ledgerUserIds, ...intentUserIds].map((id) => String(id))
  )];

  if (userIds.length === 0) return [];
  return User.find({ _id: { $in: userIds } }).select('_id googleId').lean();
};

export default {
  purchaseExternalId,
  syncRevenueCatPurchasesForUser,
  findReconciliationCandidates
};
