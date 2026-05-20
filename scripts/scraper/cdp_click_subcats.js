/**
 * cdp_click_subcats.js — Sessão Autónoma 2026-05-20
 *
 * Para cada loja: goto landing → encontra TODOS os buttons de sub-cat
 * (excluindo Iniciar sessão / Guarda / Informações taxas) → click cada um
 * sequencialmente → wait 2-3s → intercept apanha API products → próxima.
 *
 * Walker BROAD: aceita name|title|productName|displayName + price|amount|priceInfo.
 *
 * Per loja: scrape → import (Glovo÷1.15) → log.
 */

import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { persistSession: false } });

const STORES = [
  { slug: 'worten-vivaci-guarda-grd', restaurantId: 'worten-guarda',       category: 'Electrónica',     taxonomy: 'store_electronics' },
  { slug: 'leroy-merlin-grd',          restaurantId: 'leroy-merlin-guarda', category: 'Bricolage',       taxonomy: 'store_diy' },
  { slug: 'kiwoko-grd',                restaurantId: 'kiwoko-guarda',       category: 'Animais',         taxonomy: 'store_pets' },
  { slug: 'zippy-grd',                 restaurantId: 'zippy-guarda',        category: 'Roupa Criança',   taxonomy: 'store_kids' },
];

const ONLY = process.argv.find(a => a.startsWith('--only='))?.split('=')[1]?.split(',') || null;
const MARKUP = 1.15;
const outDir = path.join(process.cwd(), 'output');
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

const EXCLUDE_BUTTONS = ['Guarda', 'Iniciar sessão', 'Informações sobre as taxas', 'Conformidade', 'Política de Trocas e Devoluções', 'Voltar', 'Pesquisar'];

const sleep = (a, b) => new Promise(r => setTimeout(r, Math.floor(Math.random() * (b - a) + a)));

function normalize(s) {
  return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
}

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

function setupIntercept(page, captured) {
  page.on('response', async (resp) => {
    if (resp.status() >= 400) return;
    const url = resp.url();
    if (/analytics|tracking|braze|usercentrics|sentry|datadog|googletagmanager/i.test(url)) return;
    const ct = resp.headers()['content-type'] || '';
    if (!ct.includes('json')) return;
    try {
      const json = await resp.json();
      const walk = (obj, depth = 0) => {
        if (!obj || depth > 14) return;
        if (Array.isArray(obj)) return obj.forEach(o => walk(o, depth + 1));
        if (typeof obj !== 'object') return;
        const name = obj.name || obj.productName || obj.title || obj.itemName || obj.displayName;
        let priceRaw = obj.price ?? obj.amount ?? obj.priceCents ?? obj.unitPrice ?? obj.totalPrice ?? obj.finalPrice ?? obj.salePrice;
        if (priceRaw == null && obj.priceInfo) priceRaw = obj.priceInfo.amount ?? obj.priceInfo.price ?? obj.priceInfo.displayText;
        if (priceRaw == null && obj.formattedPrice) priceRaw = obj.formattedPrice;
        if (priceRaw == null && obj.displayPrice) priceRaw = obj.displayPrice;
        if (name && priceRaw != null && typeof name === 'string' && name.length > 2 && name.length < 250) {
          let price;
          if (typeof priceRaw === 'number') price = priceRaw > 1000 ? priceRaw / 100 : priceRaw;
          else { const m = String(priceRaw).match(/(\d+[.,]\d{2})/); price = m ? parseFloat(m[1].replace(',', '.')) : NaN; }
          if (price > 0 && !isNaN(price) && price < 10000) {
            // Skip obvious non-products (store names, fees displayText)
            if (!/^\s*(burger king|mcdonald|kfc|pizza hut|continente|wells|auchan|lidl|h3|mercadona|loja\s|store\s|delivery|surcharge)/i.test(name)) {
              const img = obj.imageUrl || obj.imageId || obj.photoUrl || obj.image || obj.thumbnailUrl || null;
              captured.push({ name, price, imageUrl: typeof img === 'string' ? img : (img?.url || img?.contentUrl || null) });
            }
          }
        }
        for (const v of Object.values(obj)) if (v && typeof v === 'object') walk(v, depth + 1);
      };
      walk(json);
    } catch (e) {}
  });
}

