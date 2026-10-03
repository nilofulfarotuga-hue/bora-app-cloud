'use strict';
// Discovery probe for Kiwoko / Leroy Merlin / Worten / Zippy on Glovo Guarda.
// 1) Test whether the crawler's content endpoint works (Worten known IDs 124378/350045).
// 2) Resolve (storeId, addressId) for all 4 from the Glovo store web page SSR payload.
// 3) For any store with a working content root, list top category collection ids + titles.
const https = require('https');
const fs = require('fs');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
function web(url) { return new Promise(res => { const o = new URL(url); https.get({ hostname: o.hostname, path: o.pathname + o.search, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept': 'text/html', 'accept-language': 'pt-PT,pt;q=0.9' } }, r => { if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) { r.resume(); return res(web(r.headers.location.startsWith('http') ? r.headers.location : 'https://' + o.hostname + r.headers.location)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d, u: url })); }).on('error', e => res({ s: 0, d: '' + e.message, u: url })); }); }

const SLUGS = {
  worten: 'worten-vivaci-guarda-grd',
  'leroy-merlin': 'leroy-merlin-grd',
  kiwoko: 'kiwoko-grd',
  zippy: 'zippy-grd',
};

// Extract top category collection ids + titles from a content JSON root.
function topCats(d) {
  let j; try { j = JSON.parse(d); } catch { return { err: 'json parse fail' }; }
  const cats = new Map();
  (function walk(o) {
    if (!o || typeof o !== 'object') return;
    if (Array.isArray(o)) { o.forEach(walk); return; }
    // collection link patterns
    const path = o.path || (o.action && o.action.data && o.action.data.path) || '';
    if (typeof path === 'string') {
      let m = path.match(/\/collections\/(\d+)/) || path.match(/-sc\.(\d+)/);
      if (m && (o.title || o.name)) cats.set(m[1], o.title || o.name);
    }
    for (const k of Object.keys(o)) walk(o[k]);
  })(j);
  return { count: cats.size, cats: [...cats.entries()].slice(0, 40) };
}

(async () => {
  const out = {};
  // STEP 1 — Worten content endpoint with known IDs
  console.log('=== STEP 1: content endpoint test (Worten 124378/350045) ===');
  const root = await api('/v3/stores/124378/addresses/350045/content');
  console.log('GET /v3/stores/124378/addresses/350045/content ->', root.s, 'len', root.d.length);
  console.log('  first 240:', root.d.slice(0, 240).replace(/\s+/g, ' '));
  if (root.s === 200) { const t = topCats(root.d); console.log('  topCats:', t.count, JSON.stringify(t.cats)); out.worten_content = t; }

  // STEP 2 — resolve (storeId, addressId) for all 4 from web SSR
  console.log('\n=== STEP 2: resolve IDs from store web page ===');
  for (const [k, slug] of Object.entries(SLUGS)) {
    const url = `https://glovoapp.com/pt/pt/guarda/stores/${slug}`;
    const r = await web(url);
    const ids = [...new Set((r.d.match(/"storeId"\s*:\s*(\d+)/g) || []).map(x => x.match(/\d+/)[0]))];
    const addrs = [...new Set((r.d.match(/"(?:addressId|storeAddressId)"\s*:\s*(\d+)/g) || []).map(x => x.match(/\d+/)[0]))];
    const scAll = [...new Set((r.d.match(/-sc\.(\d+)/g) || []).map(x => x.match(/\d+/)[0]))];
    console.log(`${k.padEnd(13)} ${slug} -> http ${r.s} len ${r.d.length} | storeId=[${ids}] addr=[${addrs}] scIds=${scAll.length}`);
    out[k] = { slug, http: r.s, len: r.d.length, storeIds: ids, addrIds: addrs, scCount: scAll.length };
    await sleep(1500);
  }
  fs.writeFileSync('.ai_4lojas_probe_out.json', JSON.stringify(out, null, 2));
  console.log('\nwrote .ai_4lojas_probe_out.json');
})();
