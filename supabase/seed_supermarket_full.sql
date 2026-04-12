-- ============================================================
-- BORA APP — Supermercado Completo (seed_supermarket_full.sql)
-- 18 categorias · 190 produtos · 570 variantes
-- APPEND ONLY — nunca apaga dados existentes
-- ============================================================

-- === 1. GARANTIR COLUNAS EXTRAS ===
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT '';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_popular BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_on_sale BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS discount_price FLOAT8;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS price_low FLOAT8;

-- === 2. CRIAR TABELA product_variants ===
CREATE TABLE IF NOT EXISTS public.product_variants (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  brand_name TEXT NOT NULL,
  price FLOAT8 NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pv_product_id ON public.product_variants(product_id);

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'product_variants' AND policyname = 'pv_read_all'
  ) THEN
    CREATE POLICY pv_read_all ON public.product_variants FOR SELECT USING (true);
  END IF;
END $$;

-- === 3. PRODUTOS ===
-- price = preço base (marca própria / mais baixo)
-- restaurant_id: continente-guarda

INSERT INTO public.products
  (id, restaurant_id, name, description, price, photo_url, is_available, category, is_popular, is_on_sale, discount_price)
VALUES

-- ── FRUTAS ──────────────────────────────────────────────────
('cm-fr-001','continente-guarda','Banana','Banana fresca, rica em potássio',0.89,'https://source.unsplash.com/400x400/?banana,fruit',true,'Frutas',true,false,null),
('cm-fr-002','continente-guarda','Maçã Golden','Maçã golden doce e crocante',1.19,'https://source.unsplash.com/400x400/?apple,fruit',true,'Frutas',true,false,null),
('cm-fr-003','continente-guarda','Laranja','Laranja valenciana sumarenta',0.99,'https://source.unsplash.com/400x400/?orange,citrus',true,'Frutas',true,false,null),
('cm-fr-004','continente-guarda','Pera Rocha','Pera rocha portuguesa DOP',1.39,'https://source.unsplash.com/400x400/?pear,fruit',true,'Frutas',false,false,null),
('cm-fr-005','continente-guarda','Uvas Brancas','Uvas brancas sem grainha',2.49,'https://source.unsplash.com/400x400/?grapes,fruit',true,'Frutas',false,false,null),
('cm-fr-006','continente-guarda','Morango','Morangos frescos portugueses',3.49,'https://source.unsplash.com/400x400/?strawberry',true,'Frutas',true,true,2.79),
('cm-fr-007','continente-guarda','Kiwi','Kiwi verde por unidade',0.49,'https://source.unsplash.com/400x400/?kiwi,fruit',true,'Frutas',false,false,null),
('cm-fr-008','continente-guarda','Limão','Limão siciliano azedo',0.69,'https://source.unsplash.com/400x400/?lemon,citrus',true,'Frutas',false,false,null),
('cm-fr-009','continente-guarda','Manga','Manga tropical madura',1.99,'https://source.unsplash.com/400x400/?mango,tropical',true,'Frutas',false,false,null),
('cm-fr-010','continente-guarda','Ananás','Ananás inteiro tropical',1.89,'https://source.unsplash.com/400x400/?pineapple',true,'Frutas',false,false,null),
('cm-fr-011','continente-guarda','Melancia','Melancia 4-5kg',3.99,'https://source.unsplash.com/400x400/?watermelon',true,'Frutas',true,true,3.29),
('cm-fr-012','continente-guarda','Framboesa','Framboesas frescas 125g',3.99,'https://source.unsplash.com/400x400/?raspberry,berries',true,'Frutas',false,false,null),

-- ── LEGUMES ─────────────────────────────────────────────────
('cm-lg-001','continente-guarda','Tomate','Tomate redondo 500g',1.29,'https://source.unsplash.com/400x400/?tomato',true,'Legumes',true,false,null),
('cm-lg-002','continente-guarda','Cebola','Cebola amarela 1kg',0.79,'https://source.unsplash.com/400x400/?onion',true,'Legumes',true,false,null),
('cm-lg-003','continente-guarda','Alho','Alho português cabeça',0.99,'https://source.unsplash.com/400x400/?garlic',true,'Legumes',true,false,null),
('cm-lg-004','continente-guarda','Cenoura','Cenoura 1kg',0.89,'https://source.unsplash.com/400x400/?carrot,vegetable',true,'Legumes',true,false,null),
('cm-lg-005','continente-guarda','Batata','Batata 2,5kg',1.29,'https://source.unsplash.com/400x400/?potato',true,'Legumes',true,false,null),
('cm-lg-006','continente-guarda','Alface','Alface iceberg 300g',0.99,'https://source.unsplash.com/400x400/?lettuce,salad',true,'Legumes',false,false,null),
('cm-lg-007','continente-guarda','Brócolos','Brócolos frescos 400g',1.49,'https://source.unsplash.com/400x400/?broccoli',true,'Legumes',false,true,1.19),
('cm-lg-008','continente-guarda','Courgette','Courgette verde 500g',0.99,'https://source.unsplash.com/400x400/?zucchini',true,'Legumes',false,false,null),
('cm-lg-009','continente-guarda','Pimento Vermelho','Pimento vermelho 500g',1.19,'https://source.unsplash.com/400x400/?red,pepper',true,'Legumes',false,false,null),
('cm-lg-010','continente-guarda','Espinafres','Espinafres frescos 250g',1.29,'https://source.unsplash.com/400x400/?spinach,greens',true,'Legumes',false,false,null),
('cm-lg-011','continente-guarda','Pepino','Pepino 250-300g',0.69,'https://source.unsplash.com/400x400/?cucumber',true,'Legumes',false,false,null),
('cm-lg-012','continente-guarda','Beringela','Beringela 300-400g',0.99,'https://source.unsplash.com/400x400/?eggplant',true,'Legumes',false,false,null),

-- ── LATICÍNIOS ──────────────────────────────────────────────
('cm-lt-001','continente-guarda','Leite Inteiro UHT','Leite gordo 1L',0.79,'https://source.unsplash.com/400x400/?milk,white',true,'Laticínios',true,false,null),
('cm-lt-002','continente-guarda','Leite Meio-Gordo UHT','Leite meio-gordo 1L',0.69,'https://source.unsplash.com/400x400/?milk,dairy',true,'Laticínios',true,false,null),
('cm-lt-003','continente-guarda','Iogurte Natural','Iogurte natural 125g',0.59,'https://source.unsplash.com/400x400/?yogurt',true,'Laticínios',true,false,null),
('cm-lt-004','continente-guarda','Iogurte Grego','Iogurte grego cremoso 150g',1.29,'https://source.unsplash.com/400x400/?greek,yogurt',true,'Laticínios',true,false,null),
('cm-lt-005','continente-guarda','Manteiga','Manteiga com sal 250g',1.99,'https://source.unsplash.com/400x400/?butter,dairy',true,'Laticínios',true,false,null),
('cm-lt-006','continente-guarda','Queijo Flamengo','Queijo flamengo fatiado 200g',2.49,'https://source.unsplash.com/400x400/?cheese,sliced',true,'Laticínios',true,true,1.99),
('cm-lt-007','continente-guarda','Queijo Mozzarella','Mozzarella fresca 125g',2.99,'https://source.unsplash.com/400x400/?mozzarella',true,'Laticínios',false,false,null),
('cm-lt-008','continente-guarda','Queijo Brie','Brie francês 200g',3.49,'https://source.unsplash.com/400x400/?brie,cheese',true,'Laticínios',false,false,null),
('cm-lt-009','continente-guarda','Natas para Culinária','Natas 200ml 18% gordura',0.99,'https://source.unsplash.com/400x400/?cream,dairy',true,'Laticínios',false,false,null),
('cm-lt-010','continente-guarda','Queijo Cheddar','Cheddar fatiado 200g',2.79,'https://source.unsplash.com/400x400/?cheddar,cheese',true,'Laticínios',false,false,null),
('cm-lt-011','continente-guarda','Bebida de Amêndoa','Bebida vegetal amêndoa 1L',1.89,'https://source.unsplash.com/400x400/?almond,milk',true,'Laticínios',false,false,null),
('cm-lt-012','continente-guarda','Leite sem Lactose','Leite UHT sem lactose 1L',1.09,'https://source.unsplash.com/400x400/?milk,glass',true,'Laticínios',false,false,null),

-- ── OVOS ────────────────────────────────────────────────────
('cm-ov-001','continente-guarda','Ovos M (12un)','Ovos frescos tamanho M',1.89,'https://source.unsplash.com/400x400/?eggs',true,'Ovos',true,false,null),
('cm-ov-002','continente-guarda','Ovos L (12un)','Ovos frescos tamanho L',2.19,'https://source.unsplash.com/400x400/?eggs,large',true,'Ovos',true,false,null),
('cm-ov-003','continente-guarda','Ovos XL (6un)','Ovos extra-grandes tamanho XL',1.49,'https://source.unsplash.com/400x400/?egg,white',true,'Ovos',false,false,null),
('cm-ov-004','continente-guarda','Ovos Bio (6un)','Ovos biológicos certificados',2.49,'https://source.unsplash.com/400x400/?organic,eggs',true,'Ovos',false,false,null),
('cm-ov-005','continente-guarda','Ovos Galinha Feliz (12un)','Galinhas criadas ao ar livre',3.49,'https://source.unsplash.com/400x400/?free,range,eggs',true,'Ovos',true,false,null),
('cm-ov-006','continente-guarda','Claras Pasteurizadas','Claras líquidas 500ml',2.99,'https://source.unsplash.com/400x400/?egg,white,liquid',true,'Ovos',false,false,null),
('cm-ov-007','continente-guarda','Ovos Caipiras (6un)','Ovos de galinha caipira',2.79,'https://source.unsplash.com/400x400/?eggs,farm',true,'Ovos',false,false,null),
('cm-ov-008','continente-guarda','Ovos de Codorniz (18un)','Ovos de codorniz pequenos',1.99,'https://source.unsplash.com/400x400/?quail,eggs',true,'Ovos',false,false,null),
('cm-ov-009','continente-guarda','Ovos Omega 3 (12un)','Ovos enriquecidos com Omega 3',2.99,'https://source.unsplash.com/400x400/?eggs,healthy',true,'Ovos',false,false,null),
('cm-ov-010','continente-guarda','Ovo Cozido (6un)','Ovos já cozidos e descascados',1.49,'https://source.unsplash.com/400x400/?boiled,egg',true,'Ovos',false,false,null),

