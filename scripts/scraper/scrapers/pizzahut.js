/**
 * Pizza Hut Portugal scraper (pizzahut.pt)
 * FASE 8 — API interception + DOM fallback
 * Pizza Hut PT uses an online ordering platform — try multiple entry points
 */
import { newPage, sleep, withRetry } from '../lib/browser.js';

const RESTAURANT_ID = 'pizzahut-guarda';
const BASE_URL = 'https://www.pizzahut.pt';

// Pizza Hut PT redirects to order.pizzahut.pt for the actual menu
const CATEGORY_URLS = [
  { url: 'https://www.pizzahut.pt/pt-pt/menu', name: 'Menu Completo' },
  { url: 'https://www.pizzahut.pt/pt-pt/menu/pizzas', name: 'Pizzas' },
  { url: 'https://www.pizzahut.pt/pt-pt/menu/entradas', name: 'Entradas' },
  { url: 'https://www.pizzahut.pt/pt-pt/menu/pastas', name: 'Pastas' },
  { url: 'https://www.pizzahut.pt/pt-pt/menu/sobremesas', name: 'Sobremesas' },
  { url: 'https://www.pizzahut.pt/pt-pt/menu/bebidas', name: 'Bebidas' },
  { url: 'https://www.pizzahut.pt/', name: 'Início' },
  // Alternative ordering domain
  { url: 'https://order.pizzahut.pt/menu', name: 'Order Menu' },
];

