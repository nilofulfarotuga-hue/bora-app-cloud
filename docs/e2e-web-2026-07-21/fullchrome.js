// Test with full Chromium binary (not headless shell)
const { chromium } = require('playwright');
const path = require('path');

const FULL_CHROME = path.join(process.env.HOME, '.cache/ms-playwright/chromium-1228/chrome-linux64/chrome');

(async () => {
  console.log('Launching full Chrome...');
  const browser = await chromium.launch({
    headless: true,
    executablePath: FULL_CHROME,
    args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
  });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();

  page.on('console', msg => console.log(`[${msg.type()}]: ${msg.text().substring(0, 120)}`));

  console.log('Navigating...');
  await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });
  console.log('Waiting 10s for Flutter...');
  await page.waitForTimeout(10000);

  const state = await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host');
    const gp = document.querySelector('flt-glass-pane');
    const canvas = document.querySelector('canvas');
    const sems = document.querySelectorAll('flt-semantics');
    const labeled = document.querySelectorAll('flt-semantics[aria-label]');
    return {
      hostChildren: host ? host.children.length : -1,
      gpChildren: gp ? gp.children.length : -1,
      hasCanvas: !!canvas,
      totalElements: document.querySelectorAll('*').length,
      semanticsCount: sems.length,
      labeledCount: labeled.length,
      labels: Array.from(labeled).map(e => e.getAttribute('aria-label')).slice(0, 15),
    };
  });
  console.log('State:', JSON.stringify(state, null, 2));

  // If semantics found, try clicking
  if (state.semanticsCount > 0) {
    console.log('\nSemantics found! Clicking placeholder...');
    await page.evaluate(() => {
      const ph = document.querySelector('flt-semantics-placeholder');
      if (ph) { ph.style.width = '100%'; ph.style.height = '100%'; ph.style.left = '0'; ph.style.top = '0'; }
    });
    await page.mouse.click(195, 422);
    await page.waitForTimeout(3000);

    const after = await page.evaluate(() => {
      const labeled = document.querySelectorAll('flt-semantics[aria-label]');
      return { count: labeled.length, labels: Array.from(labeled).map(e => e.getAttribute('aria-label')).slice(0, 20) };
    });
    console.log('After click:', JSON.stringify(after, null, 2));
  }

  await page.screenshot({ path: '/root/bora-e2e-web/fullchrome.png' });
  console.log('Screenshot saved');
  await browser.close();
})();
