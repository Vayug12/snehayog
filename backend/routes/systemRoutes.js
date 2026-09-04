import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import mongoose from 'mongoose';
import databaseManager from '../config/database.js';
import Video from '../models/Video.js';
import User from '../models/User.js';
import { passiveVerifyToken } from '../utils/verifytoken.js';
import { buildVideoPath, slugifyVideoTitle } from '../utils/videoUrl.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.join(__dirname, '..');
const publicSiteUrl = (process.env.PUBLIC_SITE_URL || 'https://snehayog.site').replace(/\/+$/, '');

const escapeHtml = (value = '') => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

const router = express.Router();

const isPrivateVideo = (video) => video.isSubscriberOnly === true
  || (Array.isArray(video.allowedSubscribers) && video.allowedSubscribers.length > 0);

/**
 * Web share/embed pages are public for normal videos, but subscriber-only
 * videos must never render a player or expose their stream URL to guests.
 * The uploader is allowed to view their own private video.
 */
const canViewPrivateVideo = async (video, req) => {
  if (!isPrivateVideo(video)) return true;

  const requestingGoogleId = req.user?.googleId || req.user?.id;
  if (!requestingGoogleId) return false;

  const requestingUser = req.user?._id
    ? { _id: req.user._id }
    : await User.findOne({ googleId: requestingGoogleId }).select('_id').lean();
  if (!requestingUser?._id) return false;

  const requestingUserId = requestingUser._id.toString();
  const uploaderId = video.uploader?._id?.toString() || video.uploader?.toString();
  if (uploaderId === requestingUserId) return true;

  return (video.allowedSubscribers || []).some((id) => id.toString() === requestingUserId);
};

const sendPrivateVideoNotFound = (res) => res.status(404).send('Video not found');

// Asset Links dynamic response
const assetLinksPackageName = process.env.ANDROID_ASSETLINKS_PACKAGE_NAME;
const assetLinksFingerprintsRaw = process.env.ANDROID_ASSETLINKS_FINGERPRINTS || '';
const assetLinksFingerprints = assetLinksFingerprintsRaw
  .split(',')
  .map((fp) => fp.trim())
  .filter((fp) => fp.length > 0);

if (assetLinksPackageName && assetLinksFingerprints.length > 0) {
  router.get('/.well-known/assetlinks.json', (req, res) => {
    res.json([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: assetLinksPackageName,
          sha256_cert_fingerprints: assetLinksFingerprints
        }
      }
    ]);
  });
}

// Serve app-ads.txt and ads.txt from root
router.get(["/app-ads.txt", "/ads.txt"], (req, res) => {
  res.sendFile(path.join(backendRoot, "ads.txt"));
});

// Redirect APK download requests to Google Play Store
router.get(['/download/vayu-latest.apk', '/download/app-release.apk', '/download'], (req, res) => {
  res.redirect(302, 'https://play.google.com/store/apps/details?id=com.snehayog.app');
});

// Root route handler - serves the landing page for APK distribution
router.get('/', (req, res) => {
  res.sendFile(path.join(backendRoot, 'public', 'index.html'));
});

// Public documentation hub for people, search engines and AI agents.
router.get(['/docs', '/docs/'], (req, res) => {
  res.sendFile(path.join(backendRoot, 'public', 'docs.html'));
});

router.get('/llms.txt', (req, res) => {
  res.sendFile(path.join(backendRoot, 'public', 'llm.txt'));
});

// SEO landing pages use clean, extensionless URLs while keeping their source
// documents in the public directory for static hosting and local preview.
const seoPages = {
  '/for-creators': 'for-creators.html',
  '/e2ee': 'e2ee.html',
  '/creator-monetization': 'creator-monetization.html',
  '/ad-free-no-interruption': 'ad-free-nointruption.html'
};

router.get('/ad-free-nointruption', (req, res) => {
  res.redirect(301, '/ad-free-no-interruption');
});

Object.entries(seoPages).forEach(([route, fileName]) => {
  router.get([route, `${route}/`], (req, res) => {
    res.sendFile(path.join(backendRoot, 'public', fileName));
  });
});

