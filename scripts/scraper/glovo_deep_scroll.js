/**
 * glovo_deep_scroll.js — Sessão Autónoma 2026-05-19
 *
 * Estratégia: scroll deep + intercept tudo (sem clicks). Hipótese: produtos
 * Worten/Leroy/Kiwoko/Zippy carregam lazy à medida que se scroll bem fundo.
 *
 * Se não funcionar, esta sessão fica documentada como BLOCKED para essas
 * 4 lojas. Wells continua funcional (476 produtos).
 */

import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { createClient } from '@supabase/supabase-js';
import { launchBrowser, newPage, sleep } from './lib/browser.js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, { auth: { persistSession: false } });

const STORES = [
  { glovoSlug: 'worten-vivaci-guarda-grd', restaurantId: 'worten-guarda', categoryFallback: 'Electrónica' },
  { glovoSlug: 'leroy-merlin-grd',          restaurantId: 'leroy-merlin-guarda', categoryFallback: 'Bricolage' },
  { glovoSlug: 'kiwoko-grd',                restaurantId: 'kiwoko-guarda', categoryFallback: 'Animais' },
  { glovoSlug: 'zippy-grd',                 restaurantId: 'zippy-guarda', categoryFallback: 'Roupa Criança' },
];

const MARKUP = 1.15;
const outDir = path.join(process.cwd(), 'output');
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

function normalize(s) {
  return (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
}

async function fetchExisting(restaurantId) {
  let all = []; let from = 0;
  while (true) {
    const { data, error } = await supabase.from('products').select('name').eq('restaurant_id', restaurantId).range(from, from + 999);
    if (error || !data || data.length === 0) break;
    all.push(...data); if (data.length < 1000) break; from += 1000;
  }
  return new Set(all.map(r => normalize(r.name)));
}

async function processStore(browser, store) {
  console.log(`\n🏪 ${store.restaurantId} (${store.glovoSlug})`);
  const existing = await fetchExisting(store.restaurantId);
  console.log(`   ${existing.size} produtos já no DB`);

  const { page, context } = await newPage(browser);
  const captured = [];

  page.on('response', async (resp) => {
    const u = resp.url();
    if (resp.status() >= 400) return;
    const ct = resp.headers()['content-type'] || '';
    if (!ct.includes('json')) return;
    if (u.includes('analytics') || u.includes('braze') || u.includes('usercentrics') || u.includes('tracking')) return;
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
            captured.push({ name, price, imageUrl: obj.imageUrl || obj.imageId || obj.photoUrl || obj.image || null });
          }
        }
        for (const v of Object.values(obj)) if (v && typeof v === 'object') walk(v, depth + 1);
      };
      walk(json);
    } catch (e) {}
  });

  const url = `https://glovoapp.com/pt/pt/guarda/${store.glovoSlug}`;
  console.log(`  🌐 ${url}`);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await sleep(4500, 6000);
  } catch (e) { console.warn(`     goto err: ${e.message}`); }

  // Scroll deep — 60 increments slow
  console.log(`  📜 Deep scroll 60×...`);
  for (let i = 0; i < 60; i++) {
    try { await page.evaluate(() => window.scrollBy(0, 800)); } catch (e) { break; }
    await sleep(500, 800);
    if (i % 10 === 9) console.log(`     scroll ${i+1}/60 → captured=${captured.length}`);
  }

  // Scroll back up to trigger any "above the fold" lazy
  for (let i = 0; i < 20; i++) {
    try { await page.evaluate(() => window.scrollBy(0, -1000)); } catch (e) { break; }
    await sleep(400, 600);
  }

  try { await context.close(); } catch (e) {}

  // Dedup intra
  const m = new Map();
  for (const p of captured) {
    const k = normalize(p.name);
    if (!m.has(k)) m.set(k, p);
  }
  const products = [...m.values()];
  console.log(`  ✅ Capturados ${products.length} produtos únicos`);

  if (products.length === 0) return { store: store.restaurantId, inserted: 0, captured: 0 };

  // Save backup
  fs.writeFileSync(
    path.join(outDir, `${store.restaurantId.replace(/-/g, '_')}_glovo_${Date.now()}.json`),
    JSON.stringify(products, null, 2)
  );

  // Dedup vs existing + insert
  const today = new Date().toISOString().slice(0, 10);
  const candidates = products.filter(p => !existing.has(normalize(p.name)));
  const rows = candidates.map(g => ({
    restaurant_id: store.restaurantId,
    name: g.name.trim().slice(0, 250),
    description: null,
    photo_url: g.imageUrl || null,
    price: +(g.price / MARKUP).toFixed(2),
    category: store.categoryFallback,
    category_root: store.categoryFallback,
    taxonomy_section: 'store_other',
    image_source: 'glovo',
    source: 'glovo_guarda',
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
    if (error) console.warn(`   ❌ batch ${i/50+1}: ${error.message.substring(0, 100)}`);
    else { inserted += batch.length; console.log(`   ✅ ${inserted}/${rows.length}`); }
  }

  return { store: store.restaurantId, captured: products.length, inserted, skipped: products.length - candidates.length };
}

async function main() {
  console.log('🎯 Glovo Deep-Scroll Import — 4 lojas\n');
  const browser = await launchBrowser();
  const results = [];
  try {
    for (const s of STORES) {
      try { results.push(await processStore(browser, s)); }
      catch (e) { results.push({ store: s.restaurantId, error: e.message }); console.error(`💥 ${s.restaurantId}: ${e.message}`); }
    }
  } finally { await browser.close(); }

  console.log('\n═══════════════════════════════');
  console.log('📋 RELATÓRIO FINAL');
  console.log('═══════════════════════════════');
  for (const r of results) {
    if (r.error) console.log(`❌ ${r.store}: ${r.error}`);
    else console.log(`✅ ${r.store.padEnd(22)} | captured=${(r.captured+'').padStart(4)} | inserted=${(r.inserted+'').padStart(4)}`);
  }
}

main().catch(e => { console.error('💥', e); process.exit(1); });
