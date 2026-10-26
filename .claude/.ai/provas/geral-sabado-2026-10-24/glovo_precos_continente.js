// Preços de HOJE do Continente no Glovo da Guarda (missão geral-sabado-24-10, bloco 5).
// Só lê a API pública do Glovo (a mesma do glovo_walk.js de abril). Não escreve no banco.
// Caminhos = categorias que o catálogo de abril guardou (campo `link` de cada produto).
// Ritmo 4,5 s ± 0,8 s; pára ao primeiro 429. Retoma pelo ficheiro de estado.
// Uso: node glovo_precos_continente.js <catalogo_abril.json> <pasta_saida>
const fs = require('fs');
const path = require('path');

const [, , CAT, SAIDA] = process.argv;
const OUT = path.join(SAIDA, 'glovo_continente_precos.json');
const EST = path.join(SAIDA, 'glovo_continente_estado.json');
const LOG = path.join(SAIDA, 'glovo_continente.log');
const BASE = 'https://api.glovoapp.com/v4/stores/295687/addresses/470732/content/main?nodeType=DEEP_LINK&link=';

const log = (m) => { const l = `[${new Date().toISOString()}] ${m}`; console.log(l); fs.appendFileSync(LOG, l + '\n'); };
const dorme = (ms) => new Promise((r) => setTimeout(r, ms));
const headers = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36',
  Accept: 'application/json, text/plain, */*', 'Accept-Language': 'pt-PT,pt;q=0.9',
  'glovo-api-version': '14', 'glovo-app-platform': 'web', 'glovo-app-type': 'customer',
  'glovo-location-country-code': 'PT', 'glovo-location-city-code': 'GRD',
  'glovo-location-latitude': '40.5373', 'glovo-location-longitude': '-7.2674',
  'glovo-language-code': 'pt', Origin: 'https://glovoapp.com',
  Referer: 'https://glovoapp.com/pt/pt/guarda/stores/continente-grd1',
};

// Preço NORMAL (sem promoção): se o azulejo tiver promoção com preço antigo, vale o antigo.
function precoNormal(d) {
  const promo = (d.promotions || []).find((p) => p && (p.priceInfo || p.originalPrice || p.price));
  const antigo = d.originalPrice ?? d.priceInfo?.originalAmount ?? promo?.originalPrice;
  return { preco: d.price, normal: typeof antigo === 'number' && antigo > d.price ? antigo : d.price, promo: !!promo };
}

function tiles(node, link, acc) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { node.forEach((n) => tiles(n, link, acc)); return; }
  if (node.type === 'PRODUCT_TILE' && node.data && typeof node.data.price === 'number') {
    const d = node.data; const p = precoNormal(d);
    acc.push({ external_id: String(d.externalId ?? d.storeProductId ?? d.id), name: d.name,
      preco_glovo: p.preco, preco_normal: p.normal, promo: p.promo, link });
  }
  for (const v of Object.values(node)) if (v && typeof v === 'object') tiles(v, link, acc);
}

(async () => {
  const cat = JSON.parse(fs.readFileSync(CAT, 'utf8'));
  const links = [...new Set(cat.products.map((p) => p.link).filter(Boolean))].sort();
  const est = fs.existsSync(EST) ? JSON.parse(fs.readFileSync(EST, 'utf8')) : { feitos: [], produtos: {} };
  log(`caminhos: ${links.length}, já feitos: ${est.feitos.length}`);
  for (const link of links) {
    if (est.feitos.includes(link)) continue;
    let r, txt;
    try { r = await fetch(BASE + encodeURIComponent(link).replace(/%2F/g, '/'), { headers }); txt = await r.text(); }
    catch (e) { log(`erro de rede ${link}: ${e.message}`); await dorme(8000); continue; }
    if (r.status === 429) { log('429 — paro aqui (retoma depois)'); break; }
    if (r.status !== 200) { log(`HTTP ${r.status} ${link}`); est.feitos.push(link); continue; }
    const acc = []; tiles(JSON.parse(txt), link, acc);
    for (const p of acc) est.produtos[p.external_id] = p;
    est.feitos.push(link);
    fs.writeFileSync(EST, JSON.stringify(est));
    if (est.feitos.length % 20 === 0) log(`${est.feitos.length}/${links.length} caminhos, ${Object.keys(est.produtos).length} produtos`);
    await dorme(Math.max(3500, 4500 + Math.floor(Math.random() * 1600) - 800));
  }
  const produtos = Object.values(est.produtos);
  fs.writeFileSync(OUT, JSON.stringify({ quando: new Date().toISOString(), caminhos: est.feitos.length, total: produtos.length, produtos }, null, 1));
  log(`FIM: ${est.feitos.length}/${links.length} caminhos, ${produtos.length} produtos, ${produtos.filter((p) => p.promo).length} com promoção`);
})();
