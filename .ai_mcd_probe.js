'use strict';
// McDonald's discovery: search Glovo city pages (Guarda + nearby cities) for a McDonald's store
// slug, then resolve (storeId, addressId). Also sanity-greps burger/kfc to confirm the page lists stores.
const https = require('https');
const fs = require('fs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
function web(url) { return new Promise(res => { const o = new URL(url); https.get({ hostname: o.hostname, path: o.pathname + o.search, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36', 'accept': 'text/html', 'accept-language': 'pt-PT,pt;q=0.9' } }, r => { if ([301, 302, 303, 307, 308].includes(r.statusCode) && r.headers.location) { r.resume(); return res(web(r.headers.location.startsWith('http') ? r.headers.location : 'https://' + o.hostname + r.headers.location)); } let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d, u: url })); }).on('error', e => res({ s: 0, d: '' + e.message, u: url })); }); }
function resolvePair(d) { const freq = new Map(); for (const m of d.matchAll(/stores\/(\d+)\/addresses\/(\d+)/g)) { const k = m[1] + '/' + m[2]; freq.set(k, (freq.get(k) || 0) + 1); } return [...freq.entries()].sort((a, b) => b[1] - a[1]).slice(0, 2); }
const CITIES = ['guarda', 'viseu', 'covilha', 'coimbra', 'castelo-branco'];
(async () => {
  const found = {};
  for (const city of CITIES) {
    const r = await web(`https://glovoapp.com/pt/pt/${city}/`);
    // collect store slugs from /stores/{slug} links or "slug" fields
    const slugs = new Set();
    for (const m of r.d.matchAll(/\/(?:pt\/pt\/[a-z-]+\/)?stores\/([a-z0-9-]+)/gi)) slugs.add(m[1]);
    for (const m of r.d.matchAll(/"(?:slug|storeSlug)"\s*:\s*"([a-z0-9-]+)"/gi)) slugs.add(m[1]);
    const all = [...slugs];
    const mc = all.filter(s => /mc-?donald|mcdo/i.test(s));
    const bk = all.filter(s => /burger|^bk-/i.test(s));
    const kf = all.filter(s => /kfc/i.test(s));
    console.log(`${city}: http ${r.s} len ${r.d.length} | stores≈${all.length} | McD=[${mc}] (sanity BK=[${bk.slice(0,2)}] KFC=[${kf.slice(0,2)}])`);
    for (const slug of mc) {
      const sr = await web(`https://glovoapp.com/pt/pt/${city}/stores/${slug}`);
      const pairs = sr.s === 200 ? resolvePair(sr.d) : [];
      console.log(`   -> ${slug} http ${sr.s} len ${sr.d.length} pairs=${JSON.stringify(pairs)}`);
      if (pairs.length) { found[city + '/' + slug] = pairs[0][0]; }
      await sleep(1200);
    }
    await sleep(1500);
  }
  fs.writeFileSync('.ai_mcd_found.json', JSON.stringify(found, null, 2));
  console.log('\nFOUND:', JSON.stringify(found));
})();
