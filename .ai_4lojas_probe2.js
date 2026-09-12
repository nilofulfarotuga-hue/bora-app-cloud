'use strict';
// Probe 2: resolve (storeId, addressId) for all 4 from web page embedded content paths,
// then for each store hit the content root and dump TOP-LEVEL layout body (type + title)
// so we can pick real top categories and spot promo carousels to exclude.
const https = require('https');
const fs = require('fs');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function web(url) { return new Promise(res => { const o = new URL(url); https.get({ hostname: o.hostname, path: o.pathname + o.search, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept': 'text/html', 'accept-language': 'pt-PT,pt;q=0.9' } }, r => { if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) { r.resume(); return res(web(r.headers.location.startsWith('http') ? r.headers.location : 'https://' + o.hostname + r.headers.location)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d, u: url })); }).on('error', e => res({ s: 0, d: '' + e.message, u: url })); }); }

const SLUGS = { worten: 'worten-vivaci-guarda-grd', 'leroy-merlin': 'leroy-merlin-grd', kiwoko: 'kiwoko-grd', zippy: 'zippy-grd' };

function resolvePair(d) {
  // frequency-rank stores/<S>/addresses/<A> pairs in the SSR payload
  const freq = new Map();
  for (const m of d.matchAll(/stores\/(\d+)\/addresses\/(\d+)/g)) { const k = m[1] + '/' + m[2]; freq.set(k, (freq.get(k) || 0) + 1); }
  const ranked = [...freq.entries()].sort((a, b) => b[1] - a[1]);
  return ranked.slice(0, 3);
}

// Dump top-level layout: returns [{type,title,nProducts,nCollections,collId}]
function dumpBody(d) {
  let j; try { j = JSON.parse(d); } catch { return { err: 'parse' }; }
  const body = (j.data && j.data.body) || j.body || [];
  const rows = [];
  for (const el of body) {
    const type = el.type;
    const title = (el.data && el.data.title) || '';
    let nP = 0, nC = 0, collId = '';
    (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'PRODUCT_TILE') nP++; if (o.type === 'COLLECTION_TILE') nC++; const p = (o.action && o.action.data && o.action.data.path) || o.path || ''; if (!collId && typeof p === 'string') { const m = p.match(/collections\/(\d+)/) || p.match(/-sc\.(\d+)/); if (m) collId = m[1]; } for (const k of Object.keys(o)) w(o[k]); })(el);
    rows.push({ type, title, nP, nC, collId });
  }
  return { nBody: body.length, rows };
}

(async () => {
  const out = {};
  for (const [k, slug] of Object.entries(SLUGS)) {
    const r = await web(`https://glovoapp.com/pt/pt/guarda/stores/${slug}`);
    const pairs = resolvePair(r.d);
    console.log(`\n### ${k} (${slug}) http ${r.s} | top pairs:`, JSON.stringify(pairs));
    out[k] = { slug, pairs };
    if (pairs.length) {
      const [S, A] = pairs[0][0].split('/');
      const root = await api(`/v3/stores/${S}/addresses/${A}/content`);
      const db = dumpBody(root.d);
      console.log(`   content ${S}/${A} -> ${root.s} len ${root.d.length} | body=${db.nBody}`);
      if (db.rows) for (const row of db.rows) console.log(`     [${row.type}] "${row.title}" prod=${row.nP} coll=${row.nC} id=${row.collId}`);
      out[k].store = S; out[k].addr = A; out[k].body = db.rows;
    }
    await sleep(1800);
  }
  fs.writeFileSync('.ai_4lojas_ids.json', JSON.stringify(out, null, 2));
  console.log('\nwrote .ai_4lojas_ids.json');
})();
