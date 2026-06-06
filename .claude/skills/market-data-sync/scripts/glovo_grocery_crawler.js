#!/usr/bin/env node
/**
 * glovo_grocery_crawler.js — Crawler real do catálogo de uma loja de mercearia Glovo.
 *
 * Implementa a Fase 1 (extracção) que o sync_template.js deixava como adapter por criar.
 * Descoberto/validado na sessão noturna 2026-06-06 (Auchan Guarda).
 *
 * API Glovo (server-side, SEM CORS — correr via Node, não no browser):
 *   - Catálogo raiz por categoria:  GET /v3/stores/{STORE}/addresses/{ADDR}/content?nodeUrl=/collections/{scId}
 *   - Subcoleções:  COLLECTION_TILE.data.action.data.path  ->  /v4/stores/.../content/main?nodeType=DEEP_LINK&link=...
 *   - Produto:  PRODUCT_TILE.data -> { storeProductId, name, price, imageUrl }
 *   - Match na DB Bora:  products.id = 'auc-' + storeProductId  (prefixo por loja)
 *
 * Como obter STORE/ADDR/scIds: abrir a página da loja (glovoapp.com/pt/pt/{cidade}/stores/{slug}),
 * capturar store/addr na chamada .../node/store_fees, e os ids `sc.{n}` dos tabs de categoria no HTML.
 *
 * Uso:  node glovo_grocery_crawler.js --store 124961 --addr 226966 --sc 23934462,... --out out.json
 * Saída: JSON array [{ id, name, price, img }]. Rate-limit ~1.5s. Preço Glovo grocery = preço de loja (base).
 */
'use strict';
const https = require('https');
const fs = require('fs');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const STORE = arg('store', '124961'), ADDR = arg('addr', '226966');
const OUT = arg('out', 'glovo_products.json');
const SCIDS = (arg('sc', '') || '').split(',').filter(Boolean);

function get(path) {
  return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); });
}
function normPath(p) { const i = p.indexOf('&link='); if (i < 0) return p; const head = p.slice(0, i + 6); let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} return head + encodeURIComponent(link); }
function walk(o, prods, cols) {
  if (o == null || typeof o !== 'object') return;
  if (Array.isArray(o)) { for (const x of o) walk(x, prods, cols); return; }
  if (o.type === 'PRODUCT_TILE' && o.data && o.data.storeProductId) prods.push({ id: o.data.storeProductId, name: o.data.name, price: o.data.price, img: o.data.imageUrl || null });
  if (o.type === 'COLLECTION_TILE' && o.data && o.data.action && o.data.action.data && o.data.action.data.path) cols.push(o.data.action.data.path);
  for (const k of Object.keys(o)) walk(o[k], prods, cols);
}
(async () => {
  if (!SCIDS.length) { console.error('missing --sc (comma-separated category sc ids)'); process.exit(2); }
  const queue = SCIDS.map(id => `/v3/stores/${STORE}/addresses/${ADDR}/content?nodeUrl=` + encodeURIComponent('/collections/' + id));
  const seen = new Set(queue); const products = new Map(); let fetched = 0, errors = 0;
  while (queue.length && fetched < 2000) {
    const path = queue.shift(); let r, t = 0;
    do { r = await get(path); if (r.status === 200) break; t++; await sleep(4000 * t); } while (t < 3);
    fetched++;
    if (r.status !== 200) { if (++errors > 60) break; continue; }
    let j; try { j = JSON.parse(r.body); } catch { continue; }
    const prods = [], cols = []; walk(j, prods, cols);
    for (const p of prods) if (!products.has(p.id)) products.set(p.id, p);
    for (const c of cols) { const np = normPath(c); if (!seen.has(np)) { seen.add(np); queue.push(np); } }
    if (fetched % 25 === 0) { fs.writeFileSync(OUT, JSON.stringify([...products.values()])); console.log('fetched=' + fetched + ' queue=' + queue.length + ' products=' + products.size); }
    await sleep(1200 + Math.floor(Math.random() * 600));
  }
  fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
  console.log('DONE products=' + products.size + ' errors=' + errors);
})();
