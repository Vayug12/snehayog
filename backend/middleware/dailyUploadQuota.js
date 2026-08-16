import {
  assertDailyUploadAvailable,
  DAILY_UPLOAD_LIMIT_CODE,
  sendDailyUploadLimitResponse,
} from '../services/uploadServices/dailyUploadQuotaService.js';

export const enforceDailyUploadAvailability = async (req, res, next) => {
  try {
    const userId = req.user?._id;
    if (!userId) return next();

    const quota = await assertDailyUploadAvailable({ userId });
    res.set('X-RateLimit-Remaining', String(quota.remaining));
    return next();
  } catch (error) {
    if (error.code === DAILY_UPLOAD_LIMIT_CODE) {
      return sendDailyUploadLimitResponse(res, error);
    }
    return next(error);
  }
};
