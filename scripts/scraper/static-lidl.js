// static-lidl.js — Gera e insere 3000+ produtos Lidl Portugal
import 'dotenv/config';
import { insertProducts } from './lib/supabase.js';

const RESTAURANT_ID = 'lidl-guarda';

const mk = (name, price, cat, unit = null) => ({
  name: name.trim(), price: +price.toFixed(2), category: cat, unit,
  description: null, photo_url: null, is_on_sale: false,
  discount_price: null, source: 'static-lidl',
});

// brand × [type, ...prices] × [size, priceIndex]
const tpl = (brand, types, sizes, cat) =>
  types.flatMap(([t, ...pr]) =>
    sizes.filter(([, i]) => pr[i] != null)
         .map(([sz, i]) => mk(`${brand ? brand + ' ' : ''}${t} ${sz}`, pr[i], cat, sz))
  );

// ═══════════════════════════════════════════════════════════════════
// 1. MERCEARIA (~550 produtos)
// ═══════════════════════════════════════════════════════════════════
const M = 'Mercearia';

const pasta = tpl('Combino', [
  ['Esparguete',0.49,0.89,1.69,2.99],['Esparguete Fino',0.49,0.89,null,null],
  ['Esparguete Grosso',0.55,0.99,null,null],['Penne',0.49,0.89,1.69,2.99],
  ['Penne Rigate',0.49,0.89,null,null],['Fusilli',0.49,0.89,1.69,2.99],
  ['Farfalle',0.55,0.99,null,null],['Rigatoni',0.55,0.99,null,null],
  ['Tagliatelle',0.59,0.99,null,null],['Linguine',0.59,0.99,null,null],
  ['Conchiglie',0.49,0.89,null,null],['Gomiti',0.49,0.89,null,null],
  ['Orecchiette',0.65,1.09,null,null],['Ditali',0.49,0.89,null,null],
  ['Lasanha',0.89,1.59,null,null],
], [['500g',0],['1kg',1],['2kg',2],['5kg',3]], M);

const arroz = tpl('Combino', [
  ['Arroz Agulha',0.79,1.49,3.29],['Arroz Carolino',0.89,1.65,3.59],
  ['Arroz Basmati',1.19,2.19,4.39],['Arroz Integral',0.99,1.79,3.79],
  ['Arroz Parboilizado',0.89,1.69,3.49],['Arroz Jasmine',1.29,2.39,null],
  ['Arroz Arbóreo',1.59,2.89,null],['Arroz Sushi',1.99,null,null],
  ['Arroz Vermelho',1.29,null,null],['Arroz Negro',1.49,null,null],
  ['Arroz Selvagem Mix',1.59,null,null],['Arroz Bio',1.49,2.79,null],
], [['1kg',0],['2kg',1],['5kg',2]], M);

const pastaSpec = tpl('Combino', [
  ['Penne Integral',0.79,1.39],['Fusilli Integral',0.79,1.39],
  ['Esparguete Integral',0.79,1.39],['Penne Sem Glúten',1.19,1.99],
  ['Fusilli Sem Glúten',1.19,1.99],['Esparguete Sem Glúten',1.19,1.99],
], [['500g',0],['1kg',1]], M);

const noodles = tpl('Vitasia', [
  ['Noodles Udon',1.29,2.49],['Noodles Ramen',0.99,1.79],
  ['Noodles Soba',1.49,2.59],['Noodles Vidro',1.19,2.19],
  ['Noodles Arroz',0.99,1.79],['Noodles Yakisoba',1.39,2.49],
  ['Noodles Tom Yum',1.29,null],['Noodles Curry',1.29,null],
], [['200g',0],['400g',1]], M);

const tomate = tpl('Orlando', [
  ['Tomate Pelado',0.39,0.69],['Tomate Polpa',0.35,0.65],
  ['Tomate Triturado',0.45,0.79],['Tomate Concentrado',0.49,0.89],
  ['Tomate Cereja Pelado',0.59,0.99],['Tomate Manjericão',0.49,0.89],
  ['Tomate Orégãos',0.49,0.89],['Molho Basilico',0.55,0.99],
  ['Molho Arrabiata',0.55,0.99],['Molho Puttanesca',0.59,1.09],
  ['Molho Amatriciana',0.59,1.09],['Molho Carbonara',0.65,1.19],
  ['Molho Bolonhesa',0.69,1.29],['Molho Genovesa',0.55,0.99],
  ['Tomate Frito',0.39,0.69],
], [['400g',0],['800g',1]], M);

const leguminosas = tpl('Combino', [
  ['Feijão Vermelho',0.45,0.85],['Feijão Branco',0.45,0.85],
  ['Feijão Preto',0.45,0.85],['Feijão Manteiga',0.49,0.89],
  ['Feijão Frade',0.49,0.89],['Grão de Bico',0.49,0.89],
  ['Lentilhas Vermelhas',0.55,0.99],['Lentilhas Castanhas',0.55,0.99],
  ['Lentilhas Verdes',0.59,1.09],['Ervilhas Cozidas',0.45,0.79],
  ['Milho Cozido',0.49,0.89],['Mix Leguminosas',0.59,1.09],
], [['400g',0],['800g',1]], M);

const cereais = tpl('Crownfield', [
  ['Cornflakes Natural',1.29,1.99],['Cornflakes Mel',1.49,2.29],
  ['Cornflakes Chocolate',1.49,2.29],['Muesli Clássico',1.79,2.99],
  ['Muesli Frutas',1.99,3.29],['Muesli Nozes',1.99,3.29],
  ['Porridge Aveia Natural',1.19,1.89],['Porridge Aveia Frutas',1.39,2.19],
  ['Granola Mel',1.99,3.49],['Granola Frutas Vermelhas',1.99,3.49],
  ['Granola Chocolate',1.99,3.49],['Flocos Aveia',0.99,1.79],
  ['Cereais Chocolate Kids',1.29,2.19],['Cereais Mel Nozes',1.49,2.49],
  ['Cereais Fitness',1.49,2.49],['Cereais Fibra',1.39,2.29],
  ['Granola Bio',2.29,3.99],['Granola Sem Glúten',2.29,3.99],
  ['Cereais Grãos Ancestrais',1.79,2.99],['Cereais Frutos Vermelhos',1.59,2.69],
], [['500g',0],['1kg',1]], M);

const bolachas = tpl('Sondey', [
  ['Digestivas',0.89,1.49],['Digestivas Chocolate',0.99,1.59],
  ['Digestivas Aveia',0.89,1.49],['Cream Crackers',0.69,1.19],
  ['Crackers Cereais',0.79,1.29],['Crackers Sésamo',0.79,1.29],
  ['Amanteigadas',0.99,1.69],['Shortbread',1.19,1.99],
  ['Bolachas Limão',0.99,1.59],['Bolachas Coco',0.99,1.59],
  ['Wafers Chocolate',0.89,1.49],['Wafers Baunilha',0.89,1.49],
  ['Wafers Avelã',0.99,1.59],['Recheadas Chocolate',0.99,1.69],
  ['Recheadas Baunilha',0.99,1.69],['Recheadas Morango',0.99,1.69],
  ['Bolachas Maria',0.59,0.99],['Rice Cakes Natural',0.79,null],
  ['Rice Cakes Chocolate',0.89,null],['Bolachas Integrais Aveia',1.09,1.79],
  ['Fig Rolls',0.99,1.69],['Bolachas Arandos',1.09,1.79],
], [['200g',0],['400g',1]], M);

const snacks = tpl('Mcennedy', [
  ['Pretzels Natural',0.99,1.79],['Pretzels Queijo',1.09,1.99],
  ['Corn Chips Natural',0.99,1.79],['Corn Chips Queijo',0.99,1.79],
  ['Corn Chips Picantes',0.99,1.79],['Popcorn Manteiga',0.99,1.79],
  ['Popcorn Caramelo',0.99,1.79],['Chips Sal',0.89,1.59],
  ['Chips Paprika',0.89,1.59],['Chips BBQ',0.99,1.79],
  ['Chips Sour Cream',0.99,1.79],['Tortilla Chips Natural',0.99,1.79],
  ['Tortilla Chips Queijo',0.99,1.79],['Peanut Butter Cups',1.29,2.49],
  ['Beef Jerky',2.49,4.49],
], [['150g',0],['300g',1]], M);

const belbake = tpl('Belbake', [
  ['Farinha Trigo T55',0.49,0.89],['Farinha Trigo T65',0.55,0.99],
  ['Farinha Integral',0.65,1.19],['Farinha Centeio',0.79,1.39],
  ['Farinha Espelta',0.89,1.59],['Farinha Sem Glúten',1.29,2.29],
  ['Farinha Milho',0.69,1.19],['Açúcar Branco',0.79,1.49],
  ['Açúcar Amarelo',0.89,1.59],['Açúcar Mascavado',0.99,null],
  ['Açúcar em Pó',0.89,null],['Açúcar de Coco',1.49,null],
  ['Cacau em Pó',1.09,null],['Chocolate Culinária',1.29,null],
  ['Gotas Chocolate Negro',1.49,null],
], [['1kg',0],['2kg',1]], M);

const cafe_cha = [
  mk('Bellarom Café Moído Clássico 250g',1.79,M,'250g'),
  mk('Bellarom Café Moído Forte 250g',1.79,M,'250g'),
  mk('Bellarom Café Moído Suave 250g',1.79,M,'250g'),
  mk('Bellarom Café Moído Descafeinado 250g',2.19,M,'250g'),
  mk('Bellarom Café em Grão 500g',3.99,M,'500g'),
  mk('Bellarom Café em Grão Forte 500g',4.29,M,'500g'),
  mk('Bellarom Café Instantâneo 200g',2.49,M,'200g'),
  mk('Bellarom Café Instantâneo 100g',1.49,M,'100g'),
  mk('Bellarom Café 3in1 10x17g',1.99,M,'10x17g'),
  mk('Bellarom Cápsulas Espresso x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Forte x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Suave x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Ristretto x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Descafeinado x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas DG Espresso x16',2.99,M,'16 cápsulas'),
  mk('Bellarom Cápsulas DG Latte x16',2.99,M,'16 cápsulas'),
  mk('Bellarom Cappuccino Instantâneo 8x15g',1.49,M,'8x15g'),
  mk('Bellarom Latte Macchiato 8x18g',1.49,M,'8x18g'),
  mk('Deluxe Café Bio Arabica 250g',3.49,M,'250g'),
  mk('Deluxe Café Single Origin Etiópia 250g',3.99,M,'250g'),
  mk('Delta Café Moído 250g',2.79,M,'250g'),
  mk('Jacobs Café Moído 250g',2.99,M,'250g'),
  mk('Chá Verde Lidl 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Verde Limão 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Verde Gengibre 20 saquetas',1.09,M,'20 saquetas'),
  mk('Chá Preto English Breakfast 25 saquetas',0.99,M,'25 saquetas'),
  mk('Chá Preto Earl Grey 25 saquetas',0.99,M,'25 saquetas'),
  mk('Chá Preto Assam 25 saquetas',0.99,M,'25 saquetas'),
  mk('Chá Camomila 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Hortelã 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Tília 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Frutos Vermelhos 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Pêssego 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Branco 20 saquetas',1.19,M,'20 saquetas'),
  mk('Chá Rooibos Natural 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Rooibos Baunilha 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Digestivo 20 saquetas',1.09,M,'20 saquetas'),
  mk('Chá Relaxante Noite 20 saquetas',1.09,M,'20 saquetas'),
  mk('Chá Bio Verde 20 saquetas',1.49,M,'20 saquetas'),
  mk('Chá Bio Ervas 20 saquetas',1.49,M,'20 saquetas'),
  mk('Deluxe Chá Premium 25 saquetas',1.99,M,'25 saquetas'),
];

const mercearia_misc = [
  mk('Azeite Virgem Extra Lidl 500ml',2.19,M,'500ml'),
  mk('Azeite Virgem Extra Lidl 750ml',2.99,M,'750ml'),
  mk('Azeite Virgem Extra Lidl 1L',4.49,M,'1L'),
  mk('Azeite Virgem Extra Lidl 2L',8.49,M,'2L'),
  mk('Deluxe Azeite Premium 500ml',4.99,M,'500ml'),
  mk('Eridanous Azeite Grego 750ml',4.49,M,'750ml'),
  mk('Italiamo Azeite Italiano 500ml',3.99,M,'500ml'),
  mk('Óleo Girassol Lidl 1L',1.59,M,'1L'),
  mk('Óleo Girassol Lidl 2L',2.99,M,'2L'),
  mk('Óleo Girassol Lidl 5L',6.99,M,'5L'),
  mk('Óleo Coco Lidl 500ml',2.99,M,'500ml'),
  mk('Óleo Sésamo Vitasia 250ml',2.49,M,'250ml'),
  mk('Ketchup Lidl 800ml',0.99,M,'800ml'),
  mk('Ketchup Lidl 450g',0.65,M,'450g'),
  mk('Maionese Lidl 500ml',0.99,M,'500ml'),
  mk('Maionese Lidl 930ml',1.69,M,'930ml'),
  mk('Mostarda Dijon 200g',0.79,M,'200g'),
  mk('Mostarda Amarela 250g',0.69,M,'250g'),
  mk('Deluxe Mostarda Grão 200g',1.49,M,'200g'),
  mk('Vitasia Molho Soja 150ml',0.89,M,'150ml'),
  mk('Vitasia Molho Soja Baixo Sal 150ml',0.99,M,'150ml'),
  mk('Vitasia Molho Teriyaki 150ml',0.99,M,'150ml'),
  mk('Vitasia Sweet Chili 200ml',0.99,M,'200ml'),
  mk('Vitasia Molho Ostras 150ml',0.99,M,'150ml'),
  mk('Vitasia Pasta Curry Vermelho 100g',1.29,M,'100g'),
  mk('Vitasia Pasta Curry Verde 100g',1.29,M,'100g'),
  mk('Vitasia Pasta Miso 300g',1.99,M,'300g'),
  mk('Mcennedy Molho BBQ 500ml',0.99,M,'500ml'),
  mk('Mcennedy Molho Ranch 250ml',1.19,M,'250ml'),
  mk('Molho Caesar Lidl 250ml',1.09,M,'250ml'),
  mk('Mcennedy Salsa Mexicana 340g',0.99,M,'340g'),
  mk('Mcennedy Guacamole 200g',1.49,M,'200g'),
  mk('Italiamo Pesto Genovesa 190g',1.49,M,'190g'),
  mk('Italiamo Pesto Rosso 190g',1.49,M,'190g'),
  mk('Eridanous Hummus Natural 200g',1.49,M,'200g'),
  mk('Eridanous Hummus Pimento 200g',1.49,M,'200g'),
  mk('Eridanous Tzatziki 200g',1.29,M,'200g'),
  mk('Mel Lidl Multifloral 500g',3.49,M,'500g'),
  mk('Mel Lidl Acácia 500g',3.99,M,'500g'),
  mk('Mel Lidl Silvestre 250g',2.49,M,'250g'),
  mk('Atum em Água Lidl 3x80g',1.49,M,'3x80g'),
  mk('Atum em Azeite Lidl 3x80g',1.79,M,'3x80g'),
  mk('Atum Natural Lidl 160g',0.89,M,'160g'),
  mk('Sardinha em Óleo Lidl 125g',0.69,M,'125g'),
  mk('Sardinha em Tomate Lidl 125g',0.69,M,'125g'),
  mk('Sardinha Picante Lidl 125g',0.79,M,'125g'),
  mk('Cavala em Óleo Lidl 125g',0.59,M,'125g'),
  mk('Polvo em Azeite Lidl 120g',1.49,M,'120g'),
  mk('Salmão em Óleo Lidl 185g',1.99,M,'185g'),
  mk('Deluxe Atum Ventresca 110g',3.49,M,'110g'),
  mk('Eridanous Azeitonas Kalamata 185g',0.99,M,'185g'),
  mk('Sol & Mar Azeitonas Verdes 185g',0.79,M,'185g'),
  mk('Sol & Mar Azeitonas Pretas 185g',0.79,M,'185g'),
  mk('Italiamo Alcaparras 100g',0.99,M,'100g'),
  mk('Eridanous Pimentos Grelhados 280g',1.29,M,'280g'),
  mk('Sal Fino Lidl 1kg',0.25,M,'1kg'),
  mk('Sal Grosso Lidl 1kg',0.25,M,'1kg'),
  mk('Sal Marinho Lidl 500g',0.49,M,'500g'),
  mk('Sal Rosa Himalaia 500g',0.99,M,'500g'),
  mk('Pimenta Preta Moída 40g',0.59,M,'40g'),
  mk('Pimenta em Grão 45g',0.69,M,'45g'),
  mk('Mix 5 Pimentas 40g',0.79,M,'40g'),
  mk('Paprika Doce 50g',0.59,M,'50g'),
  mk('Paprika Fumada 50g',0.69,M,'50g'),
  mk('Piri-Piri Moído 40g',0.59,M,'40g'),
  mk('Cúrcuma 50g',0.59,M,'50g'),
  mk('Cominhos Lidl 30g',0.59,M,'30g'),
  mk('Orégãos Lidl 15g',0.49,M,'15g'),
  mk('Tomilho Lidl 15g',0.49,M,'15g'),
  mk('Louro Lidl 5g',0.49,M,'5g'),
  mk('Alecrim Lidl 15g',0.49,M,'15g'),
  mk('Cebola Granulada 60g',0.59,M,'60g'),
  mk('Alho Granulado 60g',0.59,M,'60g'),
  mk('Canela Moída 30g',0.59,M,'30g'),
  mk('Noz Moscada 30g',0.59,M,'30g'),
  mk('Caril Lidl 40g',0.59,M,'40g'),
  mk('Mix Ervas Provença 30g',0.59,M,'30g'),
  mk('Mix Ervas Italianas 20g',0.49,M,'20g'),
  mk('Garam Masala 40g',0.69,M,'40g'),
  mk('Gengibre Moído 30g',0.59,M,'30g'),
  mk('Açafrão Lidl 0.4g',0.99,M,'0.4g'),
  mk('Colorau Doce Lidl 40g',0.49,M,'40g'),
  mk('Mix Tempero Frango 50g',0.69,M,'50g'),
  mk('Amendoins Tostados 200g',0.99,M,'200g'),
  mk('Amendoins Salgados 200g',0.99,M,'200g'),
  mk('Amêndoas Naturais 200g',2.49,M,'200g'),
  mk('Cajus Lidl 150g',2.99,M,'150g'),
  mk('Nozes Lidl 200g',2.49,M,'200g'),
  mk('Pistácios Lidl 150g',2.99,M,'150g'),
  mk('Avelãs Lidl 200g',1.99,M,'200g'),
  mk('Mix Frutos Secos Lidl 200g',2.49,M,'200g'),
  mk('Passas de Uva 250g',0.99,M,'250g'),
  mk('Damascos Secos 250g',1.49,M,'250g'),
  mk('Tâmaras Lidl 200g',1.99,M,'200g'),
  mk('Ameixas Secas 500g',2.49,M,'500g'),
  mk('Sementes Chia 250g',1.99,M,'250g'),
  mk('Sementes Linhaça 400g',0.99,M,'400g'),
  mk('Sementes Sésamo 200g',0.89,M,'200g'),
  mk('Eridanous Queijo Feta 200g',1.59,M,'200g'),
  mk('Eridanous Iogurte Grego 500g',1.29,M,'500g'),
  mk('Eridanous Mel Grego 450g',4.49,M,'450g'),
  mk('Eridanous Folhas de Uva 280g',1.49,M,'280g'),
  mk('Eridanous Spanakopita 400g',2.49,M,'400g'),
  mk('Eridanous Gyros Temperado 400g',3.49,M,'400g'),
  mk('Italiamo Passata di Pomodoro 690g',0.89,M,'690g'),
  mk('Italiamo Gnocchi 500g',0.99,M,'500g'),
  mk('Italiamo Risotto Funghi Porcini 250g',1.99,M,'250g'),
  mk('Italiamo Polenta 500g',0.99,M,'500g'),
  mk('Italiamo Grissini 150g',0.89,M,'150g'),
  mk('Italiamo Vinagre Balsâmico 500ml',1.99,M,'500ml'),
  mk('Italiamo Cantucci Mandorla 200g',1.79,M,'200g'),
  mk('Italiamo Tagliatelle Ovos 250g',1.29,M,'250g'),
  mk('Vitasia Leite Coco 400ml',0.99,M,'400ml'),
  mk('Vitasia Pasta Amendoim 350g',2.49,M,'350g'),
  mk('Vitasia Molho Hoisin 200ml',1.29,M,'200ml'),
  mk('Vitasia Vinagre Arroz 500ml',1.49,M,'500ml'),
  mk('Sopa Tomate Lidl 400ml',0.65,M,'400ml'),
  mk('Sopa Legumes Lidl 400ml',0.65,M,'400ml'),
  mk('Sopa Minestrone Lidl 400ml',0.65,M,'400ml'),
  mk('Sopa Creme Abóbora Lidl 400ml',0.69,M,'400ml'),
  mk('Sopa Creme Cogumelos Lidl 400ml',0.69,M,'400ml'),
  mk('Sopa Caldo Verde Lidl 400ml',0.69,M,'400ml'),
  mk('Caldo Galinha Lidl 500ml',0.79,M,'500ml'),
  mk('Caldo Legumes Lidl 500ml',0.79,M,'500ml'),
  mk('Vinagre de Vinho Tinto 500ml',0.69,M,'500ml'),
  mk('Vinagre de Sidra 500ml',0.99,M,'500ml'),
  mk('Spray Cozinha Lidl 250ml',1.99,M,'250ml'),
  mk('Belbake Fermento em Pó 3x15g',0.59,M,'3x15g'),
  mk('Belbake Fermento Panificação 42g',0.35,M,'42g'),
  mk('Belbake Baunilha Açúcar 8x8g',0.69,M,'8x8g'),
  mk('Belbake Extrato Baunilha 50ml',1.29,M,'50ml'),
  mk('Belbake Gotas Chocolate Branco 200g',1.49,M,'200g'),
  mk('Combino Arroz Rápido Basmati 3x125g',1.29,M,'3x125g'),
  mk('Combino Arroz Rápido Integral 3x125g',1.39,M,'3x125g'),
  mk('Combino Arroz Rápido com Legumes 3x125g',1.49,M,'3x125g'),
  mk('Deluxe Mel Premium 250g',3.99,M,'250g'),
  mk('Xarope Agave Bio 250ml',1.99,M,'250ml'),
  mk('Xarope Bordo 250ml',2.49,M,'250ml'),
];

const MERCEARIA = [...pasta,...arroz,...pastaSpec,...noodles,...tomate,...leguminosas,
  ...cereais,...bolachas,...snacks,...belbake,...cafe_cha,...mercearia_misc];

// ═══════════════════════════════════════════════════════════════════
// 2. FRESCOS (~320 produtos)
// ═══════════════════════════════════════════════════════════════════
const FR = 'Frescos';

const frutas = tpl('', [
  ['Maçã Royal Gala',1.49,2.89],['Maçã Golden',1.49,2.89],
  ['Maçã Pink Lady',1.79,3.49],['Pera Rocha',1.69,3.29],
  ['Laranja Mesa',1.29,2.49],['Laranja Sumo',1.29,2.49],
  ['Tangerina',1.49,2.89],['Limão',0.89,1.69],
  ['Lima',0.89,1.69],['Banana',1.19,2.19],
  ['Uva Branca s/Grainha',2.49,4.89],['Uva Tinta s/Grainha',2.49,4.89],
  ['Kiwi Verde',1.49,2.89],['Kiwi Amarelo',1.99,3.79],
  ['Pêssego',1.99,3.79],['Nectarina',1.99,3.79],
  ['Ameixa',2.29,4.29],['Clementina',1.49,2.89],
], [['1kg',0],['2kg',1]], FR);

const frutas_unit = [
  mk('Morangos 500g',1.99,FR,'500g'), mk('Morangos 1kg',3.49,FR,'1kg'),
  mk('Framboesas 125g',1.99,FR,'125g'), mk('Mirtilo 125g',1.99,FR,'125g'),
  mk('Mirtilo 250g',3.49,FR,'250g'), mk('Cerejas 500g',3.99,FR,'500g'),
  mk('Manga Unidade',1.49,FR,'unidade'), mk('Abacaxi Unidade',1.49,FR,'unidade'),
  mk('Melão Pele de Sapo Unidade',1.49,FR,'unidade'), mk('Melancia Unidade',2.99,FR,'unidade'),
  mk('Papaia Unidade',2.49,FR,'unidade'), mk('Romã Unidade',1.49,FR,'unidade'),
  mk('Coco Inteiro',1.49,FR,'unidade'), mk('Abacate Hass Unidade',0.89,FR,'unidade'),
  mk('Dióspiro Unidade',0.99,FR,'unidade'), mk('Figo Fresco 500g',2.49,FR,'500g'),
  mk('Maracujá 3un',1.49,FR,'3 unidades'),
];

const legumes = tpl('', [
  ['Cenoura',0.79,1.49],['Batata Branca',0.89,1.59],
  ['Batata Doce',1.29,2.49],['Cebola',0.79,1.49],
  ['Tomate Redondo',1.29,2.49],['Tomate Cherry',1.99,null],
  ['Tomate Rama',1.49,null],['Pepino',0.89,null],
  ['Alface Iceberg',0.89,null],['Alface Frisada',0.89,null],
  ['Espinafres',1.29,null],['Couve Branca',0.99,1.89],
  ['Couve Roxa',1.09,1.99],['Couve-Flor',1.49,null],
  ['Brócolos',1.49,null],['Alho Francês',1.09,null],
  ['Beringela',1.09,null],['Courgette',0.89,null],
  ['Pimento Verde',0.99,null],['Pimento Vermelho',1.29,null],
  ['Pimento Amarelo',1.29,null],['Cogumelos Paris Brancos',1.49,null],
  ['Cogumelos Paris Castanhos',1.59,null],['Alho Cabeça',0.89,null],
  ['Nabo',0.69,null],['Aipo',0.99,null],
], [['1kg',0],['2kg',1]], FR);

