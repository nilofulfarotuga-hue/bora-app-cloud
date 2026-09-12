/**
 * cdp_deep_subcats.js — Sessão Autónoma 2026-05-20
 *
 * Para cada loja:
 *   1. Goto Glovo
 *   2. Activa entrega agendada (schedule delivery) — vê produtos mesmo fechada
 *   3. Para cada sub-cat button: click → scroll até FUNDO ABSOLUTO
 *      (loop até 20 scrolls consecutivos sem novos produtos no intercept)
 *   4. Per-sub-cat: log count antes/depois
 *   5. INSERT batch, dedup contra DB
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

const EXCLUDE_BUTTONS = ['Guarda', 'Iniciar sessão', 'Informações sobre as taxas', 'Conformidade', 'Política de Trocas e Devoluções', 'Voltar', 'Pesquisar', 'Promoções', 'Promoção', 'Descontos', 'Promo'];

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

async function tryScheduleDelivery(page) {
  // Try clicking schedule delivery button
  try {
    const found = await page.evaluate(() => {
      const all = Array.from(document.querySelectorAll('button, [role="button"], a, [class*="schedule" i], [data-test*="schedule" i]'));
      const target = all.find(c => /agendar|schedule|programar.*entrega|delivery.*later|pré-encomenda/i.test(c.textContent || '')) || all.find(c => /agendar|schedule/i.test(c.getAttribute('data-test') || '')) || all.find(c => /schedule/i.test(c.className || ''));
      if (target) { target.scrollIntoView({ block: 'center' }); target.click(); return (target.textContent || '').trim().substring(0, 60); }
      return null;
    });
    if (found) {
      console.log(`     ⏰ schedule clicked: "${found}"`);
      await sleep(2000, 3000);
      // Pick a future slot
      const slot = await page.evaluate(() => {
        const all = Array.from(document.querySelectorAll('button, [role="button"], li, [class*="slot" i]'));
        const future = all.find(b => /^\d{1,2}:\d{2}/.test((b.textContent || '').trim())) ||
                       all.find(b => /amanhã|tomorrow/i.test(b.textContent || ''));
        if (future) { future.scrollIntoView({ block: 'center' }); future.click(); return (future.textContent || '').trim().substring(0, 40); }
        return null;
      });
      if (slot) console.log(`     ⏰ slot clicked: "${slot}"`);
      await sleep(1500, 2500);
      // Confirm
      const confirm = await page.evaluate(() => {
        const all = Array.from(document.querySelectorAll('button, [role="button"]'));
        const btn = all.find(b => /confirmar|confirm|aplicar|apply|guardar|save/i.test(b.textContent || ''));
        if (btn) { btn.click(); return (btn.textContent || '').trim(); }
        return null;
      });
      if (confirm) console.log(`     ⏰ confirmed: "${confirm}"`);
      await sleep(3000, 4000);
    }
  } catch (e) {}
}

async function scrapeStoreDeep(page, store) {
  const captured = [];
  setupIntercept(page, captured);

  const url = `https://glovoapp.com/pt/pt/guarda/stores/${store.slug}`;
  console.log(`  goto ${url}`);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await sleep(4000, 5500);
  } catch (e) { console.warn(`  goto: ${e.message.substring(0, 80)}`); }

  try {
    await page.evaluate(() => {
      const b = Array.from(document.querySelectorAll('button')).find(x => /aceit|accept|ok/i.test(x.textContent || ''));
      if (b) b.click();
    });
    await sleep(1500, 2000);
  } catch (e) {}

  // Schedule delivery
  await tryScheduleDelivery(page);

  // Get unique sub-cat texts
  const subcatTexts = await page.evaluate((exclude) => {
    const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
    const set = new Set();
    for (const b of btns) {
      const t = (b.textContent || '').trim();
      if (t && t.length > 2 && t.length < 80 && !exclude.includes(t) && !/^\d+[,.]?\d*\s*€?$/.test(t) && !/^(grátis|gratis|prime|promoção|promoções|promocao|promocoes|promo|descontos?)$/i.test(t.trim())) {
        set.add(t);
      }
    }
    return [...set];
  }, EXCLUDE_BUTTONS);
  console.log(`  ${subcatTexts.length} sub-cats únicas`);

  for (let i = 0; i < subcatTexts.length; i++) {
    const txt = subcatTexts[i];
    const before = captured.length;
    try {
      const clicked = await page.evaluate((needle) => {
        const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
        const target = btns.find(b => (b.textContent || '').trim() === needle);
        if (target) { target.scrollIntoView({ block: 'center', behavior: 'instant' }); target.click(); return true; }
        return false;
      }, txt);

      if (!clicked) continue;
      await sleep(1500, 2200);

      // Scroll-until-stable: scroll até 20 iterações consecutivas sem novos produtos
      let stableCount = 0;
      let lastCaptured = captured.length;
      const MAX_SCROLLS = 80;
      for (let s = 0; s < MAX_SCROLLS; s++) {
        try {
          await page.evaluate(() => window.scrollBy(0, 1200));
        } catch (e) { break; }
        await sleep(450, 650);
        if (captured.length > lastCaptured) {
          stableCount = 0;
          lastCaptured = captured.length;
        } else {
          stableCount++;
          if (stableCount >= 20) break; // bottom reached
        }
      }
      const added = captured.length - before;
      console.log(`     [${(i+1).toString().padStart(2)}/${subcatTexts.length}] "${txt.substring(0, 35).padEnd(35)}" +${added} (total ${captured.length})`);
    } catch (e) {
      console.warn(`     err sub "${txt}": ${e.message.substring(0, 60)}`);
    }
  }

  // Try to read Glovo product counter (top of page or near search)
  let glovoCount = null;
  try {
    glovoCount = await page.evaluate(() => {
      const text = document.body.innerText || '';
      const m = text.match(/(\d{2,5})\s+(?:produtos|items|artigos)/i);
      return m ? parseInt(m[1]) : null;
    });
  } catch (e) {}
  if (glovoCount) console.log(`  📊 Glovo counter: ${glovoCount} produtos`);

  // Dedup intra
  const m = new Map();
  for (const p of captured) {
    const k = normalize(p.name);
    if (!m.has(k)) m.set(k, p);
  }
  return { products: [...m.values()], glovoCount };
}

async function importProducts(store, products) {
  if (products.length === 0) return { inserted: 0, skipped: 0, captured: 0 };
  fs.writeFileSync(
    path.join(outDir, `${store.restaurantId.replace(/-/g, '_')}_deep_${Date.now()}.json`),
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
  console.log('🎯 CDP Deep-Subcats Import — 2026-05-20\n');
  const browser = await chromium.connectOverCDP('http://localhost:9222');
  const ctx = browser.contexts()[0];

  const filtered = ONLY ? STORES.filter(s => ONLY.some(o => s.restaurantId.includes(o))) : STORES;
  const results = [];
  for (const store of filtered) {
    console.log(`🏪 ${store.restaurantId} (${store.slug})`);
    const page = await ctx.newPage();
    try {
      const { products, glovoCount } = await scrapeStoreDeep(page, store);
      console.log(`   unique captured: ${products.length} (Glovo counter: ${glovoCount ?? 'n/a'})`);
      const r = await importProducts(store, products);
      results.push({ store: store.restaurantId, ...r, glovoCount });
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
    else console.log(`✅ ${r.store.padEnd(22)} | captured=${(r.captured ?? 0).toString().padStart(4)} | inserted=${(r.inserted ?? 0).toString().padStart(4)} | dups=${r.skipped ?? 0} | glovo=${r.glovoCount ?? '-'}`);
  }
}

main().catch(e => { console.error('💥', e); process.exit(1); });
