'use strict';
// Restaurant discovery: try candidate slugs, resolve (storeId, addressId) from web SSR,
// then dump the content home body (type/title/collId, nProducts, nCollections) to learn the
// nav model (inline PRODUCT_TILE vs COLLECTION_TILE menu sections).
const https = require('https');
const fs = require('fs');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function web(url) { return new Promise(res => { const o = new URL(url); https.get({ hostname: o.hostname, path: o.pathname + o.search, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept': 'text/html', 'accept-language': 'pt-PT,pt;q=0.9' } }, r => { if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) { r.resume(); return res(web(r.headers.location.startsWith('http') ? r.headers.location : 'https://' + o.hostname + r.headers.location)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d, u: url })); }).on('error', e => res({ s: 0, d: '' + e.message, u: url })); }); }
function resolvePair(d) { const freq = new Map(); for (const m of d.matchAll(/stores\/(\d+)\/addresses\/(\d+)/g)) { const k = m[1] + '/' + m[2]; freq.set(k, (freq.get(k) || 0) + 1); } return [...freq.entries()].sort((a, b) => b[1] - a[1]).slice(0, 2); }
function actionPath(o) { return (o && o.action && o.action.data && o.action.data.path) || (o && o.data && o.data.action && o.data.action.data && o.data.action.data.path) || ''; }
function dumpBody(d) { let j; try { j = JSON.parse(d); } catch { return { err: 'parse' }; } const body = (j.data && j.data.body) || j.body || []; const rows = []; for (const el of body) { let nP = 0, nC = 0, collId = ''; (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'PRODUCT_TILE') nP++; if (o.type === 'COLLECTION_TILE') nC++; const p = actionPath(o.data) || actionPath(o); if (!collId && typeof p === 'string') { const m = p.match(/-sc\.(\d+)/); if (m) collId = m[1]; } for (const k of Object.keys(o)) w(o[k]); })(el); rows.push({ type: el.type, title: (el.data && el.data.title) || '', nP, nC, collId }); } return { nBody: body.length, rows }; }

const CANDS = {
  kfc: ['kfc-guarda', 'kfc-grd', 'kfc-grd1', 'kfc-kentucky-fried-chicken-guarda'],
  'burger-king': ['burger-king-guarda', 'burger-king-grd', 'burgerking-guarda', 'burger-king-grd1'],
  mcdonalds: ['mcdonald-s-guarda', 'mcdonalds-guarda', 'mcdonald-s-grd', 'mcdonalds-grd', 'mcdonald-s-grd1'],
};
(async () => {
  const out = {};
  for (const [k, slugs] of Object.entries(CANDS)) {
    let won = null;
    for (const slug of slugs) {
      const r = await web(`https://glovoapp.com/pt/pt/guarda/stores/${slug}`);
      const pairs = r.s === 200 ? resolvePair(r.d) : [];
      console.log(`${k} try "${slug}" -> http ${r.s} len ${r.d.length} pairs=${JSON.stringify(pairs)}`);
      if (pairs.length) { won = { slug, pair: pairs[0][0] }; break; }
      await sleep(1200);
    }
    if (!won) { console.log(`### ${k}: NO SLUG RESOLVED`); out[k] = { resolved: false }; continue; }
    const [S, A] = won.pair.split('/');
    const root = await api(`/v3/stores/${S}/addresses/${A}/content`);
    const db = dumpBody(root.d);
    console.log(`### ${k} WON slug=${won.slug} store=${S} addr=${A} content=${root.s} len=${root.d.length} body=${db.nBody}`);
    if (db.rows) for (const row of db.rows) console.log(`   [${row.type}] "${row.title}" prod=${row.nP} coll=${row.nC} id=${row.collId}`);
    out[k] = { slug: won.slug, store: S, addr: A, body: db.rows };
    await sleep(1500);
  }
  fs.writeFileSync('.ai_rest_ids.json', JSON.stringify(out, null, 2));
  console.log('\nwrote .ai_rest_ids.json');
})();