const legumes_emb = [
  mk('Salada Mix Lidl 200g',1.09,FR,'200g'),
  mk('Salada Rúcula Lidl 100g',0.99,FR,'100g'),
  mk('Salada Baby Espinafres 100g',1.09,FR,'100g'),
  mk('Salada Canónigos 100g',1.29,FR,'100g'),
  mk('Ervas Aromáticas Manjericão em Vaso',1.49,FR,'vaso'),
  mk('Ervas Aromáticas Salsa em Vaso',1.49,FR,'vaso'),
  mk('Ervas Aromáticas Coentros em Vaso',1.49,FR,'vaso'),
  mk('Ervas Aromáticas Tomilho em Vaso',1.49,FR,'vaso'),
  mk('Ervas Aromáticas Alecrim em Vaso',1.49,FR,'vaso'),
  mk('Cogumelos Shiitake Frescos 200g',2.99,FR,'200g'),
  mk('Cogumelos Pleurotus 200g',2.49,FR,'200g'),
  mk('Cogumelos Mix Frescos 200g',2.99,FR,'200g'),
  mk('Tofu Natural 400g',1.99,FR,'400g'),
  mk('Tofu Fumado 200g',2.29,FR,'200g'),
  mk('Tofu Seda 349g',1.99,FR,'349g'),
  mk('Tempeh 200g',2.99,FR,'200g'),
];

const carne = tpl('', [
  ['Peito Frango sem Pele',4.99,8.99],
  ['Coxa Frango com Pele',2.99,5.49],
  ['Frango Inteiro',3.49,null],
  ['Peru Escalopes',4.99,null],
  ['Peru Peito Fatias',3.99,null],
  ['Vaca Carne Picada',3.99,6.99],
  ['Vaca Bife Alcatra',6.99,null],
  ['Vaca Escalopes',5.99,null],
  ['Vaca Carne Guisar',4.49,null],
  ['Vaca Entrecosto',4.99,null],
  ['Porco Entrecosto',3.99,6.99],
  ['Porco Lombinhos',4.99,null],
  ['Porco Costeleta',3.49,5.99],
  ['Porco Carne Picada',3.29,5.49],
  ['Porco Toucinho',1.99,null],
  ['Borrego Costeletas',6.99,null],
  ['Borrego Perna',8.99,null],
  ['Coelho Inteiro',4.99,null],
], [['500g',0],['1kg',1]], FR);

const peixe = tpl('', [
  ['Salmão Filetes',7.99,null],
  ['Salmão Postas',6.99,null],
  ['Bacalhau Demolhado',6.99,null],
  ['Pescada Filetes',4.99,8.99],
  ['Faneca Filetes',3.99,null],
  ['Pargo Inteiro',4.99,null],
  ['Dourada Inteira',4.99,null],
  ['Robalo Inteiro',5.99,null],
  ['Camarão Tigre',9.99,null],
  ['Camarão Médio',5.99,null],
  ['Gambas Peladas',8.99,null],
  ['Amêijoas',5.99,null],
  ['Mexilhão',2.99,null],
  ['Lulas Limpas',5.49,null],
  ['Polvo Inteiro',4.99,null],
], [['400g',0],['800g',1]], FR);

const charcutaria = tpl('', [
  ['Fiambre Peito Peru Fatiado',2.49,null],
  ['Fiambre Porco Fatiado',1.99,null],
  ['Fiambre Queijo Fatiado',2.29,null],
  ['Mortadela Clássica',1.49,null],
  ['Mortadela Azeitonas',1.59,null],
  ['Chouriço de Carne',2.99,null],
  ['Salpicão',3.49,null],
  ['Paio',2.99,null],
  ['Presunto Fatiado',3.49,null],
  ['Deluxe Presunto Pata Negra',5.99,null],
  ['Bacon Fatiado',2.49,null],
  ['Salame Milano',2.49,null],
  ['Salame Picante',2.49,null],
  ['Chorizo Espanhol',2.49,null],
  ['Pepperoni Fatiado',2.29,null],
  ['Prosciutto Cotto Italiamo',2.99,null],
], [['150g',0]], FR);

const FRESCOS = [...frutas,...frutas_unit,...legumes,...legumes_emb,...carne,...peixe,...charcutaria];

// ═══════════════════════════════════════════════════════════════════
// 3. LATICÍNIOS (~250 produtos)
// ═══════════════════════════════════════════════════════════════════
const L = 'Laticínios';

const leite = tpl('Milbona', [
  ['Leite Meio-Gordo',0.69,1.29,2.39],
  ['Leite Gordo',0.72,1.35,2.49],
  ['Leite Magro',0.65,1.19,2.19],
  ['Leite s/Lactose',0.99,1.89,null],
  ['Leite Cálcio',0.79,1.49,null],
  ['Leite Crescimento 1',1.49,null,null],
  ['Leite Crescimento 2',1.49,null,null],
  ['Leite Crescimento 3',1.49,null,null],
], [['1L',0],['2L',1],['6x1L',2]], L);

const iogurtes = tpl('Milbona', [
  ['Iogurte Natural',0.45,0.85,1.59],
  ['Iogurte Natural s/Açúcar',0.49,0.89,1.69],
  ['Iogurte Natural Magro',0.45,0.85,null],
  ['Iogurte Grego Natural',0.79,1.39,null],
  ['Iogurte Grego Mel',0.89,null,null],
  ['Iogurte Grego Morango',0.89,null,null],
  ['Iogurte Grego Pêssego',0.89,null,null],
  ['Iogurte Morango',0.55,0.99,null],
  ['Iogurte Framboesa',0.55,0.99,null],
  ['Iogurte Mirtilo',0.55,0.99,null],
  ['Iogurte Pêssego',0.55,0.99,null],
  ['Iogurte Cereja',0.55,0.99,null],
  ['Iogurte Maracujá',0.55,0.99,null],
  ['Iogurte Tropical',0.55,0.99,null],
  ['Iogurte Banana',0.55,0.99,null],
  ['Iogurte Cremoso Morango',0.69,1.19,null],
  ['Iogurte Cremoso Baunilha',0.69,1.19,null],
  ['Iogurte Kremoso Caramelo',0.69,1.19,null],
  ['Iogurte para Beber Morango',0.59,null,null],
  ['Iogurte para Beber Pêssego',0.59,null,null],
], [['125g',0],['4x125g',1],['8x125g',2]], L);

const queijos = tpl('Milbona', [
  ['Queijo Mozarella Fresco',1.29,null],
  ['Queijo Mozarella Rallado',1.49,2.49],
  ['Queijo Emmental Fatiado',1.99,3.49],
  ['Queijo Gouda Fatiado',1.79,2.99],
  ['Queijo Edam Fatiado',1.79,2.99],
  ['Queijo Cheddar Fatiado',1.99,null],
  ['Queijo Parmesão Rallado',1.99,null],
  ['Queijo Ricotta',1.29,null],
  ['Queijo Creme',1.49,2.49],
  ['Queijo para Barrar',0.99,1.79],
  ['Queijo Fundido Fatiado',1.49,null],
  ['Queijo Bola',2.99,null],
], [['150g',0],['300g',1]], L);

const queijos_especiais = [
  mk('Queijo Serra da Estrela Lidl 200g',4.99,L,'200g'),
  mk('Queijo Serrano Curado 200g',3.49,L,'200g'),
  mk('Queijo Manchego Lidl 200g',3.99,L,'200g'),
  mk('Queijo Brie Lidl 125g',1.99,L,'125g'),
  mk('Queijo Camembert Lidl 250g',2.49,L,'250g'),
  mk('Deluxe Queijo Manchego Curado 200g',4.99,L,'200g'),
  mk('Deluxe Queijo Comté 200g',4.49,L,'200g'),
  mk('Deluxe Queijo Gruyère Rallado 150g',2.49,L,'150g'),
  mk('Deluxe Queijo Parmigiano Reggiano 100g',2.99,L,'100g'),
  mk('Eridanous Queijo Feta 400g',2.99,L,'400g'),
  mk('Queijo Fresco Lidl 250g',1.19,L,'250g'),
  mk('Queijo Fresco Lidl 500g',1.99,L,'500g'),
  mk('Requeijão Lidl 200g',0.89,L,'200g'),
  mk('Requeijão com Natas 200g',1.19,L,'200g'),
];

const manteiga_natas = tpl('Milbona', [
  ['Manteiga sem Sal',1.29,2.49],
  ['Manteiga com Sal',1.29,2.49],
  ['Manteiga Ligeira',1.39,null],
  ['Margarina',0.99,1.79],
  ['Natas Cozinhar UHT',0.79,null],
  ['Natas Bater',0.89,null],
  ['Crème Fraîche',0.99,null],
], [['250g',0],['500g',1]], L);

const ovos_vegetais = [
  mk('Ovos M Lidl 6un',1.09,L,'6 unidades'),
  mk('Ovos M Lidl 10un',1.69,L,'10 unidades'),
  mk('Ovos M Lidl 15un',2.29,L,'15 unidades'),
  mk('Ovos XL Lidl 6un',1.29,L,'6 unidades'),
  mk('Ovos Bio Lidl 6un',1.79,L,'6 unidades'),
  mk('Ovos Galinhas Criação Livre 6un',1.49,L,'6 unidades'),
  mk('Alpro Leite Soja 1L',1.49,L,'1L'),
  mk('Alpro Leite Amêndoa 1L',1.59,L,'1L'),
  mk('Milbona Bebida Aveia 1L',1.19,L,'1L'),
  mk('Milbona Bebida Soja 1L',1.09,L,'1L'),
  mk('Milbona Bebida Amêndoa 1L',1.19,L,'1L'),
  mk('Milbona Bebida Coco 1L',1.29,L,'1L'),
  mk('Milbona Bebida Arroz 1L',1.19,L,'1L'),
  mk('Milbona Batido Chocolate 1L',0.99,L,'1L'),
  mk('Milbona Batido Morango 1L',0.99,L,'1L'),
  mk('Milbona Batido Baunilha 1L',0.99,L,'1L'),
  mk('Milbona Kefir Natural 500g',1.49,L,'500g'),
  mk('Milbona Kefir Morango 500g',1.49,L,'500g'),
];

const LATICINIOS = [...leite,...iogurtes,...queijos,...queijos_especiais,...manteiga_natas,...ovos_vegetais];

// ═══════════════════════════════════════════════════════════════════
// 4. BEBIDAS (~270 produtos)
// ═══════════════════════════════════════════════════════════════════
const B = 'Bebidas';

const agua = tpl('Lidl', [
  ['Água Natural',0.25,0.39,0.59],
  ['Água com Gás',0.29,0.45,null],
  ['Água Saborizada Limão',0.39,null,null],
  ['Água Saborizada Laranja',0.39,null,null],
  ['Água Saborizada Frutos Vermelhos',0.39,null,null],
], [['0.5L',0],['1.5L',1],['5L',2]], B);

const sumos = tpl('Solevita', [
  ['Sumo Laranja',0.99,1.69,2.99],
  ['Sumo Laranja s/Açúcar',0.99,1.69,null],
  ['Sumo Ananás',0.99,1.69,null],
  ['Sumo Maçã',0.99,1.69,null],
  ['Sumo Pêssego',0.99,1.69,null],
  ['Sumo Manga',0.99,1.69,null],
  ['Sumo Multifrutos',0.99,1.69,null],
  ['Sumo Tropical',0.99,1.69,null],
  ['Sumo Groselha',0.99,1.69,null],
  ['Sumo Uva',0.99,1.69,null],
  ['Sumo Tomate',0.99,null,null],
  ['Sumo Laranja Chilled',1.29,null,null],
], [['330ml',0],['1L',1],['2L',2]], B);

const refrigerantes = tpl('Freeway', [
  ['Cola',0.35,0.69,1.09],
  ['Cola Zero',0.35,0.69,1.09],
  ['Laranja',0.35,0.69,1.09],
  ['Limão',0.35,0.69,null],
  ['Maçã',0.35,0.69,null],
  ['Energy Drink',0.69,null,null],
  ['Energy Drink Zero',0.69,null,null],
  ['Tónica',0.35,null,null],
  ['Ginger Beer',0.45,null,null],
  ['Ice Tea Limão',0.35,0.69,null],
  ['Ice Tea Pêssego',0.35,0.69,null],
], [['330ml',0],['1.5L',1],['2L',2]], B);

const cerveja = tpl('', [
  ['Estrella Damm',0.79,3.99],
  ['Heineken',0.89,4.49],
  ['Amstel',0.75,3.79],
  ['Lidl Lager Premium',0.59,2.99],
  ['Lidl Lager Premium s/Álcool',0.65,3.29],
  ['Lidl Stout Escura',0.79,null],
  ['Lidl IPA',0.89,null],
  ['Lidl Weizen',0.79,null],
  ['Lidl Radler Limão',0.65,null],
  ['Lidl Cider Maçã',0.79,null],
], [['330ml',0],['6x330ml',1]], B);

const vinho = [
  mk('Vinho Tinto Lidl 750ml',2.49,B,'750ml'),
  mk('Vinho Tinto Lidl 1.5L',3.99,B,'1.5L'),
  mk('Vinho Branco Lidl 750ml',2.49,B,'750ml'),
  mk('Vinho Branco Lidl 1.5L',3.99,B,'1.5L'),
  mk('Vinho Rosé Lidl 750ml',2.49,B,'750ml'),
  mk('Deluxe Vinho Tinto Premium 750ml',5.99,B,'750ml'),
  mk('Deluxe Vinho Branco Premium 750ml',5.99,B,'750ml'),
  mk('Sol & Mar Vinho Verde 750ml',3.49,B,'750ml'),
  mk('Sol & Mar Vinho Verde Branco 750ml',3.49,B,'750ml'),
  mk('Vinho Alentejo Tinto 750ml',4.99,B,'750ml'),
  mk('Vinho Alentejo Branco 750ml',4.49,B,'750ml'),
  mk('Vinho Dão Tinto 750ml',3.99,B,'750ml'),
  mk('Vinho Douro Tinto 750ml',4.49,B,'750ml'),
  mk('Vinho Bairrada Tinto 750ml',3.99,B,'750ml'),
  mk('Vinho Minho Branco 750ml',2.99,B,'750ml'),
  mk('Espumante Lidl Bruto 750ml',3.99,B,'750ml'),
  mk('Espumante Lidl Rosé 750ml',3.99,B,'750ml'),
  mk('Espumante Cava 750ml',4.49,B,'750ml'),
  mk('Moscatel Setúbal 750ml',5.99,B,'750ml'),
  mk('Porto Tawny 750ml',6.99,B,'750ml'),
  mk('Porto Branco 750ml',5.99,B,'750ml'),
  mk('Sangria Lidl 1L',1.99,B,'1L'),
];

const spirits = [
  mk('Whisky Lidl 700ml',9.99,B,'700ml'),
  mk('Vodka Lidl 700ml',7.99,B,'700ml'),
  mk('Gin Lidl 700ml',9.99,B,'700ml'),
  mk('Rum Lidl Branco 700ml',7.99,B,'700ml'),
  mk('Rum Lidl Escuro 700ml',8.99,B,'700ml'),
  mk('Brandy Lidl 700ml',7.99,B,'700ml'),
  mk('Aguardente Vínica 700ml',6.99,B,'700ml'),
  mk('Medronho 700ml',8.99,B,'700ml'),
  mk('Licor Beirão 700ml',9.49,B,'700ml'),
  mk('Amaretto Lidl 700ml',5.99,B,'700ml'),
  mk('Tequila Lidl 700ml',9.99,B,'700ml'),
  mk('Prosecco Lidl 750ml',4.99,B,'750ml'),
  mk('Lambrusco 750ml',3.99,B,'750ml'),
];

const BEBIDAS = [...agua,...sumos,...refrigerantes,...cerveja,...vinho,...spirits];

// ═══════════════════════════════════════════════════════════════════
// 5. CONGELADOS (~280 produtos)
// ═══════════════════════════════════════════════════════════════════
const C = 'Congelados';

const peixe_cong = tpl('', [
  ['Salmão Filetes Congelados',5.99,9.99],
  ['Bacalhau Postas Congelado',6.99,null],
  ['Pescada Filetes Congelados',3.99,6.99],
  ['Camarão Cozido Congelado',4.99,8.99],
  ['Camarão Tigre Cong.',7.99,null],
  ['Gambas Peladas Cong.',6.99,null],
  ['Lulas Inteiras Cong.',3.99,null],
  ['Lulas Anéis Cong.',3.99,null],
  ['Polvo Cozido Cong.',5.99,null],
  ['Ameijoa Cong.',4.99,null],
  ['Mexilhão Cong.',2.99,null],
  ['Peixe Espada Filetes',4.99,null],
  ['Tilápia Filetes Cong.',3.99,6.99],
  ['Panga Filetes Cong.',2.99,4.99],
  ['Bacalhau Desfiado Cong.',4.99,null],
  ['Migas Bacalhau Cong.',5.99,null],
], [['400g',0],['800g',1]], C);

const legumes_cong = tpl('Lidl', [
  ['Ervilhas Congeladas',0.99,1.79],
  ['Milho Congelado',0.99,1.79],
  ['Feijão Verde Congelado',0.99,1.79],
  ['Espinafres Congelados',0.99,1.79],
  ['Brócolos Congelados',1.09,1.99],
  ['Couve-Flor Congelada',1.09,null],
  ['Mix Legumes Congelados',1.09,1.99],
  ['Cenoura Congelada',0.79,1.49],
  ['Batata Frita Palha',0.99,1.79],
  ['Batata Frita Cunha',1.09,1.99],
  ['Batata Frita Rústica',1.09,1.99],
  ['Cebola Congelada',0.79,null],
  ['Alho Porró Congelado',0.89,null],
  ['Edamame Congelado',1.49,null],
  ['Abóbora Congelada',0.99,null],
], [['450g',0],['900g',1]], C);

const refeicoes_cong = [
  mk('Pizza Margherita Lidl 350g',1.99,C,'350g'),
  mk('Pizza Margherita Lidl 700g',2.99,C,'700g'),
  mk('Pizza Prosciutto Lidl 350g',2.49,C,'350g'),
  mk('Pizza 4 Queijos Lidl 350g',2.49,C,'350g'),
  mk('Pizza Atum Lidl 350g',2.49,C,'350g'),
  mk('Pizza Vegetal Lidl 350g',2.29,C,'350g'),
  mk('Pizza Frango Lidl 350g',2.49,C,'350g'),
  mk('Italiamo Pizza Thin Crust Margherita 360g',2.99,C,'360g'),
  mk('Italiamo Pizza Thin Prosciutto 360g',3.49,C,'360g'),
  mk('Lasanha Carne Lidl 400g',2.49,C,'400g'),
  mk('Lasanha Vegetariana Lidl 400g',2.49,C,'400g'),
  mk('Esparguete Bolonhesa Lidl 400g',2.49,C,'400g'),
  mk('Frango Grelhado Lidl 300g',2.99,C,'300g'),
  mk('Nuggets Frango Lidl 300g',2.49,C,'300g'),
  mk('Nuggets Frango Lidl 600g',3.99,C,'600g'),
  mk('Hambúrgueres Vaca Lidl 2x125g',2.99,C,'2x125g'),
  mk('Hambúrgueres Vaca Lidl 4x125g',4.99,C,'4x125g'),
  mk('Hambúrguer Vegetal Lidl 2x113g',3.49,C,'2x113g'),
  mk('Croquetes Bacalhau Lidl 400g',3.49,C,'400g'),
  mk('Pataniscas Bacalhau Lidl 300g',2.99,C,'300g'),
  mk('Rissóis Camarão Lidl 300g',2.99,C,'300g'),
  mk('Chamuças Frango Lidl 300g',2.99,C,'300g'),
  mk('Spring Rolls Vitasia 300g',2.99,C,'300g'),
  mk('Gyozas Vitasia 300g',3.49,C,'300g'),
  mk('Edamame Pronto Vitasia 300g',2.49,C,'300g'),
  mk('Eridanous Spanakopita Cong. 400g',2.99,C,'400g'),
  mk('Feijoada Cong. Lidl 400g',2.99,C,'400g'),
  mk('Cozido à Portuguesa Cong. 500g',3.49,C,'500g'),
  mk('Bacalhau com Natas Cong. 400g',4.49,C,'400g'),
  mk('Arroz de Frango Cong. 400g',2.99,C,'400g'),
];

const gelados = tpl('Gelatelli', [
  ['Gelado Baunilha',1.99,3.49],
  ['Gelado Chocolate',1.99,3.49],
  ['Gelado Morango',1.99,3.49],
  ['Gelado Caramelo',1.99,3.49],
  ['Gelado Mix 3 Sabores',2.49,3.99],
  ['Gelado Pistachio',2.49,null],
  ['Gelado Iogurte Frutos Vermelhos',2.29,null],
  ['Gelado Stracciatella',2.29,null],
  ['Gelado Limão',1.99,null],
  ['Gelado Menta Chocolate',2.29,null],
  ['Gelado Tiramisù',2.99,null],
  ['Gelado Snickers Style',3.49,null],
  ['Magnum Style Amêndoa x4',3.99,null],
  ['Magnum Style Branco x4',3.99,null],
  ['Ice Cream Sandwich x4',2.49,null],
  ['Cornetto Style Baunilha x4',2.99,null],
  ['Cornetto Style Chocolate x4',2.99,null],
  ['Mini Gelados Sortidos x12',2.99,null],
  ['Gelado Sorbet Manga',2.49,null],
  ['Gelado Sorbet Morango',2.49,null],
], [['500ml',0],['1L',1]], C);

const CONGELADOS = [...peixe_cong,...legumes_cong,...refeicoes_cong,...gelados];

// ═══════════════════════════════════════════════════════════════════
// 6. PADARIA (~170 produtos)
// ═══════════════════════════════════════════════════════════════════
const P = 'Padaria';

const pao = tpl('', [
  ['Pão de Forma Branco Lidl',1.29,2.39],
  ['Pão de Forma Integral Lidl',1.49,null],
  ['Pão de Forma s/Glúten Lidl',1.99,null],
  ['Pão de Centeio Lidl',1.29,null],
  ['Pão Rústico Lidl',1.19,null],
  ['Pão Saloio Lidl',0.69,null],
  ['Baguette Lidl',0.49,null],
  ['Ciabatta Lidl',0.79,null],
  ['Grafschafter Pão Escuro',1.99,null],
  ['Grafschafter Pão Centeio',1.99,null],
  ['Tostas Simples Lidl',0.79,1.39],
  ['Tostas Integrais Lidl',0.89,1.59],
  ['Tostas Centeio Lidl',0.99,null],
  ['Bolacha Torrada Lidl',0.89,null],
  ['Pão Pita Lidl',0.99,null],
  ['Pão Naan Lidl',1.29,null],
  ['Pão Hamburger x4',1.19,null],
  ['Pão Hot Dog x6',0.99,null],
  ['Pão Wrap Tortilla x4',1.29,null],
], [['400g',0],['800g',1]], P);

const pastelaria = [
  mk('Croissant Manteiga x4',1.49,P,'4 unidades'),
  mk('Croissant Chocolate x4',1.59,P,'4 unidades'),
  mk('Mini Croissant x6',1.29,P,'6 unidades'),
  mk('Pain au Chocolat x4',1.99,P,'4 unidades'),
  mk('Muffin Mirtilos x2',1.49,P,'2 unidades'),
  mk('Muffin Chocolate x2',1.49,P,'2 unidades'),
  mk('Muffin Baunilha x2',1.49,P,'2 unidades'),
  mk('Brownie Chocolate x2',1.79,P,'2 unidades'),
  mk('Éclair Chocolate x2',1.99,P,'2 unidades'),
  mk('Bolo Mármore',1.99,P,'unidade'),
  mk('Bolo Laranja',1.99,P,'unidade'),
  mk('Bolo Limão',1.99,P,'unidade'),
  mk('Tarte Maçã',2.49,P,'unidade'),
  mk('Tarte Limão Merengue',2.99,P,'unidade'),
  mk('Tarte Frutas Vermelhas',2.99,P,'unidade'),
  mk('Queque Simples x6',1.49,P,'6 unidades'),
  mk('Queque Pepitas Chocolate x6',1.59,P,'6 unidades'),
  mk('Bolinhos Canela x8',1.49,P,'8 unidades'),
  mk('Deluxe Financiers Amêndoa x8',2.99,P,'8 unidades'),
  mk('Deluxe Macaron Mix x12',4.99,P,'12 unidades'),
  mk('Deluxe Tarte Caramelo',3.99,P,'unidade'),
  mk('Donuts Glacê x2',0.99,P,'2 unidades'),
  mk('Donuts Chocolate x2',0.99,P,'2 unidades'),
  mk('Rosca Açúcar',1.49,P,'unidade'),
  mk('Palmier Açúcar x4',0.99,P,'4 unidades'),
  mk('Pão de Leite x4',1.29,P,'4 unidades'),
  mk('Brioche Trança',1.99,P,'unidade'),
  mk('Brioche Individual x4',1.49,P,'4 unidades'),
  mk('Panettone Lidl 500g',3.99,P,'500g'),
  mk('Panettone Gota Chocolate 500g',4.49,P,'500g'),
  mk('Pão de Ló Lidl',1.99,P,'unidade'),
  mk('Bolo de Arroz x4',0.99,P,'4 unidades'),
  mk('Pastel de Nata x4',1.49,P,'4 unidades'),
  mk('Pastel de Nata x8',2.79,P,'8 unidades'),
  mk('Queijada Lidl x4',1.29,P,'4 unidades'),
];

