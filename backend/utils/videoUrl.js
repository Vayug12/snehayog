const MAX_VIDEO_SLUG_LENGTH = 80;

export const slugifyVideoTitle = (title) => {
  const slug = String(title || '')
    .trim()
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/'/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, MAX_VIDEO_SLUG_LENGTH)
    .replace(/-+$/g, '');

  return slug || 'video';
};

export const buildVideoPath = (videoId, title) =>
  `/video/${encodeURIComponent(String(videoId))}/${slugifyVideoTitle(title)}`;
