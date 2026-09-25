'use strict';
/**
 * .ai_acai_crawl.js — crawl Sabores de Casa Açaí (Glovo store 582135 / addr 937558).
 * Captures products + FULL attributeGroups (modifiers) — NOT expanded into separate products
 * (modifiers go to product_option_groups / product_option_items). Follows section paths +
 * CONTENT_PLACEHOLDER defensively. Price = Glovo raw (builder applies partner real prices).
 * Output: .ai_acai_products.json = [{id,name,description,price,img,root,groups:[{name,min,max,multiple,items:[{name,priceAdd}]}]}]
 */
const https = require('https'); const fs = require('fs');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const STORE = '582135', ADDR = '937558';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function get(path) { return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); }); }
const priceOf = d => (d.price != null ? d.price : (d.priceInfo && d.priceInfo.amount != null ? d.priceInfo.amount : null));
function mapGroups(d) {
  const out = [];
  for (const ag of (d.attributeGroups || [])) {
    const items = [];
    for (const at of (ag.attributes || ag.elements || [])) {
      const add = at.priceImpact != null ? at.priceImpact : (at.price != null ? at.price : 0);
      items.push({ name: String(at.name || '').trim().replace(/\s+/g, ' '), priceAdd: Math.round((add || 0) * 100) / 100 });
    }
    out.push({ name: String(ag.name || '').trim().replace(/\s+/g, ' '), min: ag.min != null ? ag.min : 0, max: ag.max != null ? ag.max : 1, multiple: !!ag.multipleSelection, items });
  }
  return out;
}
const prods = new Map();
function walk(o, root, links) {
  if (!o || typeof o !== 'object') return;
  if (Array.isArray(o)) { for (const x of o) walk(x, root, links); return; }
  if (o.type === 'LIST' && o.data && o.data.title) root = o.data.title;
  if ((o.type === 'GRID' || o.type === 'CAROUSEL') && o.data && o.data.title) root = root || o.data.title;
  if ((o.type === 'PRODUCT_ROW' || o.type === 'PRODUCT_TILE') && o.data && o.data.storeProductId) {
    const d = o.data, p = priceOf(d);
    if (d.name && p != null && !prods.has(d.storeProductId)) prods.set(d.storeProductId, { id: d.storeProductId, name: String(d.name).trim().replace(/\s+/g, ' '), description: (d.description || '').trim() || null, price: p, img: d.imageUrl || null, root: root || 'Outros', groups: mapGroups(d) });
  }
  if (o.type === 'COLLECTION_TILE' && o.data && o.data.action && o.data.action.data && o.data.action.data.path) links.push({ path: o.data.action.data.path, root });
  if (o.type === 'CONTENT_PLACEHOLDER' && o.data && o.data.contentUri) links.push({ path: o.data.contentUri, root });
  for (const k of Object.keys(o)) walk(o[k], root, links);
}
function normPath(p) { const i = p.indexOf('&link='); if (i < 0) return p; const head = p.slice(0, i + 6); let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} return head + encodeURIComponent(link); }
(async () => {
  const home = await get('/v3/stores/' + STORE + '/addresses/' + ADDR + '/content');
  if (home.status !== 200) { console.error('home fail ' + home.status); process.exit(1); }
  const j = JSON.parse(home.body);
  const sections = [];
  (function collect(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) { o.forEach(collect); return; } if (o.type === 'LIST' && o.data && o.data.title) { const path = o.data.action && o.data.action.data && o.data.action.data.path; sections.push({ title: o.data.title, path: path || '' }); } for (const k of Object.keys(o)) collect(o[k]); })(j);
  const seenT = new Set(); const ordered = sections.filter(s => !seenT.has(s.title) && seenT.add(s.title));
  console.log('sections=' + ordered.length + ' :: ' + ordered.map(s => s.title).join(' | '));
  const links = []; walk(j, null, links);
  console.log('after home inline products=' + prods.size);
  const queue = []; const seenP = new Set();
  for (const s of ordered) if (s.path) { const np = normPath(s.path); if (!seenP.has(np)) { seenP.add(np); queue.push({ path: np, root: s.title }); } }
  for (const l of links) { const np = normPath(l.path); if (!seenP.has(np)) { seenP.add(np); queue.push({ path: np, root: l.root }); } }
  let fetched = 0;
  while (queue.length && fetched < 60) {
    const it = queue.shift(); const r = await get(it.path); fetched++;
    if (r.status === 200) { try { const more = []; walk(JSON.parse(r.body), it.root, more); for (const l of more) { const np = normPath(l.path); if (!seenP.has(np)) { seenP.add(np); queue.push({ path: np, root: it.root || l.root }); } } } catch {} }
    await sleep(700);
  }
  const arr = [...prods.values()];
  fs.writeFileSync('.ai_acai_products.json', JSON.stringify(arr));
  const byRoot = {}; let withGroups = 0, totalGroups = 0, noImg = 0;
  for (const p of arr) { byRoot[p.root] = (byRoot[p.root] || 0) + 1; if (p.groups.length) withGroups++; totalGroups += p.groups.length; if (!p.img) noImg++; }
  console.log('DONE products=' + arr.length + ' withGroups=' + withGroups + ' totalGroups=' + totalGroups + ' noImg=' + noImg);
  console.log('byRoot=' + JSON.stringify(byRoot));
})();
