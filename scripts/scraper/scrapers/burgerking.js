/**
 * Burger King Portugal scraper (burgerking.pt)
 * FASE 7 — API interception + DOM fallback
 */
import { newPage, sleep, withRetry } from '../lib/browser.js';

const RESTAURANT_ID = 'burgerking-guarda';
const BASE_URL = 'https://www.burgerking.pt';

const CATEGORIES = [
  { url: '/menu/burgers/', name: 'Burgers' },
  { url: '/menu/chicken/', name: 'Chicken' },
  { url: '/menu/plant-based/', name: 'Plant-Based' },
  { url: '/menu/kids/', name: 'Kids' },
  { url: '/menu/acompanhamentos/', name: 'Acompanhamentos' },
  { url: '/menu/sobremesas/', name: 'Sobremesas' },
  { url: '/menu/bebidas/', name: 'Bebidas' },
  { url: '/menu/', name: 'Menu Completo' },
  { url: '/', name: 'Início' },
];

export async function scrapeBurgerking(browser, maxProducts = 2000) {
  console.log('\n🟠 FASE 7 — Burger King Portugal');
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
        url.includes('graphql') ||
        url.includes('ctfassets') // Contentful CMS used by BK
      )) {
        try {
          const json = await response.json();
          const items = extractBurgerkingProducts(json, cat.name);
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
            '#onetrust-accept-btn-handler, [class*="cookie"] button, [id*="cookie-accept"]'
          ) || [...document.querySelectorAll('button')].find(
            b => /aceitar|accept|concordo|ok/i.test(b.textContent)
          );
          if (btn) btn.click();
        });
        await sleep(800, 1500);

        for (let s = 0; s < 6; s++) {
          await page.evaluate(() => window.scrollBy(0, window.innerHeight * 1.5));
          await sleep(600, 1100);
        }

        if (captured.length === 0) {
          const domProducts = await scrapeBurgerkingDom(page, cat.name);
          captured.push(...domProducts);
        }
      }, 2, `BurgerKing/${cat.name}`);
    } catch (err) {
      console.warn(`  ⚠ Saltando ${cat.name}: ${err.message}`);
    } finally {
      await context.close();
    }

    for (const p of captured) {
      const key = p.name?.toLowerCase().trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        products.push({ ...p, source: 'burgerking.pt' });
      }
    }
    console.log(`     → ${captured.length} capturados (total: ${products.length})`);
    await sleep(2000, 4000);
  }

  if (products.length < 10) {
    console.log('  ℹ️  Usando menu estático como fallback...');
    const staticItems = getStaticBurgerkingMenu();
    for (const p of staticItems) {
      const key = p.name.toLowerCase().trim();
      if (!seen.has(key)) {
        seen.add(key);
        products.push(p);
      }
    }
  }

  console.log(`  ✅ Total Burger King: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

function extractBurgerkingProducts(json, category) {
  const results = [];

  // Contentful CMS structure
  const contentfulItems =
    json?.items ||
    json?.includes?.Entry ||
    null;

  // Standard API structure
  const items =
    contentfulItems ||
    json?.products ||
    json?.menu?.products ||
    json?.data?.products ||
    json?.data?.items ||
    json?.categories?.flatMap?.(c => c.products || []) ||
    (Array.isArray(json) ? json : []);

  for (const item of items) {
    // Handle Contentful entries
    const fields = item?.fields || item;

    const name =
      fields?.name ||
      fields?.title ||
      fields?.productName ||
      item?.name ||
      item?.title;
    if (!name) continue;

    const price =
      fields?.price ||
      fields?.basePrice ||
      item?.price ||
      item?.priceFrom ||
      null;

    const photo =
      fields?.image?.fields?.file?.url ||
      fields?.imageUrl ||
      item?.image?.url ||
      item?.imageUrl ||
      null;

    results.push({
      name: name.trim(),
      price: price ? parseFloat(price) : null,
      photo_url: photo
        ? (photo.startsWith('//') ? 'https:' + photo : photo.startsWith('http') ? photo : BASE_URL + photo)
        : null,
      category,
      description: fields?.description || item?.description || null,
    });
  }
  return results;
}

async function scrapeBurgerkingDom(page, category) {
  return page.evaluate((cat) => {
    const products = [];
    const selectors = [
      '[class*="product-card"]',
      '[class*="ProductCard"]',
      '[class*="menu-item"]',
      '[class*="MenuItem"]',
      '[class*="burger-card"]',
      'article[class*="product"]',
      '[data-product]',
      'li[class*="product"]',
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

      const priceText = card.querySelector('[class*="price"]')?.textContent?.trim();
      const price = priceText
        ? parseFloat(priceText.replace(/[^\d,]/g, '').replace(',', '.')) || null
        : null;

      const img = card.querySelector('img')?.src || card.querySelector('img')?.dataset?.src || null;
      const desc = card.querySelector('[class*="desc"], p')?.textContent?.trim() || null;

      products.push({ name, price, photo_url: img, category: cat, description: desc });
    }
    return products;
  }, category);
}

function getStaticBurgerkingMenu() {
  return [
    // Burgers
    { name: 'Whopper', price: 5.79, category: 'Burgers', description: 'O icónico hambúrguer grelhado com alface, tomate, cebola e maionese', photo_url: null, source: 'burgerking.pt' },
    { name: 'Whopper Duplo', price: 7.29, category: 'Burgers', description: 'Duplo Whopper grelhado', photo_url: null, source: 'burgerking.pt' },
    { name: 'Whopper com Queijo', price: 6.29, category: 'Burgers', description: 'Whopper com queijo americano', photo_url: null, source: 'burgerking.pt' },
    { name: 'Whopper com Bacon', price: 6.79, category: 'Burgers', description: 'Whopper com bacon crocante', photo_url: null, source: 'burgerking.pt' },
    { name: 'Whopper Spicy', price: 6.29, category: 'Burgers', description: 'Whopper com jalapeños e molho picante', photo_url: null, source: 'burgerking.pt' },
    { name: 'Texas Whopper', price: 6.99, category: 'Burgers', description: 'Com jalapeños, bacon e molho Texas BBQ', photo_url: null, source: 'burgerking.pt' },
    { name: 'BK Stack', price: 7.49, category: 'Burgers', description: 'Dupla carne com duplo queijo', photo_url: null, source: 'burgerking.pt' },
    { name: 'Cheeseburger', price: 2.09, category: 'Burgers', description: 'Hambúrguer com queijo clássico', photo_url: null, source: 'burgerking.pt' },
    { name: 'Double Cheeseburger', price: 3.49, category: 'Burgers', description: 'Duplo com queijo', photo_url: null, source: 'burgerking.pt' },
    { name: 'Hamburger', price: 1.79, category: 'Burgers', description: 'Hambúrguer clássico', photo_url: null, source: 'burgerking.pt' },
    { name: 'Bacon Cheeseburger', price: 3.79, category: 'Burgers', description: 'Com queijo e bacon', photo_url: null, source: 'burgerking.pt' },
    { name: 'XL Bacon', price: 5.99, category: 'Burgers', description: 'Grande burger com muito bacon', photo_url: null, source: 'burgerking.pt' },
    // Chicken
    { name: 'Chicken Royale', price: 5.29, category: 'Chicken', description: 'Frango crocante com alface e maionese', photo_url: null, source: 'burgerking.pt' },
    { name: 'Crispy Chicken', price: 4.79, category: 'Chicken', description: 'Frango extra crocante', photo_url: null, source: 'burgerking.pt' },
    { name: 'Spicy Crispy Chicken', price: 5.29, category: 'Chicken', description: 'Frango crocante picante', photo_url: null, source: 'burgerking.pt' },
    { name: 'Chicken Tenders 3 peças', price: 4.49, category: 'Chicken', description: '3 tiras de frango crocante', photo_url: null, source: 'burgerking.pt' },
    { name: 'Chicken Tenders 5 peças', price: 6.49, category: 'Chicken', description: '5 tiras de frango crocante', photo_url: null, source: 'burgerking.pt' },
    { name: 'Nuggets 6 peças', price: 3.29, category: 'Chicken', description: '6 nuggets de frango', photo_url: null, source: 'burgerking.pt' },
    { name: 'Nuggets 9 peças', price: 4.49, category: 'Chicken', description: '9 nuggets de frango', photo_url: null, source: 'burgerking.pt' },
    { name: 'Chicken Wrap', price: 4.99, category: 'Chicken', description: 'Wrap com frango crocante e salada', photo_url: null, source: 'burgerking.pt' },
    // Plant-Based
    { name: 'Whopper Plant-Based', price: 6.49, category: 'Plant-Based', description: 'Whopper 100% vegetal grelhado', photo_url: null, source: 'burgerking.pt' },
    { name: 'Veggie Burger', price: 4.99, category: 'Plant-Based', description: 'Burger vegetariano com queijo', photo_url: null, source: 'burgerking.pt' },
    { name: 'Plant-Based Nuggets 6 peças', price: 3.79, category: 'Plant-Based', description: '6 nuggets vegetais', photo_url: null, source: 'burgerking.pt' },
    // Kids
    { name: 'BK Kids Hamburger', price: 4.49, category: 'Kids', description: 'Hambúrguer + batatas + bebida', photo_url: null, source: 'burgerking.pt' },
    { name: 'BK Kids Cheeseburger', price: 4.49, category: 'Kids', description: 'Cheeseburger + batatas + bebida', photo_url: null, source: 'burgerking.pt' },
    { name: 'BK Kids Nuggets', price: 4.49, category: 'Kids', description: '4 Nuggets + batatas + bebida', photo_url: null, source: 'burgerking.pt' },
    // Acompanhamentos
    { name: 'Batatas Fritas Médias', price: 2.59, category: 'Acompanhamentos', description: 'Batatas fritas crocantes', photo_url: null, source: 'burgerking.pt' },
    { name: 'Batatas Fritas Grandes', price: 3.29, category: 'Acompanhamentos', description: 'Dose grande', photo_url: null, source: 'burgerking.pt' },
    { name: 'Batatas Fritas Pequenas', price: 1.89, category: 'Acompanhamentos', description: 'Dose pequena', photo_url: null, source: 'burgerking.pt' },
    { name: 'Onion Rings Médios', price: 2.59, category: 'Acompanhamentos', description: 'Anéis de cebola crocantes', photo_url: null, source: 'burgerking.pt' },
    { name: 'BK Loaded Fries', price: 3.99, category: 'Acompanhamentos', description: 'Batatas com molho e queijo', photo_url: null, source: 'burgerking.pt' },
    { name: 'Salada', price: 3.49, category: 'Acompanhamentos', description: 'Salada fresca', photo_url: null, source: 'burgerking.pt' },
    // Bebidas
    { name: 'Coca-Cola Média', price: 2.19, category: 'Bebidas', description: 'Coca-Cola gelada', photo_url: null, source: 'burgerking.pt' },
    { name: 'Coca-Cola Grande', price: 2.59, category: 'Bebidas', description: 'Coca-Cola gelada grande', photo_url: null, source: 'burgerking.pt' },
    { name: 'Coca-Cola Zero Média', price: 2.19, category: 'Bebidas', description: 'Sem açúcar', photo_url: null, source: 'burgerking.pt' },
    { name: 'Fanta Laranja Média', price: 2.19, category: 'Bebidas', description: 'Fanta gelada', photo_url: null, source: 'burgerking.pt' },
    { name: 'Sprite Média', price: 2.19, category: 'Bebidas', description: 'Refrigerante de limão', photo_url: null, source: 'burgerking.pt' },
    { name: 'Água', price: 1.49, category: 'Bebidas', description: 'Água mineral', photo_url: null, source: 'burgerking.pt' },
    { name: 'Café', price: 1.49, category: 'Bebidas', description: 'Café expresso', photo_url: null, source: 'burgerking.pt' },
    // Sobremesas
    { name: 'Sundae Caramelo', price: 1.49, category: 'Sobremesas', description: 'Gelado com calda de caramelo', photo_url: null, source: 'burgerking.pt' },
    { name: 'Sundae Chocolate', price: 1.49, category: 'Sobremesas', description: 'Gelado com calda de chocolate', photo_url: null, source: 'burgerking.pt' },
    { name: 'Milkshake Baunilha', price: 2.99, category: 'Sobremesas', description: 'Milkshake cremoso de baunilha', photo_url: null, source: 'burgerking.pt' },
    { name: 'Milkshake Chocolate', price: 2.99, category: 'Sobremesas', description: 'Milkshake cremoso de chocolate', photo_url: null, source: 'burgerking.pt' },
    { name: 'Milkshake Morango', price: 2.99, category: 'Sobremesas', description: 'Milkshake cremoso de morango', photo_url: null, source: 'burgerking.pt' },
    { name: 'Apple Pie', price: 1.29, category: 'Sobremesas', description: 'Pastel de maçã quente', photo_url: null, source: 'burgerking.pt' },
    { name: 'Cookie', price: 0.99, category: 'Sobremesas', description: 'Bolacha de chocolate', photo_url: null, source: 'burgerking.pt' },
  ];
}
