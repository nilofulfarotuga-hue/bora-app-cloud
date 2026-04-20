/**
 * Pingo Doce scraper
 * Descobre categorias dinamicamente na página, interceta chamadas API,
 * fallback para DOM scraping.
 */
import { newPage, sleep, withRetry } from '../lib/browser.js';

const RESTAURANT_ID = 'pingodoce-guarda';
const BASE_URL = 'https://www.pingodoce.pt';

export async function scrapePingodoce(browser, maxProducts = 1000) {
  console.log('\n🟡 FASE 2 — Pingo Doce');
  const products = [];
  const seen = new Set();

  // Step 1: discover category URLs from the main products page
  const categories = await discoverCategories(browser);
  console.log(`  📋 ${categories.length} categorias descobertas`);

  for (const cat of categories) {
    if (products.length >= maxProducts) break;
    console.log(`  📂 ${cat.name}: ${cat.url}`);

    const { page, context } = await newPage(browser);
    const captured = [];

    // Intercept ALL JSON responses — cast a wide net
    page.on('response', async (response) => {
      const ct = response.headers()['content-type'] || '';
      if (!ct.includes('application/json')) return;
      try {
        const json = await response.json();
        const items = extractProducts(json, cat.name);
        if (items.length > 0) captured.push(...items);
      } catch {}
    });

    try {
      await withRetry(async () => {
        await page.goto(cat.url, { waitUntil: 'networkidle', timeout: 35000 });
        await sleep(2000, 3000);

        // Dismiss cookie banner
        await page.evaluate(() => {
          const btn = document.querySelector(
            '#onetrust-accept-btn-handler, .cookie-accept, button[id*="accept"], button[class*="accept"]'
          ) || [...document.querySelectorAll('button')].find(
            b => /aceitar|concordo|accept/i.test(b.textContent)
          );
          if (btn) btn.click();
        });
        await sleep(500, 1000);

        // Scroll through the full page
        const height = await page.evaluate(() => document.body.scrollHeight);
        for (let y = 300; y <= height + 300; y += 500) {
          await page.evaluate(py => window.scrollTo(0, py), y);
          await sleep(300, 600);
        }

        // Paginate
        let pages = 0;
        while (products.length + captured.length < maxProducts && pages < 20) {
          const hasNext = await page.evaluate(() => {
            const next = document.querySelector('a[rel="next"], .pagination__next, [aria-label*="próxima"], [aria-label*="next"]')
              || [...document.querySelectorAll('button, a')].find(
                el => /próxima|seguinte|next/i.test(el.textContent) && !el.disabled
              );
            if (next) { next.click(); return true; }
            return false;
          });
          if (!hasNext) break;
          await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
          await sleep(1500, 2500);
          pages++;
        }

        // DOM fallback
        if (captured.length === 0) {
          const dom = await scrapeDom(page, cat.name);
          captured.push(...dom);
        }
      }, 2, `PingoDoce/${cat.name}`);
    } catch (err) {
      console.warn(`  ⚠ Saltando ${cat.name}: ${err.message.split('\n')[0]}`);
    } finally {
      await context.close();
    }

    for (const p of captured) {
      const key = p.name?.toLowerCase().trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        products.push({ ...p, source: 'pingodoce.pt' });
      }
    }
    console.log(`     → ${captured.length} capturados (total: ${products.length})`);
    await sleep(2000, 4000);
  }

  console.log(`  ✅ Total Pingo Doce: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

async function discoverCategories(browser) {
  const { page, context } = await newPage(browser);
  try {
    await page.goto(`${BASE_URL}/produtos/`, { waitUntil: 'networkidle', timeout: 30000 });
    await sleep(1500, 2500);

    const links = await page.evaluate((base) => {
      const anchors = [...document.querySelectorAll('a[href]')];
      const seen = new Set();
      return anchors
        .map(a => ({ href: a.href, text: a.textContent?.trim() }))
        .filter(l => {
          if (!l.href.includes(base) || !l.text || l.text.length < 2) return false;
          if (seen.has(l.href)) return false;
          // Must look like a category link (contains /produtos/ or category path)
          const path = new URL(l.href).pathname;
          if (path === '/produtos/' || path === '/') return false;
          if (path.split('/').length < 3) return false;
          seen.add(l.href);
          return true;
        })
        .slice(0, 20);
    }, BASE_URL);

    // If no links found, use fallback hardcoded categories
    if (links.length === 0) {
      return [
        { url: `${BASE_URL}/produtos/`, name: 'Todos os Produtos' },
      ];
    }
    return links.map(l => ({ url: l.href, name: l.text || 'Categoria' }));
  } catch {
    return [{ url: `${BASE_URL}/produtos/`, name: 'Todos os Produtos' }];
  } finally {
    await context.close();
  }
}

function extractProducts(json, category) {
  const results = [];
  const candidates = [
    json?.products, json?.items, json?.data?.products, json?.data?.items,
    json?.response?.products, json?.hits, json?.results,
    json?.productList, json?.catalog?.products,
  ];

  for (const list of candidates) {
    if (!Array.isArray(list) || list.length === 0) continue;
    for (const item of list) {
      const name = item?.name || item?.title || item?.productName || item?.display_name;
      if (!name || typeof name !== 'string') continue;

      const price = parseFloat(
        item?.price?.current ?? item?.currentPrice ?? item?.priceValue ??
        item?.price ?? item?.salePrice ?? 0
      ) || null;

      const photo =
        item?.images?.[0]?.url ?? item?.imageUrl ?? item?.image ??
        item?.thumbnail ?? item?.photos?.[0]?.url ?? null;

      results.push({
        name: name.trim(),
        price,
        photo_url: photo?.startsWith('http') ? photo : photo ? BASE_URL + photo : null,
        category,
        description: item?.brand || item?.brandName || null,
        is_on_sale: !!(item?.hasPromotion || item?.onSale || item?.isPromotion),
      });
    }
    if (results.length > 0) break; // found products, stop trying other keys
  }
  return results;
}

async function scrapeDom(page, category) {
  return page.evaluate((cat) => {
    const selectors = [
      '[class*="product-card"]', '[class*="productCard"]',
      '[class*="product-item"]', '[class*="productItem"]',
      '.product', 'article[class*="item"]',
    ];
    let cards = [];
    for (const s of selectors) {
      cards = [...document.querySelectorAll(s)];
      if (cards.length) break;
    }
    return cards.map(card => {
      const name = card.querySelector('[class*="name"],[class*="title"],h3,h2,p')?.textContent?.trim();
      const priceText = card.querySelector('[class*="price"]')?.textContent || '';
      const price = parseFloat(priceText.replace(/[^0-9,]/g, '').replace(',', '.')) || null;
      const img = card.querySelector('img')?.src || null;
      return name ? { name, price, photo_url: img, category: cat } : null;
    }).filter(Boolean);
  }, category);
}