const PADARIA = [...pao,...pastelaria];

// ═══════════════════════════════════════════════════════════════════
// 7. LIMPEZA (~200 produtos)
// ═══════════════════════════════════════════════════════════════════
const LI = 'Limpeza';

const formil = tpl('Formil', [
  ['Detergente Roupa Líquido Color',3.49,5.99],
  ['Detergente Roupa Líquido Branco',3.49,5.99],
  ['Detergente Roupa Líquido Sensitive',3.99,null],
  ['Detergente Roupa Pó Universal',2.99,4.99],
  ['Detergente Roupa Pó Color',2.99,4.99],
  ['Cápsulas Roupa Color x18',3.49,5.99],
  ['Cápsulas Roupa Branco x18',3.49,5.99],
  ['Cápsulas Roupa 3in1 x18',3.99,null],
  ['Amaciador Fresco x40',2.49,3.99],
  ['Amaciador Floral x40',2.49,3.99],
  ['Amaciador Sensitive x40',2.79,null],
  ['Amaciador Concentrado x25',2.49,null],
], [['1.5L',0],['3L',1]], LI);

const w5 = tpl('W5', [
  ['Detergente Loiça Limão',0.99,1.79],
  ['Detergente Loiça Aloe Vera',0.99,1.79],
  ['Detergente Loiça Romã',0.99,1.79],
  ['Tablets Máquina Loiça x40',3.99,null],
  ['Tablets Máquina Loiça x60',5.99,null],
  ['Sal Máquina Loiça',0.99,null],
  ['Abrillantador Loiça',1.99,null],
  ['Spray Multiusos',1.29,1.99],
  ['Spray Cozinha',1.29,1.99],
  ['Spray Casa de Banho',1.29,1.99],
  ['Spray Vidros',0.99,null],
  ['Creme Limpeza Cremoso',0.99,null],
  ['WC Gel',0.99,null],
  ['WC Bloco x2',0.79,null],
  ['Desengordurante',1.49,null],
  ['Limpeza Forno',2.49,null],
  ['Limpeza Calcário',1.49,null],
  ['Banheira e Azulejos',1.49,null],
  ['Limpador Chão',1.29,1.99],
  ['Limpador Chão Madeira',1.49,null],
], [['500ml',0],['1L',1]], LI);

const papel_sacos = [
  mk('Papel Higiénico Lidl 4 rolos',0.99,LI,'4 rolos'),
  mk('Papel Higiénico Lidl 8 rolos',1.79,LI,'8 rolos'),
  mk('Papel Higiénico Lidl 12 rolos',2.49,LI,'12 rolos'),
  mk('Papel Higiénico Lidl 24 rolos',4.49,LI,'24 rolos'),
  mk('Papel Higiénico Húmido x40',1.49,LI,'x40'),
  mk('Papel Cozinha Lidl 2 rolos',1.19,LI,'2 rolos'),
  mk('Papel Cozinha Lidl 4 rolos',1.99,LI,'4 rolos'),
  mk('Lenços Papel Lidl 10x10',1.49,LI,'10x10 lenços'),
  mk('Lenços Papel Lidl Bolso x6',0.79,LI,'6 pacotes'),
  mk('Sacos Lixo 20L x20',0.79,LI,'x20'),
  mk('Sacos Lixo 30L x15',0.89,LI,'x15'),
  mk('Sacos Lixo 50L x12',0.99,LI,'x12'),
  mk('Sacos Lixo 100L x5',1.09,LI,'x5'),
  mk('Sacos Congelação x40',0.99,LI,'x40'),
  mk('Sacos Zip Congelação x15',1.29,LI,'x15'),
  mk('Saco Aspirador Universal x5',2.49,LI,'x5'),
  mk('Esponja Esfregão x2',0.79,LI,'x2'),
  mk('Esponja Abrasiva x3',0.89,LI,'x3'),
  mk('Luvas Lavar Loiça',0.99,LI,'par'),
  mk('Pano Microfibras x3',1.99,LI,'x3'),
  mk('Pano Microfibras Cozinha x2',1.49,LI,'x2'),
  mk('Rolo Folhas Alumínio',0.99,LI,'rolo'),
  mk('Rolo Película Aderente',0.89,LI,'rolo'),
  mk('Rolo Papel Vegetal',0.89,LI,'rolo'),
];

const LIMPEZA = [...formil,...w5,...papel_sacos];

// ═══════════════════════════════════════════════════════════════════
// 8. HIGIENE E BELEZA (~220 produtos)
// ═══════════════════════════════════════════════════════════════════
const H = 'Higiene e Beleza';

const cien_higiene = tpl('Cien', [
  ['Champô Normal',1.29,1.99],
  ['Champô Oleoso',1.29,1.99],
  ['Champô Seco',1.29,1.99],
  ['Champô Colorido',1.49,2.29],
  ['Champô Anticaspa',1.49,2.29],
  ['Champô Bebé',1.29,null],
  ['Gel Duche Hidratante',1.29,1.99],
  ['Gel Duche Refrescante',1.29,1.99],
  ['Gel Duche Sensitive',1.29,null],
  ['Gel Duche Men',1.29,1.99],
  ['Sabonete Líquido Hidratante',1.29,null],
  ['Sabonete Líquido Antibacteriano',1.29,null],
  ['Creme Hidratante Rosto',2.49,null],
  ['Creme Hidratante Rosto Noite',2.49,null],
  ['Creme Hidratante Rosto FPS30',2.99,null],
  ['Creme Contorno Olhos',2.49,null],
  ['Creme Anti-Idade',3.49,null],
  ['Leite Corporal',1.99,null],
  ['Creme Corporal Intensivo',1.99,null],
  ['Desodorizante Roll-On Fresco',1.29,null],
  ['Desodorizante Roll-On Floral',1.29,null],
  ['Desodorizante Roll-On Sensitive',1.49,null],
  ['Desodorizante Spray Fresco',1.29,null],
  ['Desodorizante Spray Men',1.29,null],
  ['Pasta Dentes Brancura',0.99,null],
  ['Pasta Dentes Sensitive',1.29,null],
  ['Pasta Dentes Carvão',1.29,null],
  ['Pasta Dentes Infantil',0.99,null],
  ['Colutório Fresh',1.49,null],
  ['Fio Dental',0.99,null],
], [['300ml',0],['500ml',1]], H);

const pilos = tpl('Pilos', [
  ['Champô Cabelo Normal',1.49,2.49],
  ['Champô Cabelo Seco',1.49,2.49],
  ['Champô Cabelo Oleoso',1.49,2.49],
  ['Champô Anticaspa',1.49,2.49],
  ['Champô Colorido',1.69,2.79],
  ['Champô Reparação',1.69,2.79],
  ['Condicionador Normal',1.49,2.49],
  ['Condicionador Seco',1.49,2.49],
  ['Máscara Capilar',2.49,null],
  ['Gel Duche Original',1.29,1.99],
  ['Gel Duche Sport',1.29,1.99],
], [['300ml',0],['500ml',1]], H);

const higiene_misc = [
  mk('Cien Protetor Solar FPS30 200ml',3.99,H,'200ml'),
  mk('Cien Protetor Solar FPS50 200ml',4.49,H,'200ml'),
  mk('Cien Protetor Solar Rosto FPS50+ 50ml',4.99,H,'50ml'),
  mk('Cien Protetor Solar Criança FPS50 200ml',4.99,H,'200ml'),
  mk('Cien After Sun 200ml',2.49,H,'200ml'),
  mk('Cien Autobronzeador 150ml',3.49,H,'150ml'),
  mk('Cien Maquilhagem Base 30ml',3.99,H,'30ml'),
  mk('Cien Rímel Preto',2.99,H,'unidade'),
  mk('Cien Lápis Olhos Preto',1.99,H,'unidade'),
  mk('Cien Batom Coral',2.49,H,'unidade'),
  mk('Cien Batom Nude',2.49,H,'unidade'),
  mk('Cien Blush',2.99,H,'unidade'),
  mk('Cien Corretor',2.49,H,'unidade'),
  mk('Cien Esfoliante Facial',2.49,H,'75ml'),
  mk('Cien Soro Vitamina C',4.99,H,'30ml'),
  mk('Cien Micellar Water 400ml',2.49,H,'400ml'),
  mk('Cien Discos Desmaquilhante x40',1.49,H,'x40'),
  mk('Lâminas Barbear Lidl x4',1.99,H,'x4'),
  mk('Lâminas Barbear Lidl x10',3.49,H,'x10'),
  mk('Máquina Barbear Descartável x3',1.49,H,'x3'),
  mk('Gel Barbear Lidl 200ml',0.99,H,'200ml'),
  mk('Aftershave Lidl 100ml',1.99,H,'100ml'),
  mk('Preservativos Lidl x12',2.99,H,'x12'),
  mk('Penso Rápido Lidl x20',0.99,H,'x20'),
  mk('Compressas Lidl x25',1.49,H,'x25'),
  mk('Termómetro Digital',3.99,H,'unidade'),
  mk('Vitamina C 1000mg x20',1.99,H,'x20 comprimidos'),
  mk('Magnésio Lidl x20',1.49,H,'x20 comprimidos'),
  mk('Cotonetes Lidl x100',0.79,H,'x100'),
  mk('Algodão Lidl 100g',0.89,H,'100g'),
];

const HIGIENE = [...cien_higiene,...pilos,...higiene_misc];

// ═══════════════════════════════════════════════════════════════════
// 9. BEBÉ (~100 produtos)
// ═══════════════════════════════════════════════════════════════════
const BB = 'Bebé';

const lupilu_fraldas = tpl('Lupilu', [
  ['Fraldas Tamanho 1 (2-5kg)',2.99,5.79],
  ['Fraldas Tamanho 2 (3-6kg)',3.49,6.49],
  ['Fraldas Tamanho 3 (4-9kg)',3.99,7.49],
  ['Fraldas Tamanho 4 (7-14kg)',4.49,7.99],
  ['Fraldas Tamanho 4+ (9-20kg)',4.99,8.99],
  ['Fraldas Tamanho 5 (11-25kg)',4.99,8.99],
  ['Fraldas Tamanho 6 (13-18kg)',5.49,9.99],
  ['Fraldas Pants T4 x28',5.99,null],
  ['Fraldas Pants T5 x28',6.49,null],
  ['Toalhitas Sensitive x64',1.99,3.49],
  ['Toalhitas Sensitive x128',3.49,null],
  ['Toalhitas Pure x64',1.79,null],
], [['x24',0],['x48',1]], BB);

const lupilu_alimentacao = [
  mk('Lupilu Papa Cereal 4m+ 400g',1.99,BB,'400g'),
  mk('Lupilu Papa Fruta Maçã Banana 4m+ 190g',0.89,BB,'190g'),
  mk('Lupilu Papa Legumes Cenoura 4m+ 190g',0.89,BB,'190g'),
  mk('Lupilu Papa Frango Legumes 6m+ 190g',0.99,BB,'190g'),
  mk('Lupilu Papa Atum Tomate 6m+ 190g',0.99,BB,'190g'),
  mk('Lupilu Bolacha Bebé 8m+ 100g',1.29,BB,'100g'),
  mk('Lupilu Snack Fruta Maçã 1a+ 20g',0.89,BB,'20g'),
  mk('Lupilu Leite Crescimento 2 400g',5.49,BB,'400g'),
  mk('Lupilu Leite Crescimento 3 800g',8.49,BB,'800g'),
  mk('Lupilu Leite Crescimento 4 800g',8.49,BB,'800g'),
  mk('Lupilu Creme Fraldas 100ml',1.99,BB,'100ml'),
  mk('Lupilu Gel Banho Bebé 300ml',1.49,BB,'300ml'),
  mk('Lupilu Champô Bebé 300ml',1.49,BB,'300ml'),
  mk('Lupilu Leite Corporal Bebé 300ml',1.49,BB,'300ml'),
  mk('Lupilu Creme Proteção Frio 50ml',2.49,BB,'50ml'),
  mk('Lupilu Chupeta Silicone x2',2.99,BB,'x2'),
  mk('Lupilu Biberão 260ml',3.99,BB,'260ml'),
  mk('Lupilu Copo Aprendizagem',3.49,BB,'unidade'),
  mk('Lupilu Talheres Bebé Set',3.99,BB,'set'),
  mk('Lupilu Babete x3',2.99,BB,'x3'),
];

const BEBE = [...lupilu_fraldas,...lupilu_alimentacao];

// ═══════════════════════════════════════════════════════════════════
// 10. ANIMAIS (~80 produtos)
// ═══════════════════════════════════════════════════════════════════
const AN = 'Animais';

const racao_gato = tpl('Lidl', [
  ['Ração Gato Adulto Frango',2.99,4.99],
  ['Ração Gato Adulto Peixe',2.99,4.99],
  ['Ração Gato Adulto Mix',2.99,4.99],
  ['Ração Gato Sterilised',3.49,5.99],
  ['Ração Gato Filhote',3.49,null],
  ['Ração Gato Senior',3.49,null],
  ['Gato Patê Frango',0.49,null],
  ['Gato Patê Atum',0.49,null],
  ['Gato Patê Salmão',0.49,null],
  ['Gato Patê Mix Peixe',0.49,null],
  ['Gato Snacks Frango',1.49,null],
], [['400g',0],['900g',1]], AN);

const racao_cao = tpl('Lidl', [
  ['Ração Cão Adulto Frango',3.49,5.99],
  ['Ração Cão Adulto Carne',3.49,5.99],
  ['Ração Cão Adulto Mix',3.49,5.99],
  ['Ração Cão Mini',3.99,null],
  ['Ração Cão Grande Porte',3.49,5.99],
  ['Ração Cão Senior',3.99,null],
  ['Cão Patê Carne',0.69,null],
  ['Cão Patê Frango',0.69,null],
  ['Cão Snacks Carne',1.99,null],
  ['Cão Snacks Dentais',2.49,null],
], [['400g',0],['900g',1]], AN);

const animais_misc = [
  mk('Areia Gato Aglomerante Lidl 5L',2.99,AN,'5L'),
  mk('Areia Gato Aglomerante Lidl 10L',4.99,AN,'10L'),
  mk('Areia Gato Silica Lidl 5L',3.49,AN,'5L'),
  mk('Comedouro Gato/Cão Lidl',2.99,AN,'unidade'),
  mk('Bebedouro Gato/Cão Lidl',2.99,AN,'unidade'),
  mk('Bola Borracha Cão Lidl',1.99,AN,'unidade'),
  mk('Brinquedo Ratinho Gato Lidl',1.49,AN,'unidade'),
];

const ANIMAIS = [...racao_gato,...racao_cao,...animais_misc];

// ═══════════════════════════════════════════════════════════════════
// 11. CASA E LAR (~100 produtos)
// ═══════════════════════════════════════════════════════════════════
const CA = 'Casa e Lar';

const casa_misc = [
  mk('Pilhas AA Lidl x4',0.99,CA,'x4'),
  mk('Pilhas AA Lidl x8',1.79,CA,'x8'),
  mk('Pilhas AA Lidl x16',2.99,CA,'x16'),
  mk('Pilhas AAA Lidl x4',0.99,CA,'x4'),
  mk('Pilhas AAA Lidl x8',1.79,CA,'x8'),
  mk('Pilhas 9V Lidl x2',1.49,CA,'x2'),
  mk('Pilhas C Lidl x2',1.29,CA,'x2'),
  mk('Pilhas D Lidl x2',1.49,CA,'x2'),
  mk('Lâmpada LED E27 9W Lidl',1.99,CA,'unidade'),
  mk('Lâmpada LED E27 12W Lidl',2.49,CA,'unidade'),
  mk('Lâmpada LED E14 6W Lidl',1.99,CA,'unidade'),
  mk('Lâmpada LED E14 40W equiv Lidl',1.79,CA,'unidade'),
  mk('Lâmpada LED Pack x3 Lidl',4.99,CA,'x3'),
  mk('Lâmpada LED Dimmable Lidl',2.99,CA,'unidade'),
  mk('Caixa Ovos Cartão Lidl x10',0.49,CA,'x10'),
  mk('Prato Plástico Descartável x10',0.89,CA,'x10'),
  mk('Copo Plástico x20',0.69,CA,'x20'),
  mk('Palhinha x25',0.49,CA,'x25'),
  mk('Guardanapo Papel x80',0.99,CA,'x80'),
  mk('Guardanapo Pano x20',0.89,CA,'x20'),
  mk('Toalha Mesa Papel',1.99,CA,'rolo'),
  mk('Vela Perfumada Lidl',2.49,CA,'unidade'),
  mk('Vela Perfumada Deluxe',3.99,CA,'unidade'),
  mk('Difusor Ambiente Lidl 100ml',3.99,CA,'100ml'),
  mk('Sabonete Mãos Lidl 300ml',1.49,CA,'300ml'),
  mk('Recarga Sabonete Lidl 300ml',1.29,CA,'300ml'),
  mk('Dispensador Sabonete',3.49,CA,'unidade'),
  mk('Escova Dentes Elétrica Cien',7.99,CA,'unidade'),
  mk('Cabeças Escova Elétrica Cien x2',3.99,CA,'x2'),
  mk('Cortador Unhas Set Lidl',1.99,CA,'set'),
];

const silvercrest = [
  mk('Silvercrest Balança Digital Cozinha',7.99,CA,'unidade'),
  mk('Silvercrest Termómetro Cozinha',6.99,CA,'unidade'),
  mk('Silvercrest Relógio Cozinha',4.99,CA,'unidade'),
  mk('Silvercrest Tesoura Cozinha',4.99,CA,'unidade'),
  mk('Silvercrest Descascador Cerâmica',3.99,CA,'unidade'),
  mk('Silvercrest Ralador Aço',4.49,CA,'unidade'),
  mk('Silvercrest Forma Bolo Redonda',5.99,CA,'unidade'),
  mk('Silvercrest Forma Bolo Rectangular',5.99,CA,'unidade'),
  mk('Silvercrest Tabuleiro Assar',6.99,CA,'unidade'),
  mk('Silvercrest Espátula Silicone',2.49,CA,'unidade'),
  mk('Silvercrest Colher Silicone',2.49,CA,'unidade'),
  mk('Silvercrest Set Utensílios 5 Pcs',9.99,CA,'set'),
  mk('Silvercrest Caixa Hermética 1L',2.99,CA,'unidade'),
  mk('Silvercrest Caixa Hermética Set 3',7.99,CA,'set'),
  mk('Silvercrest Garrafa Inox 500ml',7.99,CA,'500ml'),
  mk('Silvercrest Garrafa Inox 1L',9.99,CA,'1L'),
  mk('Silvercrest Saco Pasteleiro Set',3.99,CA,'set'),
  mk('Silvercrest Pincel Silicone',1.99,CA,'unidade'),
  mk('Silvercrest Cortador Pizza',3.49,CA,'unidade'),
  mk('Silvercrest Torradeira',14.99,CA,'unidade'),
  mk('Silvercrest Chaleira Elétrica',12.99,CA,'unidade'),
  mk('Silvercrest Moinho Café',19.99,CA,'unidade'),
  mk('Silvercrest Varinha Mágica',12.99,CA,'unidade'),
  mk('Silvercrest Sanduicheira',14.99,CA,'unidade'),
  mk('Silvercrest Ventilador Mesa',12.99,CA,'unidade'),
];

const CASA = [...casa_misc,...silvercrest];

// ═══════════════════════════════════════════════════════════════════
// 12. BIO E ORGÂNICOS (~90 produtos)
// ═══════════════════════════════════════════════════════════════════
const BI = 'Bio e Orgânicos';

const bio = tpl('Bio Lidl', [
  ['Leite Meio-Gordo',1.19,null],
  ['Iogurte Natural',0.79,null],
  ['Iogurte Morango',0.89,null],
  ['Manteiga sem Sal',2.49,null],
  ['Ovos x6',1.99,null],
  ['Queijo Creme',1.99,null],
  ['Arroz Agulha',1.59,2.99],
  ['Arroz Integral',1.69,null],
  ['Esparguete',0.99,null],
  ['Fusilli',0.99,null],
  ['Farinha Trigo',0.99,null],
  ['Farinha Espelta',1.29,null],
  ['Açúcar de Cana',1.29,null],
  ['Aveia Flocos',1.29,null],
  ['Granola Mel',2.99,null],
  ['Cereais Muesli',2.49,null],
  ['Azeite Extra Virgem',5.99,null],
  ['Molho Soja',1.49,null],
  ['Leite Coco',1.49,null],
  ['Grão de Bico',0.99,null],
  ['Lentilhas Vermelhas',0.99,null],
  ['Feijão Preto',0.99,null],
  ['Sementes Chia',2.49,null],
  ['Sementes Linhaça',1.29,null],
  ['Mix Frutos Secos',3.99,null],
  ['Amêndoas',3.49,null],
  ['Caju',3.99,null],
  ['Passas de Uva',1.49,null],
  ['Mel Multifloral',4.99,null],
  ['Ketchup',1.49,null],
], [['500g',0],['1kg',1]], BI);

const BIO = [...bio];

// ═══════════════════════════════════════════════════════════════════
// 13. CHOCOLATES E DOCES (~130 produtos)
// ═══════════════════════════════════════════════════════════════════
const CH = 'Chocolates e Doces';

const finCarre = tpl('Fin Carré', [
  ['Chocolate Negro 70%',0.69,1.29],
  ['Chocolate Negro 80%',0.69,1.29],
  ['Chocolate Negro 85%',0.69,1.29],
  ['Chocolate Negro 90%',0.79,1.39],
  ['Chocolate de Leite',0.69,1.29],
  ['Chocolate de Leite Caramelo',0.79,1.39],
  ['Chocolate de Leite Avelã',0.79,1.39],
  ['Chocolate Branco',0.69,1.29],
  ['Chocolate Branco Morango',0.79,1.39],
  ['Chocolate Branco Coco',0.79,1.39],
  ['Chocolate Negro Amêndoa',0.79,1.39],
  ['Chocolate Negro Laranja',0.79,1.39],
  ['Chocolate Negro Menta',0.79,1.39],
  ['Chocolate Negro Groselha',0.79,null],
  ['Chocolate Negro Sal Marinho',0.89,1.49],
], [['100g',0],['200g',1]], CH);

const favorina = tpl('Favorina', [
  ['Gomas Ursos',0.99,1.79],
  ['Gomas Mistura',0.99,1.79],
  ['Gomas Azedas',0.99,1.79],
  ['Gomas Crocodilos',0.99,null],
  ['Gomas Fresas',0.99,null],
  ['Jelly Beans',0.99,null],
  ['Marshmallows',0.99,1.79],
  ['Rebuçados Sortidos',0.99,null],
  ['Caramelos Moles',0.99,null],
  ['Pirulitos x8',1.29,null],
  ['Pão de Mel',1.99,null],
  ['Chocolate Ovos x6',1.99,null],
  ['Trufas Chocolate x12',2.49,null],
  ['Bombons Surtidos x16',2.99,null],
  ['Pralinés Avelã x12',2.49,null],
  ['Chupa Chups Style x10',1.29,null],
], [['200g',0],['400g',1]], CH);

const doces_misc = [
  mk('Lidl Chocolate Leite e Avelã 250g',0.99,CH,'250g'),
  mk('Lidl Chocolate Negro 70% 250g',0.99,CH,'250g'),
  mk('Nutella Estilo Lidl 400g',1.99,CH,'400g'),
  mk('Creme Avelã Lidl 400g',1.49,CH,'400g'),
  mk('Creme Avelã Branco Lidl 400g',1.49,CH,'400g'),
  mk('Doce Morango Lidl 450g',1.29,CH,'450g'),
  mk('Doce Pêssego Lidl 450g',1.29,CH,'450g'),
  mk('Doce Framboesa Lidl 450g',1.29,CH,'450g'),
  mk('Doce Mirtilo Lidl 450g',1.39,CH,'450g'),
  mk('Marmelada Lidl 450g',0.99,CH,'450g'),
];

const CHOCOLATES = [...finCarre,...favorina,...doces_misc];

// ═══════════════════════════════════════════════════════════════════
// 14. FITNESS E PROTEÍNAS (~70 produtos)
// ═══════════════════════════════════════════════════════════════════
const FT = 'Fitness e Proteínas';

const fitness = tpl('Lidl Sport', [
  ['Barra Proteína Chocolate',1.49,null],
  ['Barra Proteína Amendoim',1.49,null],
  ['Barra Proteína Frutos Vermelhos',1.49,null],
  ['Barra Proteína Caramelo',1.49,null],
  ['Barra Cereais Mel',0.99,null],
  ['Barra Cereais Chocolate',0.99,null],
  ['Barra Granola Frutos',0.99,null],
  ['Shake Proteína Chocolate 750g',14.99,null],
  ['Shake Proteína Baunilha 750g',14.99,null],
  ['Shake Proteína Morango 750g',14.99,null],
  ['Whey Protein Chocolate 750g',14.99,null],
  ['Whey Protein Vanilla 750g',14.99,null],
  ['Creatina 300g',8.99,null],
  ['BCAA 300g',9.99,null],
], [['x12',0]], FT);

