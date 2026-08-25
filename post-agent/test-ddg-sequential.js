// Test 3 sequential DDG requests like trending.js does
const DDG_DELAY_MS = 1500;
function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

const queries = [
  'startup funding news this week',
  'new startup launches',
  'founder stories startup',
];

async function searchDDG(query) {
  const res = await fetch('https://html.duckduckgo.com/html/', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html',
      'Origin': 'https://html.duckduckgo.com',
      'Referer': 'https://html.duckduckgo.com/',
    },
    body: new URLSearchParams({ q: query, kl: 'us-en' }).toString(),
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const html = await res.text();
  const results = [...html.matchAll(/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)];
  console.log(`  query: "${query}" => ${results.length} results`);
  return results.length;
}

(async () => {
  let total = 0;
  for (let i = 0; i < queries.length; i++) {
    if (i > 0) await delay(DDG_DELAY_MS);
    try {
      const count = await searchDDG(queries[i]);
      total += count;
    } catch (e) {
      console.log(`  query ${i} FAILED: ${e.name} ${e.message}`);
    }
  }
  console.log(`\nTotal results: ${total}`);
})();
