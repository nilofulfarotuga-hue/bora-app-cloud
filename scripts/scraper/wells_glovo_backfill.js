/**
 * Wells × Glovo Guarda — backfill preços (tarefa pontual 2026-05-19)
 *
 * 63 produtos Wells importados sem preço (lentes contacto + cosmética premium
 * com variantes onde JSON-LD não tem `offers.price`).
 *
 * Estratégia:
 *   1. Lê estes produtos da DB (price IS NULL)
 *   2. Playwright headless abre Glovo Guarda → Wells
 *   3. Captura responses da API Glovo (intercept network)
 *   4. Faz fuzzy match name PT-normalizado
 *   5. price_base = glovo_price / 1.15 → UPDATE DB
 *   6. source='wells_glovo_fallback_2026-05-19', image_source='glovo'
 *
 * Usage: cd bora_app/scripts/scraper && node wells_glovo_backfill.js
 */

import 'dotenv/config';
import { launchBrowser, newPage, sleep } from './lib/browser.js';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  { auth: { persistSession: false } }
);

const RESTAURANT_ID = 'wells-guarda';
const GLOVO_URL = 'https://glovoapp.com/pt/pt/guarda/wells-guarda';
const SOURCE_TAG = 'wells_glovo_fallback_2026-05-19';

// Normalização para fuzzy match: lowercase, sem acentos, sem espaços extra,
// sem pontuação.
function normalize(s) {
  return (s || '')
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '') // remove acentos
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Token-set similarity (rough Jaccard) — robusto a ordem diferente de palavras
function similarity(a, b) {
  const ta = new Set(normalize(a).split(' ').filter(Boolean));
  const tb = new Set(normalize(b).split(' ').filter(Boolean));
  if (ta.size === 0 || tb.size === 0) return 0;
  const inter = [...ta].filter(t => tb.has(t)).length;
  const union = new Set([...ta, ...tb]).size;
  return inter / union;
}

async function fetchPendingProducts() {
  const { data, error } = await supabase
    .from('products')
    .select('id, name')
    .eq('restaurant_id', RESTAURANT_ID)
    .or('price.is.null,price.eq.0')
    .limit(200);
  if (error) throw error;
  console.log(`📋 ${data.length} produtos Wells sem preço na DB`);
  return data;
}

async function scrapeGlovoWells(browser) {
  const { page, context } = await newPage(browser);
  const capturedProducts = [];
  const apiUrlsSeen = new Set();
  const productResponses = [];

  page.on('response', async (response) => {
    const url = response.url();
    apiUrlsSeen.add(url.replace(/\?.*/, '').replace(/\/\d{4,}/g, '/{ID}'));
    if (response.status() < 200 || response.status() >= 400) return;
    const ct = response.headers()['content-type'] || '';
    if (!ct.includes('json')) return;
    if (url.includes('/analytics') || url.includes('/tracking') || url.includes('googletagmanager')) return;
    try {
      const json = await response.json();
      const bodyStr = JSON.stringify(json);
      // Pesquisa AMPLA: tenta encontrar qualquer estrutura com nome+preço
      if (bodyStr.includes('Wells') || bodyStr.match(/"name"\s*:\s*"[^"]{4,80}"/) || bodyStr.includes('priceInfo') || bodyStr.includes('product')) {
        productResponses.push({ url, sample: bodyStr.slice(0, 400) });
      }
      const collect = (obj, depth = 0) => {
        if (!obj || depth > 10) return;
        if (Array.isArray(obj)) return obj.forEach(o => collect(o, depth + 1));
        if (typeof obj !== 'object') return;
        const name = obj.name || obj.productName;
        const priceRaw = obj.price ?? obj.priceInfo?.amount ?? obj.formattedPrice ?? obj.priceCents ?? obj.unitPrice;
        if (name && priceRaw != null && typeof name === 'string' && name.length > 2 && name.length < 200) {
          let price;
          if (typeof priceRaw === 'number') price = priceRaw > 100 ? priceRaw / 100 : priceRaw;
          else { const m = String(priceRaw).match(/(\d+[.,]\d{2})/); price = m ? parseFloat(m[1].replace(',', '.')) : NaN; }
          if (price > 0 && !isNaN(price)) {
            capturedProducts.push({ name, price, imageUrl: obj.imageUrl || obj.imageId || obj.photoUrl || obj.image || null });
          }
        }
        for (const v of Object.values(obj)) if (v && typeof v === 'object') collect(v, depth + 1);
      };
      collect(json);
    } catch (e) { /* ignora */ }
  });

  console.log(`🌐 Carregar ${GLOVO_URL}...`);
  try {
    await page.goto(GLOVO_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await sleep(3000, 5000);
  } catch (e) { console.warn(`  ⚠️ goto: ${e.message}`); }

  // Dismiss cookie/age banner se houver
  try {
    await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      const cookie = buttons.find(b => /aceit|accept|ok|fechar|continuar/i.test(b.textContent || ''));
      if (cookie) cookie.click();
    });
    await sleep(1000, 1500);
  } catch (e) {}

  // Scroll para hydrate categorias
  console.log(`📜 Scroll inicial...`);
  for (let i = 0; i < 4; i++) {
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sleep(1200, 1800);
  }

  // Tenta clicar em categorias relevantes para forçar load de produtos
  const categoryTexts = ['Cosmética Rosto', 'Cuidado Cabelo', 'Saúde e Bem-Estar', 'Bebé e Mamã', 'Higiene Oral', 'Maquilhagem', 'Perfumes'];
  for (const txt of categoryTexts) {
    try {
      const clicked = await page.evaluate((needle) => {
        const els = Array.from(document.querySelectorAll('a, button, [role="button"], h2, h3'));
        const target = els.find(e => (e.textContent || '').trim().startsWith(needle));
        if (target) { target.scrollIntoView({ block: 'center' }); target.click(); return true; }
        return false;
      }, txt);
      if (clicked) {
        console.log(`  🔗 clicked "${txt}"`);
        await sleep(2000, 3000);
        // Scroll dentro da categoria
        for (let i = 0; i < 3; i++) {
          await page.evaluate(() => window.scrollBy(0, 1500));
          await sleep(800, 1200);
        }
        await page.goBack().catch(() => {});
        await sleep(1500, 2200);
      }
    } catch (e) {}
  }

  // Extract products from rendered DOM (fallback se intercept falhar)
  console.log(`🔍 Extract products from DOM...`);
  const domProducts = await page.evaluate(() => {
    const out = [];
    const productCards = document.querySelectorAll(
      '[data-test*="product"], [data-test*="Product"], [class*="product-row"], [class*="product-card"], [class*="ProductRow"], [class*="ProductCard"], article[class*="product"]'
    );
    for (const card of productCards) {
      const nameEl = card.querySelector('[class*="name"], [class*="title"], h3, h4, span') || card;
      const priceEl = card.querySelector('[class*="price"], [data-test*="price"]');
      const imgEl = card.querySelector('img');
      const name = (nameEl?.textContent || '').trim().replace(/\s+/g, ' ');
      const priceText = (priceEl?.textContent || '').trim();
      const m = priceText.match(/(\d+[.,]\d{2})/);
      const price = m ? parseFloat(m[1].replace(',', '.')) : null;
      if (name && price && name.length < 200) {
        out.push({ name, price, imageUrl: imgEl?.src || null });
      }
    }
    return out;
  });
  console.log(`  → DOM extraction: ${domProducts.length} produtos`);
  capturedProducts.push(...domProducts);

  console.log(`📡 Total API URLs únicos vistos: ${apiUrlsSeen.size}`);
  console.log(`📊 Responses com sinais de produto: ${productResponses.length}`);
  productResponses.slice(0, 5).forEach(r => console.log(`   • ${r.url.slice(0, 120)}\n     sample: ${r.sample.slice(0, 200).replace(/\s+/g, ' ')}`));

  const dedup = new Map();
  for (const p of capturedProducts) {
    const key = normalize(p.name);
    if (!dedup.has(key)) dedup.set(key, p);
  }
  const products = [...dedup.values()];
  console.log(`✅ Capturados ${products.length} produtos únicos do Glovo (intercept + DOM)`);
  await context.close();
  return products;
}

