/**
 * McDonald's Portugal scraper (mcdonalds.pt)
 * FASE 5 — API interception + DOM fallback
 */
import { newPage, sleep, withRetry } from '../lib/browser.js';

const RESTAURANT_ID = 'mcdonalds-guarda';
const BASE_URL = 'https://www.mcdonalds.pt';

const CATEGORIES = [
  { url: '/comida/burgers/', name: 'Burgers' },
  { url: '/comida/chicken/', name: 'Chicken' },
  { url: '/comida/mcwrap/', name: 'Wraps' },
  { url: '/comida/snacks/', name: 'Snacks' },
  { url: '/comida/saladas/', name: 'Saladas' },
  { url: '/comida/acompanhamentos/', name: 'Acompanhamentos' },
  { url: '/comida/sobremesas/', name: 'Sobremesas' },
  { url: '/comida/bebidas/', name: 'Bebidas' },
  { url: '/comida/pequeno-almoco/', name: 'Pequeno-Almoço' },
  { url: '/comida/happy-meal/', name: 'Happy Meal' },
  { url: '/comida/mcmenu/', name: 'McMenu' },
  { url: '/comida/', name: 'Menu Completo' },
];

export async function scrapeMcdonalds(browser, maxProducts = 2000) {
  console.log('\n🟡 FASE 5 — McDonald\'s Portugal');
  const products = [];
  const seen = new Set();

  for (const cat of CATEGORIES) {
    if (products.length >= maxProducts) break;
    console.log(`  📂 Categoria: ${cat.name}`);

    const { page, context } = await newPage(browser);
    const captured = [];

    // Intercept JSON API responses
    page.on('response', async (response) => {
      const url = response.url();
      const ct = response.headers()['content-type'] || '';
      if (ct.includes('application/json') && (
        url.includes('/api/') ||
        url.includes('/product') ||
        url.includes('/menu') ||
        url.includes('graphql')
      )) {
        try {
          const json = await response.json();
          const items = extractMcdonaldsProducts(json, cat.name);
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
            '#onetrust-accept-btn-handler, [id*="accept"], [class*="accept-all"], button[data-testid*="accept"]'
          ) || [...document.querySelectorAll('button')].find(
            b => /aceitar|accept all|concordo/i.test(b.textContent)
          );
          if (btn) btn.click();
        });
        await sleep(800, 1500);

        // Scroll to load all items
        for (let s = 0; s < 6; s++) {
          await page.evaluate(() => window.scrollBy(0, window.innerHeight * 1.5));
          await sleep(600, 1200);
        }

        // DOM fallback if API gave nothing
        if (captured.length === 0) {
          const domProducts = await scrapeMcdonaldsDom(page, cat.name);
          captured.push(...domProducts);
        }
      }, 2, `McDonald's/${cat.name}`);
    } catch (err) {
      console.warn(`  ⚠ Saltando ${cat.name}: ${err.message}`);
    } finally {
      await context.close();
    }

    for (const p of captured) {
      const key = p.name?.toLowerCase().trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        products.push({ ...p, source: 'mcdonalds.pt' });
      }
    }
    console.log(`     → ${captured.length} capturados (total: ${products.length})`);
    await sleep(2000, 4000);
  }

  // If almost nothing scraped, use static menu as fallback
  if (products.length < 10) {
    console.log('  ℹ️  Usando menu estático como fallback...');
    const staticItems = getStaticMcdonaldsMenu();
    for (const p of staticItems) {
      const key = p.name.toLowerCase().trim();
      if (!seen.has(key)) {
        seen.add(key);
        products.push(p);
      }
    }
  }

  console.log(`  ✅ Total McDonald's: ${products.length} produtos`);
  return { products, restaurantId: RESTAURANT_ID };
}

