#!/usr/bin/env node
/**
 * uber_eats_intermarche_crawler.js — Crawler completo do catálogo Uber Eats (Intermarché Guarda).
 * Validado 2026-06-07. Replica o pipeline do crawler Glovo, adaptado à API Uber Eats web.
 *
 * RECEITA QUE FUNCIONA (descoberta com o cURL do Danilo):
 *  - maxHeaderSize:131072 resolve o header-overflow anti-bot.
 *  - Localização: cookie uev2.loc com place_id REAL do Google (referenceType google_places)
 *    + headers x-uber-target-location-latitude/longitude. Guarda: place_id ChIJU8b2j8T6PA0RADWQ5L3rAAQ.
 *  - getStoreV1 (POST {storeUuid}) -> data.sections = lista de ~44 categorias {uuid,title}.
 *    ⚠️ getStoreV1 só devolve sections DURANTE O HORÁRIO DA LOJA (09:00-19:30 PT). Fora disso sections=[].
 *  - getCatalogPresentationV2 (POST) com body:
 *      {storeFilters:{storeUuid, sectionUuids:[SEC], subsectionUuids:null,
 *                     sectionTypes:["COLLECTION"], shouldReturnSegmentedControlData:true},
 *       pagingInfo:{enabled:true, offset:null|<n>}}
 *    -> data.catalog (HORIZONTAL_GRID com PRODUCT items) + data.pagingInfo (paginação).
 *  - Item: {uuid, title, price (CÊNTIMOS), imageUrl}. Header x-csrf-token:'x'.
 *
 * Preço: cêntimos/100 DIRETO (decisão Danilo 2026-06-07: Uber PT grocery cobra preço de loja,
 *   como a Glovo Auchan — NÃO subtrair 15%). Validar 3 samples vs Glovo antes do INSERT.
 *
 * Saída: JSON [{id:'int-'+uuid, name, price, img, root(=section title), leaf, sort_order}].
 * Uso: node uber_eats_intermarche_crawler.js --out out.json
 */
'use strict';
const https = require('https'); const fs = require('fs');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
const LAT = 40.535655899999995, LNG = -7.2673073, PID = 'ChIJU8b2j8T6PA0RADWQ5L3rAAQ';
const STORE = 'a0fe1ff9-4042-55a3-9a28-ae1d84b93576';
const OUT = (process.argv.indexOf('--out') > 0 ? process.argv[process.argv.indexOf('--out') + 1] : 'uber_intermarche.json');
const cookie = 'uev2.loc=' + encodeURIComponent(JSON.stringify({ address: { title: 'Guarda', address1: 'Guarda' }, latitude: LAT, longitude: LNG, reference: PID, referenceType: 'google_places', type: 'google_places' }));
const sleep = ms => new Promise(r => setTimeout(r, ms));
function call(path, body) {
  return new Promise(res => { const data = JSON.stringify(body);
    const r = https.request({ method: 'POST', hostname: 'www.ubereats.com', path, maxHeaderSize: 131072,
      headers: { 'content-type': 'application/json', accept: '*/*', 'content-length': Buffer.byteLength(data), 'user-agent': UA, 'x-csrf-token': 'x', origin: 'https://www.ubereats.com', 'x-uber-target-location-latitude': LAT, 'x-uber-target-location-longitude': LNG, 'x-uber-device-location-latitude': LAT, 'x-uber-device-location-longitude': LNG, cookie } },
      resp => { let d = ''; resp.on('data', c => d += c); resp.on('end', () => res({ s: resp.statusCode, d })); });
    r.on('error', e => res({ s: 0, d: '' + e.message })); r.write(data); r.end(); });
}
function extractItems(json, out) {
  (function w(o) { if (o == null || typeof o !== 'object') return; if (Array.isArray(o)) { o.forEach(w); return; }
    if (o.uuid && typeof o.title === 'string' && typeof o.price === 'number' && o.imageUrl) out.push({ uuid: o.uuid, title: o.title, price: o.price, img: o.imageUrl });
    for (const k of Object.keys(o)) w(o[k]); })(json);
}
(async () => {
  const store = JSON.parse((await call('/api/getStoreV1?localeCode=pt', { storeUuid: STORE })).d).data;
  const sections = (store.sections || []).filter(s => s && s.uuid && s.title);
  console.log('sections:', sections.length);
  if (sections.length < 5) { console.error('ABORT: getStoreV1 devolveu', sections.length, 'sections. Provavelmente fora do horário da loja (09:00-19:30 PT). Correr durante o horário.'); process.exit(3); }
  const products = new Map();
  let si = 0;
  for (const sec of sections) {
    si++;
    let offset = null, page = 0, before = products.size;
    do {
      const body = { storeFilters: { storeUuid: STORE, sectionUuids: [sec.uuid], subsectionUuids: null, sectionTypes: ['COLLECTION'], shouldReturnSegmentedControlData: true }, pagingInfo: { enabled: true, offset } };
      const r = await call('/api/getCatalogPresentationV2?localeCode=pt', body);
      let j; try { j = JSON.parse(r.d).data; } catch { break; }
      const items = []; extractItems(j.catalog || j, items);
      for (const it of items) if (!products.has(it.uuid)) products.set(it.uuid, { id: 'int-' + it.uuid, name: it.title, price: it.price / 100, img: it.img, root: sec.title, leaf: sec.title, sort_order: si * 10000 + products.size });
      const np = j.pagingInfo && (j.pagingInfo.nextOffset != null ? j.pagingInfo.nextOffset : (j.pagingInfo.hasMore ? (Number(offset || 0) + items.length) : null));
      offset = (items.length > 0 && np != null && np !== offset) ? np : null;
      page++;
      await sleep(900 + Math.floor(Math.random() * 500));
    } while (offset != null && page < 25);
    console.log('  [' + si + '/' + sections.length + '] ' + sec.title + ' -> total ' + products.size + ' (+' + (products.size - before) + ')');
    fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
  }
  fs.writeFileSync(OUT, JSON.stringify([...products.values()]));
  console.log('DONE products=' + products.size);
})();
