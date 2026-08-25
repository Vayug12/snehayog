import http from 'node:http';
import https from 'node:https';

const postData = new URLSearchParams({ q: 'startup funding news this week', kl: 'us-en' }).toString();

const options = {
  hostname: 'html.duckduckgo.com',
  port: 443,
  path: '/html/',
  method: 'POST',
  timeout: 15000,
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': 'https://html.duckduckgo.com',
    'Referer': 'https://html.duckduckgo.com/',
    'Content-Length': Buffer.byteLength(postData),
  },
};

const req = https.request(options, (res) => {
  console.log('Status:', res.statusCode);
  console.log('Headers:', JSON.stringify(res.headers, null, 2));
  let body = '';
  res.on('data', (chunk) => body += chunk);
  res.on('end', () => {
    console.log('Body length:', body.length);
    
    const results = [...body.matchAll(/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)];
    console.log('result__a matches:', results.length);

    const snippets = [...body.matchAll(/<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/gi)];
    console.log('result__snippet matches:', snippets.length);

    const allLinks = [...body.matchAll(/<a[^>]+class="([^"]+)"[^>]*>/gi)];
    const classes = [...new Set(allLinks.map(m => m[1]))];
    console.log('All link classes:', classes);

    if (body.toLowerCase().includes('captcha')) console.log('>>> CAPTCHA detected!');
    if (body.toLowerCase().includes('blocked')) console.log('>>> Blocked!');
    if (body.toLowerCase().includes('robot')) console.log('>>> Robot check!');

    console.log('\n--- HTML (first 3000 chars) ---');
    console.log(body.substring(0, 3000));
  });
});

req.on('error', (e) => console.error('Request error:', e.message));
req.on('timeout', () => { console.error('Request timed out'); req.destroy(); });
req.write(postData);
req.end();