const fitness_misc = [
  mk('Amêndoas Proteínas Lidl 100g',1.99,FT,'100g'),
  mk('Snack Proteínas Amendoim 45g',1.49,FT,'45g'),
  mk('Snack Proteínas Chocolate 45g',1.49,FT,'45g'),
  mk('Edamame Snack 100g',1.49,FT,'100g'),
  mk('Bebida Proteína Chocolate RTD',2.49,FT,'330ml'),
  mk('Bebida Proteína Baunilha RTD',2.49,FT,'330ml'),
  mk('Atum em Água Fitness Pack 3x80g',1.89,FT,'3x80g'),
  mk('Mix Sementes Fitness 250g',2.49,FT,'250g'),
  mk('Aveia Instant Fitness 500g',1.49,FT,'500g'),
  mk('Iogurte Grego Proteínas 500g',2.49,FT,'500g'),
  mk('Claras Ovos Líquidas 500ml',2.99,FT,'500ml'),
  mk('Frango Grelhado Strips 150g',2.49,FT,'150g'),
  mk('Salmão Defumado Fitness 100g',2.99,FT,'100g'),
];

const FITNESS = [...fitness,...fitness_misc];

// ═══════════════════════════════════════════════════════════════════
// 15. JARDIM E PAPELARIA (~65 produtos)
// ═══════════════════════════════════════════════════════════════════
const JP = 'Jardim e Papelaria';

const jardim_papel = [
  mk('Terra Universal Lidl 10L',2.99,JP,'10L'),
  mk('Terra Universal Lidl 25L',5.99,JP,'25L'),
  mk('Terra para Cactos 2L',1.99,JP,'2L'),
  mk('Terra Bio Lidl 20L',4.99,JP,'20L'),
  mk('Substrato Orquídeas 2L',2.49,JP,'2L'),
  mk('Fertilizante Universal 500ml',2.99,JP,'500ml'),
  mk('Fertilizante Tomates 500ml',2.99,JP,'500ml'),
  mk('Fertilizante Orquídeas 250ml',2.49,JP,'250ml'),
  mk('Sementes Tomate Lidl',0.99,JP,'saqueta'),
  mk('Sementes Alface Lidl',0.99,JP,'saqueta'),
  mk('Sementes Cenoura Lidl',0.99,JP,'saqueta'),
  mk('Sementes Pimento Lidl',0.99,JP,'saqueta'),
  mk('Sementes Manjericão Lidl',0.99,JP,'saqueta'),
  mk('Sementes Salsa Lidl',0.99,JP,'saqueta'),
  mk('Sementes Coentros Lidl',0.99,JP,'saqueta'),
  mk('Sementes Rabanete Lidl',0.99,JP,'saqueta'),
  mk('Vaso Plástico 15cm',1.49,JP,'unidade'),
  mk('Vaso Plástico 20cm',1.99,JP,'unidade'),
  mk('Vaso Cerâmica 12cm',3.99,JP,'unidade'),
  mk('Prato Vaso 15cm',0.99,JP,'unidade'),
  mk('Luvas Jardim Lidl',2.99,JP,'par'),
  mk('Pulverizador 500ml',1.99,JP,'500ml'),
  mk('Regador 1L',2.49,JP,'1L'),
  mk('Regador 5L',4.99,JP,'5L'),
  mk('Ancinho Jardim',3.99,JP,'unidade'),
  mk('Pá Jardim',3.99,JP,'unidade'),
  mk('Caderno A5 Lidl 100 folhas',1.49,JP,'100 folhas'),
  mk('Caderno A4 Lidl 100 folhas',1.99,JP,'100 folhas'),
  mk('Bloco Notas A6 x3',0.99,JP,'x3'),
  mk('Canetas Azul x10',0.99,JP,'x10'),
  mk('Canetas Esferográfica Azul/Preto/Verm x3',0.69,JP,'x3'),
  mk('Lápis HB x12',0.99,JP,'x12'),
  mk('Borracha Lidl x2',0.49,JP,'x2'),
  mk('Marcadores Fluorescentes x4',1.29,JP,'x4'),
  mk('Marcadores Coloridos x10',1.99,JP,'x10'),
  mk('Esferográficas Gel x5',1.49,JP,'x5'),
  mk('Post-it Lidl x80',1.49,JP,'x80'),
  mk('Agrafador Lidl',3.99,JP,'unidade'),
  mk('Agrafos x1000',0.79,JP,'x1000'),
  mk('Clips x100',0.49,JP,'x100'),
  mk('Tesoura Escritório',1.99,JP,'unidade'),
  mk('Cola Stick x3',0.99,JP,'x3'),
  mk('Fita Adesiva x2',0.79,JP,'x2'),
  mk('Pasta Suspensa x25',2.99,JP,'x25'),
  mk('Envelopes x50',1.49,JP,'x50'),
  mk('Impressora Papel A4 x500',3.99,JP,'x500'),
];

const JARDIM_PAPEL = jardim_papel;

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO A — MERCEARIA EXTRA
// ═══════════════════════════════════════════════════════════════════
const vitasia_extra = [
  mk('Vitasia Arroz Frito Vietnamita 250g',1.99,M,'250g'), mk('Vitasia Alga Nori x10',1.49,M,'x10 folhas'),
  mk('Vitasia Sésamo Torrado 100g',0.99,M,'100g'), mk('Vitasia Kimchi 380g',2.99,M,'380g'),
  mk('Vitasia Leite Coco Light 400ml',0.89,M,'400ml'), mk('Vitasia Pasta Gochujang 100g',1.49,M,'100g'),
  mk('Vitasia Ramen Instantâneo Galinha 80g',0.59,M,'80g'), mk('Vitasia Ramen Instantâneo Carne 80g',0.59,M,'80g'),
  mk('Vitasia Ramen Instantâneo Vegetal 80g',0.59,M,'80g'), mk('Vitasia Pho Instantâneo 65g',0.59,M,'65g'),
  mk('Vitasia Molho Hoisin 200ml',1.29,M,'200ml'), mk('Vitasia Tempurá Farinha 250g',1.49,M,'250g'),
  mk('Vitasia Vinagre Preto 300ml',1.49,M,'300ml'), mk('Vitasia Amendoim Picante 200g',1.29,M,'200g'),
  mk('Vitasia Crackers Arroz Alga 90g',1.49,M,'90g'),
];
const deluxe_extra = [
  mk('Deluxe Azeite Trufa Negra 100ml',4.99,M,'100ml'), mk('Deluxe Flor de Sal 100g',1.99,M,'100g'),
  mk('Deluxe Pimenta de Kampot 30g',2.49,M,'30g'), mk('Deluxe Vanilha em Pau x2',1.99,M,'x2'),
  mk('Deluxe Foie Gras Pato 80g',4.99,M,'80g'), mk('Deluxe Patê Salmão 100g',2.49,M,'100g'),
  mk('Deluxe Carpaccio Vitela 100g',3.49,M,'100g'), mk('Deluxe Mostarda Mel Dijon 200g',1.99,M,'200g'),
  mk('Deluxe Maionese Trufa 250ml',2.99,M,'250ml'), mk('Deluxe Chutney Manga 230g',1.99,M,'230g'),
  mk('Deluxe Chutney Figo 230g',1.99,M,'230g'), mk('Deluxe Vinagre Balsâmico 25 anos 250ml',5.99,M,'250ml'),
  mk('Deluxe Polenta Taragna 500g',2.99,M,'500g'), mk('Deluxe Massa Espelta 500g',1.99,M,'500g'),
  mk('Deluxe Risotto Porcini 250g',2.49,M,'250g'),
];
const conservas_extra = tpl('Orlando', [
  ['Cogumelos Fatiados',0.49,0.89],['Cogumelos Inteiros',0.49,0.89],
  ['Milho Doce',0.45,0.85],['Alcachofras Coração',0.99,null],
  ['Palmitos',1.19,null],['Pimentos em Tiras',0.59,null],
  ['Pepinos Pickles',0.79,null],['Couve-Flor Pickles',0.69,null],
], [['280g',0],['560g',1]], M);
const mercearia_int = [
  mk('Quinoa Lidl 500g',2.49,M,'500g'), mk('Quinoa Tricolor Lidl 500g',2.79,M,'500g'),
  mk('Bulgur Lidl 500g',1.29,M,'500g'), mk('Cuscuz Lidl 500g',1.29,M,'500g'),
  mk('Cuscuz Integral Lidl 500g',1.49,M,'500g'), mk('Trigo Sarraceno Lidl 500g',1.79,M,'500g'),
  mk('Cevada Perlada Lidl 500g',0.99,M,'500g'), mk('Espelta Grão Lidl 500g',1.49,M,'500g'),
  mk('Farelo Aveia 500g',0.99,M,'500g'), mk('Farelo Trigo 500g',0.89,M,'500g'),
  mk('Pão Ralado Lidl 400g',0.59,M,'400g'), mk('Amido Milho Lidl 400g',0.79,M,'400g'),
  mk('Gelatina Folhas Lidl 12g',0.49,M,'12g'), mk('Agar Agar Lidl 6g',0.79,M,'6g'),
  mk('Belbake Gotas Chocolate Negro 200g',1.49,M,'200g'),
  mk('Sol & Mar Bacalhau Salgado 400g',5.99,M,'400g'), mk('Sol & Mar Polvo Cozido Azeite 190g',2.49,M,'190g'),
  mk('Sol & Mar Sardinhas Premium 125g',1.19,M,'125g'), mk('Sol & Mar Amêijoas Molho Branco 190g',2.99,M,'190g'),
  mk('Sol & Mar Arroz de Peixe Preparado 400g',2.49,M,'400g'),
  mk('Eridanous Queijo Haloumi 225g',2.99,M,'225g'), mk('Eridanous Iogurte Grego Mel 150g',0.99,M,'150g'),
  mk('Eridanous Kritsinia 150g',1.29,M,'150g'),
  mk('Italiamo Arroz Carnaroli 500g',2.49,M,'500g'), mk('Italiamo Pane Carasau 200g',2.49,M,'200g'),
  mk('Italiamo Crema di Latte 170g',1.99,M,'170g'), mk('Italiamo Salsa Verde 180g',1.79,M,'180g'),
  mk('Pasta Harissa Lidl 70g',0.99,M,'70g'), mk('Pasta Anchova 60g',1.49,M,'60g'),
  mk('Tapenade Azeitonas 180g',1.99,M,'180g'), mk('Creme Avelã Duplo 350g',1.99,M,'350g'),
  mk('Doce Laranja e Gengibre 450g',1.29,M,'450g'), mk('Doce de Abóbora e Canela 450g',1.29,M,'450g'),
  mk('Curd de Limão Deluxe 320g',1.99,M,'320g'), mk('Caramelo Salgado Deluxe 210g',2.49,M,'210g'),
  mk('Xarope Ácer 250ml',2.49,M,'250ml'), mk('Xarope Agave Claro 250ml',1.99,M,'250ml'),
  mk('Vinagre Framboesa 250ml',1.49,M,'250ml'), mk('Vinagre Vinho Branco 500ml',0.69,M,'500ml'),
  mk('Sal Fumado Lidl 250g',1.29,M,'250g'), mk('Ras el Hanout 40g',0.89,M,'40g'),
  mk('Baharat Mix 40g',0.89,M,'40g'), mk('Tempero Paella 40g',0.79,M,'40g'),
  mk('Tempero Carne Assada 50g',0.69,M,'50g'), mk('Tempero Peixe Grelhado 40g',0.69,M,'40g'),
  mk('Alho em Flocos 40g',0.59,M,'40g'), mk('Cebola em Flocos 50g',0.59,M,'50g'),
  mk('Caldo Carne Concentrado x8',0.79,M,'x8 cubos'), mk('Caldo Peixe Concentrado x6',0.79,M,'x6 cubos'),
  mk('Crêpes Frios Prontos x6',1.49,M,'x6'), mk('Blinis Prontos x16',1.49,M,'x16'),
  mk('Massa Folhada Congelada Lidl 275g',1.29,M,'275g'), mk('Massa Tenra Congelada Lidl 270g',1.29,M,'270g'),
];
const granolas_barras = tpl('Crownfield', [
  ['Barra Granola Mel x6',1.49,null],['Barra Granola Chocolate x6',1.49,null],
  ['Barra Granola Frutos Vermelhos x6',1.49,null],['Barra Muesli x6',1.49,null],
  ['Barra Aveia x6',1.29,null],['Barra Proteína Cereais x6',1.99,null],
  ['Barra Kids Chocolate x6',1.29,null],
], [['150g',0]], M);

const MERCEARIA_EXTRA = [...vitasia_extra,...deluxe_extra,...conservas_extra,...mercearia_int,...granolas_barras];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO B — FRESCOS EXTRA
// ═══════════════════════════════════════════════════════════════════
const carne_extra = [
  mk('Frango Inteiro ~1.2kg',3.49,FR,'~1.2kg'), mk('Frango Marinado Piri-Piri 900g',5.49,FR,'~900g'),
  mk('Frango Marinado Limão Alho 900g',5.49,FR,'~900g'), mk('Alitas Frango 500g',3.49,FR,'500g'),
  mk('Vaca Hambúrguer 2x150g',3.99,FR,'2x150g'), mk('Vaca Hambúrguer Cheese 2x150g',4.49,FR,'2x150g'),
  mk('Vaca Bife Fino 400g',5.99,FR,'400g'), mk('Vaca T-Bone ~400g',8.99,FR,'~400g'),
  mk('Vitela Escalopes 400g',6.99,FR,'400g'), mk('Porco Secretos 400g',4.99,FR,'400g'),
  mk('Porco Febras 400g',3.99,FR,'400g'), mk('Porco Bochechas 400g',4.99,FR,'400g'),
  mk('Pato Peito 2un',6.99,FR,'~400g'), mk('Pato Confit Coxas 2un',5.99,FR,'2 coxas'),
  mk('Espetada Mista 4un',4.99,FR,'4 unidades'), mk('Espetada Frango 4un',3.99,FR,'4 unidades'),
  mk('Hambúrguer Vegetal Lidl 2x113g',3.99,FR,'2x113g'), mk('Linguiça Fresca 300g',2.99,FR,'300g'),
  mk('Chouriço Caseiro Fresco 300g',2.99,FR,'300g'), mk('Morcela Fresca 300g',2.49,FR,'300g'),
];
const peixe_extra = [
  mk('Salmão Marinado Limão 400g',7.49,FR,'400g'), mk('Bacalhau Fresco Filetes 400g',6.49,FR,'400g'),
  mk('Pregado Filetes 300g',6.99,FR,'300g'), mk('Halibute Filetes 300g',6.49,FR,'300g'),
  mk('Linguado Filetes 300g',5.99,FR,'300g'), mk('Peixe Espada Filetes 400g',4.49,FR,'400g'),
  mk('Atum Fresco Postas 300g',6.99,FR,'300g'), mk('Camarão Cozido Fresco 500g',5.99,FR,'500g'),
  mk('Camarão Cru Descascado 300g',6.99,FR,'300g'), mk('Lagostins Cozidos 6un',7.99,FR,'6 unidades'),
  mk('Chocos Limpos 400g',5.49,FR,'400g'), mk('Berbigão 500g',4.49,FR,'500g'),
  mk('Mexilhão Fresco 1kg',2.99,FR,'1kg'), mk('Vieiras 4un',6.99,FR,'4 unidades'),
  mk('Gamba Vermelha 300g',9.99,FR,'300g'), mk('Bacalhau Desfiado Fresco 200g',4.49,FR,'200g'),
];
const frescos_extra = [
  mk('Ananás Descascado Embalado',2.49,FR,'unidade'), mk('Mix Melão Melancia 400g',2.49,FR,'400g'),
  mk('Salada Fruta Pronta 400g',2.49,FR,'400g'), mk('Amoras 125g',2.49,FR,'125g'),
  mk('Groselha 125g',2.49,FR,'125g'), mk('Tamaras Medjool 200g',3.49,FR,'200g'),
  mk('Courgette Baby 300g',1.29,FR,'300g'), mk('Feijão Verde Fresco 500g',1.49,FR,'500g'),
  mk('Vagem Fina 200g',1.29,FR,'200g'), mk('Beterraba Cozida 3un',1.49,FR,'3 unidades'),
  mk('Cenoura Baby 200g',1.19,FR,'200g'), mk('Milho Fresco Espiga',0.69,FR,'unidade'),
  mk('Pimento Ramiro 2un',1.99,FR,'2 unidades'), mk('Tomate Beefsteak',1.99,FR,'unidade'),
  mk('Tomate Kumato 500g',1.99,FR,'500g'), mk('Rabanetes Maço',0.79,FR,'maço'),
  mk('Espargo Verde Maço',1.99,FR,'maço'), mk('Espargo Branco 250g',2.99,FR,'250g'),
  mk('Alcachofra Fresca',1.49,FR,'unidade'), mk('Funcho Fresco',1.29,FR,'unidade'),
  mk('Abóbora Butternut Fatia',1.49,FR,'fatia ~500g'), mk('Gengibre Fresco 100g',0.99,FR,'100g'),
  mk('Cogumelos Shimeji 150g',2.49,FR,'150g'), mk('Cogumelos Portobello 2un',1.99,FR,'2 unidades'),
  mk('Kimchi Fresco 300g',3.49,FR,'300g'), mk('Chucrute Fresco 400g',1.99,FR,'400g'),
  mk('Salada Espinafres e Rúcula 100g',1.29,FR,'100g'), mk('Salada Fresca para Wrap 150g',1.49,FR,'150g'),
  mk('Salada Italiana 200g',1.29,FR,'200g'),
];
const charcutaria_extra = [
  mk('Prosciutto Crudo Deluxe 100g',2.99,FR,'100g'), mk('Bresaola Italiamo 100g',3.49,FR,'100g'),
  mk('Coppa Italiamo 100g',2.99,FR,'100g'), mk('Speck Italiamo 100g',2.99,FR,'100g'),
  mk('Chorizo Pimento Fumado 100g',2.49,FR,'100g'), mk('Salame Napoli 100g',2.49,FR,'100g'),
  mk('Chouriço Transmontano Fatiado 100g',2.99,FR,'100g'), mk('Presunto Regional 100g',3.49,FR,'100g'),
  mk('Morcela de Vinhais Fatiada 100g',3.49,FR,'100g'), mk('Paio do Alentejo Fatiado 100g',3.49,FR,'100g'),
];

const FRESCOS_EXTRA = [...carne_extra,...peixe_extra,...frescos_extra,...charcutaria_extra];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO C — LATICÍNIOS EXTRA
// ═══════════════════════════════════════════════════════════════════
const iog_extra = tpl('Milbona', [
  ['Iogurte Grego Limão',0.89,null],['Iogurte Grego Frutos Vermelhos',0.89,null],
  ['Iogurte Grego Mango',0.89,null],['Iogurte Skyr Natural',0.99,null],
  ['Iogurte Skyr Baunilha',0.99,null],['Iogurte Skyr Morango',0.99,null],
  ['Iogurte Skyr Mirtilo',0.99,null],['Iogurte Soja Morango',0.79,null],
  ['Iogurte Soja Natural',0.79,null],['Iogurte Coco',0.79,null],
], [['150g',0]], L);
const queijo_extra = [
  mk('Milbona Mozarella Bufala 125g',1.99,L,'125g'), mk('Milbona Mozarella Marinada 150g',1.99,L,'150g'),
  mk('Milbona Queijo Parmesão Bloco 100g',2.49,L,'100g'), mk('Milbona Queijo Provolone 200g',2.49,L,'200g'),
  mk('Milbona Queijo Emental Bloco 400g',2.99,L,'400g'), mk('Milbona Burrata 125g',1.99,L,'125g'),
  mk('Milbona Halloumi 225g',2.49,L,'225g'), mk('Milbona Creme Queijo Ervas 150g',1.29,L,'150g'),
  mk('Milbona Creme Queijo Pimenta 150g',1.29,L,'150g'), mk('Queijo Cabra Fresco 150g',2.49,L,'150g'),
  mk('Queijo Cabra Curado 200g',2.99,L,'200g'), mk('Deluxe Queijo Roquefort 100g',2.99,L,'100g'),
  mk('Deluxe Queijo Gorgonzola 150g',2.99,L,'150g'), mk('Milbona Manteiga Ervas 125g',1.49,L,'125g'),
  mk('Milbona Kefir Frutos Vermelhos 500g',1.49,L,'500g'),
];

const LATICINIOS_EXTRA = [...iog_extra,...queijo_extra];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO D — BEBIDAS EXTRA
// ═══════════════════════════════════════════════════════════════════
const agua_extra = tpl('Lidl', [
  ['Água Saborizada Manga',0.45,null],['Água Saborizada Melancia',0.45,null],
  ['Água Saborizada Menta',0.45,null],['Água Infusão Pepino Hortelã',0.55,null],
  ['Água Infusão Limão Gengibre',0.55,null],['Água Coco 100%',1.29,null],
], [['330ml',0],['750ml',1]], B);
const sumos_extra = tpl('Solevita', [
  ['Smoothie Verde Espinafres Maçã',1.49,null],['Smoothie Tropical',1.49,null],
  ['Kombucha Limão Gengibre',1.99,null],['Kombucha Hibisco',1.99,null],
  ['Sumo Cenoura Laranja',0.99,1.69],['Sumo Beterraba Maçã',0.99,1.69],
  ['Sumo Romã',1.29,null],['Nectar Frutos Tropicais',0.89,1.49],
], [['330ml',0],['1L',1]], B);
const vinho_extra = [
  mk('Vinho Verde Alvarinho 750ml',5.99,B,'750ml'), mk('Vinho Branco Lote Especial 750ml',3.99,B,'750ml'),
  mk('Vinho Tinto Reserva Alentejo 750ml',6.99,B,'750ml'), mk('Vinho Tinto Reserva Douro 750ml',6.99,B,'750ml'),
  mk('Vinho Rosé Fresco 750ml',3.49,B,'750ml'), mk('Vinho Espumante Brut Premium 750ml',5.49,B,'750ml'),
  mk('Porto LBV 750ml',7.99,B,'750ml'), mk('Porto Ruby 750ml',6.49,B,'750ml'),
  mk('Whisky Single Malt Lidl 700ml',14.99,B,'700ml'), mk('Gin Botânico Lidl 700ml',12.99,B,'700ml'),
  mk('Rum Especiado Lidl 700ml',10.99,B,'700ml'), mk('Aperol Style Lidl 700ml',7.99,B,'700ml'),
  mk('Limoncello Italiamo 500ml',6.99,B,'500ml'), mk('Grappa Italiamo 500ml',7.49,B,'500ml'),
  mk('Cocktail Mojito Pronto 250ml',1.99,B,'250ml'), mk('Cocktail Spritz Pronto 250ml',1.99,B,'250ml'),
  mk('Kefir para Beber Natural 330ml',1.49,B,'330ml'), mk('Leite Cacau Milbona 330ml',0.79,B,'330ml'),
  mk('Chocolate Quente Instantâneo 400g',1.99,B,'400g'),
];
const cerveja_extra = tpl('', [
  ['Budweiser',0.89,4.49],['Carlsberg',0.79,3.99],['Corona',1.09,5.49],
  ['Lidl Weizen Cerveja',0.79,null],['Lidl IPA Artesanal',0.99,null],
  ['Lidl Porter Escura',0.89,null],['Cidra Maçã Lidl',0.89,3.99],
], [['330ml',0],['6x330ml',1]], B);

const BEBIDAS_EXTRA = [...agua_extra,...sumos_extra,...vinho_extra,...cerveja_extra];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO E — CONGELADOS EXTRA
// ═══════════════════════════════════════════════════════════════════
const cong_refeicoes = [
  mk('Arroz de Pato Cong. 400g',3.99,C,'400g'), mk('Arroz Marisco Cong. 400g',4.49,C,'400g'),
  mk('Paella Valenciana Cong. 400g',3.49,C,'400g'), mk('Paella Mista Cong. 800g',5.99,C,'800g'),
  mk('Pad Thai Vitasia Cong. 400g',3.49,C,'400g'), mk('Curry Frango Cong. 400g',3.49,C,'400g'),
  mk('Tikka Masala Cong. 400g',3.49,C,'400g'), mk('Chili con Carne Cong. 400g',2.99,C,'400g'),
  mk('Moussaka Eridanous Cong. 400g',3.49,C,'400g'), mk('Bacalhau Brás Cong. 400g',4.49,C,'400g'),
  mk('Polvo com Batata Cong. 400g',4.99,C,'400g'), mk('Salmão c/Legumes Cong. 400g',4.49,C,'400g'),
  mk('Camarão Piri-Piri Cong. 300g',4.99,C,'300g'), mk('Coxinhas Frango Cong. 400g',2.99,C,'400g'),
  mk('Samosas Legumes Cong. 300g',2.99,C,'300g'), mk('Wraps Frango Cong. 2un',3.49,C,'2 unidades'),
  mk('Burger Frango Crispy Cong.',2.49,C,'unidade'), mk('Spring Rolls Extra Cong. 400g',2.99,C,'400g'),
  mk('Tempura Camarão Cong. 200g',3.99,C,'200g'), mk('Sopa Legumes Cong. 1kg',1.99,C,'1kg'),
];
const pizza_extra = tpl('Lidl', [
  ['Pizza BBQ Frango',2.49,3.99],['Pizza Speck Rúcula',2.99,null],
  ['Pizza Pepperoni',2.49,3.99],['Pizza Funghi',2.29,null],
  ['Pizza Prosciutto Cotto',2.99,null],['Pizza 5 Queijos',2.49,3.99],
  ['Pizza Capricciosa',2.49,null],['Pizza Frango Espinafres',2.49,null],
], [['350g',0],['700g',1]], C);
const gelados_extra = [
  mk('Gelatelli Magnum Branco x4',3.99,C,'x4'), mk('Gelatelli Cornetto Morango x4',2.99,C,'x4'),
  mk('Gelatelli Sorbet Limão 500ml',2.49,C,'500ml'), mk('Gelatelli Sorbet Mango 500ml',2.49,C,'500ml'),
  mk('Gelatelli Vegan Chocolate 480ml',2.99,C,'480ml'), mk('Gelatelli Vegan Morango 480ml',2.99,C,'480ml'),
  mk('Gelatelli Mini Sundae x12',2.99,C,'x12'), mk('Gelatelli Paleta Chocolate x6',2.99,C,'x6'),
  mk('Gelatelli Cheesecake Gelado Mirtilos',4.49,C,'unidade'),
];

