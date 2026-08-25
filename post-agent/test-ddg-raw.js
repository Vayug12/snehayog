import https from 'node:https';

const postData = new URLSearchParams({ q: 'startup funding news 2026', kl: 'us-en' }).toString();
const req = https.request(
  {
    hostname: 'html.duckduckgo.com',
    port: 443,
    path: '/html/',
    method: 'POST',
    timeout: 15000,
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
    console.log('Status:', res.statusCode);
    let body = '';
    res.on('data', (chunk) => (body += chunk));
    res.on('end', () => {
      console.log('Body length:', body.length);
      const aMatches = [...body.matchAll(/<a[^>]+class="result__a"/gi)];
      console.log('result__a tags:', aMatches.length);
      // Check if there's a "no results" message
      if (body.includes('no results') || body.includes('No results')) console.log('>>> NO RESULTS PAGE');
      if (body.includes('captcha') || body.includes('CAPTCHA')) console.log('>>> CAPTCHA');
      if (body.includes('robot') || body.includes('Robot')) console.log('>>> ROBOT CHECK');
      // Show relevant HTML
      const idx = body.indexOf('result__body');
      if (idx > -1) {
        console.log('\n--- result__body area ---');
        console.log(body.substring(idx, idx + 1500));
      } else {
        console.log('\n--- HTML around body tag ---');
        const bodyIdx = body.indexOf('<body');
        if (bodyIdx > -1) console.log(body.substring(bodyIdx, bodyIdx + 2000));
        else console.log(body.substring(0, 3000));
      }
    });
  },
);
req.on('error', (e) => console.error('Error:', e.message));
req.write(postData);
req.end();
