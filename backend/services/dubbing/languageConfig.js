import DubbingError from './DubbingError.js';

const TARGET_ALIASES = new Map([
  ['hi', 'hi'],
  ['hindi', 'hi'],
  ['hi-in', 'hi'],
  ['en', 'en'],
  ['english', 'en'],
  ['en-us', 'en'],
]);

const SOURCE_ALIASES = new Map([
  ...TARGET_ALIASES,
  ['eng', 'en'],
]);

export const LANGUAGE_CONFIG = Object.freeze({
  hi: Object.freeze({
    code: 'hi',
    name: 'Hindi',
    voice: 'hi-IN-SwaraNeural',
    estimatedCharactersPerSecond: 9,
  }),
  en: Object.freeze({
    code: 'en',
    name: 'English',
    voice: 'en-US-AriaNeural',
    estimatedCharactersPerSecond: 13,
  }),
});

export function normalizeTargetLanguage(value) {
  const normalized = TARGET_ALIASES.get(String(value || '').trim().toLowerCase());
  if (!normalized) {
    throw new DubbingError(
      'UNSUPPORTED_TARGET_LANGUAGE',
      `Unsupported target language "${value}". Use hi/hindi or en/english.`,
    );
  }
  return normalized;
}

export function normalizeSourceLanguage(value) {
  if (!value) return null;
  const normalizedValue = String(value).trim().toLowerCase();
  return SOURCE_ALIASES.get(normalizedValue) || SOURCE_ALIASES.get(normalizedValue.split('-')[0]) || null;
}

export function getLanguageConfig(code) {
  const normalized = normalizeTargetLanguage(code);
  return LANGUAGE_CONFIG[normalized];
}

export function getDubbedUrl(dubbedUrls, targetLanguage) {
  if (!dubbedUrls) return null;
  if (dubbedUrls instanceof Map) {
    const value = dubbedUrls.get(targetLanguage);
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }
  const value = dubbedUrls[targetLanguage];
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}