-- ── TALHO ───────────────────────────────────────────────────
('cm-tl-001','continente-guarda','Frango Inteiro','Frango inteiro 1,3-1,6kg',4.99,'https://source.unsplash.com/400x400/?whole,chicken',true,'Talho',true,false,null),
('cm-tl-002','continente-guarda','Peito de Frango','Peito de frango 500g',6.99,'https://source.unsplash.com/400x400/?chicken,breast',true,'Talho',true,false,null),
('cm-tl-003','continente-guarda','Costeletas de Porco','Costeletas suínas 500g',5.49,'https://source.unsplash.com/400x400/?pork,ribs',true,'Talho',false,true,4.39),
('cm-tl-004','continente-guarda','Bife de Vaca','Bife de novilho 300g',8.99,'https://source.unsplash.com/400x400/?beef,steak',true,'Talho',true,false,null),
('cm-tl-005','continente-guarda','Carne Picada','Carne picada mista 500g',5.99,'https://source.unsplash.com/400x400/?ground,meat',true,'Talho',true,false,null),
('cm-tl-006','continente-guarda','Entrecosto','Entrecosto de porco 500g',6.49,'https://source.unsplash.com/400x400/?spare,ribs',true,'Talho',false,false,null),
('cm-tl-007','continente-guarda','Lombo de Porco','Lombo de porco 500g',7.99,'https://source.unsplash.com/400x400/?pork,loin',true,'Talho',false,false,null),
('cm-tl-008','continente-guarda','Salsichas (6un)','Salsichas frescas de porco',2.49,'https://source.unsplash.com/400x400/?sausage',true,'Talho',true,false,null),
('cm-tl-009','continente-guarda','Bacon','Bacon fumado fatiado 200g',2.99,'https://source.unsplash.com/400x400/?bacon',true,'Talho',true,false,null),
('cm-tl-010','continente-guarda','Alheira de Mirandela','Alheira tradicional 200g',3.49,'https://source.unsplash.com/400x400/?sausage,portuguese',true,'Talho',false,false,null),

-- ── PEIXARIA ────────────────────────────────────────────────
('cm-px-001','continente-guarda','Salmão Fresco','Lombo de salmão Atlântico 500g',12.99,'https://source.unsplash.com/400x400/?salmon,fish',true,'Peixaria',true,false,null),
('cm-px-002','continente-guarda','Bacalhau Salgado','Bacalhau seco salgado 500g',14.99,'https://source.unsplash.com/400x400/?cod,fish',true,'Peixaria',true,false,null),
('cm-px-003','continente-guarda','Pescada','Pescada inteira 500g',7.99,'https://source.unsplash.com/400x400/?hake,fish',true,'Peixaria',false,true,6.39),
('cm-px-004','continente-guarda','Dourada','Dourada fresca 300-400g',9.99,'https://source.unsplash.com/400x400/?sea,bream',true,'Peixaria',false,false,null),
('cm-px-005','continente-guarda','Robalo','Robalo fresco 350-500g',11.99,'https://source.unsplash.com/400x400/?sea,bass',true,'Peixaria',false,false,null),
('cm-px-006','continente-guarda','Camarão','Camarão inteiro 500g',15.99,'https://source.unsplash.com/400x400/?shrimp,seafood',true,'Peixaria',true,false,null),
('cm-px-007','continente-guarda','Lulas','Lulas limpas 400g',8.99,'https://source.unsplash.com/400x400/?squid,seafood',true,'Peixaria',false,false,null),
('cm-px-008','continente-guarda','Polvo','Polvo limpo 500g',9.99,'https://source.unsplash.com/400x400/?octopus,seafood',true,'Peixaria',false,false,null),
('cm-px-009','continente-guarda','Atum em Lata','Atum ao natural 120g',1.49,'https://source.unsplash.com/400x400/?tuna,can',true,'Peixaria',true,false,null),
('cm-px-010','continente-guarda','Sardinhas em Lata','Sardinhas em azeite 125g',0.99,'https://source.unsplash.com/400x400/?sardines,can',true,'Peixaria',true,false,null),

-- ── PADARIA ─────────────────────────────────────────────────
('cm-pd-001','continente-guarda','Pão de Forma','Pão de forma branco 500g',1.49,'https://source.unsplash.com/400x400/?bread,white,sliced',true,'Padaria',true,false,null),
('cm-pd-002','continente-guarda','Baguete','Baguete francesa crochante',0.49,'https://source.unsplash.com/400x400/?baguette,bread',true,'Padaria',true,false,null),
('cm-pd-003','continente-guarda','Croissant (4un)','Croissants folhados amanteigados',1.99,'https://source.unsplash.com/400x400/?croissant',true,'Padaria',true,false,null),
('cm-pd-004','continente-guarda','Pão de Mistura','Pão de mistura 400g',1.29,'https://source.unsplash.com/400x400/?whole,grain,bread',true,'Padaria',false,false,null),
('cm-pd-005','continente-guarda','Bola de Berlim','Bola de berlim com creme',0.79,'https://source.unsplash.com/400x400/?donut,pastry',true,'Padaria',true,false,null),
('cm-pd-006','continente-guarda','Carcaças (6un)','Carcaças tradicionais portuguesas',0.89,'https://source.unsplash.com/400x400/?roll,bread',true,'Padaria',true,false,null),
('cm-pd-007','continente-guarda','Pão de Sementes','Pão de sementes mistas 400g',1.79,'https://source.unsplash.com/400x400/?seeded,bread',true,'Padaria',false,false,null),
('cm-pd-008','continente-guarda','Broa de Milho','Broa de milho tradicional 400g',1.59,'https://source.unsplash.com/400x400/?cornbread',true,'Padaria',false,false,null),
('cm-pd-009','continente-guarda','Tosta Integral (20un)','Tostas integrais crocantes',1.99,'https://source.unsplash.com/400x400/?toast,cracker',true,'Padaria',false,false,null),
('cm-pd-010','continente-guarda','Brioche','Brioche amanteigado 300g',2.49,'https://source.unsplash.com/400x400/?brioche,bread',true,'Padaria',false,false,null),

-- ── MERCEARIA ───────────────────────────────────────────────
('cm-mc-001','continente-guarda','Arroz Agulha','Arroz agulha 1kg',1.29,'https://source.unsplash.com/400x400/?rice,grain',true,'Mercearia',true,false,null),
('cm-mc-002','continente-guarda','Esparguete','Massa esparguete 500g',0.79,'https://source.unsplash.com/400x400/?spaghetti,pasta',true,'Mercearia',true,false,null),
('cm-mc-003','continente-guarda','Penne','Massa penne 500g',0.79,'https://source.unsplash.com/400x400/?penne,pasta',true,'Mercearia',true,false,null),
('cm-mc-004','continente-guarda','Azeite Virgem Extra','Azeite virgem extra 750ml',3.99,'https://source.unsplash.com/400x400/?olive,oil',true,'Mercearia',true,false,null),
('cm-mc-005','continente-guarda','Óleo Alimentar','Óleo de girassol 1L',1.99,'https://source.unsplash.com/400x400/?cooking,oil',true,'Mercearia',false,false,null),
('cm-mc-006','continente-guarda','Farinha de Trigo','Farinha tipo 55 1kg',0.89,'https://source.unsplash.com/400x400/?flour,baking',true,'Mercearia',false,false,null),
('cm-mc-007','continente-guarda','Açúcar Branco','Açúcar refinado 1kg',0.99,'https://source.unsplash.com/400x400/?sugar,white',true,'Mercearia',true,false,null),
('cm-mc-008','continente-guarda','Sal Refinado','Sal marinho refinado 1kg',0.49,'https://source.unsplash.com/400x400/?salt',true,'Mercearia',false,false,null),
('cm-mc-009','continente-guarda','Vinagre de Vinho','Vinagre de vinho branco 750ml',0.99,'https://source.unsplash.com/400x400/?vinegar',true,'Mercearia',false,false,null),
('cm-mc-010','continente-guarda','Feijão Vermelho','Feijão vermelho 400g',1.19,'https://source.unsplash.com/400x400/?red,beans',true,'Mercearia',false,false,null),
('cm-mc-011','continente-guarda','Grão de Bico','Grão de bico cozido 400g',1.29,'https://source.unsplash.com/400x400/?chickpeas',true,'Mercearia',false,false,null),
('cm-mc-012','continente-guarda','Lentilhas','Lentilhas verdes 500g',1.49,'https://source.unsplash.com/400x400/?lentils',true,'Mercearia',false,false,null),

-- ── BEBIDAS ─────────────────────────────────────────────────
('cm-bv-001','continente-guarda','Sumo de Laranja','Sumo de laranja 1L',1.99,'https://source.unsplash.com/400x400/?orange,juice',true,'Bebidas',true,false,null),
('cm-bv-002','continente-guarda','Sumo de Maçã','Sumo de maçã 1L',1.79,'https://source.unsplash.com/400x400/?apple,juice',true,'Bebidas',false,false,null),
('cm-bv-003','continente-guarda','Refrigerante Cola','Cola 2L',1.29,'https://source.unsplash.com/400x400/?cola,soda',true,'Bebidas',true,false,null),
('cm-bv-004','continente-guarda','Refrigerante Limão','Refrigerante limão 1,5L',0.99,'https://source.unsplash.com/400x400/?lemon,soda',true,'Bebidas',false,false,null),
('cm-bv-005','continente-guarda','Cerveja Lager (6un)','Pack 6 cervejas 33cl',4.99,'https://source.unsplash.com/400x400/?beer,lager',true,'Bebidas',true,true,3.99),
('cm-bv-006','continente-guarda','Vinho Tinto','Vinho tinto regional 75cl',3.99,'https://source.unsplash.com/400x400/?red,wine',true,'Bebidas',true,false,null),
('cm-bv-007','continente-guarda','Vinho Branco','Vinho branco regional 75cl',3.49,'https://source.unsplash.com/400x400/?white,wine',true,'Bebidas',false,false,null),
('cm-bv-008','continente-guarda','Sidra de Maçã','Sidra natural 33cl',2.49,'https://source.unsplash.com/400x400/?cider,apple',true,'Bebidas',false,false,null),
('cm-bv-009','continente-guarda','Limonada','Limonada artesanal 1L',1.49,'https://source.unsplash.com/400x400/?lemonade',true,'Bebidas',false,false,null),
('cm-bv-010','continente-guarda','Iced Tea Pêssego','Ice tea sabor pêssego 1,5L',1.49,'https://source.unsplash.com/400x400/?iced,tea',true,'Bebidas',false,false,null),

-- ── ÁGUAS ───────────────────────────────────────────────────
('cm-ag-001','continente-guarda','Água Natural 0,5L','Água mineral natural 50cl',0.35,'https://source.unsplash.com/400x400/?water,bottle',true,'Águas',true,false,null),
('cm-ag-002','continente-guarda','Água Natural 1,5L','Água mineral natural 1,5L',0.59,'https://source.unsplash.com/400x400/?water,plastic',true,'Águas',true,false,null),
('cm-ag-003','continente-guarda','Água Natural 5L','Água mineral natural garrafa 5L',1.49,'https://source.unsplash.com/400x400/?water,large',true,'Águas',false,false,null),
('cm-ag-004','continente-guarda','Água Pack 6×1,5L','Pack familiar 6 garrafas 1,5L',3.29,'https://source.unsplash.com/400x400/?water,pack',true,'Águas',true,true,2.79),
('cm-ag-005','continente-guarda','Água com Gás 0,5L','Água gaseificada 50cl',0.49,'https://source.unsplash.com/400x400/?sparkling,water',true,'Águas',false,false,null),
('cm-ag-006','continente-guarda','Água com Gás 1,5L','Água gaseificada 1,5L',0.79,'https://source.unsplash.com/400x400/?sparkling,bottle',true,'Águas',false,false,null),
('cm-ag-007','continente-guarda','Água Saborizada Limão','Água saborizada limão 1,5L',0.89,'https://source.unsplash.com/400x400/?flavored,water,lemon',true,'Águas',false,false,null),
('cm-ag-008','continente-guarda','Água Saborizada Framboesa','Água saborizada framboesa 1,5L',0.89,'https://source.unsplash.com/400x400/?flavored,water',true,'Águas',false,false,null),
('cm-ag-009','continente-guarda','Água Mineral 33cl','Água natural formato bolso',0.45,'https://source.unsplash.com/400x400/?water,small',true,'Águas',false,false,null),
('cm-ag-010','continente-guarda','Água Pack 12×0,5L','Pack 12 garrafas 50cl',3.99,'https://source.unsplash.com/400x400/?water,bottles',true,'Águas',true,false,null),

