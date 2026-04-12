require('dotenv').config();
/**
 * BORA App — Gerador de Imagens de Produtos via DALL-E
 *
 * Uso:
 *   npm install openai
 *   node generate_product_images.js
 *
 * Variáveis de ambiente (.env):
 *   OPENAI_API_KEY=sk-...
 *   SUPABASE_SERVICE_ROLE_KEY=eyJ...   (obrigatório para upload Storage)
 *   SUPABASE_URL=https://xxx.supabase.co
 *
 *   # Opcional (controlo):
 *   BATCH_SIZE=10        (produtos por lote, padrão: 10)
 *   MODEL=dall-e-2       (dall-e-2 = $0.018/img | dall-e-3 = $0.04/img)
 *   DRY_RUN=true         (simula sem gastar créditos)
 *   SKIP_IF_HAS_IMAGE=true  (ignora produtos que já têm image_url)
 *   CATEGORY_FILTER=Frutas   (processa só uma categoria)
 */

'use strict';
require('dotenv').config();

const { createClient } = require('@supabase/supabase-js');
const OpenAI = require('openai');
const https = require('https');
const http = require('http');

// ── Config ─────────────────────────────────────────────────────────────────
const SUPABASE_URL      = process.env.SUPABASE_URL      || 'https://ojykpzwqrtusfeakzrna.supabase.co';
const SUPABASE_KEY      = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
const OPENAI_API_KEY    = process.env.OPENAI_API_KEY;
const BUCKET            = 'product-images';
const MODEL             = process.env.MODEL        || 'dall-e-3';
const IMAGE_SIZE        = MODEL === 'dall-e-3' ? '1024x1024' : '512x512';
const BATCH_SIZE        = parseInt(process.env.BATCH_SIZE || '10', 10);
const DRY_RUN           = process.env.DRY_RUN === 'true';
const SKIP_IF_HAS_IMAGE = process.env.SKIP_IF_HAS_IMAGE !== 'false'; // padrão: true
const CATEGORY_FILTER   = process.env.CATEGORY_FILTER || null;
const DELAY_MS          = parseInt(process.env.DELAY_MS || '2000', 10); // entre imagens
const PRODUCT_LIMIT     = process.env.PRODUCT_LIMIT ? parseInt(process.env.PRODUCT_LIMIT, 10) : null; // null = sem limite
const STORAGE_PUBLIC_URL = `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}`;

// ── Validação ───────────────────────────────────────────────────────────────
if (!OPENAI_API_KEY) {
  console.error('❌  OPENAI_API_KEY não definida. Adiciona ao .env');
  process.exit(1);
}
if (!SUPABASE_KEY) {
  console.error('❌  SUPABASE_SERVICE_ROLE_KEY não definida. Adiciona ao .env');
  process.exit(1);
}

// ── Clientes ────────────────────────────────────────────────────────────────
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false },
});
const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

// ── Gerador de Prompts ───────────────────────────────────────────────────────
function buildPrompt(name, category, description) {
  const cat = (category || '').toLowerCase();
  let style = 'supermarket product photo';

  if (['frutas', 'legumes'].includes(cat)) {
    style = 'fresh produce market photo';
  } else if (['talho', 'peixaria'].includes(cat)) {
    style = 'fresh market meat/fish photo';
  } else if (['laticínios', 'ovos'].includes(cat)) {
    style = 'dairy/eggs product photo';
  } else if (['bebidas', 'águas'].includes(cat)) {
    style = 'beverage bottle product photo';
  } else if (['limpeza', 'higiene'].includes(cat)) {
    style = 'household product photo';
  } else if (['gourmet'].includes(cat)) {
    style = 'premium gourmet food product photo';
  } else if (['pet'].includes(cat)) {
    style = 'pet food product photo';
  } else if (['bio'].includes(cat)) {
    style = 'organic certified product photo';
  }

  const cleanName = name.replace(/\d+g|\d+ml|\d+L|\d+kg|\(\d+un\)/gi, '').trim();

  return `Realistic ${style} of "${cleanName}", clean pure white background, ` +
    `studio lighting, sharp focus, no text overlays, no brand logos, ` +
    `professional food photography style, 4K quality`;
}

