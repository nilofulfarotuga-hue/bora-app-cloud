// Spike to discover Pingo Doce structure
const { chromium } = require('playwright');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    locale: 'pt-PT',
  });
  const page = await ctx.newPage();

  const results = {};
  const candidates = [
    'https://www.pingodoce.pt/produtos/',
    'https://www.pingodoce.pt/',
    'https://mercador.pingodoce.pt/',
    'https://www.pingodoce.pt/compras-online/',
  ];

  for (const url of candidates) {
    try {
      const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
      const status = resp?.status() ?? 0;
      const finalUrl = page.url();
      const title = await page.title().catch(() => '');
      // count product-like elements
      const tiles = await page.locator('[class*="product"], [class*="Product"], article').count().catch(() => 0);
      const links = await page.locator('a[href*="/produto"]').count().catch(() => 0);
      results[url] = { status, finalUrl, title, tiles, productLinks: links };
    } catch (e) {
      results[url] = { error: String(e).slice(0, 200) };
    }
  }

  fs.writeFileSync('scripts/scraper/_pd_spike.json', JSON.stringify(results, null, 2));
  await browser.close();
  console.log('DONE');
})();
