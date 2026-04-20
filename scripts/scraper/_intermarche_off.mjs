// Intermarché via OpenFoodFacts — L1 exception (sem loja online)
// Combina brands: Intermarché, Pâturages, Top Budget, Monique Ranou, Les Croises
// Target: 3.000 produtos após dedup
import https from 'https';
import fs from 'fs';

const HEADERS = {
  'User-Agent': 'BoraApp/1.0 (contact: nilofulfarotuga@gmail.com)',
  'Accept': 'application/json',
};

function httpGet(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: HEADERS }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.setTimeout(45000, () => { req.destroy(new Error('timeout')); });
  });
}

const titleCase = (s) =>
  String(s || '').toLowerCase().split(/\s+/)
    .map((w) => w.length ? w[0].toUpperCase() + w.slice(1) : w).join(' ').trim();

function mapCategory(catTags) {
  const all = (catTags || []).join(' ').toLowerCase();
  if (/beverage|drink|water|juice|soda/.test(all)) return 'Bebidas';
  if (/dairy|milk|yogurt|cheese|butter/.test(all)) return 'Laticínios';
  if (/meat|beef|pork|chicken|sausage/.test(all)) return 'Carne';
  if (/fish|seafood|salmon|tuna/.test(all)) return 'Peixe';
  if (/fruit|apple|banana|orange/.test(all)) return 'Frutas';
  if (/vegetable|tomato|potato|lettuce/.test(all)) return 'Legumes';
  if (/frozen/.test(all)) return 'Congelados';
  if (/chocolate|candy|sweet|biscuit|cookie/.test(all)) return 'Chocolates e Doces';
  if (/bread|pastry|bakery/.test(all)) return 'Padaria';
  if (/snack|chip|cracker/.test(all)) return 'Snacks';
  if (/baby|infant/.test(all)) return 'Bebé';
  if (/pet|cat|dog/.test(all)) return 'Animais';
  if (/cleaning|detergent|soap/.test(all)) return 'Limpeza';
  if (/hygiene|shampoo|toothpaste/.test(all)) return 'Higiene';
  if (/oil|vinegar|sauce|spice|pasta|rice|cereal/.test(all)) return 'Mercearia';
  return 'Mercearia';
}

const isLatinish = (s) => /^[\x20-\x7E\u00A0-\u024F\s]+$/.test(s);

const rows = [];
const seenCodes = new Set();
const PAGE_SIZE = 100;
const MAX_PAGES_PER_BRAND = 60;
const SLEEP_MS = 1500;
const TARGET = 3500; // colher um pouco acima do target para deduplicar
const startTime = Date.now();

const FIELDS = 'code,product_name,product_name_pt,product_name_fr,product_name_en,brands,image_front_small_url,image_small_url,image_url,categories_tags,quantity,countries_tags';

// brand queries em ordem de prioridade
const BRAND_QUERIES = [
  'brands:Intermarché',
  'brands:"Pâturages"',
  'brands:"Monique Ranou"',
  'brands:"Top Budget"',
  'brands:"Les Croises"',
  'brands:"Chabrior"',
  'brands:"Paquito"',
  'brands:"Itinéraire des Saveurs"',
];

async function scrapeBrand(query) {
  const encoded = encodeURIComponent(query);
  const BASE = `https://search.openfoodfacts.org/search?q=${encoded}&fields=${encodeURIComponent(FIELDS)}&page_size=${PAGE_SIZE}`;
  let brandAdded = 0;

  for (let page = 1; page <= MAX_PAGES_PER_BRAND; page++) {
    if (rows.length >= TARGET) return brandAdded;
    try {
      const r = await httpGet(`${BASE}&page=${page}`);
      if (r.status !== 200) {
        console.log(`  [${query}] page ${page} status=${r.status}, backoff 20s`);
        await new Promise((x) => setTimeout(x, 20000));
        const r2 = await httpGet(`${BASE}&page=${page}`);
        if (r2.status !== 200) { console.log(`  [${query}] still ${r2.status} — skip brand`); break; }
        r.body = r2.body;
        r.status = 200;
      }
      const j = JSON.parse(r.body);
      const products = j.hits || j.products || [];
      if (!products.length) { console.log(`  [${query}] page ${page} empty — done`); break; }

      let added = 0;
      for (const p of products) {
        if (rows.length >= TARGET) break;
        const code = String(p.code || p._id || '').trim();
        if (!code || seenCodes.has(code)) continue;
        const nameRaw = p.product_name_pt || p.product_name_fr || p.product_name_en || p.product_name || '';
        const name = titleCase(nameRaw);
        if (!name || name.length < 3) continue;
        if (!isLatinish(name)) continue;
        const photo = p.image_front_small_url || p.image_small_url || p.image_url;
        if (!photo) continue;
        const qty = (p.quantity || '').toString().trim().slice(0, 40);
        const qtyPart = qty && isLatinish(qty) ? ` ${qty}` : '';
        const category = mapCategory(p.categories_tags);
        const brandsList = Array.isArray(p.brands) ? p.brands : String(p.brands || '').split(',');
        const brandRaw = (brandsList[0] || '').trim();
        seenCodes.add(code);
        rows.push({
          code,
          name: `${name}${qtyPart}`.trim(),
          category,
          brand_low: titleCase(brandRaw),
          photo_url: photo,
          brand_query: query,
        });
        added++;
        brandAdded++;
      }
      if (page % 5 === 1 || added === 0) {
        console.log(`  [${query}] page=${page} total=${rows.length} added=${added} api_count=${j.count || j.page_count}`);
      }
      if (rows.length >= TARGET) { console.log(`  reached TARGET=${TARGET}`); return brandAdded; }
    } catch (e) {
      console.log(`  [${query}] page ${page} ERR ${String(e).slice(0, 120)}`);
    }
    if (page < MAX_PAGES_PER_BRAND) await new Promise((r) => setTimeout(r, SLEEP_MS));
  }
  return brandAdded;
}

for (const q of BRAND_QUERIES) {
  if (rows.length >= TARGET) break;
  console.log(`=== Scraping ${q} ===`);
  const added = await scrapeBrand(q);
  console.log(`=== ${q} added=${added} cumulative=${rows.length} elapsed=${Math.round((Date.now()-startTime)/1000)}s ===`);
  fs.writeFileSync('scripts/scraper/_intermarche_off_raw.json', JSON.stringify(rows));
  if (rows.length >= TARGET) break;
}

fs.writeFileSync('scripts/scraper/_intermarche_off_raw.json', JSON.stringify(rows));
console.log(`DONE total=${rows.length} duration=${Math.round((Date.now()-startTime)/1000)}s`);
