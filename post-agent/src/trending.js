import { TRENDING_CATEGORIES } from './config.js';
import { runSearch } from './research.js';

const DDG_DELAY_MS = 1500;
function delay(ms) { return new Promise((r) => setTimeout(r, ms)); }

export function isCategory(value) {
  return value && TRENDING_CATEGORIES[value.toLowerCase()] !== undefined;
}

export function listCategories() {
  return Object.keys(TRENDING_CATEGORIES);
}

export async function researchTrending(category) {
  const categoryKey = category.toLowerCase();
  const categoryConfig = TRENDING_CATEGORIES[categoryKey];

  if (!categoryConfig) {
    throw new Error(`Unknown category: ${category}. Available: ${listCategories().join(', ')}`);
  }

  // Run DDG queries sequentially with delay to avoid rate-limiting
  const settled = [];
  for (let i = 0; i < categoryConfig.queries.length; i++) {
    if (i > 0 && !process.env.TAVILY_API_KEY && !process.env.BRAVE_API_KEY) {
      await delay(DDG_DELAY_MS);
    }
    settled.push(await Promise.allSettled([runSearch(categoryConfig.queries[i])]).then((r) => r[0]));
  }

  const allResults = settled
    .filter((item) => item.status === 'fulfilled')
    .flatMap((item) => item.value);

  if (allResults.length === 0) {
    const reasons = settled
      .filter((item) => item.status === 'rejected')
      .map((item) => item.reason?.message)
      .filter(Boolean);
    throw new Error(`No trending results found for category "${category}"${reasons.length ? `: ${reasons[0]}` : ''}`);
  }

  const uniqueResults = [
    ...new Map(allResults.filter((item) => item.url).map((item) => [item.url, item])).values(),
  ];

  const trendingTopic = pickBestTrendingTopic(uniqueResults);

  return {
    topic: trendingTopic.title,
    newsItems: uniqueResults.slice(0, 8),
    category: categoryConfig.name,
    suggestedHashtags: categoryConfig.hashtags,
  };
}

function pickBestTrendingTopic(results) {
  const scored = results.map((result) => {
    let score = 0;
    if (result.published) {
      const age = Date.now() - new Date(result.published).getTime();
      const dayMs = 24 * 60 * 60 * 1000;
      if (age < 7 * dayMs) score += 3;
      else if (age < 30 * dayMs) score += 2;
      else score += 1;
    }
    if (result.title && result.title.length > 20) score += 1;
    if (result.snippet && result.snippet.length > 50) score += 1;
    return { ...result, score };
  });

  scored.sort((a, b) => b.score - a.score);
  return scored[0] || results[0];
}
