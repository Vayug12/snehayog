import ffmpeg from 'fluent-ffmpeg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { spawnSync } from 'child_process';
import { beat } from '../../utils/progressHeartbeat.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// **FIX: Robust FFmpeg Path Selection**
let ffmpegPath = null;
let ffprobePath = null;

try {
  const systemFfmpeg = spawnSync('which', ['ffmpeg']);
  if (systemFfmpeg.status === 0 && systemFfmpeg.stdout.toString().trim()) {
    ffmpegPath = systemFfmpeg.stdout.toString().trim();
  }
  const systemFfprobe = spawnSync('which', ['ffprobe']);
  if (systemFfprobe.status === 0 && systemFfprobe.stdout.toString().trim()) {
    ffprobePath = systemFfprobe.stdout.toString().trim();
  }
} catch (e) {
  console.warn('[HLS] FFmpeg path check failed:', e.message);
}

if (!ffmpegPath) {
  try {
    ffmpegPath = (await import('ffmpeg-static')).default;
  } catch (e) {
    console.error('[HLS] FFmpeg not found. HLS encoding will fail.');
  }
}
if (!ffprobePath) {
  try {
    ffprobePath = (await import('ffprobe-static')).default.path;
  } catch (e) {
    console.error('[HLS] FFprobe not found.');
  }
}

if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);
if (ffprobePath) ffmpeg.setFfprobePath(ffprobePath);

/**
 * Convert an FFmpeg timemark ("00:01:23.45") to seconds.
 */
function timemarkToSeconds(timemark) {
  if (typeof timemark !== 'string') return 0;
  const parts = timemark.split(':').map((p) => parseFloat(p));
  if (parts.length !== 3 || parts.some((p) => Number.isNaN(p))) return 0;
  return parts[0] * 3600 + parts[1] * 60 + parts[2];
}

class HLSEncodingService {
  constructor() {
    this.hlsOutputDir = path.join(__dirname, '../uploads/hls');
    this.ensureHLSDirectory();
    
    this.checkFFmpegInstallation().then(isInstalled => {
      if (!isInstalled) console.warn('[HLS] FFmpeg not available. Encoding will fail.');
    });
  }

  ensureHLSDirectory() {
    if (!fs.existsSync(this.hlsOutputDir)) {
      fs.mkdirSync(this.hlsOutputDir, { recursive: true });
    }
  }

