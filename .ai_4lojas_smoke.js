'use strict';
// Smoke test: seed ONE real category per store, count PRODUCT_TILE / COLLECTION_TILE / CONTENT_PLACEHOLDER
// in the immediate response + follow first placeholder one level, to confirm products are reachable.
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function count(d) { let j; try { j = JSON.parse(d); } catch { return { err: 'parse' }; } let P = 0, C = 0, PH = 0; const placeholders = []; (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'PRODUCT_TILE') P++; if (o.type === 'COLLECTION_TILE') C++; if (o.type === 'CONTENT_PLACEHOLDER' && o.data && o.data.contentUri) { PH++; placeholders.push(o.data.contentUri); } for (const k of Object.keys(o)) w(o[k]); })(j); return { P, C, PH, placeholders }; }
const T = [
  { k: 'zippy', S: 123602, A: 224489, sc: 20882738, name: 'Mulher' },
  { k: 'worten', S: 124378, A: 350045, sc: 37409779, name: 'Telemóveis e Smartphones' },
  { k: 'kiwoko', S: 529912, A: 862546, sc: 38798985, name: 'Cães' },
  { k: 'leroy-merlin', S: 539720, A: 874730, sc: 37661953, name: 'Ferramentas' },
];
(async () => {
  for (const t of T) {
    const p = `/v3/stores/${t.S}/addresses/${t.A}/content?nodeUrl=${encodeURIComponent('/collections/' + t.sc)}`;
    const r = await api(p); const c = count(r.d);
    console.log(`${t.k.padEnd(13)} "${t.name}" -> ${r.s} len ${r.d.length} | PRODUCT=${c.P} COLLECTION=${c.C} PLACEHOLDER=${c.PH}`);
    if (c.PH && c.placeholders[0]) { await sleep(1200); const r2 = await api(c.placeholders[0].replace(/^https?:\/\/[^/]+/, '')); const c2 = count(r2.d); console.log(`   └ follow placeholder -> ${r2.s} | PRODUCT=${c2.P} COLLECTION=${c2.C} PLACEHOLDER=${c2.PH}`); }
    await sleep(1500);
  }
})();
