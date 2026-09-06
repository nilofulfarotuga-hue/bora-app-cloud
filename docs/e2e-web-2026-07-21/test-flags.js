// Test different Chrome flags for Flutter rendering
const { chromium } = require('playwright');

const FLAG_SETS = [
  { name: 'swiftshader', args: ['--no-sandbox', '--use-gl=swiftshader', '--disable-gpu'] },
  { name: 'angle', args: ['--no-sandbox', '--use-angle=swiftshader', '--disable-gpu'] },
  { name: 'no-webgl', args: ['--no-sandbox', '--disable-gpu', '--disable-webgl', '--disable-webgl2'] },
  { name: 'headless-new', args: ['--no-sandbox', '--headless=new', '--disable-gpu'] },
  { name: 'ozone', args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader-webgl', '--enable-features=Vulkan'] },
  { name: 'enable-a11y', args: ['--no-sandbox', '--disable-gpu', '--enable-accessibility', '--force-renderer-accessibility'] },
];

(async () => {
  for (const { name, args } of FLAG_SETS) {
    console.log(`\n=== Testing: ${name} ===`);
    let browser;
    try {
      browser = await chromium.launch({ headless: true, args });
      const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
      const page = await ctx.newPage();

      await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });
      await page.waitForTimeout(8000);

      const state = await page.evaluate(() => {
        const host = document.querySelector('flt-semantics-host');
        const gp = document.querySelector('flt-glass-pane');
        const canvas = document.querySelector('canvas');
        return {
          hostChildren: host ? host.children.length : -1,
          gpChildren: gp ? gp.children.length : -1,
          hasCanvas: !!canvas,
          totalElements: document.querySelectorAll('*').length,
          semanticsCount: document.querySelectorAll('flt-semantics').length,
        };
      });
      console.log(`  Result: ${JSON.stringify(state)}`);
      await page.screenshot({ path: `/root/bora-e2e-web/test-${name}.png` });
    } catch (e) {
      console.log(`  ERROR: ${e.message.substring(0, 100)}`);
    } finally {
      if (browser) await browser.close();
    }
  }
})();
