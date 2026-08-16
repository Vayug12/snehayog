import DailyUploadQuota from '../../models/DailyUploadQuota.js';
import Video from '../../models/Video.js';
import AppConfig from '../../models/AppConfig.js';

export const DEFAULT_DAILY_UPLOAD_LIMIT = 10;
export const DAILY_UPLOAD_TIME_ZONE = 'Asia/Kolkata';
export const DAILY_UPLOAD_LIMIT_CODE = 'DAILY_UPLOAD_LIMIT_REACHED';

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const RETENTION_MS = 24 * 60 * 60 * 1000;
const LIMIT_CACHE_TTL_MS = 5 * 60 * 1000;

let cachedLimit = DEFAULT_DAILY_UPLOAD_LIMIT;
let limitCacheExpiresAt = 0;

const getDailyUploadLimit = async () => {
  if (Date.now() < limitCacheExpiresAt) return cachedLimit;

  try {
    const environment = process.env.NODE_ENV === 'development' ? 'development' : 'production';
    const config = await AppConfig.getLatestConfig(environment);
    const configuredLimit = Number(config?.businessRules?.uploadLimits?.maxDailyUploads);
    cachedLimit = Number.isInteger(configuredLimit) && configuredLimit > 0
      ? configuredLimit
      : DEFAULT_DAILY_UPLOAD_LIMIT;
  } catch (error) {
    console.warn('Failed to load daily upload limit from AppConfig; using default:', error.message);
    cachedLimit = DEFAULT_DAILY_UPLOAD_LIMIT;
  }

  limitCacheExpiresAt = Date.now() + LIMIT_CACHE_TTL_MS;
  return cachedLimit;
};

export class DailyUploadLimitError extends Error {
  constructor(resetAt, limit = DEFAULT_DAILY_UPLOAD_LIMIT) {
    super(`You have reached today's limit of ${limit} uploads. You can upload again after 12:00 AM IST.`);
    this.name = 'DailyUploadLimitError';
    this.statusCode = 429;
    this.code = DAILY_UPLOAD_LIMIT_CODE;
    this.limit = limit;
    this.resetAt = resetAt;
  }
}

export const getIstUploadDayWindow = (now = new Date()) => {
  const instant = now instanceof Date ? now : new Date(now);
  if (Number.isNaN(instant.getTime())) {
    throw new TypeError('A valid date is required');
  }

  const shifted = new Date(instant.getTime() + IST_OFFSET_MS);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth();
  const day = shifted.getUTCDate();
  const dayKey = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  const startAt = new Date(Date.UTC(year, month, day) - IST_OFFSET_MS);
  const resetAt = new Date(Date.UTC(year, month, day + 1) - IST_OFFSET_MS);

  return { dayKey, startAt, resetAt };
};

const quotaDocumentId = (userId, dayKey) => `${userId.toString()}:${dayKey}`;
const uploadToken = (uploadId) => uploadId.toString();

const ensureDailyQuotaDocument = async ({ userId, dayKey, startAt, resetAt }) => {
  const _id = quotaDocumentId(userId, dayKey);
  const existing = await DailyUploadQuota.exists({ _id });
  if (existing) return _id;

  const existingUploads = await Video.find({
    uploader: userId,
    uploadedAt: { $gte: startAt, $lt: resetAt },
    processingStatus: { $ne: 'failed' },
  }).select('_id').lean();

  try {
    await DailyUploadQuota.updateOne(
      { _id },
      {
        $setOnInsert: {
          userId,
          dayKey,
          uploadIds: existingUploads.map((video) => video._id.toString()),
          expiresAt: new Date(resetAt.getTime() + RETENTION_MS),
        },
      },
      { upsert: true }
    );
  } catch (error) {
    if (error?.code !== 11000) throw error;
  }

  return _id;
};

export const reserveDailyUploadSlot = async ({ userId, uploadId, now = new Date() }) => {
  if (!userId || !uploadId) {
    throw new TypeError('userId and uploadId are required to reserve an upload slot');
  }

  const { dayKey, startAt, resetAt } = getIstUploadDayWindow(now);
  const _id = await ensureDailyQuotaDocument({ userId, dayKey, startAt, resetAt });
  const token = uploadToken(uploadId);
  const limit = await getDailyUploadLimit();

  const quota = await DailyUploadQuota.findOneAndUpdate(
    {
      _id,
      uploadIds: { $ne: token },
      $expr: {
        $lt: [
          { $size: { $ifNull: ['$uploadIds', []] } },
          limit,
        ],
      },
    },
    { $push: { uploadIds: token } },
    { new: true }
  ).lean();

  if (quota) {
    return {
      dayKey,
      resetAt,
      remaining: Math.max(0, limit - quota.uploadIds.length),
    };
  }

  const existingReservation = await DailyUploadQuota.exists({ _id, uploadIds: token });
  if (existingReservation) {
    const current = await DailyUploadQuota.findById(_id).select('uploadIds').lean();
    return {
      dayKey,
      resetAt,
      remaining: Math.max(0, limit - (current?.uploadIds?.length || 0)),
    };
  }

  throw new DailyUploadLimitError(resetAt, limit);
};

export const assertDailyUploadAvailable = async ({ userId, now = new Date() }) => {
  if (!userId) {
    throw new TypeError('userId is required to check upload availability');
  }

  const { dayKey, startAt, resetAt } = getIstUploadDayWindow(now);
  const _id = await ensureDailyQuotaDocument({ userId, dayKey, startAt, resetAt });
  const limit = await getDailyUploadLimit();
  const quota = await DailyUploadQuota.findById(_id)
    .select('uploadIds')
    .lean();

  if ((quota?.uploadIds?.length || 0) >= limit) {
    throw new DailyUploadLimitError(resetAt, limit);
  }

  return {
    dayKey,
    resetAt,
    remaining: limit - (quota?.uploadIds?.length || 0),
  };
};

export const releaseDailyUploadSlot = async ({ userId, uploadId, dayKey }) => {
  if (!userId || !uploadId || !dayKey) return false;

  const result = await DailyUploadQuota.updateOne(
    { _id: quotaDocumentId(userId, dayKey), uploadIds: uploadToken(uploadId) },
    { $pull: { uploadIds: uploadToken(uploadId) } }
  );

  return result.modifiedCount > 0;
};

export const releaseUploadSlotForVideo = async (video) => {
  if (!video?.uploader || !video?._id) return false;

  const dayKey = video.uploadQuotaDay
    || (video.uploadedAt ? getIstUploadDayWindow(video.uploadedAt).dayKey : null);
  if (!dayKey) return false;

  return releaseDailyUploadSlot({
    userId: video.uploader,
    uploadId: video._id,
    dayKey,
  });
};

export const sendDailyUploadLimitResponse = (res, error) => {
  const resetAt = error.resetAt instanceof Date ? error.resetAt : new Date(error.resetAt);
  const retryAfterSeconds = Math.max(1, Math.ceil((resetAt.getTime() - Date.now()) / 1000));

  res.set('Retry-After', String(retryAfterSeconds));
  res.set('X-RateLimit-Limit', String(error.limit));
  res.set('X-RateLimit-Remaining', '0');
  res.set('X-RateLimit-Reset', String(Math.ceil(resetAt.getTime() / 1000)));

  return res.status(429).json({
    success: false,
    error: error.message,
    message: error.message,
    code: DAILY_UPLOAD_LIMIT_CODE,
    limit: error.limit,
    timeZone: DAILY_UPLOAD_TIME_ZONE,
    resetAt: resetAt.toISOString(),
  });
};
