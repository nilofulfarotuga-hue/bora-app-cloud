/**
 * seed_products.js
 * Generates ~1000+ products for non-partner stores (Continente, Pingo Doce, Lidl, etc.)
 *
 * Usage:
 *   npm install @supabase/supabase-js
 *   node seed_products.js
 *
 * Env vars (or edit the constants below):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_KEY
 */

const { createClient } = require('@supabase/supabase-js');

// ─── CONFIG ──────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || 'YOUR_SERVICE_KEY';
const BATCH_SIZE = 150;

// ─── STORE DEFINITIONS (multi-store ready) ────────────────────────────────────

const STORES = {
  continente: {
    brands: {
      budget:  ['Continente'],
      mid:     ['Mimosa', 'Compal', 'Delta', 'Nobre', 'Iglo', 'Campbells', 'Matinal'],
      premium: ['Nestlé', 'Danone', "Ben & Jerry's", 'Lindt', 'Häagen-Dazs', 'Pringles'],
    },
    multipliers: { budget: 1.0, mid: 1.2, premium: 1.5 },
    appMarkup: 1.15,
  },
  pingo_doce: {
    brands: {
      budget:  ['Pingo Doce'],
      mid:     ['Mimosa', 'Compal', 'Delta', 'Nobre', 'Vaqueiro'],
      premium: ['Nestlé', 'Danone', 'President', 'Président'],
    },
    multipliers: { budget: 1.0, mid: 1.2, premium: 1.5 },
    appMarkup: 1.15,
  },
  lidl: {
    brands: {
      budget:  ['Lidl', 'Favorina', 'Cien'],
      mid:     ['Milbona', 'Pikok', 'Nixe'],
      premium: ['Deluxe', 'Bioorganic'],
    },
    multipliers: { budget: 0.95, mid: 1.1, premium: 1.4 },
    appMarkup: 1.15,
  },
};

// ─── BASE PRODUCTS (~120 items) ───────────────────────────────────────────────
// Fields: name, category, priceRange [min, max], allowPremium