-- ── CONGELADOS ──────────────────────────────────────────────
('cm-cg-001','continente-guarda','Ervilhas Congeladas','Ervilhas verdes congeladas 1kg',1.49,'https://source.unsplash.com/400x400/?frozen,peas',true,'Congelados',false,false,null),
('cm-cg-002','continente-guarda','Esparguete Bolonhesa','Prato pronto esparguete bolonhesa 400g',3.99,'https://source.unsplash.com/400x400/?pasta,bolognese',true,'Congelados',true,false,null),
('cm-cg-003','continente-guarda','Pizza Margherita','Pizza congelada margherita 330g',3.49,'https://source.unsplash.com/400x400/?pizza,margherita',true,'Congelados',true,true,2.79),
('cm-cg-004','continente-guarda','Pizza Frango','Pizza congelada frango 380g',3.99,'https://source.unsplash.com/400x400/?pizza,chicken',true,'Congelados',false,false,null),
('cm-cg-005','continente-guarda','Lasanha Clássica','Lasanha de carne congelada 400g',4.99,'https://source.unsplash.com/400x400/?lasagna',true,'Congelados',false,false,null),
('cm-cg-006','continente-guarda','Bacalhau com Natas','Bacalhau c/ natas congelado 400g',5.99,'https://source.unsplash.com/400x400/?cod,cream',true,'Congelados',true,false,null),
('cm-cg-007','continente-guarda','Camarão Congelado','Camarão descascado 500g',6.99,'https://source.unsplash.com/400x400/?frozen,shrimp',true,'Congelados',false,false,null),
('cm-cg-008','continente-guarda','Hamburger de Vaca (4un)','Hamburgers bovinos 400g',3.99,'https://source.unsplash.com/400x400/?burger,beef',true,'Congelados',true,false,null),
('cm-cg-009','continente-guarda','Batata Frita Palito','Batatas fritas congeladas 750g',1.99,'https://source.unsplash.com/400x400/?french,fries',true,'Congelados',true,false,null),
('cm-cg-010','continente-guarda','Legumes Salteados','Mix de legumes congelados 600g',2.49,'https://source.unsplash.com/400x400/?frozen,vegetables',true,'Congelados',false,false,null),

-- ── SNACKS ──────────────────────────────────────────────────
('cm-sk-001','continente-guarda','Batatas Fritas','Batatas fritas onduladas 170g',1.79,'https://source.unsplash.com/400x400/?chips,potato',true,'Snacks',true,false,null),
('cm-sk-002','continente-guarda','Nachos','Nachos sabor original 200g',1.99,'https://source.unsplash.com/400x400/?nachos,snack',true,'Snacks',false,false,null),
('cm-sk-003','continente-guarda','Bolachas Maria','Bolachas Maria 400g',0.99,'https://source.unsplash.com/400x400/?biscuit,cookie',true,'Snacks',true,false,null),
('cm-sk-004','continente-guarda','Bolachas Oreo','Bolachas Oreo recheio baunilha 176g',1.89,'https://source.unsplash.com/400x400/?oreo,cookies',true,'Snacks',true,false,null),
('cm-sk-005','continente-guarda','Amendoins Torrados','Amendoins torrados e salgados 200g',1.29,'https://source.unsplash.com/400x400/?peanuts,roasted',true,'Snacks',false,false,null),
('cm-sk-006','continente-guarda','Pipocas Manteiga','Pipocas de manteiga 100g',0.99,'https://source.unsplash.com/400x400/?popcorn',true,'Snacks',false,false,null),
('cm-sk-007','continente-guarda','Chocolate de Leite','Tablette chocolate leite 100g',0.89,'https://source.unsplash.com/400x400/?chocolate,milk',true,'Snacks',true,false,null),
('cm-sk-008','continente-guarda','Chocolate Negro','Tablette chocolate negro 70% 100g',1.29,'https://source.unsplash.com/400x400/?dark,chocolate',true,'Snacks',false,false,null),
('cm-sk-009','continente-guarda','Barras de Cereais (6un)','Pack 6 barras cereal e mel',2.49,'https://source.unsplash.com/400x400/?granola,bar',true,'Snacks',false,false,null),
('cm-sk-010','continente-guarda','Gomas Sortidas','Gomas variadas 200g',1.49,'https://source.unsplash.com/400x400/?gummy,candy',true,'Snacks',true,false,null),
('cm-sk-011','continente-guarda','Palitos de Queijo','Palitos de queijo crocantes 100g',1.99,'https://source.unsplash.com/400x400/?cheese,crackers',true,'Snacks',false,false,null),
('cm-sk-012','continente-guarda','Pretzels','Pretzels salgados 200g',1.49,'https://source.unsplash.com/400x400/?pretzels',true,'Snacks',false,false,null),

-- ── PEQUENO-ALMOÇO ──────────────────────────────────────────
('cm-pa-001','continente-guarda','Cornflakes','Flocos de milho tostados 375g',2.49,'https://source.unsplash.com/400x400/?cornflakes,cereal',true,'Pequeno-almoço',true,false,null),
('cm-pa-002','continente-guarda','Muesli','Muesli com frutos secos 500g',3.49,'https://source.unsplash.com/400x400/?muesli,cereal',true,'Pequeno-almoço',false,false,null),
('cm-pa-003','continente-guarda','Granola','Granola artesanal mel e aveia 400g',3.99,'https://source.unsplash.com/400x400/?granola,breakfast',true,'Pequeno-almoço',false,false,null),
('cm-pa-004','continente-guarda','Nutella','Creme avelã-cacau 400g',3.99,'https://source.unsplash.com/400x400/?nutella,hazelnut',true,'Pequeno-almoço',true,true,3.29),
('cm-pa-005','continente-guarda','Manteiga de Amendoim','Manteiga de amendoim lisa 340g',2.99,'https://source.unsplash.com/400x400/?peanut,butter',true,'Pequeno-almoço',false,false,null),
('cm-pa-006','continente-guarda','Mel Puro','Mel puro de flores 250g',3.49,'https://source.unsplash.com/400x400/?honey,jar',true,'Pequeno-almoço',false,false,null),
('cm-pa-007','continente-guarda','Sumo Laranja NFC','Sumo laranja não concentrado 1L',2.49,'https://source.unsplash.com/400x400/?orange,juice,fresh',true,'Pequeno-almoço',true,false,null),
('cm-pa-008','continente-guarda','Leite Condensado','Leite condensado 397g',1.49,'https://source.unsplash.com/400x400/?condensed,milk',true,'Pequeno-almoço',false,false,null),
('cm-pa-009','continente-guarda','Cereais Chocolate','Cereais com chocolate 375g',2.99,'https://source.unsplash.com/400x400/?chocolate,cereal',true,'Pequeno-almoço',true,false,null),
('cm-pa-010','continente-guarda','Flocos de Aveia','Aveia em flocos integrais 500g',1.99,'https://source.unsplash.com/400x400/?oats,cereal',true,'Pequeno-almoço',false,false,null),

-- ── LIMPEZA ─────────────────────────────────────────────────
('cm-lp-001','continente-guarda','Detergente Roupa Líquido','Det. líquido roupa 1,5L 30 doses',4.99,'https://source.unsplash.com/400x400/?laundry,detergent',true,'Limpeza',true,false,null),
('cm-lp-002','continente-guarda','Amaciador de Roupa','Amaciador 1,5L floral',3.49,'https://source.unsplash.com/400x400/?fabric,softener',true,'Limpeza',false,false,null),
('cm-lp-003','continente-guarda','Detergente Loiça','Detergente loiça limão 500ml',1.49,'https://source.unsplash.com/400x400/?dish,soap',true,'Limpeza',true,false,null),
('cm-lp-004','continente-guarda','Limpador Multi-Usos','Spray limpador superfícies 500ml',2.49,'https://source.unsplash.com/400x400/?cleaning,spray',true,'Limpeza',false,false,null),
('cm-lp-005','continente-guarda','Limpador WC','Gel limpeza WC 750ml',1.99,'https://source.unsplash.com/400x400/?toilet,cleaner',true,'Limpeza',false,false,null),
('cm-lp-006','continente-guarda','Ajax Pó de Limpeza','Pó abrasivo limpeza 500g',1.79,'https://source.unsplash.com/400x400/?cleaning,powder',true,'Limpeza',false,false,null),
('cm-lp-007','continente-guarda','Lixívia','Lixívia lavanda 1,5L',0.99,'https://source.unsplash.com/400x400/?bleach',true,'Limpeza',false,false,null),
('cm-lp-008','continente-guarda','Panos Microfibra (5un)','Panos microfibra multiusos',3.99,'https://source.unsplash.com/400x400/?microfiber,cloth',true,'Limpeza',false,false,null),
('cm-lp-009','continente-guarda','Sacos do Lixo (30un)','Sacos lixo pretos 30L',2.49,'https://source.unsplash.com/400x400/?trash,bags',true,'Limpeza',false,false,null),
('cm-lp-010','continente-guarda','Esponja de Cozinha (3un)','Esponjas dupla função',1.49,'https://source.unsplash.com/400x400/?sponge,kitchen',true,'Limpeza',false,false,null),

