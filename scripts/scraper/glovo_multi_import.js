/**
 * glovo_multi_import.js — Sessão Autónoma 2026-05-19
 *
 * Importa catálogo de várias lojas Glovo Guarda directamente para Bora DB
 * aplicando a NOVA regra global (business_rules §27.2.1):
 *   - Produtos + imagens: Glovo Guarda (primário)
 *   - Preço: ÷ 1.15 (fallback global — sistema aplica +15% em runtime)
 *   - Dedup obrigatório por nome normalizado
 *   - NUNCA produto sem preço → não importar
 *
 * Lojas (sequencial, bloqueante):
 *   1. Worten      → worten-guarda      / store        / electrónica
 *   2. Leroy Merlin → leroy-merlin-guarda / store      / bricolage
 *   3. Kiwoko      → kiwoko-guarda      / store        / animais
 *   4. Zippy       → zippy-guarda       / store        / roupa criança
 *
 * Glovo slugs reais (descobertos via discovery v2 2026-05-19):
 *   - Worten: worten-vivaci-guarda-grd
 *   - Leroy:  leroy-merlin-grd
 *   - Kiwoko: kiwoko-grd
 *   - Zippy:  zippy-grd
 */

import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { createClient } from '@supabase/supabase-js';
import { launchBrowser, newPage, sleep } from './lib/browser.js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  { auth: { persistSession: false } }
);

const STORES = [
  {
    glovoSlug: 'worten-vivaci-guarda-grd',
    restaurantId: 'worten-guarda',
    categoryFallback: 'Electrónica',
    taxonomyByKeyword: {
      tv: 'store_tv', televis: 'store_tv',
      computador: 'store_computers', portatil: 'store_computers', laptop: 'store_computers',
      telemovel: 'store_phones', smartphone: 'store_phones', tablet: 'store_phones',
      gaming: 'store_gaming', console: 'store_gaming', xbox: 'store_gaming', playstation: 'store_gaming',
      frigorif: 'store_appliances', fogao: 'store_appliances', forno: 'store_appliances',
      maquina: 'store_appliances', aspirador: 'store_appliances', microondas: 'store_appliances',
      cabo: 'store_accessories', carregador: 'store_accessories',
    },
  },
  {
    glovoSlug: 'leroy-merlin-grd',
    restaurantId: 'leroy-merlin-guarda',
    categoryFallback: 'Bricolage',
    taxonomyByKeyword: {
      ferramenta: 'store_tools', berbequim: 'store_tools', martelo: 'store_tools', alicate: 'store_tools',
      tinta: 'store_paint', verniz: 'store_paint', pincel: 'store_paint',
      jardim: 'store_garden', planta: 'store_garden', vaso: 'store_garden',
      banho: 'store_bath', sanit: 'store_bath', torneira: 'store_bath', chuveiro: 'store_bath',
      eletric: 'store_electrical', cabo: 'store_electrical', lampada: 'store_electrical',
      decora: 'store_decor', tapete: 'store_decor', cortinado: 'store_decor',
    },
  },
  {
    glovoSlug: 'kiwoko-grd',
    restaurantId: 'kiwoko-guarda',
    categoryFallback: 'Animais',
    taxonomyByKeyword: {
      cao: 'store_dog', cachorro: 'store_dog', dog: 'store_dog',
      gato: 'store_cat', cat: 'store_cat',
      passaro: 'store_bird', ave: 'store_bird',
      peixe: 'store_fish', aquario: 'store_fish',
      roedor: 'store_rodent', hamster: 'store_rodent', coelho: 'store_rodent',
      reptil: 'store_reptile',
      racao: 'store_food', alimento: 'store_food',
      brinquedo: 'store_toys',
      higien: 'store_pet_hygiene',
    },
  },
  {
    glovoSlug: 'zippy-grd',
    restaurantId: 'zippy-guarda',
    categoryFallback: 'Roupa Criança',
    taxonomyByKeyword: {
      bebe: 'store_baby',
      menino: 'store_boy', boy: 'store_boy',
      menina: 'store_girl', girl: 'store_girl',
      calcad: 'store_shoes', sapato: 'store_shoes',
      acessor: 'store_accessories',
    },
  },
];

const MARKUP = 1.15;
const SOURCE_TAG = 'glovo_guarda';

