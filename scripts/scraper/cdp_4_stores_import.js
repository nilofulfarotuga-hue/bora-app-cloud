/**
 * cdp_4_stores_import.js — Sessão Autónoma 2026-05-19
 *
 * Connecta ao Chrome do Danilo via CDP (http://localhost:9222), abre as 4 lojas
 * Glovo Guarda em tabs, confirma endereço, extrai todos os produtos por intercept
 * + DOM, aplica regra de preço (Glovo÷1.15 — fallback global), INSERT batch.
 *
 * Per loja: scrape → import → log. Commit+push é feito fora deste script.
 */

import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  { auth: { persistSession: false } }
);

const STORES = [
  { glovoSlug: 'worten-vivaci-guarda-grd', restaurantId: 'worten-guarda',       categoryFallback: 'Electrónica',       taxonomy: 'store_electronics' },
  { glovoSlug: 'leroy-merlin-grd',          restaurantId: 'leroy-merlin-guarda', categoryFallback: 'Bricolage',         taxonomy: 'store_diy' },
  { glovoSlug: 'kiwoko-grd',                restaurantId: 'kiwoko-guarda',       categoryFallback: 'Animais',           taxonomy: 'store_pets' },
  { glovoSlug: 'zippy-grd',                 restaurantId: 'zippy-guarda',        categoryFallback: 'Roupa Criança',     taxonomy: 'store_kids' },
];

// Only process stores passed via CLI args (--only=worten,leroy,kiwoko,zippy)
const onlyArg = process.argv.find(a => a.startsWith('--only='))?.split('=')[1];
const ONLY_FILTER = onlyArg ? onlyArg.split(',') : null;

const MARKUP = 1.15;
const SOURCE = 'glovo_guarda';
const CDP_URL = 'http://localhost:9222';

const outDir = path.join(process.cwd(), 'output');
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

function normalize(s) {
  return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
}

const sleep = (min, max) => new Promise(r => setTimeout(r, Math.floor(Math.random() * (max - min) + min)));

async function fetchExisting(restaurantId) {
  let all = []; let from = 0;
  while (true) {
    const { data, error } = await supabase.from('products').select('name')
      .eq('restaurant_id', restaurantId).range(from, from + 999);
    if (error || !data || data.length === 0) break;
    all.push(...data);
    if (data.length < 1000) break;
    from += 1000;
  }
  return new Set(all.map(r => normalize(r.name)));
}

async function confirmAddress(page) {
  // Glovo address banner: clicar "Continuar com este endereço" / "Use this address"
  try {
    const clicked = await page.evaluate(() => {
      const btns = Array.from(document.querySelectorAll('button, [role="button"], a'));
      const candidates = btns.filter(b => /continuar|continuar com|use this|usar este|guardar|save|aceitar|confirmar/i.test(b.textContent || ''));
      const addr = btns.find(b => /endere[çc]o|address|morada/i.test(b.textContent || ''));
      const target = candidates[0] || addr;
      if (target) { target.click(); return target.textContent?.trim() || 'clicked'; }
      return null;
    });
    if (clicked) console.log(`       confirm address: "${clicked.substring(0, 40)}"`);
  } catch (e) {}
}

async function dismissCookies(page) {
  try {
    await page.evaluate(() => {
      const btns = Array.from(document.querySelectorAll('button'));
      const b = btns.find(x => /aceit|accept|ok|i agree|concordo/i.test(x.textContent || ''));
      if (b) b.click();
    });
    await sleep(800, 1200);
  } catch (e) {}
}

