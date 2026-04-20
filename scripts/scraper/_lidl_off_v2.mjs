// Lidl via OpenFoodFacts — v2 using search-a-licious (search.openfoodfacts.org)
// Much faster than world.openfoodfacts.org, and less rate-limited
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

// Only Latin-script (Portuguese/English/French/etc.) — exclude Cyrillic/CJK/etc.
const isLatinish = (s) => /^[\x20-\x7E\u00A0-\u024F\s]+$/.test(s);

const rows = [];
const seenCodes = new Set();
const PAGE_SIZE = 100;
const MAX_PAGES = 80;
const SLEEP_MS = 1500;
const startTime = Date.now();

// search-a-licious query: brands:lidl
const FIELDS = 'code,product_name,product_name_pt,product_name_fr,product_name_en,brands,image_front_small_url,image_small_url,image_url,categories_tags,quantity,countries_tags';
const BASE = `https://search.openfoodfacts.org/search?q=brands%3Alidl&fields=${encodeURIComponent(FIELDS)}&page_size=${PAGE_SIZE}`;

for (let page = 1; page <= MAX_PAGES; page++) {
  try {
    const r = await httpGet(`${BASE}&page=${page}`);
    if (r.status !== 200) {
      console.log(`page ${page} status=${r.status}, wait 20s and retry`);
      await new Promise((x) => setTimeout(x, 20000));
      const r2 = await httpGet(`${BASE}&page=${page}`);
      if (r2.status !== 200) { console.log(`still ${r2.status} — stopping`); break; }
      r.body = r2.body;
      r.status = 200;
    }
    const j = JSON.parse(r.body);
    const products = j.hits || j.products || [];
    if (!products.length) { console.log(`page ${page} empty — stopping`); break; }

    let added = 0;
    for (const p of products) {
      const code = String(p.code || p._id || '').trim();
      if (!code || seenCodes.has(code)) continue;
      // Prefer PT name, then FR/EN/generic
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
      });
      added++;
    }
    if (page % 5 === 1 || added === 0) {
      console.log(`page=${page} total=${rows.length} added=${added} elapsed=${Math.round((Date.now()-startTime)/1000)}s api_count=${j.count || j.page_count}`);
    }
    if (page % 10 === 0) fs.writeFileSync('scripts/scraper/_lidl_off_v2_raw.json', JSON.stringify(rows));
    if (rows.length >= 6000) { console.log('reached 6000 cap'); break; }
  } catch (e) {
    console.log(`page ${page} ERR ${String(e).slice(0, 120)}`);
  }
  if (page < MAX_PAGES) await new Promise((r) => setTimeout(r, SLEEP_MS));
}

fs.writeFileSync('scripts/scraper/_lidl_off_v2_raw.json', JSON.stringify(rows));
console.log(`DONE total=${rows.length} duration=${Math.round((Date.now()-startTime)/1000)}s`);
