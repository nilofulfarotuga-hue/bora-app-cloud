'use strict';
// Extract McD (store 215649) address id from the store page, then test the content endpoint.
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function web(url) { return new Promise(res => { const o = new URL(url); https.get({ hostname: o.hostname, path: o.pathname + o.search, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept': 'text/html', 'accept-language': 'pt-PT,pt;q=0.9' } }, r => { if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) { r.resume(); return res(web(r.headers.location.startsWith('http') ? r.headers.location : 'https://' + o.hostname + r.headers.location)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function countRows(d) { let j; try { j = JSON.parse(d); } catch { return -1; } let n = 0; (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'PRODUCT_ROW') n++; for (const k of Object.keys(o)) w(o[k]); })(j); return n; }
(async () => {
  const r = await web('https://glovoapp.com/pt/pt/guarda/stores/mcdonalds-grd');
  const d = r.d.replace(/\\"/g, '"'); // unescape
  // context around the store object
  const i = d.indexOf('"store":{"id":215649');
  console.log('store obj ctx:', i >= 0 ? d.slice(i, i + 320) : 'not found');
  // candidate address ids
  const addrCands = [...new Set([
    ...[...d.matchAll(/"addressId"\s*:\s*(\d+)/g)].map(m => m[1]),
    ...[...d.matchAll(/"address"\s*:\s*\{\s*"id"\s*:\s*(\d+)/g)].map(m => m[1]),
    ...[...d.matchAll(/stores\/215649\/addresses\/(\d+)/g)].map(m => m[1]),
  ])];
  console.log('addr candidates:', JSON.stringify(addrCands));
  // also any 6-digit ids near 215649
  for (const A of addrCands.slice(0, 6)) {
    const c = await api(`/v3/stores/215649/addresses/${A}/content`);
    console.log(`  content 215649/${A} -> ${c.s} len ${c.d.length} PRODUCT_ROW=${c.s === 200 ? countRows(c.d) : '-'}`);
    await sleep(900);
  }
})();
