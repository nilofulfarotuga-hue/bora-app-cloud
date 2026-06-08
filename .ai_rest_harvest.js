'use strict';
/**
 * .ai_rest_harvest.js — Glovo restaurant harvester (KFC/BK/McD model).
 * Restaurant content = LIST_VIEW_LAYOUT -> LIST (menu sections) -> data.elements[] -> PRODUCT_ROW.
 * Products (PRODUCT_ROW) are inline in the home content; each LIST also has an action.path
 * (?link={slug}) for the full section. category_root = LIST title. No -sc.{id} ids, so promo/
 * seasonal sections are excluded by TITLE keyword.
 *
 * Captures from home inline + follows each kept section path (completeness). Dedup by storeProductId.
 * Usage: node .ai_rest_harvest.js --store 363080 --addr 538047 --out .ai_kfc_harvest.json [--exclude-extra "regex"]
 */
const https = require('https');
const fs = require('fs');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const STORE = arg('store'), ADDR = arg('addr'), OUT = arg('out', 'rest_harvest.json');
const EXTRA = arg('exclude-extra', '');
// Promo/seasonal section titles to exclude (normalized, accent-stripped).
const EXCLUDE = new RegExp('(promoc|promo\\b|oferta|desconto|poupanc|novidade|destaque|mais vendidos|populares|tempo limitado|edicao limitada|dia da crianca|verao|natal|pascoa|halloween|black friday|volta as aulas|menu do dia|da semana|esta semana' + (EXTRA ? '|' + EXTRA : '') + ')', 'i');
function get(path) { return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); }); }
function norm(s) { return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
function excluded(title) { return EXCLUDE.test(norm(title)); }
const priceOf = d => (d.price != null ? d.price : (d.priceInfo && d.priceInfo.amount != null ? d.priceInfo.amount : null));

// Walk capturing PRODUCT_ROW tagged by nearest ancestor LIST title (root). Skips excluded sections.
function walk(o, root, prods, sections) {
  if (!o || typeof o !== 'object') return;
  if (Array.isArray(o)) { for (const x of o) walk(x, root, prods, sections); return; }
  if (o.type === 'LIST' && o.data && o.data.title) {
    root = o.data.title;
    if (sections) { const path = o.data.action && o.data.action.data && o.data.action.data.path; sections.push({ title: o.data.title, slug: o.data.slug || '', path: path || '' }); }
  }
  if (o.type === 'PRODUCT_ROW' && o.data && o.data.storeProductId) {
    const d = o.data; const p = priceOf(d);
    if (root && !excluded(root) && p != null && d.name && !prods.has(d.storeProductId)) {
      prods.set(d.storeProductId, { id: d.storeProductId, name: d.name, price: p, img: d.imageUrl || null, root, leaf: root });
    }
  }
  for (const k of Object.keys(o)) walk(o[k], root, prods, sections);
}

(async () => {
  const home = await get('/v3/stores/' + STORE + '/addresses/' + ADDR + '/content');
  if (home.status !== 200) { console.error('home fail', home.status); process.exit(1); }
  const prods = new Map(); const sections = [];
  walk(JSON.parse(home.body), null, prods, sections);
  // dedup section list, keep order, mark excluded
  const seenS = new Set(); const order = [];
  for (const s of sections) { if (seenS.has(s.title)) continue; seenS.add(s.title); order.push(s); }
  const kept = order.filter(s => !excluded(s.title));
  const skipped = order.filter(s => excluded(s.title));
  console.log('sections total=' + order.length + ' kept=' + kept.length + ' skipped=[' + skipped.map(s => s.title).join(' | ') + ']');
  console.log('after home inline: products=' + prods.size);
  // follow each kept section path for completeness (full list), force root=section.title
  for (const s of kept) {
    if (!s.path) continue;
    const r = await get(s.path); if (r.status !== 200) { await sleep(800); continue; }
    let j; try { j = JSON.parse(r.body); } catch { continue; }
    const before = prods.size;
    // walk but force the section root for any LIST without a title match
    walk(j, s.title, prods, null);
    const add = prods.size - before;
    if (add) console.log('  +' + add + ' from "' + s.title + '"');
    await sleep(900 + Math.floor(Math.random() * 400));
  }
  const arr = [...prods.values()];
  fs.writeFileSync(OUT, JSON.stringify(arr));
  const byRoot = {}; let noImg = 0, noPrice = 0;
  for (const p of arr) { byRoot[p.root] = (byRoot[p.root] || 0) + 1; if (!p.img) noImg++; if (p.price == null) noPrice++; }
  console.log('DONE products=' + arr.length + ' noImg=' + noImg + ' noPrice=' + noPrice);
  console.log('byRoot=' + JSON.stringify(byRoot));
  console.log('ORDER=' + JSON.stringify(kept.map(s => s.title)));
})();