-- ── HIGIENE ─────────────────────────────────────────────────
('cm-hg-001','continente-guarda','Champô Cabelo Normal','Champô para cabelo normal 400ml',2.99,'https://source.unsplash.com/400x400/?shampoo,hair',true,'Higiene',true,false,null),
('cm-hg-002','continente-guarda','Gel de Banho','Gel de banho hidratante 400ml',2.49,'https://source.unsplash.com/400x400/?shower,gel',true,'Higiene',true,false,null),
('cm-hg-003','continente-guarda','Pasta de Dentes','Pasta dentes branqueadora 75ml',1.99,'https://source.unsplash.com/400x400/?toothpaste',true,'Higiene',true,false,null),
('cm-hg-004','continente-guarda','Escova de Dentes','Escova dentes macia',1.49,'https://source.unsplash.com/400x400/?toothbrush',true,'Higiene',false,false,null),
('cm-hg-005','continente-guarda','Desodorizante Roll-on','Desodorizante 48h roll-on 50ml',2.49,'https://source.unsplash.com/400x400/?deodorant',true,'Higiene',true,false,null),
('cm-hg-006','continente-guarda','Sabão para Mãos','Sabão líquido mãos 300ml',1.99,'https://source.unsplash.com/400x400/?hand,soap',true,'Higiene',false,false,null),
('cm-hg-007','continente-guarda','Creme Hidratante Corpo','Creme corpo hidratante 400ml',3.99,'https://source.unsplash.com/400x400/?body,lotion',true,'Higiene',false,false,null),
('cm-hg-008','continente-guarda','Papel Higiénico (12un)','Pack 12 rolos 3 folhas',3.49,'https://source.unsplash.com/400x400/?toilet,paper',true,'Higiene',true,false,null),
('cm-hg-009','continente-guarda','Lenços Húmidos (72un)','Lenços húmidos com aloe vera',2.49,'https://source.unsplash.com/400x400/?wet,wipes',true,'Higiene',false,false,null),
('cm-hg-010','continente-guarda','Protetor Solar SPF50','Protetor solar FPS50 200ml',6.99,'https://source.unsplash.com/400x400/?sunscreen',true,'Higiene',false,false,null),

-- ── PET ─────────────────────────────────────────────────────
('cm-pt-001','continente-guarda','Ração Cão Adulto 3kg','Ração completa cão adulto',8.99,'https://source.unsplash.com/400x400/?dog,food',true,'Pet',true,false,null),
('cm-pt-002','continente-guarda','Ração Gato Adulto 3kg','Ração completa gato adulto',7.99,'https://source.unsplash.com/400x400/?cat,food',true,'Pet',true,false,null),
('cm-pt-003','continente-guarda','Petisco Cão 200g','Petiscos prêmio para cão',3.49,'https://source.unsplash.com/400x400/?dog,treats',true,'Pet',false,false,null),
('cm-pt-004','continente-guarda','Petisco Gato 60g','Snacks para gato 60g',1.99,'https://source.unsplash.com/400x400/?cat,treats',true,'Pet',false,false,null),
('cm-pt-005','continente-guarda','Areia para Gato 5L','Areia absorvente para gato',4.99,'https://source.unsplash.com/400x400/?cat,litter',true,'Pet',false,false,null),
('cm-pt-006','continente-guarda','Coleira Antiparasitas','Coleira antiparasitas 65cm',12.99,'https://source.unsplash.com/400x400/?dog,collar',true,'Pet',false,false,null),
('cm-pt-007','continente-guarda','Brinquedo Cão Bola','Bola borracha para cão',3.99,'https://source.unsplash.com/400x400/?dog,toy',true,'Pet',false,false,null),
('cm-pt-008','continente-guarda','Shampoo para Cão','Shampoo pH neutro para cão 250ml',5.99,'https://source.unsplash.com/400x400/?dog,shampoo',true,'Pet',false,false,null),
('cm-pt-009','continente-guarda','Ração Cão Filhote 3kg','Ração crescimento para filhote',9.99,'https://source.unsplash.com/400x400/?puppy,food',true,'Pet',false,false,null),
('cm-pt-010','continente-guarda','Ração Gato Filhote 2kg','Ração crescimento para gatinho',8.49,'https://source.unsplash.com/400x400/?kitten,food',true,'Pet',false,false,null),

-- ── BIO ─────────────────────────────────────────────────────
('cm-bi-001','continente-guarda','Leite Bio 1L','Leite biológico inteiro 1L',1.49,'https://source.unsplash.com/400x400/?organic,milk',true,'Bio',false,false,null),
('cm-bi-002','continente-guarda','Ovos Bio (6un)','Ovos biológicos certificados 6un',2.99,'https://source.unsplash.com/400x400/?organic,eggs',true,'Bio',false,false,null),
('cm-bi-003','continente-guarda','Quinoa Bio 500g','Quinoa branca biológica',4.99,'https://source.unsplash.com/400x400/?quinoa,grain',true,'Bio',false,false,null),
('cm-bi-004','continente-guarda','Arroz Integral Bio 1kg','Arroz integral biológico',2.49,'https://source.unsplash.com/400x400/?brown,rice',true,'Bio',false,false,null),
('cm-bi-005','continente-guarda','Iogurte Natural Bio','Iogurte biológico natural 125g',0.99,'https://source.unsplash.com/400x400/?organic,yogurt',true,'Bio',false,false,null),
('cm-bi-006','continente-guarda','Frango Bio Inteiro','Frango biológico certificado 1,3kg',8.99,'https://source.unsplash.com/400x400/?organic,chicken',true,'Bio',false,false,null),
('cm-bi-007','continente-guarda','Azeite Bio 500ml','Azeite virgem extra biológico',5.99,'https://source.unsplash.com/400x400/?organic,olive,oil',true,'Bio',false,false,null),
('cm-bi-008','continente-guarda','Banana Bio 1kg','Bananas biológicas Fairtrade',1.99,'https://source.unsplash.com/400x400/?organic,banana',true,'Bio',false,false,null),
('cm-bi-009','continente-guarda','Tomate Cherry Bio','Tomate cherry biológico 250g',2.99,'https://source.unsplash.com/400x400/?organic,tomato',true,'Bio',false,false,null),
('cm-bi-010','continente-guarda','Mel Bio 250g','Mel biológico multifloral 250g',4.99,'https://source.unsplash.com/400x400/?organic,honey',true,'Bio',false,false,null),

-- ── GOURMET ─────────────────────────────────────────────────
('cm-gm-001','continente-guarda','Presunto Ibérico Fatiado','Presunto ibérico bellota 100g',9.99,'https://source.unsplash.com/400x400/?iberico,ham',true,'Gourmet',true,false,null),
('cm-gm-002','continente-guarda','Queijo Parmesão Ralado','Parmigiano Reggiano 100g',4.99,'https://source.unsplash.com/400x400/?parmesan,cheese',true,'Gourmet',false,false,null),
('cm-gm-003','continente-guarda','Salmão Fumado','Salmão fumado norueguês 100g',7.99,'https://source.unsplash.com/400x400/?smoked,salmon',true,'Gourmet',true,false,null),
('cm-gm-004','continente-guarda','Foie Gras','Foie gras de pato 130g',14.99,'https://source.unsplash.com/400x400/?foie,gras',true,'Gourmet',false,false,null),
('cm-gm-005','continente-guarda','Champanhe Brut','Champanhe brut 75cl',19.99,'https://source.unsplash.com/400x400/?champagne,sparkling',true,'Gourmet',false,false,null),
('cm-gm-006','continente-guarda','Caviar Beluga','Caviar beluga premium 30g',39.99,'https://source.unsplash.com/400x400/?caviar,luxury',true,'Gourmet',false,false,null),
('cm-gm-007','continente-guarda','Azeitonas Premium','Azeitonas verdes recheadas 200g',3.99,'https://source.unsplash.com/400x400/?olives,gourmet',true,'Gourmet',false,false,null),
('cm-gm-008','continente-guarda','Azeite Premium DOP','Azeite DOP Trás-os-Montes 500ml',8.99,'https://source.unsplash.com/400x400/?premium,olive,oil',true,'Gourmet',false,false,null),
('cm-gm-009','continente-guarda','Chocolate Negro 85%','Chocolate negro 85% cacau 100g',2.99,'https://source.unsplash.com/400x400/?dark,chocolate,premium',true,'Gourmet',false,false,null),
('cm-gm-010','continente-guarda','Trufas de Chocolate','Trufas artesanais sortidas 150g',4.99,'https://source.unsplash.com/400x400/?chocolate,truffle',true,'Gourmet',false,false,null)

ON CONFLICT (id) DO NOTHING;

-- === 4. VARIANTES (3 por produto: baixo · médio · premium) ===
-- Preços: mid = price × 1.35 · premium = price × 1.75

INSERT INTO public.product_variants (id, product_id, brand_name, price) VALUES

-- FRUTAS variants
('pv-cm-fr-001-1','cm-fr-001','Marca Continente',0.89),('pv-cm-fr-001-2','cm-fr-001','Pingo Doce',1.20),('pv-cm-fr-001-3','cm-fr-001','Bio Premium',1.56),
('pv-cm-fr-002-1','cm-fr-002','Marca Continente',1.19),('pv-cm-fr-002-2','cm-fr-002','Pingo Doce',1.61),('pv-cm-fr-002-3','cm-fr-002','Bio Premium',2.08),
('pv-cm-fr-003-1','cm-fr-003','Marca Continente',0.99),('pv-cm-fr-003-2','cm-fr-003','Pingo Doce',1.34),('pv-cm-fr-003-3','cm-fr-003','Bio Premium',1.73),
('pv-cm-fr-004-1','cm-fr-004','Marca Continente',1.39),('pv-cm-fr-004-2','cm-fr-004','Pingo Doce',1.88),('pv-cm-fr-004-3','cm-fr-004','Bio Premium',2.43),
('pv-cm-fr-005-1','cm-fr-005','Marca Continente',2.49),('pv-cm-fr-005-2','cm-fr-005','Pingo Doce',3.36),('pv-cm-fr-005-3','cm-fr-005','Bio Premium',4.36),
('pv-cm-fr-006-1','cm-fr-006','Marca Continente',2.79),('pv-cm-fr-006-2','cm-fr-006','Pingo Doce',3.76),('pv-cm-fr-006-3','cm-fr-006','Bio Premium',4.87),
('pv-cm-fr-007-1','cm-fr-007','Marca Continente',0.49),('pv-cm-fr-007-2','cm-fr-007','Pingo Doce',0.66),('pv-cm-fr-007-3','cm-fr-007','Bio Premium',0.86),
('pv-cm-fr-008-1','cm-fr-008','Marca Continente',0.69),('pv-cm-fr-008-2','cm-fr-008','Pingo Doce',0.93),('pv-cm-fr-008-3','cm-fr-008','Bio Premium',1.21),
('pv-cm-fr-009-1','cm-fr-009','Marca Continente',1.99),('pv-cm-fr-009-2','cm-fr-009','Pingo Doce',2.69),('pv-cm-fr-009-3','cm-fr-009','Bio Premium',3.48),
('pv-cm-fr-010-1','cm-fr-010','Marca Continente',1.89),('pv-cm-fr-010-2','cm-fr-010','Pingo Doce',2.55),('pv-cm-fr-010-3','cm-fr-010','Bio Premium',3.31),
('pv-cm-fr-011-1','cm-fr-011','Marca Continente',3.29),('pv-cm-fr-011-2','cm-fr-011','Pingo Doce',4.44),('pv-cm-fr-011-3','cm-fr-011','Bio Premium',5.76),
('pv-cm-fr-012-1','cm-fr-012','Marca Continente',3.99),('pv-cm-fr-012-2','cm-fr-012','Pingo Doce',5.39),('pv-cm-fr-012-3','cm-fr-012','Bio Premium',6.98),