async function scrapeStore(page, store) {
  const captured = [];
  const apiUrls = new Set();

  const onResp = async (resp) => {
    const url = resp.url();
    apiUrls.add(url.split('?')[0]);
    if (resp.status() >= 400) return;
    const ct = resp.headers()['content-type'] || '';
    if (!ct.includes('json')) return;
    if (/analytics|tracking|braze|usercentrics|google|datadog|sentry/i.test(url)) return;
    try {
      const json = await resp.json();
      const walk = (obj, depth = 0) => {
        if (!obj || depth > 12) return;
        if (Array.isArray(obj)) return obj.forEach(o => walk(o, depth + 1));
        if (typeof obj !== 'object') return;
        const name = obj.name || obj.productName || obj.title;
        const priceRaw = obj.price ?? obj.priceInfo?.amount ?? obj.formattedPrice ?? obj.priceCents ?? obj.unitPrice ?? obj.totalPrice;
        if (name && priceRaw != null && typeof name === 'string' && name.length > 2 && name.length < 250) {
          let price;
          if (typeof priceRaw === 'number') price = priceRaw > 1000 ? priceRaw / 100 : priceRaw;
          else { const m = String(priceRaw).match(/(\d+[.,]\d{2})/); price = m ? parseFloat(m[1].replace(',', '.')) : NaN; }
          if (price > 0 && !isNaN(price)) {
            const img = obj.imageUrl || obj.imageId || obj.photoUrl || obj.image || null;
            captured.push({ name, price, imageUrl: typeof img === 'string' ? img : (img?.url || img?.contentUrl) });
          }
        }
        for (const v of Object.values(obj)) if (v && typeof v === 'object') walk(v, depth + 1);
      };
      walk(json);
    } catch (e) {}
  };

  page.on('response', onResp);

  const url = `https://glovoapp.com/pt/pt/guarda/stores/${store.glovoSlug}`;
  console.log(`     goto ${url}`);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await sleep(4000, 5500);
  } catch (e) { console.warn(`     goto: ${e.message}`); }

  await dismissCookies(page);
  await confirmAddress(page);
  await sleep(2500, 3500);

  // Re-goto (more stable than reload — keeps intercept attached)
  try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 }); } catch (e) {}
  await sleep(4000, 5500);

  // Deep scroll to trigger lazy (wrapped — safe if navigation happens)
  console.log(`     scroll deep…`);
  for (let i = 0; i < 35; i++) {
    try { await page.evaluate(() => window.scrollBy(0, 700)); }
    catch (e) {
      // If context destroyed, navigate back to store URL and continue
      console.warn(`     scroll ${i}: context lost, recovering…`);
      try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 }); await sleep(2000, 3000); } catch (e2) { break; }
    }
    await sleep(500, 800);
  }

  // Find sub-category clickable headers (h3/h4 with categoryId data attrs OR text headings)
  let subCatTexts = [];
  try { subCatTexts = await page.evaluate(() => {
    const out = new Set();
    // Strategy 1: data-test attributes
    document.querySelectorAll('[data-test*="collection-group" i], [data-test*="category" i], [data-test*="section-title" i], [data-test*="header" i]')
      .forEach(el => { const t = (el.textContent || '').trim(); if (t.length > 2 && t.length < 60) out.add(t); });
    // Strategy 2: clickable h2/h3 inside main store layout
    document.querySelectorAll('h2, h3, h4').forEach(el => {
      const t = (el.textContent || '').trim();
      if (t.length > 2 && t.length < 60 && !/sobre|info|delivery|entrega|hor[áa]rio/i.test(t)) out.add(t);
    });
    return [...out].slice(0, 40);
  }); } catch (e) { console.warn(`     subcat scan err: ${e.message.substring(0, 80)}`); }
  console.log(`     ${subCatTexts.length} sub-cat headers candidatas`);

  // Sub-cat clicks REMOVED — too risky (cause navigation context destruction).
  // Rely on intercept during scroll + DOM extraction.

  // Final scroll deeper
  for (let i = 0; i < 20; i++) {
    try { await page.evaluate(() => window.scrollBy(0, 1200)); }
    catch (e) {
      try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 }); await sleep(3000, 4000); } catch (e2) { break; }
    }
    await sleep(450, 700);
  }

  // Also extract from DOM as fallback (Glovo product cards)
  let domProducts = [];
  try { domProducts = await page.evaluate(() => {
    const out = [];
    const cards = document.querySelectorAll('[data-test*="product" i], [class*="product-row" i], [class*="ProductRow" i], [class*="StoreProduct" i], [class*="product-card" i]');
    for (const card of cards) {
      const nameEl = card.querySelector('[class*="name" i], [class*="title" i], [data-test*="title" i], h3, h4, span');
      const priceEl = card.querySelector('[class*="price" i], [data-test*="price" i]');
      const imgEl = card.querySelector('img');
      const name = (nameEl?.textContent || '').trim().replace(/\s+/g, ' ');
      const priceText = (priceEl?.textContent || '').trim();
      const m = priceText.match(/(\d+[.,]\d{2})/);
      const price = m ? parseFloat(m[1].replace(',', '.')) : null;
      if (name && price && price > 0 && name.length < 250) {
        out.push({ name, price, imageUrl: imgEl?.src || imgEl?.getAttribute('data-src') || null });
      }
    }
    return out;
  }); } catch (e) { console.warn(`     dom scan err: ${e.message.substring(0, 80)}`); }
  console.log(`     intercept=${captured.length}, dom=${domProducts.length}, api_urls=${apiUrls.size}`);
  captured.push(...domProducts);

  page.off('response', onResp);

  // Dedup intra
  const m = new Map();
  for (const p of captured) {
    const k = normalize(p.name);
    if (!m.has(k)) m.set(k, p);
  }
  return [...m.values()];
}