function matchProducts(dbProducts, glovoProducts, threshold = 0.55) {
  const matches = [];
  for (const db of dbProducts) {
    let best = { glovo: null, score: 0 };
    for (const g of glovoProducts) {
      const s = similarity(db.name, g.name);
      if (s > best.score) best = { glovo: g, score: s };
    }
    if (best.score >= threshold) {
      matches.push({ db, glovo: best.glovo, score: best.score });
    }
  }
  return matches;
}

async function applyUpdates(matches) {
  let updated = 0;
  let failed = 0;
  for (const { db, glovo, score } of matches) {
    const basePrice = +(glovo.price / 1.15).toFixed(2);
    try {
      const { error } = await supabase
        .from('products')
        .update({
          price: basePrice,
          is_available: true,
          needs_review: false,
          needs_photo: false,
          source: SOURCE_TAG,
          image_source: 'glovo',
          last_updated: new Date().toISOString().slice(0, 10),
        })
        .eq('id', db.id);
      if (error) { failed++; console.warn(`  ❌ ${db.name}: ${error.message}`); continue; }
      updated++;
      console.log(`  ✅ "${db.name}" ↔ "${glovo.name}" (score ${score.toFixed(2)}) → glovo €${glovo.price} ÷ 1.15 = €${basePrice}`);
    } catch (e) {
      failed++;
      console.warn(`  ❌ ${db.name}: ${e.message}`);
    }
  }
  return { updated, failed };
}

async function main() {
  console.log('🎯 Wells × Glovo backfill — Sessão 2026-05-19');
  console.log(`   Supabase: ${process.env.SUPABASE_URL}`);

  const pending = await fetchPendingProducts();
  if (pending.length === 0) {
    console.log('Nenhum produto pendente. Nada a fazer.');
    return;
  }

  const browser = await launchBrowser();
  try {
    const glovoProducts = await scrapeGlovoWells(browser);

    // Save backup
    const fs = await import('fs');
    const path = await import('path');
    const outDir = path.join(process.cwd(), 'output');
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(
      path.join(outDir, `wells_glovo_${Date.now()}.json`),
      JSON.stringify(glovoProducts, null, 2)
    );

    const matches = matchProducts(pending, glovoProducts);
    console.log(`\n🔗 ${matches.length}/${pending.length} matches >= 0.55 similarity`);

    if (matches.length === 0) {
      console.log('Nenhum match — Glovo provavelmente não tem estes produtos no catálogo Guarda.');
      return;
    }

    const { updated, failed } = await applyUpdates(matches);
    console.log(`\n📊 Resultado: ${updated} actualizados, ${failed} falhas, ${pending.length - matches.length} sem match no Glovo`);
  } finally {
    await browser.close();
  }
}

main().catch(err => { console.error('💥', err); process.exit(1); });