-- LEGUMES variants
('pv-cm-lg-001-1','cm-lg-001','Marca Continente',1.29),('pv-cm-lg-001-2','cm-lg-001','Pingo Doce',1.74),('pv-cm-lg-001-3','cm-lg-001','Hortaliças Premium',2.26),
('pv-cm-lg-002-1','cm-lg-002','Marca Continente',0.79),('pv-cm-lg-002-2','cm-lg-002','Pingo Doce',1.07),('pv-cm-lg-002-3','cm-lg-002','Hortaliças Premium',1.38),
('pv-cm-lg-003-1','cm-lg-003','Marca Continente',0.99),('pv-cm-lg-003-2','cm-lg-003','Pingo Doce',1.34),('pv-cm-lg-003-3','cm-lg-003','Hortaliças Premium',1.73),
('pv-cm-lg-004-1','cm-lg-004','Marca Continente',0.89),('pv-cm-lg-004-2','cm-lg-004','Pingo Doce',1.20),('pv-cm-lg-004-3','cm-lg-004','Hortaliças Premium',1.56),
('pv-cm-lg-005-1','cm-lg-005','Marca Continente',1.29),('pv-cm-lg-005-2','cm-lg-005','Pingo Doce',1.74),('pv-cm-lg-005-3','cm-lg-005','Hortaliças Premium',2.26),
('pv-cm-lg-006-1','cm-lg-006','Marca Continente',0.99),('pv-cm-lg-006-2','cm-lg-006','Pingo Doce',1.34),('pv-cm-lg-006-3','cm-lg-006','Hortaliças Premium',1.73),
('pv-cm-lg-007-1','cm-lg-007','Marca Continente',1.19),('pv-cm-lg-007-2','cm-lg-007','Pingo Doce',1.61),('pv-cm-lg-007-3','cm-lg-007','Hortaliças Premium',2.01),
('pv-cm-lg-008-1','cm-lg-008','Marca Continente',0.99),('pv-cm-lg-008-2','cm-lg-008','Pingo Doce',1.34),('pv-cm-lg-008-3','cm-lg-008','Hortaliças Premium',1.73),
('pv-cm-lg-009-1','cm-lg-009','Marca Continente',1.19),('pv-cm-lg-009-2','cm-lg-009','Pingo Doce',1.61),('pv-cm-lg-009-3','cm-lg-009','Hortaliças Premium',2.08),
('pv-cm-lg-010-1','cm-lg-010','Marca Continente',1.29),('pv-cm-lg-010-2','cm-lg-010','Pingo Doce',1.74),('pv-cm-lg-010-3','cm-lg-010','Hortaliças Premium',2.26),
('pv-cm-lg-011-1','cm-lg-011','Marca Continente',0.69),('pv-cm-lg-011-2','cm-lg-011','Pingo Doce',0.93),('pv-cm-lg-011-3','cm-lg-011','Hortaliças Premium',1.21),
('pv-cm-lg-012-1','cm-lg-012','Marca Continente',0.99),('pv-cm-lg-012-2','cm-lg-012','Pingo Doce',1.34),('pv-cm-lg-012-3','cm-lg-012','Hortaliças Premium',1.73),

-- LATICÍNIOS variants
('pv-cm-lt-001-1','cm-lt-001','Marca Continente',0.79),('pv-cm-lt-001-2','cm-lt-001','Mimosa',1.07),('pv-cm-lt-001-3','cm-lt-001','Président',1.38),
('pv-cm-lt-002-1','cm-lt-002','Marca Continente',0.69),('pv-cm-lt-002-2','cm-lt-002','Mimosa',0.93),('pv-cm-lt-002-3','cm-lt-002','Président',1.21),
('pv-cm-lt-003-1','cm-lt-003','Marca Continente',0.59),('pv-cm-lt-003-2','cm-lt-003','Danone',0.80),('pv-cm-lt-003-3','cm-lt-003','Activia Premium',1.03),
('pv-cm-lt-004-1','cm-lt-004','Marca Continente',1.29),('pv-cm-lt-004-2','cm-lt-004','Danone',1.74),('pv-cm-lt-004-3','cm-lt-004','Fage Total',2.26),
('pv-cm-lt-005-1','cm-lt-005','Marca Continente',1.99),('pv-cm-lt-005-2','cm-lt-005','Mimosa',2.69),('pv-cm-lt-005-3','cm-lt-005','Président',3.48),
('pv-cm-lt-006-1','cm-lt-006','Marca Continente',1.99),('pv-cm-lt-006-2','cm-lt-006','La Vache Qui Rit',2.69),('pv-cm-lt-006-3','cm-lt-006','Edam Premium',3.36),
('pv-cm-lt-007-1','cm-lt-007','Marca Continente',2.99),('pv-cm-lt-007-2','cm-lt-007','Galbani',4.04),('pv-cm-lt-007-3','cm-lt-007','Di Stefano',5.23),
('pv-cm-lt-008-1','cm-lt-008','Marca Continente',3.49),('pv-cm-lt-008-2','cm-lt-008','Président',4.71),('pv-cm-lt-008-3','cm-lt-008','Le Rustique',6.11),
('pv-cm-lt-009-1','cm-lt-009','Marca Continente',0.99),('pv-cm-lt-009-2','cm-lt-009','Parmalat',1.34),('pv-cm-lt-009-3','cm-lt-009','Elle & Vire',1.73),
('pv-cm-lt-010-1','cm-lt-010','Marca Continente',2.79),('pv-cm-lt-010-2','cm-lt-010','Cathedral City',3.77),('pv-cm-lt-010-3','cm-lt-010','Seriously Strong',4.88),
('pv-cm-lt-011-1','cm-lt-011','Marca Continente',1.89),('pv-cm-lt-011-2','cm-lt-011','Alpro',2.55),('pv-cm-lt-011-3','cm-lt-011','Oatly Premium',3.31),
('pv-cm-lt-012-1','cm-lt-012','Marca Continente',1.09),('pv-cm-lt-012-2','cm-lt-012','Mimosa',1.47),('pv-cm-lt-012-3','cm-lt-012','Lactel',1.91),

-- OVOS variants
('pv-cm-ov-001-1','cm-ov-001','Marca Continente',1.89),('pv-cm-ov-001-2','cm-ov-001','Cascais Select',2.55),('pv-cm-ov-001-3','cm-ov-001','Ovos de Ouro',3.31),
('pv-cm-ov-002-1','cm-ov-002','Marca Continente',2.19),('pv-cm-ov-002-2','cm-ov-002','Cascais Select',2.96),('pv-cm-ov-002-3','cm-ov-002','Ovos de Ouro',3.83),
('pv-cm-ov-003-1','cm-ov-003','Marca Continente',1.49),('pv-cm-ov-003-2','cm-ov-003','Cascais Select',2.01),('pv-cm-ov-003-3','cm-ov-003','Ovos de Ouro',2.61),
('pv-cm-ov-004-1','cm-ov-004','Marca Continente',2.49),('pv-cm-ov-004-2','cm-ov-004','Terra',3.36),('pv-cm-ov-004-3','cm-ov-004','Naturovos Bio',4.36),
('pv-cm-ov-005-1','cm-ov-005','Marca Continente',3.49),('pv-cm-ov-005-2','cm-ov-005','Quinta Feliz',4.71),('pv-cm-ov-005-3','cm-ov-005','Happy Farm',6.11),
('pv-cm-ov-006-1','cm-ov-006','Marca Continente',2.99),('pv-cm-ov-006-2','cm-ov-006','Naturovi',4.04),('pv-cm-ov-006-3','cm-ov-006','Pure White',5.23),
('pv-cm-ov-007-1','cm-ov-007','Marca Continente',2.79),('pv-cm-ov-007-2','cm-ov-007','Quinta do Sol',3.77),('pv-cm-ov-007-3','cm-ov-007','Caipira Gold',4.88),
('pv-cm-ov-008-1','cm-ov-008','Marca Continente',1.99),('pv-cm-ov-008-2','cm-ov-008','Quinta das Codornizes',2.69),('pv-cm-ov-008-3','cm-ov-008','Codorniz Premium',3.48),
('pv-cm-ov-009-1','cm-ov-009','Marca Continente',2.99),('pv-cm-ov-009-2','cm-ov-009','Vital Omega',4.04),('pv-cm-ov-009-3','cm-ov-009','Omega Gold',5.23),
('pv-cm-ov-010-1','cm-ov-010','Marca Continente',1.49),('pv-cm-ov-010-2','cm-ov-010','Ovos Prontos',2.01),('pv-cm-ov-010-3','cm-ov-010','Easy Eggs',2.61),

-- TALHO variants
('pv-cm-tl-001-1','cm-tl-001','Marca Continente',4.99),('pv-cm-tl-001-2','cm-tl-001','Nobre',6.74),('pv-cm-tl-001-3','cm-tl-001','Puresabor',8.73),
('pv-cm-tl-002-1','cm-tl-002','Marca Continente',6.99),('pv-cm-tl-002-2','cm-tl-002','Nobre',9.44),('pv-cm-tl-002-3','cm-tl-002','Puresabor',12.23),
('pv-cm-tl-003-1','cm-tl-003','Marca Continente',4.39),('pv-cm-tl-003-2','cm-tl-003','Nobre',5.93),('pv-cm-tl-003-3','cm-tl-003','Puresabor',7.68),
('pv-cm-tl-004-1','cm-tl-004','Marca Continente',8.99),('pv-cm-tl-004-2','cm-tl-004','Vaca Feliz',12.14),('pv-cm-tl-004-3','cm-tl-004','Black Angus',15.73),
('pv-cm-tl-005-1','cm-tl-005','Marca Continente',5.99),('pv-cm-tl-005-2','cm-tl-005','Nobre',8.09),('pv-cm-tl-005-3','cm-tl-005','Puresabor',10.48),
('pv-cm-tl-006-1','cm-tl-006','Marca Continente',6.49),('pv-cm-tl-006-2','cm-tl-006','Nobre',8.76),('pv-cm-tl-006-3','cm-tl-006','Puresabor',11.36),
('pv-cm-tl-007-1','cm-tl-007','Marca Continente',7.99),('pv-cm-tl-007-2','cm-tl-007','Nobre',10.79),('pv-cm-tl-007-3','cm-tl-007','Puresabor',13.98),
('pv-cm-tl-008-1','cm-tl-008','Marca Continente',2.49),('pv-cm-tl-008-2','cm-tl-008','Campofrio',3.36),('pv-cm-tl-008-3','cm-tl-008','Bratwurst Premium',4.36),
('pv-cm-tl-009-1','cm-tl-009','Marca Continente',2.99),('pv-cm-tl-009-2','cm-tl-009','Oscar Mayer',4.04),('pv-cm-tl-009-3','cm-tl-009','Bacon Premium',5.23),
('pv-cm-tl-010-1','cm-tl-010','Marca Continente',3.49),('pv-cm-tl-010-2','cm-tl-010','Fumeiro Real',4.71),('pv-cm-tl-010-3','cm-tl-010','Mirandela Gold',6.11),

