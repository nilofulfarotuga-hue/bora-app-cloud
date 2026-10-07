// _engine.js — motor partilhado dos 4 clips da Semente da Luz (palco responsivo + kf)
const $ = id => document.getElementById(id);
const E = { lin: p => p, out: p => 1 - Math.pow(1 - p, 3), in: p => p * p * p, io: p => p < .5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2, pop: p => 1 - Math.exp(-7 * p) * Math.cos(2 * Math.PI * 1.1 * p), soft: p => 1 - Math.pow(1 - p, 4), inq: p => p * p };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v)); const lerp = (a, b, p) => a + (b - a) * p;
const prog = (t, t0, t1, e = 'out') => E[e](clamp((t - t0) / (t1 - t0), 0, 1));
function kf(el, keys, t) {
  const def = { x: 0, y: 0, s: 1, o: 1, r: 0 }; const full = []; let cur = { ...def };
  for (const k of keys) { cur = { ...cur, ...k }; full.push(cur); }
  let st; if (t <= full[0].t) st = full[0]; else if (t >= full[full.length - 1].t) st = full[full.length - 1];
  else { let i = 1; while (full[i].t < t) i++; const a = full[i - 1], b = full[i]; const p = E[b.e || 'out']((t - a.t) / (b.t - a.t)); st = { x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p), s: lerp(a.s, b.s, p), o: lerp(a.o, b.o, p), r: lerp(a.r, b.r, p) }; }
  apply(el, st); return st;
}
function apply(el, st) { const base = el.dataset.base || ''; el.style.transform = `${base} translate(${st.x}px, ${st.y}px) scale(${st.s}) rotate(${st.r}deg)`; el.style.opacity = st.o; el.classList.toggle('hidden', st.o <= 0.001); }
const PORT = window.innerHeight > window.innerWidth; document.body.classList.add(PORT ? 'port' : 'land');
const SW = PORT ? 1080 : 1920, SH = PORT ? 1920 : 1080;
function fitStage() { const s = Math.min(window.innerWidth / SW, window.innerHeight / SH); $('stage').style.transform = `scale(${s})`; }
function ready() { Promise.all([document.fonts.load('900 1em Inter'), document.fonts.load('400 1em Inter'), ...[...document.images].map(i => i.decode().catch(() => { }))]).then(() => { window.seek(0); window.__ready = true; }); }
// ruído determinístico (para o mesmo t dar sempre o mesmo frame)
function hash(n) { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); }
