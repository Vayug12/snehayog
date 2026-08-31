import AdCampaign from '../../models/AdCampaign.js';
import AdCreative from '../../models/AdCreative.js';
import AdCreditTransaction from '../../models/AdCreditTransaction.js';
import walletService from './walletService.js';
import { AD_CONFIG } from '../../constants/index.js';

/**
 * Create an ad campaign paid for out of the advertiser's prepaid credit wallet.
 *
 * This replaces the deleted `createAdWithPayment`, whose defect was structural:
 * it marked the campaign active *before* payment, so the payment step was
 * decorative. Here the debit happens first and the campaign only exists if the
 * money moved — and if creation then fails, the debit is refunded.
 *
 * Everything in the request body that decides how much inventory the ad gets
 * (CPM, impressions) or who owns it (uploaderId, advertiserUserId) is ignored
 * and recomputed from the token and server config. A client that could set its
 * own CPM could buy the whole feed for ₹1.
 */

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const DEFAULT_FLIGHT_DAYS = 30;
const DEFAULT_VIDEO_DURATION_SEC = 15;
const MAX_CAROUSEL_SLIDES = 10;
const BANNER_TITLE_MAX_WORDS = 30;
const BANNER_TITLE_MAX_CHARS = 150;

const AD_TYPES = new Set(['banner', 'carousel', 'video feed ad']);

export class AdValidationError extends Error {
  constructor(message, field = null) {
    super(message);
    this.name = 'AdValidationError';
    this.statusCode = 400;
    this.code = 'AD_VALIDATION_FAILED';
    this.field = field;
  }
}

export class AdCreationConflictError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'AdCreationConflictError';
    this.statusCode = 409;
    this.code = code;
  }
}

/** Rupees per 1000 delivered views, by ad type. */
export const cpmForAdType = (adType) => (adType === 'banner'
  ? (AD_CONFIG?.BANNER_CPM ?? 20)
  : (AD_CONFIG?.DEFAULT_CPM ?? 30));

const trimmed = (value) => (typeof value === 'string' ? value.trim() : '');

/**
 * Hosts an ad creative may point at.
 *
 * Ads are auto-approved and land straight in the feed, so an unrestricted media
 * URL would let anyone with credits serve arbitrary remote content to users.
 * Configure `AD_MEDIA_ALLOWED_HOSTS` (comma separated) to close that; the R2
 * public domain is included automatically when it is set.
 */
const allowedMediaHosts = () => {
  const hostOf = (value) => {
    const raw = trimmed(value);
    if (!raw) return null;
    try {
      return new URL(raw.includes('://') ? raw : `https://${raw}`).host.toLowerCase();
    } catch {
      return null;
    }
  };

  const hosts = String(process.env.AD_MEDIA_ALLOWED_HOSTS || '')
    .split(',')
    .map(hostOf)
    .filter(Boolean);

  const r2Host = hostOf(process.env.CLOUDFLARE_R2_PUBLIC_DOMAIN);
  if (r2Host) hosts.push(r2Host);

  return new Set(hosts);
};

/**
 * @param {string} url
 * @param {string} field  Name used in the error message
 * @param {Set<string>} allowlist
 */
const assertMediaUrl = (url, field, allowlist) => {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    throw new AdValidationError(`${field} must be a valid URL`, field);
  }

  // `javascript:` and `data:` in a feed-rendered creative are an XSS vector on
  // any surface that treats the value as a link rather than an image source.
  const allowInsecure = process.env.NODE_ENV !== 'production';
  if (parsed.protocol !== 'https:' && !(allowInsecure && parsed.protocol === 'http:')) {
    throw new AdValidationError(`${field} must be an https URL`, field);
  }

  if (allowlist.size > 0 && !allowlist.has(parsed.host.toLowerCase())) {
    throw new AdValidationError(`${field} must be hosted on an approved domain`, field);
  }

  return parsed.toString();
};

/** Optional click-through link. Empty is allowed — not every ad has a destination. */
const normaliseLink = (link) => {
  const raw = trimmed(link);
  if (!raw) return '';

  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw new AdValidationError('link must be a valid URL', 'link');
  }

  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new AdValidationError('link must be an http or https URL', 'link');
  }

  return parsed.toString();
};

