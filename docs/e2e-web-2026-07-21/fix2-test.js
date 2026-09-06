// Fix 2: xvfb with headless: false (real browser window on virtual display)
const { chromium } = require('playwright');
const path = require('path');

const FULL_CHROME = path.join(process.env.HOME, '.cache/ms-playwright/chromium-1228/chrome-linux64/chrome');

(async () => {
  console.log('=== FIX 2: xvfb + headless:false ===');
  const browser = await chromium.launch({
    headless: false,
    executablePath: FULL_CHROME,
    args: [
      '--no-sandbox',
      '--disable-gpu',
      '--disable-dev-shm-usage',
    ],
  });
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
  });
  const page = await ctx.newPage();

  page.on('console', msg => {
    const t = msg.type();
    if (t === 'error' || t === 'warning') console.log(`[${t}]: ${msg.text().substring(0, 150)}`);
  });

  console.log('Navigate to site...');
  await page.goto('https://bora-app-web.pages.dev', { waitUntil: 'networkidle', timeout: 60000 });
  console.log('Waiting 20s for Flutter render...');
  await page.waitForTimeout(20000);

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
      canvasSize: canvas ? `${canvas.width}x${canvas.height}` : null,
      totalElements: document.querySelectorAll('*').length,
      semanticsCount: sems.length,
      labeledCount: labeled.length,
      labels: Array.from(labeled).map(e => e.getAttribute('aria-label')).slice(0, 15),
    };
  });
  console.log('STATE:', JSON.stringify(state, null, 2));

  const shotPath = path.join(__dirname, 'fix2-xvfb.png');
  await page.screenshot({ path: shotPath });
  const size = require('fs').statSync(shotPath).size;
  console.log(`Screenshot: ${shotPath} (${size} bytes)`);

  if (state.gpChildren > 0 || state.hasCanvas || state.semanticsCount > 0) {
    console.log('\n✅ FIX 2 SUCCESS — Flutter rendered!');
  } else {
    console.log('\n❌ FIX 2 FAILED — flt-glass-pane still empty');
  }

  await browser.close();
})();