const CONGELADOS_EXTRA = [...cong_refeicoes,...pizza_extra,...gelados_extra];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO F — PADARIA EXTRA
// ═══════════════════════════════════════════════════════════════════
const pao_extra = [
  mk('Pão de Mistura Lidl 500g',1.49,P,'500g'), mk('Pão com Sementes 500g',1.79,P,'500g'),
  mk('Pão Sem Glúten 400g',2.49,P,'400g'), mk('Mini Baguette x4',1.29,P,'x4'),
  mk('Pão de Leite x6',1.49,P,'x6'), mk('Pão Tigre',1.29,P,'unidade'),
  mk('Pão Bagel x4',1.29,P,'x4'), mk('Pão Sírio x6',0.99,P,'x6'),
  mk('Pão Chapata',1.19,P,'unidade'), mk('Tosta Knäckebrod 250g',1.49,P,'250g'),
  mk('Pão Brioche Hamburger x4',1.79,P,'x4'), mk('Pão Pretzel x4',1.49,P,'x4'),
  mk('Wrap Integral x6',1.49,P,'x6'), mk('Pão Centeio Escuro 500g',1.69,P,'500g'),
  mk('Baguette Congelada x2',1.29,P,'x2'),
];
const pastelaria_extra = [
  mk('Strudel Maçã Lidl',2.49,P,'unidade'), mk('Rolo de Canela x4',1.99,P,'x4'),
  mk('Berliner x2',1.29,P,'x2'), mk('Chouriço Brioche Lidl',1.99,P,'unidade'),
  mk('Sandes Mista Fatiada',2.49,P,'unidade'), mk('Bolo Cenoura Lidl',1.99,P,'unidade'),
  mk('Bolo Chocolate Recheado',2.49,P,'unidade'), mk('Cake de Frutas',1.99,P,'unidade'),
  mk('Financiers x6',2.49,P,'x6'), mk('Madeleines x10',1.99,P,'x10'),
  mk('Palmiers Grandes x4',1.49,P,'x4'), mk('Profiteroles x12',2.99,P,'x12'),
  mk('Mil-Folhas Individual',1.49,P,'unidade'), mk('Waffle Belga x4',1.99,P,'x4'),
  mk('Canelé x4',2.99,P,'x4'), mk('Queque Limão x4',1.99,P,'x4'),
  mk('Broa de Mel Lidl 400g',2.49,P,'400g'), mk('Folar da Páscoa',3.99,P,'unidade'),
];

const PADARIA_EXTRA = [...pao_extra,...pastelaria_extra];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO G — LIMPEZA EXTRA
// ═══════════════════════════════════════════════════════════════════
const limpeza_extra = tpl('W5', [
  ['Spray Anti-Bactérias',1.49,2.49],['Pastilha WC x4',0.99,null],
  ['Gel WC Pinheiro',0.99,null],['Desengordurante Extra Forte',1.99,null],
  ['Limpa Inox',1.49,null],['Spray Móveis Brilhante',1.49,null],
  ['Limpa Alcatifas',2.49,null],['Limpa Frigorífico',1.49,null],
], [['500ml',0],['1L',1]], LI);
const air_fresh = [
  mk('Ambientador Spray Lidl Lavanda 300ml',1.29,LI,'300ml'),
  mk('Ambientador Spray Lidl Pinho 300ml',1.29,LI,'300ml'),
  mk('Ambientador Spray Lidl Fresco 300ml',1.29,LI,'300ml'),
  mk('Plug-in Ambientador Lidl',3.99,LI,'unidade'),
  mk('Recarga Plug-in Lavanda x2',2.99,LI,'x2 recargas'),
  mk('Bolas Anti-Traça Lidl x15',1.29,LI,'x15'),
  mk('Gel Anti-Humidade Lidl 500g',2.99,LI,'500g'),
  mk('Pastilhas Máquina Loiça x50',5.99,LI,'x50'),
  mk('Pastilhas Máquina Loiça x70',7.99,LI,'x70'),
  mk('Spray Engomado Roupa 400ml',1.49,LI,'400ml'),
  mk('Esponja Mágica x2',1.49,LI,'x2'),
  mk('Luvas Vinil x20',1.49,LI,'x20'),
  mk('Escova WC c/Suporte',3.99,LI,'unidade'),
  mk('Esfregona Microfibra',4.99,LI,'unidade'),
  mk('Rolo Folhas Alumínio',0.99,LI,'rolo'),
  mk('Rolo Película Aderente',0.89,LI,'rolo'),
];

const LIMPEZA_EXTRA = [...limpeza_extra,...air_fresh];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO H — HIGIENE EXTRA
// ═══════════════════════════════════════════════════════════════════
const higiene_men = [
  mk('Cien Men Desodorizante 48h 50ml',1.29,H,'50ml'),
  mk('Cien Men Gel Duche 3in1 300ml',1.29,H,'300ml'),
  mk('Cien Men Creme Hidratante 50ml',2.49,H,'50ml'),
  mk('Cien Men Champô Anticaspa 300ml',1.49,H,'300ml'),
  mk('Gel Barbear Sensitive 200ml',0.99,H,'200ml'),
  mk('Espuma Barbear Lidl 200ml',1.29,H,'200ml'),
  mk('Aftershave Bálsamo 100ml',1.99,H,'100ml'),
  mk('Gel Cabelo Fixação Forte 200ml',1.29,H,'200ml'),
  mk('Cera Cabelo 100ml',1.99,H,'100ml'),
  mk('Máquina Barbear Descartável x3',1.49,H,'x3'),
];
const higiene_fem = [
  mk('Cien Toalhas Íntimas x30',1.49,H,'x30'), mk('Cien Toalhas Menstruais Normal x12',1.49,H,'x12'),
  mk('Cien Tampões Normal x16',1.49,H,'x16'), mk('Cien Tampões Super x16',1.49,H,'x16'),
  mk('Cien Creme Depilatório 200ml',2.49,H,'200ml'), mk('Cien Óleo Argan 100ml',2.49,H,'100ml'),
  mk('Cien Óleo Corporal 200ml',2.99,H,'200ml'), mk('Cien Esfoliante Corporal 200ml',2.49,H,'200ml'),
  mk('Cien Máscara Cabelo 300ml',2.49,H,'300ml'), mk('Cien Sérum Olhos 15ml',4.49,H,'15ml'),
  mk('Cien Leite Limpador 200ml',1.99,H,'200ml'), mk('Cien Tónico 200ml',1.99,H,'200ml'),
  mk('Cien Máscara Facial Argila 75ml',2.49,H,'75ml'), mk('Cien Patches Olhos x10',1.99,H,'x10'),
  mk('Cien Verniz Unhas',1.49,H,'unidade'),
];
const higiene_geral = [
  mk('Escova Dentes Cien Soft',0.89,H,'unidade'), mk('Escova Dentes Cien Medium',0.89,H,'unidade'),
  mk('Escova Dentes Cien Kids',0.99,H,'unidade'), mk('Pasta Dentes Cien Clareadora 75ml',0.89,H,'75ml'),
  mk('Pasta Dentes Cien Herbal 75ml',0.99,H,'75ml'), mk('Colutório Cien Clareador 400ml',1.99,H,'400ml'),
  mk('Cien Protetor Lábios FPS30',0.99,H,'unidade'), mk('Cien Creme Pés 100ml',1.29,H,'100ml'),
  mk('Cien Creme Mãos Intensivo 75ml',0.99,H,'75ml'), mk('Cien Tira Poros x6',1.49,H,'x6'),
  mk('Cien Sérum Vitamina C 30ml',5.99,H,'30ml'), mk('Cien Micellar Water 400ml',2.49,H,'400ml'),
  mk('Cien Discos Desmaquilhante x40',1.49,H,'x40'), mk('Cien Fixador Maquilhagem 100ml',2.99,H,'100ml'),
  mk('Cotonetes Lidl x100',0.79,H,'x100'),
];

const HIGIENE_EXTRA = [...higiene_men,...higiene_fem,...higiene_geral];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO I — BEBÉ EXTRA
// ═══════════════════════════════════════════════════════════════════
const bebe_extra = [
  mk('Lupilu Papa Arroz 200g',1.49,BB,'200g'), mk('Lupilu Papa Multicereais 200g',1.49,BB,'200g'),
  mk('Lupilu Saqueta Fruta Maçã Pera 90g',0.89,BB,'90g'), mk('Lupilu Saqueta Fruta Banana Manga 90g',0.89,BB,'90g'),
  mk('Lupilu Saqueta Legumes Cenoura 90g',0.89,BB,'90g'), mk('Lupilu Iogurte Bebé Morango 2x50g',0.89,BB,'2x50g'),
  mk('Lupilu Leite Fórmula 1 800g',9.99,BB,'800g'), mk('Lupilu Leite Fórmula 2 800g',9.99,BB,'800g'),
  mk('Lupilu Fraldas Pants T3 x34',6.49,BB,'x34'), mk('Lupilu Fraldas Pants T4 x28',5.99,BB,'x28'),
  mk('Lupilu Toalhitas Pure 4x56',5.99,BB,'4x56'), mk('Lupilu Sabonete Bebé 2in1 300ml',1.99,BB,'300ml'),
  mk('Lupilu Óleo Amêndoa Bebé 200ml',2.99,BB,'200ml'), mk('Lupilu Pomada Assadura 100ml',2.49,BB,'100ml'),
  mk('Lupilu Protetor Solar Bebé FPS50+ 150ml',5.99,BB,'150ml'),
];
const BEBE_EXTRA = bebe_extra;

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO J — CASA EXTRA
// ═══════════════════════════════════════════════════════════════════
const casa_extra = [
  mk('Silvercrest Ferro Roupa',12.99,CA,'unidade'), mk('Silvercrest Secador Cabelo',9.99,CA,'unidade'),
  mk('Silvercrest Alisador Cabelo',12.99,CA,'unidade'), mk('Silvercrest Aparador Barba',9.99,CA,'unidade'),
  mk('Silvercrest Massajador Pescoço',14.99,CA,'unidade'), mk('Silvercrest Termómetro Infravermelho',14.99,CA,'unidade'),
  mk('Silvercrest Despertador Digital',5.99,CA,'unidade'), mk('Silvercrest Coluna Bluetooth',12.99,CA,'unidade'),
  mk('Silvercrest Power Bank 10000mAh',14.99,CA,'unidade'), mk('Silvercrest Carregador USB Duplo',4.99,CA,'unidade'),
  mk('Caixa Hermética Vidro 1L',4.99,CA,'unidade'), mk('Caixa Hermética Vidro 500ml',3.99,CA,'unidade'),
  mk('Frascos Vidro c/Tampa 4un',3.99,CA,'x4'), mk('Organizador Gaveta 3 divisões',3.49,CA,'unidade'),
  mk('Manta Coral Lidl',5.99,CA,'unidade'), mk('Toalha Banho Lidl',3.99,CA,'unidade'),
  mk('Cabide Anti-Deslizante x5',2.49,CA,'x5'), mk('Fita Métrica 3m',1.99,CA,'unidade'),
  mk('Chave Parafusos Set 4 Peças',2.99,CA,'set'), mk('Martelo Lidl',3.99,CA,'unidade'),
  mk('Fita Isolante x3',1.29,CA,'x3'), mk('Parafusos Sortidos x100',1.49,CA,'x100'),
];
const CASA_EXTRA = casa_extra;

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO K — CHOCOLATES + ANIMAIS + FITNESS EXTRA
// ═══════════════════════════════════════════════════════════════════
const choc_extra = [
  mk('Fin Carré Chocolate Negro 70% Bio 100g',1.19,CH,'100g'),
  mk('Fin Carré Chocolate Leite Quinoa 100g',0.89,CH,'100g'),
  mk('Fin Carré Trufas Caixa x12',2.99,CH,'x12'),
  mk('Favorina Gomas Verme Mix 400g',1.49,CH,'400g'),
  mk('Favorina Chocolate Leite Avelã 250g',1.29,CH,'250g'),
  mk('Favorina Caixa Bombons 200g',2.99,CH,'200g'),
  mk('Favorina Caramelos Manteiga 200g',0.99,CH,'200g'),
  mk('Favorina Marshmallows 200g',0.99,CH,'200g'),
  mk('Favorina Gomas Morango 200g',0.99,CH,'200g'),
  mk('Favorina Regaliz Sortido 200g',0.99,CH,'200g'),
  mk('Deluxe Trufas Champanhe x12',4.99,CH,'x12'),
  mk('Deluxe Pralinés Bélgicos x12',3.99,CH,'x12'),
  mk('Lidl Amendoim Caramelizado 150g',0.99,CH,'150g'),
  mk('Lidl Pop Corn Caramelo Chocolate 150g',1.29,CH,'150g'),
  mk('Doce Morango Lidl 450g',1.29,CH,'450g'),
  mk('Doce Pêssego Lidl 450g',1.29,CH,'450g'),
  mk('Doce Framboesa Lidl 450g',1.29,CH,'450g'),
  mk('Marmelada Lidl 450g',0.99,CH,'450g'),
];
const animais_extra = tpl('Lidl', [
  ['Ração Gato Sterilised Salmão',3.49,5.99],['Ração Gato Indoor',3.49,null],
  ['Ração Cão Mini Ativo',4.49,null],['Ração Cão Filhote',4.49,null],
  ['Ração Cão Adulto Light',3.99,5.99],['Gato Patê Peixe do Mar',0.49,null],
  ['Gato Patê Carne com Legumes',0.49,null],['Cão Patê Vitela',0.69,null],
  ['Gato Snacks Dentais',1.79,null],['Cão Snacks Osso Natural',1.99,null],
], [['400g',0],['900g',1]], AN);
const fitness_extra = [
  mk('Frango Pré-Cozinhado Tiras 150g',2.99,FT,'150g'),
  mk('Batido Proteínas Morango RTD 330ml',2.49,FT,'330ml'),
  mk('Iogurte Skyr Proteínas Baunilha 150g',1.29,FT,'150g'),
  mk('Iogurte Skyr Proteínas Chocolate 150g',1.29,FT,'150g'),
  mk('Mix Sementes Proteínas 150g',2.49,FT,'150g'),
  mk('Crackers Proteínas x5',1.99,FT,'x5'),
  mk('Aveia Instant com Proteína 500g',2.49,FT,'500g'),
  mk('Whey Protein Chocolate Lidl 1kg',16.99,FT,'1kg'),
  mk('BCAA Limão 300g',9.99,FT,'300g'),
  mk('Colagénio Lidl 300g',12.99,FT,'300g'),
];

const EXTRAS_MISC = [...choc_extra,...animais_extra,...fitness_extra];

// ═══════════════════════════════════════════════════════════════════
// 16. SEM GLÚTEN / SEM LACTOSE (~60 produtos)
// ═══════════════════════════════════════════════════════════════════
const SG = 'Sem Glúten / Sem Lactose';

const semGluten = tpl('Combino SG', [
  ['Pão de Forma',2.49,null],
  ['Pão Rústico',2.29,null],
  ['Farinha Universal',1.49,null],
  ['Massa Penne',1.19,null],
  ['Massa Fusilli',1.19,null],
  ['Esparguete',1.29,null],
  ['Crackers',1.49,null],
  ['Bolachas Arroz',1.29,null],
  ['Flocos Aveia',1.99,null],
  ['Granola',2.49,null],
  ['Cereais Pequeno-Almoço',2.29,null],
  ['Pizza Base',2.99,null],
  ['Barras Cereais x4',1.99,null],
], [['400g',0]], SG);

const semLactose = tpl('Milbona SL', [
  ['Leite Meio-Gordo',1.09,null],
  ['Leite Gordo',1.09,null],
  ['Iogurte Natural',0.79,null],
  ['Iogurte Morango',0.89,null],
  ['Queijo Creme',1.79,null],
  ['Queijo Fundido Fatiado',1.99,null],
  ['Manteiga',1.79,null],
  ['Natas Cozinhar',1.19,null],
], [['1L',0]], SG);

const SEM_GLUTEN = [...semGluten,...semLactose];

// ═══════════════════════════════════════════════════════════════════
// TOTAL
// ═══════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO M — MERCEARIA WAVE 3 (mais tipos × 3 tamanhos)
// ═══════════════════════════════════════════════════════════════════
const pasta3 = tpl('Combino', [
  ['Esparguete de Trigo Duro',0.55,0.99,1.89],['Penne de Trigo Duro',0.55,0.99,1.89],
  ['Fusilli de Trigo Duro',0.55,0.99,1.89],['Farfalle de Trigo Duro',0.59,1.09,null],
  ['Tagliatelle Ovos',0.89,1.59,null],['Fettuccine Ovos',0.89,1.59,null],
  ['Gnocchi di Patate',0.99,1.79,null],['Lasanha Rígida',0.99,1.79,null],
  ['Conchiglie Rigate',0.55,0.99,null],['Radiatori',0.55,0.99,null],
  ['Trofie',0.69,1.19,null],['Cavatappi',0.55,0.99,null],
], [['500g',0],['1kg',1],['2kg',2]], M);

const arroz3 = tpl('Combino', [
  ['Arroz Agulha Extra',0.85,1.59,3.49],['Arroz Carolino Extra',0.95,1.79,3.79],
  ['Arroz Basmati Extra',1.25,2.29,null],['Arroz Parboilizado Extra',0.95,1.75,null],
  ['Arroz Integral Longo',1.05,1.89,null],['Arroz Aromático Tailandês',1.35,2.49,null],
], [['1kg',0],['2kg',1],['5kg',2]], M);

const azeites3 = tpl('', [
  ['Azeite Bio Lidl',2.99,5.49,9.99],['Azeite Virgem Lidl',1.99,3.79,7.49],
  ['Sol & Mar Azeite Premium',3.49,6.49,null],['Eridanous Azeite DOP',4.99,null,null],
  ['Italiamo Olio di Oliva',1.99,3.79,null],
], [['500ml',0],['1L',1],['2L',2]], M);

const conservas3 = tpl('', [
  ['Atum Albacore Lidl',0.99,1.89,null],['Atum Claro Lidl',0.79,1.49,null],
  ['Sardinha Premium Sol & Mar',0.89,null,null],['Cavala Limão Lidl',0.65,1.19,null],
  ['Carapau Tomate Lidl',0.59,1.09,null],['Arenque Pickles Lidl',1.49,null,null],
  ['Salmão Rosa Lidl',1.99,null,null],['Anchova Premium Italiamo',1.49,null,null],
], [['125g',0],['3x125g',1]], M);

const molhos3 = tpl('Italiamo', [
  ['Sugo Arrabbiata',0.99,1.79],['Sugo al Pomodoro',0.89,1.59],
  ['Sugo Basilico',0.89,1.59],['Pesto Ligure',1.69,null],
  ['Sugo Amatriciana',0.99,1.79],['Sugo Funghi',0.99,1.79],
  ['Sugo Norcina',1.19,null],['Salsa Verde',1.49,null],
], [['180g',0],['350g',1]], M);

const cereais3 = tpl('Crownfield', [
  ['Granola Chocolate Branco',2.29,3.99],['Granola Caramelo Salgado',2.29,3.99],
  ['Granola Coco Manga',2.29,null],['Granola Pistáchio',2.49,null],
  ['Muesli Crunchy Mel',1.99,3.49],['Muesli Crunchy Frutos',1.99,3.49],
  ['Porridge Aveia Banana',1.39,null],['Porridge Aveia Chocolate',1.39,null],
  ['Flocos Aveia com Frutas',1.29,null],['Cereais Ancestrais Espelta',1.89,null],
], [['500g',0],['1kg',1]], M);

const bolachas3 = tpl('Sondey', [
  ['Bolachas Baunilha Açúcar',0.99,1.69],['Bolachas Amêndoa',1.29,2.19],
  ['Bolachas Creme Cacau',0.99,1.69],['Bolachas Caramelo',1.09,null],
  ['Crackers Queijo',0.89,null],['Crackers Alecrim',0.89,null],
  ['Wafers Pistáchio',1.09,null],['Wafers Coco',0.99,null],
  ['Cookies Chocolate Chip',1.19,null],['Cookies Aveia Passas',1.09,null],
  ['Bolachas Pipoca Caramelo',1.09,null],['Cookies Manteiga Amendoim',1.29,null],
], [['200g',0],['400g',1]], M);

const snacks3 = tpl('Mcennedy', [
  ['Cheddar Puffs',0.99,null],['Cheddar Twists',0.99,null],
  ['Corn Chips Jalapeño',0.99,null],['Pretzels Manteiga',1.09,null],
  ['Popcorn Doce Salgado',0.99,null],['Peanuts Wasabi',1.19,null],
  ['Mixed Nuts BBQ',1.79,null],['Trail Mix Energy',1.79,null],
  ['Pork Crackling',1.99,null],['Veggie Crisps',1.49,null],
], [['125g',0]], M);

const especiarias3 = [
  mk('Mistura 7 Especiarias 40g',0.89,M,'40g'), mk('Zaatar Mix 35g',0.99,M,'35g'),
  mk('Berbere Etíope 35g',0.99,M,'35g'), mk('Furikake Vitasia 50g',1.29,M,'50g'),
  mk('Shichimi Togarashi Vitasia 30g',1.29,M,'30g'), mk('Dashi Pó Vitasia 50g',1.49,M,'50g'),
  mk('Caldo Pó Legumes Lidl 150g',0.99,M,'150g'), mk('Caldo Pó Frango Lidl 150g',0.99,M,'150g'),
  mk('Pimenta Cubeba 30g',1.29,M,'30g'), mk('Aniz Estrelado 15g',0.79,M,'15g'),
  mk('Cardamomo Verde Inteiro 20g',0.99,M,'20g'), mk('Cravinho Inteiro 20g',0.79,M,'20g'),
  mk('Curcuma Bio 30g',0.99,M,'30g'), mk('Paprika Fumada Bio 40g',0.89,M,'40g'),
  mk('Fleur de Sel Bretagne 125g',1.99,M,'125g'),
];

const MERCEARIA_W3 = [...pasta3,...arroz3,...azeites3,...conservas3,...molhos3,...cereais3,...bolachas3,...snacks3,...especiarias3];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO N — LATICÍNIOS + BEBIDAS WAVE 3
// ═══════════════════════════════════════════════════════════════════
const leite3 = tpl('Milbona', [
  ['Leite UHT Meio-Gordo',0.65,1.25,2.35],
  ['Leite UHT Gordo',0.68,1.29,2.45],
  ['Leite UHT Magro',0.62,1.19,2.25],
  ['Leite UHT s/Lactose',0.95,1.85,null],
  ['Leite Enriquecido Vitaminas',0.79,1.49,null],
  ['Leite Proteínas',0.89,1.65,null],
], [['1L',0],['2L',1],['6x1L',2]], L);

const iog3 = tpl('Milbona', [
  ['Iogurte Soja Mirtilo',0.79,1.39],['Iogurte Soja Pêssego',0.79,1.39],
  ['Iogurte Aveia Natural',0.89,null],['Iogurte Aveia Morango',0.89,null],
  ['Iogurte Coco Maracujá',0.89,null],['Iogurte Bifidus Ameixa',0.79,null],
  ['Iogurte Probiótico Natural',0.69,1.25],['Iogurte Probiótico Frutos',0.79,null],
  ['Iogurte Batido Morango',0.49,null],['Iogurte Batido Pêssego',0.49,null],
  ['Iogurte Sobremesa Chocolate',0.79,null],['Iogurte Sobremesa Caramelo',0.79,null],
], [['125g',0],['4x125g',1]], L);

const queijo3 = tpl('Milbona', [
  ['Queijo Gouda Jovem Bloco',1.99,3.79],['Queijo Edam Bloco',1.89,3.59],
  ['Queijo Cheddar Vermelho Bloco',2.19,null],['Queijo Emmental Bloco',2.29,null],
  ['Queijo Parmesão Rallado',2.19,null],['Queijo Mozzarella Rallado Mix',1.69,null],
  ['Queijo Gruyère Fatiado',2.49,null],['Queijo Gouda Curado Fatiado',2.29,null],
], [['200g',0],['400g',1]], L);

const beb3_agua = tpl('Lidl', [
  ['Água Natural Clássica',0.19,0.29,0.49],['Água Natural Premium',0.29,0.45,0.69],
  ['Água c/Gás Clássica',0.25,0.39,null],['Água c/Gás Limão',0.35,null,null],
], [['500ml',0],['1.5L',1],['6x1.5L',2]], B);

const beb3_ref = tpl('Freeway', [
  ['Tónica Clássica',0.35,0.69,null],['Tónica Limão',0.35,0.69,null],
  ['Bitter Lemon',0.35,null,null],['Ginger Ale',0.39,null,null],
  ['Limonada',0.35,0.69,null],['Laranjada',0.35,0.69,null],
  ['Grenadine',0.99,null,null],['Xarope Hortelã',0.99,null,null],
  ['Xarope Groselha',0.99,null,null],['Ice Tea Limão Zero',0.35,0.69,null],
], [['330ml',0],['1.5L',1]], B);