router.get(['/video/:id', '/video/:id/:slug'], passiveVerifyToken, async (req, res) => {
  // Prevent browser caching of the redirect response
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');

  try {
    const { id, slug } = req.params;
    
    // Safety check for ID format
    if (!mongoose.isObjectIdOrHexString(id)) {
       return res.status(400).send('Invalid Link Format');
    }

    const video = await Video.findById(id).populate('uploader', 'name');

    if (video && !(await canViewPrivateVideo(video, req))) {
      return sendPrivateVideoNotFound(res);
    }

    // Preserve a shared section when the web fallback opens the installed app.
    const sharedTimestampParams = new URLSearchParams();
    for (const key of ['t', 'end']) {
      const value = req.query[key];
      if (typeof value === 'string' && /^\d+$/.test(value)) {
        sharedTimestampParams.set(key, value);
      }
    }
    const sharedTimestampQuery = sharedTimestampParams.toString();
    const sharedTimestampSuffix = sharedTimestampQuery ? `?${sharedTimestampQuery}` : '';

    const canonicalVideoPath = buildVideoPath(video._id, video.videoName);
    const expectedSlug = slugifyVideoTitle(video.videoName);
    if (slug !== expectedSlug || req.path !== canonicalVideoPath) {
      const queryIndex = req.originalUrl.indexOf('?');
      const querySuffix = queryIndex >= 0 ? req.originalUrl.slice(queryIndex) : '';
      return res.redirect(301, `${canonicalVideoPath}${querySuffix}`);
    }

    const canonicalVideoUrl = `${publicSiteUrl}${canonicalVideoPath}`;
    // App links constants
    const appSchemeUrl = `snehayog://video/${id}${sharedTimestampSuffix}`;
    const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.snehayog.app';
    const intentUrl = `intent://video/${id}${sharedTimestampSuffix}#Intent;scheme=snehayog;package=com.snehayog.app;S.browser_fallback_url=${encodeURIComponent(canonicalVideoUrl)};end`;

    // Video Found: Serve the Premium Web Player
    video.incrementView(null, 2, 'embed').catch(err => console.error('Error tracking shared view:', err));

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const videoStreamUrl = video.hlsMasterPlaylistUrl || video.videoUrl;
    const finalStreamUrl = videoStreamUrl.startsWith('http') ? videoStreamUrl : `${baseUrl}${videoStreamUrl}`;
    const finalThumbnailUrl = (video.thumbnailUrl && video.thumbnailUrl.startsWith('http')) 
      ? video.thumbnailUrl
      : (video.thumbnailUrl ? `${baseUrl}${video.thumbnailUrl}` : '');
    const isSubscriberOnly = isPrivateVideo(video);
    const safeVideoName = escapeHtml(video.videoName || 'Vayug video');
    const safeDescription = escapeHtml(video.description || 'Watch this video on Vayug');
    const safeCreatorName = escapeHtml(video.uploader?.name || 'Vayug creator');
    const creatorInitial = escapeHtml((video.uploader?.name || 'V').trim().charAt(0).toUpperCase() || 'V');
    const storedAspectRatio = Number(video.aspectRatio);
    const playerAspectRatio = Number.isFinite(storedAspectRatio) && storedAspectRatio > 0
      ? Math.min(Math.max(storedAspectRatio, 0.5625), 2.4)
      : 16 / 9;
    const isPortraitVideo = playerAspectRatio < 1;
    const robotsDirective = isSubscriberOnly ? 'noindex, nofollow' : 'index, follow';
    const canonicalMarkup = isSubscriberOnly
      ? ''
      : `<link rel="canonical" href="${canonicalVideoUrl}" />`;
    const durationSeconds = Number(video.duration);
    const videoStructuredData = isSubscriberOnly ? '' : `<script type="application/ld+json">${JSON.stringify({
      '@context': 'https://schema.org',
      '@type': 'VideoObject',
      name: video.videoName || 'Vayug video',
      description: video.description || 'Watch this video on Vayug',
      thumbnailUrl: finalThumbnailUrl || undefined,
      uploadDate: (video.createdAt || video.uploadedAt || new Date()).toISOString(),
      duration: Number.isFinite(durationSeconds) && durationSeconds > 0
        ? `PT${Math.round(durationSeconds)}S`
        : undefined,
      contentUrl: finalStreamUrl,
      embedUrl: `${publicSiteUrl}/embed/${id}`,
      publisher: {
        '@type': 'Organization',
        name: 'Vayug',
        url: publicSiteUrl
      }
    }).replace(/</g, '\\u003c')}</script>`;

    const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${safeVideoName} | Vayug</title>
  <meta name="description" content="${safeDescription}" />
  <meta name="robots" content="${robotsDirective}" />
  ${canonicalMarkup}
  
  <meta property="og:url" content="${canonicalVideoUrl}" />
  <meta property="og:type" content="video.other" />
  <meta property="og:title" content="${safeVideoName}" />
  <meta property="og:description" content="${safeDescription}" />
  <meta property="og:image" content="${escapeHtml(finalThumbnailUrl)}" />
  <meta name="theme-color" content="#2563eb" />
  ${videoStructuredData}

  <style>
    :root {
      color-scheme: dark;
      --background: #0f172a;
      --surface: #1e293b;
      --divider: #334155;
      --primary: #ffffff;
      --secondary: #94a3b8;
      --muted: #64748b;
      --accent: #2563eb;
      --accent-pressed: #1d4ed8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-width: 320px;
      min-height: 100vh;
      background: var(--background);
      color: var(--primary);
      font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    .page { min-height: 100vh; }
    .topbar {
      height: 68px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      max-width: 1040px;
      margin: 0 auto;
      padding: 0 24px;
      border-bottom: 1px solid rgba(51, 65, 85, 0.55);
    }
    .brand { display: inline-flex; align-items: center; gap: 10px; color: var(--primary); text-decoration: none; font-size: 17px; font-weight: 600; letter-spacing: -0.01em; }
    .brand-mark { width: 28px; height: 28px; border-radius: 9px; display: grid; place-items: center; background: var(--accent); color: white; font-size: 14px; font-weight: 700; }
    .topbar-label { color: var(--muted); font-size: 13px; }
    .content { width: min(100%, 1040px); margin: 0 auto; padding: 32px 24px 56px; }
    .player-wrap { display: flex; justify-content: center; width: 100%; }
    .player {
      --media-ratio: ${playerAspectRatio};
      width: min(100%, ${isPortraitVideo ? 440 : 960}px);
      aspect-ratio: var(--media-ratio);
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
      background: #020617;
      border: 1px solid rgba(51, 65, 85, 0.7);
      border-radius: 18px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.18);
    }
    video { display: block; width: 100%; height: 100%; object-fit: contain; outline: none; }
    .meta { width: min(100%, 760px); margin: 0 auto; padding-top: 28px; }
    .creator { display: inline-flex; align-items: center; gap: 10px; color: var(--secondary); font-size: 14px; margin-bottom: 14px; }
    .creator-mark { width: 28px; height: 28px; display: grid; place-items: center; border-radius: 50%; background: var(--surface); border: 1px solid var(--divider); color: var(--secondary); font-size: 12px; font-weight: 600; }
    h1 { margin: 0; color: var(--primary); font-size: clamp(22px, 3vw, 28px); line-height: 1.2; letter-spacing: -0.025em; font-weight: 600; }
    .details { margin: 10px 0 0; color: var(--secondary); font-size: 14px; line-height: 1.5; }
    .actions { display: flex; align-items: center; gap: 12px; margin-top: 24px; }
    .btn { min-height: 52px; padding: 0 20px; border-radius: 14px; font-size: 15px; font-weight: 600; text-decoration: none; display: inline-flex; align-items: center; justify-content: center; gap: 9px; transition: background 200ms ease, border-color 200ms ease, transform 200ms ease; }
    .btn:focus-visible { outline: 3px solid rgba(59, 130, 246, 0.45); outline-offset: 3px; }
    .btn:hover { transform: translateY(-1px); }
    .primary { flex: 1; background: var(--accent); color: #fff; }
    .primary:hover { background: var(--accent-pressed); }
    .secondary { flex: 1; color: var(--primary); background: transparent; border: 1px solid var(--divider); }
    .secondary:hover { background: rgba(30, 41, 59, 0.7); border-color: #475569; }
    .btn svg { width: 18px; height: 18px; }
    .footer-note { margin: 30px auto 0; width: min(100%, 760px); color: var(--muted); font-size: 12px; text-align: center; }
    @media (max-width: 640px) {
      .topbar { height: 60px; padding: 0 18px; }
      .topbar-label { display: none; }
      .content { padding: 20px 16px 40px; }
      .player { border-radius: 16px; }
      .meta { padding-top: 22px; }
      .actions { flex-direction: column; align-items: stretch; margin-top: 20px; }
      .btn { width: 100%; }
    }
  </style>
</head>
<body>
  <div class="page">
    <header class="topbar">
      <a class="brand" href="${publicSiteUrl}" aria-label="Vayug home">
        <span class="brand-mark">V</span>
        <span>Vayug</span>
      </a>
      <span class="topbar-label">Shared video</span>
    </header>
    <main class="content">
      <div class="player-wrap">
        <div class="player">
          <video id="v" poster="${escapeHtml(finalThumbnailUrl)}" controls playsinline autoplay muted preload="metadata"></video>
        </div>
      </div>
      <section class="meta" aria-labelledby="video-title">
        <div class="creator"><span class="creator-mark">${creatorInitial}</span><span>${safeCreatorName}</span></div>
        <h1 id="video-title">${safeVideoName}</h1>
        <p class="details">${Number(video.views || 0).toLocaleString()} views <span aria-hidden="true">&bull;</span> Shared from Vayug</p>
        <div class="actions">
          <a href="${intentUrl}" class="btn primary">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"></path><path d="m13 6 6 6-6 6"></path></svg>
            <span>Open in Vayug</span>
          </a>
          <a href="${playStoreUrl}" class="btn secondary">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12"></path><path d="m7 10 5 5 5-5"></path><path d="M5 21h14"></path></svg>
            <span>Get the app</span>
          </a>
        </div>
      </section>
      <p class="footer-note">Watch, discover, and share on Vayug.</p>
    </main>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
  <script>
    const video = document.getElementById('v');
    const src = '${finalStreamUrl}';
    if(Hls.isSupported() && src.includes('.m3u8')) {
      const hls = new Hls(); hls.loadSource(src); hls.attachMedia(video);
    } else { video.src = src; }

    // Smart handoff: If opened on an Android device inside a browser/webview,
    // automatically attempt opening the installed Vayug app via Android Intent.
    (function() {
      const isAndroid = /Android/i.test(navigator.userAgent);
      const isEmbed = window !== window.top;
      if (isAndroid && !isEmbed && !sessionStorage.getItem('vayu_intent_triggered')) {
        sessionStorage.setItem('vayu_intent_triggered', '1');
        setTimeout(function() {
          window.location.href = '${intentUrl}';
        }, 120);
      }
    })();
  </script>
</body>
</html>`;

    res.status(200).send(html);
  } catch (error) {
    console.error('❌ Social route error:', error);
    res.status(500).send('Error loading video page');
  }
});

// Minimalist external embed route
router.get('/embed/:id', passiveVerifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    const video = await Video.findById(id).populate('uploader', 'name');

    if (!video) {
      return res.status(404).send('Video not found');
    }

    if (!(await canViewPrivateVideo(video, req))) {
      return sendPrivateVideoNotFound(res);
    }

    // Track view from embed source
    // Passing null for userId to count as a guest view
    video.incrementView(null, 2, 'embed').catch(err => console.error('Error tracking embed view:', err));

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const videoStreamUrl = video.hlsMasterPlaylistUrl || video.videoUrl;
    const finalStreamUrl = videoStreamUrl.startsWith('http') ? videoStreamUrl : `${baseUrl}${videoStreamUrl}`;
    const finalThumbnailUrl = video.thumbnailUrl.startsWith('http') ? video.thumbnailUrl : `${baseUrl}${video.thumbnailUrl}`;

    const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${video.videoName} - Vayug</title>
  
  <!-- SEO / Open Graph -->
  <meta property="og:title" content="${video.videoName}" />
  <meta property="og:description" content="${video.description || 'Watch this video on Vayug'}" />
  <meta property="og:image" content="${finalThumbnailUrl}" />
  <meta property="og:type" content="video.other" />
  
  <style>
    body { margin: 0; background: #0f172a; overflow: hidden; font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    .player-container { position: relative; width: 100vw; height: 100vh; padding: 12px; display: flex; align-items: center; justify-content: center; background: #0f172a; }
    video { width: 100%; height: 100%; max-height: 100vh; object-fit: contain; outline: none; border-radius: 16px; background: #020617; }
    .vayu-btn {
      position: absolute; bottom: 20px; right: 20px;
      background: #2563eb; color: #fff; padding: 10px 16px;
      border-radius: 14px; text-decoration: none; font-weight: 600; font-size: 14px;
      box-shadow: 0 2px 12px rgba(0,0,0,0.18); opacity: 0.96; transition: opacity 0.2s, transform 0.2s;
      z-index: 10; display: flex; align-items: center; gap: 8px;
    }
    .vayu-btn:hover { transform: scale(1.05); background: #2563eb; }
    .player-container:hover .vayu-btn { opacity: 1; }
    
    /* Responsive adjustment for small embeds */
    @media (max-width: 400px) {
      .vayu-btn { bottom: 10px; right: 10px; padding: 8px 12px; font-size: 12px; }
    }
  </style>
</head>
<body>
  <div class="player-container">
    <video id="video" poster="${finalThumbnailUrl}" controls playsinline preload="metadata"></video>
    <a href="${publicSiteUrl}${buildVideoPath(video._id, video.videoName)}" target="_blank" class="vayu-btn">
      <span>Watch on Vayug</span>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>
    </a>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
  <script>
    document.addEventListener('DOMContentLoaded', function() {
      const video = document.getElementById('video');
      const videoSrc = '${finalStreamUrl}';
      const fallbackSrc = '${video.videoUrl.startsWith('http') ? video.videoUrl : baseUrl + video.videoUrl}';

      if (Hls.isSupported() && videoSrc.includes('.m3u8')) {
        const hls = new Hls({
          capLevelToPlayerSize: true,
          autoStartLoad: true
        });
        hls.loadSource(videoSrc);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, function (event, data) {
          if (data.fatal) {
            console.warn('HLS fatal error, falling back to MP4');
            video.src = fallbackSrc;
          }
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        // Native HLS support (Safari)
        video.src = videoSrc;
      } else {
        // Fallback to MP4
        video.src = fallbackSrc;
      }
    });
  </script>
</body>
</html>`;

    res.setHeader('X-Frame-Options', 'ALLOWALL'); // Explicitly allow embedding
    res.setHeader('Content-Security-Policy', "frame-ancestors *"); // Modern equivalent
    res.status(200).send(html);
  } catch (error) {
    console.error('❌ Embed error:', error);
    res.status(500).send('An error occurred loading the video embed');
  }
});

// Admin Dashboard route
router.get('/admin/dashboard', (req, res) => {
  res.sendFile(path.join(backendRoot, 'admin', 'admin_dashboard.html'));
});

// Health check endpoints
router.get('/health', (req, res) => {
  const dbStatus = databaseManager.getConnectionStatus();
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    server: {
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      version: process.version,
      platform: process.platform
    },
    cors: {
      origin: req.headers.origin || 'No origin header',
      method: req.method,
      headers: req.headers
    },
    message: 'Backend is running successfully!'
  });
});

router.get('/api/health', (req, res) => {
  const dbStatus = databaseManager.getConnectionStatus();
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    message: 'Backend API is running successfully',
    endpoints: {
      auth: '/api/auth',
      users: '/api/users',
      videos: '/api/videos',
      ads: '/api/ads',
      billing: '/api/billing',
      upload: '/api/upload'
    }
  });
});

export default router;
