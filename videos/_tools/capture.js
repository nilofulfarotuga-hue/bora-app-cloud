// capture.js — capturas reais de um app web (Flutter) em viewport de telemóvel.
// uso: node _tools/capture.js --url https://... --out dir --name home [--wait 12000] [--w 390 --h 844] [--clicks "x,y;x,y"]
const path = require('path'); const fs = require('fs');
const { chromium } = require('playwright');
const args = {}; for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : true; args[k] = v; } }
const W = parseInt(args.w || '390'), H = parseInt(args.h || '844');
(async () => {
  fs.mkdirSync(args.out, { recursive: true });
  const browser = await chromium.launch({ args: ['--disable-gpu', '--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: 'pt-PT' });
  const page = await ctx.newPage();
  await page.goto(args.url, { waitUntil: 'load', timeout: 90000 });
  await page.waitForTimeout(parseInt(args.wait || '12000'));
  let k = 0;
  const shot = async (suffix) => { const f = path.join(args.out, `${args.name}${suffix}.png`); await page.screenshot({ path: f }); console.log('shot', f); };
  await shot('');
  if (args.clicks) { for (const c of args.clicks.split(';')) { const [x, y] = c.split(',').map(Number); await page.mouse.click(x, y); await page.waitForTimeout(3500); k++; await shot('_' + k); } }
  if (args.scroll) { await page.mouse.wheel(0, parseInt(args.scroll)); await page.waitForTimeout(1500); await shot('_scroll'); }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
