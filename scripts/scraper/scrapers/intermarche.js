/**
 * Intermarché scraper — Open Food Facts API
 *
 * intermarche.pt não tem loja online. Usamos Open Food Facts,
 * uma base de dados pública com produtos reais de supermercados PT.
 * API: https://world.openfoodfacts.org/
 */
import https from 'https';
import { sleep } from '../lib/browser.js';

const RESTAURANT_ID = 'intermarche-guarda';

// Termos de pesquisa para cobrir categorias principais
const SEARCH_QUERIES = [
  { q: 'intermarché portugal', cat: 'Mercearia' },
  { q: 'marca própria intermarché', cat: 'Mercearia' },
  { q: 'leite portugal supermercado', cat: 'Laticínios' },
  { q: 'arroz portugal', cat: 'Mercearia' },
  { q: 'azeite portugal', cat: 'Mercearia' },
  { q: 'iogurte portugal', cat: 'Laticínios' },
  { q: 'agua mineral portugal', cat: 'Bebidas' },
  { q: 'sumo portugal', cat: 'Bebidas' },
  { q: 'pão portugal', cat: 'Padaria' },
  { q: 'atum conserva portugal', cat: 'Conservas' },
  { q: 'massa esparguete portugal', cat: 'Mercearia' },
  { q: 'frango portugal', cat: 'Carne' },
  { q: 'detergente roupa portugal', cat: 'Limpeza' },
  { q: 'shampoo portugal', cat: 'Higiene' },
  { q: 'queijo portugal', cat: 'Laticínios' },
];

export async function scrapeIntermarche(browser, maxProducts = 3000) {
  console.log('\n🔵 FASE 3 — Intermarché (via Open Food Facts)');
  const products = [];
  const seen = new Set();

  // Also get products specifically tagged with Intermarché stores
  const storeSlugs = ['intermarché', 'intermarche', 'intermarche-portugal'];

  for (const slug of storeSlugs) {
    if (products.length >= maxProducts) break;
    console.log(`  🔍 Open Food Facts — loja: ${slug}`);

    for (let page = 1; page <= 10; page++) {
      if (products.length >= maxProducts) break;
      try {
        const url = `https://world.openfoodfacts.org/store/${encodeURIComponent(slug)}.json?page=${page}&page_size=100`;
        const data = await apiGet(url);
        const items = data?.products || [];
        if (items.length === 0) break;

        for (const item of items) {
          addProduct(item, 'Mercearia', seen, products);
        }
        console.log(`     página ${page}: ${items.length} itens (total: ${products.length})`);
        await sleep(300, 600);
      } catch (e) {
        console.warn(`  ⚠ store/${slug} p${page}: ${e.message.split('\n')[0]}`);
        break;
      }
    }
  }

  // Supplement with country-based search for PT products
  if (products.length < maxProducts) {
    console.log(`  🔍 Open Food Facts — país: Portugal`);
    for (let page = 1; page <= 20; page++) {
      if (products.length >= maxProducts) break;
      try {
        const url = `https://world.openfoodfacts.org/country/portugal.json?page=${page}&page_size=100`;
        const data = await apiGet(url);
        const items = data?.products || [];
        if (items.length === 0) break;

        for (const item of items) {
          addProduct(item, null, seen, products);
        }
        console.log(`     página ${page}: ${items.length} itens (total: ${products.length})`);
        await sleep(300, 600);
      } catch (e) {
        console.warn(`  ⚠ country/portugal p${page}: ${e.message.split('\n')[0]}`);
        break;
      }
    }
  }

  console.log(`  ✅ Total Intermarché (OFF): ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

function addProduct(item, defaultCat, seen, products) {
  const name = item?.product_name_pt || item?.product_name || item?.abbreviated_product_name;
  if (!name || name.trim().length < 2) return;
  const key = name.toLowerCase().trim();
  if (seen.has(key)) return;
  seen.add(key);

  const price = parseFloat(item?.price) || null;
  const photo = item?.image_url || item?.image_front_url || null;
  const cat = item?.categories_tags?.[0]?.replace('en:', '').replace(/-/g, ' ') || defaultCat || 'Outros';
  const brand = item?.brands || null;

  products.push({
    name: name.trim(),
    price,
    photo_url: photo,
    category: cat,
    description: brand,
    unit: item?.quantity || null,
    is_on_sale: false,
    source: 'openfoodfacts.org',
  });
}

function apiGet(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'BoraApp/1.0 (product scraper for local delivery app)',
      },
    }, (res) => {
      if (res.statusCode >= 400) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`JSON parse: ${e.message}`)); }
      });
    });
    req.on('error', reject);
    req.setTimeout(20000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}
