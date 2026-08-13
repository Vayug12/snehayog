import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import Video from '../models/Video.js';
import { buildVideoPath } from '../utils/videoUrl.js';

const router = express.Router();
const __filename = fileURLToPath(import.meta.url);
const backendRoot = path.join(path.dirname(__filename), '..');
const publicSiteUrl = (process.env.PUBLIC_SITE_URL || 'https://snehayog.site').replace(/\/+$/, '');

const staticPaths = [
  '/',
  '/docs',
  '/faq.html',
  '/for-creators',
  '/e2ee',
  '/creator-monetization',
  '/monetization.json',
  '/ad-free-no-interruption',
  '/about.html',
  '/contact.html',
  '/privacy.html',
  '/terms.html',
  '/refund.html',
];

const escapeXml = (value = '') => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&apos;');

const formatDate = (value) => {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toISOString().slice(0, 10);
};

const staticUrlEntries = staticPaths.map((route) => ({
  loc: `${publicSiteUrl}${route}`,
  changefreq: route === '/' ? 'weekly' : 'monthly',
  priority: route === '/' ? '1.0' : '0.7',
}));

router.get('/sitemap.xml', async (req, res) => {
  try {
    const videos = await Video.find({
      processingStatus: 'completed',
      isSubscriberOnly: { $ne: true },
      $and: [
        {
          $or: [
            { allowedSubscribers: { $exists: false } },
            { allowedSubscribers: { $size: 0 } },
          ],
        },
        {
          $or: [
            { videoUrl: { $exists: true, $nin: [null, ''] } },
            { hlsMasterPlaylistUrl: { $exists: true, $nin: [null, ''] } },
            { hlsPlaylistUrl: { $exists: true, $nin: [null, ''] } },
          ],
        },
      ],
    })
      .select('_id videoName updatedAt createdAt uploadedAt')
      .sort({ updatedAt: -1 })
      .limit(50000)
      .lean();

    const videoEntries = videos.map((video) => ({
      loc: `${publicSiteUrl}${buildVideoPath(video._id, video.videoName)}`,
      lastmod: formatDate(video.updatedAt || video.createdAt || video.uploadedAt),
      changefreq: 'weekly',
      priority: '0.7',
    }));

    const entries = [...staticUrlEntries, ...videoEntries]
      .map((entry) => [
        '  <url>',
        `    <loc>${escapeXml(entry.loc)}</loc>`,
        entry.lastmod ? `    <lastmod>${entry.lastmod}</lastmod>` : '',
        `    <changefreq>${entry.changefreq}</changefreq>`,
        `    <priority>${entry.priority}</priority>`,
        '  </url>',
      ].filter(Boolean).join('\n'))
      .join('\n');

    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${entries}\n</urlset>\n`;
    res.type('application/xml').set('Cache-Control', 'public, max-age=900').send(xml);
  } catch (error) {
    console.error('❌ Dynamic sitemap error:', error);
    // Keep static pages discoverable if the database is temporarily unavailable.
    res.sendFile(path.join(backendRoot, 'public', 'sitemap.xml'));
  }
});

export default router;