// ── Download de imagem para Buffer ──────────────────────────────────────────
function downloadImage(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    lib.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        return downloadImage(res.headers.location).then(resolve).catch(reject);
      }
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

// ── Sleep ────────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── Validar URL acessível ────────────────────────────────────────────────────
function validateUrl(url) {
  return new Promise((resolve) => {
    const lib = url.startsWith('https') ? https : http;
    const req = lib.request(url, { method: 'HEAD' }, (res) => {
      resolve({ ok: res.statusCode >= 200 && res.statusCode < 400, status: res.statusCode });
    });
    req.on('error', (err) => resolve({ ok: false, status: err.message }));
    req.setTimeout(5000, () => { req.destroy(); resolve({ ok: false, status: 'timeout' }); });
    req.end();
  });
}

// ── Estatísticas ─────────────────────────────────────────────────────────────
const stats = { total: 0, done: 0, skipped: 0, errors: 0, cost: 0 };
const COST_PER_IMAGE = MODEL === 'dall-e-3' ? 0.04 : 0.018;

// ── Processar um produto ─────────────────────────────────────────────────────
async function processProduct(product) {
  const { id, name, category, description } = product;
  const fileName = `product-${id}.jpg`;
  const publicUrl = `${STORAGE_PUBLIC_URL}/${fileName}`;

  console.log(`  [${id}] ${name} (${category})`);

  if (DRY_RUN) {
    console.log(`    🔵 DRY RUN — prompt: ${buildPrompt(name, category, description).slice(0, 80)}...`);
    stats.done++;
    stats.cost += COST_PER_IMAGE;
    return;
  }

  try {
    // 1. Gerar imagem via OpenAI
    const prompt = buildPrompt(name, category, description);
    const response = await openai.images.generate({
      model: MODEL,
      prompt,
      n: 1,
      size: IMAGE_SIZE,
      quality: MODEL === 'dall-e-3' ? 'standard' : undefined,
      response_format: 'url',
    });

    const imageUrl = response.data[0].url;
    console.log(`    ✅ Imagem gerada`);

    // 2. Download da imagem
    const imageBuffer = await downloadImage(imageUrl);
    console.log(`    ✅ Download: ${Math.round(imageBuffer.length / 1024)}KB`);

    // 3. Upload para Supabase Storage
    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(fileName, imageBuffer, {
        contentType: 'image/jpeg',
        upsert: true,
      });

    if (uploadError) {
      console.error(`    ❌ Upload falhou: ${uploadError.message}`);
      stats.errors++;
      return;
    }
    console.log(`    ✅ Upload: ${fileName}`);

    // 4. Atualizar image_url na tabela products
    const { error: updateError } = await supabase
      .from('products')
      .update({ photo_url: publicUrl })
      .eq('id', id);

    if (updateError) {
      console.error(`    ❌ Update falhou: ${updateError.message}`);
      stats.errors++;
      return;
    }

    console.log(`    ✅ DB atualizado → ${publicUrl}`);

    // 5. Validar que a URL é acessível publicamente
    const validation = await validateUrl(publicUrl);
    if (validation.ok) {
      console.log(`    ✅ URL validada (HTTP ${validation.status})`);
    } else {
      console.warn(`    ⚠️  URL não acessível (status: ${validation.status}) — ${publicUrl}`);
    }

    stats.done++;
    stats.cost += COST_PER_IMAGE;

  } catch (err) {
    console.error(`    ❌ Erro: ${err.message}`);
    stats.errors++;
  }
}

