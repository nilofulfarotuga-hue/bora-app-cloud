require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const BATCH_SIZE = 100;
const BATCH_DELAY_MS = 150;

function normalizeQuery(name, category) {
  const normalized = (name + ' ' + (category || ''))
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')   // remove accents
    .replace(/[^a-z0-9\s]/g, '')       // remove special chars
    .trim()
    .replace(/\s+/g, '+');
  return encodeURIComponent(normalized.replace(/\+/g, ' ')).replace(/%20/g, '+');
}

function buildUnsplashUrl(name, category) {
  const query = normalizeQuery(name, category);
  return `https://source.unsplash.com/featured/400x300/?${query}`;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function run() {
  console.log('🚀 Iniciando preenchimento de photo_url com Unsplash...\n');

  let offset = 0;
  let totalProcessed = 0;
  let totalErrors = 0;
  let batchNum = 0;

  while (true) {
    // Fetch products without photo_url
    const { data: products, error: fetchError } = await supabase
      .from('products')
      .select('id, name, category')
      .or('photo_url.is.null,photo_url.eq.')
      .range(offset, offset + BATCH_SIZE - 1);

    if (fetchError) {
      console.error('❌ Erro ao buscar produtos:', fetchError.message);
      break;
    }

    if (!products || products.length === 0) {
      console.log('\n✅ Nenhum produto sem imagem restante.');
      break;
    }

    batchNum++;
    console.log(`📦 Batch ${batchNum}: processando ${products.length} produtos (offset ${offset})...`);

    const updates = products.map(p => ({
      id: p.id,
      photo_url: buildUnsplashUrl(p.name, p.category),
    }));

    // Update in sub-batches to avoid payload limits
    for (const update of updates) {
      const { error: updateError } = await supabase
        .from('products')
        .update({ photo_url: update.photo_url })
        .eq('id', update.id);

      if (updateError) {
        console.error(`  ⚠️  Erro ao atualizar produto ${update.id}: ${updateError.message}`);
        totalErrors++;
      } else {
        totalProcessed++;
      }
    }

    console.log(`  ✔ Batch ${batchNum} concluído. Total processados: ${totalProcessed}`);

    // If fewer results than batch size, we've hit the end
    if (products.length < BATCH_SIZE) break;

    offset += BATCH_SIZE;
    await sleep(BATCH_DELAY_MS);
  }

  console.log(`\n📊 Resumo:`);
  console.log(`   Produtos atualizados: ${totalProcessed}`);
  console.log(`   Erros: ${totalErrors}`);
  console.log(totalErrors === 0 ? '🎉 Concluído sem erros!' : '⚠️  Concluído com erros — verifique os logs acima.');
}

run().catch(err => {
  console.error('💥 Erro fatal:', err);
  process.exit(1);
});
