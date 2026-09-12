// Deep diagnostic — investigate flt-semantics-host and Flutter a11y state
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-gpu'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('console', msg => console.log(`[${msg.type()}]: ${msg.text().substring(0, 150)}`));

  await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });

  // Check at intervals
  for (const wait of [2000, 5000, 8000, 12000, 15000]) {
    if (wait > 2000) await page.waitForTimeout(wait - (wait === 5000 ? 2000 : wait === 8000 ? 5000 : wait === 12000 ? 8000 : 12000));
    else await page.waitForTimeout(wait);

    const state = await page.evaluate(() => {
      const host = document.querySelector('flt-semantics-host');
      const ph = document.querySelector('flt-semantics-placeholder');
      const glassPane = document.querySelector('flt-glass-pane');
      return {
        hostExists: !!host,
        hostChildren: host ? host.children.length : 0,
        hostHTML: host ? host.innerHTML.substring(0, 200) : 'none',
        hostStyle: host ? host.getAttribute('style') : 'none',
        phStyle: ph ? { display: ph.style.display, w: ph.style.width, h: ph.style.height } : null,
        glassPaneChildren: glassPane ? glassPane.children.length : 0,
        totalElements: document.querySelectorAll('*').length,
        semanticsCount: document.querySelectorAll('flt-semantics').length,
      };
    });
    console.log(`\n@${wait}ms:`, JSON.stringify(state, null, 2));
  }

  // Try to force semantics via Flutter engine API
  console.log('\nTrying to force Flutter semantics...');
  const forced = await page.evaluate(() => {
    // Try to access Flutter engine
    const flt = window._flutter || window.flutter;
    if (flt) return 'flutter object found: ' + Object.keys(flt).join(',');

    // Try to find flutter-view and access its engine
    const fv = document.querySelector('flutter-view');
    if (fv) {
      const keys = Object.keys(fv);
      return 'flutter-view keys: ' + keys.join(',');
    }

    return 'no flutter object found';
  });
  console.log('Force result:', forced);

  // Check if there's a canvas (CanvasKit) vs no canvas (HTML renderer)
  const renderer = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    return { hasCanvas: !!canvas, canvasCount: document.querySelectorAll('canvas').length };
  });
  console.log('Renderer:', JSON.stringify(renderer));

  // Check the actual content of flt-glass-pane
  const gpContent = await page.evaluate(() => {
    const gp = document.querySelector('flt-glass-pane');
    if (!gp) return 'no glass-pane';
    return { children: gp.children.length, tags: Array.from(gp.children).map(c => c.tagName.toLowerCase()).join(',') };
  });
  console.log('Glass pane:', JSON.stringify(gpContent));

  await page.screenshot({ path: '/root/bora-e2e-web/deep-diag.png' });
  await browser.close();
})();