const LATBEB_W3 = [...leite3,...iog3,...queijo3,...beb3_agua,...beb3_ref];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO O — CONGELADOS + PADARIA WAVE 3
// ═══════════════════════════════════════════════════════════════════
const cong3_peixe = tpl('', [
  ['Salmão Inteiro Congelado',6.99,null],['Atum Postas Congelado',5.99,null],
  ['Bacalhau Lascas Congelado',4.99,8.99],['Bacalhau Migas Congelado',3.99,null],
  ['Panga Filetes Congelados',2.99,4.99],['Tilápia Filetes Congelados',3.99,null],
  ['Camarão Descascado Congelado',5.99,null],['Polvo Inteiro Congelado',5.49,null],
  ['Mariscos Mix Congelado',5.99,null],['Vieiras Congeladas 8un',7.99,null],
], [['400g',0],['800g',1]], C);

const cong3_legumes = tpl('Lidl', [
  ['Mix Legumes Asiáticos',1.29,null],['Mix Legumes Mediterrânicos',1.29,null],
  ['Espinafres Folha Congelado',0.99,1.79],['Bruxelas Congeladas',1.09,null],
  ['Espargos Congelados',1.49,null],['Cogumelos Congelados',1.49,null],
  ['Abóbora Cubed Congelada',0.99,null],['Beterraba Congelada',0.79,null],
  ['Batata Wedges Congelada',1.09,1.99],['Batata Assada Congelada',1.09,null],
], [['450g',0],['900g',1]], C);

const padaria3_pao = tpl('', [
  ['Pão Espelta Lidl',1.99,null],['Pão de Aveia Lidl',1.79,null],
  ['Pão Multi-Sementes Lidl',1.99,null],['Pão Rústico Caseiro Lidl',1.49,null],
  ['Pão Alho Lidl',1.29,null],['Pão Espiral Queijo Lidl',1.49,null],
  ['Pão de Cebola Lidl',1.29,null],['Pão Orégãos Lidl',1.29,null],
  ['Pão Mini Rolls x6',1.29,null],['Bolo Inglês Lidl',1.49,null],
], [['400g',0]], P);

const padaria3_paste = [
  mk('Croissant Amêndoa Lidl',1.29,P,'unidade'), mk('Danish Maçã x4',1.99,P,'x4'),
  mk('Danish Frutos Vermelhos x4',1.99,P,'x4'), mk('Bolinho Baunilha Creme x2',1.49,P,'x2'),
  mk('Tarte Mirtilos Individual',1.49,P,'unidade'), mk('Tarte Morango Individual',1.49,P,'unidade'),
  mk('Eclair Caramelo x2',1.99,P,'x2'), mk('Mini Croissant Amêndoa x6',1.99,P,'x6'),
  mk('Bicho de Conta x2',0.99,P,'x2'), mk('Palmier Caramelizado x4',1.49,P,'x4'),
  mk('Chouriço em Massa x2',1.99,P,'x2'), mk('Linguiça em Massa x2',1.99,P,'x2'),
  mk('Pizza Pão Tomate Queijo',1.29,P,'unidade'), mk('Focaccia Alecrim Lidl',1.49,P,'unidade'),
  mk('Brioche Cacau Lidl',1.79,P,'unidade'),
];

const CONGPAD_W3 = [...cong3_peixe,...cong3_legumes,...padaria3_pao,...padaria3_paste];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO P — HIGIENE + LIMPEZA WAVE 3
// ═══════════════════════════════════════════════════════════════════
const cien3 = tpl('Cien', [
  ['Champô Reparador Queratina',1.69,2.79],['Champô Proteção Cor',1.69,2.79],
  ['Champô Hidratante Argan',1.69,2.79],['Gel Duche Coco',1.29,1.99],
  ['Gel Duche Verbena',1.29,1.99],['Gel Duche Aloe Vera',1.29,1.99],
  ['Sabonete Exfoliante Apricot',1.49,null],['Creme Hidratante Aloe Vera',1.99,null],
  ['Creme Hidratante Urea 10%',2.49,null],['Soro Anti-Manchas',4.99,null],
  ['Gel Contorno Olhos',3.49,null],['BB Cream FPS20',3.49,null],
  ['Spray Bronzeador',3.99,null],['Pó Solto Bronze',2.99,null],
], [['300ml',0],['500ml',1]], H);

const pilos3 = tpl('Pilos', [
  ['Champô Argan',1.69,2.79],['Champô Biotina',1.69,2.79],
  ['Champô Coconut',1.49,2.49],['Condicionador Argan',1.49,2.49],
  ['Condicionador Biotina',1.49,2.49],['Condicionador Coconut',1.49,2.49],
  ['Sérum Cabelo Anti-Frizz',2.99,null],['Óleo Cabelo Argan',2.99,null],
], [['300ml',0],['500ml',1]], H);

const formil3 = tpl('Formil', [
  ['Detergente Bio Color',3.99,6.99],['Detergente Bio Branco',3.99,6.99],
  ['Gel Roupa Delicadas',3.49,null],['Gel Lã e Seda',3.49,null],
  ['Cápsulas 3in1 Color x30',5.49,null],['Cápsulas 3in1 Branco x30',5.49,null],
  ['Amaciador Primavera',2.49,3.99],['Amaciador Brisa do Mar',2.49,3.99],
], [['1.5L',0],['3L',1]], LI);

const w5_3 = tpl('W5', [
  ['Spray Desengordurante',1.49,2.49],['Spray Brilho Aço Inox',1.49,null],
  ['Pastilhas Banho x6',1.29,null],['Limpa Janelas c/Microfibra',2.49,null],
  ['Gel Escova WC',0.99,null],['Pó Cleanser',1.49,null],
  ['Spray Antimofo',1.99,null],['Spray Limpa Tapetes',2.49,null],
], [['500ml',0],['1L',1]], LI);

const HIGLIE_W3 = [...cien3,...pilos3,...formil3,...w5_3];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO Q — FRESCOS + ANIMAIS + BIO WAVE 3
// ═══════════════════════════════════════════════════════════════════
const frescos3_carne = tpl('', [
  ['Frango Peito s/Osso Marinado Limão',5.49,null],
  ['Frango Coxas Marinadas Paprika',3.99,null],
  ['Porco Lombo Assado Preparado',5.99,null],
  ['Vaca Rosbife Marinado',7.99,null],
  ['Pato Confit Coxas Pack',7.99,null],
  ['Avestruz Medallhões',6.99,null],
  ['Javali Salsichas 300g',4.99,null],
  ['Carne Picada Mista',3.99,6.99],
  ['Carne Picada Peru',3.49,null],
  ['Porco Entrecosto Temperado',4.49,null],
], [['300g',0],['600g',1]], FR);

const frescos3_peixe = tpl('', [
  ['Bacalhau Postas Demolhadas',6.99,null],
  ['Salmão Tranches sem Pele',7.99,null],
  ['Dourada Filetes Frescos',5.99,null],
  ['Robalo Filetes Frescos',5.99,null],
  ['Camarão Cozido Inteiro',5.99,null],
  ['Amêijoa Boa Fresca',5.99,null],
  ['Marisco Mix Fresco',7.99,null],
  ['Bacalhau Salgado Verde',5.99,null],
], [['300g',0]], FR);

const bio3 = tpl('Bio Lidl', [
  ['Massa Penne Integral',1.19,null],['Massa Fusilli Integral',1.19,null],
  ['Massa Esparguete Integral',1.19,null],['Arroz Agulha',1.59,2.99],
  ['Aveia Instant',1.29,null],['Quinoa',2.99,null],
  ['Lentilhas Vermelhas',1.09,null],['Grão de Bico',1.09,null],
  ['Tomate Pelado',0.89,null],['Polpa Tomate',0.79,null],
  ['Ketchup',1.49,null],['Mostarda Dijon',1.29,null],
  ['Azeite Extra Virgem',5.99,null],['Óleo Girassol',1.79,null],
  ['Manteiga Amendoim',2.99,null],['Mel Multifloral',4.99,null],
  ['Farinha Trigo',1.09,null],['Açúcar Cana',1.19,null],
], [['500g',0],['1kg',1]], BI);

const animais3 = [
  mk('Whiskas Style Gato Frango 12x85g',5.99,AN,'12x85g'),
  mk('Pedigree Style Cão Carne 12x100g',5.99,AN,'12x100g'),
  mk('Ração Gato Sénior Lidl 400g',3.99,AN,'400g'),
  mk('Ração Gato Adulto Mix Peixe 1.5kg',4.99,AN,'1.5kg'),
  mk('Ração Cão Sénior Lidl 400g',3.99,AN,'400g'),
  mk('Ração Cão Adulto Mix Carne 1.5kg',5.99,AN,'1.5kg'),
  mk('Ração Cão Mini 1.5kg',6.99,AN,'1.5kg'),
  mk('Snacks Cão Dental Lidl 200g',2.49,AN,'200g'),
  mk('Snacks Gato Frango Lidl 50g',0.99,AN,'50g'),
  mk('Snacks Gato Atum Lidl 50g',0.99,AN,'50g'),
  mk('Caixa Transporte Gato/Cão Lidl',9.99,AN,'unidade'),
  mk('Tapete Higiénico Cão x20',3.49,AN,'x20'),
];

const FRESANI_W3 = [...frescos3_carne,...frescos3_peixe,...bio3,...animais3];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO R — BEBÉ + CASA + FITNESS WAVE 3
// ═══════════════════════════════════════════════════════════════════
const bebe3 = tpl('Lupilu', [
  ['Fraldas T1 Premium',3.29,6.29],['Fraldas T2 Premium',3.79,6.99],
  ['Fraldas T3 Premium',4.29,7.79],['Fraldas T4 Premium',4.79,8.49],
  ['Fraldas T5 Premium',5.29,9.49],['Fraldas T6 Premium',5.79,10.49],
  ['Toalhitas Sensitive Premium',2.29,4.29],['Toalhitas Pure Premium',1.99,3.79],
], [['x24',0],['x48',1]], BB);

const casa3_tools = tpl('Silvercrest', [
  ['Freidora de Ar 4L',39.99,null],['Mini Grill 1500W',24.99,null],
  ['Processador Alimentos',29.99,null],['Batedeira de Mão',19.99,null],
  ['Cafeteira Filtro',14.99,null],['Espremedor Citrinos',9.99,null],
  ['Escova de Dentes Elétrica',7.99,null],['Liquidificador',19.99,null],
], [['unidade',0]], CA);

const fitnes3 = [
  mk('Lidl Sport Iso Drink Limão 500ml',1.49,FT,'500ml'),
  mk('Lidl Sport Iso Drink Laranja 500ml',1.49,FT,'500ml'),
  mk('Lidl Sport Iso Drink Frutos 500ml',1.49,FT,'500ml'),
  mk('Lidl Sport Energy Gel Baunilha 40g',1.49,FT,'40g'),
  mk('Lidl Sport Energy Gel Laranja 40g',1.49,FT,'40g'),
  mk('Lidl Sport Creatina 500g',12.99,FT,'500g'),
  mk('Lidl Sport Ômega 3 90 cápsulas',6.99,FT,'x90 cápsulas'),
  mk('Lidl Sport Vitamina D3 60 cápsulas',3.99,FT,'x60 cápsulas'),
  mk('Lidl Sport Magnésio 300mg x60',3.99,FT,'x60 comprimidos'),
  mk('Lidl Sport Multivitamínico x60',4.99,FT,'x60 comprimidos'),
  mk('Lidl Sport B12 x60',2.99,FT,'x60 comprimidos'),
  mk('Lidl Sport Ferro x60',2.99,FT,'x60 comprimidos'),
  mk('Lidl Sport Zinco x60',2.99,FT,'x60 comprimidos'),
  mk('Lidl Sport Proteína Vegetal Pea 750g',14.99,FT,'750g'),
  mk('Lidl Sport Proteína Hemp 500g',12.99,FT,'500g'),
];

const BEBCAFIT_W3 = [...bebe3,...casa3_tools,...fitnes3];

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO S — PRODUTOS DELI / ESPECIALIDADES (~100)
// ═══════════════════════════════════════════════════════════════════
const deli = [
  mk('Deluxe Tábua Aperitivos Mix',6.99,'Regional e Deli','unidade'),
  mk('Deluxe Queijo Manchego DOP 200g',5.49,'Regional e Deli','200g'),
  mk('Deluxe Pata Negra 100g',6.99,'Regional e Deli','100g'),
  mk('Deluxe Alheira Premium 200g',3.49,'Regional e Deli','200g'),
  mk('Deluxe Chouriço Trufado 150g',4.99,'Regional e Deli','150g'),
  mk('Deluxe Presunto Ibérico Bellota 80g',5.99,'Regional e Deli','80g'),
  mk('Deluxe Sobrasada Mallorquina 200g',3.99,'Regional e Deli','200g'),
  mk('Deluxe Terrina Foie Gras 100g',4.99,'Regional e Deli','100g'),
  mk('Deluxe Rillettes de Pato 180g',3.49,'Regional e Deli','180g'),
  mk('Deluxe Tarama Luxo 200g',2.99,'Regional e Deli','200g'),
  mk('Deluxe Salmão Fumado Premium 200g',5.99,'Regional e Deli','200g'),
  mk('Deluxe Truta Fumada 100g',2.99,'Regional e Deli','100g'),
  mk('Deluxe Bacalhau Fumado 100g',3.49,'Regional e Deli','100g'),
  mk('Eridanous Saganaki Frito',2.99,'Regional e Deli','unidade'),
  mk('Eridanous Tzatziki Premium 400g',2.49,'Regional e Deli','400g'),
  mk('Eridanous Hummus Trufa 200g',2.99,'Regional e Deli','200g'),
  mk('Italiamo Antipasto Misto 280g',3.49,'Regional e Deli','280g'),
  mk('Italiamo Bresaola Vaca 100g',3.99,'Regional e Deli','100g'),
  mk('Italiamo Mortadella Pistáchio 100g',2.49,'Regional e Deli','100g'),
  mk('Italiamo Focaccia Rosmarino 400g',1.99,'Regional e Deli','400g'),
  mk('Sol & Mar Pataniscas Artesanais 300g',2.99,'Regional e Deli','300g'),
  mk('Sol & Mar Sardinha Escabeche 250g',2.49,'Regional e Deli','250g'),
  mk('Sol & Mar Atum Ventresca Premium 110g',4.99,'Regional e Deli','110g'),
  mk('Sol & Mar Polvo Galiza 190g',2.99,'Regional e Deli','190g'),
  mk('Queijo Azul Velho 100g',2.99,'Regional e Deli','100g'),
  mk('Queijo Flamengo Extra 200g',1.99,'Regional e Deli','200g'),
  mk('Queijo S. Jorge Curado 200g',3.99,'Regional e Deli','200g'),
  mk('Queijo Ilha Curado 150g',3.49,'Regional e Deli','150g'),
  mk('Queijo Nisa DOP 200g',4.49,'Regional e Deli','200g'),
  mk('Queijo Évora DOP 150g',3.99,'Regional e Deli','150g'),
  mk('Queijo Serpa DOP 200g',4.49,'Regional e Deli','200g'),
  mk('Chouriço de Estremoz 200g',3.99,'Regional e Deli','200g'),
  mk('Morcela de Assar 200g',2.99,'Regional e Deli','200g'),
  mk('Farinheira Fumada 200g',2.49,'Regional e Deli','200g'),
  mk('Salpicão Transmontano 150g',3.99,'Regional e Deli','150g'),
];

const DELI_W3 = deli;

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO T — WAVE 4 (800+ produtos únicos garantidos)
// ═══════════════════════════════════════════════════════════════════

// Combino pasta novos formatos (nunca listados)
const pastaW4 = tpl('Combino', [
  ['Capellini',0.55,0.99],['Vermicelli',0.55,0.99],['Bucatini',0.59,1.09],
  ['Pappardelle',0.69,1.19],['Mafaldine',0.69,1.19],['Strozzapreti',0.65,1.09],
  ['Casarecce',0.65,1.09],['Garganelli Ovos',0.89,null],
  ['Massa Cuscuz Marroquino',0.99,null],['Orzo Pasta',0.69,1.19],
], [['500g',0],['1kg',1]], M);

// Crownfield — mais formatos de embalagem
const cerW4 = tpl('Crownfield', [
  ['Porridge Cup Banana',0.99,null],['Porridge Cup Mirtilo',0.99,null],
  ['Granola Bar Caramelo',0.49,null],['Granola Bar Mirtilo',0.49,null],
  ['Muesli Fitness Proteína',1.99,null],['Cereais Anel Mel',1.29,null],
  ['Cereais Anel Cacau',1.29,null],['Flocos 4 Cereais',1.19,null],
], [['45g',0]], M);

// Sondey — variantes novas
const bolW4 = tpl('Sondey', [
  ['Cookies Duplo Chocolate',1.29,null],['Cookies Canela',1.09,null],
  ['Bolachas Mel Integral',0.99,1.59],['Crackers Multigrain',0.89,null],
  ['Wafers Tiramisù',1.09,null],['Wafers Caramelo',1.09,null],
  ['Bolachas Espelta Mel',1.19,null],['Bolachas Arroz Alga',1.09,null],
  ['Mini Twists Sal',0.79,null],['Stroopwafels x8',1.49,null],
], [['200g',0],['400g',1]], M);

// Mcennedy — variantes novas
const snkW4 = tpl('Mcennedy', [
  ['Dip Cheddar 275g',1.29,null],['Dip Jalapeño 275g',1.29,null],
  ['Dip Nachos Queijo 275g',1.29,null],['Crackers Milho',0.99,null],
  ['Peanut Butter Smooth 280g',2.49,null],['Peanut Butter Crunchy 280g',2.49,null],
  ['Mixed Nuts Roasted 200g',2.49,null],['Sesame Sticks 150g',1.09,null],
], [['150g',0]], M);

