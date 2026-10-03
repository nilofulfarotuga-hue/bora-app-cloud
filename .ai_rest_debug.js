'use strict';
// Debug: for each kept section, compare inline PRODUCT_ROW count (home) vs following its action path.
const https = require('https');
const H = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const S = arg('store'), A = arg('addr');
function get(path) { return new Promise(res => { https.get(BASE + path, { headers: H }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ status: r.statusCode, body: d })); }).on('error', e => res({ status: 0, body: e.message })); }); }
function countRows(o, set) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) { for (const x of o) countRows(x, set); return; } if (o.type === 'PRODUCT_ROW' && o.data && o.data.storeProductId) set.add(o.data.storeProductId); for (const k of Object.keys(o)) countRows(o[k], set); }
(async () => {
  const home = await get('/v3/stores/' + S + '/addresses/' + A + '/content');
  const j = JSON.parse(home.body);
  const lists = [];
  (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'LIST' && o.data) { const set = new Set(); countRows(o.data.elements || o, set); lists.push({ title: o.data.title, slug: o.data.slug, path: (o.data.action && o.data.action.data && o.data.action.data.path) || '', inline: set.size }); } for (const k of Object.keys(o)) w(o[k]); })(j);
  console.log('LIST sections:', lists.length);
  for (const l of lists) {
    let pathCount = '-';
    if (l.path) { const r = await get(l.path); if (r.status === 200) { const set = new Set(); try { countRows(JSON.parse(r.body), set); pathCount = set.size; } catch { pathCount = 'parsefail'; } } else pathCount = 'http' + r.status; await sleep(700); }
    console.log(`  "${l.title}" slug=${l.slug} inline=${l.inline} pathFull=${pathCount}`);
  }
})();