// ── Garantir bucket existe ───────────────────────────────────────────────────
async function ensureBucket() {
  const { data: buckets } = await supabase.storage.listBuckets();
  const exists = (buckets || []).some((b) => b.name === BUCKET);

  if (!exists) {
    console.log(`📦 Criando bucket "${BUCKET}"...`);
    const { error } = await supabase.storage.createBucket(BUCKET, {
      public: true,
      fileSizeLimit: 5 * 1024 * 1024, // 5MB
    });
    if (error) {
      console.error(`❌ Falha ao criar bucket: ${error.message}`);
      process.exit(1);
    }
    console.log(`✅ Bucket "${BUCKET}" criado`);
  } else {
    console.log(`✅ Bucket "${BUCKET}" já existe`);
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('');
  console.log('╔════════════════════════════════════════════╗');
  console.log('║  BORA — Gerador de Imagens de Produtos     ║');
  console.log('╚════════════════════════════════════════════╝');
  console.log(`  Modelo    : ${MODEL}`);
  console.log(`  Tamanho   : ${IMAGE_SIZE}`);
  console.log(`  Batch     : ${BATCH_SIZE}`);
  console.log(`  Dry Run   : ${DRY_RUN}`);
  console.log(`  Skip c/img: ${SKIP_IF_HAS_IMAGE}`);
  console.log(`  Filtro cat: ${CATEGORY_FILTER || 'todos'}`);
  console.log(`  Limite    : ${PRODUCT_LIMIT ?? 'sem limite'}`);
  console.log('');

  // Garantir bucket
  if (!DRY_RUN) await ensureBucket();

  // Construir query
  let query = supabase
    .from('products')
    .select('id, name, category, description, photo_url')
    .order('category');

  if (CATEGORY_FILTER) {
    query = query.eq('category', CATEGORY_FILTER);
  }

  if (SKIP_IF_HAS_IMAGE) {
    // Incluir produtos sem photo_url OU com URLs do unsplash (para substituir)
    query = query.or('photo_url.is.null,photo_url.like.%unsplash%,photo_url.eq.');
  }

  if (PRODUCT_LIMIT) {
    query = query.limit(PRODUCT_LIMIT);
  }

  const { data: products, error } = await query;

  if (error) {
    console.error('❌ Erro ao buscar produtos:', error.message);
    process.exit(1);
  }

  stats.total = products.length;
  console.log(`📋 Produtos a processar: ${stats.total}`);

  if (stats.total === 0) {
    console.log('✅ Nada a fazer!');
    return;
  }

  const estimatedCost = (stats.total * COST_PER_IMAGE).toFixed(2);
  console.log(`💰 Custo estimado: $${estimatedCost} USD`);
  console.log('');

  // Processar em batches
  for (let i = 0; i < products.length; i += BATCH_SIZE) {
    const batch = products.slice(i, i + BATCH_SIZE);
    const batchNum = Math.floor(i / BATCH_SIZE) + 1;
    const totalBatches = Math.ceil(products.length / BATCH_SIZE);

    console.log(`\n━━ Batch ${batchNum}/${totalBatches} ━━━━━━━━━━━━━━━━━━━━━━`);

    for (const product of batch) {
      await processProduct(product);
      if (!DRY_RUN) await sleep(DELAY_MS); // Rate limiting
    }

    console.log(`\n  ✔ Batch ${batchNum} completo | Done: ${stats.done} | Erros: ${stats.errors} | Custo até agora: $${stats.cost.toFixed(2)}`);
  }

  // Resumo final
  console.log('\n');
  console.log('╔════════════════════════════════════════════╗');
  console.log('║  RESUMO FINAL                              ║');
  console.log('╚════════════════════════════════════════════╝');
  console.log(`  Total processados : ${stats.done}`);
  console.log(`  Pulados           : ${stats.skipped}`);
  console.log(`  Erros             : ${stats.errors}`);
  console.log(`  Custo total       : $${stats.cost.toFixed(2)} USD`);
  console.log('');
}

main().catch((err) => {
  console.error('💥 Erro fatal:', err);
  process.exit(1);
});
