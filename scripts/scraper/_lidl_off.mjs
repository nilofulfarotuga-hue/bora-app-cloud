// Lidl via OpenFoodFacts (L2 fallback per BR §27.2 updated)
// User-approved: Playwright blocked → OFF filtered by brand "lidl"
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
    req.setTimeout(30000, () => { req.destroy(new Error('timeout')); });
  });
}

function titleCase(s) {
  return String(s || '').toLowerCase().split(/\s+/)
    .map((w) => w.length ? w[0].toUpperCase() + w.slice(1) : w).join(' ').trim();
}

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

const rows = [];
const seenCodes = new Set();
const PAGE_SIZE = 100;
const MAX_PAGES = 80;
const SLEEP_MS = 4000; // OFF rate-limits hard — be polite
const RETRY_MS = 15000;
const startTime = Date.now();

// Query: brand=lidl (no country filter — includes all Lidl-branded products)
const BASE = `https://world.openfoodfacts.org/api/v2/search?brands_tags=lidl&fields=code,product_name,product_name_pt,brands,image_front_small_url,image_small_url,image_url,categories_tags,categories,quantity&page_size=${PAGE_SIZE}`;

// Filter: only products with Latin-script names (exclude Cyrillic, CJK, Arabic, Hebrew)
const isLatinish = (s) => /^[\x20-\x7E\u00A0-\u024F\s]+$/.test(s);

async function fetchWithRetry(url, attempt = 0) {
  const r = await httpGet(url);
  if (r.status === 503 && attempt < 3) {
    console.log(`  503 on attempt ${attempt+1}, backoff ${RETRY_MS}ms`);
    await new Promise((x) => setTimeout(x, RETRY_MS));
    return fetchWithRetry(url, attempt + 1);
  }
  return r;
}

for (let page = 1; page <= MAX_PAGES; page++) {
  try {
    const r = await fetchWithRetry(`${BASE}&page=${page}`);
    if (r.status !== 200) { console.log(`page ${page} status ${r.status} — stopping`); break; }
    const j = JSON.parse(r.body);
    const products = j.products || [];
    if (!products.length) { console.log(`page ${page} empty — stopping`); break; }

    let added = 0;
    for (const p of products) {
      const code = String(p.code || p._id || '').trim();
      if (!code || seenCodes.has(code)) continue;
      const name = titleCase(p.product_name_pt || p.product_name || '');
      if (!name || name.length < 3) continue;
      if (!isLatinish(name)) continue;  // skip Cyrillic/CJK/etc.
      const photo = p.image_front_small_url || p.image_small_url || p.image_url;
      if (!photo) continue;
      const qty = (p.quantity || '').toString().trim().slice(0, 40);
      const category = mapCategory(p.categories_tags);
      const brandRaw = (p.brands || '').split(',')[0].trim();
      seenCodes.add(code);
      rows.push({
        code,
        name: qty && isLatinish(qty) ? `${name} ${qty}` : name,
        category,
        brand_low: titleCase(brandRaw),
        photo_url: photo,
      });
      added++;
    }
    if (page % 5 === 1) console.log(`page=${page} total=${rows.length} added=${added} elapsed=${Math.round((Date.now()-startTime)/1000)}s total_api_count=${j.count}`);

    // Save incremental
    if (page % 10 === 0) fs.writeFileSync('scripts/scraper/_lidl_off_raw.json', JSON.stringify(rows));

    if (j.count && rows.length >= j.count) break;
    if (rows.length >= 6000) break;
  } catch (e) {
    console.log(`page ${page} ERR ${String(e).slice(0, 100)}`);
  }
  if (page < MAX_PAGES) await new Promise((r) => setTimeout(r, SLEEP_MS));
}

fs.writeFileSync('scripts/scraper/_lidl_off_raw.json', JSON.stringify(rows));
console.log(`DONE total=${rows.length} duration=${Math.round((Date.now()-startTime)/1000)}s`);
