'use strict';
/**
 * .ai_4lojas_harvest.js — Glovo Guarda harvester for stores whose categories are reached via
 * content/main?nodeType=DEEP_LINK&link=...-sc.{topId}/...  (Kiwoko/Leroy/Worten/Zippy),
 * NOT via /collections/{id} (which returns the store home for these stores).
 *
 * Seeds from the home's COLLECTION_TILE paths whose top scId is in NAMEMAP (promo/seasonal
 * tiles resolve to null root -> skipped). Never walks the home's inline promo PRODUCT_TILEs.
 * Reuses the proven walk()/rootFromPath()/normPath() logic from glovo_grocery_crawler.js.
 *
 * Usage: node .ai_4lojas_harvest.js --store 123602 --addr 224489 --names .ai_zippy_names.json --out .ai_zippy_harvest.json
 */
const https = require('https');
const fs = require('fs');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const STORE = arg('store'), ADDR = arg('addr'), OUT = arg('out', 'harvest.json');
const NAMEMAP = JSON.parse(fs.readFileSync(arg('names'), 'utf8'));
function get(path) { return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); }); }
function normPath(p) { const i = p.indexOf('&link='); if (i < 0) return p; const head = p.slice(0, i + 6); let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} return head + encodeURIComponent(link); }
function rootFromPath(p, fallback) { const i = p.indexOf('&link='); if (i < 0) return fallback; let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} const m = link.split('/')[0].match(/-sc\.(\d+)$/); return m && NAMEMAP[m[1]] ? NAMEMAP[m[1]] : fallback; }
function topSegFromPath(p) { const i = p.indexOf('&link='); if (i < 0) return null; let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} return link.split('/')[0]; }
function walk(o, root, leaf, prods, cols) {
  if (o == null || typeof o !== 'object') return;
  if (Array.isArray(o)) { for (const x of o) walk(x, root, leaf, prods, cols); return; }
  if ((o.type === 'GRID' || o.type === 'CAROUSEL') && o.data && o.data.title) leaf = o.data.title;
  if (o.type === 'PRODUCT_TILE' && o.data && o.data.storeProductId) {
    if (root && !prods.has(o.data.storeProductId)) prods.set(o.data.storeProductId, { id: o.data.storeProductId, name: o.data.name, price: o.data.price, img: o.data.imageUrl || null, root, leaf });
  }
  if (o.type === 'COLLECTION_TILE' && o.data && o.data.action && o.data.action.data && o.data.action.data.path) cols.push({ path: o.data.action.data.path, root: rootFromPath(o.data.action.data.path, root), leaf: o.data.title || leaf });
  if (o.type === 'CONTENT_PLACEHOLDER' && o.data && o.data.contentUri) cols.push({ path: o.data.contentUri, root, leaf: o.data.title || leaf });
  for (const k of Object.keys(o)) walk(o[k], root, leaf, prods, cols);
}
(async () => {
  const home = await get('/v3/stores/' + STORE + '/addresses/' + ADDR + '/content');
  if (home.status !== 200) { console.error('home fail', home.status, home.body.slice(0, 120)); process.exit(1); }
  const products = new Map(); const seen = new Set(); const queue = [];
  const seedCols = []; walk(JSON.parse(home.body), null, null, new Map(), seedCols); // discard home inline products (promo)
  const topSeeded = new Set();
  let seeded = 0;
  for (const c of seedCols) {
    if (!c.root) continue; // promo/seasonal/unknown -> skip
    const np = normPath(c.path);
    if (!seen.has(np)) { seen.add(np); queue.push({ path: np, root: c.root, leaf: c.leaf }); seeded++; }
    // also seed the full top-category landing (first link segment, e.g. caes-sc.38798985)
    const first = topSegFromPath(c.path); const m = first && first.match(/-sc\.(\d+)$/);
    if (m && NAMEMAP[m[1]] && !topSeeded.has(m[1])) {
      topSeeded.add(m[1]);
      const tp = '/v4/stores/' + STORE + '/addresses/' + ADDR + '/content/main?nodeType=DEEP_LINK&link=' + encodeURIComponent(first);
      if (!seen.has(tp)) { seen.add(tp); queue.push({ path: tp, root: NAMEMAP[m[1]], leaf: NAMEMAP[m[1]] }); seeded++; }
    }
  }
  console.log('seeds=' + seeded + ' topCats=' + topSeeded.size + ' (home tiles=' + seedCols.length + ')');
  let fetched = 0, errors = 0;
  while (queue.length && fetched < 9000) {
    const item = queue.shift(); let r, t = 0;
    do { r = await get(item.path); if (r.status === 200) break; t++; await sleep(4000 * t); } while (t < 3);
    fetched++;
    if (r.status !== 200) { if (++errors > 80) { console.error('too many errors, abort'); break; } continue; }
    let j; try { j = JSON.parse(r.body); } catch { continue; }
    const cols = []; walk(j, item.root, item.leaf, products, cols);
    for (const c of cols) { const np = normPath(c.path); if (!seen.has(np)) { seen.add(np); queue.push({ path: np, root: c.root || item.root, leaf: c.leaf }); } }
    if (fetched % 25 === 0) { fs.writeFileSync(OUT, JSON.stringify([...products.values()])); console.log('fetched=' + fetched + ' queue=' + queue.length + ' products=' + products.size); }
    await sleep(1100 + Math.floor(Math.random() * 500));
  }
  fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
  const byRoot = {}; let noImg = 0, noPrice = 0;
  for (const p of products.values()) { byRoot[p.root] = (byRoot[p.root] || 0) + 1; if (!p.img) noImg++; if (p.price == null) noPrice++; }
  console.log('DONE products=' + products.size + ' fetched=' + fetched + ' errors=' + errors + ' noImg=' + noImg + ' noPrice=' + noPrice);
  console.log('byRoot=' + JSON.stringify(byRoot));
})();
