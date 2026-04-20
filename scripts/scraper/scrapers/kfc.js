/**
 * KFC Portugal scraper (kfc.pt)
 * FASE 6 — API interception + DOM fallback
 */
import { newPage, sleep, withRetry } from '../lib/browser.js';

const RESTAURANT_ID = 'kfc-guarda';
const BASE_URL = 'https://www.kfc.pt';

const CATEGORIES = [
  { url: '/menu/burgers/', name: 'Burgers' },
  { url: '/menu/frango/', name: 'Frango' },
  { url: '/menu/twister/', name: 'Twister' },
  { url: '/menu/snacks/', name: 'Snacks' },
  { url: '/menu/acompanhamentos/', name: 'Acompanhamentos' },
  { url: '/menu/sobremesas/', name: 'Sobremesas' },
  { url: '/menu/bebidas/', name: 'Bebidas' },
  { url: '/menu/', name: 'Menu Completo' },
  { url: '/', name: 'Início' },
];

export async function scrapeKfc(browser, maxProducts = 2000) {
  console.log('\n🔴 FASE 6 — KFC Portugal');
  const products = [];
  const seen = new Set();

  for (const cat of CATEGORIES) {
    if (products.length >= maxProducts) break;
    console.log(`  📂 Categoria: ${cat.name}`);

    const { page, context } = await newPage(browser);
    const captured = [];

    page.on('response', async (response) => {
      const url = response.url();
      const ct = response.headers()['content-type'] || '';
      if (ct.includes('application/json') && (
        url.includes('/api/') ||
        url.includes('/menu') ||
        url.includes('/product') ||
        url.includes('catalog') ||
        url.includes('graphql')
      )) {
        try {
          const json = await response.json();
          const items = extractKfcProducts(json, cat.name);
          captured.push(...items);
        } catch {}
      }
    });

    try {
      await withRetry(async () => {
        await page.goto(BASE_URL + cat.url, { waitUntil: 'networkidle', timeout: 35000 });
        await sleep(1500, 2500);

        // Accept cookies
        await page.evaluate(() => {
          const btn = document.querySelector(
            '#onetrust-accept-btn-handler, [class*="cookie-accept"], [id*="accept-cookies"]'
          ) || [...document.querySelectorAll('button')].find(
            b => /aceitar|accept|concordo/i.test(b.textContent)
          );
          if (btn) btn.click();
        });
        await sleep(800, 1500);

        for (let s = 0; s < 6; s++) {
          await page.evaluate(() => window.scrollBy(0, window.innerHeight * 1.5));
          await sleep(600, 1100);
        }

        if (captured.length === 0) {
          const domProducts = await scrapeKfcDom(page, cat.name);
          captured.push(...domProducts);
        }
      }, 2, `KFC/${cat.name}`);
    } catch (err) {
      console.warn(`  ⚠ Saltando ${cat.name}: ${err.message}`);
    } finally {
      await context.close();
    }

    for (const p of captured) {
      const key = p.name?.toLowerCase().trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        products.push({ ...p, source: 'kfc.pt' });
      }
    }
    console.log(`     → ${captured.length} capturados (total: ${products.length})`);
    await sleep(2000, 4000);
  }

  if (products.length < 10) {
    console.log('  ℹ️  Usando menu estático como fallback...');
    const staticItems = getStaticKfcMenu();
    for (const p of staticItems) {
      const key = p.name.toLowerCase().trim();
      if (!seen.has(key)) {
        seen.add(key);
        products.push(p);
      }
    }
  }

  console.log(`  ✅ Total KFC: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

function extractKfcProducts(json, category) {
  const results = [];
  const items =
    json?.products ||
    json?.items ||
    json?.menu ||
    json?.data?.products ||
    json?.data?.items ||
    json?.categories?.flatMap?.(c => c.products || c.items || []) ||
    (Array.isArray(json) ? json : []);

  for (const item of items) {
    const name =
      item?.name ||
      item?.title ||
      item?.productName ||
      item?.label;
    if (!name) continue;

    const price =
      item?.price ||
      item?.basePrice ||
      item?.priceFrom ||
      item?.defaultPrice ||
      null;

    const photo =
      item?.image?.url ||
      item?.imageUrl ||
      item?.image ||
      item?.img ||
      null;

    results.push({
      name: name.trim(),
      price: price ? parseFloat(price) : null,
      photo_url: photo ? (photo.startsWith('http') ? photo : BASE_URL + photo) : null,
      category,
      description: item?.description || item?.shortDescription || null,
    });
  }
  return results;
}

async function scrapeKfcDom(page, category) {
  return page.evaluate((cat) => {
    const products = [];
    const selectors = [
      '[class*="product-card"]',
      '[class*="menu-item"]',
      '[class*="MenuItem"]',
      '[class*="ProductCard"]',
      '[class*="product-tile"]',
      'article[class*="product"]',
      '[data-product-id]',
      'li[class*="item"]',
    ];

    let cards = [];
    for (const sel of selectors) {
      cards = [...document.querySelectorAll(sel)];
      if (cards.length > 0) break;
    }

    for (const card of cards) {
      const name =
        card.querySelector('h2, h3, h4, [class*="name"], [class*="title"]')?.textContent?.trim();
      if (!name || name.length < 2) continue;

      const priceText = card.querySelector('[class*="price"], [class*="Price"]')?.textContent?.trim();
      const price = priceText
        ? parseFloat(priceText.replace(/[^\d,]/g, '').replace(',', '.')) || null
        : null;

      const img =
        card.querySelector('img')?.src ||
        card.querySelector('img')?.dataset?.src ||
        null;

      const desc = card.querySelector('[class*="desc"], p')?.textContent?.trim() || null;

      products.push({ name, price, photo_url: img, category: cat, description: desc });
    }
    return products;
  }, category);
}

function getStaticKfcMenu() {
  return [
    // Burgers
    { name: 'Zinger Burger', price: 5.49, category: 'Burgers', description: 'Frango picante crocante com alface e maionese', photo_url: null, source: 'kfc.pt' },
    { name: 'Zinger Double', price: 6.99, category: 'Burgers', description: 'Duplo frango picante', photo_url: null, source: 'kfc.pt' },
    { name: 'Tower Burger', price: 5.99, category: 'Burgers', description: 'Burger alto com hash brown', photo_url: null, source: 'kfc.pt' },
    { name: 'BBQ Bacon Tower', price: 6.49, category: 'Burgers', description: 'Tower burger com bacon e molho BBQ', photo_url: null, source: 'kfc.pt' },
    { name: 'Classic Burger', price: 4.49, category: 'Burgers', description: 'Frango crocante clássico', photo_url: null, source: 'kfc.pt' },
    { name: 'Fillet Burger', price: 4.99, category: 'Burgers', description: 'Peito de frango grelhado', photo_url: null, source: 'kfc.pt' },
    { name: 'Colonel Burger', price: 5.99, category: 'Burgers', description: 'O burger do Coronel com a receita original', photo_url: null, source: 'kfc.pt' },
    // Frango
    { name: 'Balde Familiar (8 peças)', price: 16.99, category: 'Frango', description: '8 peças de frango original', photo_url: null, source: 'kfc.pt' },
    { name: 'Balde Familiar (12 peças)', price: 22.99, category: 'Frango', description: '12 peças de frango original', photo_url: null, source: 'kfc.pt' },
    { name: 'Frango Original 2 peças', price: 5.49, category: 'Frango', description: '2 peças de frango com receita original do Coronel', photo_url: null, source: 'kfc.pt' },
    { name: 'Frango Original 3 peças', price: 7.49, category: 'Frango', description: '3 peças de frango original', photo_url: null, source: 'kfc.pt' },
    { name: 'Frango Crocante 2 peças', price: 5.49, category: 'Frango', description: '2 peças de frango extra crocante', photo_url: null, source: 'kfc.pt' },
    { name: 'Hot Wings 5 peças', price: 4.49, category: 'Frango', description: '5 asas picantes', photo_url: null, source: 'kfc.pt' },
    { name: 'Hot Wings 9 peças', price: 7.49, category: 'Frango', description: '9 asas picantes', photo_url: null, source: 'kfc.pt' },
    { name: 'Popcorn Chicken Médio', price: 3.49, category: 'Frango', description: 'Pedaços mini de frango crocante', photo_url: null, source: 'kfc.pt' },
    { name: 'Popcorn Chicken Grande', price: 4.99, category: 'Frango', description: 'Dose grande de popcorn chicken', photo_url: null, source: 'kfc.pt' },
    { name: 'Tenders 3 peças', price: 4.49, category: 'Frango', description: '3 tiras de frango crocante', photo_url: null, source: 'kfc.pt' },
    { name: 'Tenders 5 peças', price: 6.49, category: 'Frango', description: '5 tiras de frango crocante', photo_url: null, source: 'kfc.pt' },
    // Twister
    { name: 'Twister Original', price: 5.49, category: 'Twister', description: 'Wrap com frango crocante e salada', photo_url: null, source: 'kfc.pt' },
    { name: 'Twister Picante', price: 5.49, category: 'Twister', description: 'Wrap com frango picante', photo_url: null, source: 'kfc.pt' },
    { name: 'Twister Grelhado', price: 5.49, category: 'Twister', description: 'Wrap com frango grelhado', photo_url: null, source: 'kfc.pt' },
    // Snacks
    { name: 'Mini Fillet', price: 2.99, category: 'Snacks', description: 'Mini burger de frango crocante', photo_url: null, source: 'kfc.pt' },
    { name: 'Krunch', price: 1.49, category: 'Snacks', description: 'Snack de frango mini', photo_url: null, source: 'kfc.pt' },
    // Acompanhamentos
    { name: 'Batatas Fritas Médias', price: 2.49, category: 'Acompanhamentos', description: 'Batatas fritas crocantes', photo_url: null, source: 'kfc.pt' },
    { name: 'Batatas Fritas Grandes', price: 3.09, category: 'Acompanhamentos', description: 'Dose grande de batatas', photo_url: null, source: 'kfc.pt' },
    { name: 'Coleslaw', price: 1.99, category: 'Acompanhamentos', description: 'Salada de couve com maionese', photo_url: null, source: 'kfc.pt' },
    { name: 'Corn on the Cob', price: 1.99, category: 'Acompanhamentos', description: 'Espiga de milho grelhada', photo_url: null, source: 'kfc.pt' },
    { name: 'Puré de Batata', price: 2.49, category: 'Acompanhamentos', description: 'Puré cremoso', photo_url: null, source: 'kfc.pt' },
    { name: 'Beans', price: 1.99, category: 'Acompanhamentos', description: 'Feijão estufado', photo_url: null, source: 'kfc.pt' },
    { name: 'Hash Brown', price: 1.49, category: 'Acompanhamentos', description: 'Batata crocante', photo_url: null, source: 'kfc.pt' },
    // Bebidas
    { name: 'Pepsi Médio', price: 2.19, category: 'Bebidas', description: 'Pepsi gelada tamanho médio', photo_url: null, source: 'kfc.pt' },
    { name: 'Pepsi Grande', price: 2.49, category: 'Bebidas', description: 'Pepsi gelada tamanho grande', photo_url: null, source: 'kfc.pt' },
    { name: 'Pepsi Max Médio', price: 2.19, category: 'Bebidas', description: 'Sem açúcar', photo_url: null, source: 'kfc.pt' },
    { name: 'Lipton Ice Tea Pêssego', price: 2.19, category: 'Bebidas', description: 'Chá frio de pêssego', photo_url: null, source: 'kfc.pt' },
    { name: 'Mountain Dew', price: 2.19, category: 'Bebidas', description: 'Refrigerante cítrico', photo_url: null, source: 'kfc.pt' },
    { name: 'Água Médio', price: 1.49, category: 'Bebidas', description: 'Água mineral', photo_url: null, source: 'kfc.pt' },
    // Sobremesas
    { name: 'Krushers Morango', price: 2.99, category: 'Sobremesas', description: 'Milkshake gelado de morango', photo_url: null, source: 'kfc.pt' },
    { name: 'Krushers Chocolate', price: 2.99, category: 'Sobremesas', description: 'Milkshake gelado de chocolate', photo_url: null, source: 'kfc.pt' },
    { name: 'Gelado Sundae Caramelo', price: 1.49, category: 'Sobremesas', description: 'Gelado com calda de caramelo', photo_url: null, source: 'kfc.pt' },
    { name: 'Cheesecake', price: 2.49, category: 'Sobremesas', description: 'Cheesecake cremoso', photo_url: null, source: 'kfc.pt' },
    { name: 'Cookie', price: 0.99, category: 'Sobremesas', description: 'Bolacha de chocolate', photo_url: null, source: 'kfc.pt' },
  ];
}
