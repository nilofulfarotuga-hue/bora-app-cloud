// Diagnostic v2: test real user gestures to activate Flutter semantics
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true });
  const page = await ctx.newPage();

  page.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') return;
    console.log(`[${msg.type()}]: ${msg.text().substring(0, 150)}`);
  });

  console.log('1. Navigate...');
  await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForTimeout(5000);

  // Dismiss iOS banner if present
  console.log('2. Dismiss iOS banner...');
  const dismissed = await page.evaluate(() => {
    const btn = document.querySelector('#bora-ios button.x, [aria-label="Fechar"]');
    if (btn) { btn.click(); return 'dismissed'; }
    return 'no_banner';
  });
  console.log(`   Banner: ${dismissed}`);
  await page.waitForTimeout(1000);

  // Check current state
  const state1 = await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    const els = document.querySelectorAll('flt-semantics');
    const labeled = document.querySelectorAll('flt-semantics[aria-label]');
    return {
      placeholderExists: !!ph,
      placeholderHidden: ph ? (ph.style.width === '1px' && ph.style.height === '1px') : null,
      totalSemantics: els.length,
      labeledCount: labeled.length,
    };
  });
  console.log('3. State before activation:', JSON.stringify(state1));

  // Method 1: Tab to focus placeholder, then Enter/Space
  console.log('4. Trying Tab + Enter on placeholder...');
  await page.keyboard.press('Tab');
  await page.waitForTimeout(500);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(2000);

  let state2 = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics[aria-label]');
    return { count: els.length, labels: Array.from(els).map(e => e.getAttribute('aria-label')).slice(0, 10) };
  });
  console.log('   After Tab+Enter:', JSON.stringify(state2));

  // Method 2: Click the placeholder directly with mouse
  console.log('5. Trying mouse click on placeholder...');
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) {
      // Make it bigger so mouse can hit it
      ph.style.width = '100%';
      ph.style.height = '100%';
      ph.style.left = '0';
      ph.style.top = '0';
    }
  });
  await page.waitForTimeout(500);
  // Click center of screen
  await page.mouse.click(195, 422);
  await page.waitForTimeout(2000);

  state2 = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics[aria-label]');
    return { count: els.length, labels: Array.from(els).map(e => e.getAttribute('aria-label')).slice(0, 10) };
  });
  console.log('   After mouse click:', JSON.stringify(state2));

  // Method 3: Focus + dispatch keyboard event
  console.log('6. Trying focus + Space...');
  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (ph) { ph.focus(); }
  });
  await page.waitForTimeout(300);
  await page.keyboard.press('Space');
  await page.waitForTimeout(2000);

  state2 = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics[aria-label]');
    return { count: els.length, labels: Array.from(els).map(e => e.getAttribute('aria-label')).slice(0, 15) };
  });
  console.log('   After Space:', JSON.stringify(state2));

  // Method 4: Try clicking on the flutter-view/glass-pane itself
  console.log('7. Clicking on glass-pane...');
  await page.evaluate(() => {
    const gp = document.querySelector('flt-glass-pane');
    if (gp) {
      const r = gp.getBoundingClientRect();
      console.log('glass-pane rect:', r);
    }
  });
  await page.mouse.click(195, 422);
  await page.waitForTimeout(3000);

  state2 = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics[aria-label]');
    const host = document.querySelector('flt-semantics-host');
    const hostChildren = host ? host.children.length : 0;
    return {
      count: els.length,
      labels: Array.from(els).map(e => e.getAttribute('aria-label')).slice(0, 20),
      hostChildren,
    };
  });
  console.log('   After glass-pane click:', JSON.stringify(state2));

  // Check what the semantics elements actually contain
  const semDetails = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics');
    return Array.from(els).map(el => ({
      role: el.getAttribute('role'),
      label: el.getAttribute('aria-label'),
      hidden: el.style.display === 'none',
      size: `${el.style.width}x${el.style.height}`,
    })).slice(0, 20);
  });
  console.log('8. Semantics details:', JSON.stringify(semDetails, null, 2));

  await page.screenshot({ path: '/root/bora-e2e-web/diagnostic2.png' });
  console.log('Screenshot saved');

  await browser.close();
})();
