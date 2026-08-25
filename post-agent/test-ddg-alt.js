import https from 'node:https';

function tryEndpoint(hostname, path, method, extraHeaders = {}) {
  return new Promise((resolve) => {
    const q = 'startup funding news 2026';
    let reqPath = path;
    let postData = null;
    const headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      ...extraHeaders,
    };
    if (method === 'GET') {
      reqPath = `${path}?q=${encodeURIComponent(q)}&kl=us-en`;
    } else {
      postData = new URLSearchParams({ q, kl: 'us-en' }).toString();
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      headers['Content-Length'] = Buffer.byteLength(postData);
    }
    const req = https.request({ hostname, port: 443, path: reqPath, method, timeout: 15000, headers }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        const hasResults = /result__a|result-link|links_main/i.test(body);
        const isChallenge = /anomaly|duck.*ascii|select all squares|challenge-form/i.test(body);
        console.log(`${method} https://${hostname}${path} -> status=${res.statusCode} len=${body.length} results=${hasResults} challenge=${isChallenge}`);
        resolve();
      });
    });
    req.on('error', (e) => { console.log(`${method} https://${hostname}${path} -> ERROR ${e.message}`); resolve(); });
    req.on('timeout', () => { req.destroy(); console.log(`${method} https://${hostname}${path} -> TIMEOUT`); resolve(); });
    if (postData) req.write(postData);
    req.end();
  });
}

await tryEndpoint('html.duckduckgo.com', '/html/', 'GET');
await tryEndpoint('lite.duckduckgo.com', '/lite/', 'GET');
await tryEndpoint('lite.duckduckgo.com', '/lite/', 'POST');
await tryEndpoint('duckduckgo.com', '/html/', 'GET');

// Check where duckduckgo.com/html/ redirects to
const req2 = https.request({ hostname: 'duckduckgo.com', port: 443, path: '/html/?q=test', method: 'GET', headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
  console.log('Redirect location:', res.headers.location);
  res.resume();
});
req2.end();