export async function scrapePizzahut(browser, maxProducts = 2000) {
  console.log('\n🔴 FASE 8 — Pizza Hut Portugal');
  const products = [];
  const seen = new Set();

  for (const cat of CATEGORY_URLS) {
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
        url.includes('/catalog') ||
        url.includes('/items') ||
        url.includes('graphql') ||
        url.includes('yext') ||       // Pizza Hut uses Yext for CMS
        url.includes('pizzahut')
      )) {
        try {
          const json = await response.json();
          const items = extractPizzahutProducts(json, cat.name);
          captured.push(...items);
        } catch {}
      }
    });

    try {
      await withRetry(async () => {
        await page.goto(cat.url, { waitUntil: 'networkidle', timeout: 40000 });
        await sleep(2000, 3000);

        // Accept cookies
        await page.evaluate(() => {
          const btn = document.querySelector(
            '#onetrust-accept-btn-handler, [id*="accept"], [class*="accept-cookies"], [data-testid*="accept"]'
          ) || [...document.querySelectorAll('button')].find(
            b => /aceitar|accept all|concordo|permitir/i.test(b.textContent)
          );
          if (btn) btn.click();
        });
        await sleep(800, 1500);

        // Handle possible location/store selection modal
        await page.evaluate(() => {
          const closeBtn = document.querySelector(
            '[class*="modal"] [class*="close"], [class*="dialog"] [aria-label*="close"], [class*="close-btn"]'
          );
          if (closeBtn) closeBtn.click();
        });
        await sleep(500, 1000);

        for (let s = 0; s < 8; s++) {
          await page.evaluate(() => window.scrollBy(0, window.innerHeight * 1.5));
          await sleep(700, 1300);
        }

        // Try clicking through menu tabs/sections
        const tabs = await page.$$('[class*="tab"], [class*="category"], [role="tab"]');
        for (const tab of tabs.slice(0, 8)) {
          try {
            await tab.click();
            await sleep(800, 1500);
            if (captured.length === 0) {
              const partial = await scrapePizzahutDom(page, cat.name);
              captured.push(...partial);
            }
          } catch {}
        }

        if (captured.length === 0) {
          const domProducts = await scrapePizzahutDom(page, cat.name);
          captured.push(...domProducts);
        }
      }, 2, `PizzaHut/${cat.name}`);
    } catch (err) {
      console.warn(`  ⚠ Saltando ${cat.name}: ${err.message}`);
    } finally {
      await context.close();
    }

    for (const p of captured) {
      const key = p.name?.toLowerCase().trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        products.push({ ...p, source: 'pizzahut.pt' });
      }
    }
    console.log(`     → ${captured.length} capturados (total: ${products.length})`);
    await sleep(2500, 4500);
  }

  if (products.length < 10) {
    console.log('  ℹ️  Usando menu estático como fallback...');
    const staticItems = getStaticPizzahutMenu();
    for (const p of staticItems) {
      const key = p.name.toLowerCase().trim();
      if (!seen.has(key)) {
        seen.add(key);
        products.push(p);
      }
    }
  }

  console.log(`  ✅ Total Pizza Hut: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

function extractPizzahutProducts(json, category) {
  const results = [];

  // Try various JSON structures
  const items =
    json?.products ||
    json?.items ||
    json?.menu?.categories?.flatMap?.(c => c.products || c.items || []) ||
    json?.data?.products ||
    json?.data?.items ||
    json?.response?.products ||
    json?.entities ||
    (Array.isArray(json) ? json : []);

  for (const item of items) {
    const name =
      item?.name ||
      item?.title ||
      item?.productName ||
      item?.displayName ||
      item?.label;
    if (!name || name.length < 2) continue;

    const price =
      item?.price ||
      item?.basePrice ||
      item?.priceFrom ||
      item?.defaultPrice ||
      item?.minPrice ||
      null;

    const photo =
      item?.image?.url ||
      item?.imageUrl ||
      item?.image ||
      item?.thumbnail?.url ||
      item?.thumbnail ||
      null;

    const sizes = item?.sizes || item?.variants || null;
    const description = item?.description ||
      item?.shortDescription ||
      (sizes ? `Tamanhos: ${sizes.map(s => s.name || s).join(', ')}` : null);

    results.push({
      name: name.trim(),
      price: price ? parseFloat(price) : null,
      photo_url: photo
        ? (photo.startsWith('//') ? 'https:' + photo : photo.startsWith('http') ? photo : BASE_URL + photo)
        : null,
      category: category === 'Menu Completo' || category === 'Início' || category === 'Order Menu'
        ? (item?.category || 'Pizzas')
        : category,
      description,
    });
  }
  return results;
}

async function scrapePizzahutDom(page, category) {
  return page.evaluate((cat) => {
    const products = [];
    const selectors = [
      '[class*="product-card"]',
      '[class*="ProductCard"]',
      '[class*="menu-item"]',
      '[class*="MenuItem"]',
      '[class*="pizza-card"]',
      '[class*="PizzaCard"]',
      '[class*="item-card"]',
      'article[class*="product"]',
      '[data-product-id]',
      '[data-testid*="product"]',
      'li[class*="product"]',
    ];

    let cards = [];
    for (const sel of selectors) {
      cards = [...document.querySelectorAll(sel)];
      if (cards.length > 0) break;
    }

    for (const card of cards) {
      const name =
        card.querySelector('h1, h2, h3, h4, [class*="name"], [class*="title"]')?.textContent?.trim();
      if (!name || name.length < 2) continue;

      const priceText = card.querySelector('[class*="price"], [class*="Price"], [data-testid*="price"]')?.textContent?.trim();
      const price = priceText
        ? parseFloat(priceText.replace(/[^\d,]/g, '').replace(',', '.')) || null
        : null;

      const img = card.querySelector('img')?.src || card.querySelector('img')?.dataset?.src || null;
      const desc = card.querySelector('[class*="desc"], [class*="ingredients"], p')?.textContent?.trim() || null;

      products.push({ name, price, photo_url: img, category: cat, description: desc });
    }
    return products;
  }, category);
}

function getStaticPizzahutMenu() {
  return [
    // Pizzas Clássicas
    { name: 'Margherita', price: 8.99, category: 'Pizzas', description: 'Tomate, mozzarella e manjericão fresco', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Pepperoni Lovers', price: 11.99, category: 'Pizzas', description: 'Molho de tomate com tripla quantidade de pepperoni', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Supreme', price: 12.99, category: 'Pizzas', description: 'Pepperoni, salsichas, pimentos, cebola e azeitonas', photo_url: null, source: 'pizzahut.pt' },
    { name: 'BBQ Chicken', price: 12.49, category: 'Pizzas', description: 'Frango grelhado com molho BBQ e cebola', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Veggie', price: 10.99, category: 'Pizzas', description: 'Legumes frescos e queijo mozzarella', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Chicken Italiano', price: 12.49, category: 'Pizzas', description: 'Frango, pimentos, tomates secos e azeitonas', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Tropical Chicken', price: 11.99, category: 'Pizzas', description: 'Frango e ananás com molho de tomate', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Meat Lovers', price: 13.49, category: 'Pizzas', description: 'Pepperoni, bacon, salsichas e carne picada', photo_url: null, source: 'pizzahut.pt' },
    { name: '4 Queijos', price: 11.49, category: 'Pizzas', description: 'Mozzarella, cheddar, emmental e gorgonzola', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Prawn Cocktail', price: 13.99, category: 'Pizzas', description: 'Camarão com molho cocktail e alface', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Tuna Melt', price: 11.99, category: 'Pizzas', description: 'Atum com cebola e azeitonas', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Super Veggie', price: 11.49, category: 'Pizzas', description: 'Mix de legumes grelhados e queijo', photo_url: null, source: 'pizzahut.pt' },
    { name: 'BBQ Bacon', price: 12.99, category: 'Pizzas', description: 'Bacon, frango e molho BBQ', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Hot Dog Stuffed Crust', price: 14.49, category: 'Pizzas', description: 'Orla recheada com salsicha quente', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Cheese Stuffed Crust Margherita', price: 12.49, category: 'Pizzas', description: 'Margherita com orla recheada de queijo', photo_url: null, source: 'pizzahut.pt' },
    // Entradas
    { name: 'Breadsticks', price: 3.49, category: 'Entradas', description: 'Paus de pão com molho de tomate', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Garlic Bread', price: 2.99, category: 'Entradas', description: 'Pão de alho crocante', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Garlic Bread com Queijo', price: 3.49, category: 'Entradas', description: 'Pão de alho com mozzarella gratinada', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Mozzarella Sticks 6 peças', price: 4.99, category: 'Entradas', description: '6 palitos de mozzarella empanados', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Wings de Frango 6 peças', price: 5.49, category: 'Entradas', description: '6 asas de frango crocantes', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Wings de Frango 12 peças', price: 9.49, category: 'Entradas', description: '12 asas de frango crocantes', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Potato Wedges', price: 3.99, category: 'Entradas', description: 'Cunhas de batata temperadas', photo_url: null, source: 'pizzahut.pt' },
    // Pastas
    { name: 'Pasta Bolonhesa', price: 8.49, category: 'Pastas', description: 'Espaguete com molho de carne', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Pasta Carbonara', price: 8.99, category: 'Pastas', description: 'Massa cremosa com bacon', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Pasta ao Pesto', price: 8.49, category: 'Pastas', description: 'Massa com molho pesto de manjericão', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Pasta Arrabiata', price: 7.99, category: 'Pastas', description: 'Massa picante com molho de tomate', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Lasanha Clássica', price: 9.49, category: 'Pastas', description: 'Lasanha de carne ao forno', photo_url: null, source: 'pizzahut.pt' },
    // Bebidas
    { name: 'Coca-Cola 33cl', price: 2.49, category: 'Bebidas', description: 'Coca-Cola gelada', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Coca-Cola 1L', price: 3.99, category: 'Bebidas', description: 'Garrafa de 1 litro', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Coca-Cola Zero 33cl', price: 2.49, category: 'Bebidas', description: 'Sem açúcar', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Fanta Laranja 33cl', price: 2.49, category: 'Bebidas', description: 'Refrigerante de laranja', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Sprite 33cl', price: 2.49, category: 'Bebidas', description: 'Refrigerante de limão', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Água 50cl', price: 1.79, category: 'Bebidas', description: 'Água mineral', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Sumo de Laranja', price: 2.99, category: 'Bebidas', description: 'Sumo natural de laranja', photo_url: null, source: 'pizzahut.pt' },
    // Sobremesas
    { name: 'Cookie Dough', price: 4.49, category: 'Sobremesas', description: 'Bolinha de massa de cookie quente com gelado', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Chocolate Fudge Cake', price: 4.99, category: 'Sobremesas', description: 'Bolo quente de chocolate com gelado', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Hershey\'s Sundae', price: 3.49, category: 'Sobremesas', description: 'Gelado com calda Hershey\'s', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Ben & Jerry\'s Ice Cream', price: 3.99, category: 'Sobremesas', description: 'Gelado premium Ben & Jerry\'s', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Churros', price: 3.99, category: 'Sobremesas', description: 'Churros com calda de chocolate', photo_url: null, source: 'pizzahut.pt' },
    { name: 'Cheesecake de Framboesa', price: 4.49, category: 'Sobremesas', description: 'Cheesecake cremoso com coulis de framboesa', photo_url: null, source: 'pizzahut.pt' },
  ];
}