async function importProducts(store, products) {
  if (products.length === 0) return { inserted: 0, skipped: 0 };

  fs.writeFileSync(
    path.join(outDir, `${store.restaurantId.replace(/-/g, '_')}_glovo_cdp_${Date.now()}.json`),
    JSON.stringify(products, null, 2)
  );

  const existing = await fetchExisting(store.restaurantId);
  const today = new Date().toISOString().slice(0, 10);
  const candidates = products.filter(p => !existing.has(normalize(p.name)));

  const rows = candidates.map(g => ({
    restaurant_id: store.restaurantId,
    name: g.name.trim().slice(0, 250),
    description: null,
    photo_url: g.imageUrl && String(g.imageUrl).startsWith('http') ? g.imageUrl : null,
    price: +(g.price / MARKUP).toFixed(2),
    category: store.categoryFallback,
    category_root: store.categoryFallback,
    taxonomy_section: store.taxonomy,
    image_source: 'glovo',
    source: SOURCE,
    unit: null,
    is_available: true,
    is_popular: false,
    is_on_sale: false,
    discount_price: null,
    needs_photo: !g.imageUrl,
    needs_review: false,
    last_updated: today,
  }));

  let inserted = 0;
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50);
    const { error } = await supabase.from('products').insert(batch);
    if (error) console.warn(`     ❌ batch ${i/50+1}: ${error.message.substring(0, 120)}`);
    else { inserted += batch.length; console.log(`     ✅ inserted ${inserted}/${rows.length}`); }
  }
  return { inserted, skipped: products.length - candidates.length, captured: products.length };
}

async function main() {
  console.log('🎯 CDP 4-Stores Import — Sessão autónoma 2026-05-19\n');
  console.log(`   Connecting CDP ${CDP_URL}…`);
  const browser = await chromium.connectOverCDP(CDP_URL);
  const ctx = browser.contexts()[0] || await browser.newContext();
  console.log(`   Context found · existing pages: ${ctx.pages().length}\n`);

  const results = [];
  const filtered = ONLY_FILTER
    ? STORES.filter(s => ONLY_FILTER.some(o => s.restaurantId.includes(o)))
    : STORES;
  console.log(`   Processing ${filtered.length} stores: ${filtered.map(s => s.restaurantId).join(', ')}\n`);
  for (const store of filtered) {
    console.log(`🏪 ${store.restaurantId} (${store.glovoSlug})`);
    let page;
    try {
      page = await ctx.newPage();
      const products = await scrapeStore(page, store);
      console.log(`   captured ${products.length} unique products`);
      const r = await importProducts(store, products);
      results.push({ store: store.restaurantId, ...r });
      await page.close().catch(() => {});
    } catch (e) {
      console.error(`💥 ${store.restaurantId}: ${e.message}`);
      results.push({ store: store.restaurantId, error: e.message });
      if (page) try { await page.close(); } catch (e2) {}
    }
  }

  // Disconnect (não fechar Chrome — é do Danilo)
  try { await browser.close(); } catch (e) {}

  console.log('\n═══════════════════════════════');
  console.log('📋 RELATÓRIO FINAL');
  console.log('═══════════════════════════════');
  for (const r of results) {
    if (r.error) console.log(`❌ ${r.store}: ${r.error}`);
    else console.log(`✅ ${r.store.padEnd(22)} | captured=${(r.captured ?? 0).toString().padStart(4)} | inserted=${(r.inserted ?? 0).toString().padStart(4)} | dups=${r.skipped ?? 0}`);
  }
}

main().catch(e => { console.error('💥', e); process.exit(1); });
