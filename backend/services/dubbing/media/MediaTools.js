import fs from 'node:fs/promises';
import path from 'node:path';
import ffmpegStatic from 'ffmpeg-static';
import ffprobeStatic from 'ffprobe-static';
import DubbingError from '../DubbingError.js';
import { runProcess } from '../processRunner.js';

const AUDIO_SAMPLE_RATE = 48000;

function executablePath(configured, packaged, fallback) {
  return configured || packaged || fallback;
}

export function buildAtempoFilter(ratio) {
  if (!Number.isFinite(ratio) || ratio <= 0) {
    throw new DubbingError('INVALID_TEMPO', `Invalid atempo ratio: ${ratio}`);
  }
  const factors = [];
  let remaining = ratio;
  while (remaining > 2) {
    factors.push(2);
    remaining /= 2;
  }
  while (remaining < 0.5) {
    factors.push(0.5);
    remaining /= 0.5;
  }
  factors.push(remaining);
  return factors.map((factor) => `atempo=${factor.toFixed(6)}`).join(',');
}

function concatFilePath(filePath) {
  const normalized = path.resolve(filePath).replace(/\\/g, '/').replace(/'/g, "'\\''");
  return `file '${normalized}'`;
}

async function mapWithConcurrency(items, concurrency, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  let firstError = null;

  async function consume() {
    while (cursor < items.length && !firstError) {
      const index = cursor;
      cursor += 1;
      try {
        results[index] = await worker(items[index], index);
      } catch (error) {
        firstError = error;
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, consume));
  if (firstError) throw firstError;
  return results;
}

export default class MediaTools {
  constructor({
    ffmpegPath = process.env.FFMPEG_PATH,
    ffprobePath = process.env.FFPROBE_PATH,
    timeoutMs = 600000,
    maxTempo = 2.5,
    ttsConcurrency = 2,
    logger = console,
  } = {}) {
    this.ffmpegPath = executablePath(ffmpegPath, ffmpegStatic, 'ffmpeg');
    this.ffprobePath = executablePath(ffprobePath, ffprobeStatic?.path || ffprobeStatic, 'ffprobe');
    this.timeoutMs = timeoutMs;
    this.maxTempo = maxTempo;
    this.ttsConcurrency = ttsConcurrency;
    this.logger = logger;
  }

  async runFfmpeg(args, signal) {
    return runProcess(this.ffmpegPath, ['-hide_banner', '-nostdin', '-y', ...args], {
      signal,
      timeoutMs: this.timeoutMs,
      errorCode: 'MEDIA_PROCESSING_FAILED',
    });
  }

  async assertAvailable(signal) {
    await Promise.all([
      runProcess(this.ffmpegPath, ['-version'], {
        signal,
        timeoutMs: 15000,
        errorCode: 'FFMPEG_NOT_FOUND',
      }),
      runProcess(this.ffprobePath, ['-version'], {
        signal,
        timeoutMs: 15000,
        errorCode: 'FFPROBE_NOT_FOUND',
      }),
    ]);
  }

  async probe(filePath, signal) {
    const { stdout } = await runProcess(this.ffprobePath, [
      '-v', 'error',
      '-show_entries', 'format=duration,size:stream=index,codec_type,codec_name,duration',
      '-of', 'json',
      filePath,
    ], {
      signal,
      timeoutMs: Math.min(this.timeoutMs, 120000),
      errorCode: 'MEDIA_PROBE_FAILED',
    });
    try {
      const metadata = JSON.parse(stdout);
      const durationSeconds = Number(metadata.format?.duration)
        || Math.max(0, ...((metadata.streams || []).map((stream) => Number(stream.duration) || 0)));
      return {
        durationSeconds,
        size: Number(metadata.format?.size) || 0,
        hasVideo: (metadata.streams || []).some((stream) => stream.codec_type === 'video'),
        hasAudio: (metadata.streams || []).some((stream) => stream.codec_type === 'audio'),
        streams: metadata.streams || [],
      };
    } catch (error) {
      throw new DubbingError('MEDIA_PROBE_FAILED', 'ffprobe returned invalid JSON.', { cause: error });
    }
  }

  async extractSpeechAudio(inputPath, outputPath, signal) {
    await this.runFfmpeg([
      '-i', inputPath,
      '-vn',
      '-map', '0:a:0',
      '-ac', '1',
      '-ar', '16000',
      '-c:a', 'flac',
      outputPath,
    ], signal);
    const stats = await fs.stat(outputPath);
    if (stats.size === 0) throw new DubbingError('MEDIA_PROCESSING_FAILED', 'FFmpeg created empty speech audio.');
    return outputPath;
  }

  estimateEdgeRate(text, targetDurationMs, charactersPerSecond) {
    const targetSeconds = Math.max(targetDurationMs / 1000, 0.1);
    const estimatedSeconds = Math.max(String(text).length / charactersPerSecond, 0.1);
    const requiredRatio = estimatedSeconds / targetSeconds;
    const percent = Math.max(0, Math.min(50, Math.round((requiredRatio - 1) * 100)));
    return `+${percent}%`;
  }

  async fitClip(inputPath, outputPath, targetDurationMs, signal) {
    const metadata = await this.probe(inputPath, signal);
    if (!metadata.hasAudio || metadata.durationSeconds <= 0) {
      throw new DubbingError('TTS_FAILED', 'Generated TTS clip has no usable audio.');
    }
    const targetSeconds = Math.max(targetDurationMs / 1000, 0.05);
    const rawRatio = metadata.durationSeconds / targetSeconds;
    const appliedRatio = Math.max(1, Math.min(rawRatio, this.maxTempo));
    const filters = [];
    if (appliedRatio > 1.001) filters.push(buildAtempoFilter(appliedRatio));
    filters.push(`apad=pad_dur=${targetSeconds.toFixed(3)}`);
    filters.push(`atrim=duration=${targetSeconds.toFixed(3)}`);
    filters.push('asetpts=N/SR/TB');

    await this.runFfmpeg([
      '-i', inputPath,
      '-af', filters.join(','),
      '-ar', String(AUDIO_SAMPLE_RATE),
      '-ac', '1',
      '-c:a', 'pcm_s16le',
      outputPath,
    ], signal);

    return {
      generatedDurationMs: Math.round(metadata.durationSeconds * 1000),
      appliedTempo: appliedRatio,
      clipped: rawRatio > this.maxTempo,
    };
  }

  async createSilence(outputPath, durationMs, signal) {
    const seconds = Math.max(durationMs / 1000, 0.001);
    await this.runFfmpeg([
      '-f', 'lavfi',
      '-i', `anullsrc=r=${AUDIO_SAMPLE_RATE}:cl=mono`,
      '-t', seconds.toFixed(3),
      '-c:a', 'pcm_s16le',
      outputPath,
    ], signal);
    return outputPath;
  }

  normalizeTimelineSegments(segments, videoDurationMs) {
    const sorted = [...segments].sort((a, b) => a.startMs - b.startMs || a.id - b.id);
    const normalized = [];
    let cursorMs = 0;
    for (const segment of sorted) {
      const startMs = Math.max(cursorMs, segment.startMs);
      const endMs = Math.min(videoDurationMs, segment.endMs);
      if (endMs <= startMs) continue;
      normalized.push({ ...segment, effectiveStartMs: startMs, effectiveEndMs: endMs });
      cursorMs = endMs;
    }
    return normalized;
  }

  async buildDubbedTimeline({ segments, videoDurationMs, workspace, language, ttsProvider, signal }) {
    const normalized = this.normalizeTimelineSegments(segments, videoDurationMs);
    if (normalized.length === 0) throw new DubbingError('NO_SPEECH', 'No segments fit the video timeline.');

    const clips = await mapWithConcurrency(normalized, this.ttsConcurrency, async (segment, index) => {
      const baseName = `segment-${String(index).padStart(5, '0')}`;
      const mp3Path = path.join(workspace, `${baseName}.mp3`);
      const wavPath = path.join(workspace, `${baseName}.wav`);
      const durationMs = segment.effectiveEndMs - segment.effectiveStartMs;
      const rate = this.estimateEdgeRate(
        segment.translatedText,
        durationMs,
        language.estimatedCharactersPerSecond,
      );
      await ttsProvider.synthesize({
        text: segment.translatedText,
        voice: language.voice,
        rate,
        outputPath: mp3Path,
        signal,
      });
      try {
        const fit = await this.fitClip(mp3Path, wavPath, durationMs, signal);
        return { ...segment, ...fit, path: wavPath };
      } finally {
        await fs.rm(mp3Path, { force: true }).catch(() => {});
      }
    });

    const concatParts = [];
    const disposableParts = [];
    let cursorMs = 0;
    for (let index = 0; index < clips.length; index += 1) {
      const clip = clips[index];
      if (clip.effectiveStartMs > cursorMs) {
        const silencePath = path.join(workspace, `silence-${String(index).padStart(5, '0')}.wav`);
        await this.createSilence(silencePath, clip.effectiveStartMs - cursorMs, signal);
        concatParts.push(silencePath);
        disposableParts.push(silencePath);
      }
      concatParts.push(clip.path);
      disposableParts.push(clip.path);
      cursorMs = clip.effectiveEndMs;
    }
    if (cursorMs < videoDurationMs) {
      const tailPath = path.join(workspace, 'silence-tail.wav');
      await this.createSilence(tailPath, videoDurationMs - cursorMs, signal);
      concatParts.push(tailPath);
      disposableParts.push(tailPath);
    }

    const concatPath = path.join(workspace, 'timeline-concat.txt');
    const timelinePath = path.join(workspace, 'dubbed-timeline.wav');
    await fs.writeFile(concatPath, `${concatParts.map(concatFilePath).join('\n')}\n`, 'utf8');
    try {
      await this.runFfmpeg([
        '-f', 'concat',
        '-safe', '0',
        '-i', concatPath,
        '-c:a', 'pcm_s16le',
        timelinePath,
      ], signal);
    } finally {
      await Promise.all([
        fs.rm(concatPath, { force: true }).catch(() => {}),
        ...disposableParts.map((partPath) => fs.rm(partPath, { force: true }).catch(() => {})),
      ]);
    }

    return {
      timelinePath,
      clippedSegmentCount: clips.filter((clip) => clip.clipped).length,
    };
  }

  async muxDubbedVideo(inputVideoPath, timelinePath, outputPath, durationSeconds, signal) {
    await this.runFfmpeg([
      '-i', inputVideoPath,
      '-i', timelinePath,
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-c:v', 'copy',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-t', durationSeconds.toFixed(3),
      '-map_metadata', '0',
      '-movflags', '+faststart',
      outputPath,
    ], signal);
    return outputPath;
  }

  async validateDubbedVideo(outputPath, expectedDurationSeconds, signal) {
    const stats = await fs.stat(outputPath);
    const metadata = await this.probe(outputPath, signal);
    const tolerance = Math.max(1, expectedDurationSeconds * 0.02);
    if (stats.size === 0 || !metadata.hasVideo || !metadata.hasAudio) {
      throw new DubbingError('INVALID_OUTPUT_MEDIA', 'Dubbed MP4 is missing a video or audio stream.');
    }
    if (Math.abs(metadata.durationSeconds - expectedDurationSeconds) > tolerance) {
      throw new DubbingError(
        'INVALID_OUTPUT_DURATION',
        `Dubbed MP4 duration ${metadata.durationSeconds.toFixed(2)}s does not match source ${expectedDurationSeconds.toFixed(2)}s.`,
      );
    }
    return metadata;
  }
}