function extractMcdonaldsProducts(json, category) {
  const results = [];
  const items =
    json?.products ||
    json?.items ||
    json?.menu?.items ||
    json?.data?.products ||
    json?.data?.items ||
    json?.response?.products ||
    (Array.isArray(json) ? json : []);

  for (const item of items) {
    const name =
      item?.name ||
      item?.title ||
      item?.productName ||
      item?.displayName;
    if (!name) continue;

    const price =
      item?.price ||
      item?.basePrice ||
      item?.defaultPrice ||
      item?.priceFrom ||
      null;

    const photo =
      item?.image?.url ||
      item?.imageUrl ||
      item?.image ||
      item?.thumbnail ||
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

async function scrapeMcdonaldsDom(page, category) {
  return page.evaluate((cat) => {
    const products = [];
    const selectors = [
      '[class*="product-card"]',
      '[class*="menu-item"]',
      '[class*="MenuItem"]',
      '[class*="ProductCard"]',
      'article[class*="item"]',
      '.product-tile',
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

      const priceText = card.querySelector('[class*="price"], [class*="Price"]')?.textContent?.trim();
      const price = priceText
        ? parseFloat(priceText.replace(/[^\d,]/g, '').replace(',', '.')) || null
        : null;

      const img =
        card.querySelector('img[src*="mcdonalds"], img[src*="product"], img')?.src ||
        card.querySelector('img')?.dataset?.src ||
        null;

      const desc = card.querySelector('[class*="description"], [class*="desc"], p')?.textContent?.trim() || null;

      products.push({ name, price, photo_url: img, category: cat, description: desc });
    }
    return products;
  }, category);
}

function getStaticMcdonaldsMenu() {
  return [
    // Burgers
    { name: 'Big Mac', price: 5.10, category: 'Burgers', description: 'O clássico hambúrguer McDonald\'s', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McDouble', price: 2.50, category: 'Burgers', description: 'Duplo hambúrguer com queijo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McRoyal', price: 5.80, category: 'Burgers', description: 'Hambúrguer premium 100% carne de vaca', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McRoyal Bacon', price: 6.20, category: 'Burgers', description: 'McRoyal com bacon crocante', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Quarter Pounder with Cheese', price: 5.60, category: 'Burgers', description: '1/4 de libra de carne com queijo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Hamburger', price: 1.50, category: 'Burgers', description: 'Hambúrguer clássico', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Cheeseburger', price: 1.80, category: 'Burgers', description: 'Hambúrguer com queijo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Double Cheeseburger', price: 2.90, category: 'Burgers', description: 'Duplo com queijo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McBacon', price: 4.80, category: 'Burgers', description: 'Hambúrguer com bacon e queijo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Grand McExtreme Bacon Burger', price: 6.50, category: 'Burgers', description: 'Sabor intenso com bacon', photo_url: null, source: 'mcdonalds.pt' },
    // Chicken
    { name: 'McChicken', price: 2.80, category: 'Chicken', description: 'Frango crocante com maionese', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Spicy McChicken', price: 3.20, category: 'Chicken', description: 'Frango picante', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McNuggets 6 peças', price: 3.50, category: 'Chicken', description: '6 McNuggets de frango', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McNuggets 9 peças', price: 4.80, category: 'Chicken', description: '9 McNuggets de frango', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McNuggets 20 peças', price: 9.50, category: 'Chicken', description: '20 McNuggets de frango', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McWrap Frango Grelhado', price: 4.20, category: 'Wraps', description: 'Wrap com frango grelhado e salada', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McWrap Frango Crocante', price: 4.20, category: 'Wraps', description: 'Wrap com frango crocante', photo_url: null, source: 'mcdonalds.pt' },
    // Snacks
    { name: 'McBaguete', price: 3.80, category: 'Snacks', description: 'Baguete com frango grelhado', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McToast', price: 2.50, category: 'Snacks', description: 'Torrada com queijo e presunto', photo_url: null, source: 'mcdonalds.pt' },
    // Acompanhamentos
    { name: 'Batatas Fritas Médias', price: 2.50, category: 'Acompanhamentos', description: 'Batatas fritas no ponto certo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Batatas Fritas Grandes', price: 3.00, category: 'Acompanhamentos', description: 'Dose grande de batatas fritas', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Batatas Fritas Pequenas', price: 1.80, category: 'Acompanhamentos', description: 'Dose pequena de batatas fritas', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McPotato', price: 2.80, category: 'Acompanhamentos', description: 'Batatas com especiarias', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Onion Rings', price: 2.50, category: 'Acompanhamentos', description: 'Anéis de cebola crocantes', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Salada de Frutas', price: 2.00, category: 'Acompanhamentos', description: 'Fruta fresca variada', photo_url: null, source: 'mcdonalds.pt' },
    // Bebidas
    { name: 'Coca-Cola Média', price: 2.00, category: 'Bebidas', description: 'Coca-Cola gelada tamanho médio', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Coca-Cola Grande', price: 2.30, category: 'Bebidas', description: 'Coca-Cola gelada tamanho grande', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Coca-Cola Zero Média', price: 2.00, category: 'Bebidas', description: 'Sem açúcar', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Sprite Média', price: 2.00, category: 'Bebidas', description: 'Refrigerante de limão', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Fanta Laranja Média', price: 2.00, category: 'Bebidas', description: 'Refrigerante de laranja', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Sumo de Laranja', price: 2.50, category: 'Bebidas', description: 'Sumo 100% natural', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Água', price: 1.50, category: 'Bebidas', description: 'Água mineral', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McShake Morango', price: 2.80, category: 'Bebidas', description: 'Milkshake de morango', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McShake Baunilha', price: 2.80, category: 'Bebidas', description: 'Milkshake de baunilha', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McShake Chocolate', price: 2.80, category: 'Bebidas', description: 'Milkshake de chocolate', photo_url: null, source: 'mcdonalds.pt' },
    // Sobremesas
    { name: 'McFlurry Oreo', price: 2.50, category: 'Sobremesas', description: 'Gelado com pedaços de Oreo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McFlurry M&Ms', price: 2.50, category: 'Sobremesas', description: 'Gelado com M&Ms', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Casquinha de Baunilha', price: 1.00, category: 'Sobremesas', description: 'Gelado soft de baunilha', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Sundae Caramelo', price: 1.80, category: 'Sobremesas', description: 'Gelado com calda de caramelo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Sundae Chocolate', price: 1.80, category: 'Sobremesas', description: 'Gelado com calda de chocolate', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Apple Pie', price: 1.50, category: 'Sobremesas', description: 'Pastel de maçã quente', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Donut de Chocolate', price: 1.20, category: 'Sobremesas', description: 'Donut com cobertura de chocolate', photo_url: null, source: 'mcdonalds.pt' },
    // Saladas
    { name: 'Salada César com Frango Grelhado', price: 5.50, category: 'Saladas', description: 'Salada fresca com frango grelhado', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Salada de Frango Crocante', price: 5.50, category: 'Saladas', description: 'Salada com frango crocante', photo_url: null, source: 'mcdonalds.pt' },
    // Pequeno-Almoço
    { name: 'McMuffin Ovo e Queijo', price: 2.80, category: 'Pequeno-Almoço', description: 'Muffin com ovo e queijo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'McMuffin Salsichas', price: 2.50, category: 'Pequeno-Almoço', description: 'Muffin com salsichas', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Hash Brown', price: 1.20, category: 'Pequeno-Almoço', description: 'Batata crocante para o pequeno-almoço', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Panquecas com Maple Syrup', price: 3.50, category: 'Pequeno-Almoço', description: '3 panquecas com xarope de maple', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Porridge', price: 2.00, category: 'Pequeno-Almoço', description: 'Aveia cremosa com frutas', photo_url: null, source: 'mcdonalds.pt' },
    // Happy Meal
    { name: 'Happy Meal Hamburger', price: 4.50, category: 'Happy Meal', description: 'Hambúrguer + batatas + bebida + brinquedo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Happy Meal McChicken', price: 4.50, category: 'Happy Meal', description: 'McChicken + batatas + bebida + brinquedo', photo_url: null, source: 'mcdonalds.pt' },
    { name: 'Happy Meal McNuggets 4 peças', price: 4.50, category: 'Happy Meal', description: '4 McNuggets + batatas + bebida + brinquedo', photo_url: null, source: 'mcdonalds.pt' },
  ];
}
