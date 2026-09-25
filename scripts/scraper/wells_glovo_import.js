/**
 * Wells × Glovo Import — Sessão 2026-05-19
 *
 * Importa os 247 produtos extraídos do Glovo Wells Guarda (output JSON do
 * backfill anterior) como NOVAS entradas Wells em produtos.
 *
 * Regras:
 *   - price_db = glovo_price ÷ 1.15  (sistema aplica +15% via pricing_calculate)
 *   - source = 'glovo_guarda'
 *   - image_source = 'glovo'
 *   - is_available = true, needs_review = false
 *   - restaurant_id = 'wells-guarda'
 *
 * Dedup: normalize(name) vs produtos existentes — ignora duplicados, insere novos.
 *
 * Usage: cd bora_app/scripts/scraper && node wells_glovo_import.js
 */

import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  { auth: { persistSession: false } }
);

const RESTAURANT_ID = 'wells-guarda';
const SOURCE_TAG = 'glovo_guarda';
const MARKUP = 1.15;

function normalize(s) {
  return (s || '')
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

function classifyTaxonomy(name) {
  const n = normalize(name);
  if (/\b(creme|serum|hidrat|antirrug|antimanch|fotoprotetor|spf|fps|protetor solar|maquilhag|baton|rimel|pos all about|powder|highlighter|cleanance|effaclar|sebium|sensibio|toleriane|hyalu|niacinamida|tridolfin|antienv|firmeza|reermicilico|liftactiv|filler|elasticity|skinerie)/i.test(n)) return 'pharmacy_beauty';
  if (/\b(perfum|edt|eau de toilette|coloni|fragranc)/i.test(n)) return 'pharmacy_beauty';
  if (/\b(champo|champô|shampoo|condicionador|cabelo|escova|laca|spray.*cabelo)/i.test(n)) return 'pharmacy_beauty';
  if (/\b(vitamin|magnesi|suplement|omega|colagen|colageno|multivitamin|probioti)/i.test(n)) return 'pharmacy_vitamins';
  if (/\b(bebe|bebé|fralda|biberao|biberão|chupeta|infantil|babymilk|mama|mamã|seringa.*alimenta)/i.test(n)) return 'pharmacy_baby';
  if (/\b(sabonete|gel banho|desodorizant|desodorant|escova dent|pasta dent|dentifric|boca|tampon|penso)/i.test(n)) return 'pharmacy_hygiene';
  return 'pharmacy_otc';
}

function categoryRoot(taxonomy) {
  return {
    pharmacy_beauty: 'Beleza & Cuidados Pessoais',
    pharmacy_vitamins: 'Nutrição & Suplementos',
    pharmacy_baby: 'Bebé & Mama',
    pharmacy_hygiene: 'Higiene Pessoal',
    pharmacy_otc: 'Saúde',
  }[taxonomy] || 'Outros';
}

async function fetchExistingNames() {
  let all = [];
  let from = 0;
  const PAGE = 1000;
  while (true) {
    const { data, error } = await supabase
      .from('products')
      .select('name')
      .eq('restaurant_id', RESTAURANT_ID)
      .range(from, from + PAGE - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    all.push(...data);
    if (data.length < PAGE) break;
    from += PAGE;
  }
  return new Set(all.map(r => normalize(r.name)));
}

function loadLatestBackup() {
  const outDir = path.join(process.cwd(), 'output');
  const files = fs.readdirSync(outDir)
    .filter(f => f.startsWith('wells_glovo_'))
    .map(f => ({ name: f, size: fs.statSync(path.join(outDir, f)).size, mtime: fs.statSync(path.join(outDir, f)).mtimeMs }))
    .filter(f => f.size > 100)
    .sort((a, b) => b.mtime - a.mtime);
  if (files.length === 0) throw new Error('Nenhum backup wells_glovo_*.json encontrado em output/');
  const latest = files[0].name;
  console.log(`📦 Backup: ${latest} (${files[0].size} bytes)`);
  return JSON.parse(fs.readFileSync(path.join(outDir, latest), 'utf-8'));
}

async function main() {
  console.log('🎯 Wells × Glovo Import');
  console.log(`   Supabase: ${process.env.SUPABASE_URL}`);

  const glovoData = loadLatestBackup();
  console.log(`📊 Backup contém ${glovoData.length} produtos Glovo`);

  console.log(`🔍 A obter produtos Wells existentes...`);
  const existing = await fetchExistingNames();
  console.log(`   ${existing.size} produtos Wells já na DB`);

  // Dedup
  const seen = new Set();
  const candidates = [];
  for (const g of glovoData) {
    if (!g.name || !g.price || g.price <= 0) continue;
    const norm = normalize(g.name);
    if (existing.has(norm)) continue; // já existe no DB
    if (seen.has(norm)) continue; // dup dentro do batch
    seen.add(norm);
    candidates.push(g);
  }
  console.log(`✂️  Filtrados ${glovoData.length - candidates.length} duplicados/inválidos`);
  console.log(`➕ ${candidates.length} produtos novos para inserir`);

  if (candidates.length === 0) {
    console.log('Nada novo. Saindo.');
    return;
  }

  const today = new Date().toISOString().slice(0, 10);
  const rows = candidates.map(g => {
    const basePrice = +(g.price / MARKUP).toFixed(2);
    const taxonomy = classifyTaxonomy(g.name);
    return {
      restaurant_id: RESTAURANT_ID,
      name: g.name.trim(),
      description: null,
      photo_url: g.imageUrl || null,
      price: basePrice,
      category: categoryRoot(taxonomy),
      category_root: categoryRoot(taxonomy),
      taxonomy_section: taxonomy,
      image_source: 'glovo',
      source: SOURCE_TAG,
      unit: null,
      is_available: true,
      is_popular: false,
      is_on_sale: false,
      discount_price: null,
      needs_photo: !g.imageUrl,
      needs_review: false,
      last_updated: today,
    };
  });

  // Insert in batches of 50
  const BATCH = 50;
  let inserted = 0;
  let failed = 0;
  for (let i = 0; i < rows.length; i += BATCH) {
    const batch = rows.slice(i, i + BATCH);
    const { error } = await supabase.from('products').insert(batch);
    if (error) {
      failed += batch.length;
      console.warn(`  ❌ Lote ${i / BATCH + 1} falhou: ${error.message}`);
    } else {
      inserted += batch.length;
      console.log(`  ✅ ${inserted}/${rows.length} inseridos`);
    }
  }

  console.log(`\n📊 Inseridos: ${inserted} · Falhas: ${failed}`);
  console.log(`   Preços range: €${Math.min(...rows.map(r => r.price)).toFixed(2)} - €${Math.max(...rows.map(r => r.price)).toFixed(2)}`);
  console.log(`   Markup ÷ 1.15 aplicado · 15% será adicionado em runtime via pricing_calculate`);
}

main().catch(err => { console.error('💥', err); process.exit(1); });
