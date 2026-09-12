'use strict';
/**
 * .ai_mcd_uber_crawler.js — Uber Eats catalog crawler for McDonald's Guarda (storeUuid b4866ee3-...).
 * McD on Uber = 1 top section "McMenu" with 11 subsections (real categories). Items are harvested from the full
 * getStoreV1 payload (sectionEntitiesMap/catalogSectionsMap embed them) AND per-subsection getCatalogPresentationV2.
 * CP1252 double-encode mojibake recovery (Uber locale bug). Price = cents/100 raw (inflated; cross-ref only).
 * Usage: node .ai_mcd_uber_crawler.js --out .ai_mcd_uber.json
 */
const https = require('https'); const fs = require('fs');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
const LAT = 40.535655899999995, LNG = -7.2673073, PID = 'ChIJU8b2j8T6PA0RADWQ5L3rAAQ';
function arg(n, d) { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; }
const STORE = arg('store', 'b4866ee3-1127-4a27-8cb7-e70c39b1ca30');
const OUT = arg('out', '.ai_mcd_uber.json');
const cookie = 'uev2.loc=' + encodeURIComponent(JSON.stringify({ address: { title: 'Guarda', address1: 'Guarda' }, latitude: LAT, longitude: LNG, reference: PID, referenceType: 'google_places', type: 'google_places' }));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const E2MAP = { 0x9C: 0x93, 0x9D: 0x94, 0x98: 0x91, 0x99: 0x92, 0x93: 0x96, 0x94: 0x97, 0xA6: 0x85, 0xA2: 0x95, 0xB0: 0x89, 0xA0: 0x86, 0xA1: 0x87, 0xB9: 0x8B, 0xBA: 0x9B, 0xAC: 0x80 };
function recoverMojibake(buf) {
  const out = [];
  for (let i = 0; i < buf.length;) {
    const b = buf[i];
    if (b < 0x80) { out.push(b); i++; }
    else if (b === 0xC2 && i + 1 < buf.length) { out.push(buf[i + 1]); i += 2; }
    else if (b === 0xC3 && i + 1 < buf.length) { out.push((buf[i + 1] & 0x3F) | 0x40); i += 2; }
    else if (b === 0xE2 && buf[i + 1] === 0x80 && i + 2 < buf.length) { const m = E2MAP[buf[i + 2]]; out.push(m != null ? m : 0x3F); i += 3; }
    else if (b === 0xC5 && i + 1 < buf.length) { const m = { 0x92: 0x8C, 0x93: 0x9C, 0xA0: 0x8A, 0xA1: 0x9A, 0xB8: 0x9F, 0xBD: 0x8E, 0xBE: 0x9E }[buf[i + 1]]; out.push(m != null ? m : 0x3F); i += 2; }
    else if (b === 0xC6 && buf[i + 1] === 0x92) { out.push(0x83); i += 2; }
    else { out.push(b); i++; }
  }
  return Buffer.from(out).toString('utf8');
}
function call(path, body) {
  return new Promise(res => { const data = JSON.stringify(body);
    const r = https.request({ method: 'POST', hostname: 'www.ubereats.com', path, maxHeaderSize: 131072, headers: { 'content-type': 'application/json', accept: '*/*', 'content-length': Buffer.byteLength(data), 'user-agent': UA, 'x-csrf-token': 'x', origin: 'https://www.ubereats.com', 'x-uber-target-location-latitude': LAT, 'x-uber-target-location-longitude': LNG, cookie } },
      resp => { const ch = []; resp.on('data', c => ch.push(c)); resp.on('end', () => res({ s: resp.statusCode, d: recoverMojibake(Buffer.concat(ch)) })); });
    r.on('error', e => res({ s: 0, d: '' + e.message })); r.write(data); r.end(); });
}
const products = new Map();
function harvest(j) {
  (function w(o) { if (o == null || typeof o !== 'object') return; if (Array.isArray(o)) { o.forEach(w); return; }
    if (o.uuid && typeof o.title === 'string' && typeof o.price === 'number' && o.imageUrl && o.price > 0 && !products.has(o.uuid))
      products.set(o.uuid, { id: 'mcdu-' + o.uuid, name: o.title, price: Math.round(o.price) / 100, img: o.imageUrl });
    for (const k of Object.keys(o)) w(o[k]); })(j);
}
(async () => {
  const raw = await call('/api/getStoreV1?localeCode=pt', { storeUuid: STORE });
  let sd; try { sd = JSON.parse(raw.d); } catch (e) { console.error('storeV1 parse fail ' + e.message); process.exit(1); }
  const data = sd.data || {};
  console.log('isOpen=' + data.isOpen + ' storeV1Len=' + raw.d.length);
  harvest(data);
  console.log('items from storeV1=' + products.size);
  const top = (data.sections || [])[0];
  const subs = (top && top.subsectionUuids) || [];
  console.log('subsections=' + subs.length);
  let si = 0;
  for (const su of subs) {
    si++;
    const before = products.size;
    const r = await call('/api/getCatalogPresentationV2?localeCode=pt', { storeFilters: { storeUuid: STORE, sectionUuids: [top.uuid], subsectionUuids: [su], sectionTypes: ['COLLECTION'], shouldReturnSegmentedControlData: true }, pagingInfo: { enabled: true, offset: null } });
    try { harvest(JSON.parse(r.d).data); } catch {}
    console.log('  sub[' + si + '/' + subs.length + '] +' + (products.size - before) + ' total=' + products.size);
    fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
    await sleep(800 + Math.floor(Math.random() * 400));
  }
  fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
  console.log('DONE products=' + products.size);
})();
