import fs from 'node:fs/promises';
import path from 'node:path';

import { OUTPUT_ROOT } from './config.js';

function slugify(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60) || 'post';
}

export async function saveOutput({ platform, topic, provider, post, research, context }) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const directory = path.join(OUTPUT_ROOT, `${stamp}-${platform}-${slugify(topic)}`);
  const sources = research.results
    .map((item, index) => `${index + 1}. ${item.title}\n   ${item.url}\n   ${item.snippet || ''}`)
    .join('\n\n');
  await fs.mkdir(directory, { recursive: true });
  await Promise.all([
    fs.writeFile(path.join(directory, 'post.md'), `${post.trim()}\n`, 'utf8'),
    fs.writeFile(path.join(directory, 'research.md'), `# Research\n\nQueries:\n${research.queries.map((query) => `- ${query}`).join('\n')}\n\n${sources}\n`, 'utf8'),
    fs.writeFile(path.join(directory, 'metadata.json'), JSON.stringify({
      createdAt: new Date().toISOString(),
      platform,
      topic,
      provider,
      searchProvider: research.provider,
      contextFiles: context.files,
      sources: research.results.map(({ title, url, published }) => ({ title, url, published })),
    }, null, 2), 'utf8'),
  ]);
  return directory;
}

export { slugify };
