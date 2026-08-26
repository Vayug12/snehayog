import fs from 'node:fs';
import fsp from 'node:fs/promises';
import axios from 'axios';
import FormData from 'form-data';
import DubbingError from '../DubbingError.js';
import { abortableDelay } from '../processRunner.js';
import { normalizeSourceLanguage } from '../languageConfig.js';

function parseRetryAfter(value, fallbackMs) {
  if (!value) return fallbackMs;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const dateMs = Date.parse(value);
  return Number.isFinite(dateMs) ? Math.max(0, dateMs - Date.now()) : fallbackMs;
}

function isRetryable(error) {
  const status = error.response?.status;
  return !status || status === 429 || status >= 500;
}

export default class GroqSttProvider {
  constructor({ apiKey, model, endpoint, maxUploadMb = 24, timeoutMs = 300000, logger = console, httpClient = axios }) {
    this.apiKey = apiKey;
    this.model = model;
    this.endpoint = endpoint;
    this.maxUploadBytes = maxUploadMb * 1024 * 1024;
    this.timeoutMs = timeoutMs;
    this.logger = logger;
    this.httpClient = httpClient;
  }

  normalizeResponse(data, videoDurationMs) {
    if (!data || !Array.isArray(data.segments)) {
      throw new DubbingError('INVALID_STT_RESPONSE', 'Groq returned no timestamped segments.');
    }

    const segments = data.segments
      .map((segment, index) => {
        const startMs = Math.round(Number(segment.start) * 1000);
        const endMs = Math.round(Number(segment.end) * 1000);
        const sourceText = String(segment.text || '').trim();
        if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || !sourceText) return null;
        if (startMs < 0 || endMs <= startMs || endMs > videoDurationMs + 1000) return null;
        return {
          id: index,
          startMs,
          endMs: Math.min(endMs, videoDurationMs),
          sourceLanguage: normalizeSourceLanguage(data.language),
          sourceText,
          translatedText: null,
          voice: null,
          generatedAudioPath: null,
          generatedDurationMs: null,
          finalDurationMs: Math.min(endMs, videoDurationMs) - startMs,
        };
      })
      .filter(Boolean);

    if (segments.length === 0) {
      throw new DubbingError('NO_SPEECH', 'Groq returned no usable speech segments.');
    }

    return {
      language: normalizeSourceLanguage(data.language),
      durationSeconds: Number(data.duration) || videoDurationMs / 1000,
      segments,
    };
  }

  async transcribe(audioPath, { videoDurationMs, signal } = {}) {
    if (!this.apiKey) throw new DubbingError('MISSING_CONFIGURATION', 'GROQ_API_KEY is required.');
    const stats = await fsp.stat(audioPath);
    if (stats.size > this.maxUploadBytes) {
      throw new DubbingError(
        'AUDIO_TOO_LARGE',
        `Extracted audio is ${(stats.size / 1024 / 1024).toFixed(1)} MB; maximum is ${(this.maxUploadBytes / 1024 / 1024).toFixed(1)} MB.`,
      );
    }

    let lastError;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      if (signal?.aborted) throw new DubbingError('CANCELLED', 'Operation cancelled.');
      const form = new FormData();
      form.append('file', fs.createReadStream(audioPath));
      form.append('model', this.model);
      form.append('response_format', 'verbose_json');
      form.append('timestamp_granularities[]', 'segment');
      form.append('temperature', '0');

      try {
        const response = await this.httpClient.post(this.endpoint, form, {
          headers: {
            ...form.getHeaders(),
            Authorization: `Bearer ${this.apiKey}`,
          },
          maxBodyLength: Infinity,
          timeout: this.timeoutMs,
          signal,
        });
        return this.normalizeResponse(response.data, videoDurationMs);
      } catch (error) {
        if (error.code === 'ERR_CANCELED' || signal?.aborted) {
          throw new DubbingError('CANCELLED', 'Operation cancelled.');
        }
        lastError = error;
        if (!isRetryable(error) || attempt === 3) break;
        const delayMs = parseRetryAfter(error.response?.headers?.['retry-after'], 1000 * (2 ** (attempt - 1)));
        this.logger.warn?.(`[groq] transient transcription failure; retrying in ${delayMs}ms (attempt ${attempt}/3)`);
        await abortableDelay(delayMs, signal);
      }
    }

    const status = lastError?.response?.status;
    if (status === 401 || status === 403) {
      throw new DubbingError('PROVIDER_AUTH_FAILED', 'Groq authentication failed.', { cause: lastError });
    }
    if (status === 429) {
      throw new DubbingError('PROVIDER_RATE_LIMITED', 'Groq rate limit exceeded.', { retryable: true, cause: lastError });
    }
    throw new DubbingError('STT_FAILED', 'Groq transcription failed.', {
      retryable: isRetryable(lastError),
      cause: lastError,
    });
  }
}
