// Test if Node's native fetch works with DDG
const postData = new URLSearchParams({ q: 'startup funding news this week', kl: 'us-en' }).toString();

fetch('https://html.duckduckgo.com/html/', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html',
    'Origin': 'https://html.duckduckgo.com',
    'Referer': 'https://html.duckduckgo.com/',
  },
  body: postData,
  signal: AbortSignal.timeout(15000),
}).then(r => {
  console.log('Status:', r.status);
  return r.text();
}).then(html => {
  console.log('Body length:', html.length);
  const results = [...html.matchAll(/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)];
  console.log('result__a matches:', results.length);
}).catch(e => {
  console.error('FETCH FAILED:', e.name, e.message);
  console.error('Cause:', e.cause);
});
