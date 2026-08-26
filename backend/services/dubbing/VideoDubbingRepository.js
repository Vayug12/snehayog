import mongoose from 'mongoose';
import User from '../../models/User.js';
import Video from '../../models/Video.js';
import DubbingError from './DubbingError.js';

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export default class VideoDubbingRepository {
  async resolveChannel({ channelName, channelId }) {
    if (channelId) {
      if (!mongoose.isValidObjectId(channelId)) {
        throw new DubbingError('INVALID_CHANNEL_ID', 'The supplied channel ID is not a valid MongoDB ObjectId.');
      }
      const channel = await User.findById(channelId).select('_id name').lean();
      if (!channel) throw new DubbingError('CHANNEL_NOT_FOUND', `No channel found for ID ${channelId}.`);
      return channel;
    }

    const trimmedName = String(channelName || '').trim();
    if (!trimmedName) throw new DubbingError('CHANNEL_REQUIRED', '--channel is required.');
    const exactName = new RegExp(`^${escapeRegex(trimmedName)}$`, 'i');
    const matches = await User.find({ name: exactName }).select('_id name').limit(3).lean();
    if (matches.length === 0) {
      throw new DubbingError('CHANNEL_NOT_FOUND', `No channel found with exact name "${trimmedName}".`);
    }
    if (matches.length > 1) {
      const ids = matches.map((channel) => `${channel.name}: ${channel._id}`).join(', ');
      throw new DubbingError(
        'AMBIGUOUS_CHANNEL',
        `Multiple channels use that name. Retry with --channel-id. Matches: ${ids}`,
      );
    }
    return matches[0];
  }

  async listChannelVideos(channelId) {
    return Video.find({
      uploader: channelId,
      $or: [
        { mediaType: 'video' },
        { mediaType: { $exists: false } },
      ],
    })
      .select('_id videoName duration language mediaType canonicalMp4Url canonicalMp4Key videoHash dubbedUrls uploadedAt')
      .sort({ uploadedAt: 1, _id: 1 })
      .lean();
  }

  async setDubbedUrl(videoId, targetLanguage, dubbedUrl, { force = false } = {}) {
    const field = `dubbedUrls.${targetLanguage}`;
    const filter = { _id: videoId };
    if (!force) {
      filter.$or = [
        { [field]: { $exists: false } },
        { [field]: null },
        { [field]: '' },
      ];
    }
    const result = await Video.updateOne(filter, { $set: { [field]: dubbedUrl } });
    if (result.matchedCount === 0) {
      throw new DubbingError(
        'DUBBED_URL_CONFLICT',
        `A dubbed URL for ${targetLanguage} was written by another process; refusing to overwrite it.`,
      );
    }
    return result;
  }
}
