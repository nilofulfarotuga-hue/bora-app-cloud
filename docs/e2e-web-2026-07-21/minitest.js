// Minimal test — replicate exact diagnostic conditions
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();

  page.on('console', msg => {
    if (msg.type() === 'log') console.log(`[${msg.type()}]: ${msg.text().substring(0, 120)}`);
  });

  console.log('Navigate...');
  await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });
  console.log('networkidle reached. Waiting 8s...');
  await page.waitForTimeout(8000);

  // Check semantics
  const r1 = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics');
    const labeled = document.querySelectorAll('flt-semantics[aria-label]');
    const withRole = document.querySelectorAll('flt-semantics[role]');
    return { total: els.length, labeled: labeled.length, withRole: withRole.length,
      labels: Array.from(labeled).map(e => e.getAttribute('aria-label')).slice(0, 10) };
  });
  console.log('After 8s:', JSON.stringify(r1));

  // Try clicking placeholder
  console.log('Clicking placeholder...');
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) { ph.style.width = '100%'; ph.style.height = '100%'; ph.style.left = '0'; ph.style.top = '0'; }
  });
  await page.mouse.click(195, 422);
  await page.waitForTimeout(3000);

  const r2 = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics');
    const labeled = document.querySelectorAll('flt-semantics[aria-label]');
    return { total: els.length, labeled: labeled.length, labels: Array.from(labeled).map(e => e.getAttribute('aria-label')).slice(0, 10) };
  });
  console.log('After click:', JSON.stringify(r2));

  // Check DOM
  const dom = await page.evaluate(() => {
    const tags = {};
    document.querySelectorAll('*').forEach(el => { tags[el.tagName.toLowerCase()] = (tags[el.tagName.toLowerCase()]||0)+1; });
    return tags;
  });
  console.log('DOM:', JSON.stringify(dom));

  await page.screenshot({ path: '/root/bora-e2e-web/minitest.png' });
  await browser.close();
})();
