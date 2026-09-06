/**
 * Wells scraper — Sessão Autónoma 2026-05-19
 *
 * Estratégia: sitemap_0-product.xml (público, robots.txt-friendly) → fetch
 * Product-Show de cada URL → parse JSON-LD ou meta tags → produtos com
 * nome/descrição/photo/price/category/brand.
 *
 * Wells.pt = Salesforce Commerce Cloud (SFCC/Demandware) — mesma plataforma
 * que Continente. JSON-LD `Product` schema está embebido em
 * `<script type="application/ld+json">` em cada Product-Show.
 *
 * NÃO usa Playwright (acesso HTTPS directo funciona). NÃO bate em endpoints
 * proibidos pelo robots.txt (`/Search-UpdateGrid`, `/quickview`, filtros).
 *
 * Glovo Guarda Wells página devolveu 503 (Cloudflare) — sitemap dá catálogo
 * mais completo que Glovo na prática.
 *
 * Output: produtos compatíveis com `insertProducts(products, 'wells-guarda')`.
 * Preço guardado é PURO (sem 15% markup) — sistema aplica em runtime via
 * `pricing_calculate` (business_rules §2.4, §27.7).
 */

import https from 'https';
import { sleep } from '../lib/browser.js';

const RESTAURANT_ID = 'wells-guarda';
const BASE_URL = 'https://wells.pt'; // sem www — www.wells.pt redirect 301 → wells.pt
const SITEMAP_PRODUCT = `${BASE_URL}/sitemap_0-product.xml`;
const SITEMAP_CATEGORY = `${BASE_URL}/sitemap_2-category.xml`;

// Categorias top-level Wells (do sitemap_2) — usado para classificação
// canónica → taxonomy_section.
const TAXONOMY_MAP = {
  saude: 'pharmacy_otc',
  'primeiros-socorros': 'pharmacy_otc',
  'higiene-oral': 'pharmacy_hygiene',
  'saude-sexual': 'pharmacy_otc',
  'saude-animal': 'pharmacy_otc',
  'equipamentos': 'pharmacy_otc',
  'nutricao-suplementos': 'pharmacy_vitamins',
  suplementos: 'pharmacy_vitamins',
  vitaminas: 'pharmacy_vitamins',
  'bebe-mama': 'pharmacy_baby',
  bebe: 'pharmacy_baby',
  perfumes: 'pharmacy_beauty',
  'cosmetica-rosto-e-corpo': 'pharmacy_beauty',
  cosmetica: 'pharmacy_beauty',
  maquilhagem: 'pharmacy_beauty',
  'produtos-cabelo': 'pharmacy_beauty',
  beleza: 'pharmacy_beauty',
  homem: 'pharmacy_hygiene',
  higiene: 'pharmacy_hygiene',
  otica: 'pharmacy_otc',
};

// PALAVRAS-CHAVE que indicam produto sob prescrição médica → EXCLUIR.
// Wells separa estes com badge "Apenas com receita médica" mas para evitar
// problemas legais excluímos todos os termos relacionados.
const PRESCRIPTION_KEYWORDS = [
  'receita médica',
  'sob prescrição',
  'medicamento sujeito',
  'msrm',
  'apenas com receita',
];

function pickTaxonomySection(productUrl, breadcrumb) {
  const haystack = `${productUrl} ${breadcrumb || ''}`.toLowerCase();
  for (const [key, section] of Object.entries(TAXONOMY_MAP)) {
    if (haystack.includes(`/${key}/`) || haystack.includes(` ${key} `)) {
      return section;
    }
  }
  return 'pharmacy_otc';
}

function looksLikePrescription(name, description) {
  const text = `${name || ''} ${description || ''}`.toLowerCase();
  return PRESCRIPTION_KEYWORDS.some(k => text.includes(k));
}

function apiGet(url, redirectsLeft = 5) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pt-PT,pt;q=0.9,en;q=0.8',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      },
      timeout: 20000,
    }, (res) => {
      // Follow 301/302/307/308 redirects
      if ([301, 302, 307, 308].includes(res.statusCode) && res.headers.location && redirectsLeft > 0) {
        res.resume();
        const next = new URL(res.headers.location, url).toString();
        return apiGet(next, redirectsLeft - 1).then(resolve, reject);
      }
      if (res.statusCode >= 400) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error(`timeout ${url}`)); });
  });
}

async function fetchProductUrls(maxUrls = Infinity) {
  console.log(`  🗺️  Fetch sitemap: ${SITEMAP_PRODUCT}`);
  const xml = await apiGet(SITEMAP_PRODUCT);
  const urls = [];
  const re = /<loc>([^<]+)<\/loc>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    const u = m[1].trim();
    if (u.startsWith(BASE_URL) && u !== SITEMAP_PRODUCT) urls.push(u);
    if (urls.length >= maxUrls) break;
  }
  console.log(`     → ${urls.length} URLs de produto no sitemap`);
  return urls;
}

