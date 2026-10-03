// Diagnostic: check Flutter CanvasKit semantics on the live site
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true });
  const page = await ctx.newPage();

  // Collect console
  page.on('console', (msg) => console.log(`CONSOLE [${msg.type()}]: ${msg.text().substring(0, 200)}`));
  page.on('pageerror', (err) => console.log(`PAGE_ERROR: ${err.message.substring(0, 200)}`));

  console.log('Navigating to site...');
  await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });
  console.log('Page loaded. Waiting 8s for Flutter boot...');
  await page.waitForTimeout(8000);

  // Check page structure
  const info = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    const flutterView = document.querySelector('flutter-view, flt-glass-pane');
    const semanticsPh = document.querySelector('flt-semantics-placeholder');
    const semantics = document.querySelectorAll('flt-semantics');
    const semanticsWithLabel = document.querySelectorAll('flt-semantics[aria-label]');
    const body = document.body.innerHTML.substring(0, 500);
    return {
      hasCanvas: !!canvas,
      canvasSize: canvas ? `${canvas.width}x${canvas.height}` : null,
      hasFlutterView: !!flutterView,
      hasSemanticsPlaceholder: !!semanticsPh,
      semanticsPlaceholderVisible: semanticsPh ? window.getComputedStyle(semanticsPh).display !== 'none' : false,
      totalSemantics: semantics.length,
      withLabels: semanticsWithLabel.length,
      labels: Array.from(semanticsWithLabel).map(el => el.getAttribute('aria-label')).slice(0, 20),
      bodySnippet: body,
    };
  });
  console.log('DIAGNOSTIC:', JSON.stringify(info, null, 2));

  // Try clicking the placeholder
  if (info.hasSemanticsPlaceholder) {
    console.log('Clicking semantics placeholder...');
    await page.evaluate(() => {
      const ph = document.querySelector('flt-semantics-placeholder');
      if (ph) ph.click();
    });
    await page.waitForTimeout(2000);
    const after = await page.evaluate(() => {
      const els = document.querySelectorAll('flt-semantics[aria-label]');
      return { count: els.length, labels: Array.from(els).map(el => el.getAttribute('aria-label')).slice(0, 20) };
    });
    console.log('AFTER CLICK:', JSON.stringify(after, null, 2));
  }

  // Try Tab
  console.log('Pressing Tab...');
  await page.keyboard.press('Tab');
  await page.waitForTimeout(1000);
  const afterTab = await page.evaluate(() => {
    const els = document.querySelectorAll('flt-semantics[aria-label]');
    return { count: els.length, labels: Array.from(els).map(el => el.getAttribute('aria-label')).slice(0, 20) };
  });
  console.log('AFTER TAB:', JSON.stringify(afterTab, null, 2));

  // Screenshot
  await page.screenshot({ path: '/root/bora-e2e-web/diagnostic.png' });
  console.log('Screenshot saved');

  // Check all DOM elements
  const domInfo = await page.evaluate(() => {
    const all = document.querySelectorAll('*');
    const tagCounts = {};
    for (const el of all) {
      const tag = el.tagName.toLowerCase();
      tagCounts[tag] = (tagCounts[tag] || 0) + 1;
    }
    return tagCounts;
  });
  console.log('DOM TAGS:', JSON.stringify(domInfo, null, 2));

  await browser.close();
})();
