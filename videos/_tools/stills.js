// stills.js — frames-chave para avaliação: node _tools/stills.js --html proj/index.html --w 1920 --h 1080 --times "0.5,2.8,5.2" --out proj/stills.jpg [--cols 4]
const path = require('path'); const fs = require('fs'); const os = require('os');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const args = {}; for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : true; args[k] = v; } }
const html = path.resolve(args.html); let W = parseInt(args.w || '1920'), H = parseInt(args.h || '1080');
const s = W > H ? 854 / W : 480 / W; W = Math.round(W * s / 2) * 2; H = Math.round(H * s / 2) * 2;
const times = args.times.split(',').map(Number); const cols = parseInt(args.cols || '4');
(async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'stills-'));
  const browser = await chromium.launch({ args: ['--disable-gpu', '--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  page.on('pageerror', e => console.error('PAGEERROR', e.message));
  await page.goto('file:///' + html.replace(/\\/g, '/'));
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
  const files = [];
  for (let i = 0; i < times.length; i++) { await page.evaluate(t => window.seek(t), times[i]); const f = path.join(tmp, `s${i}.png`); await page.screenshot({ path: f }); files.push(f); }
  await browser.close();
  const rows = Math.ceil(times.length / cols);
  const inputs = []; files.forEach(f => inputs.push('-i', f));
  const draw = times.map(() => 'null');
  const fc = files.map((_, i) => `[${i}:v]${draw[i]}[v${i}]`).join(';') + ';' + files.map((_, i) => `[v${i}]`).join('') + `xstack=inputs=${files.length}:layout=${files.map((_, i) => `${(i % cols)}_${Math.floor(i / cols)}`).map(p => { const [c, r] = p.split('_'); return `${c * W}_${r * H}`; }).join('|')}${files.length < cols * rows ? ':fill=black' : ''}[o]`;
  execFileSync('ffmpeg', ['-y', '-v', 'error', ...inputs, '-filter_complex', fc, '-map', '[o]', '-q:v', '4', path.resolve(args.out)]);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('OK', args.out);
})().catch(e => { console.error(e); process.exit(1); });
