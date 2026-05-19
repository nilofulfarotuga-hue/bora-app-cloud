/**
 * Bora App — Product Scraper
 * Usage:
 *   node scrape.js                    # all phases
 *   node scrape.js --only=continente  # single site
 *   node scrape.js --only=pingodoce
 *   node scrape.js --only=intermarche
 *   node scrape.js --only=mercadona
 *   node scrape.js --only=wells
 *   node scrape.js --only=mcdonalds
 *   node scrape.js --only=kfc
 *   node scrape.js --only=burgerking
 *   node scrape.js --only=pizzahut
 *   node scrape.js --only=restaurants  # all restaurant phases
 */
import 'dotenv/config';
import { launchBrowser } from './lib/browser.js';
import { saveBackup, insertProducts } from './lib/supabase.js';
import { scrapeContinente } from './scrapers/continente.js';
import { scrapePingodoce } from './scrapers/pingodoce.js';
import { scrapeIntermarche } from './scrapers/intermarche.js';
import { scrapeMercadona } from './scrapers/mercadona.js';
import { scrapeMcdonalds } from './scrapers/mcdonalds.js';
import { scrapeKfc } from './scrapers/kfc.js';
import { scrapeBurgerking } from './scrapers/burgerking.js';
import { scrapePizzahut } from './scrapers/pizzahut.js';
import { scrapeWells } from './scrapers/wells.js';

const MAX = parseInt(process.env.MAX_PRODUCTS_PER_SITE || '0') || Infinity;
const only = process.argv.find(a => a.startsWith('--only='))?.split('=')[1]?.toLowerCase();

const PHASES = [
  { key: 'continente',  fn: (b) => scrapeContinente(b, MAX) },
  { key: 'pingodoce',   fn: (b) => scrapePingodoce(b, MAX) },
  { key: 'intermarche', fn: (b) => scrapeIntermarche(b, MAX) },
  { key: 'mercadona',   fn: (b) => scrapeMercadona(b, MAX) },
  { key: 'wells',       fn: (b) => scrapeWells(b, MAX) },
  { key: 'mcdonalds',   fn: (b) => scrapeMcdonalds(b, MAX) },
  { key: 'kfc',         fn: (b) => scrapeKfc(b, MAX) },
  { key: 'burgerking',  fn: (b) => scrapeBurgerking(b, MAX) },
  { key: 'pizzahut',    fn: (b) => scrapePizzahut(b, MAX) },
];

async function main() {
  console.log('🚀 Bora App Scraper iniciado');
  console.log(`   Supabase: ${process.env.SUPABASE_URL || '⚠ não configurado'}`);

  const restaurantKeys = ['mcdonalds', 'kfc', 'burgerking', 'pizzahut'];
  const phases = only === 'restaurants'
    ? PHASES.filter(p => restaurantKeys.includes(p.key))
    : only
      ? PHASES.filter(p => p.key === only)
      : PHASES;

  if (phases.length === 0) {
    console.error(`❌ Site desconhecido: ${only}. Usa: continente, pingodoce, intermarche, mercadona, wells, mcdonalds, kfc, burgerking, pizzahut, restaurants`);
    process.exit(1);
  }

  const browser = await launchBrowser();
  const summary = [];

  for (const phase of phases) {
    const start = Date.now();
    let result = { inserted: 0, skipped: 0, failed: 0, products: 0 };

    try {
      const { products, restaurantId } = await phase.fn(browser);

      if (products.length === 0) {
        console.warn(`  ⚠ Nenhum produto encontrado para ${phase.key}`);
        summary.push({ site: phase.key, ...result, error: 'Sem produtos' });
        continue;
      }

      // 1. Save backup JSON
      saveBackup(phase.key, products);

      // 2. Insert to Supabase
      const stats = await insertProducts(products, restaurantId);
      result = { ...stats, products: products.length };

    } catch (err) {
      console.error(`\n❌ ERRO em ${phase.key}: ${err.message}`);
      result.error = err.message;
    }

    const elapsed = ((Date.now() - start) / 1000 / 60).toFixed(1);
    summary.push({ site: phase.key, ...result, elapsed: `${elapsed}m` });

    console.log(`\n📊 Relatório ${phase.key}:`);
    console.log(`   Produtos scrapeados : ${result.products}`);
    console.log(`   Inseridos no DB     : ${result.inserted}`);
    console.log(`   Duplicados ignorados: ${result.skipped}`);
    console.log(`   Falharam            : ${result.failed}`);
    console.log(`   Tempo               : ${elapsed} minutos`);
    if (result.error) console.log(`   Erro               : ${result.error}`);
  }

  await browser.close();

  console.log('\n═══════════════════════════════');
  console.log('📋 RELATÓRIO FINAL');
  console.log('═══════════════════════════════');
  for (const s of summary) {
    const status = s.error ? '❌' : '✅';
    console.log(`${status} ${s.site.padEnd(12)} | +${s.inserted} inseridos | ${s.skipped} duplicados | ${s.failed} falhas | ${s.elapsed || 'n/a'}`);
  }
  console.log('═══════════════════════════════');

  const totalInserted = summary.reduce((n, s) => n + (s.inserted || 0), 0);
  console.log(`\n🎉 Total inserido no Supabase: ${totalInserted} produtos`);
}

main().catch(err => {
  console.error('💥 Erro fatal:', err);
  process.exit(1);
});
