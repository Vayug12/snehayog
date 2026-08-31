import express from 'express';
import { randomUUID } from 'crypto';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { validatePagination } from '../../middleware/validation.js';
import { verifyToken } from '../../utils/verifytoken.js';
import { requireConfiguredAdminDashboardKey } from '../../middleware/adminDashboardAuth.js';
import User from '../../models/User.js';
import AdCreditPurchaseIntent from '../../models/AdCreditPurchaseIntent.js';
import walletService from '../../services/adServices/walletService.js';
import { isKnownProduct } from '../../config/adCreditProducts.js';
import { syncRevenueCatPurchasesForUser } from '../../services/adServices/revenueCatPurchaseSyncService.js';

const router = express.Router();

// /api/ads/* is mounted behind a `public, max-age=180` cache header. That is
// fine for ad serving but not for a wallet — a shared cache could hand one
// user's balance to another. Declared first so it covers every route below,
// including the admin one.
router.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});

/**
 * POST /api/ads/wallet/grant — mint credits into a user's wallet.
 *
 * Declared *before* `router.use(verifyToken)` on purpose: this is called by the
 * admin dashboard with only an admin key, and every other admin route in the
 * repo works the same way. Requiring a user token here would mean an operator
 * could only grant credits to themselves.
 *
 * Always ledgered with a unique `externalId`, so a retried dashboard click
 * cannot double-grant and every grant is attributable after the fact.
 */
router.post('/grant', requireConfiguredAdminDashboardKey, asyncHandler(async (req, res) => {
  const { googleId, amount, note } = req.body || {};

  if (!googleId || typeof googleId !== 'string') {
    return res.status(400).json({ error: 'googleId is required' });
  }

  const credits = Number(amount);
  if (!Number.isInteger(credits) || credits < 1) {
    return res.status(400).json({ error: 'amount must be a positive integer number of credits' });
  }

  const user = await User.findOne({ googleId }).select('_id name email').lean();
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  const { transaction, wallet } = await walletService.credit({
    userId: user._id,
    amount: credits,
    type: 'grant',
    source: 'admin',
    externalId: `admin:${randomUUID()}`,
    reason: note || 'admin grant',
    metadata: { grantedTo: googleId, note: note || null }
  });

  return res.json({
    success: true,
    granted: credits,
    balance: wallet?.balance ?? 0,
    transactionId: transaction?._id,
    user: { googleId, name: user.name, email: user.email }
  });
}));

// Everything below is the caller's own wallet. A wallet is money, so it is
// only ever readable by the user it belongs to.
router.use(verifyToken);

/**
 * Resolve the caller's User._id.
 *
 * AdWallet.userId is an ObjectId ref, so `req.user.id` (the Google ID) is the
 * wrong key here. verifyToken memoises `_id` alongside the token, so this is
 * free; it is absent only when the token is valid but the user row is gone.
 */
const walletOwnerId = (req) => req.user?._id;

// Record before opening Play Billing. Without this, a dropped webhook for a
// user's first-ever purchase leaves no local buyer record for reconciliation.
router.post('/purchase-intents', asyncHandler(async (req, res) => {
  const ownerId = walletOwnerId(req);
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  const productId = String(req.body?.productId || '').split(':')[0].trim();
  if (!isKnownProduct(productId)) {
    return res.status(400).json({ error: 'Unknown ad-credit product' });
  }

  const intent = await AdCreditPurchaseIntent.create({
    userId: ownerId,
    productId
  });

  return res.status(201).json({ success: true, intentId: intent._id });
}));

// Ask RevenueCat directly for the caller's recent consumable purchases. This
// is a safe fallback after checkout because credits still come only from
// RevenueCat's server-side record, never from a client claim.
router.post('/sync-purchases', asyncHandler(async (req, res) => {
  const ownerId = walletOwnerId(req);
  const googleId = req.user?.googleId || req.user?.id;
  if (!ownerId || !googleId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }
  if (!process.env.REVENUECAT_API_KEY) {
    return res.status(503).json({ error: 'Purchase sync is not configured' });
  }

  const sync = await syncRevenueCatPurchasesForUser({
    _id: ownerId,
    googleId
  });
  const wallet = await walletService.getBalance(ownerId);
  return res.json({ success: true, sync, wallet });
}));

// GET /api/ads/wallet - caller's balance (creates the wallet on first read)
router.get('/', asyncHandler(async (req, res) => {
  const ownerId = walletOwnerId(req);
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  const wallet = await walletService.getBalance(ownerId);
  return res.json({ success: true, wallet });
}));

// GET /api/ads/wallet/transactions - paginated ledger history
router.get('/transactions', validatePagination, asyncHandler(async (req, res) => {
  const ownerId = walletOwnerId(req);
  if (!ownerId) {
    return res.status(401).json({ error: 'User not found for this token' });
  }

  const { page, limit } = req.pagination;
  const { items, pagination } = await walletService.getTransactions(ownerId, { page, limit });

  return res.json({ success: true, transactions: items, pagination });
}));

export default router;
