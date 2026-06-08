'use strict';
// Deep probe: are McD product variants (sizes) present? In the home attributeGroups, or only in a
// product-detail endpoint? Do the variant attributes carry prices (expandable) or are they free options?
const https = require('https');
const APIH = { 'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer', 'glovo-language-code': 'pt', accept: 'application/json', 'user-agent': 'Mozilla/5.0', 'glovo-location-city-code': 'GRD' };
const BASE = 'https://api.glovoapp.com';
const sleep = ms => new Promise(r => setTimeout(r, ms));
function api(path) { return new Promise(res => { https.get(BASE + path, { headers: APIH }, r => { let d = ''; r.on('data', c => d += c); r.on('end', () => res({ s: r.statusCode, d })); }).on('error', e => res({ s: 0, d: '' + e.message })); }); }
const S = 215649, A = 346436;
function dumpAG(p, where) {
  console.log(`\n[${where}] "${p.name}" base=${p.price} id=${p.id} spid=${p.storeProductId}`);
  const ags = p.attributeGroups || [];
  console.log('  attributeGroups=' + ags.length);
  for (const ag of ags.slice(0, 8)) {
    const attrs = ag.attributes || ag.elements || [];
    console.log(`   GROUP "${ag.name}" min=${ag.min} max=${ag.max} attrs=${attrs.length} keys=[${Object.keys(ag).join(',')}]`);
    for (const at of attrs.slice(0, 6)) console.log(`      - "${at.name}" price=${at.price != null ? at.price : at.priceImpact} keys=[${Object.keys(at).join(',')}]`);
  }
}
(async () => {
  const r = await api(`/v3/stores/${S}/addresses/${A}/content`);
  const j = JSON.parse(r.d);
  const prods = [];
  (function w(o) { if (!o || typeof o !== 'object') return; if (Array.isArray(o)) return o.forEach(w); if (o.type === 'PRODUCT_ROW' && o.data && o.data.storeProductId) prods.push(o.data); for (const k of Object.keys(o)) w(o[k]); })(j);
  const withAG = prods.filter(p => p.attributeGroups && p.attributeGroups.length);
  const withAttrs = prods.filter(p => (p.attributeGroups || []).some(ag => (ag.attributes || ag.elements || []).length));
  console.log('PRODUCT_ROW=' + prods.length + ' withAttributeGroups=' + withAG.length + ' withInlineAttrs=' + withAttrs.length);
  // sample a drink and a combo from the HOME
  const drink = prods.find(p => /coca|sumol|fanta|agua|ice tea|lipton|bebida/i.test(p.name));
  const combo = prods.find(p => /mcmenu|menu/i.test(p.name));
  if (drink) dumpAG(drink, 'HOME drink');
  if (combo) dumpAG(combo, 'HOME combo');
  // try product-detail endpoints to get full variants
  const pid = drink ? drink.id : prods[0].id; const spid = drink ? drink.storeProductId : prods[0].storeProductId;
  const tries = [
    `/v3/stores/${S}/addresses/${A}/products/${pid}`,
    `/v3/stores/${S}/products/${pid}`,
    `/v3/stores/${S}/addresses/${A}/products/${spid}`,
    `/v3/stores/${S}/addresses/${A}/content/product?productId=${pid}`,
  ];
  for (const p of tries) { await sleep(700); const rr = await api(p); console.log(`DETAIL ${p} -> ${rr.s} len ${rr.d.length}` + (rr.s === 200 ? ' | has attributes=' + /"attributes"\s*:\s*\[/.test(rr.d) + ' priceImpact=' + /priceImpact|"price"/.test(rr.d) : '')); if (rr.s === 200 && rr.d.length > 200) { try { const dj = JSON.parse(rr.d); (function findP(o){ if(!o||typeof o!=='object')return; if(o.attributeGroups&&o.name){ dumpAG(o,'DETAIL'); throw 'done'; } for(const k of Object.keys(o)) findP(o[k]); })(dj); } catch(e){} break; } }
})();
