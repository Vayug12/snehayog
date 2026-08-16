import mongoose from 'mongoose';
import DailyUploadQuota from '../models/DailyUploadQuota.js';
import {
  DAILY_UPLOAD_LIMIT_CODE,
  DEFAULT_DAILY_UPLOAD_LIMIT,
  getIstUploadDayWindow,
  releaseDailyUploadSlot,
  reserveDailyUploadSlot,
} from '../services/uploadServices/dailyUploadQuotaService.js';

describe('daily upload quota', () => {
  const userId = new mongoose.Types.ObjectId();
  const now = new Date('2026-08-16T12:00:00.000Z');

  afterEach(async () => {
    await DailyUploadQuota.deleteMany({ userId });
  });

  test('allows only ten concurrent reservations for one user and IST day', async () => {
    const attempts = Array.from({ length: DEFAULT_DAILY_UPLOAD_LIMIT + 2 }, () => (
      reserveDailyUploadSlot({
        userId,
        uploadId: new mongoose.Types.ObjectId(),
        now,
      })
    ));

    const results = await Promise.allSettled(attempts);
    const accepted = results.filter((result) => result.status === 'fulfilled');
    const rejected = results.filter((result) => result.status === 'rejected');

    expect(accepted).toHaveLength(DEFAULT_DAILY_UPLOAD_LIMIT);
    expect(rejected).toHaveLength(2);
    expect(rejected.every((result) => result.reason.code === DAILY_UPLOAD_LIMIT_CODE)).toBe(true);

    const { dayKey } = getIstUploadDayWindow(now);
    const quota = await DailyUploadQuota.findById(`${userId}:${dayKey}`).lean();
    expect(quota.uploadIds).toHaveLength(DEFAULT_DAILY_UPLOAD_LIMIT);
  });

  test('releases a failed upload slot and resets naturally on the next IST day', async () => {
    const uploadIds = Array.from(
      { length: DEFAULT_DAILY_UPLOAD_LIMIT },
      () => new mongoose.Types.ObjectId()
    );

    for (const uploadId of uploadIds) {
      await reserveDailyUploadSlot({ userId, uploadId, now });
    }

    const { dayKey } = getIstUploadDayWindow(now);
    await releaseDailyUploadSlot({ userId, uploadId: uploadIds[0], dayKey });

    await expect(reserveDailyUploadSlot({
      userId,
      uploadId: new mongoose.Types.ObjectId(),
      now,
    })).resolves.toMatchObject({ dayKey, remaining: 0 });

    const nextIstDay = new Date('2026-08-16T18:30:00.000Z');
    await expect(reserveDailyUploadSlot({
      userId,
      uploadId: new mongoose.Types.ObjectId(),
      now: nextIstDay,
    })).resolves.toMatchObject({ dayKey: '2026-08-17', remaining: 9 });
  });
});
