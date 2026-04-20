import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';

let _client = null;

export function getSupabase() {
  if (!_client) {
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_KEY;
    if (!url || !key || key.startsWith('eyJ...')) {
      throw new Error('SUPABASE_SERVICE_KEY não configurado em .env');
    }
    _client = createClient(url, key);
  }
  return _client;
}

/** Save products to local JSON backup */
export function saveBackup(siteName, products) {
  const dir = path.join(process.cwd(), 'output');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir);
  const file = path.join(dir, `${siteName}_${Date.now()}.json`);
  fs.writeFileSync(file, JSON.stringify(products, null, 2));
  console.log(`  💾 Backup guardado: ${file} (${products.length} produtos)`);
  return file;
}

/**
 * Insert products in batches of 50, skipping duplicates by (name, restaurant_id).
 * Returns { inserted, skipped, failed }
 */
export async function insertProducts(products, restaurantId) {
  const supabase = getSupabase();
  const BATCH = 50;
  let inserted = 0, skipped = 0, failed = 0;

  // Fetch existing names (paginated to bypass 1000-row default limit)
  console.log(`  🔍 A verificar duplicados para ${restaurantId}...`);
  let allExisting = [];
  let page = 0;
  const PAGE = 1000;
  while (true) {
    const { data, error } = await supabase
      .from('products')
      .select('name')
      .eq('restaurant_id', restaurantId)
      .range(page * PAGE, (page + 1) * PAGE - 1);
    if (error || !data || data.length === 0) break;
    allExisting.push(...data);
    if (data.length < PAGE) break;
    page++;
  }

  const existingNames = new Set(allExisting.map(r => r.name?.toLowerCase().trim()));
  console.log(`  ℹ️  ${existingNames.size} produtos já existentes no DB`);

  // Filter out duplicates
  const toInsert = products.filter(p => {
    const key = p.name?.toLowerCase().trim();
    return key && !existingNames.has(key);
  });

  skipped = products.length - toInsert.length;
  console.log(`  ➕ ${toInsert.length} novos produtos para inserir, ${skipped} duplicados ignorados`);

  // Insert in batches
  for (let i = 0; i < toInsert.length; i += BATCH) {
    const batch = toInsert.slice(i, i + BATCH).map(p => ({
      restaurant_id: restaurantId,
      name: p.name,
      description: p.description || null,
      photo_url: p.photo_url || null,
      price: p.price || null,
      category: p.category || 'Outros',
      unit: p.unit || null,
      is_available: true,
      is_popular: false,
      is_on_sale: p.is_on_sale || false,
      discount_price: p.discount_price || null,
      source: p.source || null,
    }));

    const { error } = await supabase.from('products').insert(batch);
    if (error) {
      console.error(`  ❌ Erro no batch ${i / BATCH + 1}: ${error.message}`);
      failed += batch.length;
    } else {
      inserted += batch.length;
      process.stdout.write(`\r  ✅ ${inserted}/${toInsert.length} inseridos...`);
    }
  }

  console.log(''); // newline after progress
  return { inserted, skipped, failed };
}
