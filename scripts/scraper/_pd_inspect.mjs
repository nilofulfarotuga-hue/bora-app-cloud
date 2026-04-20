import { chromium } from 'playwright';
import fs from 'fs';

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  locale: 'pt-PT',
});
const page = await ctx.newPage();

const apiCalls = [];
page.on('response', async (r) => {
  const url = r.url();
  const ct = r.headers()['content-type'] || '';
  if (ct.includes('json') && (url.includes('api') || url.includes('wp-json') || url.includes('graphql'))) {
    apiCalls.push({ url, status: r.status(), ct });
  }
});

await page.goto('https://www.pingodoce.pt/home/produtos', { waitUntil: 'networkidle', timeout: 40000 });
await new Promise(r => setTimeout(r, 5000));

// snapshot first product tile outerHTML
const firstTile = await page.evaluate(() => {
  const candidates = document.querySelectorAll('a[href*="/produto"]');
  if (!candidates.length) return null;
  const el = candidates[0].closest('article, [class*="product"], [class*="card"], div') || candidates[0];
  return el.outerHTML.slice(0, 2000);
});

// try to find category links
const categories = await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('a[href*="/produtos"]').forEach(a => {
    const href = a.getAttribute('href');
    const text = (a.textContent || '').trim();
    if (href && text) out.push({ href, text: text.slice(0, 80) });
  });
  return out.slice(0, 40);
});

// count products on page + try to see if there's pagination
const stats = await page.evaluate(() => {
  return {
    productLinks: document.querySelectorAll('a[href*="/produto"]').length,
    images: document.querySelectorAll('img').length,
    title: document.title,
    htmlLen: document.documentElement.outerHTML.length,
  };
});

fs.writeFileSync('scripts/scraper/_pd_inspect.json', JSON.stringify({
  firstTile,
  categories,
  stats,
  apiCalls: apiCalls.slice(0, 20),
}, null, 2));

await browser.close();
console.log('DONE');
