'use strict';
// Dump home structure for one store: each top body element -> title, its own action path,
// and its child COLLECTION_TILE {title, path} (first 3). Reveals the real seedable nav paths.
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const S = arg('store'), A = arg('addr');
function actionPath(o) { return (o && o.action && o.action.data && o.action.data.path) || (o && o.data && o.data.action && o.data.action.data && o.data.action.data.path) || ''; }
function childTiles(el) { const out = []; (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'COLLECTION_TILE') out.push({ title: (o.data && o.data.title) || '', path: actionPath(o.data) || actionPath(o) }); for (const k of Object.keys(o)) w(o[k]); })(el); return out; }
(async () => {
  const r = await api(`/v3/stores/${S}/addresses/${A}/content`);
  const j = JSON.parse(r.d);
  const body = (j.data && j.data.body) || j.body || [];
  console.log(`store ${S}/${A} body=${body.length}`);
  for (const el of body) {
    const title = (el.data && el.data.title) || '';
    const own = actionPath(el.data) || actionPath(el);
    const kids = childTiles(el);
    console.log(`\n[${el.type}] "${title}"`);
    if (own) console.log(`   ownPath: ${own.slice(0, 160)}`);
    console.log(`   childTiles=${kids.length}`);
    for (const k of kids.slice(0, 3)) console.log(`     - "${k.title}" :: ${(k.path || '(none)').slice(0, 150)}`);
  }
})();