function normalize(s) {
  return (s || '')
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

function pickTaxonomy(name, map, fallback) {
  const n = normalize(name);
  for (const [k, v] of Object.entries(map)) if (n.includes(k)) return v;
  return fallback;
}

async function fetchExistingNames(restaurantId) {
  let all = [];
  let from = 0;
  const PAGE = 1000;
  while (true) {
    const { data, error } = await supabase
      .from('products').select('name')
      .eq('restaurant_id', restaurantId)
      .range(from, from + PAGE - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    all.push(...data);
    if (data.length < PAGE) break;
    from += PAGE;
  }
  return new Set(all.map(r => normalize(r.name)));
}

async function scrapeGlovoStore(browser, slug) {
  const url = `https://glovoapp.com/pt/pt/guarda/${slug}`;
  const { page, context } = await newPage(browser);
  const captured = [];

  page.on('response', async (resp) => {
    const u = resp.url();
    if (!u.match(/api\.glovoapp\.com|glovoapp\.com\/api|content\.glovoapp/i)) return;
    if (resp.status() >= 400) return;
    const ct = resp.headers()['content-type'] || '';
    if (!ct.includes('json')) return;
    try {
      const json = await resp.json();
      const walk = (obj, depth = 0) => {
        if (!obj || depth > 10) return;
        if (Array.isArray(obj)) return obj.forEach(o => walk(o, depth + 1));
        if (typeof obj !== 'object') return;
        const name = obj.name || obj.productName;
        const priceRaw = obj.price ?? obj.priceInfo?.amount ?? obj.formattedPrice ?? obj.priceCents ?? obj.unitPrice;
        if (name && priceRaw != null && typeof name === 'string' && name.length > 2 && name.length < 250) {
          let price;
          if (typeof priceRaw === 'number') price = priceRaw > 1000 ? priceRaw / 100 : priceRaw;
          else { const m = String(priceRaw).match(/(\d+[.,]\d{2})/); price = m ? parseFloat(m[1].replace(',', '.')) : NaN; }
          if (price > 0 && !isNaN(price)) {
            captured.push({ name, price, imageUrl: obj.imageUrl || obj.imageId || obj.photoUrl || obj.image || null });
          }
        }
        for (const v of Object.values(obj)) if (v && typeof v === 'object') walk(v, depth + 1);
      };
      walk(json);
    } catch (e) {}
  });

  console.log(`  🌐 ${url}`);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await sleep(4000, 5500);
  } catch (e) { console.warn(`     goto: ${e.message}`); }

  // Dismiss cookie banner
  try {
    await page.evaluate(() => {
      const btns = Array.from(document.querySelectorAll('button'));
      const b = btns.find(x => /aceit|accept|ok|fechar/i.test(x.textContent));
      if (b) b.click();
    });
    await sleep(1500, 2000);
  } catch (e) {}

  // Strategy: extract all sub-category URLs from the store landing
  // (Glovo store URLs include /c/<slug>_<id> for sub-categories)
  const subUrls = await page.evaluate((storeSlug) => {
    const set = new Set();
    const anchors = Array.from(document.querySelectorAll('a[href]'));
    for (const a of anchors) {
      const href = a.getAttribute('href') || '';
      // Sub-category within this store
      if (href.includes(`/${storeSlug}/`) || href.includes(`?collection`) || href.includes(`?node`) || href.includes(`?section`) || href.match(new RegExp(`${storeSlug}/c/`))) {
        try {
          const u = new URL(href, location.origin);
          if (u.pathname.includes(storeSlug) && u.toString() !== location.href) set.add(u.toString());
        } catch (e) {}
      }
    }
    return [...set].slice(0, 30);
  }, slug);
  console.log(`     ${subUrls.length} sub-URLs discovered`);

  // Scroll initial page first
  for (let i = 0; i < 8; i++) {
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sleep(800, 1100);
  }

  // Visit each sub-URL (these usually have actual product cards)
  for (let i = 0; i < Math.min(subUrls.length, 20); i++) {
    const sub = subUrls[i];
    try {
      console.log(`     [${i+1}/${Math.min(subUrls.length, 20)}] ${sub.substring(0, 90)}`);
      await page.goto(sub, { waitUntil: 'domcontentloaded', timeout: 45000 });
      await sleep(2200, 3200);
      // Scroll within sub-page to trigger lazy loads
      for (let j = 0; j < 5; j++) {
        await page.evaluate(() => window.scrollBy(0, 1500));
        await sleep(700, 1000);
      }
    } catch (e) { console.warn(`     sub goto err: ${e.message.substring(0, 80)}`); }
  }

  await context.close();
  // Dedup intra
  const m = new Map();
  for (const p of captured) {
    const k = normalize(p.name);
    if (!m.has(k)) m.set(k, p);
  }
  return [...m.values()];
}

async function processStore(browser, store) {
  console.log(`\n🏪 ${store.restaurantId} (Glovo: ${store.glovoSlug})`);
  const existing = await fetchExistingNames(store.restaurantId);
  console.log(`   ${existing.size} produtos já no DB`);

  const glovoProducts = await scrapeGlovoStore(browser, store.glovoSlug);
  console.log(`   ${glovoProducts.length} produtos capturados do Glovo`);

  if (glovoProducts.length === 0) return { store: store.restaurantId, inserted: 0, skipped: 0, total_glovo: 0 };

  // Save backup
  const outDir = path.join(process.cwd(), 'output');
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(
    path.join(outDir, `${store.restaurantId.replace(/-/g, '_')}_glovo_${Date.now()}.json`),
    JSON.stringify(glovoProducts, null, 2)
  );

  // Dedup vs existing
  const today = new Date().toISOString().slice(0, 10);
  const candidates = glovoProducts.filter(g => !existing.has(normalize(g.name)));
  console.log(`   ${candidates.length} novos (${glovoProducts.length - candidates.length} duplicados)`);

  if (candidates.length === 0) return { store: store.restaurantId, inserted: 0, skipped: glovoProducts.length, total_glovo: glovoProducts.length };

  const rows = candidates.map(g => {
    const taxonomy = pickTaxonomy(g.name, store.taxonomyByKeyword, store.categoryFallback.toLowerCase().replace(/\s+/g, '_'));
    return {
      restaurant_id: store.restaurantId,
      name: g.name.trim().slice(0, 250),
      description: null,
      photo_url: g.imageUrl || null,
      price: +(g.price / MARKUP).toFixed(2),
      category: store.categoryFallback,
      category_root: store.categoryFallback,
      taxonomy_section: taxonomy,
      image_source: 'glovo',
      source: SOURCE_TAG,
      unit: null,
      is_available: true,
      is_popular: false,
      is_on_sale: false,
      discount_price: null,
      needs_photo: !g.imageUrl,
      needs_review: false,
      last_updated: today,
    };
  });

  let inserted = 0;
  const BATCH = 50;
  for (let i = 0; i < rows.length; i += BATCH) {
    const batch = rows.slice(i, i + BATCH);
    const { error } = await supabase.from('products').insert(batch);
    if (error) console.warn(`   ❌ batch ${i / BATCH + 1}: ${error.message}`);
    else { inserted += batch.length; console.log(`   ✅ ${inserted}/${rows.length}`); }
  }
  return { store: store.restaurantId, inserted, skipped: glovoProducts.length - candidates.length, total_glovo: glovoProducts.length };
}

async function main() {
  console.log('🎯 Glovo Multi-Import — Sessão autónoma 2026-05-19');
  console.log(`   ${STORES.length} lojas em sequência (NUNCA produto sem preço · ÷ ${MARKUP} markup)\n`);

  const browser = await launchBrowser();
  const results = [];
  try {
    for (const store of STORES) {
      try {
        const r = await processStore(browser, store);
        results.push(r);
      } catch (e) {
        console.error(`💥 ${store.restaurantId} falhou: ${e.message}`);
        results.push({ store: store.restaurantId, error: e.message });
      }
    }
  } finally {
    await browser.close();
  }

  console.log('\n═══════════════════════════════');
  console.log('📋 RELATÓRIO FINAL');
  console.log('═══════════════════════════════');
  for (const r of results) {
    if (r.error) console.log(`❌ ${r.store}: ERR ${r.error}`);
    else console.log(`✅ ${r.store.padEnd(22)} | Glovo: ${(r.total_glovo + '').padStart(4)} | Inseridos: ${(r.inserted + '').padStart(4)} | Dups: ${r.skipped}`);
  }
  console.log('═══════════════════════════════');
}

main().catch(err => { console.error('💥', err); process.exit(1); });