function extractJsonLd(html) {
  // Wells embute Product schema em <script type="application/ld+json">.
  // Pode haver múltiplos scripts; queremos o que tem @type=Product.
  const results = [];
  const re = /<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    try {
      const parsed = JSON.parse(m[1].trim());
      const items = Array.isArray(parsed) ? parsed : [parsed];
      for (const item of items) {
        const t = item['@type'];
        if (t === 'Product' || (Array.isArray(t) && t.includes('Product'))) {
          results.push(item);
        }
      }
    } catch (e) { /* ignora scripts mal formados */ }
  }
  return results;
}

function extractMetaContent(html, name) {
  const re = new RegExp(`<meta[^>]+(?:name|property)=["']${name}["'][^>]+content=["']([^"']+)["']`, 'i');
  const m = html.match(re);
  return m ? m[1] : null;
}

function extractBreadcrumb(html) {
  // SFCC tipicamente tem <ol class="breadcrumb">…</ol> ou JSON-LD BreadcrumbList.
  const re = /<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    try {
      const parsed = JSON.parse(m[1].trim());
      const items = Array.isArray(parsed) ? parsed : [parsed];
      for (const item of items) {
        if (item['@type'] === 'BreadcrumbList' && Array.isArray(item.itemListElement)) {
          return item.itemListElement.map(e => e.name || e.item?.name).filter(Boolean).join(' > ');
        }
      }
    } catch (e) { /* ignora */ }
  }
  return null;
}

function parseProductPage(html, productUrl) {
  const lds = extractJsonLd(html);
  if (lds.length === 0) return null;

  const ld = lds[0];
  const offers = Array.isArray(ld.offers) ? ld.offers[0] : ld.offers;
  const priceRaw = offers?.price ?? offers?.lowPrice ?? null;
  const price = priceRaw != null ? parseFloat(String(priceRaw).replace(',', '.')) : null;
  const availability = offers?.availability || '';
  const inStock = /InStock/i.test(availability);

  const name = (ld.name || extractMetaContent(html, 'og:title') || '').trim();
  if (!name) return null;

  const description = (ld.description || extractMetaContent(html, 'og:description') || '').trim() || null;
  const brand = (typeof ld.brand === 'object' ? ld.brand.name : ld.brand) || null;
  const photoRaw = Array.isArray(ld.image) ? ld.image[0] : ld.image;
  const photo_url = typeof photoRaw === 'string' && photoRaw ? (photoRaw.startsWith('http') ? photoRaw : BASE_URL + photoRaw) : null;

  const breadcrumb = extractBreadcrumb(html);
  const taxonomy_section = pickTaxonomySection(productUrl, breadcrumb);
  const category_root = breadcrumb ? breadcrumb.split(' > ').slice(1).join(' > ') : (taxonomy_section || 'Outros');

  if (looksLikePrescription(name, description)) {
    return null; // exclui produtos sob receita médica
  }

  return {
    name,
    description: description || (brand ? `${brand}` : null),
    photo_url,
    price: (price && price > 0 && inStock) ? price : null,
    category: category_root || 'Outros',
    category_root,
    taxonomy_section,
    unit: null,
    is_on_sale: false,
    discount_price: null,
    source: `wells.pt_${new Date().toISOString().slice(0, 10)}`,
    image_source: photo_url ? 'wells_official' : null,
    needs_photo: !photo_url,
    needs_review: !price || !inStock,
    _product_url: productUrl,
  };
}

export async function scrapeWells(browser, maxProducts = 3000) {
  console.log('\n💊 FASE — Wells (farmácia)');
  console.log(`   restaurant_id: ${RESTAURANT_ID}`);
  console.log(`   modo: sitemap-based (HTTPS, no Playwright)`);

  const productUrls = await fetchProductUrls(maxProducts);

  const products = [];
  const seen = new Set();
  let processed = 0;
  let failed = 0;

  for (const url of productUrls) {
    if (products.length >= maxProducts) break;
    processed++;
    try {
      const html = await apiGet(url);
      const p = parseProductPage(html, url);
      if (p && p.name && !seen.has(p.name.toLowerCase())) {
        seen.add(p.name.toLowerCase());
        products.push(p);
      }
      if (processed % 25 === 0) {
        console.log(`   • Processados ${processed}/${productUrls.length} (capturados ${products.length})`);
      }
      // rate limit 1 req/seg (§27.5 anti-blocking)
      await sleep(1000, 1400);
    } catch (e) {
      failed++;
      if (failed <= 5) console.warn(`   ⚠️  ${url} → ${e.message}`);
      if (failed > 50) {
        console.error(`   ❌ Demasiados erros (${failed}); abortando Wells.`);
        break;
      }
      await sleep(3000, 4500);
    }
  }

  console.log(`  ✅ Wells: ${products.length} produtos capturados (${failed} falhas em ${processed} tentativas)`);
  return { products, restaurantId: RESTAURANT_ID };
}
