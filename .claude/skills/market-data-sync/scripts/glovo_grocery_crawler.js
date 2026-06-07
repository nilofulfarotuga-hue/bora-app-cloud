#!/usr/bin/env node
/**
 * glovo_grocery_crawler.js — Crawler real do catálogo de uma loja de mercearia Glovo.
 *
 * Implementa a Fase 1 (extracção) que o sync_template.js deixava como adapter por criar.
 * Descoberto/validado 2026-06-06 (Auchan Guarda). Enriquecido com categoria por produto.
 *
 * API Glovo (server-side, SEM CORS — correr via Node, não no browser):
 *   - Catálogo raiz por categoria:  GET /v3/stores/{STORE}/addresses/{ADDR}/content?nodeUrl=/collections/{scId}
 *   - Subcoleções:  COLLECTION_TILE.data.action.data.path  ->  /v4/.../content/main?nodeType=DEEP_LINK&link=...
 *   - Secções lazy:  CONTENT_PLACEHOLDER.data.contentUri   ->  /v4/.../content/partial?component=section&id=...
 *   - Produto:  PRODUCT_TILE.data -> { storeProductId, name, price, imageUrl }
 *   - Match na DB Bora:  products.id = 'auc-' + storeProductId  (prefixo por loja)
 *
 * Categoria por produto: root = categoria top (NAMEMAP do scId); leaf = título do GRID/secção mais específico.
 *
 * Uso:  node glovo_grocery_crawler.js --store 124961 --addr 226966 --sc 23934462,... --out out.json
 * Saída: JSON array [{ id, name, price, img, root, leaf }]. Rate-limit ~1.5s.
 * Preço Glovo grocery = preço de loja (base). NÃO subtrair markup.
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

// Categorias top Auchan Guarda (scId -> nome de exibição com acentos). Fallback: slug do deep-link.
let NAMEMAP = { '23934462':'Frutas e Vegetais','23934516':'Talho e Peixaria','23934733':'Charcutaria e Queijos','23934670':'Padaria e Pastelaria','23934488':'Laticínios e Ovos','23934721':'Mercearia','23934603':'Mercearia Doce','23934758':'Refeições Frescas','23934610':'Gelados e Congelados','23934667':'Águas e Sumos','23935041':'Cervejas e Sidras','23934913':'Vinhos e Espumantes','23934612':'Bebidas Espirituosas','23935093':'Bio e Saudável','23935002':'Beleza e Higiene','23935219':'Saúde e Bem-Estar','23935223':'Limpeza','23935200':'Bebé e Criança','23934842':'Animais de Estimação','23935400':'Casa e Decoração','23935389':'Bricolage, Jardim e Auto' };
// --names <ficheiro.json> permite outra loja (ex.: Pingo Doce) com scId->nome próprios.
if (arg('names', '')) { try { NAMEMAP = JSON.parse(fs.readFileSync(arg('names'), 'utf8')); } catch (e) { console.error('names load fail:', e.message); } }

function get(path) {
  return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); });
}
function normPath(p) { const i = p.indexOf('&link='); if (i < 0) return p; const head = p.slice(0, i + 6); let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} return head + encodeURIComponent(link); }
// derive true root category from a deep-link path's leading "...-sc.{id}" segment; fallback = parent root
function rootFromPath(p, fallback) { const i = p.indexOf('&link='); if (i < 0) return fallback; let link = p.slice(i + 6); try { link = decodeURIComponent(link); } catch {} const m = link.split('/')[0].match(/-sc\.(\d+)$/); return m && NAMEMAP[m[1]] ? NAMEMAP[m[1]] : fallback; }

// walk a response: tag PRODUCT_TILE with (root, leaf); leaf updates on GRID/CAROUSEL titles.
function walk(o, root, leaf, prods, cols) {
  if (o == null || typeof o !== 'object') return;
  if (Array.isArray(o)) { for (const x of o) walk(x, root, leaf, prods, cols); return; }
  if ((o.type === 'GRID' || o.type === 'CAROUSEL') && o.data && o.data.title) leaf = o.data.title;
  if (o.type === 'PRODUCT_TILE' && o.data && o.data.storeProductId) {
    if (!prods.has(o.data.storeProductId)) prods.set(o.data.storeProductId, { id: o.data.storeProductId, name: o.data.name, price: o.data.price, img: o.data.imageUrl || null, root, leaf });
  }
  if (o.type === 'COLLECTION_TILE' && o.data && o.data.action && o.data.action.data && o.data.action.data.path) cols.push({ path: o.data.action.data.path, root: rootFromPath(o.data.action.data.path, root), leaf: o.data.title || leaf });
  if (o.type === 'CONTENT_PLACEHOLDER' && o.data && o.data.contentUri) cols.push({ path: o.data.contentUri, root, leaf: o.data.title || leaf });
  for (const k of Object.keys(o)) walk(o[k], root, leaf, prods, cols);
}
function slugName(scId) { return NAMEMAP[scId] || scId; }

(async () => {
  if (!SCIDS.length) { console.error('missing --sc (comma-separated category sc ids)'); process.exit(2); }
  const products = new Map(); const seen = new Set(); const queue = [];
  for (const id of SCIDS) { const p = '/v3/stores/' + STORE + '/addresses/' + ADDR + '/content?nodeUrl=' + encodeURIComponent('/collections/' + id); const root = slugName(id); queue.push({ path: p, root, leaf: root }); seen.add(p); }
  let fetched = 0, errors = 0;
  while (queue.length && fetched < 6000) {
    const item = queue.shift(); let r, t = 0;
    do { r = await get(item.path); if (r.status === 200) break; t++; await sleep(4000 * t); } while (t < 3);
    fetched++;
    if (r.status !== 200) { if (++errors > 60) break; continue; }
    let j; try { j = JSON.parse(r.body); } catch { continue; }
    const cols = [];
    walk(j, item.root, item.leaf, products, cols);
    for (const c of cols) { const np = normPath(c.path); if (!seen.has(np)) { seen.add(np); queue.push({ path: np, root: c.root, leaf: c.leaf }); } }
    if (fetched % 25 === 0) { fs.writeFileSync(OUT, JSON.stringify([...products.values()])); console.log('fetched=' + fetched + ' queue=' + queue.length + ' products=' + products.size); }
    await sleep(1200 + Math.floor(Math.random() * 600));
  }
  fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
  console.log('DONE products=' + products.size + ' errors=' + errors);
})();