-- PEIXARIA variants
('pv-cm-px-001-1','cm-px-001','Marca Continente',12.99),('pv-cm-px-001-2','cm-px-001','Pescanova',17.54),('pv-cm-px-001-3','cm-px-001','Norwegian Premium',22.73),
('pv-cm-px-002-1','cm-px-002','Marca Continente',14.99),('pv-cm-px-002-2','cm-px-002','Riberalves',20.24),('pv-cm-px-002-3','cm-px-002','Bacalhau Especial',26.23),
('pv-cm-px-003-1','cm-px-003','Marca Continente',6.39),('pv-cm-px-003-2','cm-px-003','Pescanova',8.63),('pv-cm-px-003-3','cm-px-003','Mar Premium',11.19),
('pv-cm-px-004-1','cm-px-004','Marca Continente',9.99),('pv-cm-px-004-2','cm-px-004','Pescanova',13.49),('pv-cm-px-004-3','cm-px-004','Mar Premium',17.48),
('pv-cm-px-005-1','cm-px-005','Marca Continente',11.99),('pv-cm-px-005-2','cm-px-005','Pescanova',16.19),('pv-cm-px-005-3','cm-px-005','Mar Premium',20.98),
('pv-cm-px-006-1','cm-px-006','Marca Continente',15.99),('pv-cm-px-006-2','cm-px-006','Pescanova',21.59),('pv-cm-px-006-3','cm-px-006','Mar Premium',27.98),
('pv-cm-px-007-1','cm-px-007','Marca Continente',8.99),('pv-cm-px-007-2','cm-px-007','Pescanova',12.14),('pv-cm-px-007-3','cm-px-007','Mar Premium',15.73),
('pv-cm-px-008-1','cm-px-008','Marca Continente',9.99),('pv-cm-px-008-2','cm-px-008','Pescanova',13.49),('pv-cm-px-008-3','cm-px-008','Mar Premium',17.48),
('pv-cm-px-009-1','cm-px-009','Marca Continente',1.49),('pv-cm-px-009-2','cm-px-009','Bom Petisco',2.01),('pv-cm-px-009-3','cm-px-009','Rio Mare',2.61),
('pv-cm-px-010-1','cm-px-010','Marca Continente',0.99),('pv-cm-px-010-2','cm-px-010','Bom Petisco',1.34),('pv-cm-px-010-3','cm-px-010','Briosa Gold',1.73),

-- PADARIA variants
('pv-cm-pd-001-1','cm-pd-001','Marca Continente',1.49),('pv-cm-pd-001-2','cm-pd-001','Panrico',2.01),('pv-cm-pd-001-3','cm-pd-001','Boulangerie',2.61),
('pv-cm-pd-002-1','cm-pd-002','Marca Continente',0.49),('pv-cm-pd-002-2','cm-pd-002','Panrico',0.66),('pv-cm-pd-002-3','cm-pd-002','Boulangerie',0.86),
('pv-cm-pd-003-1','cm-pd-003','Marca Continente',1.99),('pv-cm-pd-003-2','cm-pd-003','Panrico',2.69),('pv-cm-pd-003-3','cm-pd-003','Brioche Dorée',3.48),
('pv-cm-pd-004-1','cm-pd-004','Marca Continente',1.29),('pv-cm-pd-004-2','cm-pd-004','Panrico',1.74),('pv-cm-pd-004-3','cm-pd-004','Boulangerie',2.26),
('pv-cm-pd-005-1','cm-pd-005','Marca Continente',0.79),('pv-cm-pd-005-2','cm-pd-005','Pastelaria Real',1.07),('pv-cm-pd-005-3','cm-pd-005','Patisserie Gold',1.38),
('pv-cm-pd-006-1','cm-pd-006','Marca Continente',0.89),('pv-cm-pd-006-2','cm-pd-006','Panrico',1.20),('pv-cm-pd-006-3','cm-pd-006','Boulangerie',1.56),
('pv-cm-pd-007-1','cm-pd-007','Marca Continente',1.79),('pv-cm-pd-007-2','cm-pd-007','Panrico',2.42),('pv-cm-pd-007-3','cm-pd-007','Boulangerie',3.13),
('pv-cm-pd-008-1','cm-pd-008','Marca Continente',1.59),('pv-cm-pd-008-2','cm-pd-008','Tradicional',2.15),('pv-cm-pd-008-3','cm-pd-008','Aldeia Gold',2.78),
('pv-cm-pd-009-1','cm-pd-009','Marca Continente',1.99),('pv-cm-pd-009-2','cm-pd-009','Wasa',2.69),('pv-cm-pd-009-3','cm-pd-009','Ryvita',3.48),
('pv-cm-pd-010-1','cm-pd-010','Marca Continente',2.49),('pv-cm-pd-010-2','cm-pd-010','St Moret',3.36),('pv-cm-pd-010-3','cm-pd-010','Brioche Dorée',4.36),

-- MERCEARIA variants
('pv-cm-mc-001-1','cm-mc-001','Marca Continente',1.29),('pv-cm-mc-001-2','cm-mc-001','Nacional',1.74),('pv-cm-mc-001-3','cm-mc-001','Cigala',2.26),
('pv-cm-mc-002-1','cm-mc-002','Marca Continente',0.79),('pv-cm-mc-002-2','cm-mc-002','Nacional',1.07),('pv-cm-mc-002-3','cm-mc-002','Barilla',1.38),
('pv-cm-mc-003-1','cm-mc-003','Marca Continente',0.79),('pv-cm-mc-003-2','cm-mc-003','Nacional',1.07),('pv-cm-mc-003-3','cm-mc-003','Barilla',1.38),
('pv-cm-mc-004-1','cm-mc-004','Marca Continente',3.99),('pv-cm-mc-004-2','cm-mc-004','Gallo',5.39),('pv-cm-mc-004-3','cm-mc-004','Herdade do Esporão',6.98),
('pv-cm-mc-005-1','cm-mc-005','Marca Continente',1.99),('pv-cm-mc-005-2','cm-mc-005','Fula',2.69),('pv-cm-mc-005-3','cm-mc-005','Bertolli',3.48),
('pv-cm-mc-006-1','cm-mc-006','Marca Continente',0.89),('pv-cm-mc-006-2','cm-mc-006','Nacional',1.20),('pv-cm-mc-006-3','cm-mc-006','Espiga',1.56),
('pv-cm-mc-007-1','cm-mc-007','Marca Continente',0.99),('pv-cm-mc-007-2','cm-mc-007','Sidul',1.34),('pv-cm-mc-007-3','cm-mc-007','Demerara Gold',1.73),
('pv-cm-mc-008-1','cm-mc-008','Marca Continente',0.49),('pv-cm-mc-008-2','cm-mc-008','Salmarim',0.66),('pv-cm-mc-008-3','cm-mc-008','Flor de Sal',0.86),
('pv-cm-mc-009-1','cm-mc-009','Marca Continente',0.99),('pv-cm-mc-009-2','cm-mc-009','Borges',1.34),('pv-cm-mc-009-3','cm-mc-009','Maille',1.73),
('pv-cm-mc-010-1','cm-mc-010','Marca Continente',1.19),('pv-cm-mc-010-2','cm-mc-010','Nacional',1.61),('pv-cm-mc-010-3','cm-mc-010','Heinz',2.08),
('pv-cm-mc-011-1','cm-mc-011','Marca Continente',1.29),('pv-cm-mc-011-2','cm-mc-011','Nacional',1.74),('pv-cm-mc-011-3','cm-mc-011','Borgo',2.26),
('pv-cm-mc-012-1','cm-mc-012','Marca Continente',1.49),('pv-cm-mc-012-2','cm-mc-012','Nacional',2.01),('pv-cm-mc-012-3','cm-mc-012','Puy Green',2.61),

-- BEBIDAS variants
('pv-cm-bv-001-1','cm-bv-001','Marca Continente',1.99),('pv-cm-bv-001-2','cm-bv-001','Compal',2.69),('pv-cm-bv-001-3','cm-bv-001','Tropicana',3.48),
('pv-cm-bv-002-1','cm-bv-002','Marca Continente',1.79),('pv-cm-bv-002-2','cm-bv-002','Compal',2.42),('pv-cm-bv-002-3','cm-bv-002','Tropicana',3.13),
('pv-cm-bv-003-1','cm-bv-003','Marca Continente',1.29),('pv-cm-bv-003-2','cm-bv-003','Pepsi',1.74),('pv-cm-bv-003-3','cm-bv-003','Coca-Cola',2.26),
('pv-cm-bv-004-1','cm-bv-004','Marca Continente',0.99),('pv-cm-bv-004-2','cm-bv-004','7Up',1.34),('pv-cm-bv-004-3','cm-bv-004','San Pellegrino',1.73),
('pv-cm-bv-005-1','cm-bv-005','Marca Continente',3.99),('pv-cm-bv-005-2','cm-bv-005','Super Bock',5.39),('pv-cm-bv-005-3','cm-bv-005','Sagres Reserva',6.98),
('pv-cm-bv-006-1','cm-bv-006','Marca Continente',3.99),('pv-cm-bv-006-2','cm-bv-006','Casal Garcia',5.39),('pv-cm-bv-006-3','cm-bv-006','Esporão Reserva',6.98),
('pv-cm-bv-007-1','cm-bv-007','Marca Continente',3.49),('pv-cm-bv-007-2','cm-bv-007','Casal Garcia',4.71),('pv-cm-bv-007-3','cm-bv-007','Alvarinho Premium',6.11),
('pv-cm-bv-008-1','cm-bv-008','Marca Continente',2.49),('pv-cm-bv-008-2','cm-bv-008','Somersby',3.36),('pv-cm-bv-008-3','cm-bv-008','Bulmers',4.36),
('pv-cm-bv-009-1','cm-bv-009','Marca Continente',1.49),('pv-cm-bv-009-2','cm-bv-009','Frutis',2.01),('pv-cm-bv-009-3','cm-bv-009','Limoneiro Artisan',2.61),
('pv-cm-bv-010-1','cm-bv-010','Marca Continente',1.49),('pv-cm-bv-010-2','cm-bv-010','Lipton',2.01),('pv-cm-bv-010-3','cm-bv-010','Fuze Tea',2.61),

