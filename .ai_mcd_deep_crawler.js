'use strict';
/**
 * .ai_mcd_deep_crawler.js — Deep Glovo crawler for McDonald's Guarda (store 215649 / addr 346436).
 * Combines two proven recipes:
 *   - restaurant model (.ai_rest_harvest_v2): LIST sections -> PRODUCT_ROW, follow action.path, SIZE-variant expansion.
 *   - grocery recursion (glovo_grocery_crawler): follow COLLECTION_TILE.action.data.path + CONTENT_PLACEHOLDER.contentUri,
 *     update leaf on GRID/CAROUSEL, walk recursively with path dedup.
 * Captures ALL sections (incl. Europoupança / Europoupança DUO / Chicken como Nunca / Mais vendidos / Novidades).
 * NOTHING is excluded — products are deduped by storeProductId; a real category always wins over a promo carousel
 * (addProduct upgrades root when the stored one is promo and a non-promo one is seen). Builder remaps to canonical cats.
 * Size variants only ("Selecione o Tamanho"). Price = Glovo € raw (NOT store price; builder overrides per Fonte A/B).
 * Usage: node .ai_mcd_deep_crawler.js --store 215649 --addr 346436 --out .ai_mcd_deep.json
 */
const https = require('https');
const fs = require('fs');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const STORE = arg('store', '215649'), ADDR = arg('addr', '346436'), OUT = arg('out', '.ai_mcd_deep.json');
function get(path) { return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); }); }
function norm(s) { return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
// promo/seasonal carousels — NOT excluded, only de-prioritised as a category source.
const PROMO = /(mais vendidos|populares|novidade|destaque|tempo limitado|edicao limitada|black friday|volta as aulas|recomendad|sugest)/i;
function isPromo(r) { return PROMO.test(norm(r || '')); }
const priceOf = d => (d.price != null ? d.price : (d.priceInfo && d.priceInfo.amount != null ? d.priceInfo.amount : null));
function sizeVariants(d) {
  const out = [];
  for (const ag of (d.attributeGroups || [])) {
    if (!/\btamanho|\bsize/.test(norm(ag.name || ''))) continue;
    for (const at of (ag.attributes || ag.elements || [])) {
      const delta = at.priceImpact != null ? at.priceImpact : (at.price != null ? at.price : 0);
      if (delta && delta !== 0) out.push({ name: String(at.name || '').trim(), delta, attrId: at.attributeId || at.id });
    }
  }
  return out;
}
function cleanSize(s) { let t = String(s || '').trim(); t = t.replace(/\s*\([^)]*\)\s*/g, ' ').trim(); t = t.replace(/\bgrande\s*p\b/i, 'Grande').replace(/\bmedia\b/i, 'Média').replace(/\bmedio\b/i, 'Médio'); return t.replace(/\s+/g, ' ').trim(); }
function variantName(b, s) { const sz = cleanSize(s); const st = String(b).replace(/\s*(pequen[ao]|m[ée]di[ao]|grande|small|medium|large)\s*$/i, '').trim(); return (st + ' (' + sz + ')').replace(/\s+/g, ' ').trim().slice(0, 250); }
function addProduct(prods, d, root, leaf) {
  const p = priceOf(d);
  if (!(d && d.storeProductId && d.name && p != null)) return;
  const id = d.storeProductId;
  if (!prods.has(id)) prods.set(id, { id, name: d.name, price: p, img: d.imageUrl || null, root, leaf });
  else { const ex = prods.get(id); if (isPromo(ex.root) && !isPromo(root)) { ex.root = root; ex.leaf = leaf; } }
  for (const v of sizeVariants(d)) {
    const vid = id + '-s' + v.attrId;
    if (!v.name) continue;
    if (!prods.has(vid)) prods.set(vid, { id: vid, name: variantName(d.name, v.name), price: Math.round((p + v.delta) * 100) / 100, img: d.imageUrl || null, root, leaf, variant: true });
    else { const ex = prods.get(vid); if (isPromo(ex.root) && !isPromo(root)) { ex.root = root; ex.leaf = leaf; } }
  }
}
function walk(o, root, leaf, prods, links) {
  if (!o || typeof o !== 'object') return;
  if (Array.isArray(o)) { for (const x of o) walk(x, root, leaf, prods, links); return; }
  if (o.type === 'LIST' && o.data && o.data.title) root = o.data.title;
  if ((o.type === 'GRID' || o.type === 'CAROUSEL') && o.data && o.data.title) leaf = o.data.title;
  if (o.type === 'PRODUCT_ROW' && o.data) addProduct(prods, o.data, root, leaf);
  if (o.type === 'PRODUCT_TILE' && o.data) addProduct(prods, o.data, root, leaf);
  if (o.type === 'COLLECTION_TILE' && o.data && o.data.action && o.data.action.data && o.data.action.data.path) links.push({ path: o.data.action.data.path, root, leaf: o.data.title || leaf });
  if (o.type === 'CONTENT_PLACEHOLDER' && o.data && o.data.contentUri) links.push({ path: o.data.contentUri, root, leaf: o.data.title || leaf });
  for (const k of Object.keys(o)) walk(o[k], root, leaf, prods, links);
}
function normPath(p) { const i = p.indexOf('&link='); if (i < 0) return p; const head = p.slice(0, i + 6); let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} return head + encodeURIComponent(link); }
(async () => {
  const home = await get('/v3/stores/' + STORE + '/addresses/' + ADDR + '/content');
  if (home.status !== 200) { console.error('home fail ' + home.status + ' :: ' + home.body.slice(0, 200)); process.exit(1); }
  const prods = new Map();
  // collect home sections (LIST) with follow paths
  const sections = [];
  (function collect(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) { o.forEach(collect); return; } if (o.type === 'LIST' && o.data && o.data.title) { const path = o.data.action && o.data.action.data && o.data.action.data.path; sections.push({ title: o.data.title, path: path || '' }); } for (const k of Object.keys(o)) collect(o[k]); })(JSON.parse(home.body));
  const seenT = new Set(); const ordered = [];
  for (const s of sections) { if (seenT.has(s.title)) continue; seenT.add(s.title); ordered.push(s); }
  console.log('home sections=' + ordered.length + ' :: ' + ordered.map(s => s.title).join(' | '));
  // capture home inline
  const homeLinks = []; walk(JSON.parse(home.body), null, null, prods, homeLinks);
  console.log('after home inline products=' + prods.size);
  // queue: real sections first, promo carousels last; then any collection/placeholder links
  const queue = []; const seenP = new Set();
  const realFirst = ordered.slice().sort((a, b) => (isPromo(a.title) ? 1 : 0) - (isPromo(b.title) ? 1 : 0));
  for (const s of realFirst) { if (s.path) { const np = normPath(s.path); if (!seenP.has(np)) { seenP.add(np); queue.push({ path: np, root: s.title, leaf: s.title }); } } }
  for (const l of homeLinks) { const np = normPath(l.path); if (!seenP.has(np)) { seenP.add(np); queue.push({ path: np, root: l.root || l.leaf, leaf: l.leaf }); } }
  let fetched = 0, errors = 0;
  while (queue.length && fetched < 400) {
    const it = queue.shift(); let r, t = 0;
    do { r = await get(it.path); if (r.status === 200) break; t++; await sleep(2500 * t); } while (t < 3);
    fetched++;
    if (r.status !== 200) { if (++errors > 40) break; continue; }
    let j; try { j = JSON.parse(r.body); } catch { continue; }
    const links = []; walk(j, it.root, it.leaf, prods, links);
    for (const l of links) { const np = normPath(l.path); if (!seenP.has(np)) { seenP.add(np); queue.push({ path: np, root: it.root || l.root, leaf: l.leaf }); } }
    await sleep(900 + Math.floor(Math.random() * 400));
  }
  const arr = [...prods.values()];
  fs.writeFileSync(OUT, JSON.stringify(arr));
  const byRoot = {}; let base = 0, vars = 0, noImg = 0;
  for (const p of arr) { byRoot[p.root] = (byRoot[p.root] || 0) + 1; if (p.variant) vars++; else base++; if (!p.img) noImg++; }
  console.log('DONE total=' + arr.length + ' base=' + base + ' variants=' + vars + ' noImg=' + noImg + ' fetched=' + fetched + ' errors=' + errors);
  console.log('byRoot=' + JSON.stringify(byRoot));
})();