/** Label inferred from the destination, matching what the old flow produced. */
const callToActionLabelFor = (link) => {
  const url = link.toLowerCase();
  if (url.includes('shop') || url.includes('buy') || url.includes('purchase')) return 'Shop Now';
  if (url.includes('download')) return 'Download';
  if (url.includes('signup') || url.includes('register')) return 'Sign Up';
  return 'Learn More';
};

const parseDate = (value) => {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

const clampInt = (value, min, max, fallback) => {
  const num = Number(value);
  if (!Number.isFinite(num)) return fallback;
  return Math.min(max, Math.max(min, Math.round(num)));
};

const stringList = (value, { max = 50 } = {}) => {
  if (!Array.isArray(value)) return [];
  return value
    .map(trimmed)
    .filter(Boolean)
    .slice(0, max);
};

const enumOr = (value, allowed, fallback) => (
  allowed.includes(value) ? value : fallback
);

/**
 * Turn a request body into the exact documents to persist.
 *
 * Pure: it reads config and the body, and returns plain objects. Nothing is
 * written and no money moves, so it is safe to run before the debit — which is
 * the point. A validation failure after the debit would mean refunding a
 * customer for our own 400.
 */
export const buildAdSpec = (body, { googleId, userObjectId }) => {
  const title = trimmed(body.title);
  const description = trimmed(body.description);
  const adType = trimmed(body.adType);

  if (!title) throw new AdValidationError('title is required', 'title');
  if (!description) throw new AdValidationError('description is required', 'description');
  if (!AD_TYPES.has(adType)) {
    throw new AdValidationError(
      `adType must be one of: ${[...AD_TYPES].join(', ')}`,
      'adType'
    );
  }

  if (adType === 'banner') {
    if (title.length > BANNER_TITLE_MAX_CHARS) {
      throw new AdValidationError(
        `Banner titles are limited to ${BANNER_TITLE_MAX_CHARS} characters`,
        'title'
      );
    }
    if (title.split(/\s+/).length > BANNER_TITLE_MAX_WORDS) {
      throw new AdValidationError(
        `Banner titles are limited to ${BANNER_TITLE_MAX_WORDS} words`,
        'title'
      );
    }
  }

  // --- Budget ------------------------------------------------------------
  // Credits are whole rupees, so a fractional budget cannot be debited. The
  // client sends a double; an integral double is fine, 999.5 is not.
  const budget = Number(body.budget);
  if (!Number.isFinite(budget) || !Number.isInteger(budget)) {
    throw new AdValidationError('budget must be a whole number of credits', 'budget');
  }
  if (budget < AD_CONFIG.MIN_TOTAL_BUDGET) {
    throw new AdValidationError(
      `budget must be at least ${AD_CONFIG.MIN_TOTAL_BUDGET} credits`,
      'budget'
    );
  }

  // --- Flight window -----------------------------------------------------
  const now = new Date();
  const requestedStart = parseDate(body.startDate);
  const requestedEnd = parseDate(body.endDate);

  // A start date is clamped rather than rejected. Clients send a calendar date
  // at local midnight, which is already hours in the past by the time it
  // arrives — rejecting it would fail every ad created after midnight. Clamping
  // forward is safe because serving only ever checks `startDate <= now`.
  const startDate = requestedStart && requestedStart > now ? requestedStart : now;
  const endDate = requestedEnd || new Date(now.getTime() + DEFAULT_FLIGHT_DAYS * MS_PER_DAY);

  if (endDate <= startDate) {
    throw new AdValidationError('endDate must be after startDate', 'endDate');
  }
  if (endDate <= now) {
    throw new AdValidationError('endDate must be in the future', 'endDate');
  }

  const flightDays = Math.max(1, Math.ceil((endDate - startDate) / MS_PER_DAY));

  // --- Media -------------------------------------------------------------
  const allowlist = allowedMediaHosts();
  const isCarousel = adType === 'carousel';

  let slides = [];
  let cloudinaryUrl = null;
  let thumbnail = null;
  let mediaType = 'image';

  if (isCarousel) {
    const urls = stringList(body.imageUrls, { max: MAX_CAROUSEL_SLIDES });
    if (urls.length === 0) {
      throw new AdValidationError('carousel ads require at least one image', 'imageUrls');
    }
    slides = urls.map((url, index) => ({
      mediaUrl: assertMediaUrl(url, `imageUrls[${index}]`, allowlist),
      thumbnail: assertMediaUrl(url, `imageUrls[${index}]`, allowlist),
      mediaType: 'image',
      aspectRatio: '9:16',
      title,
      description
    }));
  } else {
    const videoUrl = trimmed(body.videoUrl);
    const imageUrl = trimmed(body.imageUrl);

    if (!videoUrl && !imageUrl) {
      throw new AdValidationError('imageUrl or videoUrl is required', 'imageUrl');
    }
    // The model rejects this too, but only after the wallet has been debited.
    if (adType === 'banner' && videoUrl) {
      throw new AdValidationError('banner ads can only use images', 'videoUrl');
    }

    mediaType = videoUrl ? 'video' : 'image';
    cloudinaryUrl = assertMediaUrl(videoUrl || imageUrl, videoUrl ? 'videoUrl' : 'imageUrl', allowlist);
    thumbnail = imageUrl ? assertMediaUrl(imageUrl, 'imageUrl', allowlist) : undefined;
  }

  const link = normaliseLink(body.link);

  // --- Pricing -----------------------------------------------------------
  // CPM is server-owned and must equal what adStatsBuffer charges per delivered
  // view. If a campaign could carry a different CPM, its recorded spend would
  // diverge from the creator payouts funded by that same spend.
  const cpmINR = cpmForAdType(adType);
  const estimatedImpressions = Math.floor((budget / cpmINR) * 1000);

  // dailyBudget is a required field and is not yet enforced during serving
  // (tracked as a known gap). Derived so it is at least self-consistent.
  const dailyBudget = Math.max(
    AD_CONFIG.MIN_DAILY_BUDGET,
    Math.floor(budget / flightDays)
  );

  const campaignData = {
    name: title,
    advertiserUserId: userObjectId,
    objective: enumOr(body.objective, ['awareness', 'consideration', 'conversion'], 'awareness'),
    status: 'active',
    startDate,
    endDate,
    dailyBudget,
    totalBudget: budget,
    spentINR: 0,
    bidType: enumOr(body.bidType, ['CPM', 'CPC'], AD_CONFIG.DEFAULT_BID_TYPE || 'CPM'),
    cpmINR,
    target: {
      age: {
        min: clampInt(body.minAge, 13, 65, 18),
        max: clampInt(body.maxAge, 13, 65, 65)
      },
      gender: enumOr(body.gender, ['all', 'male', 'female', 'other'], 'all'),
      locations: stringList(body.locations),
      interests: stringList(body.interests),
      platforms: stringList(body.platforms).filter((p) => ['android', 'ios', 'web'].includes(p)),
      deviceType: enumOr(body.deviceType, ['mobile', 'tablet', 'desktop', 'all'], 'all')
    },
    optimizationGoal: enumOr(body.optimizationGoal, ['clicks', 'impressions', 'conversions'], 'impressions'),
    timeZone: trimmed(body.timeZone) || 'Asia/Kolkata',
    dayParting: body.dayParting && typeof body.dayParting === 'object' ? body.dayParting : {},
    hourParting: body.hourParting && typeof body.hourParting === 'object' ? body.hourParting : {},
    pacing: enumOr(body.pacing, ['smooth', 'asap'], 'smooth'),
    frequencyCap: clampInt(body.frequencyCap, AD_CONFIG.MIN_FREQUENCY_CAP, AD_CONFIG.MAX_FREQUENCY_CAP, 3)
  };

  if (campaignData.target.age.max < campaignData.target.age.min) {
    throw new AdValidationError('maxAge must be greater than or equal to minAge', 'maxAge');
  }
  if (campaignData.target.platforms.length === 0) {
    campaignData.target.platforms = ['android', 'ios', 'web'];
  }

  const creativeData = {
    adType,
    type: mediaType,
    title,
    callToAction: {
      label: enumOr(
        trimmed(body.callToActionLabel),
        ['Learn More', 'Shop Now', 'Download', 'Sign Up', 'Get Started', 'Watch More'],
        callToActionLabelFor(link)
      ),
      url: link
    },
    // Auto-approved: credits cost real money, so the spam economics already
    // work against an attacker. The backstop is the admin reject endpoint,
    // which pulls the creative and refunds the remaining budget.
    reviewStatus: 'approved',
    isActive: true
  };

  if (isCarousel) {
    creativeData.slides = slides;
  } else {
    creativeData.cloudinaryUrl = cloudinaryUrl;
    creativeData.thumbnail = thumbnail;
    creativeData.aspectRatio = enumOr(trimmed(body.aspectRatio), ['16:9', '9:16', '1:1', '4:3', '3:4'], '9:16');
    if (mediaType === 'video') {
      creativeData.durationSec = clampInt(body.durationSec, 1, 60, DEFAULT_VIDEO_DURATION_SEC);
    }
  }

  return {
    campaignData,
    creativeData,
    budget,
    cpmINR,
    estimatedImpressions,
    flightDays,
    googleId
  };
};

/**
 * Validate, charge, then create. In that order, and not negotiable:
 *
 *  - validating after the debit would mean refunding customers for our 400s;
 *  - creating before the debit is exactly the bug this endpoint replaces.
 *
 * If persistence fails after the debit, the credits go back before the error
 * is returned. A debit with no campaign is money taken for nothing.
 */
export const createAdWithCredits = async (body, { googleId, userObjectId }) => {
  const spec = buildAdSpec(body, { googleId, userObjectId });
  const idempotencyKey = trimmed(body.idempotencyKey);
  if (!/^[A-Za-z0-9._:-]{16,128}$/.test(idempotencyKey)) {
    throw new AdValidationError(
      'idempotencyKey must be 16-128 URL-safe characters',
      'idempotencyKey'
    );
  }

  const debitExternalId = `campaign_create:${userObjectId}:${idempotencyKey}`;

  // Throws InsufficientCreditsError (402) — the route turns that into a
  // shortfall response the client can act on.
  const { transaction, duplicate } = await walletService.debit({
    userId: userObjectId,
    amount: spec.budget,
    reason: 'campaign_creation',
    externalId: debitExternalId,
    metadata: { creationState: 'started', idempotencyKey }
  });

  if (duplicate) {
    const existingCampaign = await AdCampaign.findOne({
      advertiserUserId: userObjectId,
      idempotencyKey
    });

    if (existingCampaign) {
      const existingCreative = await AdCreative.findOne({ campaignId: existingCampaign._id });
      if (existingCreative) {
        return { campaign: existingCampaign, creative: existingCreative, spec, duplicate: true };
      }
    }

    if (transaction.metadata?.creationState === 'failed') {
      throw new AdCreationConflictError(
        'The previous creation attempt was refunded. Retry with a new request.',
        'AD_CREATION_RETRY_REQUIRED'
      );
    }

    throw new AdCreationConflictError(
      'This campaign creation is still processing. Retry shortly.',
      'AD_CREATION_IN_PROGRESS'
    );
  }

  let campaign;
  let creative;

  try {
    campaign = await AdCampaign.create({ ...spec.campaignData, idempotencyKey });
    creative = await AdCreative.create({ ...spec.creativeData, campaignId: campaign._id });
  } catch (err) {
    // Roll back in reverse order, then return the credits.
    if (creative?._id) {
      await AdCreative.deleteOne({ _id: creative._id }).catch(() => {});
    }
    if (campaign?._id) {
      await AdCampaign.deleteOne({ _id: campaign._id }).catch(() => {});
    }

    let creationState = 'failed';
    try {
      await walletService.refund({
        userId: userObjectId,
        amount: spec.budget,
        reason: 'campaign_creation_failed',
        externalId: `campaign_create_rollback:${transaction._id}`,
        metadata: {
          failedWith: err.message,
          originalSpendTransactionId: String(transaction._id)
        }
      });
    } catch (refundErr) {
      creationState = 'refund_pending';
      console.error('❌ CRITICAL: campaign creation failed and the refund also failed', {
        userId: String(userObjectId),
        amount: spec.budget,
        transactionId: String(transaction._id),
        createError: err.message,
        refundError: refundErr.message
      });
    }

    await AdCreditTransaction.updateOne(
      { _id: transaction._id },
      {
        $set: {
          'metadata.creationState': creationState,
          'metadata.creationError': err.message
        }
      }
    ).catch(() => {});

    throw err;
  }

  // Link the spend row to what it bought. Best effort — the campaign exists and
  // the money moved either way, and the ledger row is already correct without it.
  await AdCreditTransaction.updateOne(
    { _id: transaction._id },
    {
      $set: {
        campaignId: campaign._id,
        'metadata.creationState': 'completed'
      }
    }
  ).catch((err) => {
    console.warn(`⚠️ adCreationService: could not backfill campaignId on ${transaction._id}: ${err.message}`);
  });

  return { campaign, creative, spec };
};

export default {
  buildAdSpec,
  createAdWithCredits,
  cpmForAdType,
  AdValidationError,
  AdCreationConflictError
};