-- ÁGUAS variants
('pv-cm-ag-001-1','cm-ag-001','Marca Continente',0.35),('pv-cm-ag-001-2','cm-ag-001','Luso',0.47),('pv-cm-ag-001-3','cm-ag-001','Evian',0.61),
('pv-cm-ag-002-1','cm-ag-002','Marca Continente',0.59),('pv-cm-ag-002-2','cm-ag-002','Luso',0.80),('pv-cm-ag-002-3','cm-ag-002','Evian',1.03),
('pv-cm-ag-003-1','cm-ag-003','Marca Continente',1.49),('pv-cm-ag-003-2','cm-ag-003','Luso',2.01),('pv-cm-ag-003-3','cm-ag-003','Evian',2.61),
('pv-cm-ag-004-1','cm-ag-004','Marca Continente',2.79),('pv-cm-ag-004-2','cm-ag-004','Luso',3.77),('pv-cm-ag-004-3','cm-ag-004','Evian',4.88),
('pv-cm-ag-005-1','cm-ag-005','Marca Continente',0.49),('pv-cm-ag-005-2','cm-ag-005','Pedras',0.66),('pv-cm-ag-005-3','cm-ag-005','San Pellegrino',0.86),
('pv-cm-ag-006-1','cm-ag-006','Marca Continente',0.79),('pv-cm-ag-006-2','cm-ag-006','Pedras',1.07),('pv-cm-ag-006-3','cm-ag-006','San Pellegrino',1.38),
('pv-cm-ag-007-1','cm-ag-007','Marca Continente',0.89),('pv-cm-ag-007-2','cm-ag-007','Luso Frut',1.20),('pv-cm-ag-007-3','cm-ag-007','Vittel Lemon',1.56),
('pv-cm-ag-008-1','cm-ag-008','Marca Continente',0.89),('pv-cm-ag-008-2','cm-ag-008','Luso Frut',1.20),('pv-cm-ag-008-3','cm-ag-008','Vittel Berry',1.56),
('pv-cm-ag-009-1','cm-ag-009','Marca Continente',0.45),('pv-cm-ag-009-2','cm-ag-009','Luso',0.61),('pv-cm-ag-009-3','cm-ag-009','Evian',0.79),
('pv-cm-ag-010-1','cm-ag-010','Marca Continente',3.99),('pv-cm-ag-010-2','cm-ag-010','Luso',5.39),('pv-cm-ag-010-3','cm-ag-010','Evian',6.98),

-- CONGELADOS variants
('pv-cm-cg-001-1','cm-cg-001','Marca Continente',1.49),('pv-cm-cg-001-2','cm-cg-001','Iglo',2.01),('pv-cm-cg-001-3','cm-cg-001','Birds Eye',2.61),
('pv-cm-cg-002-1','cm-cg-002','Marca Continente',3.99),('pv-cm-cg-002-2','cm-cg-002','Findus',5.39),('pv-cm-cg-002-3','cm-cg-002','La Famiglia',6.98),
('pv-cm-cg-003-1','cm-cg-003','Marca Continente',2.79),('pv-cm-cg-003-2','cm-cg-003','Dr. Oetker',3.77),('pv-cm-cg-003-3','cm-cg-003','Ristorante',4.88),
('pv-cm-cg-004-1','cm-cg-004','Marca Continente',3.99),('pv-cm-cg-004-2','cm-cg-004','Dr. Oetker',5.39),('pv-cm-cg-004-3','cm-cg-004','Ristorante',6.98),
('pv-cm-cg-005-1','cm-cg-005','Marca Continente',4.99),('pv-cm-cg-005-2','cm-cg-005','Findus',6.74),('pv-cm-cg-005-3','cm-cg-005','La Famiglia',8.73),
('pv-cm-cg-006-1','cm-cg-006','Marca Continente',5.99),('pv-cm-cg-006-2','cm-cg-006','Pescanova',8.09),('pv-cm-cg-006-3','cm-cg-006','Lusomar Gold',10.48),
('pv-cm-cg-007-1','cm-cg-007','Marca Continente',6.99),('pv-cm-cg-007-2','cm-cg-007','Pescanova',9.44),('pv-cm-cg-007-3','cm-cg-007','Mar Premium',12.23),
('pv-cm-cg-008-1','cm-cg-008','Marca Continente',3.99),('pv-cm-cg-008-2','cm-cg-008','Quick',5.39),('pv-cm-cg-008-3','cm-cg-008','Black Angus',6.98),
('pv-cm-cg-009-1','cm-cg-009','Marca Continente',1.99),('pv-cm-cg-009-2','cm-cg-009','Iglo',2.69),('pv-cm-cg-009-3','cm-cg-009','McCain',3.48),
('pv-cm-cg-010-1','cm-cg-010','Marca Continente',2.49),('pv-cm-cg-010-2','cm-cg-010','Iglo',3.36),('pv-cm-cg-010-3','cm-cg-010','Birds Eye',4.36),

-- SNACKS variants
('pv-cm-sk-001-1','cm-sk-001','Marca Continente',1.79),('pv-cm-sk-001-2','cm-sk-001','Lay''s',2.42),('pv-cm-sk-001-3','cm-sk-001','Pringles',3.13),
('pv-cm-sk-002-1','cm-sk-002','Marca Continente',1.99),('pv-cm-sk-002-2','cm-sk-002','Doritos',2.69),('pv-cm-sk-002-3','cm-sk-002','Tostitos',3.48),
('pv-cm-sk-003-1','cm-sk-003','Marca Continente',0.99),('pv-cm-sk-003-2','cm-sk-003','Lu',1.34),('pv-cm-sk-003-3','cm-sk-003','McVitie''s',1.73),
('pv-cm-sk-004-1','cm-sk-004','Marca Continente',1.89),('pv-cm-sk-004-2','cm-sk-004','Oreo',2.55),('pv-cm-sk-004-3','cm-sk-004','Milka Choco',3.31),
('pv-cm-sk-005-1','cm-sk-005','Marca Continente',1.29),('pv-cm-sk-005-2','cm-sk-005','Planters',1.74),('pv-cm-sk-005-3','cm-sk-005','Cashew Premium',2.26),
('pv-cm-sk-006-1','cm-sk-006','Marca Continente',0.99),('pv-cm-sk-006-2','cm-sk-006','Pop Weaver',1.34),('pv-cm-sk-006-3','cm-sk-006','Orville',1.73),
('pv-cm-sk-007-1','cm-sk-007','Marca Continente',0.89),('pv-cm-sk-007-2','cm-sk-007','Milka',1.20),('pv-cm-sk-007-3','cm-sk-007','Lindt',1.56),
('pv-cm-sk-008-1','cm-sk-008','Marca Continente',1.29),('pv-cm-sk-008-2','cm-sk-008','Valor',1.74),('pv-cm-sk-008-3','cm-sk-008','Lindt Excellence',2.26),
('pv-cm-sk-009-1','cm-sk-009','Marca Continente',2.49),('pv-cm-sk-009-2','cm-sk-009','Nature Valley',3.36),('pv-cm-sk-009-3','cm-sk-009','Kind Bar',4.36),
('pv-cm-sk-010-1','cm-sk-010','Marca Continente',1.49),('pv-cm-sk-010-2','cm-sk-010','Haribo',2.01),('pv-cm-sk-010-3','cm-sk-010','Trolli Premium',2.61),
('pv-cm-sk-011-1','cm-sk-011','Marca Continente',1.99),('pv-cm-sk-011-2','cm-sk-011','Cheez-It',2.69),('pv-cm-sk-011-3','cm-sk-011','Pepperidge',3.48),
('pv-cm-sk-012-1','cm-sk-012','Marca Continente',1.49),('pv-cm-sk-012-2','cm-sk-012','Rold Gold',2.01),('pv-cm-sk-012-3','cm-sk-012','Snyder''s',2.61),

-- PEQUENO-ALMOÇO variants
('pv-cm-pa-001-1','cm-pa-001','Marca Continente',2.49),('pv-cm-pa-001-2','cm-pa-001','Kellogg''s',3.36),('pv-cm-pa-001-3','cm-pa-001','Special K Gold',4.36),
('pv-cm-pa-002-1','cm-pa-002','Marca Continente',3.49),('pv-cm-pa-002-2','cm-pa-002','Jordans',4.71),('pv-cm-pa-002-3','cm-pa-002','Bob''s Red Mill',6.11),
('pv-cm-pa-003-1','cm-pa-003','Marca Continente',3.99),('pv-cm-pa-003-2','cm-pa-003','Jordans',5.39),('pv-cm-pa-003-3','cm-pa-003','Kind Granola',6.98),
('pv-cm-pa-004-1','cm-pa-004','Marca Continente',3.29),('pv-cm-pa-004-2','cm-pa-004','Nutella',4.45),('pv-cm-pa-004-3','cm-pa-004','Justin''s',5.77),
('pv-cm-pa-005-1','cm-pa-005','Marca Continente',2.99),('pv-cm-pa-005-2','cm-pa-005','Skippy',4.04),('pv-cm-pa-005-3','cm-pa-005','Justin''s Almond',5.23),
('pv-cm-pa-006-1','cm-pa-006','Marca Continente',3.49),('pv-cm-pa-006-2','cm-pa-006','Vitacress',4.71),('pv-cm-pa-006-3','cm-pa-006','Manuka Gold',6.11),
('pv-cm-pa-007-1','cm-pa-007','Marca Continente',2.49),('pv-cm-pa-007-2','cm-pa-007','Compal',3.36),('pv-cm-pa-007-3','cm-pa-007','Tropicana',4.36),
('pv-cm-pa-008-1','cm-pa-008','Marca Continente',1.49),('pv-cm-pa-008-2','cm-pa-008','Nestlé',2.01),('pv-cm-pa-008-3','cm-pa-008','Eagle Brand',2.61),
('pv-cm-pa-009-1','cm-pa-009','Marca Continente',2.99),('pv-cm-pa-009-2','cm-pa-009','Kellogg''s Choco',4.04),('pv-cm-pa-009-3','cm-pa-009','Nestlé Chocapic',5.23),
('pv-cm-pa-010-1','cm-pa-010','Marca Continente',1.99),('pv-cm-pa-010-2','cm-pa-010','Quaker',2.69),('pv-cm-pa-010-3','cm-pa-010','Bob''s Red Mill',3.48),

-- LIMPEZA variants
('pv-cm-lp-001-1','cm-lp-001','Marca Continente',4.99),('pv-cm-lp-001-2','cm-lp-001','Ariel',6.74),('pv-cm-lp-001-3','cm-lp-001','Persil',8.73),
('pv-cm-lp-002-1','cm-lp-002','Marca Continente',3.49),('pv-cm-lp-002-2','cm-lp-002','Comfort',4.71),('pv-cm-lp-002-3','cm-lp-002','Lenor',6.11),
('pv-cm-lp-003-1','cm-lp-003','Marca Continente',1.49),('pv-cm-lp-003-2','cm-lp-003','Fairy',2.01),('pv-cm-lp-003-3','cm-lp-003','Dawn Platinum',2.61),
('pv-cm-lp-004-1','cm-lp-004','Marca Continente',2.49),('pv-cm-lp-004-2','cm-lp-004','Mr. Proper',3.36),('pv-cm-lp-004-3','cm-lp-004','Method Premium',4.36),
('pv-cm-lp-005-1','cm-lp-005','Marca Continente',1.99),('pv-cm-lp-005-2','cm-lp-005','Domestos',2.69),('pv-cm-lp-005-3','cm-lp-005','Harpic Power',3.48),
('pv-cm-lp-006-1','cm-lp-006','Marca Continente',1.79),('pv-cm-lp-006-2','cm-lp-006','Ajax',2.42),('pv-cm-lp-006-3','cm-lp-006','Bar Keepers',3.13),
('pv-cm-lp-007-1','cm-lp-007','Marca Continente',0.99),('pv-cm-lp-007-2','cm-lp-007','Ace',1.34),('pv-cm-lp-007-3','cm-lp-007','Domestos Bleach',1.73),
('pv-cm-lp-008-1','cm-lp-008','Marca Continente',3.99),('pv-cm-lp-008-2','cm-lp-008','3M Scotch-Brite',5.39),('pv-cm-lp-008-3','cm-lp-008','E-Cloth Premium',6.98),
('pv-cm-lp-009-1','cm-lp-009','Marca Continente',2.49),('pv-cm-lp-009-2','cm-lp-009','Glad',3.36),('pv-cm-lp-009-3','cm-lp-009','Hefty Premium',4.36),
('pv-cm-lp-010-1','cm-lp-010','Marca Continente',1.49),('pv-cm-lp-010-2','cm-lp-010','3M Scotch-Brite',2.01),('pv-cm-lp-010-3','cm-lp-010','Vileda Premium',2.61),

