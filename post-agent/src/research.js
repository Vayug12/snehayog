import https from 'node:https';

const SEARCH_TIMEOUT_MS = 25000;
const MAX_RESULTS = 6;
const DDG_MAX_RETRIES = 2;
const DDG_RETRY_BASE_MS = 2000;

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

export async function searchBrave(query) {
  const url = new URL('https://api.search.brave.com/res/v1/web/search');
  url.searchParams.set('q', query);
  url.searchParams.set('count', String(MAX_RESULTS));
  const data = await fetchJson(url, {
    headers: {
      'X-Subscription-Token': process.env.BRAVE_API_KEY,
      'Accept': 'application/json',
    },
  });
  return (data.web?.results || []).map((item) => ({
    title: item.title,
    url: item.url,
    snippet: item.description,
    published: item.page_age || null,
    provider: 'brave',
  }));
}

function ddgHttpPost(query) {
  return new Promise((resolve, reject) => {
    const postData = new URLSearchParams({ q: query, kl: 'us-en' }).toString();
    const req = https.request(
      {
        hostname: 'html.duckduckgo.com',
        port: 443,
        path: '/html/',
        method: 'POST',
        timeout: SEARCH_TIMEOUT_MS,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html',
          'Accept-Language': 'en-US,en;q=0.9',
          'Origin': 'https://html.duckduckgo.com',
          'Referer': 'https://html.duckduckgo.com/',
          'Content-Length': Buffer.byteLength(postData),
        },
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          if (res.statusCode !== 200) return reject(new Error(`DuckDuckGo HTTP ${res.statusCode}`));
          resolve(body);
        });
      },
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('DuckDuckGo request timed out'));
    });
    req.write(postData);
    req.end();
  });
}

function parseDdgHtml(html) {
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

async function fetchDdgHtml(query) {
  // Try native fetch first
  const response = await fetch('https://html.duckduckgo.com/html/', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html',
      'Origin': 'https://html.duckduckgo.com',
      'Referer': 'https://html.duckduckgo.com/',
    },
    body: new URLSearchParams({ q: query, kl: 'us-en' }).toString(),
    signal: AbortSignal.timeout(SEARCH_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`DuckDuckGo fetch failed with HTTP ${response.status}`);
  return response.text();
}

async function searchDuckDuckGoHtml(query) {
  let lastError;
  for (let attempt = 0; attempt <= DDG_MAX_RETRIES; attempt++) {
    try {
      let html;
      try {
        html = await fetchDdgHtml(query);
      } catch {
        // fetch failed — fall back to https module
        html = await ddgHttpPost(query);
      }
      const parsed = parseDdgHtml(html);
      if (parsed.length > 0) return parsed;
      lastError = new Error('DuckDuckGo returned empty results');
    } catch (error) {
      lastError = error;
    }
    if (attempt < DDG_MAX_RETRIES) {
      await new Promise((r) => setTimeout(r, DDG_RETRY_BASE_MS * 2 ** attempt));
    }
  }
  throw lastError;
}

export async function runSearch(query) {
  if (process.env.TAVILY_API_KEY) {
    return searchTavily(query);
  }
  if (process.env.BRAVE_API_KEY) {
    return searchBrave(query);
  }
  // Free: DuckDuckGo HTML (POST avoids CAPTCHA)
  return searchDuckDuckGoHtml(query);
}

export function buildQueries({ topic, projectName = 'Snehayog/Vayug' }) {
  const subject = topic || 'creator video monetization and audience growth';
  const year = new Date().getFullYear();
  // For long/complex topics, use shorter queries to avoid DDG returning nothing
  const words = subject.split(/\s+/);
  const shortTopic = words.length > 6 ? words.slice(0, 5).join(' ') : subject;
  return [
    `${shortTopic} ${year}`,
    `${shortTopic} latest news`,
    `${projectName} ${shortTopic}`,
  ];
}

const DDG_DELAY_MS = 1500;

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function research({ topic, projectName }) {
  const queries = buildQueries({ topic, projectName });

  // Run DDG queries sequentially with delay to avoid rate-limiting
  const settled = [];
  for (let i = 0; i < queries.length; i++) {
    if (i > 0 && !process.env.TAVILY_API_KEY && !process.env.BRAVE_API_KEY) {
      await delay(DDG_DELAY_MS);
    }
    settled.push(await Promise.allSettled([runSearch(queries[i])]).then((r) => r[0]));
  }
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
