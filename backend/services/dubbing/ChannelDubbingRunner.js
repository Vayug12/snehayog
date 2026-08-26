import DubbingError from './DubbingError.js';
import { getDubbedUrl, normalizeTargetLanguage } from './languageConfig.js';

function hasCanonicalMp4(video) {
  return Boolean(String(video.canonicalMp4Key || '').trim() || String(video.canonicalMp4Url || '').trim());
}

export default class ChannelDubbingRunner {
  constructor({ repository, pipeline = null, maxVideoSeconds = 600, logger = console }) {
    this.repository = repository;
    this.pipeline = pipeline;
    this.maxVideoSeconds = maxVideoSeconds;
    this.logger = logger;
  }

  async preflight({ channelName, channelId, targetLanguage, force = false, limit = null }) {
    const target = normalizeTargetLanguage(targetLanguage);
    const channel = await this.repository.resolveChannel({ channelName, channelId });
    const videos = await this.repository.listChannelVideos(channel._id);
    const cached = [];
    const missingCanonical = [];
    const tooLong = [];
    const eligible = [];

    for (const video of videos) {
      if (getDubbedUrl(video.dubbedUrls, target) && !force) {
        cached.push(video);
      } else if (!hasCanonicalMp4(video)) {
        missingCanonical.push(video);
      } else if (Number(video.duration) > this.maxVideoSeconds) {
        tooLong.push(video);
      } else {
        eligible.push(video);
      }
    }

    const selected = Number.isInteger(limit) ? eligible.slice(0, limit) : eligible;
    return {
      channel,
      targetLanguage: target,
      force,
      totalVideos: videos.length,
      cached,
      missingCanonical,
      tooLong,
      eligible,
      selected,
      totalSelectedSeconds: selected.reduce((sum, video) => sum + (Number(video.duration) || 0), 0),
    };
  }

  async run(preflight, { runId, failFast = false, signal } = {}) {
    if (!this.pipeline) throw new DubbingError('PIPELINE_NOT_CONFIGURED', 'Dubbing pipeline is not configured.');
    const summary = {
      selected: preflight.selected.length,
      completed: 0,
      skipped: preflight.cached.length,
      failed: 0,
      notSuitable: preflight.missingCanonical.length + preflight.tooLong.length,
      azureSourceCharacters: 0,
      audioSeconds: 0,
      failures: [],
    };

    for (let index = 0; index < preflight.selected.length; index += 1) {
      if (signal?.aborted) throw new DubbingError('CANCELLED', 'Channel dubbing interrupted.');
      const video = preflight.selected[index];
      this.logger.info?.(`[batch] ${index + 1}/${preflight.selected.length}: ${video.videoName || video._id}`);
      try {
        const result = await this.pipeline.runVideo(video, {
          targetLanguage: preflight.targetLanguage,
          force: preflight.force,
          runId,
          signal,
        });
        if (result.status === 'completed') {
          summary.completed += 1;
          summary.azureSourceCharacters += result.azureSourceCharacters || 0;
          summary.audioSeconds += result.audioSeconds || 0;
        } else if (result.status === 'skipped') {
          summary.skipped += 1;
        } else {
          summary.notSuitable += 1;
          this.logger.warn?.(`[batch] not suitable: ${video._id} (${result.reason})`);
        }
      } catch (error) {
        if (error.code === 'CANCELLED' || signal?.aborted) throw error;
        summary.failed += 1;
        summary.failures.push({
          videoId: String(video._id),
          videoName: video.videoName || '',
          code: error.code || 'DUBBING_FAILED',
          message: error.message,
        });
        this.logger.error?.(`[batch] failed ${video._id}: ${error.code || 'DUBBING_FAILED'} ${error.message}`);
        if (failFast) throw error;
      }
    }

    return summary;
  }
}
