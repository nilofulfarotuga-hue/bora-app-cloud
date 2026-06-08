'use strict';
/**
 * .ai_rest_harvest_v2.js — Glovo restaurant harvester WITH size-variant expansion.
 * Same base capture as v1 (LIST sections -> PRODUCT_ROW, inline + follow action.path, exclude promo
 * by title, dedup by storeProductId). NEW: for each product, expand its SIZE attributeGroup
 * ("Selecione o Tamanho" / size) into one extra product per non-zero priceImpact option.
 * Does NOT expand choice groups (bebida/acompanhamento) nor add-on groups (molho/complemento).
 * Variant: id={storeProductId}-s{attrId}, name="{base} ({size})", price=base+priceImpact (Glovo €).
 * Decision by Danilo 2026-06-08: "Expandir só TAMANHOS".
 * Usage: node .ai_rest_harvest_v2.js --store 215649 --addr 346436 --out .ai_mcd_v2.json
 */
const https = require('https');
const fs = require('fs');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const STORE = arg('store'), ADDR = arg('addr'), OUT = arg('out', 'rest_harvest_v2.json');
const EXTRA = arg('exclude-extra', '');
const EXCLUDE = new RegExp('(promoc|promo\\b|oferta|desconto|poupanc|novidade|destaque|mais vendidos|populares|tempo limitado|edicao limitada|dia da crianca|dia da mae|dia do pai|verao|natal|pascoa|halloween|black friday|volta as aulas|menu do dia|da semana|esta semana' + (EXTRA ? '|' + EXTRA : '') + ')', 'i');
function get(path) { return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); }); }
function norm(s) { return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
function excluded(title) { return EXCLUDE.test(norm(title)); }
const priceOf = d => (d.price != null ? d.price : (d.priceInfo && d.priceInfo.amount != null ? d.priceInfo.amount : null));
// SIZE groups only: group name contains "tamanho" or "size". Returns [{name, delta, attrId}] for priceImpact!=0.
function sizeVariants(d) {
  const out = [];
  for (const ag of (d.attributeGroups || [])) {
    if (!/\btamanho\b|\bsize\b|\btamanhos\b/.test(norm(ag.name || ''))) continue;
    for (const at of (ag.attributes || [])) {
      const delta = at.priceImpact != null ? at.priceImpact : (at.price != null ? at.price : 0);
      if (delta && delta !== 0) out.push({ name: String(at.name || '').trim(), delta, attrId: at.attributeId || at.id });
    }
  }
  return out;
}
// Clean a Glovo size label: drop "(Large)" etc., normalise "Grande P"->Grande, "Media"->Média.
function cleanSize(s) { let t = String(s || '').trim(); t = t.replace(/\s*\([^)]*\)\s*/g, ' ').trim(); t = t.replace(/\bgrande\s*p\b/i, 'Grande').replace(/\bmedia\b/i, 'Média').replace(/\bmedio\b/i, 'Médio'); return t.replace(/\s+/g, ' ').trim(); }
// Build a clean variant name: strip a trailing size word from the base, append "(size)".
function variantName(baseName, sizeName) { const sz = cleanSize(sizeName); const stripped = String(baseName).replace(/\s*(pequen[ao]|m[ée]di[ao]|grande|small|medium|large)\s*$/i, '').trim(); return (stripped + ' (' + sz + ')').replace(/\s+/g, ' ').trim().slice(0, 250); }
let nVariants = 0;
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
      for (const v of sizeVariants(d)) {
        const vid = d.storeProductId + '-s' + v.attrId;
        if (v.name && !prods.has(vid)) { prods.set(vid, { id: vid, name: variantName(d.name, v.name), price: Math.round((p + v.delta) * 100) / 100, img: d.imageUrl || null, root, leaf: root, variant: true }); nVariants++; }
      }
    }
  }
  for (const k of Object.keys(o)) walk(o[k], root, prods, sections);
}
(async () => {
  const home = await get('/v3/stores/' + STORE + '/addresses/' + ADDR + '/content');
  if (home.status !== 200) { console.error('home fail', home.status); process.exit(1); }
  const prods = new Map(); const sections = [];
  walk(JSON.parse(home.body), null, prods, sections);
  const seenS = new Set(); const order = [];
  for (const s of sections) { if (seenS.has(s.title)) continue; seenS.add(s.title); order.push(s); }
  const kept = order.filter(s => !excluded(s.title));
  const skipped = order.filter(s => excluded(s.title));
  console.log('sections total=' + order.length + ' kept=' + kept.length + ' skipped=[' + skipped.map(s => s.title).join(' | ') + ']');
  for (const s of kept) {
    if (!s.path) continue;
    const r = await get(s.path); if (r.status !== 200) { await sleep(800); continue; }
    let j; try { j = JSON.parse(r.body); } catch { continue; }
    walk(j, s.title, prods, null);
    await sleep(900 + Math.floor(Math.random() * 400));
  }
  const arr = [...prods.values()];
  fs.writeFileSync(OUT, JSON.stringify(arr));
  const byRoot = {}; let noImg = 0, noPrice = 0, base = 0, vars = 0;
  for (const p of arr) { byRoot[p.root] = (byRoot[p.root] || 0) + 1; if (!p.img) noImg++; if (p.price == null) noPrice++; if (p.variant) vars++; else base++; }
  console.log('DONE products=' + arr.length + ' (base=' + base + ' sizeVariants=' + vars + ') noImg=' + noImg + ' noPrice=' + noPrice);
  console.log('byRoot=' + JSON.stringify(byRoot));
  console.log('ORDER=' + JSON.stringify(kept.map(s => s.title)));
})();
