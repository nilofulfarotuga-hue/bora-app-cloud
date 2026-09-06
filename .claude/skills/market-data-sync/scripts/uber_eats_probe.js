#!/usr/bin/env node
/**
 * uber_eats_probe.js — Acesso à API web da Uber Eats a partir de Node (2026-06-06).
 *
 * DESCOBERTAS QUE FUNCIONAM:
 *  - O header-overflow anti-bot da homepage resolve-se com `maxHeaderSize: 131072` em https.request.
 *  - A localização (obrigatória p/ feed/loja) faz-se com cookie `uev2.loc` contendo um
 *    `reference` = place_id REAL do Google (referenceType: 'google_places'). Sem place_id válido,
 *    o feed vem vazio. Obter place_id via Google Places (GOOGLE_MAPS_API_KEY do .dart_defines).
 *  - getSearchSuggestionsV1 (POST) -> 200 sem localização.
 *  - getFeedV1 (POST, com cookie uev2.loc) -> 200, lista lojas da zona (storeUuid + title).
 *    Intermarché Guarda = storeUuid a0fe1ff9-4042-55a3-9a28-ae1d84b93576 (title "pt_intermarche").
 *  - getStoreV1 (POST {storeUuid}) -> 200, 260KB: data.sections (44 categorias: Charcutaria,
 *    Frutas e Legumes, Álcool, ...) + ~75 produtos featured (catalogSectionsMap, 5 secções).
 *    Item: { uuid, title, price (CÊNTIMOS), imageUrl, subsectionUuid, isAvailable }.
 *
 * BLOQUEIO POR RESOLVER (TODO):
 *  - Carregar TODOS os ~3000 produtos por secção. getCatalogPresentationV2 devolve sempre
 *    "Pedido inválido" (400) com todas as combinações testadas de params
 *    ({storeUuid, sectionUuid, subsectionUuids[]}, +pageInfo, +vertical, single sub, swaps).
 *  - PARA FINALIZAR: capturar 1 request real de getCatalogPresentationV2 no DevTools do
 *    browser (Network tab, ao fazer scroll numa categoria da loja Uber) -> copiar o body
 *    exato -> replicar aqui. Depois iterar as 44 sections como no crawler Glovo.
 *
 * Headers necessários: user-agent Chrome, 'x-csrf-token':'x', 'x-uber-client-name':'eats-web',
 *   content-type application/json, cookie uev2.loc.
 *
 * Preço: Uber tem markup -> preço-base Bora = preço_uber * 0.85 (regra "Uber menos 15%").
 * Uso: node uber_eats_probe.js   (lê GOOGLE_MAPS_API_KEY de .dart_defines)
 */
'use strict';
const https = require('https'); const fs = require('fs');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/146.0.0.0 Safari/537.36';
function getJSON(url) { return new Promise(r => https.get(url, { headers: { 'user-agent': UA } }, s => { let d = ''; s.on('data', c => d += c); s.on('end', () => r(d)); })); }
function uber(path, body, cookie) {
  return new Promise(res => { const data = JSON.stringify(body || {});
    const r = https.request({ method: 'POST', hostname: 'www.ubereats.com', path, maxHeaderSize: 131072,
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data), 'user-agent': UA, accept: 'application/json', 'x-csrf-token': 'x', 'x-uber-client-name': 'eats-web', cookie: cookie || '' } },
      resp => { let d = ''; resp.on('data', c => d += c); resp.on('end', () => res({ s: resp.statusCode, d })); });
    r.on('error', e => res({ s: 0, d: '' + e.message })); r.write(data); r.end(); });
}
async function guardaCookie() {
  const dd = fs.readFileSync('.dart_defines', 'utf8');
  const k = (dd.match(/GOOGLE_MAPS_API_KEY\s*=\s*(.+)/) || [])[1].trim().replace(/^["']|["']$/g, '');
  const g = JSON.parse(await getJSON('https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=' + encodeURIComponent('Guarda, Portugal') + '&inputtype=textquery&fields=place_id,geometry&key=' + k));
  const p = g.candidates[0];
  return 'uev2.loc=' + encodeURIComponent(JSON.stringify({ address: { title: 'Guarda', address1: 'Guarda' }, latitude: p.geometry.location.lat, longitude: p.geometry.location.lng, reference: p.place_id, referenceType: 'google_places', type: 'google_places' }));
}
module.exports = { uber, guardaCookie };
if (require.main === module) (async () => {
  const cookie = await guardaCookie();
  const r = await uber('/api/getStoreV1?localeCode=pt', { storeUuid: 'a0fe1ff9-4042-55a3-9a28-ae1d84b93576' }, cookie);
  const j = JSON.parse(r.d).data;
  console.log('getStoreV1', r.s, '| sections', j.sections.length, '| featured items',
    (r.d.match(/\"price\":[0-9]+/g) || []).length);
})();
