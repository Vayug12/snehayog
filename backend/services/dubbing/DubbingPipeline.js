import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import DubbingError, { toDubbingError } from './DubbingError.js';
import { getDubbedUrl, getLanguageConfig, normalizeSourceLanguage } from './languageConfig.js';

function safeKeyPart(value, fallback) {
  const sanitized = String(value || '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  return sanitized || fallback;
}

function sourceFingerprint(video, sourceKey) {
  if (video.videoHash) return safeKeyPart(video.videoHash, 'source').slice(0, 24);
  return crypto.createHash('sha256').update(String(sourceKey)).digest('hex').slice(0, 16);
}

export default class DubbingPipeline {
  constructor({
    config,
    workspaceManager,
    storage,
    repository,
    sttProvider,
    translationProvider,
    ttsProvider,
    mediaTools,
    logger = console,
  }) {
    this.config = config;
    this.workspaceManager = workspaceManager;
    this.storage = storage;
    this.repository = repository;
    this.sttProvider = sttProvider;
    this.translationProvider = translationProvider;
    this.ttsProvider = ttsProvider;
    this.mediaTools = mediaTools;
    this.logger = logger;
  }

  stage(video, name) {
    this.logger.info?.(`[dub:${video._id}] ${name}`);
  }

  async runVideo(video, { targetLanguage, force = false, runId, signal } = {}) {
    const existingUrl = getDubbedUrl(video.dubbedUrls, targetLanguage);
    if (existingUrl && !force) {
      return { status: 'skipped', reason: 'cache_hit', dubbedUrl: existingUrl };
    }

    const language = getLanguageConfig(targetLanguage);
    const workspace = await this.workspaceManager.create(video._id);
    let pipelineError = null;

    try {
      if (signal?.aborted) throw new DubbingError('CANCELLED', 'Operation cancelled.');
      const inputPath = path.join(workspace, 'source.mp4');
      const speechPath = path.join(workspace, 'speech.flac');
      const outputPath = path.join(workspace, 'dubbed.mp4');

      this.stage(video, 'downloading source from R2');
      const source = await this.storage.downloadSource(video, inputPath, signal);

      this.stage(video, 'probing source media');
      const sourceMetadata = await this.mediaTools.probe(inputPath, signal);
      if (!sourceMetadata.hasVideo) throw new DubbingError('VIDEO_STREAM_MISSING', 'Source MP4 has no video stream.');
      if (!sourceMetadata.hasAudio) {
        return { status: 'not_suitable', reason: 'no_audio_stream' };
      }
      if (!Number.isFinite(sourceMetadata.durationSeconds) || sourceMetadata.durationSeconds <= 0) {
        throw new DubbingError('INVALID_VIDEO_DURATION', 'Source MP4 duration is invalid.');
      }
      if (sourceMetadata.durationSeconds > this.config.maxVideoSeconds) {
        return { status: 'not_suitable', reason: 'video_too_long' };
      }
      const videoDurationMs = Math.round(sourceMetadata.durationSeconds * 1000);

      this.stage(video, 'extracting speech audio');
      await this.mediaTools.extractSpeechAudio(inputPath, speechPath, signal);

      this.stage(video, 'transcribing with Groq');
      let transcription;
      try {
        transcription = await this.sttProvider.transcribe(speechPath, { videoDurationMs, signal });
      } finally {
        await fs.rm(speechPath, { force: true }).catch(() => {});
      }

      const sourceLanguage = transcription.language || normalizeSourceLanguage(video.language);
      if (sourceLanguage === targetLanguage) {
        return { status: 'not_suitable', reason: 'already_target_language' };
      }

      this.stage(video, 'translating with Azure Translator');
      const translation = await this.translationProvider.translateSegments(transcription.segments, {
        sourceLanguage,
        targetLanguage,
        signal,
      });

      this.stage(video, 'synthesizing and aligning Edge TTS');
      const timeline = await this.mediaTools.buildDubbedTimeline({
        segments: translation.segments,
        videoDurationMs,
        workspace,
        language,
        ttsProvider: this.ttsProvider,
        signal,
      });

      this.stage(video, 'muxing dubbed MP4');
      try {
        await this.mediaTools.muxDubbedVideo(
          inputPath,
          timeline.timelinePath,
          outputPath,
          sourceMetadata.durationSeconds,
          signal,
        );
      } finally {
        await fs.rm(timeline.timelinePath, { force: true }).catch(() => {});
      }

      this.stage(video, 'validating dubbed MP4');
      await this.mediaTools.validateDubbedVideo(outputPath, sourceMetadata.durationSeconds, signal);

      const version = safeKeyPart(this.config.pipelineVersion, 'v1');
      const safeRunId = safeKeyPart(runId, Date.now());
      const fingerprint = sourceFingerprint(video, source.key);
      const outputKey = `dubbed/${video._id}/${targetLanguage}/${fingerprint}/${version}-${safeRunId}.mp4`;

      this.stage(video, 'uploading dubbed MP4 to R2');
      const uploaded = await this.storage.uploadDubbed(outputPath, outputKey, signal);

      this.stage(video, 'persisting dubbed URL');
      await this.repository.setDubbedUrl(video._id, targetLanguage, uploaded.url, { force });

      if (timeline.clippedSegmentCount > 0) {
        this.logger.warn?.(`[dub:${video._id}] ${timeline.clippedSegmentCount} segment(s) exceeded the configured tempo limit.`);
      }

      return {
        status: 'completed',
        dubbedUrl: uploaded.url,
        outputKey: uploaded.key,
        audioSeconds: sourceMetadata.durationSeconds,
        segmentCount: translation.segments.length,
        azureSourceCharacters: translation.sourceCharacters,
        clippedSegmentCount: timeline.clippedSegmentCount,
      };
    } catch (error) {
      pipelineError = toDubbingError(error);
      throw pipelineError;
    } finally {
      try {
        await this.workspaceManager.cleanup(workspace);
        this.logger.info?.(`[dub:${video._id}] local workspace cleaned`);
      } catch (cleanupError) {
        this.logger.error?.(`[dub:${video._id}] local workspace cleanup failed: ${cleanupError.message}`);
        if (!pipelineError) {
          throw new DubbingError('CLEANUP_FAILED', 'Dub completed but local workspace cleanup failed.', {
            cause: cleanupError,
          });
        }
      }
    }
  }
}