// Bellarom cápsulas novos sabores
const cafW4 = [
  mk('Bellarom Cápsulas Lungo x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Cappuccino x10',2.49,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Lungo Forte x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Vanilla Latte x10',2.49,M,'10 cápsulas'),
  mk('Deluxe Café Monsoon Malabar 250g',4.49,M,'250g'),
  mk('Deluxe Café Sumatra 250g',4.49,M,'250g'),
  mk('Deluxe Café Kenia 250g',4.49,M,'250g'),
  mk('Bellarom Cold Brew Concentrate 500ml',2.99,M,'500ml'),
  mk('Bellarom Café Moído Espresso 250g',1.99,M,'250g'),
  mk('Bellarom Café em Grão Arabica 1kg',7.99,M,'1kg'),
];

// Vitasia — produtos premium e novos
const vitW4 = [
  mk('Vitasia Tofu Frito Pré-Cozinhado 200g',2.49,M,'200g'),
  mk('Vitasia Tempeh Fumado 200g',3.29,M,'200g'),
  mk('Vitasia Alga Wakame Seca 40g',1.99,M,'40g'),
  mk('Vitasia Alga Kombu Seca 50g',1.99,M,'50g'),
  mk('Vitasia Macarrão de Arroz 400g',1.49,M,'400g'),
  mk('Vitasia Arroz Glutinoso 1kg',1.79,M,'1kg'),
  mk('Vitasia Pasta de Amendoim Asiática 350g',2.99,M,'350g'),
  mk('Vitasia Molho XO 100ml',2.99,M,'100ml'),
  mk('Vitasia Molho Bulgogi 200ml',1.99,M,'200ml'),
  mk('Vitasia Curry em Bloco Japonês 100g',1.79,M,'100g'),
  mk('Vitasia Molho Ponzu 150ml',1.99,M,'150ml'),
  mk('Vitasia Kecap Manis 200ml',1.49,M,'200ml'),
];

// Condimentos e molhos novos
const condW4 = [
  mk('Mostarda Antiga c/Ervas 200g',1.49,M,'200g'),
  mk('Mostarda Mel e Alho 200g',1.09,M,'200g'),
  mk('Aioli Sol & Mar 200ml',1.49,M,'200ml'),
  mk('Romesco Sol & Mar 200g',1.79,M,'200g'),
  mk('Chimichurri Argentino 200ml',1.99,M,'200ml'),
  mk('Molho Frank Hot Original 148ml',1.99,M,'148ml'),
  mk('Tabasco Chipotle 60ml',2.49,M,'60ml'),
  mk('Picante Madeira 150ml',1.49,M,'150ml'),
  mk('Ketchup Bio Lidl 450g',1.49,M,'450g'),
  mk('Maionese Trufa Negra 200ml',3.49,M,'200ml'),
  mk('Molho Tahini Eridanous 300g',1.99,M,'300g'),
  mk('Pasta Sesamo Preto 250g',1.99,M,'250g'),
];

// Eridanous novos produtos
const eridW4 = [
  mk('Eridanous Spanakopita Mini x8',2.99,M,'x8'),
  mk('Eridanous Tiropita Mini x8',2.99,M,'x8'),
  mk('Eridanous Kolokithopita Courgette',2.99,M,'400g'),
  mk('Eridanous Pastitsio 400g',2.99,M,'400g'),
  mk('Eridanous Saganaki Cheese 200g',2.49,M,'200g'),
  mk('Eridanous Kefalotyri 150g',2.99,M,'150g'),
  mk('Eridanous Mizithra 200g',2.49,M,'200g'),
  mk('Eridanous Mastiha Goma Mascar x10',1.99,M,'x10'),
  mk('Eridanous Suco Romã Grego 1L',2.99,M,'1L'),
  mk('Eridanous Loukoumades Frito 400g',2.99,M,'400g'),
];

const MERC_W4 = [...pastaW4,...cerW4,...bolW4,...snkW4,...cafW4,...vitW4,...condW4,...eridW4];

// ─── Frescos Wave 4 ───────────────────────────────────────────────
const frescW4 = [
  mk('Frango Maryland 2un',3.99,FR,'2 unidades'),
  mk('Frango Desossado Recheado',6.99,FR,'unidade'),
  mk('Pato Magret Fresco 2un',7.99,FR,'2 unidades'),
  mk('Rabo de Boi 500g',4.99,FR,'500g'),
  mk('Tutano Vaca 500g',3.49,FR,'500g'),
  mk('Osso Vaca c/Tutano 2un',3.99,FR,'2 unidades'),
  mk('Coração Frango 500g',2.49,FR,'500g'),
  mk('Moela Frango 500g',1.99,FR,'500g'),
  mk('Figado Vaca 400g',3.49,FR,'400g'),
  mk('Rim Vaca 400g',2.99,FR,'400g'),
  mk('Tripa Porco 200g',2.99,FR,'200g'),
  mk('Chouriço de Carne Fresco 250g',3.49,FR,'250g'),
  mk('Salpicão Fresco 250g',3.99,FR,'250g'),
  mk('Carne de Porco à Alentejana 500g',6.99,FR,'500g'),
  mk('Mix Marisco Fresco 400g',8.99,FR,'400g'),
  mk('Ovas de Salmão 100g',4.99,FR,'100g'),
  mk('Ikura Salmão 100g',6.99,FR,'100g'),
  mk('Truta Fumada 150g',3.49,FR,'150g'),
  mk('Arenque Marinado 200g',2.49,FR,'200g'),
  mk('Bacalhau à Lagareiro Preparado 400g',5.99,FR,'400g'),
  mk('Robalo Inteiro Limpo',5.99,FR,'~300g'),
  mk('Dourada Inteira Limpa',5.49,FR,'~250g'),
  mk('Polvo Pequeno 400g',5.99,FR,'400g'),
  mk('Búzios 500g',5.49,FR,'500g'),
  mk('Percebes 200g',7.99,FR,'200g'),
  mk('Camarão Inteiro Cru 500g',6.99,FR,'500g'),
  mk('Lagosta Mini 2un',9.99,FR,'2 unidades'),
  mk('Espigola Filetes 300g',5.99,FR,'300g'),
  mk('Ruivo Filetes 300g',4.99,FR,'300g'),
  mk('Linguado Inteiro',4.99,FR,'unidade'),
];

// ─── Laticínios Wave 4 ───────────────────────────────────────────
const latW4 = tpl('Milbona', [
  ['Iogurte Limão com Granola',1.09,null],['Iogurte Maçã Canela',0.79,null],
  ['Iogurte Ananás Coco',0.79,null],['Iogurte Toranja',0.79,null],
  ['Iogurte Fruta da Paixão',0.79,null],['Iogurte Lichie',0.79,null],
  ['Iogurte Mango Maracujá',0.79,null],['Iogurte Kiwi',0.79,null],
  ['Iogurte Grego Baunilha Mel',0.99,null],['Iogurte Grego Maracujá',0.99,null],
  ['Iogurte Grego Caramelo',0.99,null],['Iogurte Grego Coco',0.99,null],
], [['150g',0]], L);

const latW4b = [
  mk('Milbona Creme Azedo 200ml',0.89,L,'200ml'),
  mk('Milbona Laban Ayran 500ml',1.19,L,'500ml'),
  mk('Milbona Lassi Mango 250ml',1.29,L,'250ml'),
  mk('Milbona Lassi Natural 250ml',1.19,L,'250ml'),
  mk('Milbona Bebida Proteína Achocolatado 250ml',1.49,L,'250ml'),
  mk('Milbona Leite Condensado 397g',1.29,L,'397g'),
  mk('Milbona Natas Bater 35% 200ml',1.29,L,'200ml'),
  mk('Milbona Natas Cozinhar UHT 200ml',0.89,L,'200ml'),
  mk('Milbona Ricotta 250g',1.49,L,'250g'),
  mk('Milbona Mascarpone 250g',1.99,L,'250g'),
  mk('Milbona Cream Cheese Block 200g',1.69,L,'200g'),
  mk('Milbona Quark Natural 500g',1.49,L,'500g'),
  mk('Milbona Quark Morango 500g',1.49,L,'500g'),
  mk('Milbona Skyr Plain 450g',1.79,L,'450g'),
  mk('Milbona Bebida Aveia c/Chocolate 1L',1.39,L,'1L'),
];

// ─── Bebidas Wave 4 ──────────────────────────────────────────────
const bebW4 = tpl('Freeway', [
  ['Limonada Premium',0.45,null],['Guaraná Premium',0.39,0.75],
  ['Groselha Refrigerante',0.35,0.69],['Cherry Cola',0.35,null],
  ['Vanilla Cola',0.35,null],['Tropical Mix',0.39,null],
  ['Sport Drink Limão',0.69,null],['Sport Drink Laranja',0.69,null],
], [['330ml',0],['1.5L',1]], B);

const bebW4b = [
  mk('Solevita Sumo Laranja Néctar 200ml',0.49,B,'200ml'),
  mk('Solevita Sumo Pêssego 200ml',0.49,B,'200ml'),
  mk('Solevita Sumo Manga 200ml',0.49,B,'200ml'),
  mk('Solevita Sumo Ananás 200ml',0.49,B,'200ml'),
  mk('Solevita Sumo Tomate Spicy 250ml',0.69,B,'250ml'),
  mk('Solevita Smoothie Maçã Espinafre',1.79,B,'250ml'),
  mk('Solevita Smoothie Manga Cenoura',1.79,B,'250ml'),
  mk('Lidl Água Tónica Premium 200ml',0.49,B,'200ml'),
  mk('Lidl Ginger Beer Premium 330ml',0.79,B,'330ml'),
  mk('Lidl Elderflower Cordial 500ml',1.99,B,'500ml'),
  mk('Vinho Generoso Moscatel 500ml',4.99,B,'500ml'),
  mk('Vinho Porto Colheita Vintage 500ml',9.99,B,'500ml'),
  mk('Cidra Pera Lidl 330ml',0.89,B,'330ml'),
  mk('Hidromel Lidl 750ml',6.99,B,'750ml'),
];

// ─── Congelados Wave 4 ───────────────────────────────────────────
const congW4 = [
  mk('Nuggets Bacalhau Cong. 300g',3.49,C,'300g'),
  mk('Filetes Peixe Polme Cong. 400g',2.99,C,'400g'),
  mk('Fish & Chips Cong. 400g',3.99,C,'400g'),
  mk('Camarão Polme Cong. 250g',3.99,C,'250g'),
  mk('Lulas Grelhadas Cong. 300g',3.99,C,'300g'),
  mk('Bacalhau à Brás Cong. 600g',6.49,C,'600g'),
  mk('Arroz de Polvo Cong. 400g',4.49,C,'400g'),
  mk('Massa com Mariscos Cong. 400g',3.99,C,'400g'),
  mk('Frango Assado Cong. 1kg',4.99,C,'1kg'),
  mk('Perú Assado Cong. 500g',4.49,C,'500g'),
  mk('Almôndegas Vaca Cong. 400g',3.49,C,'400g'),
  mk('Almôndegas Frango Cong. 400g',3.29,C,'400g'),
  mk('Kebab Mix Cong. 400g',3.99,C,'400g'),
  mk('Donut Cong. x6',2.49,C,'x6'),
  mk('Waffles Belga Cong. x4',1.99,C,'x4'),
  mk('Crepes Cong. x6',1.99,C,'x6'),
  mk('Mini Panquecas Cong. x16',2.99,C,'x16'),
  mk('Rissois de Camarão Cong. 6un',3.49,C,'6 unidades'),
  mk('Croquetes de Carne Cong. 8un',2.99,C,'8 unidades'),
  mk('Pasteis de Bacalhau Cong. 6un',3.49,C,'6 unidades'),
  mk('Hambúrguer Duplo Cong. 2un',3.99,C,'2 unidades'),
  mk('Wraps BBQ Frango Cong. 2un',3.99,C,'2 unidades'),
  mk('Mini Pizza Margherita Cong. x4',2.99,C,'x4'),
  mk('Gelatelli Gelado Framboesa Ripple 500ml',2.49,C,'500ml'),
  mk('Gelatelli Gelado Baunilha Caramelo 500ml',2.49,C,'500ml'),
  mk('Gelatelli Sundae Chocolate x2',2.99,C,'x2'),
  mk('Gelatelli Sundae Morango x2',2.99,C,'x2'),
  mk('Gelatelli Frozen Yogurt Mirtilo 500ml',2.99,C,'500ml'),
  mk('Gelatelli Frozen Yogurt Morango 500ml',2.99,C,'500ml'),
  mk('Ervilhas e Cenouras Mix Cong. 450g',0.99,C,'450g'),
];

// ─── Padaria Wave 4 ──────────────────────────────────────────────
const padW4 = [
  mk('Pão de Hambúrguer Integral x4',1.49,P,'x4'),
  mk('Pão Centeio Escuro Pré-Cortado',1.89,P,'500g'),
  mk('Pão de Pipas 500g',1.69,P,'500g'),
  mk('Pão de Linho Linhaça 500g',1.79,P,'500g'),
  mk('Mini Pão para Petiscos x12',1.79,P,'x12'),
  mk('Pão de Milho Brioche x4',1.29,P,'x4'),
  mk('Croissant Queijo x4',1.99,P,'x4'),
  mk('Muffin Blueberry Aveia',0.99,P,'unidade'),
  mk('Mini Bolo de Mel x6',1.99,P,'x6'),
  mk('Tarte de Nata Grande',2.99,P,'unidade'),
  mk('Cheesecake Mirtilos Lidl',3.49,P,'unidade'),
  mk('Cheesecake Morango Lidl',3.49,P,'unidade'),
  mk('Mousse Chocolate Lidl x4',2.49,P,'x4'),
  mk('Panna Cotta Baunilha x2',1.99,P,'x2'),
  mk('Tiramisù Individual Italiamo',1.99,P,'unidade'),
  mk('Creme Brûlée Individual x2',2.99,P,'x2'),
  mk('Profiteroles Chocolate x12',2.99,P,'x12'),
  mk('Tronco Natal Chocolate',6.99,P,'unidade'),
  mk('Bolo Aniversário Baunilha',7.99,P,'unidade'),
  mk('Queques Marmorizados x4',1.49,P,'x4'),
];

// ─── Higiene Wave 4 ──────────────────────────────────────────────
const higW4 = tpl('Cien', [
  ['Champô Extra Volume',1.49,2.49],['Champô Biotina Crescimento',1.69,2.79],
  ['Champô Romã',1.49,null],['Champô Gengibre Cafeína',1.69,null],
  ['Gel Duche Manga',1.29,null],['Gel Duche Hibisco',1.29,null],
  ['Gel Duche Lavanda',1.29,null],['Gel Duche Pepino',1.29,null],
  ['Creme Corpo Manteiga Karité',2.29,null],['Creme Corpo Amêndoa Doce',2.29,null],
  ['Óleo Corpo Rosa 200ml',3.49,null],['Spray Cabelo Volume',2.49,null],
  ['Spray Cabelo Proteção Calor',2.99,null],['Sérum Facial Retinol',5.99,null],
], [['300ml',0],['500ml',1]], H);

const higW4b = [
  mk('Cien Pó Facial SPF20',3.99,H,'unidade'), mk('Cien Iluminador',2.99,H,'unidade'),
  mk('Cien Sombras Olhos Paleta',4.99,H,'unidade'), mk('Cien Contorno Nariz',2.99,H,'unidade'),
  mk('Cien Blush Peach',2.99,H,'unidade'), mk('Cien Gloss Lábios',1.99,H,'unidade'),
  mk('Cien Batom Vermelho',2.49,H,'unidade'), mk('Cien Máscara Volume',3.49,H,'unidade'),
  mk('Cien Delineador Preto',2.49,H,'unidade'), mk('Cien Corretor Cobertura Total',2.49,H,'unidade'),
  mk('Pilos Máscara Capilar 300ml',2.49,H,'300ml'), mk('Pilos Sérum Anti-Queda 100ml',3.49,H,'100ml'),
  mk('Pilos Spray Proteção UV Cabelo',2.99,H,'150ml'), mk('Cien Creme Nutritivo Pés 100ml',1.49,H,'100ml'),
  mk('Cien Bálsamo Lábios Hidratante',0.99,H,'unidade'),
];

// ─── Limpeza Wave 4 ──────────────────────────────────────────────
const limW4 = tpl('Formil', [
  ['Gel Roupa Perfume Violeta',3.49,5.99],['Gel Roupa Perfume Rosa',3.49,5.99],
  ['Pastilhas Roupa Colour x30',4.99,null],['Pastilhas Roupa White x30',4.99,null],
  ['Amaciador Concentrado Lavanda',2.79,null],['Amaciador Concentrado Mar',2.79,null],
  ['Pre-Wash Manchas 750ml',2.49,null],['Branqueador Roupa 750ml',1.99,null],
], [['1.5L',0],['3L',1]], LI);

const limW4b = [
  mk('W5 Spray Pedra Sanitária 500ml',1.49,LI,'500ml'),
  mk('W5 Gel WC Fragrância Pinheiro 750ml',0.99,LI,'750ml'),
  mk('W5 Cápsulas Máquina Loiça Platinum x40',4.99,LI,'x40'),
  mk('W5 Pastilhas Máquina Roupa Colour x50',6.99,LI,'x50'),
  mk('W5 Pré-Tratamento Manchas 200ml',1.99,LI,'200ml'),
  mk('W5 Limpeza Inodoro Cisterna x2',1.29,LI,'x2'),
  mk('Lidl Luvas Latex M x20',1.29,LI,'x20'),
  mk('Lidl Saco Aspirador x5',2.99,LI,'x5'),
  mk('Lidl Pano Chão Microfibra x2',2.49,LI,'x2'),
  mk('Lidl Cesto Roupa 25L',3.99,LI,'25L'),
];

// ─── Bebé Wave 4 ─────────────────────────────────────────────────
const bebW4_bebe = tpl('Lupilu', [
  ['Leite Fórmula 1 Noite 800g',11.99,null],['Leite Fórmula 2 Noite 800g',11.99,null],
  ['Leite Fórmula 3 Crescimento 800g',9.99,null],
  ['Fraldas Confort T3 x36',4.49,null],['Fraldas Confort T4 x32',4.99,null],
  ['Toalhitas Camomila x64',1.89,null],['Toalhitas Aloe Vera x64',1.89,null],
  ['Shampoo Suave Bebé 200ml',1.29,null],['Gel Duche Bebé 2in1 200ml',1.29,null],
  ['Leite Corporal Bebé 200ml',1.29,null],
], [['unidade',0]], BB);

// ─── Bio Wave 4 ──────────────────────────────────────────────────
const bioW4 = tpl('Bio Lidl', [
  ['Tâmaras Orgânicas',2.99,null],['Damascos Orgânicos',1.99,null],
  ['Mix Frutos Secos Orgânicos',4.49,null],['Amêndoas Orgânicas',3.49,null],
  ['Cajus Orgânicos',4.49,null],['Sementes Chia Orgânicas',2.49,null],
  ['Sementes Girassol Orgânicas',1.29,null],['Coco Ralado Orgânico',1.09,null],
  ['Chocolate Negro 70% Orgânico',1.49,null],['Café Moído Orgânico',3.49,null],
  ['Chá Verde Orgânico',1.69,null],['Passas Sultanas Orgânicas',1.29,null],
  ['Groselhas Secas Orgânicas',1.79,null],['Cranberries Orgânicos',1.99,null],
], [['200g',0]], BI);

// ─── Jardim Wave 4 ───────────────────────────────────────────────
const jardW4 = [
  mk('Substrato Morangos 5L',2.99,JP,'5L'), mk('Substrato Bonsai 2L',2.49,JP,'2L'),
  mk('Substrato Relvado 10L',3.99,JP,'10L'), mk('Fertil. Rosas 250ml',2.49,JP,'250ml'),
  mk('Fertil. Plantas Verdes 500ml',2.49,JP,'500ml'), mk('Fertil. Hortícolas 500ml',2.99,JP,'500ml'),
  mk('Sementes Beterraba',0.99,JP,'saqueta'), mk('Sementes Abóbora',0.99,JP,'saqueta'),
  mk('Sementes Alho Francês',0.99,JP,'saqueta'), mk('Sementes Espinafres',0.99,JP,'saqueta'),
  mk('Sementes Flores Mix',0.99,JP,'saqueta'), mk('Sementes Girassol',0.99,JP,'saqueta'),
  mk('Vaso Suspenso Plástico',2.99,JP,'unidade'), mk('Suporte Vasos 3 andares',7.99,JP,'unidade'),
  mk('Cinto de Rega Automática',4.99,JP,'unidade'), mk('Tesoura Poda Lidl',5.99,JP,'unidade'),
  mk('Semeador Manual Lidl',3.99,JP,'unidade'), mk('Protetor Plantas Geada',2.99,JP,'unidade'),
  mk('Grade Tutores Bambu x10',1.99,JP,'x10'), mk('Fio Tutor Verde 50m',1.49,JP,'50m'),
];

// ─── Sem Glúten / Sem Lactose Wave 4 ─────────────────────────────
const sgW4 = tpl('Combino SG', [
  ['Massa Rigatoni',1.19,null],['Massa Tagliatelle',1.29,null],
  ['Massa Lasanha',1.49,null],['Pão Brioche',2.99,null],
  ['Bolachas Aveia',1.49,null],['Granola',2.99,null],
  ['Flocos Aveia',1.99,null],['Farinha Mistura',1.79,null],
], [['300g',0]], SG);

const slW4 = tpl('Milbona SL', [
  ['Queijo Mozarella',1.79,null],['Queijo Edam',1.99,null],
  ['Queijo Gouda',1.99,null],['Natas Culinária',1.29,null],
  ['Iogurte Grego',0.89,null],['Leite com Cálcio',1.09,null],
  ['Manteiga Ligeira',1.69,null],['Creme de Queijo',1.59,null],
], [['200g',0]], SG);

// ─── Chocolates Wave 4 ───────────────────────────────────────────
const chocW4 = tpl('Fin Carré', [
  ['Chocolate Negro 75% Equador',0.99,1.79],['Chocolate Negro 95% Nibs',0.99,null],
  ['Chocolate Leite Arroz Tufado',0.79,null],['Chocolate Branco Crocante',0.79,null],
  ['Chocolate Leite Caramelo Salgado',0.89,null],['Chocolate Negro Pimenta',0.89,null],
  ['Chocolate Negro Framboise',0.89,null],['Chocolate Branco Pistáchio',0.99,null],
  ['Chocolate Preto Baunilha',0.79,null],['Chocolate Leite Malte',0.79,null],
], [['100g',0],['200g',1]], CH);

const favW4 = tpl('Favorina', [
  ['Gomas Fruta Tropical',0.99,null],['Gomas Ácidas Arco-Íris',0.99,null],
  ['Gomas Pinheiros',0.99,null],['Gomas Laranjas Aciduladas',0.99,null],
  ['Caramelos Chocolate x20',1.29,null],['Pirulitos Sortidos x10',1.49,null],
  ['Chiclets Sortidos x10',0.99,null],['Pé de Moleque',1.49,null],
], [['200g',0]], CH);

// ═══════════════════════════════════════════════════════════════════
// SUPLEMENTO U — WAVE 5 (final push, ~400 nomes únicos)
// ═══════════════════════════════════════════════════════════════════
const W5_mercearia = [
  // Combino massas — formatos família/pack
  mk('Combino Esparguete Pack Família 3kg',2.49,M,'3kg'),
  mk('Combino Penne Pack Família 3kg',2.49,M,'3kg'),
  mk('Combino Fusilli Pack Família 3kg',2.49,M,'3kg'),
  mk('Combino Esparguete Grosso 3kg',2.69,M,'3kg'),
  mk('Combino Rigatoni 3kg',2.69,M,'3kg'),
  mk('Combino Farfalle 3kg',2.69,M,'3kg'),
  // Combino arroz — pack grande
  mk('Combino Arroz Agulha Pack 10kg',6.49,M,'10kg'),
  mk('Combino Arroz Carolino Pack 10kg',6.99,M,'10kg'),
  mk('Combino Arroz Basmati Pack 5kg',4.39,M,'5kg'),
  // Azeites — formatos especiais
  mk('Azeite Virgem Extra Lidl 3L',11.99,M,'3L'),
  mk('Azeite Virgem Extra Lidl 5L',18.99,M,'5L'),
  mk('Eridanous Azeite DOP Kalamata 500ml',5.49,M,'500ml'),
  mk('Sol & Mar Azeite Alentejano 500ml',4.49,M,'500ml'),
  // Conservas — novos produtos
  mk('Atum Skipjack em Água Lidl 4x80g',2.49,M,'4x80g'),
  mk('Sardinha Espanhola em Azeite Lidl 120g',0.99,M,'120g'),
  mk('Ameijoa Galega em Salmoura 120g',1.99,M,'120g'),
  mk('Ostra Fumada em Óleo 85g',2.49,M,'85g'),
  mk('Mexilhão em Escabeche 120g',1.29,M,'120g'),
  mk('Bacalhau Desfiado com Azeite 200g',2.99,M,'200g'),
  mk('Salmão Defumado em Óleo 110g',2.49,M,'110g'),
  // Leguminosas — formatos secos
  mk('Combino Feijão Vermelho Seco 500g',0.69,M,'500g'),
  mk('Combino Feijão Branco Seco 500g',0.69,M,'500g'),
  mk('Combino Feijão Preto Seco 500g',0.69,M,'500g'),
  mk('Combino Grão de Bico Seco 500g',0.79,M,'500g'),
  mk('Combino Lentilhas Secas Verdes 500g',0.79,M,'500g'),
  mk('Combino Ervilhas Secas 500g',0.69,M,'500g'),
  mk('Combino Favas Secas 500g',0.79,M,'500g'),
  mk('Combino Tremoços Salgados 500g',0.89,M,'500g'),
  // Farinhas — formatos especiais
  mk('Belbake Farinha T55 5kg',1.99,M,'5kg'),
  mk('Belbake Farinha Integral 2kg',1.19,M,'2kg'),
  mk('Belbake Açúcar Branco 5kg',3.49,M,'5kg'),
  mk('Belbake Mix Panquecas 500g',1.29,M,'500g'),
  mk('Belbake Mix Bolos Chocolate 500g',1.49,M,'500g'),
  mk('Belbake Mix Muffins 500g',1.29,M,'500g'),
  mk('Belbake Amido Milho 200g',0.49,M,'200g'),
  mk('Belbake Pó de Alfarroba 200g',1.19,M,'200g'),
  // Café — formatos especiais
  mk('Bellarom Café Pack Economia 500g',3.29,M,'500g'),
  mk('Bellarom Cápsulas Ristretto Intenso x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Lungo Leggero x10',1.99,M,'10 cápsulas'),
  mk('Bellarom Cápsulas Bio Arabica x10',2.49,M,'10 cápsulas'),
  // Chá — variantes novas
  mk('Chá Hibisco Lidl 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá de Erva-Cidreira 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá de Lúpulo 20 saquetas',1.09,M,'20 saquetas'),
  mk('Chá de Alcaçuz 20 saquetas',0.99,M,'20 saquetas'),
  mk('Chá Detox Mix 20 saquetas',1.29,M,'20 saquetas'),
  mk('Chá Imunidade Mix 20 saquetas',1.29,M,'20 saquetas'),
  mk('Chá Anti-Stress Mix 20 saquetas',1.09,M,'20 saquetas'),
  // Snacks — formatos mini
  mk('Mcennedy Chips Mini Pack 6x25g',1.49,M,'6x25g'),
  mk('Mcennedy Pretzels Mini Pack 4x40g',1.29,M,'4x40g'),
  mk('Mcennedy Popcorn Multisabor 4x30g',1.19,M,'4x30g'),
  mk('Sondey Bolachas Mini Packs 6x25g',1.29,M,'6x25g'),
  mk('Crownfield Barritas Muesli Mel 6x25g',1.49,M,'6x25g'),
  // Sopas — novas variedades
  mk('Sopa Creme Cogumelos Silvestres 400ml',0.89,M,'400ml'),
  mk('Sopa Creme Espargos 400ml',0.89,M,'400ml'),
  mk('Sopa Creme Beterraba 400ml',0.89,M,'400ml'),
  mk('Sopa Creme Couve-Flor 400ml',0.89,M,'400ml'),
  mk('Sopa Creme Ervilha Hortelã 400ml',0.89,M,'400ml'),
  mk('Caldo Peixe Lidl 1L',1.29,M,'1L'),
  mk('Caldo Marisco Lidl 1L',1.49,M,'1L'),
  // Outros mercearia
  mk('Polpa de Tomate Lidl 1kg',0.89,M,'1kg'),
  mk('Tomate Pelado Biológico 400g',0.65,M,'400g'),
  mk('Molho de Tomate com Manjericão 350g',0.69,M,'350g'),
  mk('Molho Napolitana Premium 350g',0.89,M,'350g'),
  mk('Cremes de Queijo Sortidos 3x45g',1.29,M,'3x45g'),
  mk('Manteiga de Amendoim Proteínas 350g',2.99,M,'350g'),
  mk('Pasta de Castanha de Caju 350g',3.49,M,'350g'),
  mk('Doce Extra Figo 350g',1.49,M,'350g'),
  mk('Doce Extra Laranja Amarga 350g',1.49,M,'350g'),
  mk('Doce Extra Alperce 350g',1.49,M,'350g'),
];

const W5_frescos = [
  mk('Kiwi Berry 125g',2.49,FR,'125g'), mk('Uva Isabella Preta 500g',2.99,FR,'500g'),
  mk('Pera Conference 1kg',1.89,FR,'1kg'), mk('Maçã Fuji 1kg',1.69,FR,'1kg'),
  mk('Maçã Gala 2kg',2.79,FR,'2kg'), mk('Citrinos Mix 1kg',1.49,FR,'1kg'),
  mk('Clementinas Rede 1.5kg',2.99,FR,'1.5kg'), mk('Limões Bio 500g',1.49,FR,'500g'),
  mk('Morangos Bio 400g',2.99,FR,'400g'), mk('Salteados Frescos Mix 300g',2.49,FR,'300g'),
  mk('Couve Portuguesa 1kg',0.89,FR,'1kg'), mk('Grelos 500g',1.29,FR,'500g'),
  mk('Nabiças 500g',1.09,FR,'500g'), mk('Troncho de Nabo',0.79,FR,'unidade'),
  mk('Alface Romana',0.99,FR,'unidade'), mk('Chicória Frisada',0.99,FR,'unidade'),
  mk('Agrião Maço',1.09,FR,'maço'), mk('Rúcula Selvagem 100g',1.29,FR,'100g'),
  mk('Pak Choi 300g',1.49,FR,'300g'), mk('Bok Choy 300g',1.49,FR,'300g'),
  mk('Endívias 2un',1.49,FR,'2 unidades'), mk('Radicchio',1.49,FR,'unidade'),
  mk('Beterraba Amarela 500g',1.99,FR,'500g'), mk('Raiz de Aipo 500g',0.99,FR,'500g'),
  mk('Aipo Talo Maço',1.29,FR,'maço'), mk('Alho Elefante',1.29,FR,'unidade'),
  mk('Cebola Roxa Rede 1kg',1.09,FR,'1kg'), mk('Cebola Pérola 500g',0.99,FR,'500g'),
  mk('Chalota 200g',0.99,FR,'200g'), mk('Hortelã Fresca Embalada',0.99,FR,'embalagem'),
];

const W5_laticinios = [
  mk('Milbona Iogurte Natural Firme 125g',0.39,L,'125g'),
  mk('Milbona Iogurte Natural Firme 4x125g',0.79,L,'4x125g'),
  mk('Milbona Iogurte Natural Pack Económico 8x125g',1.49,L,'8x125g'),
  mk('Milbona Iogurte Cremoso Duplo 2x125g',0.89,L,'2x125g'),
  mk('Milbona Queijo Creme Snack 4x30g',1.29,L,'4x30g'),
  mk('Milbona Queijo em Fatias Light 12un',1.79,L,'12 fatias'),
  mk('Milbona Leite Condensado Magro 397g',1.19,L,'397g'),
  mk('Milbona Iogurte Drink Morango 4x100ml',1.49,L,'4x100ml'),
  mk('Milbona Iogurte Drink Pêssego 4x100ml',1.49,L,'4x100ml'),
  mk('Milbona Natas para Bater 30% 200ml',1.09,L,'200ml'),
  mk('Milbona Queijo Ralado Mix 3 Queijos 150g',1.79,L,'150g'),
  mk('Milbona Queijo Mozzarella Fatiado 125g',1.49,L,'125g'),
  mk('Milbona Queijo Edam em Palitos 100g',1.29,L,'100g'),
  mk('Milbona Manteiga s/Sal Pack 2x250g',2.49,L,'2x250g'),
  mk('Milbona Creme Fraîche 200ml',1.09,L,'200ml'),
];

const W5_bebidas = [
  mk('Lidl Água Mineral Premium 5L',0.79,B,'5L'),
  mk('Lidl Água c/Gás Premium 1.5L',0.55,B,'1.5L'),
  mk('Solevita Sumo Ananás 100% 1L',1.29,B,'1L'),
  mk('Solevita Sumo Maçã 100% 1L',1.29,B,'1L'),
  mk('Solevita Sumo Uva 100% 1L',1.29,B,'1L'),
  mk('Solevita Néctar Laranja 6x200ml',1.99,B,'6x200ml'),
  mk('Freeway Cola Pack 6x330ml',1.99,B,'6x330ml'),
  mk('Freeway Zero Pack 6x330ml',1.99,B,'6x330ml'),
  mk('Freeway Laranja Pack 6x330ml',1.99,B,'6x330ml'),
  mk('Freeway Energy Pack 4x250ml',2.49,B,'4x250ml'),
  mk('Lidl Cerveja Premium 24x330ml',9.99,B,'24x330ml'),
  mk('Vinho Tinto Casa Lidl 3L',5.99,B,'3L Bag-in-Box'),
  mk('Vinho Branco Casa Lidl 3L',5.99,B,'3L Bag-in-Box'),
  mk('Vinho Rosé Casa Lidl 3L',5.99,B,'3L Bag-in-Box'),
  mk('Prosecco Extra Dry Lidl 750ml',5.49,B,'750ml'),
];

const W5_congelados = [
  mk('Batata Frita Palha Pack 1.5kg',2.29,C,'1.5kg'),
  mk('Batata Frita Cunha Pack 1.5kg',2.29,C,'1.5kg'),
  mk('Ervilhas e Cenouras Pack 1kg',1.49,C,'1kg'),
  mk('Brócolos Pack 1kg',1.79,C,'1kg'),
  mk('Spinach Pack 1kg',1.59,C,'1kg'),
  mk('Camarão Tigre Pack 600g',10.99,C,'600g'),
  mk('Mix Mariscos Pack 1kg',9.99,C,'1kg'),
  mk('Gelatelli Gelado Familiar 1.5L Baunilha',3.49,C,'1.5L'),
  mk('Gelatelli Gelado Familiar 1.5L Chocolate',3.49,C,'1.5L'),
  mk('Gelatelli Gelado Familiar 1.5L Morango',3.49,C,'1.5L'),
  mk('Gelatelli Gelado Familiar 1.5L Caramelo',3.49,C,'1.5L'),
  mk('Gelatelli Gelado Mix 3 Sabores 2L',4.99,C,'2L'),
  mk('Pizza Salame Duplo Lidl 700g',2.99,C,'700g'),
  mk('Pizza Tonno Duplo Lidl 700g',2.99,C,'700g'),
  mk('Frango Assado Pack Família Cong. 2kg',7.99,C,'2kg'),
];

const W5_higiene = [
  mk('Cien Champô Keratina Pack 2x300ml',2.49,H,'2x300ml'),
  mk('Cien Gel Duche Pack 2x500ml',2.29,H,'2x500ml'),
  mk('Cien Desodorizante Spray Pack 2x150ml',2.49,H,'2x150ml'),
  mk('Cien Pasta Dentes Pack 3x75ml',1.99,H,'3x75ml'),
  mk('Cien Creme Mãos Pack 3x75ml',1.99,H,'3x75ml'),
  mk('Pilos Champô Pack Económico 500ml',1.99,H,'500ml'),
  mk('Pilos Condicionador Pack Económico 500ml',1.99,H,'500ml'),
  mk('Cien Leite Corporal Fragrância Coco',2.29,H,'400ml'),
  mk('Cien Leite Corporal Fragrância Rosa',2.29,H,'400ml'),
  mk('Cien Gel Banho Casal Pack 2x750ml',3.49,H,'2x750ml'),
  mk('Cien Sérum Firmeza Rosto 30ml',6.49,H,'30ml'),
  mk('Cien Tónico Poros 200ml',2.49,H,'200ml'),
  mk('Cien Esfoliante Facial Bicarbonato 75ml',2.49,H,'75ml'),
  mk('Cien Creme Olhos SPF15 15ml',3.49,H,'15ml'),
  mk('Cien Água Micelar Bifásica 400ml',2.99,H,'400ml'),
];

const W5_limpeza = [
  mk('Formil Detergente Pack Económico 4.5L',7.99,LI,'4.5L'),
  mk('W5 Multiusos Pack Económico 2x1L',2.49,LI,'2x1L'),
  mk('Lidl Papel Higiénico Pack 32 rolos',7.99,LI,'32 rolos'),
  mk('Lidl Papel Cozinha Pack 6 rolos',2.99,LI,'6 rolos'),
  mk('Lidl Sacos Lixo 100L Pack x20',2.49,LI,'x20'),
  mk('Lidl Sacos Zip Mix Tamanhos x30',1.99,LI,'x30'),
  mk('W5 Pastilhas Máquina Loiça x100',9.99,LI,'x100'),
  mk('Formil Cápsulas Roupa Pack x36',6.99,LI,'x36'),
  mk('W5 Amaciador Concentrado Pack 3L',5.99,LI,'3L'),
  mk('Lidl Lenços Papel Box x100',1.49,LI,'x100'),
];

const W5_bebe = [
  mk('Lupilu Fraldas T3 Pack Mensal x96',12.99,BB,'x96'),
  mk('Lupilu Fraldas T4 Pack Mensal x88',13.99,BB,'x88'),
  mk('Lupilu Fraldas T5 Pack Mensal x76',14.99,BB,'x76'),
  mk('Lupilu Toalhitas Pack Mensal 12x56',18.99,BB,'12x56'),
  mk('Lupilu Leite Fórmula 1 Pack 2x800g',18.99,BB,'2x800g'),
  mk('Lupilu Snack Maçã Arrufão 6m+ 20g',0.79,BB,'20g'),
  mk('Lupilu Snack Ananás Pera 6m+ 20g',0.79,BB,'20g'),
  mk('Lupilu Papa 7 Cereais 7m+ 400g',1.99,BB,'400g'),
  mk('Lupilu Papa Legumes Batata 4m+ 190g',0.89,BB,'190g'),
  mk('Lupilu Iogurte Bebé Pêssego 2x50g',0.89,BB,'2x50g'),
];

const W5_animais = [
  mk('Ração Gato Adulto Sterilised 1.5kg',5.99,AN,'1.5kg'),
  mk('Ração Gato Adulto Pack Económico 2.5kg',7.99,AN,'2.5kg'),
  mk('Ração Cão Adulto Pack Económico 2.5kg',7.99,AN,'2.5kg'),
  mk('Ração Cão Grande Porte Pack 4kg',9.99,AN,'4kg'),
  mk('Patê Gato Vitela Saqueta 12x100g',5.99,AN,'12x100g'),
  mk('Patê Cão Aves Saqueta 12x100g',5.99,AN,'12x100g'),
  mk('Snacks Gato Mix 3 Sabores 60g',1.49,AN,'60g'),
  mk('Snacks Cão Mix Dentais 200g',2.99,AN,'200g'),
  mk('Areia Gato Silica Premium 7L',4.49,AN,'7L'),
  mk('Areia Gato Aglomerante Premium 15L',6.99,AN,'15L'),
];

const W5_fitness = [
  mk('Lidl Sport Ômega 3 1000mg x120',10.99,FT,'x120 cápsulas'),
  mk('Lidl Sport Vitamina C 1000mg x60',3.99,FT,'x60 comprimidos'),
  mk('Lidl Sport Proteína Vegetal Soja 750g',13.99,FT,'750g'),
  mk('Lidl Sport Proteína Rice 750g',13.99,FT,'750g'),
  mk('Lidl Sport Glutamina 300g',9.99,FT,'300g'),
  mk('Lidl Sport Barras 20g Proteína x12',8.99,FT,'x12 barras'),
  mk('Lidl Sport Sachê Electrólitos x10',3.99,FT,'x10 sachês'),
  mk('Lidl Sport Bebida Isotónica 500ml Limão',0.99,FT,'500ml'),
  mk('Lidl Sport Bebida Isotónica 500ml Laranja',0.99,FT,'500ml'),
  mk('Lidl Sport Pré-Treino Energy 300g',12.99,FT,'300g'),
];

const W5_chocolates = [
  mk('Favorina Gomas Ursinhos Gigantes 1kg',3.99,CH,'1kg'),
  mk('Favorina Mix Doces Pack Família 500g',2.99,CH,'500g'),
  mk('Fin Carré Chocolate Leite Pack 5x100g',2.99,CH,'5x100g'),
  mk('Fin Carré Chocolate Negro Pack 5x100g',2.99,CH,'5x100g'),
  mk('Lidl Chocolate Milka Style 100g',0.89,CH,'100g'),
  mk('Lidl Kinder Style Chocolate x4',1.49,CH,'x4'),
  mk('Deluxe Trufas Praliné 300g',5.99,CH,'300g'),
  mk('Deluxe Caixa Chocolates Sortidos 400g',7.99,CH,'400g'),
  mk('Favorina Biscoitos Natal Sortidos 400g',2.99,CH,'400g'),
  mk('Favorina Calendário Advento 200g',2.99,CH,'200g'),
];

const W5_casa = [
  mk('Silvercrest Aspirador Sem Fios',39.99,CA,'unidade'),
  mk('Silvercrest Iôni Frizz Cabelo',14.99,CA,'unidade'),
  mk('Silvercrest Escova Modeladora',17.99,CA,'unidade'),
  mk('Silvercrest Aquecedor Cerâmico',14.99,CA,'unidade'),
  mk('Silvercrest Humidificador',19.99,CA,'unidade'),
  mk('Silvercrest Purificador Ar Pequeno',24.99,CA,'unidade'),
  mk('Silvercrest Mini Câmara IP WiFi',19.99,CA,'unidade'),
  mk('Lidl Pilhas Recarregáveis AA x4',5.99,CA,'x4'),
  mk('Lidl Pilhas Recarregáveis AAA x4',5.99,CA,'x4'),
  mk('Lidl Carregador Pilhas Universal',7.99,CA,'unidade'),
  mk('Lâmpada LED Smart Lidl E27',5.99,CA,'unidade'),
  mk('Extensão Elétrica Lidl 3 tomadas 2m',4.99,CA,'unidade'),
];

const WAVE5 = [
  ...W5_mercearia, ...W5_frescos, ...W5_laticinios, ...W5_bebidas,
  ...W5_congelados, ...W5_higiene, ...W5_limpeza, ...W5_bebe,
  ...W5_animais, ...W5_fitness, ...W5_chocolates, ...W5_casa,
];

const WAVE4 = [
  ...MERC_W4, ...frescW4, ...latW4, ...latW4b, ...bebW4, ...bebW4b,
  ...congW4, ...padW4, ...higW4, ...higW4b, ...limW4, ...limW4b,
  ...bebW4_bebe, ...bioW4, ...jardW4, ...sgW4, ...slW4, ...chocW4, ...favW4,
];

// ═══════════════════════════════════════════════════════════════════
// WAVE6 — top-up ~120 produtos para atingir 3000+
// ═══════════════════════════════════════════════════════════════════
const w6_mercearia = [
  mk('Combino Esparguete Tricolor 500g', 0.55, 'Mercearia', '500g'),
  mk('Combino Penne Tricolor 500g', 0.55, 'Mercearia', '500g'),
  mk('Combino Fusilli Tricolor 500g', 0.55, 'Mercearia', '500g'),
  mk('Combino Conchiglie 500g', 0.49, 'Mercearia', '500g'),
  mk('Belbake Farinha Espelta 1kg', 1.19, 'Mercearia', '1kg'),
  mk('Belbake Farinha Centeio 1kg', 1.09, 'Mercearia', '1kg'),
  mk('Belbake Cacau em Pó Magro 200g', 0.89, 'Mercearia', '200g'),
  mk('Belbake Bicarbonato de Sódio 200g', 0.45, 'Mercearia', '200g'),
  mk('Orlando Ketchup Picante 560g', 1.29, 'Mercearia', '560g'),
  mk('Orlando Mostarda Dijon 200g', 0.89, 'Mercearia', '200g'),
  mk('Orlando Maionese Light 400ml', 1.39, 'Mercearia', '400ml'),
  mk('Vitasia Molho Hoisin 150ml', 1.49, 'Mercearia', '150ml'),
  mk('Vitasia Óleo de Sésamo 250ml', 1.99, 'Mercearia', '250ml'),
  mk('Vitasia Vinagre de Arroz 500ml', 1.19, 'Mercearia', '500ml'),
  mk('Vitasia Kimchi 300g', 1.89, 'Mercearia', '300g'),
  mk('Solevita Sumo Toranja 1L', 0.89, 'Mercearia', '1L'),
  mk('Solevita Néctar Pêssego 1L', 0.89, 'Mercearia', '1L'),
  mk('Milbona Café Torrado Moído 250g', 1.79, 'Mercearia', '250g'),
  mk('Milbona Café Descafeinado Grão 500g', 3.49, 'Mercearia', '500g'),
  mk('Grafschafter Mel Acácia 500g', 3.29, 'Mercearia', '500g'),
  mk('Grafschafter Mel Silvestre 250g', 1.99, 'Mercearia', '250g'),
  mk('Eridanous Bulgur 500g', 0.89, 'Mercearia', '500g'),
  mk('Eridanous Cuscuz 500g', 0.89, 'Mercearia', '500g'),
  mk('Eridanous Lentilhas Vermelhas 500g', 0.99, 'Mercearia', '500g'),
  mk('Italiamo Risotto Funghi 300g', 1.49, 'Mercearia', '300g'),
  mk('Italiamo Risotto Limão 300g', 1.49, 'Mercearia', '300g'),
  mk('Mcennedy Ketchup Smoky BBQ 400ml', 1.09, 'Mercearia', '400ml'),
  mk('Mcennedy Ranch Dressing 400ml', 1.29, 'Mercearia', '400ml'),
  mk('Mcennedy Pickles Fatiados 400g', 0.99, 'Mercearia', '400g'),
];

const w6_frescos = [
  mk('Milbona Iogurte Líquido Morango 4x100g', 0.89, 'Frescos', '4x100g'),
  mk('Milbona Iogurte Líquido Pêssego 4x100g', 0.89, 'Frescos', '4x100g'),
  mk('Milbona Iogurte Skyr Baunilha 150g', 0.69, 'Frescos', '150g'),
  mk('Milbona Iogurte Skyr Manga 150g', 0.69, 'Frescos', '150g'),
  mk('Milbona Queijo Fresco Magro 200g', 0.69, 'Frescos', '200g'),
  mk('Milbona Queijo Fresco Ervas 150g', 0.99, 'Frescos', '150g'),
  mk('Milbona Manteiga Com Sal 250g', 1.49, 'Frescos', '250g'),
  mk('Milbona Manteiga Light 250g', 1.59, 'Frescos', '250g'),
  mk('Milbona Natas Para Bater 200ml', 0.89, 'Frescos', '200ml'),
  mk('Pilos Ovo M Classe A 10un', 1.49, 'Frescos', '10un'),
  mk('Pilos Ovo L Classe A 6un', 1.29, 'Frescos', '6un'),
  mk('Pilos Ovo Caipira 6un', 1.89, 'Frescos', '6un'),
  mk('Frango Peito Sem Pele 600g', 3.49, 'Frescos', '600g'),
  mk('Frango Asa Marinada 500g', 2.49, 'Frescos', '500g'),
  mk('Peru Escalope 400g', 3.29, 'Frescos', '400g'),
];

const w6_bebidas = [
  mk('Freeway Água Com Gás Limão 1.5L', 0.39, 'Bebidas', '1.5L'),
  mk('Freeway Água Com Gás Laranja 1.5L', 0.39, 'Bebidas', '1.5L'),
  mk('Freeway Isotónico Tropical 500ml', 0.55, 'Bebidas', '500ml'),
  mk('Freeway Isotónico Melancia 500ml', 0.55, 'Bebidas', '500ml'),
  mk('Freeway Energy Açaí 250ml', 0.59, 'Bebidas', '250ml'),
  mk('Freeway Energy Zero 250ml', 0.59, 'Bebidas', '250ml'),
  mk('Solevita Smoothie Verde 750ml', 1.49, 'Bebidas', '750ml'),
  mk('Solevita Smoothie Vermelho 750ml', 1.49, 'Bebidas', '750ml'),
  mk('Milbona Leite Aveia Barista 1L', 1.29, 'Bebidas', '1L'),
  mk('Milbona Leite Coco Culinário 400ml', 0.89, 'Bebidas', '400ml'),
];

const w6_congelados = [
  mk('Mcennedy Burger Vegetal 2x113g', 2.49, 'Congelados', '2x113g'),
  mk('Mcennedy Nuggets Frango 400g', 2.99, 'Congelados', '400g'),
  mk('Mcennedy Fish Burger 300g', 2.49, 'Congelados', '300g'),
  mk('Vitasia Gyoza Legumes 200g', 2.29, 'Congelados', '200g'),
  mk('Vitasia Edamame Cozido 400g', 1.99, 'Congelados', '400g'),
  mk('Favorina Gelado Magnum Style 4un', 2.99, 'Congelados', '4un'),
  mk('Favorina Gelado Twister Limão 4un', 1.99, 'Congelados', '4un'),
  mk('Congelado Espinafres Folha 750g', 1.29, 'Congelados', '750g'),
  mk('Congelado Milho Doce 750g', 1.09, 'Congelados', '750g'),
  mk('Congelado Brócolos Ramos 600g', 1.19, 'Congelados', '600g'),
];

const w6_higiene = [
  mk('Cien Sérum Vitamina C 30ml', 3.49, 'Higiene e Beleza', '30ml'),
  mk('Cien Sérum Ácido Hialurónico 30ml', 3.49, 'Higiene e Beleza', '30ml'),
  mk('Cien Máscara Hidratante 50ml', 2.99, 'Higiene e Beleza', '50ml'),
  mk('Cien Protetor Solar SPF50 Face 50ml', 4.99, 'Higiene e Beleza', '50ml'),
  mk('Cien Eau de Toilette Homme 50ml', 4.99, 'Higiene e Beleza', '50ml'),
  mk('Cien Eau de Toilette Femme 50ml', 4.99, 'Higiene e Beleza', '50ml'),
  mk('Cien Esfoliante Corporal 200ml', 1.99, 'Higiene e Beleza', '200ml'),
  mk('Cien Roll-On Sensitive 50ml', 0.99, 'Higiene e Beleza', '50ml'),
  mk('Cien Pasta Dentes Whitening 75ml', 0.89, 'Higiene e Beleza', '75ml'),
  mk('Cien Fio Dental Menta 50m', 0.79, 'Higiene e Beleza', '50m'),
];

const w6_limpeza = [
  mk('W5 Detergente Máquina Louça 1.5L', 2.29, 'Limpeza', '1.5L'),
  mk('W5 Pastilhas Máquina Louça 50un', 3.99, 'Limpeza', '50un'),
  mk('W5 Desinfetante WC 750ml', 0.89, 'Limpeza', '750ml'),
  mk('W5 Limpa Inox 500ml', 1.29, 'Limpeza', '500ml'),
  mk('W5 Pastilhas Sanita 2un', 0.99, 'Limpeza', '2un'),
  mk('W5 Sacos Lixo 30L 20un', 0.89, 'Limpeza', '20un'),
  mk('W5 Sacos Lixo 120L 10un', 1.49, 'Limpeza', '10un'),
  mk('Formil Cápsulas Color 18un', 3.49, 'Limpeza', '18un'),
  mk('Formil Detergente Lã e Seda 1L', 1.99, 'Limpeza', '1L'),
];

const w6_bio = [
  mk('Bio Organic Aveia Grão 500g', 1.49, 'Bio e Orgânicos', '500g'),
  mk('Bio Organic Linhaça Dourada 250g', 1.29, 'Bio e Orgânicos', '250g'),
  mk('Bio Organic Quinoa Branca 400g', 2.49, 'Bio e Orgânicos', '400g'),
  mk('Bio Organic Grão-de-Bico 400g', 1.09, 'Bio e Orgânicos', '400g'),
  mk('Bio Organic Tomate Pelado 400g', 0.99, 'Bio e Orgânicos', '400g'),
  mk('Bio Organic Azeite Virgem Extra 500ml', 4.99, 'Bio e Orgânicos', '500ml'),
  mk('Bio Organic Mel Lavanda 250g', 3.49, 'Bio e Orgânicos', '250g'),
  mk('Bio Organic Pasta Amendoim 350g', 2.99, 'Bio e Orgânicos', '350g'),
  mk('Bio Organic Leite Aveia 1L', 1.49, 'Bio e Orgânicos', '1L'),
  mk('Bio Organic Iogurte Natural 400g', 1.29, 'Bio e Orgânicos', '400g'),
];

const w6_chocolates = [
  mk('Fin Carré Chocolate Branco Framboesa 100g', 0.79, 'Chocolates e Doces', '100g'),
  mk('Fin Carré Chocolate Negro 85% 100g', 0.89, 'Chocolates e Doces', '100g'),
  mk('Fin Carré Chocolate Negro 99% 100g', 0.99, 'Chocolates e Doces', '100g'),
  mk('Fin Carré Chocolate Leite Avelã 200g', 1.29, 'Chocolates e Doces', '200g'),
  mk('Sondey Bolachas Wafer Chocolate 250g', 0.99, 'Chocolates e Doces', '250g'),
  mk('Sondey Bolachas Digestive Aveia 400g', 1.09, 'Chocolates e Doces', '400g'),
  mk('Favorina Gomas Ursos 200g', 0.69, 'Chocolates e Doces', '200g'),
  mk('Favorina Marshmallows 150g', 0.79, 'Chocolates e Doces', '150g'),
  mk('Favorina Caramelos Manteiga 150g', 0.89, 'Chocolates e Doces', '150g'),
];

const w6_sg = [
  mk('Combino Esparguete Sem Glúten 400g', 1.49, 'Sem Glúten / Sem Lactose', '400g'),
  mk('Combino Penne Sem Glúten 400g', 1.49, 'Sem Glúten / Sem Lactose', '400g'),
  mk('Belbake Farinha Sem Glúten 500g', 1.99, 'Sem Glúten / Sem Lactose', '500g'),
  mk('Milbona Iogurte Sem Lactose Morango 125g', 0.55, 'Sem Glúten / Sem Lactose', '125g'),
  mk('Milbona Leite Sem Lactose UHT 1L', 0.99, 'Sem Glúten / Sem Lactose', '1L'),
  mk('Favorina Biscoitos Aveia Sem Glúten 200g', 1.29, 'Sem Glúten / Sem Lactose', '200g'),
];

const w6_patch = [
  mk('Solevita Sumo Maçã e Pêra 1L', 0.89, 'Mercearia', '1L'),
  mk('Milbona Leite Meio-Gordo Bio 1L', 1.09, 'Bio e Orgânicos', '1L'),
  mk('Eridanous Houmous Pimento 200g', 1.29, 'Mercearia', '200g'),
  mk('Eridanous Houmous Alho Assado 200g', 1.29, 'Mercearia', '200g'),
  mk('Vitasia Ramen Frango 85g', 0.49, 'Mercearia', '85g'),
  mk('Vitasia Ramen Camarão 85g', 0.49, 'Mercearia', '85g'),
  mk('Vitasia Ramen Legumes 85g', 0.49, 'Mercearia', '85g'),
  mk('Freeway Água Sabor Pepino Menta 500ml', 0.45, 'Bebidas', '500ml'),
  mk('Freeway Água Sabor Limão Gengibre 500ml', 0.45, 'Bebidas', '500ml'),
  mk('Sondey Biscoitos Speculoos 400g', 1.09, 'Chocolates e Doces', '400g'),
];

const WAVE6 = [
  ...w6_mercearia, ...w6_frescos, ...w6_bebidas, ...w6_congelados,
  ...w6_higiene, ...w6_limpeza, ...w6_bio, ...w6_chocolates, ...w6_sg,
  ...w6_patch,
];

const ALL_PRODUCTS = [
  ...MERCEARIA, ...FRESCOS, ...LATICINIOS, ...BEBIDAS, ...CONGELADOS,
  ...PADARIA, ...LIMPEZA, ...HIGIENE, ...BEBE, ...ANIMAIS,
  ...CASA, ...BIO, ...CHOCOLATES, ...FITNESS, ...JARDIM_PAPEL, ...SEM_GLUTEN,
  // Suplementos round 1
  ...MERCEARIA_EXTRA, ...FRESCOS_EXTRA, ...LATICINIOS_EXTRA, ...BEBIDAS_EXTRA,
  ...CONGELADOS_EXTRA, ...PADARIA_EXTRA, ...LIMPEZA_EXTRA, ...HIGIENE_EXTRA,
  ...BEBE_EXTRA, ...CASA_EXTRA, ...EXTRAS_MISC,
  // Suplementos round 2
  ...MERCEARIA_W3, ...LATBEB_W3, ...CONGPAD_W3, ...HIGLIE_W3,
  ...FRESANI_W3, ...BEBCAFIT_W3, ...DELI_W3,
  // Suplementos round 3
  ...WAVE4,
  // Suplementos round 4 — final push para 3000+
  ...WAVE5,
  // Suplementos round 5 — top-up para 3000+
  ...WAVE6,
];

// ═══════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════
async function main() {
  console.log(`\n🛒 LIDL GUARDA — Inserção de produtos`);
  console.log(`📦 Total gerado: ${ALL_PRODUCTS.length} produtos\n`);

  // Dedup by name within this batch (avoid inserting same name twice)
  const seen = new Set();
  const unique = ALL_PRODUCTS.filter(p => {
    const key = p.name.toLowerCase().trim();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  console.log(`✅ Únicos após dedup interno: ${unique.length}`);

  const { inserted, skipped, failed } = await insertProducts(unique, RESTAURANT_ID);
  console.log(`\n════════════════════════════════`);
  console.log(`✅ Inseridos: ${inserted}`);
  console.log(`⏭  Já existiam: ${skipped}`);
  console.log(`❌ Falhou: ${failed}`);
  console.log(`📊 TOTAL FINAL NO DB: ${inserted + skipped}`);
  console.log(`════════════════════════════════\n`);
}

main().catch(err => {
  console.error('Erro fatal:', err.message);
  process.exit(1);
});
