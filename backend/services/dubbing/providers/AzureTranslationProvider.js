import axios from 'axios';
import DubbingError from '../DubbingError.js';
import { abortableDelay } from '../processRunner.js';

function retryDelay(error, attempt) {
  const raw = error.response?.headers?.['retry-after'];
  const seconds = Number(raw);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  return 1000 * (2 ** (attempt - 1));
}

function isRetryable(error) {
  const status = error.response?.status;
  return !status || status === 429 || status >= 500;
}

export function createTranslationBatches(segments, maxCharacters = 45000, maxItems = 1000) {
  const batches = [];
  let current = [];
  let characters = 0;

  for (const segment of segments) {
    const text = String(segment.sourceText || '');
    if (!text.trim()) {
      throw new DubbingError('INVALID_SEGMENT', `Segment ${segment.id} has no source text.`);
    }
    if (text.length > maxCharacters) {
      throw new DubbingError('TRANSLATION_TEXT_TOO_LARGE', `Segment ${segment.id} exceeds Azure's batch safety limit.`);
    }
    if (current.length > 0 && (current.length >= maxItems || characters + text.length > maxCharacters)) {
      batches.push(current);
      current = [];
      characters = 0;
    }
    current.push(segment);
    characters += text.length;
  }
  if (current.length > 0) batches.push(current);
  return batches;
}

export default class AzureTranslationProvider {
  constructor({ key, region, endpoint, maxBatchCharacters = 45000, timeoutMs = 300000, logger = console, httpClient = axios }) {
    this.key = key;
    this.region = region;
    this.endpoint = endpoint.replace(/\/$/, '');
    this.maxBatchCharacters = Math.min(maxBatchCharacters, 50000);
    this.timeoutMs = timeoutMs;
    this.logger = logger;
    this.httpClient = httpClient;
  }

  buildUrl(sourceLanguage, targetLanguage) {
    const url = new URL(`${this.endpoint}/translate`);
    url.searchParams.set('api-version', '3.0');
    if (sourceLanguage) url.searchParams.set('from', sourceLanguage);
    url.searchParams.set('to', targetLanguage);
    return url.toString();
  }

  async translateBatch(batch, sourceLanguage, targetLanguage, signal) {
    const headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Ocp-Apim-Subscription-Key': this.key,
    };
    if (this.region) headers['Ocp-Apim-Subscription-Region'] = this.region;

    let lastError;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const response = await this.httpClient.post(
          this.buildUrl(sourceLanguage, targetLanguage),
          batch.map((segment) => ({ text: segment.sourceText })),
          { headers, timeout: this.timeoutMs, signal },
        );
        if (!Array.isArray(response.data) || response.data.length !== batch.length) {
          throw new DubbingError('INVALID_TRANSLATION_RESPONSE', 'Azure returned an unexpected number of translations.');
        }

        return response.data.map((result, index) => {
          const translation = result?.translations?.find((item) => item.to === targetLanguage)
            || result?.translations?.[0];
          const translatedText = String(translation?.text || '').trim();
          if (!translatedText) {
            throw new DubbingError('INVALID_TRANSLATION_RESPONSE', `Azure returned empty text for segment ${batch[index].id}.`);
          }
          return translatedText;
        });
      } catch (error) {
        if (error instanceof DubbingError) throw error;
        if (error.code === 'ERR_CANCELED' || signal?.aborted) {
          throw new DubbingError('CANCELLED', 'Operation cancelled.');
        }
        lastError = error;
        if (!isRetryable(error) || attempt === 3) break;
        const delayMs = retryDelay(error, attempt);
        this.logger.warn?.(`[azure] transient translation failure; retrying in ${delayMs}ms (attempt ${attempt}/3)`);
        await abortableDelay(delayMs, signal);
      }
    }

    const status = lastError?.response?.status;
    if (status === 401 || status === 403) {
      throw new DubbingError('PROVIDER_AUTH_FAILED', 'Azure Translator authentication failed.', { cause: lastError });
    }
    if (status === 429) {
      throw new DubbingError('PROVIDER_RATE_LIMITED', 'Azure Translator rate limit exceeded.', { retryable: true, cause: lastError });
    }
    throw new DubbingError('TRANSLATION_FAILED', 'Azure translation failed.', {
      retryable: isRetryable(lastError),
      cause: lastError,
    });
  }

  async translateSegments(segments, { sourceLanguage, targetLanguage, signal } = {}) {
    if (!this.key) throw new DubbingError('MISSING_CONFIGURATION', 'AZURE_TRANSLATOR_KEY is required.');
    const batches = createTranslationBatches(segments, this.maxBatchCharacters);
    const translatedSegments = [];
    let sourceCharacters = 0;

    for (const batch of batches) {
      const translations = await this.translateBatch(batch, sourceLanguage, targetLanguage, signal);
      batch.forEach((segment, index) => {
        sourceCharacters += segment.sourceText.length;
        translatedSegments.push({
          ...segment,
          translatedText: translations[index],
        });
      });
    }

    return { segments: translatedSegments, sourceCharacters };
  }
}
