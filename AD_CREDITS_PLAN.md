# Ad Credits — Implementation Plan (Phases 1–4)

Prepaid ad-credit wallet funded by **RevenueCat consumables over Google Play Billing**.
Razorpay is fully removed. This document is the working spec — a fresh session should be
able to start from here without prior context.

> **Standing constraint: do not `git commit`.** Everything below stays in the working tree
> until the user commits it themselves.

---

## 0. Where we are right now

All of this is **done but uncommitted** (`git status` shows ~45 changed paths).

### Phases 1, 2 and 3 — code DONE (see the "status" sections below for deviations)

Phase 3's **dashboard work (§3.1) and pricing decisions (§3.2) are still yours** — the code is
inert until `REVENUECAT_WEBHOOK_SECRET` and a client SDK key exist.

### Phase 0 — Razorpay / payment attack surface deleted

| What | Why |
|---|---|
| `backend/routes/adRoutes/paymentRoutes.js` — **deleted** | Held `POST /ads/process-payment`, which trusted a client-supplied payment id |
| `backend/routes/adRoutes/adRoutes.js` — **deleted** (1400 lines) | Dead file, never imported; contained a second copy of the same bypass |
| `GET /creator/revenue/:userId` | Moved verbatim from `paymentRoutes.js` → `analyticsRoutes.js` (now ~line 122) with `verifyToken`. This is what the Flutter creator revenue screen calls — it still works |
| `adService.createAdWithPayment` / `processPayment` — **deleted** (223 lines) | See "the real bug" below |
| `validatePaymentData` (both copies), `config/razorpay.js`, razorpay config blocks, `npm uninstall razorpay` | Dead once the routes went |
| `packages/snehayog_monetization/` — **deleted** | Contained only `razorpay_service.dart` |
| Flutter: `payment_handler_widget.dart` deleted, `advertising_benefits_widget.dart` extracted from it, leaked Razorpay keys removed from `app_config.dart` | Keys were hardcoded in a shipped client |

**The real bug found during Phase 0:** `createAdWithPayment` already set
`reviewStatus: 'approved'`, `isActive: true`, and campaign `status: 'active'` **at creation
time**. `processPayment` only stamped an invoice afterwards. Nobody ever had to forge a
signature — ads went live without calling the payment endpoint at all.

### Phase 0.5 — Budget enforcement (a campaign can now run out of money)

- `AdCampaign.spentINR` field added.
- `backend/services/adServices/campaignServability.js` — **the single definition of
  "servable"**. Exports `servableCampaignMatch()` (for `populate({ match })`),
  `servableCampaignStage(as)` (for aggregation), `isCampaignServable(doc)` (in-memory).
  A **missing `totalBudget` counts as zero**, i.e. excluded — an unfunded campaign is not
  served for free.
- `backend/services/adServices/adStatsBuffer.js` — `recordCampaignSpend(adId, adType, count)`
  accumulates spend in a `spendDeltas` Map, resolves creative→campaign once per flush, then
  `bulkWrite`s `$inc: { spentINR }` and flips exhausted campaigns to `status: 'completed'`.
- `backend/routes/adRoutes/impressionRoutes.js` — `bookDeliveredView(creatorId, adId, adType)`
  books creator credit and advertiser spend **together, at the same CPM**. Splitting them
  would let a campaign fund creator payouts past its own budget.
- 8 serving paths gated: `BannerAdSource`, `CarouselAdSource`, 5 paths in
  `adTargetingService.js` (the AI-semantic path at ~line 78 previously had **no campaign
  check at all**), and `creativeRoutes.js GET /carousel`.
- `backend/scripts/backfill-campaign-spend.js` — reconstructs `spentINR` from
  `AdCreative.views` at the same CPM. Supports `--dry-run`. Safe to re-run.

### campaignRoutes hardening

