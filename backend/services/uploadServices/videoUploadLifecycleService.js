import Video from '../../models/Video.js';
import {
  releaseDailyUploadSlot,
  releaseUploadSlotForVideo,
  reserveDailyUploadSlot,
} from './dailyUploadQuotaService.js';

export const saveVideoWithDailyQuota = async (video) => {
  const reservation = await reserveDailyUploadSlot({
    userId: video.uploader,
    uploadId: video._id,
  });

  video.uploadQuotaDay = reservation.dayKey;

  try {
    await video.save();
    return video;
  } catch (error) {
    await releaseDailyUploadSlot({
      userId: video.uploader,
      uploadId: video._id,
      dayKey: reservation.dayKey,
    }).catch((releaseError) => {
      console.error('Failed to release upload quota after save error:', releaseError.message);
    });
    throw error;
  }
};

export const markVideoUploadFailed = async (videoId, error) => {
  const message = error instanceof Error ? error.message : String(error || 'Upload processing failed');
  const video = await Video.findByIdAndUpdate(
    videoId,
    {
      processingStatus: 'failed',
      processingError: message,
    },
    { new: true }
  ).select('+uploadQuotaDay');

  if (video) {
    await releaseUploadSlotForVideo(video);
  }

  return video;
};

export const saveVideoRetryWithDailyQuota = async (video) => {
  const reservation = await reserveDailyUploadSlot({
    userId: video.uploader,
    uploadId: video._id,
  });

  video.uploadQuotaDay = reservation.dayKey;

  try {
    await video.save();
    return video;
  } catch (error) {
    await releaseDailyUploadSlot({
      userId: video.uploader,
      uploadId: video._id,
      dayKey: reservation.dayKey,
    }).catch((releaseError) => {
      console.error('Failed to release retry upload quota after save error:', releaseError.message);
    });
    throw error;
  }
};
