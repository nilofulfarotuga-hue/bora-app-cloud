// Lidl probe with Playwright + capture network JSON to find real API endpoint
import { chromium } from 'playwright';
import fs from 'fs';

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  locale: 'pt-PT',
});
const page = await ctx.newPage();

const jsonCalls = [];
page.on('response', async (r) => {
  const url = r.url();
  const ct = r.headers()['content-type'] || '';
  if (ct.includes('json') && /product|search|catalog|item|campaign|api/i.test(url)) {
    try {
      const text = await r.text();
      jsonCalls.push({ url, status: r.status(), ct, size: text.length, sample: text.slice(0, 400) });
    } catch {}
  }
});

try {
  await page.goto('https://www.lidl.pt/', { waitUntil: 'networkidle', timeout: 30000 });
} catch (e) {}
await new Promise(r => setTimeout(r, 3000));

// Collect product-looking anchors
const anchors = await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('a[href]').forEach(a => {
    const h = a.getAttribute('href');
    if (h && /\/p\/|\/h\/|\/c\/|product/i.test(h)) out.push(h);
  });
  return [...new Set(out)].slice(0, 30);
});

// Try navigating to an actual product page from links
let productPageInfo = {};
try {
  // Try a known catalog URL (Nossa Gama)
  await page.goto('https://www.lidl.pt/h/nossa-gama', { waitUntil: 'networkidle', timeout: 20000 });
  await new Promise(r => setTimeout(r, 3000));
  productPageInfo = await page.evaluate(() => ({
    title: document.title,
    hasProducts: document.querySelectorAll('[class*="product"],[data-product-id],article').length,
    nuxtData: !!document.querySelector('#__nuxt, #__NUXT__'),
    url: location.href,
  }));
} catch (e) { productPageInfo = { error: String(e).slice(0, 200) }; }

fs.writeFileSync('scripts/scraper/_lidl_spike.json', JSON.stringify({
  anchors,
  productPageInfo,
  jsonCalls: jsonCalls.slice(0, 15).map(c => ({...c, sample: c.sample.slice(0, 300)})),
}, null, 2));
await browser.close();
console.log('DONE jsonCalls=' + jsonCalls.length + ' anchors=' + anchors.length);
