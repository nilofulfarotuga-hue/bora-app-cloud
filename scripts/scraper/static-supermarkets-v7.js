import 'dotenv/config';
import { insertProducts } from './lib/supabase.js';

// Apenas Intermarché — fechar gap de ~8 produtos para atingir 3000
const products = [
  { name: 'Tosta Mista Intermarché Congelada 2un', price: 2.49, category: 'Congelados', unit: '2un' },
  { name: 'Crepe Salgado Intermarché Presunto 2un', price: 2.99, category: 'Congelados', unit: '2un' },
  { name: 'Sumo Uva Branca Intermarché 1L', price: 1.09, category: 'Bebidas', unit: '1L' },
  { name: 'Limonada Intermarché 1.5L', price: 0.99, category: 'Bebidas', unit: '1.5L' },
  { name: 'Pão de Batata Intermarché 450g', price: 1.49, category: 'Padaria', unit: '450g' },
  { name: 'Farinha Trigo T65 Intermarché 1kg', price: 0.79, category: 'Mercearia', unit: '1kg' },
  { name: 'Açúcar Amarelo Intermarché 1kg', price: 1.29, category: 'Mercearia', unit: '1kg' },
  { name: 'Vinagre Vinho Branco Intermarché 750ml', price: 0.89, category: 'Mercearia', unit: '750ml' },
  { name: 'Molho Inglês Intermarché 150ml', price: 1.29, category: 'Mercearia', unit: '150ml' },
  { name: 'Pimentão Doce Intermarché 50g', price: 0.89, category: 'Mercearia', unit: '50g' },
].map(p => ({ ...p, description: null, is_on_sale: false, discount_price: null, source: 'static' }));

async function main() {
  console.log(`\n🛒 intermarche-guarda — ${products.length} produtos`);
  const { inserted, skipped, failed } = await insertProducts(products, 'intermarche-guarda');
  console.log(`  ✅ Inseridos: ${inserted} | Ignorados: ${skipped} | Falhas: ${failed}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
