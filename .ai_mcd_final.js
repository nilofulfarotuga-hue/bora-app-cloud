'use strict';
// Final McD attempt: inspect closed-store content, try /v4 main deep-link + scheduled-order variants.
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function api(path, extra) { return new Promise(res => { https.get(BASE + path, { headers: { ...APIH, ...(extra || {}) } }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function countRows(d) { let j; try { j = JSON.parse(d); } catch { return -1; } let n = 0; (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'PRODUCT_ROW') n++; for (const k of Object.keys(o)) w(o[k]); })(j); return n; }
(async () => {
  const S = 215649, A = 346436;
  const c0 = await api(`/v3/stores/${S}/addresses/${A}/content`);
  console.log('content len', c0.d.length, ':', c0.d.slice(0, 400));
  const tries = [
    `/v4/stores/${S}/addresses/${A}/content/main?nodeType=HOME`,
    `/v3/stores/${S}/addresses/${A}/content?scheduled=true`,
    `/v3/stores/${S}/addresses/${A}`,
    `/v3/stores/${S}`,
  ];
  for (const p of tries) { const r = await api(p); console.log(`${p} -> ${r.s} len ${r.d.length} PRODUCT_ROW=${r.s === 200 ? countRows(r.d) : '-'}`); await sleep(800); }
})();
