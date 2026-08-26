import DubbingError from '../DubbingError.js';

function normalizeHost(value) {
  if (!value) return '';
  try {
    return new URL(value.includes('://') ? value : `https://${value}`).host.toLowerCase();
  } catch {
    return '';
  }
}

function validateKey(key) {
  const normalized = String(key || '').replace(/\\/g, '/').replace(/^\/+/, '');
  if (!normalized || normalized.includes('..') || normalized.includes('\0')) {
    throw new DubbingError('INVALID_R2_KEY', 'Video has an invalid R2 object key.');
  }
  return normalized;
}

export default class R2DubbingStorage {
  constructor({ r2Service, accountId, bucketName, publicDomain }) {
    this.r2Service = r2Service;
    this.accountId = accountId;
    this.bucketName = bucketName;
    this.allowedHosts = new Set([
      normalizeHost(publicDomain),
      normalizeHost(`${accountId}.r2.cloudflarestorage.com`),
      normalizeHost(`${bucketName}.${accountId}.r2.cloudflarestorage.com`),
    ].filter(Boolean));
  }

  sourceKey(video) {
    if (video.canonicalMp4Key) return validateKey(video.canonicalMp4Key);
    if (!video.canonicalMp4Url) {
      throw new DubbingError('CANONICAL_MP4_MISSING', 'Video has no canonical MP4 key or URL.');
    }

    let url;
    try {
      url = new URL(video.canonicalMp4Url);
    } catch (error) {
      throw new DubbingError('CANONICAL_MP4_MISSING', 'Video canonical MP4 URL is invalid.', { cause: error });
    }
    if (!this.allowedHosts.has(url.host.toLowerCase())) {
      throw new DubbingError('UNTRUSTED_VIDEO_ORIGIN', 'Canonical MP4 URL is not on the configured R2/CDN origin.');
    }
    const decodedPath = url.pathname
      .split('/')
      .map((segment) => decodeURIComponent(segment))
      .join('/');
    return validateKey(decodedPath);
  }

  async downloadSource(video, localPath, signal) {
    const key = this.sourceKey(video);
    await this.r2Service.downloadFile(key, localPath, { signal });
    return { key, localPath };
  }

  async uploadDubbed(localPath, key, signal) {
    return this.r2Service.uploadFileToR2(localPath, validateKey(key), 'video/mp4', { signal });
  }
}

export { validateKey };
