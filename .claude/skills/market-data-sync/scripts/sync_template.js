#!/usr/bin/env node
/**
 * sync_template.js — Template universal Market Data Sync (Bora App)
 *
 * Uso:
 *   node sync_template.js \
 *     --store "Continente Guarda" \
 *     --restaurant-id "8f3a-..." \
 *     --source glovo \
 *     --source-store-id continente-grd1 \
 *     --price-source continente \
 *     --phase extract|price|apply
 *
 * Este ficheiro é um TEMPLATE. Cada loja pode override os adaptadores em:
 *   adapters/<source>.js          (extracção)
 *   adapters/price_<priceSource>.js (preço)
 *
 * Regras gerais — ver references/regras.md
 * Lojas suportadas — ver references/lojas.md
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ──────────────────────────────────────────────────────────────────
// CONFIG
// ──────────────────────────────────────────────────────────────────

const RATE_LIMIT_MS = 4500;
const RATE_LIMIT_JITTER_MS = 1000;
const CHECKPOINT_EVERY = 200;
const NAME_GUARD_THRESHOLD = 0.3;
const MAX_PRICE_CENTS = 50000;
const RETRY_BACKOFF_MS = [30_000, 60_000, 120_000];

// 22 categorias canónicas (ordem de precedência)
const CANONICAL_CATEGORIES = [
  'Congelados', 'Bebé', 'Animais', 'Vinhos', 'Charcutaria', 'Fitness',
  'Conservas', 'Snacks', 'Pequenos-Almoços', 'Padaria', 'Peixaria',
  'Talho', 'Laticínios', 'Frutas & Legumes', 'Pronto a Comer',
  'Mercearia', 'Bebidas', 'Saúde', 'Higiene Pessoal', 'Higiene do Lar',
  'Festa', 'Bio',
];

// ──────────────────────────────────────────────────────────────────
// UTILS
// ──────────────────────────────────────────────────────────────────

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const rateLimitDelay = () =>
  RATE_LIMIT_MS + Math.floor(Math.random() * RATE_LIMIT_JITTER_MS);

function stripAccents(s) {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '');
}

function normName(name) {
  return stripAccents((name || '').trim().toLowerCase());
}

function levenshteinNormalized(a, b) {
  if (!a || !b) return 1;
  if (a === b) return 0;
  const m = a.length, n = b.length;
  const dp = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      );
    }
  }
  return dp[m][n] / Math.max(m, n);
}

function todayStamp() {
  const d = new Date();
  return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
}

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

function writeJson(file, obj) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, JSON.stringify(obj, null, 2), 'utf8');
}

function readJsonOr(file, fallback) {
  return fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, 'utf8'))
    : fallback;
}

// ──────────────────────────────────────────────────────────────────
// CLI ARGS
// ──────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k.startsWith('--')) {
      const key = k.slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
      args[key] = val;
    }
  }
  return args;
}

function requireArg(args, name) {
  if (!args[name]) {
    console.error(`[sync] missing --${name}`);
    process.exit(2);
  }
  return args[name];
}

// ──────────────────────────────────────────────────────────────────
// ADAPTER LOADERS (override-friendly)
// ──────────────────────────────────────────────────────────────────

function loadSourceAdapter(source) {
  const tryPath = path.join(__dirname, 'adapters', `${source}.js`);
  if (fs.existsSync(tryPath)) return require(tryPath);
  return {
    async listProducts(_storeId) {
      throw new Error(
        `[sync] adapter '${source}' not implemented at ${tryPath}. ` +
        `Crie o ficheiro com a função async listProducts(storeId) → [{name, image_url, category_source, description}].`,
      );
    },
  };
}

function loadPriceAdapter(priceSource) {
  const tryPath = path.join(__dirname, 'adapters', `price_${priceSource}.js`);
  if (fs.existsSync(tryPath)) return require(tryPath);
  return {
    async fetchPrice(_name) {
      throw new Error(
        `[sync] price adapter '${priceSource}' not implemented at ${tryPath}. ` +
        `Crie o ficheiro com a função async fetchPrice(name) → { priceCents, foundName } | null.`,
      );
    },
  };
}

// Override: BD adapter (Supabase). Stub por defeito.
function loadDbAdapter() {
  const tryPath = path.join(__dirname, 'adapters', 'db.js');
  if (fs.existsSync(tryPath)) return require(tryPath);
  return {
    async fetchExistingProducts(_restaurantId) {
      console.warn('[sync] db adapter not implemented — running in dry-run mode (no DB lookup).');
      return [];
    },
    async upsertBatch(_rows) {
      console.warn('[sync] db adapter not implemented — skipping upsert.');
      return { updated: 0, inserted: 0 };
    },
  };
}

// ──────────────────────────────────────────────────────────────────
// CATEGORY MAPPING
// ──────────────────────────────────────────────────────────────────

function mapToCanonicalCategory(sourceCategory) {
  const s = normName(sourceCategory || '');
  for (const cat of CANONICAL_CATEGORIES) {
    if (s.includes(normName(cat))) return cat;
  }
  return null;
}

// ──────────────────────────────────────────────────────────────────
// QUALITY GATE
// ──────────────────────────────────────────────────────────────────

function passesQualityGate(product) {
  if (!product.name || product.name.trim().length < 3) return false;
  if (/^[\d\W]+$/.test(product.name)) return false;
  if (product.image_url && !/^https:\/\//.test(product.image_url)) return false;
  if (product.taxonomy_section && !CANONICAL_CATEGORIES.includes(product.taxonomy_section)) return false;
  if (product.price_cents != null) {
    if (!Number.isInteger(product.price_cents) || product.price_cents < 0) return false;
    if (product.price_cents > MAX_PRICE_CENTS) return false;
  }
  return true;
}

// ──────────────────────────────────────────────────────────────────
// PHASES
// ──────────────────────────────────────────────────────────────────

async function phaseExtract({ store, sourceStoreId, source, tmpDir }) {
  const adapter = loadSourceAdapter(source);
  const outFile = path.join(tmpDir, `extracted_${slug(store)}_${todayStamp()}.json`);

  console.log(`[extract] source=${source} store=${store}`);
  const products = await adapter.listProducts(sourceStoreId);
  console.log(`[extract] obtained ${products.length} products`);

  for (const p of products) {
    p.norm_name = normName(p.name);
    p.taxonomy_section = mapToCanonicalCategory(p.category_source);
    delete p.price; // CRITICAL: never carry source price to apply phase
  }

  writeJson(outFile, { store, source, count: products.length, products });
  console.log(`[extract] saved → ${outFile}`);
  return outFile;
}

async function phasePrice({ store, priceSource, tmpDir }) {
  const inFile = path.join(tmpDir, `extracted_${slug(store)}_${todayStamp()}.json`);
  const outFile = path.join(tmpDir, `priced_${slug(store)}_${todayStamp()}.json`);
  const ckpFile = path.join(tmpDir, `checkpoint_${slug(store)}_${todayStamp()}.json`);

  if (!fs.existsSync(inFile)) {
    throw new Error(`[price] missing extracted file ${inFile}. Run --phase extract first.`);
  }

  const adapter = loadPriceAdapter(priceSource);
  const data = readJsonOr(inFile, { products: [] });
  const ckp = readJsonOr(ckpFile, { phase: 'price', last_index: -1 });
  const startIdx = ckp.phase === 'price' ? ckp.last_index + 1 : 0;

  console.log(`[price] resuming from index ${startIdx} / ${data.products.length}`);

  for (let i = startIdx; i < data.products.length; i++) {
    const p = data.products[i];
    let attempt = 0;
    let result = null;
    while (attempt <= RETRY_BACKOFF_MS.length) {
      try {
        result = await adapter.fetchPrice(p.name);
        break;
      } catch (err) {
        if (attempt === RETRY_BACKOFF_MS.length) {
          console.error(`[price] giving up on "${p.name}":`, err.message);
          break;
        }
        const wait = RETRY_BACKOFF_MS[attempt++];
        console.warn(`[price] retry ${attempt} after ${wait}ms — ${err.message}`);
        await sleep(wait);
      }
    }
    if (result && Number.isInteger(result.priceCents)) {
      p.price_cents = result.priceCents;
      p.price_lookup_failed = false;
    } else {
      p.price_cents = null;
      p.price_lookup_failed = true;
    }
    if ((i + 1) % CHECKPOINT_EVERY === 0) {
      writeJson(ckpFile, {
        phase: 'price',
        last_index: i,
        last_product_name: p.name,
        timestamp: new Date().toISOString(),
      });
      console.log(`[price] checkpoint at ${i + 1}/${data.products.length}`);
    }
    await sleep(rateLimitDelay());
  }

  writeJson(outFile, data);
  console.log(`[price] saved → ${outFile}`);
  return outFile;
}

async function phaseApply({ store, restaurantId, tmpDir, reportDir }) {
  const inFile = path.join(tmpDir, `priced_${slug(store)}_${todayStamp()}.json`);
  const rejectedFile = path.join(tmpDir, `rejected_${slug(store)}_${todayStamp()}.json`);
  const reportFile = path.join(reportDir, `market-data-sync-${slug(store)}-${todayStamp()}.md`);

  if (!fs.existsSync(inFile)) {
    throw new Error(`[apply] missing priced file ${inFile}. Run --phase price first.`);
  }

  const data = readJsonOr(inFile, { products: [] });
  const db = loadDbAdapter();
  const existing = await db.fetchExistingProducts(restaurantId);
  const existingByNorm = new Map(existing.map((e) => [normName(e.name), e]));

  const rows = { update: [], insert: [], rejected: [], duvidosos: [] };

  for (const p of data.products) {
    const candidate = existingByNorm.get(p.norm_name);
    if (candidate) {
      rows.update.push({ id: candidate.id, ...p });
      continue;
    }
    let bestScore = 1, bestMatch = null;
    for (const [norm, e] of existingByNorm) {
      const s = levenshteinNormalized(p.norm_name, norm);
      if (s < bestScore) { bestScore = s; bestMatch = e; }
    }
    if (bestMatch && bestScore <= NAME_GUARD_THRESHOLD) {
      rows.duvidosos.push({ candidate_id: bestMatch.id, score: bestScore, ...p });
      continue;
    }

    const newRow = {
      restaurant_id: restaurantId,
      name: p.name,
      image_url: p.image_url || null,
      taxonomy_section: p.taxonomy_section,
      price_cents: p.price_cents,
      needs_review: true,
      is_available: p.price_cents != null,
      sync_source: data.source || 'manual',
    };
    if (passesQualityGate(newRow)) rows.insert.push(newRow);
    else rows.rejected.push({ reason: 'quality_gate', ...newRow });
  }

  writeJson(rejectedFile, rows.rejected);

  // Apply only after writing the report; STOP for approval.
  const summary = {
    store,
    restaurant_id: restaurantId,
    total_extracted: data.products.length,
    to_update: rows.update.length,
    to_insert: rows.insert.length,
    duvidosos: rows.duvidosos.length,
    rejected: rows.rejected.length,
    no_price: data.products.filter((p) => p.price_lookup_failed).length,
  };

  ensureDir(reportDir);
  fs.writeFileSync(reportFile, renderReport(summary, rows), 'utf8');
  console.log(`[apply] report → ${reportFile}`);
  console.log('[apply] STOP — aguardar aprovação do Danilo antes de fazer commit BD.');
  return { summary, reportFile, rows };
}

function renderReport(summary, rows) {
  return [
    `# Market Data Sync — ${summary.store}`,
    '',
    `**Data:** ${new Date().toISOString()}`,
    `**Restaurant ID:** \`${summary.restaurant_id}\``,
    '',
    '## Sumário',
    '',
    `- Total extraídos: **${summary.total_extracted}**`,
    `- A actualizar (UPDATE): **${summary.to_update}**`,
    `- A inserir (INSERT): **${summary.to_insert}**`,
    `- Sem preço (is_available=false): **${summary.no_price}**`,
    `- Matches duvidosos (revisão): **${summary.duvidosos}**`,
    `- Rejeitados (quality gate): **${summary.rejected}**`,
    '',
    '## Próximo passo',
    '',
    'Aguardar aprovação explícita do Danilo antes de aplicar à BD.',
    '',
    rows.duvidosos.length
      ? '> ⚠️ Há matches duvidosos — rever antes de aplicar.'
      : '',
  ].join('\n');
}

function slug(s) {
  return stripAccents(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

// ──────────────────────────────────────────────────────────────────
// MAIN
// ──────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  const store = requireArg(args, 'store');
  const phase = requireArg(args, 'phase');
  const restaurantId = args['restaurant-id'];
  const source = args['source'];
  const sourceStoreId = args['source-store-id'];
  const priceSource = args['price-source'];

  const tmpDir = path.join(__dirname, '..', '..', '..', '.ai', 'tmp', 'market-data-sync');
  const reportDir = path.join(__dirname, '..', '..', '..', '.ai', 'reports');

  ensureDir(tmpDir);

  switch (phase) {
    case 'extract':
      await phaseExtract({ store, sourceStoreId: requireArg(args, 'source-store-id'), source: requireArg(args, 'source'), tmpDir });
      break;
    case 'price':
      await phasePrice({ store, priceSource: requireArg(args, 'price-source'), tmpDir });
      break;
    case 'apply':
      await phaseApply({ store, restaurantId: requireArg(args, 'restaurant-id'), tmpDir, reportDir });
      break;
    default:
      console.error(`[sync] unknown phase: ${phase}. Use extract|price|apply.`);
      process.exit(2);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('[sync] fatal:', err);
    process.exit(1);
  });
}

module.exports = {
  normName,
  levenshteinNormalized,
  mapToCanonicalCategory,
  passesQualityGate,
  CANONICAL_CATEGORIES,
};