`backend/routes/adRoutes/campaignRoutes.js` now has `router.use(verifyToken)`, a router-level
`Cache-Control: no-store`, an `advertiserId(req)` helper and a `loadOwnedCampaign` middleware
(404 not 403 for someone else's campaign). `GET /` is always scoped to the caller — it used to
list **every** advertiser's campaigns plus their name and email whenever `me=true` was omitted.

### Flutter is already pointed at the new endpoint

`ad_service.dart` → `createAdWithCredits()` → `POST $baseUrl/api/ads/create-with-credits`.
Gated by `AppConfig.adCreationEnabled = false`, and `_submitAd()` in
`create_ad_screen_refactored.dart` short-circuits with a friendly message while it is false.
**Nothing in the app can create an ad until Phase 2 ships.** That is intentional.

---

## Repo facts you need before writing any code

These are the things that are easy to get wrong here.

**`verifyToken` (`backend/utils/verifytoken.js`) sets both:**
- `req.user.id` / `req.user.googleId` → **Google ID string**
- `req.user._id` → **`User._id` as a string**, memoised for 10 min (`getMemoizedUserExtras`)

`AdWallet.userId` and `AdCampaign.advertiserUserId` are `ObjectId ref User`, so they need
`req.user._id`. Roughly 31 other `req.user.id` usages in the repo are *correct* — they feed
`User.findOne({ googleId: req.user.id })`. Don't "fix" those.
`req.user._id` is `undefined` when the token is valid but the user row is gone → return 401.

**`/api/ads/*` is mounted behind a shared cache header** — `loaders/express.js:177`:
```js
apiRouter.use('/ads', createCacheMiddleware('public, max-age=180, ...'), adRoutes);
```
Any per-user route under `/api/ads` **must** set `Cache-Control: no-store` at the router level,
the way `campaignRoutes.js` does. Wallet routes are per-user. This is not optional.

**`express.json()` is global** — `loaders/express.js:120`, before the API router. The
RevenueCat webhook needs the **raw body**, so it must be mounted *before* that line, or use
`express.raw({ type: 'application/json' })` on that one path.

**Route mounting:** `backend/routes/adRoutes/index.js` mounts the sub-routers. Note most are
mounted at `/`, so a new `walletRoutes` should be `router.use('/wallet', walletRoutes)`.

**Money constants** — `backend/constants/index.js`:
```js
AD_CONFIG = { MIN_DAILY_BUDGET: 100, MIN_TOTAL_BUDGET: 1000,
              DEFAULT_CPM: 30, BANNER_CPM: 20,
              CREATOR_REVENUE_SHARE: 0.80, PLATFORM_REVENUE_SHARE: 0.20, ... }
```

**Admin guard that already exists:** `requireAdminDashboardKey` from
`backend/middleware/adminDashboardAuth.js` (header key check). Reuse it — don't invent a new one.

**`AdCampaign.status` enum is** `['draft','pending_review','active','paused','completed']`.
There is **no `cancelled`** — Phase 1's refund path has to either add it or reuse `completed`.

---

## 1 credit = ₹1 of ad spend. Integers only.

Wallet balances are **whole integer credits**. Campaign budgets must be integers.
Refunds of unspent budget are **floored** to an integer — rounding always favours the platform,
so the ledger can never manufacture money. `spentINR` stays fractional (it accrues per
impression); only the wallet is integral.

---

# Phase 1 — Wallet ledger

**Goal:** a balance that can be credited and debited safely, with an append-only audit trail.
No purchase path and no spend path yet — those are Phases 3 and 2. Phase 1 is testable on its
own via the admin grant endpoint.

### 1.1 `backend/models/AdWallet.js`

```js
{
  userId:            { type: ObjectId, ref: 'User', required: true, unique: true, index: true },
  balance:           { type: Number, default: 0, min: 0 },   // whole credits
  lifetimePurchased: { type: Number, default: 0 },
  lifetimeSpent:     { type: Number, default: 0 },
  currency:          { type: String, default: 'INR' },
  status:            { type: String, enum: ['active', 'frozen'], default: 'active' },
}
```
`min: 0` is a backstop; the atomic debit is what actually prevents an overdraft.
`frozen` exists so a chargeback/fraud case can stop spend without deleting history.

### 1.2 `backend/models/AdCreditTransaction.js` — append-only, never updated in place

```js
{
  userId:      { type: ObjectId, ref: 'User', required: true },
  type:        { enum: ['purchase','spend','refund','grant','reversal'], required: true },
  amount:      { type: Number, required: true, min: 1 },   // always positive; sign implied by type
  balanceAfter:{ type: Number },                            // set when applied
  source:      { enum: ['revenuecat','admin','campaign','system'], required: true },
  externalId:  { type: String },        // RevenueCat event/transaction id — the idempotency key
  campaignId:  { type: ObjectId, ref: 'AdCampaign' },
  productId:   { type: String },
  applied:     { type: Boolean, default: false, index: true },
  appliedAt:   { type: Date },
  metadata:    { type: Object },
}
```

Indexes:
```js
schema.index({ externalId: 1 }, { unique: true, sparse: true });  // idempotency
schema.index({ userId: 1, createdAt: -1 });                        // history listing
schema.index({ applied: 1, createdAt: 1 });                        // reconcile sweep
```

**The unique sparse index on `externalId` is the whole anti-double-credit mechanism.**
RevenueCat retries webhooks; without it a retry mints free credits.

### 1.3 `backend/services/adServices/walletService.js`

**`getOrCreateWallet(userId)`** — `findOneAndUpdate({userId}, {$setOnInsert:{...}}, {upsert:true, new:true})`.
Handle the duplicate-key race (two concurrent first-requests) by re-reading on `E11000`.

**`credit({ userId, amount, type, source, externalId, productId, metadata })` — two-phase, idempotent:**

1. Insert the ledger row with `applied: false`. A duplicate `externalId` throws `E11000` →
   **that is success, not failure**: return the existing row, credit nothing.
2. `$inc` the wallet `balance` and `lifetimePurchased`.
3. Set `applied: true, appliedAt, balanceAfter`.

If the process dies between 1 and 2, the row sits `applied:false` and the **reconcile sweep**
(§1.6) applies it. This is why we don't need Mongo transactions — and the same `applied` flag
is what makes dropped RevenueCat webhooks recoverable in Phase 3. Never collapse this into
"increment then log": a crash there loses the audit row for money that already moved.

**`debit({ userId, amount, campaignId, reason })` — atomic, no read-then-write:**
```js
const wallet = await AdWallet.findOneAndUpdate(
  { userId, status: 'active', balance: { $gte: amount } },
  { $inc: { balance: -amount, lifetimeSpent: amount } },
  { new: true }
);
if (!wallet) throw new InsufficientCreditsError(amount, currentBalance);
```
The `balance: { $gte: amount }` in the **filter** is what makes this safe. A read, a check, then
a write is a race two parallel requests will win together.

Then write the `spend` ledger row (`applied: true`, `balanceAfter: wallet.balance`). If that
write fails, **compensate immediately** — `$inc` the balance back and rethrow. Money moved with
no record is worse than a failed request.

**`refund({ userId, amount, campaignId, reason })`** — `Math.floor(amount)`, credit back,
ledger `type: 'refund'`, `source: 'campaign'`. Used when a campaign ends under budget.

Export a typed `InsufficientCreditsError` carrying `required` and `available` so the route can
build the 402 shortfall response without re-querying.

### 1.4 `backend/routes/adRoutes/walletRoutes.js`

Copy the header block from `campaignRoutes.js` verbatim — `router.use(verifyToken)` then the
`no-store` middleware, with the same comment explaining the `/api/ads` cache header.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/ads/wallet` | Caller's balance. Creates the wallet lazily on first read |
| `GET` | `/api/ads/wallet/transactions` | Paginated, `{ userId: req.user._id }` — reuse `validatePagination` |
| `POST` | `/api/ads/wallet/grant` | **`requireAdminDashboardKey`**. Body: `{ googleId, amount, note }`. `source:'admin'`, `externalId: 'admin:<uuid>'` |

Mount in `adRoutes/index.js`: `router.use('/wallet', walletRoutes);`

The grant endpoint is not a convenience — it is how Phase 1 gets tested and how a support
refund happens before Phase 3 exists. Keep it admin-key-gated and always ledgered.

### 1.5 Flutter — read-only wallet UI

- `frontend/lib/features/ads/data/services/wallet_service.dart` — `getBalance()`, `getTransactions()`.
- Riverpod provider + a balance chip on the create-ad screen and a transactions list.
- No purchase button yet (Phase 3). Show balance and history only.

### 1.6 `backend/scripts/reconcile-ad-credits.js`

Finds `AdCreditTransaction` rows with `applied:false` older than 5 minutes and applies them
(same `$inc` + mark-applied path as `walletService.credit`). Idempotent. Run it manually in
Phase 1; wire it to a cron in Phase 4.

### Phase 1 verification

- `node --check` every new file.
- A script (scratchpad, against a **local/test** Mongo — not prod) that: grants 1000, debits 400,
  asserts balance 600 and 2 ledger rows; fires 20 parallel debits of 100 against a balance of
  1000 and asserts exactly 10 succeed and the balance is 0; calls `credit` twice with the same
  `externalId` and asserts one row and one increment.
- `curl` the three routes and confirm `Cache-Control: no-store` on each response.
- `flutter analyze` → 0 errors (there are ~454 pre-existing `avoid_print` / `empty_catches`
  warnings; that count is the baseline, not a regression).

**Do not boot the dev server against prod Mongo/Upstash** — Upstash is on a 10k/day request cap.

---

## Phase 1 status — implemented and verified (uncommitted)

Files added: `models/AdWallet.js`, `models/AdCreditTransaction.js`,
`services/adServices/walletService.js`, `routes/adRoutes/walletRoutes.js`,
`scripts/reconcile-ad-credits.js`, plus Flutter `data/wallet_model.dart`,
`data/services/wallet_service.dart`,
`presentation/screens/wallet_transactions_screen.dart`,
`presentation/widgets/create_ad/wallet_balance_chip.dart`.
Mounted at `adRoutes/index.js` → `router.use('/wallet', walletRoutes)`.
The chip is wired into `create_ad_screen_refactored.dart` above the form.

**Three deliberate deviations from the spec above:**

1. **The apply step claims the row, and a loser reverses itself.** §1.3 says
   "`$inc` the wallet, then set `applied: true`". Done literally, the reconcile
   sweep and a live retry can both read `applied:false` and both increment.
   `applyTransaction()` therefore marks with the filter `{ _id, applied: false }`
   — exactly one caller wins — and whoever loses undoes the `$inc` it just made.
   Order is still increment-then-mark, so a crash still fails toward "recoverable
   by the sweep", never toward "money moved, no record".

2. **`refund` reduces `lifetimeSpent` instead of raising `lifetimePurchased`.**
   A returned campaign budget was never bought twice; counting it as a purchase
   would overstate revenue in every report built on that field.

3. **`POST /wallet/grant` fails closed when `ADMIN_DASHBOARD_KEY` is unset.**
   `requireAdminDashboardKey` falls *open* in non-production when the key is
   missing. That is fine for read-only dashboard routes and not fine for one
   that mints money, so `walletRoutes` adds a 503 precondition in front of it.
   The shared middleware is untouched.

Also worth knowing: the grant route is declared **before** `router.use(verifyToken)`,
so it needs only the admin key — matching every other admin route in the repo.
An operator with a user token could otherwise only grant credits to themselves.

**Verification actually run** (ephemeral MongoDB via `mongodb-memory-server`;
nothing touched prod Mongo or Upstash):

- 53/53 service-level assertions — grant→debit arithmetic and ledger-sum
  equality; 20 parallel debits of 100 against 1000 → exactly 10 succeed, balance
  0, 10 spend rows; same-`externalId` credit twice → one row, one increment;
  10 concurrent credits on one `externalId` → one increment; orphaned
  `applied:false` row applied exactly once, second sweep a no-op; two workers
  applying the same row → one increment; refund flooring (959.4 → 959, dust
  skipped not rounded up); frozen wallet blocks spend but accepts credits;
  `0/-5/10.5/NaN/Infinity/null/undefined/'100'` all rejected without moving a
  balance; debit on an unknown user → 402 with `available: 0`.
- 25/25 route-level assertions, mounted behind the same
  `public, max-age=180` header `/api/ads` carries — `Cache-Control: no-store`
  on all three routes *and* on the 401; grant guards (no key / wrong key → 401,
  fractional → 400, negative → 400, unknown user → 404, none of which move the
  balance); `limit=500` → 400; a second user sees their own zero balance and
  none of the first user's rows.
- `reconcile-ad-credits.js` dry-run → real run → second run: credits once,
  the second run is a no-op, and an in-flight row inside the 5-minute grace
  window is correctly skipped.
- `node --check` on all six backend files.
- `flutter analyze lib/features/ads` → 22 issues, **0 errors**, none in the new
  files (all pre-existing `avoid_print`).

**Not done in Phase 1, by design:** no purchase path (Phase 3) and no spend path
(Phase 2). `AppConfig.adCreationEnabled` is still `false`.

---

# Phase 2 — Create ads on credits

**Goal:** `POST /api/ads/create-with-credits`, the endpoint the Flutter client already calls.

### 2.1 The endpoint

New route in `campaignRoutes.js` or a dedicated `adCreationRoutes.js` — either way behind
`verifyToken` + `no-store`.

Request body is already defined by `ad_service.dart:158-256`: `title`, `description`,
`imageUrl`/`videoUrl`/`imageUrls`, `link`, `adType`, `budget`, `targetAudience`,
`targetKeywords`, `startDate`, `endDate`, targeting fields, `bidType`/`bidAmount`, etc.

**Fields to ignore from the body — they are trust boundaries, not inputs:**
- `uploaderId` → use `req.user.googleId`
- `uploaderName`, `uploaderProfilePic` → look up from `User`
- `advertiserUserId` → `req.user._id`
- `fixedCpm`, `estimatedImpressions` → recompute server-side from `AD_CONFIG`. A client that
  sends `fixedCpm: 0.01` must not get 100× the impressions.

**Flow, in this order:**
1. Validate. `budget` must be a positive **integer** ≥ `AD_CONFIG.MIN_TOTAL_BUDGET`.
   Validate dates (`endDate > startDate`, `startDate` not in the past).
2. `walletService.debit({ amount: budget, reason: 'campaign_creation' })` — **before** creating
   anything. On `InsufficientCreditsError` → `402` with
   `{ error, code: 'INSUFFICIENT_CREDITS', required, available, shortfall }`.
3. Create `AdCampaign` (`status: 'active'`, `totalBudget: budget`, `spentINR: 0`,
   `advertiserUserId: req.user._id`) and `AdCreative`.
4. **If step 3 throws, refund the debit** and return 500. Wrap 3 in try/catch — a debit with no
   campaign is a customer-visible theft.
5. Backfill `campaignId` onto the ledger row from step 2.
6. `201` with the created ad.

Reuse whatever `adService.getActiveAds` and `creativeRoutes` already expect for creative shape;
don't invent a new creative document format.

### 2.2 Review status decision — **make this call explicitly**

Phase 0 showed that auto-approving at creation is how the old bypass went unnoticed. Two options:

- **`reviewStatus: 'pending'`** — safe, but nothing serves until someone approves, so an admin
  approval endpoint becomes a launch blocker.
- **`reviewStatus: 'approved'`** — ships now, but any user with credits can put arbitrary media
  in the feed.

Recommendation: **`approved` at launch** (credits cost real money, so the spam economics are
bad for an attacker), **plus** an admin `POST /api/ads/creatives/:id/reject` that sets
`isActive: false` and refunds the remaining budget. Revisit before the app has meaningful reach.

### 2.3 Refund unspent budget when a campaign ends

`adStatsBuffer.flushSpend()` already flips exhausted campaigns to `completed`. Add: when a
campaign moves to `completed` **with `spentINR < totalBudget`** (i.e. it ended on `endDate`, not
on budget), refund `Math.floor(totalBudget - spentINR)` credits. Guard with a
`budgetRefundedAt` field on `AdCampaign` so a re-run cannot refund twice.

A campaign that ends early with money still in it is the single most likely support ticket.
Handle it in Phase 2, not "later".

### 2.4 Flip the flag

`AppConfig.adCreationEnabled = true` in `frontend/lib/shared/config/app_config.dart`.
This is the last step of Phase 2, after the endpoint is verified — not before.

Also handle the 402 in `ad_service.dart`: parse `shortfall` and route the user to the top-up
sheet (which lands in Phase 3; until then, show the shortfall and a "coming soon" message).

---

## Phase 2 status — implemented and verified (uncommitted)

**Review-status decision: `approved` at creation**, per §2.2's recommendation and confirmed by
the user. The admin reject + refund endpoint ships alongside it, not later.

Files added: `services/adServices/adCreationService.js`,
`services/adServices/campaignSettlement.js`, `routes/adRoutes/adCreationRoutes.js`.
Changed: `models/AdCampaign.js` (`budgetRefundedAt`), `services/adServices/adStatsBuffer.js`
(exhausted campaigns now close through the settlement path), `loaders/jobs.js` (hourly expiry
sweep), `middleware/adminDashboardAuth.js` (new `requireConfiguredAdminDashboardKey`),
`routes/adRoutes/index.js`. Flutter: `ad_service.dart` (typed 402),
`wallet_model.dart` (`InsufficientCreditsException`), `create_ad_screen_refactored.dart`,
`campaign_settings_widget.dart`, `app_config.dart`.

Endpoints:

| Method | Path | Auth |
|---|---|---|
| `POST` | `/api/ads/create-with-credits` | user token |
| `POST` | `/api/ads/creatives/:id/reject` | admin key (fails closed if unset) |
| `GET` | `/api/ads/creatives/:id/status` | user token, owner only |

**Deviations and additions beyond the spec:**

1. **Nothing was closing a campaign at its `endDate`.** §2.3 assumed `flushSpend` was the only
   path to `completed`, but that only fires on *budget exhaustion* — a campaign that ran out of
   time stayed `active` with the advertiser's money inside it forever. Added
   `expireEndedCampaigns()` in `loaders/jobs.js`. Without it, §2.3's refund would have covered
   a case that never occurs and missed the one that does.

   **Scheduling — read this before changing it.** `fly.toml` runs with
   `auto_stop_machines = 'stop'` and `min_machines_running = 0`, so *any* fixed schedule only
   fires if the machine happens to be awake at that minute. On a low-traffic app it usually is
   not, which means a cron alone can leave refunds unrun indefinitely. So the sweep has two
   triggers: **on boot** (10s after start — the machine is already awake because a real user
   asked for something, so this costs no extra wakeup and gives the best refund latency the
   deployment allows) and **weekly** (`0 3 * * 0`) as a backstop for a machine that stays up.
   An `{ status, endDate, budgetRefundedAt }` index on `AdCampaign` keeps the normal
   "nothing to settle" boot check to one index lookup matching zero documents.

2. **One settlement path, guarded twice.** All three endings (budget exhausted, end date
   reached, creative rejected) go through `settleCampaign()`. It claims the campaign with
   `{ budgetRefundedAt: null }` so concurrent sweeps cannot both proceed, *and* the refund
   carries `externalId: 'campaign_refund:<id>'` so the ledger's unique index rejects a second
   credit even if the claim were cleared. If the refund throws, the claim is released so a
   later sweep retries.

3. **Rejecting one creative does not settle a campaign that has others running.** Refunding a
   budget a sibling creative is still spending would let the campaign overdeliver against money
   already returned.

4. **`cpmINR` is server-owned, and must be.** `adStatsBuffer` charges spend at
   `AD_CONFIG.BANNER_CPM`/`DEFAULT_CPM` regardless of what the campaign says, so a campaign
   carrying a client-supplied CPM would record spend that disagrees with the creator payouts
   that same spend funds. `fixedCpm`, `cpmINR`, and `bidAmount` from the body are ignored.
   `AppConfig.bannerCpm` was **10.0 on the client vs 20 on the server** — corrected to 20, or
   the impression estimate shown to advertisers is double what they get.

5. **`startDate` is clamped, not rejected.** §2.1 says "startDate not in the past", but clients
   send a calendar date at local midnight, which is already hours old on arrival — rejecting it
   would fail every ad created after midnight. Clamping forward is equally safe: serving only
   checks `startDate <= now`.

6. **Media URLs are validated.** Auto-approval means a creative goes straight into the feed, so
   `imageUrl`/`videoUrl`/`imageUrls` must parse, must be `https` (http allowed off-production),
   and — if `AD_MEDIA_ALLOWED_HOSTS` is set — must be on an approved host. The R2 public domain
   is added to that allowlist automatically. **Set `AD_MEDIA_ALLOWED_HOSTS` before launch**;
   without it any https host is accepted.

7. **The UI said "Daily Budget".** The credited amount is the *total* debited at creation, and
   the client's floor was ₹100 against the server's ₹1000 — so a user could fill the form,
   upload media, and only then get a 400. Label, hint, helper text, summary row, and both
   validators now say total and enforce ₹1000, whole rupees.

**Verification actually run** (ephemeral MongoDB; router mounted behind the real
`public, max-age=180` header). **77/77 assertions**, on top of Phase 1's 53 + 25 which were
re-run and still pass:

- happy path: 201, balance debited exactly once, campaign `active` with `totalBudget == debit`
  and `spentINR == 0`, creative `approved`/`isActive`, spend row backfilled with `campaignId`,
  `Cache-Control: no-store`;
- 402 carries `required`/`available`/`shortfall`, balance untouched, no campaign created;
- 9 validation cases (budget < 1000, fractional budget, missing media, banner+video, inverted
  dates, unknown adType, empty title, `javascript:` media URL, carousel with no images) — all
  400 **before** any debit, with balance and ledger unchanged;
- trust boundaries: `fixedCpm: 0.01`, `estimatedImpressions: 999999999`, another user's
  `uploaderId`/`advertiserUserId`, `spentINR: -100000`, `status: 'draft'` — all ignored;
- two parallel creations against a balance covering one → exactly one 201, one 402, one campaign;
- forced creative-write failure → 500, full refund ledgered, orphan campaign deleted;
- campaign ended under budget → refund floored (`2000 − 40.6 → 1959`), `budgetRefundedAt`
  stamped, second sweep a no-op, exactly one refund row;
- three concurrent `settleCampaign` calls → one winner, one refund;
- admin reject → 401 without the key; with it, creative deactivated + `rejectionReason` stored +
  remainder refunded + campaign completed; re-rejecting refunds nothing;
- rejecting one of two creatives → campaign stays active and funded;
- `GET /creatives/:id/status`: owner 200, other user 404, anonymous 401.

`flutter analyze lib/features/ads lib/shared/config` → **0 errors** (one pre-existing
`unused_field` warning in `app_config.dart`, plus the usual `avoid_print` infos).

**`AppConfig.adCreationEnabled` is now `true`.** Ads can be created as soon as a wallet has
credits — which today means an admin grant, until Phase 3 ships in-app purchases.

---

# Phase 3 — RevenueCat / Google Play Billing

**Goal:** users buy credits in-app. This is the phase where real money enters the system.

### 3.1 RevenueCat / Play Console setup (dashboard work, not code)

- Google Play Console → **in-app products** (consumables, *not* subscriptions):
  `ad_credits_30`, `ad_credits_100`.
- RevenueCat → connect the Play service account, create **Offering `ad_credits`** with two
  packages. **Do not create entitlements** — entitlements model "does the user have access",
  which is not what a consumable balance is.
- RevenueCat → Integrations → Webhooks → point at
  `https://<api-host>/api/webhooks/revenuecat`, set an Authorization header secret.
- Configure **transfer behaviour** for the same purchase seen on a second account
  (`Transfer to new App User ID` is the safer default for consumables).

### 3.2 Pricing — gross-up is mandatory

The store takes its cut off the top. If you sell "₹1,000 of credits" for ₹1,000, you receive
₹850 and owe ₹1,000 of inventory. **Every price must be grossed up:**

```
price = credits / (1 − storeFee)
```

| Credits | Fee 15% → min price | Fee 30% → min price | List price | Margin @15% |
|---|---|---|---|---|
| 30  | ₹36  | ₹43  | **₹49**  | ₹11.65 |
| 100 | ₹118 | ₹143 | **₹149** | ₹26.65 |

Both rows clear at **either** fee tier, so the 15%-vs-30% question no longer blocks publishing
prices. Confirm the tier anyway — it decides your actual margin, just not whether you have one.

**Sizing rule: never sell a pack you cannot deliver.** These are small because inventory is the
binding constraint, not willingness to pay. At ~320 billable impressions/day and a ₹20 banner
CPM the platform absorbs about **₹6.40/day** of total ad spend, so 30 credits takes ~5 days to
deliver and 100 takes ~16. The previous 1,000-credit entry tier was five months of inventory and
the 25,000 tier was over a decade — both were refund complaints waiting to be filed.

Size the entry pack from measured throughput, not intuition:

```
credits_entry ≈ dailyBillableImpressions × 14 ÷ 1000 × CPM
```

Add larger tiers back when billable impressions clear ~1,500/day, and **re-measure first** —
this figure has been roughly 2.5x'ing month over month.

**Also unresolved: GST.** Indian digital sales carry 18% GST and the developer-vs-Google
liability depends on your registration. This changes the formula. **Confirm with a CA before
launch** — it is not something to guess at in code.

**Rule that protects you regardless:** the product → credits map lives **server-side only**
(`backend/config/adCreditProducts.js`). Never derive credits from a price the client reports.
If the fee tier or GST answer changes, you re-tune one server file plus Play Console prices, and
no client release is needed.

### 3.3 `POST /api/webhooks/revenuecat`

**Mount before the global `express.json()` at `loaders/express.js:120`**, or with
`express.raw({ type: 'application/json' })` on that path — signature verification needs the
exact bytes.

Checks, in order, all before any DB write:
1. `Authorization` header vs `process.env.REVENUECAT_WEBHOOK_SECRET`, compared with
   `crypto.timingSafeEqual` on equal-length buffers. A `!==` here leaks the secret by timing.
2. `event.type === 'NON_RENEWING_PURCHASE'` (also handle `CANCELLATION` / `REFUND`).
3. **Reject `event.environment === 'SANDBOX'` when `NODE_ENV === 'production'`.** Without this,
   anyone with a test device mints unlimited real credits.
4. `event.product_id` → credits, from the server-side map. Unknown product → log and `200`
   (a `200` stops RevenueCat retrying something that will never succeed; alert instead).
5. Resolve the user from `event.app_user_id`.
6. `walletService.credit({ type:'purchase', source:'revenuecat', externalId: event.id, ... })`.

Always return `200` for anything you've durably recorded, even a duplicate — a non-2xx makes
RevenueCat retry, and the `externalId` index means a retry is harmless anyway.

**Refunds / `CANCELLATION`:** decide the policy explicitly. Recommended — debit the credits back
if the balance covers it; if it doesn't (already spent), allow the balance to go negative via a
`reversal` ledger row and block new campaigns until it clears. Silently absorbing refunds is a
free-money exploit: buy, spend, refund.

### 3.4 Flutter purchase flow

- `purchases_flutter` in `pubspec.yaml`; configure with the Play SDK key at startup.
- **`Purchases.logIn(<our user id>)` before any purchase** so `app_user_id` in the webhook maps
  to a real user. An anonymous purchase is unattributable and becomes a support ticket.
- Top-up sheet: read the `ad_credits` Offering, show packages, `purchasePackage()`.
- After a successful purchase the balance arrives **via the webhook, not the client**. Poll
  `GET /api/ads/wallet` a few times with backoff and show "credits arriving…". Never credit
  from the client's purchase result.
- Handle user-cancelled, pending (slow payment methods), and already-owned.

### 3.5 Reconciliation

`backend/scripts/reconcile-revenuecat.js` — pull recent RevenueCat transactions via their REST
API, find any not present as a `purchase` ledger row, and credit them. Webhooks get dropped;
without this, a user pays and gets nothing. Also runs the §1.6 `applied:false` sweep.

---

## Phase 3 status — code implemented and verified (uncommitted)

**Refund policy decision (§3.3): the recommended one.** A reversal the balance covers is an
ordinary correction. A reversal the balance does *not* cover — because the credits were already
spent on ads — takes the balance **negative** and **freezes the wallet**. Without that, "buy →
spend → refund" is free advertising.

Files added: `config/adCreditProducts.js`, `routes/webhooks/revenuecatRoutes.js`,
`scripts/reconcile-revenuecat.js`, Flutter
`data/services/ad_credit_purchase_service.dart`, `presentation/widgets/wallet/top_up_sheet.dart`.
Changed: `services/adServices/walletService.js` (`reverse()`), `models/AdWallet.js`,
`loaders/express.js`, `app_config.dart`, `wallet_balance_chip.dart`,
`wallet_transactions_screen.dart`, `create_ad_screen_refactored.dart`,
`pubspec.yaml` (`purchases_flutter: ^10.7.0`).

**Deviations and things worth knowing:**

1. **`AdWallet.balance` lost its `min: 0`.** A negative balance is now a legitimate state, so a
   schema floor would block the reversal that creates it. Overdraft protection was never that
   bound anyway — it is the `balance: { $gte: amount }` filter on `debit`, which no positive
   amount satisfies against a negative balance. Spending is blocked twice over while negative:
   by that filter and by the freeze.

2. **The freeze is not automatically lifted.** Buying credits again clears the debt, but
   `status` stays `frozen` until a human unfreezes it. A chargeback should get looked at.

3. **The webhook answers `200` to things it refuses.** Unknown product, unknown user, sandbox in
   production, unhandled event type — all 200. A non-2xx makes RevenueCat retry, and none of
   those become resolvable by retrying. Real failures (a write that did not land) get 500 so
   they *are* retried, and `reconcile-revenuecat.js` sweeps up the rest.

4. **`app_user_id` resolution is wider than the spec.** `app_user_id`, `original_app_user_id`
   and `aliases` are all tried, and RevenueCat's own `$RCAnonymousID:` ids are rejected outright
   — an anonymous purchase cannot be attributed and must not credit a random account.

5. **The SDK key comes from `--dart-define`, never source.**
   `--dart-define=REVENUECAT_ANDROID_KEY=goog_xxx`. With no key,
   `AppConfig.adCreditPurchasesEnabled` is false, every top-up entry point hides itself, and the
   wallet works exactly as it did in Phase 1. This is the direct lesson of the Razorpay keys
   that are still in git history.

6. **The client never credits.** After a successful purchase it polls `GET /api/ads/wallet`
   with backoff (1+2+3+4+5+5s) and compares against the balance *before* the purchase — so it
   stays correct even if the server credits a different amount than the client expected. If the
   webhook has not landed in ~20s the sheet says "credits are on the way" rather than showing a
   balance that is not real.

**Verification actually run** — **62/62** assertions (all four suites re-run together: 53 + 25 +
77 + 62 = **217 passing**). The test app mirrors `loaders/express.js` exactly, webhook mounted
before the global `express.json()`, so the raw-body requirement is exercised rather than assumed:

- product map: known ids resolve, `:base-plan` suffixes tolerated, unknown → `null`, and
  `constructor` / `__proto__` are not products (prototype-pollution probe);
- auth: missing header, wrong secret, a prefix of the secret, and the secret plus one byte all
  401 with no ledger row written — the length cases confirm `timingSafeEqual` does not throw;
- an unset `REVENUECAT_WEBHOOK_SECRET` returns 503, never an open endpoint;
- a valid purchase credits once; a retry of the same event id is a 200 duplicate; **ten
  concurrent deliveries of one event produce one credit and one ledger row**;
- sandbox-in-production, unknown product, unknown user, `$RCAnonymousID:`, and unhandled event
  types are all 200-with-ignored and credit nothing;
- malformed JSON → 400, missing id/type → 400; routes mounted after the raw webhook still parse
  JSON normally;
- refund of unspent credits → balance back to 0, `lifetimePurchased` unwound, wallet **not**
  frozen, retry does not double-debit;
- **buy → spend → refund → balance −5000, wallet frozen, spending blocked, and
  `balance == Σ(ledger)` still holds**;
- a later purchase clears the debt to 0 while the wallet stays frozen pending review;
- eight concurrent cancellations debit exactly once.

`flutter analyze lib/features/ads lib/shared/config` → **0 errors**.

### What is still yours before this can take money

- [ ] Play Console: create the two **consumables** — `ad_credits_30` (₹49) and
      `ad_credits_100` (₹149). The ids must match `config/adCreditProducts.js` exactly.
- [ ] Confirm **GST** treatment before publishing prices. The **15% vs 30%** fee tier no longer
      gates launch — both rows clear at either tier — but confirm it anyway; it sets your margin.
- [ ] RevenueCat: connect the Play service account, create Offering **`ad_credits`** with two
      packages, **no entitlements**.
- [ ] RevenueCat → Webhooks → `https://<api-host>/api/webhooks/revenuecat`, with an
      Authorization header value set as `REVENUECAT_WEBHOOK_SECRET` in Fly secrets.
- [ ] Set `REVENUECAT_API_KEY` (v1 secret key) in Fly secrets, or
      `reconcile-revenuecat.js` cannot recover dropped webhooks — it says so when it runs.
- [ ] Build with `--dart-define=REVENUECAT_ANDROID_KEY=goog_...`.
- [ ] Set RevenueCat **transfer behaviour** to `Transfer to new App User ID` for consumables.
- [ ] Schedule `reconcile-revenuecat.js` (Phase 4). Until then, run it manually after any
      deploy that overlapped a purchase.

---

# Phase 4 — Operations & launch readiness

*(The original Phase 4 — Razorpay web top-up — is dropped.)*

1. **Cron the reconcilers.** Both scripts hourly. Follow the existing cron pattern
   (`recommendationScoreCron.js`, `monthlyNotificationCron.js`).
2. **Alerting on money invariants.** A periodic job asserting, per wallet:
   `balance == Σ(credits) − Σ(debits)` over the ledger. Any drift is a bug that costs money;
   you want to find it before a user does.
3. **Admin surface.** Wallet lookup by user, manual grant/reversal (already built in Phase 1),
   and a list of `applied:false` rows older than an hour.
4. **`dailyBudget` enforcement.** Currently only `totalBudget` is enforced. `dailyBudget` is
   accepted, stored, and ignored — either implement per-day spend tracking or remove the field
   from the UI so it stops being a promise you don't keep.
5. **Delete the `Invoice` model.** Orphaned since Phase 0 but still referenced by
   `campaignRoutes.js` (the `/activate` payment check), `userRoutes.js`, and
   `adCleanupService.js`. Once `create-with-credits` is the only path, `POST /:id/activate`'s
   invoice check is dead code — remove the route or repoint it at the wallet.
6. **Docs.** `AGENTS.md` still says "Payments: Razorpay". `CLAUDE.md` is already updated.

---

## User action items (outside the code)

- [ ] **Rotate/revoke the leaked Razorpay keys.** They were in `app_config.dart` — in git history
      *and* in every already-shipped build. Removing the file does not un-leak them.
- [ ] Run `node backend/scripts/backfill-campaign-spend.js --dry-run` **before** deploying
      Phase 0.5. It reports campaigns with no `totalBudget` and campaigns already over budget —
      both go dark under the new gate. Review that list, then run it for real.
- [ ] Confirm the Play service-fee tier (15% vs 30%) in Play Console.
- [ ] Confirm GST treatment with a CA before setting prices.
- [x] ~~Decide the refund policy (§3.3)~~ — implemented as recommended: negative balance +
      wallet freeze when the refunded credits were already spent.
- [x] ~~Review-status policy (§2.2)~~ — decided: auto-approve at creation.
- [ ] **Set `AD_MEDIA_ALLOWED_HOSTS`** (comma-separated hosts) in Fly secrets. Ads are
      auto-approved, so without an allowlist any https URL can be put in the feed. The R2
      public domain is included automatically when `CLOUDFLARE_R2_PUBLIC_DOMAIN` is set.
- [ ] Confirm `ADMIN_DASHBOARD_KEY` is set in every environment — the grant and reject routes
      return 503 without it, by design.

## Known gaps left deliberately

- `dailyBudget` is not enforced (Phase 4, item 4).
- The `Invoice` model still exists (Phase 4, item 5).
- Two **pre-existing, unrelated** broken imports found during Phase 0 and left alone:
  `adCommentRoutes.js → ../models/Comment.js` and
  `youtubeAuthRoutes.js → ../services/platforms/youtubeService.js`.

---

## Starting a new session

Give it this:

> Read `AD_CREDITS_PLAN.md`. Sections 0 and "Repo facts" are done and uncommitted — don't redo
> them. Implement Phase 1 (wallet ledger). Do not commit anything.

Useful checks that already exist: `node --check <file>` for syntax, and the import-resolution
script pattern from Phase 0 (a small `.mjs` that walks every `import` and resolves it —
`grep -P` does **not** work in this environment's locale). Never `git commit`.
