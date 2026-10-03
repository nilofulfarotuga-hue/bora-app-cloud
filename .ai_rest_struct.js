'use strict';
// Inspect restaurant content structure: type histogram + a sample product-shaped node +
// a sample LIST node, so we can adapt the harvester to the restaurant product component type.
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const S = arg('store'), A = arg('addr');
(async () => {
  const r = await api(`/v3/stores/${S}/addresses/${A}/content`);
  console.log('content', r.s, 'len', r.d.length);
  let j; try { j = JSON.parse(r.d); } catch (e) { console.log('parse fail'); return; }
  const types = {}; let sampleProduct = null, sampleList = null, withPrice = 0;
  (function w(o) {
    if (!o || typeof o !== 'object') return;
    if (Array.isArray(o)) return o.forEach(w);
    if (typeof o.type === 'string') types[o.type] = (types[o.type] || 0) + 1;
    const d = o.data && typeof o.data === 'object' ? o.data : o;
    const hasName = typeof d.name === 'string' && d.name.length > 1;
    const priceField = d.price != null ? 'price' : (d.priceInfo ? 'priceInfo' : (d.formattedPrice ? 'formattedPrice' : (d.attributesV2 ? 'attributesV2' : null)));
    if (hasName && priceField) { withPrice++; if (!sampleProduct) sampleProduct = { type: o.type, priceField, dataKeys: Object.keys(d), data: d }; }
    if (!sampleList && o.type === 'LIST') sampleList = { keys: Object.keys(o), dataKeys: o.data ? Object.keys(o.data) : [], raw: JSON.stringify(o).slice(0, 500) };
    for (const k of Object.keys(o)) w(o[k]);
  })(j);
  console.log('TYPES:', JSON.stringify(types));
  console.log('nodesWithNameAndPrice:', withPrice);
  console.log('SAMPLE PRODUCT:', sampleProduct ? JSON.stringify(sampleProduct).slice(0, 900) : 'NONE');
  console.log('SAMPLE LIST:', sampleList ? JSON.stringify(sampleList).slice(0, 900) : 'NONE');
})();
