const SEARCH_TIMEOUT_MS = 20000;
const MAX_RESULTS = 6;

function cleanText(value = '') {
  return value
    .replace(/<[^>]*>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeUrl(value) {
  try {
    const url = new URL(value, 'https://duckduckgo.com');
    return url.searchParams.get('uddg') || url.href;
  } catch {
    return value;
  }
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(SEARCH_TIMEOUT_MS),
    headers: { Accept: 'application/json', ...(options.headers || {}) },
  });
  if (!response.ok) throw new Error(`search request failed with HTTP ${response.status}`);
  return response.json();
}

export async function searchTavily(query) {
  const data = await fetchJson('https://api.tavily.com/search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      api_key: process.env.TAVILY_API_KEY,
      query,
      search_depth: 'advanced',
      max_results: MAX_RESULTS,
      include_answer: false,
      include_raw_content: false,
    }),
  });
  return (data.results || []).map((item) => ({
    title: item.title,
    url: item.url,
    snippet: item.content,
    published: item.published_date || null,
    provider: 'tavily',
  }));
}

export async function searchDuckDuckGo(query) {
  const url = new URL('https://html.duckduckgo.com/html/');
  url.searchParams.set('q', query);
  const response = await fetch(url, {
    headers: { 'User-Agent': 'snehayog-post-agent/0.1' },
    signal: AbortSignal.timeout(SEARCH_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`DuckDuckGo search failed with HTTP ${response.status}`);
  const html = await response.text();
  const results = [...html.matchAll(/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)];
  const snippets = [...html.matchAll(/<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/gi)];
  return results.slice(0, MAX_RESULTS).map((match, index) => ({
    title: cleanText(match[2]),
    url: decodeUrl(match[1]),
    snippet: cleanText(snippets[index]?.[1] || ''),
    published: null,
    provider: 'duckduckgo',
  }));
}

export function buildQueries({ topic, projectName = 'Snehayog/Vayug' }) {
  const subject = topic || 'creator video monetization and audience growth';
  const year = new Date().getFullYear();
  return [
    `${subject} creator problem ${year - 1} ${year}`,
    `${subject} creators discussion challenges`,
    `${projectName} ${subject}`,
  ];
}

export async function research({ topic, projectName }) {
  const queries = buildQueries({ topic, projectName });
  const search = process.env.TAVILY_API_KEY
    ? searchTavily
    : searchDuckDuckGo;

  const settled = await Promise.allSettled(queries.map((query) => search(query)));
  const results = settled.flatMap((item) => (item.status === 'fulfilled' ? item.value : []));
  const unique = [...new Map(results.filter((item) => item.url).map((item) => [item.url, item])).values()];

  if (unique.length === 0) {
    const reasons = settled
      .filter((item) => item.status === 'rejected')
      .map((item) => item.reason?.message)
      .filter(Boolean);
    throw new Error(`web research returned no results${reasons.length ? `: ${reasons[0]}` : ''}`);
  }

  return { queries, provider: unique[0].provider, results: unique.slice(0, 12) };
}
