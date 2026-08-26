import os from 'node:os';
import path from 'node:path';
import DubbingError from './DubbingError.js';

function positiveNumber(env, name, fallback) {
  const raw = env[name];
  if (raw == null || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new DubbingError('INVALID_CONFIGURATION', `${name} must be a positive number.`);
  }
  return value;
}

function positiveInteger(env, name, fallback) {
  const value = positiveNumber(env, name, fallback);
  if (!Number.isInteger(value)) {
    throw new DubbingError('INVALID_CONFIGURATION', `${name} must be a positive integer.`);
  }
  return value;
}

export function loadDubbingConfig(env = process.env) {
  return Object.freeze({
    enabled: String(env.DUBBING_BATCH_ENABLED || 'true').toLowerCase() !== 'false',
    mongoUri: env.MONGO_URI || env.MONGODB_URI || '',
    groqApiKey: String(env.GROQ_API_KEY || '').trim(),
    groqModel: String(env.DUBBING_STT_MODEL || 'whisper-large-v3-turbo').trim(),
    groqEndpoint: String(env.GROQ_STT_ENDPOINT || 'https://api.groq.com/openai/v1/audio/transcriptions').trim(),
    azureKey: String(env.AZURE_TRANSLATOR_KEY || '').trim(),
    azureRegion: String(env.AZURE_TRANSLATOR_REGION || '').trim(),
    azureEndpoint: String(env.AZURE_TRANSLATOR_ENDPOINT || 'https://api.cognitive.microsofttranslator.com').trim(),
    tempRoot: path.resolve(env.DUBBING_TEMP_ROOT || path.join(os.tmpdir(), 'vayug-dubbing')),
    staleTempHours: positiveNumber(env, 'DUBBING_STALE_TEMP_HOURS', 24),
    minFreeDiskMb: positiveNumber(env, 'DUBBING_MIN_FREE_DISK_MB', 2048),
    maxVideoSeconds: positiveNumber(env, 'DUBBING_MAX_VIDEO_SECONDS', 600),
    maxAudioUploadMb: positiveNumber(env, 'DUBBING_MAX_AUDIO_UPLOAD_MB', 24),
    azureBatchCharacters: positiveInteger(env, 'DUBBING_AZURE_BATCH_CHARACTERS', 45000),
    ttsConcurrency: positiveInteger(env, 'DUBBING_TTS_CONCURRENCY', 2),
    maxTempo: positiveNumber(env, 'DUBBING_MAX_TEMPO', 2.5),
    pipelineVersion: String(env.DUBBING_PIPELINE_VERSION || 'v1').trim(),
    pythonBin: String(env.DUBBING_PYTHON_BIN || '').trim(),
    providerTimeoutMs: positiveInteger(env, 'DUBBING_PROVIDER_TIMEOUT_MS', 300000),
    processTimeoutMs: positiveInteger(env, 'DUBBING_PROCESS_TIMEOUT_MS', 600000),
  });
}

export function assertExecutionConfig(config, env = process.env) {
  const missing = [];
  if (!config.enabled) {
    throw new DubbingError('DUBBING_DISABLED', 'Channel dubbing is disabled by DUBBING_BATCH_ENABLED=false.');
  }
  if (!config.mongoUri) missing.push('MONGO_URI');
  if (!config.groqApiKey) missing.push('GROQ_API_KEY');
  if (!config.azureKey) missing.push('AZURE_TRANSLATOR_KEY');

  const r2Names = [
    'CLOUDFLARE_ACCOUNT_ID',
    'CLOUDFLARE_R2_BUCKET_NAME',
    'CLOUDFLARE_R2_ACCESS_KEY_ID',
    'CLOUDFLARE_R2_SECRET_ACCESS_KEY',
  ];
  for (const name of r2Names) {
    if (!String(env[name] || '').trim()) missing.push(name);
  }

  if (missing.length > 0) {
    throw new DubbingError(
      'MISSING_CONFIGURATION',
      `Missing required environment variables: ${missing.join(', ')}`,
    );
  }
}