async function clickAllSubcats(page, store) {
  // Get list of unique sub-cat button texts (filtered)
  const subcatTexts = await page.evaluate((exclude) => {
    const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
    const set = new Set();
    for (const b of btns) {
      const t = (b.textContent || '').trim();
      if (t && t.length > 2 && t.length < 80 && !exclude.includes(t) && !/^\d/.test(t) && !/grátis|gratis|prime|promo|sobre|0,/i.test(t)) {
        set.add(t);
      }
    }
    return [...set];
  }, EXCLUDE_BUTTONS);
  console.log(`     ${subcatTexts.length} sub-cat buttons únicos`);

  for (let i = 0; i < subcatTexts.length; i++) {
    const txt = subcatTexts[i];
    try {
      const clicked = await page.evaluate((needle) => {
        const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
        const target = btns.find(b => (b.textContent || '').trim() === needle);
        if (target) {
          target.scrollIntoView({ block: 'center', behavior: 'instant' });
          target.click();
          return true;
        }
        return false;
      }, txt);
      if (clicked) {
        await sleep(1200, 1800);
        // Scroll within potential opened panel
        await page.evaluate(() => window.scrollBy(0, 800)).catch(() => {});
        await sleep(500, 800);
        // Try clicking "Mostrar tudo" if present
        try {
          const mostrar = await page.evaluate(() => {
            const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
            const target = btns.find(b => /mostrar tudo|ver tudo|see all|show all/i.test(b.textContent || ''));
            if (target) { target.scrollIntoView({ block: 'center' }); target.click(); return true; }
            return false;
          });
          if (mostrar) {
            await sleep(2500, 3500);
            // Scroll deep
            for (let j = 0; j < 8; j++) {
              try { await page.evaluate(() => window.scrollBy(0, 1000)); } catch (e) {}
              await sleep(400, 600);
            }
            // Go back
            try { await page.goBack({ waitUntil: 'domcontentloaded', timeout: 10000 }); await sleep(1200, 1800); } catch (e) {}
          }
        } catch (e) {}
      }
    } catch (e) {
      console.warn(`     subcat err: ${e.message.substring(0, 80)}`);
    }
    if ((i + 1) % 5 === 0) console.log(`     clicked ${i+1}/${subcatTexts.length}`);
  }
}

async function scrapeStore(page, store) {
  const captured = [];
  setupIntercept(page, captured);

  const url = `https://glovoapp.com/pt/pt/guarda/stores/${store.slug}`;
  console.log(`  goto ${url}`);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await sleep(4000, 5500);
  } catch (e) { console.warn(`  goto: ${e.message.substring(0, 80)}`); }

  // dismiss cookies
  try {
    await page.evaluate(() => {
      const b = Array.from(document.querySelectorAll('button')).find(x => /aceit|accept|ok/i.test(x.textContent || ''));
      if (b) b.click();
    });
    await sleep(1500, 2000);
  } catch (e) {}

  // Initial scroll to render everything
  for (let i = 0; i < 10; i++) {
    try { await page.evaluate(() => window.scrollBy(0, 800)); } catch (e) { break; }
    await sleep(400, 600);
  }

  console.log(`  starting sub-cat clicks…`);
  await clickAllSubcats(page, store);

  console.log(`  total captured (raw): ${captured.length}`);
  // Dedup intra
  const m = new Map();
  for (const p of captured) {
    const k = normalize(p.name);
    if (!m.has(k)) m.set(k, p);
  }
  return [...m.values()];
}

async function importProducts(store, products) {
  if (products.length === 0) return { inserted: 0, skipped: 0, captured: 0 };

  fs.writeFileSync(
    path.join(outDir, `${store.restaurantId.replace(/-/g, '_')}_subcats_${Date.now()}.json`),
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
    category: store.category, category_root: store.category, taxonomy_section: store.taxonomy,
    image_source: 'glovo', source: 'glovo_guarda',
    unit: null, is_available: true, is_popular: false, is_on_sale: false, discount_price: null,
    needs_photo: !g.imageUrl, needs_review: false, last_updated: today,
  }));

  let inserted = 0;
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50);
    const { error } = await supabase.from('products').insert(batch);
    if (error) console.warn(`  ❌ batch ${i/50+1}: ${error.message.substring(0, 120)}`);
    else { inserted += batch.length; console.log(`  ✅ inserted ${inserted}/${rows.length}`); }
  }
  return { inserted, skipped: products.length - candidates.length, captured: products.length };
}

async function main() {
  console.log('🎯 CDP Click-Subcats Import — Sessão 2026-05-20\n');
  const browser = await chromium.connectOverCDP('http://localhost:9222');
  const ctx = browser.contexts()[0];

  const filtered = ONLY ? STORES.filter(s => ONLY.some(o => s.restaurantId.includes(o))) : STORES;

  const results = [];
  for (const store of filtered) {
    console.log(`🏪 ${store.restaurantId} (${store.slug})`);
    const page = await ctx.newPage();
    try {
      const products = await scrapeStore(page, store);
      console.log(`   unique captured: ${products.length}`);
      const r = await importProducts(store, products);
      results.push({ store: store.restaurantId, ...r });
    } catch (e) {
      console.error(`💥 ${store.restaurantId}: ${e.message}`);
      results.push({ store: store.restaurantId, error: e.message });
    }
    try { await page.close(); } catch (e) {}
  }
  try { await browser.close(); } catch (e) {}

  console.log('\n═══════════════════════════════');
  for (const r of results) {
    if (r.error) console.log(`❌ ${r.store}: ${r.error.substring(0, 120)}`);
    else console.log(`✅ ${r.store.padEnd(22)} | captured=${(r.captured ?? 0).toString().padStart(4)} | inserted=${(r.inserted ?? 0).toString().padStart(4)} | dups=${r.skipped ?? 0}`);
  }
}

main().catch(e => { console.error('💥', e); process.exit(1); });
