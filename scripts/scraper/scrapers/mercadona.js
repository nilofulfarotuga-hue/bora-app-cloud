/**
 * Mercadona scraper — API pública tienda.mercadona.es
 *
 * Hierarquia real da API (3 níveis):
 *   GET /api/categories/?wh=mad1
 *     → { results: [ { id, name, categories: [{id:112,...}] } ] }
 *   GET /api/categories/112/?wh=mad1
 *     → { categories: [{id:420, name, products:[...]}] }   ← produtos aqui
 */
import { newPage, sleep } from '../lib/browser.js';
import https from 'https';

const RESTAURANT_ID = 'mercadona-guarda';
const API_BASE = 'https://tienda.mercadona.es/api';
const WH = 'mad1'; // warehouse Madrid — único que responde publicamente

export async function scrapeMercadona(browser, maxProducts = 99999) {
  console.log('\n🟣 FASE 4 — Mercadona');
  const products = [];
  const seen = new Set();

  try {
    // Step 1 — listar todas as categorias de topo
    const topData = await apiGet(`${API_BASE}/categories/?lang=es&wh=${WH}`);
    const topCats = topData?.results || [];
    console.log(`  📡 API OK: ${topCats.length} categorias de topo`);

    for (const topCat of topCats) {
      if (products.length >= maxProducts) break;
      const topName = topCat?.name || 'Outros';
      const midCats = topCat?.categories || [];
      let topCount = 0;

      for (const midCat of midCats) {
        if (products.length >= maxProducts) break;

        // Step 2 — obter sub-categorias folha (que contêm os produtos)
        let leafCats = [];
        try {
          const midData = await apiGet(`${API_BASE}/categories/${midCat.id}/?lang=es&wh=${WH}`);
          leafCats = midData?.categories || [];
          await sleep(150, 350); // rate-limit gentil
        } catch (e) {
          console.warn(`  ⚠ mid-cat ${midCat.id}: ${e.message.split('\n')[0]}`);
          continue;
        }

        // Step 3 — extrair produtos de cada categoria folha
        for (const leaf of leafCats) {
          const leafName = leaf?.name || midCat?.name || topName;
          const items = leaf?.products || [];

          for (const item of items) {
            const name = item?.display_name || item?.description;
            if (!name) continue;
            const key = name.toLowerCase().trim();
            if (seen.has(key)) continue;
            seen.add(key);

            const pi = item?.price_instructions;
            const price = parseFloat(pi?.unit_price ?? pi?.bulk_price ?? 0) || null;
            const photo = item?.thumbnail || item?.photos?.[0]?.zoom || item?.photos?.[0]?.regular || null;

            products.push({
              name: name.trim(),
              price,
              photo_url: photo || null,
              category: leafName,
              unit: pi?.unit_name || null,
              is_on_sale: !!(pi?.is_new),
              description: item?.packaging || null,
              source: 'mercadona.pt',
            });
            topCount++;
          }
        }
      }

      if (topCount > 0) console.log(`     📂 ${topName}: ${topCount} produtos`);
    }
  } catch (err) {
    console.error(`  ❌ Erro Mercadona: ${err.message}`);
  }

  console.log(`  ✅ Total Mercadona: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

/** Direct Node.js HTTPS request — sem browser, sem CORS */
function apiGet(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: {
        'Accept': 'application/json',
        'Accept-Language': 'es-ES,es;q=0.9',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://tienda.mercadona.es/',
      },
    }, (res) => {
      if (res.statusCode >= 400) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`JSON parse error: ${e.message}`)); }
      });
    });
    req.on('error', reject);
    req.setTimeout(15000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}