const BASE_PRODUCTS = [
  // ── MERCEARIA ──
  { name: 'Arroz Agulha',             category: 'mercearia',  priceRange: [0.60, 1.20], allowPremium: false },
  { name: 'Arroz Carolino',           category: 'mercearia',  priceRange: [0.70, 1.40], allowPremium: false },
  { name: 'Arroz Integral',           category: 'mercearia',  priceRange: [0.90, 1.80], allowPremium: true  },
  { name: 'Massa Esparguete',         category: 'mercearia',  priceRange: [0.45, 1.10], allowPremium: false },
  { name: 'Massa Penne',              category: 'mercearia',  priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Massa Fusilli',            category: 'mercearia',  priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Farinha de Trigo T55',     category: 'mercearia',  priceRange: [0.50, 1.00], allowPremium: false },
  { name: 'Farinha de Trigo T65',     category: 'mercearia',  priceRange: [0.60, 1.20], allowPremium: false },
  { name: 'Farinha de Milho',         category: 'mercearia',  priceRange: [0.70, 1.40], allowPremium: false },
  { name: 'Açúcar Branco 1kg',        category: 'mercearia',  priceRange: [0.65, 1.30], allowPremium: false },
  { name: 'Açúcar Amarelo 1kg',       category: 'mercearia',  priceRange: [0.75, 1.50], allowPremium: false },
  { name: 'Sal Fino 1kg',             category: 'mercearia',  priceRange: [0.30, 0.80], allowPremium: false },
  { name: 'Sal Grosso 1kg',           category: 'mercearia',  priceRange: [0.30, 0.80], allowPremium: false },
  { name: 'Azeite Virgem Extra 750ml',category: 'mercearia',  priceRange: [3.50, 7.00], allowPremium: true  },
  { name: 'Óleo de Girassol 1L',      category: 'mercearia',  priceRange: [1.20, 2.50], allowPremium: false },
  { name: 'Vinagre de Vinho Branco',  category: 'mercearia',  priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Tomate Pelado 400g',       category: 'mercearia',  priceRange: [0.40, 0.90], allowPremium: false },
  { name: 'Tomate Triturado 500ml',   category: 'mercearia',  priceRange: [0.50, 1.00], allowPremium: false },
  { name: 'Feijão Vermelho Cozido',   category: 'mercearia',  priceRange: [0.50, 1.10], allowPremium: false },
  { name: 'Grão de Bico Cozido',      category: 'mercearia',  priceRange: [0.55, 1.20], allowPremium: false },
  { name: 'Lentilhas',                category: 'mercearia',  priceRange: [0.60, 1.30], allowPremium: false },
  { name: 'Atum em Água 120g',        category: 'mercearia',  priceRange: [0.60, 1.40], allowPremium: true  },
  { name: 'Sardinhas em Azeite',      category: 'mercearia',  priceRange: [0.80, 1.80], allowPremium: true  },
  { name: 'Polpa de Tomate 200g',     category: 'mercearia',  priceRange: [0.30, 0.80], allowPremium: false },
  { name: 'Maionese 250ml',           category: 'mercearia',  priceRange: [0.90, 2.20], allowPremium: true  },
  { name: 'Ketchup 560g',             category: 'mercearia',  priceRange: [1.00, 2.50], allowPremium: true  },
  { name: 'Mostarda 270g',            category: 'mercearia',  priceRange: [0.80, 1.80], allowPremium: false },
  { name: 'Molho de Soja 150ml',      category: 'mercearia',  priceRange: [0.90, 2.00], allowPremium: false },
  { name: 'Caldo de Legumes 6 cubos', category: 'mercearia',  priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Caldo de Frango 6 cubos',  category: 'mercearia',  priceRange: [0.50, 1.20], allowPremium: false },

  // ── BEBIDAS ──
  { name: 'Água 1.5L',                category: 'bebidas',    priceRange: [0.25, 0.65], allowPremium: false },
  { name: 'Água com Gás 1.5L',        category: 'bebidas',    priceRange: [0.30, 0.80], allowPremium: false },
  { name: 'Sumo Laranja 1L',          category: 'bebidas',    priceRange: [0.90, 2.20], allowPremium: true  },
  { name: 'Sumo Maçã 1L',             category: 'bebidas',    priceRange: [0.80, 2.00], allowPremium: true  },
  { name: 'Sumo Pêssego 1L',          category: 'bebidas',    priceRange: [0.85, 2.10], allowPremium: false },
  { name: 'Sumo Ananás 1L',           category: 'bebidas',    priceRange: [0.85, 2.00], allowPremium: false },
  { name: 'Sumo Multifrutas 1L',      category: 'bebidas',    priceRange: [0.90, 2.20], allowPremium: false },
  { name: 'Refrigerante Cola 2L',     category: 'bebidas',    priceRange: [1.00, 2.00], allowPremium: false },
  { name: 'Refrigerante Laranja 1.5L',category: 'bebidas',    priceRange: [0.70, 1.60], allowPremium: false },
  { name: 'Refrigerante Limão 1.5L',  category: 'bebidas',    priceRange: [0.70, 1.60], allowPremium: false },
  { name: 'Chá Preto 20 saquetas',    category: 'bebidas',    priceRange: [0.60, 1.80], allowPremium: true  },
  { name: 'Chá Verde 20 saquetas',    category: 'bebidas',    priceRange: [0.70, 2.00], allowPremium: true  },
  { name: 'Café em Grão 500g',        category: 'bebidas',    priceRange: [2.50, 6.00], allowPremium: true  },
  { name: 'Café Moído 250g',          category: 'bebidas',    priceRange: [1.50, 3.50], allowPremium: true  },
  { name: 'Café Solúvel 200g',        category: 'bebidas',    priceRange: [2.00, 5.00], allowPremium: true  },
  { name: 'Leite com Chocolate 200ml',category: 'bebidas',    priceRange: [0.50, 1.20], allowPremium: true  },
  { name: 'Cerveja 33cl Pack 6',      category: 'bebidas',    priceRange: [2.50, 5.00], allowPremium: false },
  { name: 'Vinho Tinto 750ml',        category: 'bebidas',    priceRange: [2.50, 8.00], allowPremium: true  },
  { name: 'Vinho Branco 750ml',       category: 'bebidas',    priceRange: [2.50, 7.50], allowPremium: true  },
  { name: 'Sumo de Tomate 1L',        category: 'bebidas',    priceRange: [0.80, 1.80], allowPremium: false },

  // ── LATICÍNIOS ──
  { name: 'Leite Meio-gordo 1L',      category: 'laticinios', priceRange: [0.60, 1.20], allowPremium: true  },
  { name: 'Leite Gordo 1L',           category: 'laticinios', priceRange: [0.65, 1.30], allowPremium: true  },
  { name: 'Leite Magro 1L',           category: 'laticinios', priceRange: [0.60, 1.20], allowPremium: false },
  { name: 'Leite UHT 6x1L',          category: 'laticinios', priceRange: [3.50, 6.50], allowPremium: true  },
  { name: 'Iogurte Natural 125g',     category: 'laticinios', priceRange: [0.25, 0.65], allowPremium: true  },
  { name: 'Iogurte Grego 150g',       category: 'laticinios', priceRange: [0.55, 1.30], allowPremium: true  },
  { name: 'Iogurte Morango 4 pack',   category: 'laticinios', priceRange: [1.00, 2.50], allowPremium: true  },
  { name: 'Iogurte Líquido Morango',  category: 'laticinios', priceRange: [0.40, 1.00], allowPremium: true  },
  { name: 'Manteiga 250g',            category: 'laticinios', priceRange: [1.00, 2.50], allowPremium: true  },
  { name: 'Margarina 500g',           category: 'laticinios', priceRange: [0.90, 2.00], allowPremium: false },
  { name: 'Queijo Flamengo Fatiado',  category: 'laticinios', priceRange: [1.50, 3.50], allowPremium: true  },
  { name: 'Queijo Mozzarella 125g',   category: 'laticinios', priceRange: [0.90, 2.20], allowPremium: true  },
  { name: 'Queijo Parmesão Ralado',   category: 'laticinios', priceRange: [1.50, 3.50], allowPremium: true  },
  { name: 'Natas para Culinária 200ml',category:'laticinios', priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Requeijão 250g',           category: 'laticinios', priceRange: [0.80, 1.80], allowPremium: false },
  { name: 'Ovo Classe M 10 un.',      category: 'laticinios', priceRange: [1.20, 2.50], allowPremium: false },

  // ── CONGELADOS ──
  { name: 'Batata Frita Palito 1kg',  category: 'congelados', priceRange: [1.00, 2.50], allowPremium: true  },
  { name: 'Pizza Margherita 350g',    category: 'congelados', priceRange: [1.50, 3.50], allowPremium: true  },
  { name: 'Pizza Frango 350g',        category: 'congelados', priceRange: [1.60, 3.80], allowPremium: true  },
  { name: 'Peixe Panado 400g',        category: 'congelados', priceRange: [2.00, 4.50], allowPremium: true  },
  { name: 'Camarão 400g',             category: 'congelados', priceRange: [4.00, 9.00], allowPremium: true  },
  { name: 'Legumes Mistos 750g',      category: 'congelados', priceRange: [1.00, 2.50], allowPremium: false },
  { name: 'Ervilhas 1kg',             category: 'congelados', priceRange: [0.80, 1.80], allowPremium: false },
  { name: 'Espinafres 600g',          category: 'congelados', priceRange: [0.90, 2.00], allowPremium: false },
  { name: 'Frango Panado 400g',       category: 'congelados', priceRange: [2.00, 4.50], allowPremium: true  },
  { name: 'Gelado Baunilha 1L',       category: 'congelados', priceRange: [1.80, 5.50], allowPremium: true  },
  { name: 'Gelado Chocolate 500ml',   category: 'congelados', priceRange: [1.50, 4.50], allowPremium: true  },
  { name: 'Gelado Morango 1L',        category: 'congelados', priceRange: [1.80, 5.50], allowPremium: true  },
  { name: 'Croquetes 500g',           category: 'congelados', priceRange: [1.20, 3.00], allowPremium: false },
  { name: 'Hambúrguer Vaca 4 un.',    category: 'congelados', priceRange: [2.50, 5.50], allowPremium: true  },

  // ── LIMPEZA ──
  { name: 'Detergente Roupa Liquido 1.5L', category: 'limpeza', priceRange: [2.00, 5.50], allowPremium: true },
  { name: 'Detergente Roupa Pó 3kg',  category: 'limpeza',    priceRange: [3.00, 7.00], allowPremium: true  },
  { name: 'Amaciador Roupa 1.5L',     category: 'limpeza',    priceRange: [1.50, 4.00], allowPremium: true  },
  { name: 'Detergente Louça 500ml',   category: 'limpeza',    priceRange: [0.60, 1.80], allowPremium: true  },
  { name: 'Pastilhas Máquina Louça 30un', category: 'limpeza',priceRange: [2.50, 6.00], allowPremium: true  },
  { name: 'Lixívia 1L',               category: 'limpeza',    priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Desinfetante Multiusos 500ml', category: 'limpeza',priceRange: [0.90, 2.50], allowPremium: true  },
  { name: 'Esponja de Cozinha 3 un.', category: 'limpeza',    priceRange: [0.50, 1.20], allowPremium: false },
  { name: 'Saco do Lixo 20L 20un.',   category: 'limpeza',    priceRange: [0.60, 1.50], allowPremium: false },
  { name: 'Saco do Lixo 50L 10un.',   category: 'limpeza',    priceRange: [0.70, 1.80], allowPremium: false },
  { name: 'Papel Cozinha 4 rolos',    category: 'limpeza',    priceRange: [1.00, 2.80], allowPremium: false },
  { name: 'Guardanapos 33x33 100un.', category: 'limpeza',    priceRange: [0.60, 1.50], allowPremium: false },
  { name: 'Papel Higiénico 12 rolos', category: 'limpeza',    priceRange: [2.00, 5.00], allowPremium: true  },
  { name: 'Limpa Vidros 500ml',       category: 'limpeza',    priceRange: [0.80, 2.20], allowPremium: true  },
  { name: 'Limpa WC 750ml',           category: 'limpeza',    priceRange: [0.70, 2.00], allowPremium: false },

  // ── HIGIENE ──
  { name: 'Champô Normal 400ml',      category: 'higiene',    priceRange: [1.00, 3.50], allowPremium: true  },
  { name: 'Champô Anticaspa 400ml',   category: 'higiene',    priceRange: [1.20, 4.00], allowPremium: true  },
  { name: 'Gel de Banho 750ml',       category: 'higiene',    priceRange: [1.00, 3.50], allowPremium: true  },
  { name: 'Sabonete Sólido 3 un.',    category: 'higiene',    priceRange: [0.60, 1.80], allowPremium: false },
  { name: 'Creme Mãos 75ml',          category: 'higiene',    priceRange: [0.80, 2.50], allowPremium: true  },
  { name: 'Desodorizante Roll-on 50ml',category:'higiene',    priceRange: [1.00, 3.00], allowPremium: true  },
  { name: 'Desodorizante Spray 150ml',category: 'higiene',    priceRange: [1.20, 3.50], allowPremium: true  },
  { name: 'Pasta Dentes 75ml',        category: 'higiene',    priceRange: [0.60, 2.50], allowPremium: true  },
  { name: 'Escova Dentes Média',      category: 'higiene',    priceRange: [0.50, 2.00], allowPremium: false },
  { name: 'Fio Dental 50m',           category: 'higiene',    priceRange: [0.70, 2.00], allowPremium: false },
  { name: 'Lâmina de Barbear 5un.',   category: 'higiene',    priceRange: [0.80, 3.00], allowPremium: true  },
  { name: 'Penso Rápido 20un.',       category: 'higiene',    priceRange: [0.60, 2.00], allowPremium: false },
  { name: 'Algodão 100g',             category: 'higiene',    priceRange: [0.50, 1.50], allowPremium: false },
  { name: 'Absorventes 16un.',        category: 'higiene',    priceRange: [1.00, 3.00], allowPremium: true  },
  { name: 'Lenços de Papel 10 pack',  category: 'higiene',    priceRange: [1.00, 2.50], allowPremium: false },

  // ── SNACKS ──
  { name: 'Bolachas Maria 400g',      category: 'snacks',     priceRange: [0.50, 1.50], allowPremium: false },
  { name: 'Bolachas Água e Sal 200g', category: 'snacks',     priceRange: [0.60, 1.60], allowPremium: false },
  { name: 'Bolachas Chocolate 200g',  category: 'snacks',     priceRange: [0.80, 2.00], allowPremium: true  },
  { name: 'Bolachas Digestivas 400g', category: 'snacks',     priceRange: [0.70, 1.80], allowPremium: false },
  { name: 'Batatas Fritas Liso 150g', category: 'snacks',     priceRange: [0.80, 2.50], allowPremium: true  },
  { name: 'Batatas Fritas Ondulado 150g', category: 'snacks', priceRange: [0.90, 2.60], allowPremium: true  },
  { name: 'Pipocas Manteiga 100g',    category: 'snacks',     priceRange: [0.70, 2.00], allowPremium: false },
  { name: 'Amendoins Salgados 200g',  category: 'snacks',     priceRange: [0.60, 1.80], allowPremium: false },
  { name: 'Cajus 100g',               category: 'snacks',     priceRange: [1.50, 4.00], allowPremium: true  },
  { name: 'Mix de Frutos Secos 200g', category: 'snacks',     priceRange: [1.20, 3.50], allowPremium: true  },
  { name: 'Chocolate de Leite 100g',  category: 'snacks',     priceRange: [0.60, 3.00], allowPremium: true  },
  { name: 'Chocolate Negro 100g',     category: 'snacks',     priceRange: [0.70, 3.50], allowPremium: true  },
  { name: 'Chocolate Branco 100g',    category: 'snacks',     priceRange: [0.70, 3.00], allowPremium: true  },
  { name: 'Gomas Sortidas 200g',      category: 'snacks',     priceRange: [0.60, 1.80], allowPremium: false },
  { name: 'Cereais Flocos Aveia 500g',category: 'snacks',     priceRange: [1.00, 3.00], allowPremium: true  },
  { name: 'Cereais Milho 375g',       category: 'snacks',     priceRange: [1.00, 2.80], allowPremium: true  },
  { name: 'Barras de Cereais 6un.',   category: 'snacks',     priceRange: [1.20, 3.00], allowPremium: true  },
  { name: 'Croissant Embalado 4un.',  category: 'snacks',     priceRange: [0.80, 2.00], allowPremium: false },
  { name: 'Bolo Mármore 400g',        category: 'snacks',     priceRange: [1.20, 3.00], allowPremium: false },
  { name: 'Donuts 4un.',              category: 'snacks',     priceRange: [1.00, 2.50], allowPremium: false },
];

// ─── UTILITIES ────────────────────────────────────────────────────────────────

function randomBetween(min, max) {
  return min + Math.random() * (max - min);
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

// ─── PRODUCT GENERATOR ────────────────────────────────────────────────────────

function generateProducts(storeName) {
  const storeCfg = STORES[storeName];
  if (!storeCfg) throw new Error(`Unknown store: ${storeName}`);

  const { brands, multipliers, appMarkup } = storeCfg;
  const products = [];
  const seen = new Set();

  for (const base of BASE_PRODUCTS) {
    const tiers = base.allowPremium
      ? ['budget', 'mid', 'premium']
      : ['budget', 'mid'];

    for (const tier of tiers) {
      const tierBrands = brands[tier];
      for (const brand of tierBrands) {
        const key = `${storeName}|${base.name}|${brand}|${tier}`;
        if (seen.has(key)) continue;
        seen.add(key);

        const [min, max] = base.priceRange;
        const basePrice = randomBetween(min, max);
        const priceOriginal = round2(basePrice * multipliers[tier]);
        const priceApp = round2(priceOriginal * appMarkup);

        products.push({
          id: uuid(),
          name: `${brand} ${base.name}`,
          category: base.category,
          store: storeName,
          type: tier === 'budget' ? 'budget' : tier === 'mid' ? 'mid' : 'premium',
          price_original: priceOriginal,
          price_app: priceApp,
          created_at: new Date().toISOString(),
        });
      }
    }
  }

  console.log(`[${storeName}] Generated ${products.length} products`);
  return products;
}

// ─── BATCH INSERT ──────────────────────────────────────────────────────────────

async function seedStore(supabase, storeName) {
  const products = generateProducts(storeName);

  // Delete existing products for this store
  const { error: delErr } = await supabase
    .from('products')
    .delete()
    .eq('store', storeName);

  if (delErr) {
    console.error(`[${storeName}] Delete failed:`, delErr.message);
    return;
  }
  console.log(`[${storeName}] Cleared existing products`);

  // Insert in batches
  let inserted = 0;
  for (let i = 0; i < products.length; i += BATCH_SIZE) {
    const batch = products.slice(i, i + BATCH_SIZE);
    const { error } = await supabase.from('products').insert(batch);
    if (error) {
      console.error(`[${storeName}] Batch insert error (offset ${i}):`, error.message);
    } else {
      inserted += batch.length;
      process.stdout.write(`\r[${storeName}] Inserted ${inserted}/${products.length}...`);
    }
  }
  console.log(`\n[${storeName}] Done. Total inserted: ${inserted}`);
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {
  if (
    SUPABASE_URL.includes('YOUR_PROJECT') ||
    SUPABASE_KEY.includes('YOUR_SERVICE_KEY')
  ) {
    console.error(
      'ERROR: Set SUPABASE_URL and SUPABASE_SERVICE_KEY env vars before running.\n' +
      'Example:\n' +
      '  SUPABASE_URL=https://xxx.supabase.co SUPABASE_SERVICE_KEY=eyJ... node seed_products.js'
    );
    process.exit(1);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

  // Seed all stores (add or remove as needed)
  const storesToSeed = ['continente'];
  // Uncomment to seed more stores:
  // const storesToSeed = ['continente', 'pingo_doce', 'lidl'];

  for (const store of storesToSeed) {
    await seedStore(supabase, store);
  }

  console.log('\nAll done!');
}

main().catch(console.error);
