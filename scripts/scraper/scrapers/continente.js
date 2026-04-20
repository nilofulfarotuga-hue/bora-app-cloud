/**
 * Continente scraper
 * Intercepts API calls from continente.pt to extract product data.
 * API pattern: /api/2.0/page/search/ with product JSON responses.
 */
import { newPage, sleep, withRetry } from '../lib/browser.js';

const RESTAURANT_ID = 'continente-guarda';
const BASE_URL = 'https://www.continente.pt';

// Top-level category slugs on continente.pt
const CATEGORIES = [
  { url: '/mercearia/', name: 'Mercearia' },
  { url: '/frescos/', name: 'Frescos' },
  { url: '/padaria-e-pastelaria/', name: 'Padaria' },
  { url: '/bebidas/', name: 'Bebidas' },
  { url: '/congelados/', name: 'Congelados' },
  { url: '/lacticinios-e-ovos/', name: 'Laticínios' },
  { url: '/limpeza-e-higiene/', name: 'Limpeza' },
  { url: '/higiene-e-beleza/', name: 'Higiene' },
  { url: '/bebe/', name: 'Bebé' },
  { url: '/animais/', name: 'Animais' },
];

export async function scrapeContinente(browser, maxProducts = 3000) {
  console.log('\n🟢 FASE 1 — Continente');
  const products = [];
  const seen = new Set();

  for (const cat of CATEGORIES) {
    if (products.length >= maxProducts) break;
    console.log(`  📂 Categoria: ${cat.name}`);

    const { page, context } = await newPage(browser);
    const captured = [];

    // Intercept Continente's internal product API responses
    page.on('response', async (response) => {
      const url = response.url();
      if (
        (url.includes('/api/2.0/page/') || url.includes('/search?') || url.includes('product_list')) &&
        response.headers()['content-type']?.includes('application/json')
      ) {
        try {
          const json = await response.json();
          const items = extractContinenteProducts(json, cat.name);
          captured.push(...items);
        } catch {}
      }
    });

    try {
      await withRetry(async () => {
        await page.goto(BASE_URL + cat.url, { waitUntil: 'networkidle', timeout: 30000 });
        await sleep(1500, 3000);

        // Dismiss CybotCookiebot banner via JS click (bypasses overlay interception)
        await page.evaluate(() => {
          const btn = document.querySelector(
            '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll, #CybotCookiebotDialogBodyButtonAccept, .CybotCookiebotDialogBodyButton'
          );
          if (btn) btn.click();
        });
        await sleep(500, 1000);

        // Scroll to trigger lazy loads
        for (let s = 0; s < 5; s++) {
          await page.evaluate(() => window.scrollBy(0, window.innerHeight));
          await sleep(600, 1200);
        }

        // Try clicking "Ver mais" / "Carregar mais" via JS (avoids overlay blocking)
        let loadMore = true;
        let pages = 0;
        while (loadMore && products.length + captured.length < maxProducts && pages < 20) {
          const clicked = await page.evaluate(() => {
            const btn = document.querySelector(
              '[data-testid="load-more"], .load-more, .ct-load-more'
            ) || [...document.querySelectorAll('button')].find(
              b => b.textContent.includes('Ver mais') || b.textContent.includes('Carregar mais')
            );
            if (btn) { btn.click(); return true; }
            return false;
          });
          if (clicked) {
            await sleep(1500, 2500);
            pages++;
          } else {
            loadMore = false;
          }
        }

        // If no API captured, fallback to DOM scraping
        if (captured.length === 0) {
          const domProducts = await scrapeContinenteDom(page, cat.name);
          captured.push(...domProducts);
        }
      }, 2, `Continente/${cat.name}`);
    } catch (err) {
      console.warn(`  ⚠ Saltando ${cat.name}: ${err.message}`);
    } finally {
      await context.close();
    }

    // Deduplicate
    for (const p of captured) {
      const key = p.name?.toLowerCase().trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        products.push({ ...p, source: 'continente.pt' });
      }
    }
    console.log(`     → ${captured.length} capturados (total: ${products.length})`);
    await sleep(2000, 4000);
  }

  console.log(`  ✅ Total Continente: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

function extractContinenteProducts(json, category) {
  const results = [];

  // Try multiple JSON structures Continente might use
  const items =
    json?.plpContent?.products ||
    json?.products ||
    json?.results ||
    json?.data?.products ||
    json?.response?.docs ||
    [];

  for (const item of items) {
    const name =
      item?.productName ||
      item?.name ||
      item?.title ||
      item?.longDescription;
    if (!name) continue;

    const price =
      item?.price?.selling?.amount ||
      item?.price?.actual ||
      item?.sellPrice ||
      item?.prices?.sellingPrice?.amount ||
      parseFloat(item?.priceValue) ||
      null;

    const photo =
      item?.images?.[0]?.url ||
      item?.image?.url ||
      item?.imageURL ||
      item?.img ||
      null;

    const originalPrice =
      item?.price?.regular?.amount ||
      item?.price?.was ||
      null;

    results.push({
      name: name.trim(),
      price: price ? parseFloat(price) : null,
      photo_url: photo ? (photo.startsWith('http') ? photo : BASE_URL + photo) : null,
      category,
      unit: item?.unitOfMeasure || item?.unit || null,
      is_on_sale: originalPrice && originalPrice > price,
      discount_price: originalPrice && originalPrice > price ? parseFloat(originalPrice) : null,
      description: item?.brand || null,
    });
  }
  return results;
}

async function scrapeContinenteDom(page, category) {
  return page.evaluate((cat) => {
    const products = [];
    // Multiple possible selectors for Continente product cards
    const selectors = [
      '[data-testid="product-card"]',
      '.product-tile',
      '.ct-product-shelf-tile',
      'article.product',
    ];

    let cards = [];
    for (const sel of selectors) {
      cards = [...document.querySelectorAll(sel)];
      if (cards.length > 0) break;
    }

    for (const card of cards) {
      const name =
        card.querySelector('[class*="product-name"], [class*="title"], h3, h2')?.textContent?.trim();
      if (!name) continue;

      const priceText = card.querySelector('[class*="price"], [data-testid*="price"]')?.textContent?.trim();
      const price = priceText ? parseFloat(priceText.replace(/[^0-9,]/g, '').replace(',', '.')) : null;

      const img = card.querySelector('img')?.src || card.querySelector('img')?.dataset?.src || null;

      products.push({ name, price, photo_url: img, category: cat });
    }
    return products;
  }, category);
}