-- HIGIENE variants
('pv-cm-hg-001-1','cm-hg-001','Marca Continente',2.99),('pv-cm-hg-001-2','cm-hg-001','Pantene',4.04),('pv-cm-hg-001-3','cm-hg-001','L''Oréal',5.23),
('pv-cm-hg-002-1','cm-hg-002','Marca Continente',2.49),('pv-cm-hg-002-2','cm-hg-002','Dove',3.36),('pv-cm-hg-002-3','cm-hg-002','Rituals',4.36),
('pv-cm-hg-003-1','cm-hg-003','Marca Continente',1.99),('pv-cm-hg-003-2','cm-hg-003','Colgate',2.69),('pv-cm-hg-003-3','cm-hg-003','Oral-B Pro',3.48),
('pv-cm-hg-004-1','cm-hg-004','Marca Continente',1.49),('pv-cm-hg-004-2','cm-hg-004','Colgate',2.01),('pv-cm-hg-004-3','cm-hg-004','Oral-B Pro',2.61),
('pv-cm-hg-005-1','cm-hg-005','Marca Continente',2.49),('pv-cm-hg-005-2','cm-hg-005','Rexona',3.36),('pv-cm-hg-005-3','cm-hg-005','Dove Advanced',4.36),
('pv-cm-hg-006-1','cm-hg-006','Marca Continente',1.99),('pv-cm-hg-006-2','cm-hg-006','Dove',2.69),('pv-cm-hg-006-3','cm-hg-006','Molton Brown',3.48),
('pv-cm-hg-007-1','cm-hg-007','Marca Continente',3.99),('pv-cm-hg-007-2','cm-hg-007','Nivea',5.39),('pv-cm-hg-007-3','cm-hg-007','Clarins',6.98),
('pv-cm-hg-008-1','cm-hg-008','Marca Continente',3.49),('pv-cm-hg-008-2','cm-hg-008','Scottex',4.71),('pv-cm-hg-008-3','cm-hg-008','Renova Black',6.11),
('pv-cm-hg-009-1','cm-hg-009','Marca Continente',2.49),('pv-cm-hg-009-2','cm-hg-009','Pampers',3.36),('pv-cm-hg-009-3','cm-hg-009','WaterWipes',4.36),
('pv-cm-hg-010-1','cm-hg-010','Marca Continente',6.99),('pv-cm-hg-010-2','cm-hg-010','Garnier',9.44),('pv-cm-hg-010-3','cm-hg-010','La Roche-Posay',12.23),

-- PET variants
('pv-cm-pt-001-1','cm-pt-001','Marca Continente',8.99),('pv-cm-pt-001-2','cm-pt-001','Pedigree',12.14),('pv-cm-pt-001-3','cm-pt-001','Royal Canin',15.73),
('pv-cm-pt-002-1','cm-pt-002','Marca Continente',7.99),('pv-cm-pt-002-2','cm-pt-002','Whiskas',10.79),('pv-cm-pt-002-3','cm-pt-002','Royal Canin',13.98),
('pv-cm-pt-003-1','cm-pt-003','Marca Continente',3.49),('pv-cm-pt-003-2','cm-pt-003','Pedigree Rodeo',4.71),('pv-cm-pt-003-3','cm-pt-003','Zuke''s Mini',6.11),
('pv-cm-pt-004-1','cm-pt-004','Marca Continente',1.99),('pv-cm-pt-004-2','cm-pt-004','Whiskas Temptations',2.69),('pv-cm-pt-004-3','cm-pt-004','Dreamies',3.48),
('pv-cm-pt-005-1','cm-pt-005','Marca Continente',4.99),('pv-cm-pt-005-2','cm-pt-005','Catsan',6.74),('pv-cm-pt-005-3','cm-pt-005','Ever Clean',8.73),
('pv-cm-pt-006-1','cm-pt-006','Marca Continente',12.99),('pv-cm-pt-006-2','cm-pt-006','Seresto',17.54),('pv-cm-pt-006-3','cm-pt-006','Frontline',22.73),
('pv-cm-pt-007-1','cm-pt-007','Marca Continente',3.99),('pv-cm-pt-007-2','cm-pt-007','Kong',5.39),('pv-cm-pt-007-3','cm-pt-007','West Paw',6.98),
('pv-cm-pt-008-1','cm-pt-008','Marca Continente',5.99),('pv-cm-pt-008-2','cm-pt-008','TropiClean',8.09),('pv-cm-pt-008-3','cm-pt-008','Burt''s Bees Pet',10.48),
('pv-cm-pt-009-1','cm-pt-009','Marca Continente',9.99),('pv-cm-pt-009-2','cm-pt-009','Pedigree Puppy',13.49),('pv-cm-pt-009-3','cm-pt-009','Royal Canin Junior',17.48),
('pv-cm-pt-010-1','cm-pt-010','Marca Continente',8.49),('pv-cm-pt-010-2','cm-pt-010','Whiskas Kitten',11.46),('pv-cm-pt-010-3','cm-pt-010','Royal Canin Kitten',14.86),

-- BIO variants
('pv-cm-bi-001-1','cm-bi-001','Marca Continente Bio',1.49),('pv-cm-bi-001-2','cm-bi-001','Celeiro Bio',2.01),('pv-cm-bi-001-3','cm-bi-001','Organic Valley',2.61),
('pv-cm-bi-002-1','cm-bi-002','Marca Continente Bio',2.99),('pv-cm-bi-002-2','cm-bi-002','Terra Bio',4.04),('pv-cm-bi-002-3','cm-bi-002','Happy Hen Organic',5.23),
('pv-cm-bi-003-1','cm-bi-003','Marca Continente Bio',4.99),('pv-cm-bi-003-2','cm-bi-003','Celeiro Bio',6.74),('pv-cm-bi-003-3','cm-bi-003','Ancient Harvest',8.73),
('pv-cm-bi-004-1','cm-bi-004','Marca Continente Bio',2.49),('pv-cm-bi-004-2','cm-bi-004','Celeiro Bio',3.36),('pv-cm-bi-004-3','cm-bi-004','Lundberg',4.36),
('pv-cm-bi-005-1','cm-bi-005','Marca Continente Bio',0.99),('pv-cm-bi-005-2','cm-bi-005','Activia Bio',1.34),('pv-cm-bi-005-3','cm-bi-005','Stonyfield',1.73),
('pv-cm-bi-006-1','cm-bi-006','Marca Continente Bio',8.99),('pv-cm-bi-006-2','cm-bi-006','Celeiro Bio',12.14),('pv-cm-bi-006-3','cm-bi-006','Label Rouge',15.73),
('pv-cm-bi-007-1','cm-bi-007','Marca Continente Bio',5.99),('pv-cm-bi-007-2','cm-bi-007','Gallo Bio',8.09),('pv-cm-bi-007-3','cm-bi-007','Esporão Bio',10.48),
('pv-cm-bi-008-1','cm-bi-008','Marca Continente Bio',1.99),('pv-cm-bi-008-2','cm-bi-008','Fairtrade Bio',2.69),('pv-cm-bi-008-3','cm-bi-008','Organic Fair',3.48),
('pv-cm-bi-009-1','cm-bi-009','Marca Continente Bio',2.99),('pv-cm-bi-009-2','cm-bi-009','Celeiro Bio',4.04),('pv-cm-bi-009-3','cm-bi-009','Organic Girl',5.23),
('pv-cm-bi-010-1','cm-bi-010','Marca Continente Bio',4.99),('pv-cm-bi-010-2','cm-bi-010','Mel da Serra Bio',6.74),('pv-cm-bi-010-3','cm-bi-010','Manuka Health',8.73),

-- GOURMET variants
('pv-cm-gm-001-1','cm-gm-001','Marca Continente',9.99),('pv-cm-gm-001-2','cm-gm-001','El Corte Inglés',13.49),('pv-cm-gm-001-3','cm-gm-001','Joselito Bellota',17.48),
('pv-cm-gm-002-1','cm-gm-002','Marca Continente',4.99),('pv-cm-gm-002-2','cm-gm-002','Zanetti',6.74),('pv-cm-gm-002-3','cm-gm-002','Parmigiano DOP',8.73),
('pv-cm-gm-003-1','cm-gm-003','Marca Continente',7.99),('pv-cm-gm-003-2','cm-gm-003','Labeyrie',10.79),('pv-cm-gm-003-3','cm-gm-003','Acme Smoked Fish',13.98),
('pv-cm-gm-004-1','cm-gm-004','Marca Continente',14.99),('pv-cm-gm-004-2','cm-gm-004','Labeyrie',20.24),('pv-cm-gm-004-3','cm-gm-004','Rougie Premium',26.23),
('pv-cm-gm-005-1','cm-gm-005','Marca Continente',19.99),('pv-cm-gm-005-2','cm-gm-005','Moët Chandon',26.99),('pv-cm-gm-005-3','cm-gm-005','Veuve Clicquot',34.98),
('pv-cm-gm-006-1','cm-gm-006','Marca Continente',39.99),('pv-cm-gm-006-2','cm-gm-006','Petrossian',53.99),('pv-cm-gm-006-3','cm-gm-006','Beluga Royal',69.98),
('pv-cm-gm-007-1','cm-gm-007','Marca Continente',3.99),('pv-cm-gm-007-2','cm-gm-007','Fragata',5.39),('pv-cm-gm-007-3','cm-gm-007','Castillo de Canena',6.98),
('pv-cm-gm-008-1','cm-gm-008','Marca Continente',8.99),('pv-cm-gm-008-2','cm-gm-008','Esporão DOP',12.14),('pv-cm-gm-008-3','cm-gm-008','Quinta do Crasto',15.73),
('pv-cm-gm-009-1','cm-gm-009','Marca Continente',2.99),('pv-cm-gm-009-2','cm-gm-009','Valor 85%',4.04),('pv-cm-gm-009-3','cm-gm-009','Lindt 90%',5.23),
('pv-cm-gm-010-1','cm-gm-010','Marca Continente',4.99),('pv-cm-gm-010-2','cm-gm-010','Leonidas',6.74),('pv-cm-gm-010-3','cm-gm-010','Godiva Premium',8.73)

ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- RESUMO
-- Produtos inseridos : 190
-- Variantes inseridas: 570
-- Categorias cobertas: 18
-- restaurant_id      : continente-guarda
-- Status             : base finalizada
-- ============================================================
