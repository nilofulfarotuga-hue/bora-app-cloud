'use strict';
// Inspect McD slug candidates: status, len, name presence, any storeId / stores/{id} / address ids,
// and closed/unavailable indicators. If a store id is found, try the content endpoint.
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function web(url) { return new Promise(res => { const o = new URL(url); https.get({ hostname: o.hostname, path: o.pathname + o.search, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept': 'text/html', 'accept-language': 'pt-PT,pt;q=0.9' } }, r => { if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) { r.resume(); return res(web(r.headers.location.startsWith('http') ? r.headers.location : 'https://' + o.hostname + r.headers.location)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d, u: url })); }).on('error', e => res({ s: 0, d: '' + e.message, u: url })); }); }
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
const CANDS = ['mcdonalds-grd', 'mcdonald-s-grd', 'mcdonalds-guarda-grd', 'mcdonald-s-guarda-grd', 'mcdonalds-grd1', 'mcdonald-s-grd1', 'mc-donald-s-grd'];
(async () => {
  for (const slug of CANDS) {
    const r = await web(`https://glovoapp.com/pt/pt/guarda/stores/${slug}`);
    const hasName = /mcdonald/i.test(r.d);
    const storeIds = [...new Set((r.d.match(/"storeId"\s*:\s*(\d+)/g) || []).map(x => x.match(/\d+/)[0]))];
    const pathIds = [...new Set((r.d.match(/stores\/(\d+)\/addresses\/(\d+)/g) || []))].slice(0, 3);
    const anyStoreNum = [...new Set((r.d.match(/\\?"store\\?"\s*:\s*\{\s*\\?"id\\?"\s*:\s*(\d+)/g) || []))].slice(0, 3);
    const closed = /indispon|fechado|closed|fora de|não entrega|nao entrega|unavailable/i.test(r.d);
    console.log(`${slug}: http ${r.s} len ${r.d.length} mcdonald=${hasName} storeId=[${storeIds}] pathPairs=[${pathIds}] storeObj=[${anyStoreNum}] closedHint=${closed}`);
    await sleep(1000);
  }
})();