  /**
   * Convert video to HLS format (SINGLE 480p quality only)
   */
  async convertToHLS(inputPath, videoId, options = {}) {
    const {
      segmentDuration = 3,
      quality = 'medium',
      codec = 'h265',
      copyVideo = false,
      copyAudio = false,
      onProgress = null
    } = options;

    let actualCodec = codec;
    if (codec === 'h265') {
      const hasH265 = await this.checkLibx265Available();
      if (!hasH265) {
        console.warn(`[HLS] ${videoId} | WARNING | H.265 requested but libx265 not available. Falling back to H.264.`);
        actualCodec = 'h264';
      }
    }

    return new Promise((resolve, reject) => {
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
      const playlistPath = path.join(outputDir, 'playlist.m3u8');
      
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      const qualityPresets = {
        low: { crf: 28, audioBitrate: '48k' },
        medium: { crf: 28, audioBitrate: '48k' },
        high: { crf: 23, audioBitrate: '128k' }
      };

      const originalVideoInfo = options.originalVideoInfo;
      let selectedResolution;
      let targetBitrate = '340k';
      
      if (originalVideoInfo && originalVideoInfo.width && originalVideoInfo.height) {
        const originalHeight = originalVideoInfo.height;
        if (originalHeight > 1080) {
          targetBitrate = '2500k';
        } else if (originalHeight > 720) {
          targetBitrate = '1200k';
        } else if (originalHeight > 480) {
          targetBitrate = '340k';
        } else {
          targetBitrate = '340k';
        }
        
        selectedResolution = {
          width: originalVideoInfo.width,
          height: originalVideoInfo.height,
          bitrate: targetBitrate
        };
      } else {
        targetBitrate = '340k';
        selectedResolution = { width: 854, height: 480, bitrate: targetBitrate };
      }
      
      const selectedQuality = qualityPresets[quality] || qualityPresets.medium;
      const codecName = actualCodec === 'h265' ? 'H.265 (HEVC)' : 'H.264 (AVC)';
      
      let videoOptions;
      if (copyVideo) {
        videoOptions = ['-c:v', 'copy'];
      } else {
        videoOptions = actualCodec === 'h265'
          ? [
              '-c:v', 'libx265',
              '-tag:v', 'hvc1',
              '-preset', 'superfast',
              '-tune', 'fastdecode',
              '-crf', selectedQuality.crf.toString(),
              '-maxrate', targetBitrate,
              '-bufsize', `${parseInt(targetBitrate) * 2}k`,
              '-x265-params', 'keyint=60:min-keyint=60:scenecut=0:superfast=1',
              '-threads', '0',
              '-pix_fmt', 'yuv420p'
            ]
          : [
              '-c:v', 'libx264',
              '-preset', 'superfast',
              '-profile:v', 'high',
              '-level', '3.1',
              '-crf', selectedQuality.crf.toString(),
              '-maxrate', targetBitrate,
              '-bufsize', `${parseInt(targetBitrate) * 2}k`,
              '-threads', '0',
              '-sc_threshold', '0',
              '-g', '60',
              '-keyint_min', '48',
              '-force_key_frames', 'expr:gte(t,n_forced*2)',
              '-pix_fmt', 'yuv420p'
            ];
      }

      const audioOptions = copyAudio
        ? ['-c:a', 'copy']
        : [
            '-c:a', 'aac',
            '-b:a', selectedQuality.audioBitrate,
            '-ac', '2',
            '-ar', '44100',
            '-af', 'acompressor=ratio=4:attack=200:release=1000:threshold=-12dB'
          ];

      const commonOptions = [
        '-f', 'hls',
        '-hls_time', segmentDuration.toString(),
        '-hls_list_size', '0',
        '-hls_segment_filename', path.join(outputDir, 'segment_%03d.ts'),
        '-hls_playlist_type', 'vod',
        '-hls_flags', 'independent_segments+delete_segments',
        '-hls_segment_type', 'mpegts',
        '-movflags', '+faststart'
      ];

      // '-stats' is required: at '-loglevel error' FFmpeg suppresses the stats
      // lines that fluent-ffmpeg parses to emit 'progress' events.
      let command = ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error', '-stats'])
        .outputOptions([...videoOptions, ...audioOptions, ...commonOptions]);

      if (originalVideoInfo && originalVideoInfo.height > 1080) {
        command = command.videoFilters(`scale=-2:1080:force_original_aspect_ratio=decrease`);
      }
      
      command = command.output(playlistPath);

      const sourceDuration = originalVideoInfo?.duration || 0;
      const encodeStart = Date.now();
      let lastProgressLog = 0;

      command.on('start', (commandLine) => {
        console.log(
          `[HLS] ${videoId} | START | codec=${actualCodec} | source=${originalVideoInfo?.width || '?'}x${originalVideoInfo?.height || '?'} | duration=${sourceDuration.toFixed(1)}s | maxrate=${targetBitrate}`
        );
        console.log(`[HLS] ${videoId} | CMD | ${commandLine}`);
      });

      command.on('progress', (progress) => {
        // Worker stall watchdog ka sabse barik signal: '-stats' on hone ki wajah se
        // ye ~1 baar/second aata hai. FFmpeg hang ho to event rukta hai jabki process
        // zinda rehta hai — hang ki asli pehchaan yehi hai.
        beat();

        const encodedSeconds = timemarkToSeconds(progress.timemark);

        let percent = progress.percent;
        if ((percent === undefined || Number.isNaN(percent)) && sourceDuration > 0) {
          percent = (encodedSeconds / sourceDuration) * 100;
        }
        percent = Math.max(0, Math.min(100, Math.round(percent || 0)));

        const elapsedSec = (Date.now() - encodeStart) / 1000;
        // speed < 1.0x means FFmpeg encodes slower than the video plays: CPU-bound.
        const speed = elapsedSec > 0 ? encodedSeconds / elapsedSec : 0;

        const now = Date.now();
        if (now - lastProgressLog > 5000) {
          lastProgressLog = now;
          console.log(
            `[HLS] ${videoId} | PROGRESS | ${percent}% | ${progress.timemark} of ${sourceDuration.toFixed(1)}s | fps=${progress.currentFps ?? '?'} | speed=${speed.toFixed(2)}x | elapsed=${elapsedSec.toFixed(0)}s`
          );
        }

        if (onProgress) onProgress(percent);
      });

      command.on('end', () => {
        const encodeSec = (Date.now() - encodeStart) / 1000;
        try {
          const playlistContent = fs.readFileSync(playlistPath, 'utf8');
          const segments = fs.readdirSync(outputDir).filter(file => file.endsWith('.ts'));
          console.log(
            `[HLS] ${videoId} | DONE | ${segments.length} segments | encode=${encodeSec.toFixed(1)}s for ${sourceDuration.toFixed(1)}s of video (${encodeSec > 0 ? (sourceDuration / encodeSec).toFixed(2) : '?'}x realtime)`
          );
          resolve({
            success: true,
            playlistPath,
            playlistUrl: `/uploads/hls/${cleanVideoId}/playlist.m3u8`,
            segments: segments.length,
            outputDir,
            codec: actualCodec
          });
        } catch (error) {
          reject(new Error(`Failed to read HLS output: ${error.message}`));
        }
      });

      command.on('error', (error) => {
        const encodeSec = (Date.now() - encodeStart) / 1000;
        console.error(`[HLS] ${videoId} | ERROR | after ${encodeSec.toFixed(1)}s | ${error.message}`);
        reject(new Error(`HLS encoding failed: ${error.message}`));
      });

      command.run();
    });
  }

  async checkFFmpegInstallation() {
    return new Promise((resolve) => {
      ffmpeg.getAvailableCodecs((err) => {
        if (err) resolve(false);
        else resolve(true);
      });
    });
  }

  async checkLibx265Available() {
    return new Promise((resolve) => {
      ffmpeg.getAvailableEncoders((err, encoders) => {
        if (err) resolve(false);
        else resolve(!!(encoders && encoders['libx265']));
      });
    });
  }

  async cleanupHLS(videoId) {
    const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
    if (fs.existsSync(outputDir)) {
      fs.rmSync(outputDir, { recursive: true, force: true });
    }
  }

  async cleanupTempHLSDirectories() {
    try {
      const files = fs.readdirSync(this.hlsOutputDir);
      const tempDirs = files.filter(file => file.startsWith('temp_'));
      for (const tempDir of tempDirs) {
        try {
          fs.rmSync(path.join(this.hlsOutputDir, tempDir), { recursive: true, force: true });
        } catch (error) {}
      }
    } catch (error) {}
  }

  getHLSInfo(videoId) {
    const outputDir = path.join(this.hlsOutputDir, videoId);
    if (!fs.existsSync(outputDir)) return null;
    try {
      const files = fs.readdirSync(outputDir, { recursive: true });
      return {
        videoId,
        totalSegments: files.filter(file => file.endsWith('.ts')).length,
        hasSinglePlaylist: files.includes('playlist.m3u8')
      };
    } catch (error) {
      return null;
    }
  }
}

export default new HLSEncodingService();
