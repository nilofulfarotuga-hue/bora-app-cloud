import { chromium } from 'playwright';
import fs from 'fs';

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  locale: 'pt-PT',
});
const page = await ctx.newPage();

// Capture all JSON responses
const jsonCalls = [];
page.on('response', async (r) => {
  const url = r.url();
  const ct = r.headers()['content-type'] || '';
  if (ct.includes('json')) {
    try {
      const text = await r.text();
      jsonCalls.push({ url, status: r.status(), size: text.length, sample: text.slice(0, 600) });
    } catch {}
  }
});

try {
  await page.goto('https://www.lidl.pt/h/frutas-e-legumes/h10071012', { waitUntil: 'networkidle', timeout: 45000 });
} catch (e) {
  console.log('goto err:', String(e).slice(0, 100));
}
await new Promise(r => setTimeout(r, 5000));

const info = await page.evaluate(() => {
  // Find product-looking elements
  const tiles = document.querySelectorAll('[data-testid*="product"], [class*="product-tile"], [class*="ProductTile"]');
  const firstHtml = tiles.length ? tiles[0].outerHTML.slice(0, 2500) : null;
  const allImgs = [...document.querySelectorAll('img')].map(i => i.src).filter(s => s && !s.startsWith('data:')).slice(0, 10);
  return {
    url: location.href,
    title: document.title,
    tileCount: tiles.length,
    firstTileHtml: firstHtml,
    sampleImgs: allImgs,
    prices: [...document.querySelectorAll('[class*="price"],[class*="Price"]')].slice(0, 5).map(e => e.textContent.trim().slice(0, 50)),
  };
});

// Filter relevant API calls
const relevant = jsonCalls.filter(c =>
  !/translation|i18n|locale|analytics|consent|gtm|ensighten/i.test(c.url)
);

fs.writeFileSync('scripts/scraper/_lidl_cat.json', JSON.stringify({
  info,
  relevantCalls: relevant.slice(0, 20),
  allCallsCount: jsonCalls.length,
}, null, 2));
await browser.close();
console.log('DONE relevant=' + relevant.length + ' total=' + jsonCalls.length);
