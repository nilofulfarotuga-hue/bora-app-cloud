// render.js — render frame a frame de um index.html com seek(t) global.
// uso: node _tools/render.js --html proj/index.html --w 1920 --h 1080 --dur 25 --out proj/frames_16x9 [--draft] [--fps 30] [--from 0] [--to N]
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) {
    const k = a.slice(2);
    const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : true;
    args[k] = v;
  }
}
const html = path.resolve(args.html);
let W = parseInt(args.w || '1920', 10), H = parseInt(args.h || '1080', 10);
const fps = parseInt(args.fps || '30', 10);
const dur = parseFloat(args.dur);
const out = path.resolve(args.out);
const draft = !!args.draft;
const BATCH = parseInt(args.batch || '300', 10);
if (!dur) { console.error('--dur obrigatório'); process.exit(2); }
const total = Math.round(dur * fps);
const from = parseInt(args.from || '0', 10);
const to = Math.min(total, parseInt(args.to || String(total), 10));
if (draft) { const s = W > H ? 854 / W : 480 / W; W = Math.round(W * s / 2) * 2; H = Math.round(H * s / 2) * 2; }
fs.mkdirSync(out, { recursive: true });
const ext = draft ? 'jpg' : 'png';

(async () => {
  const t0 = Date.now();
  let i = from;
  while (i < to) {
    const end = Math.min(to, i + BATCH);
    const browser = await chromium.launch({ args: ['--disable-gpu', '--no-sandbox', '--font-render-hinting=none'] });
    const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
    page.on('pageerror', e => console.error('PAGEERROR', e.message));
    await page.goto('file:///' + html.replace(/\\/g, '/'), { waitUntil: 'load' });
    await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
    for (; i < end; i++) {
      const t = i / fps;
      await page.evaluate(t => window.seek(t), t);
      const file = path.join(out, `f${String(i).padStart(5, '0')}.${ext}`);
      await page.screenshot({ path: file, type: draft ? 'jpeg' : 'png', quality: draft ? 85 : undefined, animations: 'disabled', caret: 'hide' });
      if (i % 30 === 0) process.stdout.write(`frame ${i}/${total} (${((Date.now() - t0) / 1000).toFixed(0)}s)\n`);
    }
    await browser.close();
  }
  const n = fs.readdirSync(out).filter(f => f.endsWith('.' + ext)).length;
  console.log(`DONE frames=${n} esperados=${total} size=${W}x${H} seg=${((Date.now() - t0) / 1000).toFixed(0)}`);
  if (n !== total && from === 0 && to === total) process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
