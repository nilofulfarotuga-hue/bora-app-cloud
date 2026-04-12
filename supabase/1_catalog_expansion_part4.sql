-- ============================================================
-- BORA APP — EXPANSÃO CATÁLOGO PARTE 4/4
-- Papel · Congelados · Charcutaria · Iogurtes · Gelados
-- Refeições Prontas · Bebé · Animais · Frutos Secos · Temperos
-- + ETAPA 5: Preços · ETAPA 8: Imagens
-- ============================================================

INSERT INTO public.products
  (id, restaurant_id, name, description, price, photo_url, is_available, category, is_popular, is_on_sale, discount_price)
VALUES

-- ── PAPEL E DESCARTÁVEIS ─────────────────────────────────────
('pp-001','continente-guarda','Renova Papel Higiénico 12 rolos','Papel higiénico 3 folhas 12 rolos',3.99,'https://source.unsplash.com/400x400/?toilet,paper,rolls',true,'Papel e Descartáveis',true,false,null),
('pp-002','continente-guarda','Renova Papel Higiénico 24 rolos','Papel higiénico 3 folhas 24 rolos',6.99,'https://source.unsplash.com/400x400/?toilet,paper,pack',true,'Papel e Descartáveis',true,false,null),
('pp-003','continente-guarda','Continente Papel Higiénico 12 rolos','Papel higiénico marca própria 12 rolos',2.49,'https://source.unsplash.com/400x400/?toilet,paper,white',true,'Papel e Descartáveis',true,false,null),
('pp-004','continente-guarda','Continente Papel Higiénico 6 rolos','Papel higiénico 3 folhas 6 rolos',1.49,'https://source.unsplash.com/400x400/?tissue,paper,soft',true,'Papel e Descartáveis',false,false,null),
('pp-005','continente-guarda','Scottex Papel de Cozinha 4 rolos','Papel absorvente cozinha 4 rolos',3.49,'https://source.unsplash.com/400x400/?kitchen,paper,towel',true,'Papel e Descartáveis',true,false,null),
('pp-006','continente-guarda','Continente Papel Cozinha 2 rolos','Papel cozinha absorvente 2 rolos',1.29,'https://source.unsplash.com/400x400/?paper,towel,kitchen',true,'Papel e Descartáveis',false,false,null),
('pp-007','continente-guarda','Scottex Guardanapos 40un','Guardanapos brancos 40 un',1.29,'https://source.unsplash.com/400x400/?napkins,white,paper',true,'Papel e Descartáveis',false,false,null),
('pp-008','continente-guarda','Guardanapos Festivos 20un','Guardanapos coloridos 20 un',1.49,'https://source.unsplash.com/400x400/?colored,napkins,party',true,'Papel e Descartáveis',false,false,null),
('pp-009','continente-guarda','Pratos Descartáveis 25un','Pratos papel descartáveis 25 un',1.99,'https://source.unsplash.com/400x400/?paper,plates,disposable',true,'Papel e Descartáveis',false,false,null),
('pp-010','continente-guarda','Copos Descartáveis 50un','Copos plástico descartáveis 50 un',1.49,'https://source.unsplash.com/400x400/?plastic,cups,disposable',true,'Papel e Descartáveis',false,false,null),
('pp-011','continente-guarda','Talheres Descartáveis Set','Set talheres biodegradáveis 30 un',2.49,'https://source.unsplash.com/400x400/?plastic,cutlery,eco',true,'Papel e Descartáveis',false,false,null),
('pp-012','continente-guarda','Film de Cozinha 20m','Película aderente cozinha 20m',1.49,'https://source.unsplash.com/400x400/?cling,film,wrap',true,'Papel e Descartáveis',false,false,null),
('pp-013','continente-guarda','Papel de Alumínio 25m','Folha de alumínio 25m',2.99,'https://source.unsplash.com/400x400/?aluminum,foil,kitchen',true,'Papel e Descartáveis',false,false,null),
('pp-014','continente-guarda','Sacos Congelação Ziploc 25un','Sacos freezer com fecho 25 un',2.49,'https://source.unsplash.com/400x400/?ziploc,freezer,bag',true,'Papel e Descartáveis',false,false,null),
('pp-015','continente-guarda','Kleenex Lenços Caixa 80un','Lenços faciais caixa 80 un',1.99,'https://source.unsplash.com/400x400/?tissue,kleenex,box',true,'Papel e Descartáveis',true,false,null),

-- ── CONGELADOS ───────────────────────────────────────────────
('fg-001','continente-guarda','Batata Frita McCain Clássica 1kg','Batatas fritas clássicas congeladas 1kg',3.49,'https://source.unsplash.com/400x400/?frozen,fries,potato',true,'Congelados',true,false,null),
('fg-002','continente-guarda','Batata Frita McCain Ondulada 1kg','Batatas onduladas congeladas 1kg',3.49,'https://source.unsplash.com/400x400/?waffle,fries,frozen',true,'Congelados',true,false,null),
('fg-003','continente-guarda','Batata Frita Palito Continente 1kg','Batatas fritas marca própria 1kg',2.49,'https://source.unsplash.com/400x400/?french,fries,frozen,bag',true,'Congelados',false,false,null),
('fg-004','continente-guarda','Pizza Margherita Dr. Oetker 320g','Pizza margherita congelada 320g',3.99,'https://source.unsplash.com/400x400/?frozen,pizza,margherita',true,'Congelados',true,false,null),
('fg-005','continente-guarda','Pizza Pepperoni Dr. Oetker 320g','Pizza pepperoni congelada 320g',3.99,'https://source.unsplash.com/400x400/?frozen,pizza,pepperoni',true,'Congelados',true,false,null),
('fg-006','continente-guarda','Pizza Ristorante Vegetais 330g','Pizza vegetais congelada 330g',4.49,'https://source.unsplash.com/400x400/?frozen,pizza,vegetable',true,'Congelados',false,false,null),
('fg-007','continente-guarda','Pizza Ristorante 4 Queijos 320g','Pizza 4 queijos congelada 320g',4.49,'https://source.unsplash.com/400x400/?four,cheese,pizza,frozen',true,'Congelados',false,false,null),
('fg-008','continente-guarda','Ervilhas Congeladas 1kg','Ervilhas verdes congeladas 1kg',1.79,'https://source.unsplash.com/400x400/?frozen,peas,green',true,'Congelados',true,false,null),
('fg-009','continente-guarda','Milho Doce Congelado 1kg','Grãos de milho congelados 1kg',1.79,'https://source.unsplash.com/400x400/?frozen,corn,sweet',true,'Congelados',false,false,null),
('fg-010','continente-guarda','Mix Vegetais Congelados 1kg','Mistura legumes congelados 1kg',2.29,'https://source.unsplash.com/400x400/?frozen,vegetables,mix',true,'Congelados',true,false,null),
('fg-011','continente-guarda','Espinafres Congelados 1kg','Espinafres folha congelados 1kg',1.99,'https://source.unsplash.com/400x400/?frozen,spinach,bag',true,'Congelados',false,false,null),
('fg-012','continente-guarda','Brócolos Congelados 1kg','Brócolos congelados 1kg',2.29,'https://source.unsplash.com/400x400/?frozen,broccoli,bag',true,'Congelados',false,false,null),
('fg-013','continente-guarda','Camarão Tigre Congelado 500g','Camarão tigre descascado congelado',8.99,'https://source.unsplash.com/400x400/?frozen,shrimp,tiger',true,'Congelados',true,false,null),
('fg-014','continente-guarda','Camarão Inteiro Congelado 1kg','Camarão inteiro congelado 1kg',12.99,'https://source.unsplash.com/400x400/?frozen,prawn,whole',true,'Congelados',false,false,null),
('fg-015','continente-guarda','Filetes de Peixe Congelado 500g','Filetes peixe branco congelados',5.49,'https://source.unsplash.com/400x400/?frozen,fish,fillet',true,'Congelados',false,false,null),
('fg-016','continente-guarda','Salmão Congelado 500g','Lombo salmão atlântico congelado',9.99,'https://source.unsplash.com/400x400/?frozen,salmon,fillet',true,'Congelados',true,false,null),
('fg-017','continente-guarda','Lulas Congeladas 500g','Lulas limpas congeladas 500g',5.99,'https://source.unsplash.com/400x400/?frozen,squid,clean',true,'Congelados',false,false,null),
('fg-018','continente-guarda','Frango Coxas Congeladas 1kg','Coxas de frango congeladas 1kg',4.49,'https://source.unsplash.com/400x400/?frozen,chicken,thighs',true,'Congelados',true,false,null),
('fg-019','continente-guarda','Hamburguer Bovino 4x125g','Hamburguer de carne bovino',3.99,'https://source.unsplash.com/400x400/?beef,burger,frozen',true,'Congelados',true,false,null),
('fg-020','continente-guarda','Nuggets Frango 450g','Nuggets de frango congelados 450g',3.99,'https://source.unsplash.com/400x400/?chicken,nuggets,frozen',true,'Congelados',true,false,null),
('fg-021','continente-guarda','Fish Sticks 450g','Palitos de peixe congelados 450g',3.49,'https://source.unsplash.com/400x400/?fish,sticks,frozen',true,'Congelados',false,false,null),
('fg-022','continente-guarda','Lasanha Bolonhesa Findus 400g','Lasanha congelada bolonhesa 400g',4.99,'https://source.unsplash.com/400x400/?lasagna,frozen,bolognese',true,'Congelados',true,false,null),
('fg-023','continente-guarda','Lasanha Vegetal 400g','Lasanha congelada vegetais 400g',4.49,'https://source.unsplash.com/400x400/?vegetable,lasagna,frozen',true,'Congelados',false,false,null),
('fg-024','continente-guarda','Frutos Vermelhos Congelados 500g','Mix frutos vermelhos congelados',3.99,'https://source.unsplash.com/400x400/?frozen,berries,mixed',true,'Congelados',false,false,null),
('fg-025','continente-guarda','Manga Cubos Congelados 500g','Manga aos cubos congelada 500g',3.49,'https://source.unsplash.com/400x400/?frozen,mango,chunks',true,'Congelados',false,false,null),

-- ── CHARCUTARIA ──────────────────────────────────────────────
('ct-001','continente-guarda','Fiambre da Perna Extra 200g','Fiambre de porco fatiado 200g',2.29,'https://source.unsplash.com/400x400/?ham,sliced,deli',true,'Charcutaria',true,false,null),
('ct-002','continente-guarda','Fiambre Light 200g','Fiambre light fatiado 200g',2.49,'https://source.unsplash.com/400x400/?light,ham,low,fat',true,'Charcutaria',false,false,null),
('ct-003','continente-guarda','Fiambre Peito Peru 200g','Fiambre peito de peru fatiado',2.49,'https://source.unsplash.com/400x400/?turkey,ham,sliced',true,'Charcutaria',false,false,null),
('ct-004','continente-guarda','Mortadela Bologna 200g','Mortadela italiana fatiada 200g',1.99,'https://source.unsplash.com/400x400/?mortadella,italian,deli',true,'Charcutaria',true,false,null),
('ct-005','continente-guarda','Salami Milano 100g','Salami italiano fatiado 100g',2.99,'https://source.unsplash.com/400x400/?salami,milano,sliced',true,'Charcutaria',true,false,null),
('ct-006','continente-guarda','Presunto Serrano 100g','Presunto espanhol fatiado 100g',2.99,'https://source.unsplash.com/400x400/?serrano,ham,sliced',true,'Charcutaria',true,false,null),
('ct-007','continente-guarda','Prosciutto Crudo 80g','Presunto italiano cru 80g',3.49,'https://source.unsplash.com/400x400/?prosciutto,italian,cured',true,'Charcutaria',false,false,null),
('ct-008','continente-guarda','Chouriço de Carne 200g','Chouriço português fatiado 200g',3.49,'https://source.unsplash.com/400x400/?chorizo,portuguese,sliced',true,'Charcutaria',true,false,null),
('ct-009','continente-guarda','Paio 200g','Paio de porco português 200g',3.49,'https://source.unsplash.com/400x400/?paio,portuguese,cured,meat',true,'Charcutaria',false,false,null),
('ct-010','continente-guarda','Salpicão 200g','Salpicão de porco trás-os-montes',3.99,'https://source.unsplash.com/400x400/?salpicao,cured,portuguese',true,'Charcutaria',false,false,null),
('ct-011','continente-guarda','Pepperoni 80g','Pepperoni americano fatiado 80g',2.49,'https://source.unsplash.com/400x400/?pepperoni,sliced,pizza',true,'Charcutaria',false,false,null),
('ct-012','continente-guarda','Bacon Fumado Fatiado 200g','Bacon fumado fatiado 200g',3.49,'https://source.unsplash.com/400x400/?bacon,smoked,sliced',true,'Charcutaria',true,false,null),
('ct-013','continente-guarda','Linguiça 200g','Linguiça portuguesa 200g',2.99,'https://source.unsplash.com/400x400/?linguica,portuguese,sausage',true,'Charcutaria',false,false,null),
('ct-014','continente-guarda','Paté de Fígado 200g','Paté de fígado suave 200g',1.99,'https://source.unsplash.com/400x400/?liver,pate,jar',true,'Charcutaria',true,false,null),
('ct-015','continente-guarda','Paté de Pato 100g','Paté de pato premium 100g',3.49,'https://source.unsplash.com/400x400/?duck,pate,gourmet',true,'Charcutaria',false,false,null),

-- ── IOGURTES E SOBREMESAS ────────────────────────────────────
('yg-001','continente-guarda','Activia Natural 4x125g','Iogurte Activia natural 4 un',2.29,'https://source.unsplash.com/400x400/?activia,yogurt,natural',true,'Iogurtes',true,false,null),
('yg-002','continente-guarda','Activia Morango 4x125g','Iogurte Activia morango 4 un',2.49,'https://source.unsplash.com/400x400/?activia,strawberry,yogurt',true,'Iogurtes',true,false,null),
('yg-003','continente-guarda','Activia Pêssego 4x125g','Iogurte Activia pêssego 4 un',2.49,'https://source.unsplash.com/400x400/?activia,peach,yogurt',true,'Iogurtes',false,false,null),
('yg-004','continente-guarda','Danone Morango 4x125g','Iogurte Danone morango 4 un',2.29,'https://source.unsplash.com/400x400/?danone,strawberry',true,'Iogurtes',true,false,null),
('yg-005','continente-guarda','Danone Framboesa 4x125g','Iogurte Danone framboesa 4 un',2.29,'https://source.unsplash.com/400x400/?danone,raspberry,yogurt',true,'Iogurtes',false,false,null),
('yg-006','continente-guarda','Nestlé Iogurte Cremoso Baunilha 4x125g','Iogurte cremoso baunilha 4 un',2.29,'https://source.unsplash.com/400x400/?vanilla,creamy,yogurt',true,'Iogurtes',false,false,null),
('yg-007','continente-guarda','Iogurte Skyr Natural 150g','Iogurte islandês proteico natural 150g',1.49,'https://source.unsplash.com/400x400/?skyr,icelandic,yogurt',true,'Iogurtes',false,false,null),
('yg-008','continente-guarda','Iogurte Skyr Morango 150g','Iogurte proteico morango 150g',1.49,'https://source.unsplash.com/400x400/?skyr,strawberry,high,protein',true,'Iogurtes',false,false,null),
('yg-009','continente-guarda','Iogurte Grego Mel e Nozes 150g','Iogurte grego mel e nozes 150g',1.79,'https://source.unsplash.com/400x400/?greek,yogurt,honey,nuts',true,'Iogurtes',false,false,null),
('yg-010','continente-guarda','Iogurte Grego Framboesa 150g','Iogurte grego framboesa 150g',1.49,'https://source.unsplash.com/400x400/?greek,raspberry,yogurt',true,'Iogurtes',false,false,null),
('yg-011','continente-guarda','Müller Canto Cereal 150g','Iogurte com canto de cereais 150g',0.89,'https://source.unsplash.com/400x400/?muller,corner,yogurt,cereal',true,'Iogurtes',false,false,null),
('yg-012','continente-guarda','Müller Canto Avo 150g','Iogurte com canto de avelã 150g',0.89,'https://source.unsplash.com/400x400/?muller,corner,hazelnut',true,'Iogurtes',false,false,null),
('yg-013','continente-guarda','Arroz Doce Mimosa 200g','Arroz doce clássico 200g',0.79,'https://source.unsplash.com/400x400/?rice,pudding,creamy',true,'Iogurtes',true,false,null),
('yg-014','continente-guarda','Mousse de Chocolate 4x60g','Mousse chocolate 4 un',2.49,'https://source.unsplash.com/400x400/?chocolate,mousse,dessert',true,'Iogurtes',true,false,null),
('yg-015','continente-guarda','Pudim Flan Continente 4x125g','Pudim flan clássico 4 un',1.99,'https://source.unsplash.com/400x400/?flan,caramel,pudding',true,'Iogurtes',false,false,null),

-- ── GELADOS ──────────────────────────────────────────────────
('gl-001','continente-guarda','Magnum Classic 3un','Gelado baunilha chocolate 3 un',4.99,'https://source.unsplash.com/400x400/?magnum,ice,cream,bar',true,'Gelados',true,false,null),
('gl-002','continente-guarda','Magnum Almond 3un','Gelado baunilha amêndoa chocolate 3 un',4.99,'https://source.unsplash.com/400x400/?magnum,almond,icecream',true,'Gelados',true,false,null),
('gl-003','continente-guarda','Magnum White 3un','Gelado baunilha chocolate branco 3 un',4.99,'https://source.unsplash.com/400x400/?magnum,white,chocolate',true,'Gelados',false,false,null),
('gl-004','continente-guarda','Cornetto Classic 4un','Casquinha baunilha chocolate 4 un',4.49,'https://source.unsplash.com/400x400/?cornetto,cone,ice,cream',true,'Gelados',true,false,null),
('gl-005','continente-guarda','Cornetto Morango 4un','Casquinha morango 4 un',4.49,'https://source.unsplash.com/400x400/?cornetto,strawberry,cone',true,'Gelados',false,false,null),
('gl-006','continente-guarda','Solero Maracujá 4un','Gelado maracujá 4 un',4.49,'https://source.unsplash.com/400x400/?solero,passion,fruit',true,'Gelados',false,false,null),
('gl-007','continente-guarda','Ben & Jerry''s Cookie Dough 458ml','Gelado massa biscoito 458ml',6.99,'https://source.unsplash.com/400x400/?ben,jerry,cookie,dough',true,'Gelados',true,false,null),
('gl-008','continente-guarda','Ben & Jerry''s Brownie 458ml','Gelado brownie chocolate 458ml',6.99,'https://source.unsplash.com/400x400/?ben,jerry,chocolate,brownie',true,'Gelados',false,false,null),
('gl-009','continente-guarda','Häagen-Dazs Baunilha 460ml','Gelado baunilha premium 460ml',6.49,'https://source.unsplash.com/400x400/?haagen,dazs,vanilla,icecream',true,'Gelados',false,false,null),
('gl-010','continente-guarda','Häagen-Dazs Morango 460ml','Gelado morango premium 460ml',6.49,'https://source.unsplash.com/400x400/?haagen,dazs,strawberry',true,'Gelados',false,false,null),
('gl-011','continente-guarda','Olá Tareco 1L','Gelado familiar napolitana 1L',3.99,'https://source.unsplash.com/400x400/?family,ice,cream,tub',true,'Gelados',true,false,null),
('gl-012','continente-guarda','Olá Baunilha 1L','Gelado baunilha familiar 1L',3.49,'https://source.unsplash.com/400x400/?vanilla,ice,cream,large',true,'Gelados',true,false,null),
('gl-013','continente-guarda','Continente Gelado Nata 1L','Gelado nata marca própria 1L',2.49,'https://source.unsplash.com/400x400/?cream,ice,cream,economy',true,'Gelados',false,false,null),
('gl-014','continente-guarda','Popsicle Morango 4un','Gelado pau morango 4 un',2.99,'https://source.unsplash.com/400x400/?popsicle,strawberry,pop',true,'Gelados',false,false,null),
('gl-015','continente-guarda','Twister Ananás 4un','Gelado twister ananás 4 un',3.49,'https://source.unsplash.com/400x400/?twister,pineapple,ice,pop',true,'Gelados',false,false,null),

-- ── REFEIÇÕES PRONTAS ────────────────────────────────────────
('rp-001','continente-guarda','Bolonhesa Findus Congelada 400g','Massa bolonhesa congelada 400g',3.99,'https://source.unsplash.com/400x400/?spaghetti,bolognese,ready',true,'Refeições Prontas',true,false,null),
('rp-002','continente-guarda','Arroz de Frango Continente 350g','Arroz com frango pronto 350g',3.49,'https://source.unsplash.com/400x400/?chicken,rice,ready,meal',true,'Refeições Prontas',true,false,null),
('rp-003','continente-guarda','Bacalhau com Natas 350g','Bacalhau gratinado com natas 350g',4.99,'https://source.unsplash.com/400x400/?codfish,cream,gratin',true,'Refeições Prontas',true,false,null),
('rp-004','continente-guarda','Caldo Verde Sopas da Avó 750ml','Caldo verde português 750ml',2.99,'https://source.unsplash.com/400x400/?caldo,verde,soup',true,'Refeições Prontas',true,false,null),
('rp-005','continente-guarda','Sopa de Legumes 750ml','Sopa legumes pronta 750ml',2.49,'https://source.unsplash.com/400x400/?vegetable,soup,fresh',true,'Refeições Prontas',false,false,null),
('rp-006','continente-guarda','Sopa de Tomate 750ml','Sopa tomate e manjericão 750ml',2.79,'https://source.unsplash.com/400x400/?tomato,soup,basil',true,'Refeições Prontas',false,false,null),
('rp-007','continente-guarda','Maggi Sopa Instantânea Galinha 3 saquetas','Sopa instantânea galinha 3 saquetas',1.29,'https://source.unsplash.com/400x400/?instant,soup,noodle',true,'Refeições Prontas',false,false,null),
('rp-008','continente-guarda','Ramen Instantâneo Nissin 85g','Ramen instantâneo japonês 85g',0.89,'https://source.unsplash.com/400x400/?ramen,instant,noodle',true,'Refeições Prontas',false,false,null),
('rp-009','continente-guarda','Wrap Frango 200g','Wrap de frango grelhado 200g',3.99,'https://source.unsplash.com/400x400/?wrap,chicken,grilled',true,'Refeições Prontas',false,false,null),
('rp-010','continente-guarda','Hamburguer Pronto 250g','Hamburguer pronto a aquecer 250g',3.99,'https://source.unsplash.com/400x400/?burger,ready,meal',true,'Refeições Prontas',false,false,null),
('rp-011','continente-guarda','Arroz Basmati em Saco 2 min 250g','Arroz basmati micro-ondas 250g',1.99,'https://source.unsplash.com/400x400/?basmati,rice,microwave',true,'Refeições Prontas',true,false,null),
('rp-012','continente-guarda','Arroz Integral em Saco 2 min 250g','Arroz integral micro-ondas 250g',1.99,'https://source.unsplash.com/400x400/?brown,rice,microwave,pack',true,'Refeições Prontas',false,false,null),
('rp-013','continente-guarda','Quinoa Cozida em Saco 250g','Quinoa pronta micro-ondas 250g',2.49,'https://source.unsplash.com/400x400/?quinoa,cooked,microwave',true,'Refeições Prontas',false,false,null),

-- ── BEBÉ E CRIANÇA ───────────────────────────────────────────
('bb-001','continente-guarda','Pampers Baby Dry T3 46un','Fraldas bebé T3 46 un',11.99,'https://source.unsplash.com/400x400/?diapers,baby,pampers',true,'Bebé e Criança',true,false,null),
('bb-002','continente-guarda','Pampers Baby Dry T4 44un','Fraldas bebé T4 44 un',12.49,'https://source.unsplash.com/400x400/?baby,diapers,size4',true,'Bebé e Criança',true,false,null),
('bb-003','continente-guarda','Pampers Baby Dry T5 41un','Fraldas bebé T5 41 un',12.99,'https://source.unsplash.com/400x400/?diapers,size,baby',true,'Bebé e Criança',false,false,null),
('bb-004','continente-guarda','Huggies Ultra Comfort T3 56un','Fraldas Huggies T3 56 un',12.99,'https://source.unsplash.com/400x400/?huggies,diapers,comfort',true,'Bebé e Criança',false,false,null),
('bb-005','continente-guarda','Dodot Pensos Recém-Nascido T1 28un','Fraldas recém-nascido T1 28 un',7.99,'https://source.unsplash.com/400x400/?newborn,diapers,size1',true,'Bebé e Criança',false,false,null),
('bb-006','continente-guarda','Pampers Lenços Húmidos 64un','Lenços húmidos bebé 64 un',2.99,'https://source.unsplash.com/400x400/?baby,wipes,pampers',true,'Bebé e Criança',true,false,null),
('bb-007','continente-guarda','Nestlé NAN1 800g','Leite fórmula 1ª infância 800g',13.99,'https://source.unsplash.com/400x400/?baby,formula,milk',true,'Bebé e Criança',true,false,null),
('bb-008','continente-guarda','Nestlé NAN2 800g','Leite fórmula 2ª infância 800g',13.99,'https://source.unsplash.com/400x400/?formula,infant,milk',true,'Bebé e Criança',false,false,null),
('bb-009','continente-guarda','Aptamil 1 800g','Leite fórmula bebé 0-6 meses',14.99,'https://source.unsplash.com/400x400/?aptamil,infant,formula',true,'Bebé e Criança',false,false,null),
('bb-010','continente-guarda','Gerber Papinha Maçã 130g','Papa maçã bebé Gerber 130g',1.29,'https://source.unsplash.com/400x400/?baby,food,apple,puree',true,'Bebé e Criança',true,false,null),
('bb-011','continente-guarda','Gerber Papinha Legumes 130g','Papa legumes bebé Gerber 130g',1.29,'https://source.unsplash.com/400x400/?baby,food,vegetables,puree',true,'Bebé e Criança',false,false,null),
('bb-012','continente-guarda','Nestlé Cerelac Arroz 400g','Cereal arroz bebé 400g',4.99,'https://source.unsplash.com/400x400/?cerelac,baby,cereal,rice',true,'Bebé e Criança',false,false,null),
('bb-013','continente-guarda','Sumo Hero 100% Frutas Bebé 6x200ml','Sumo bebé 100% frutas 6x200ml',4.49,'https://source.unsplash.com/400x400/?baby,juice,fruit',true,'Bebé e Criança',false,false,null),
('bb-014','continente-guarda','Johnson''s Shampoo Bebé 500ml','Shampoo delicado bebé 500ml',4.99,'https://source.unsplash.com/400x400/?baby,shampoo,gentle',true,'Bebé e Criança',true,false,null),
('bb-015','continente-guarda','Johnson''s Creme Bebé 200ml','Creme hidratante bebé 200ml',3.99,'https://source.unsplash.com/400x400/?baby,cream,moisturizer',true,'Bebé e Criança',false,false,null),

-- ── ANIMAIS DE ESTIMAÇÃO ─────────────────────────────────────
('pt-001','continente-guarda','Whiskas Adulto Frango 400g','Ração húmida gato frango 400g',1.49,'https://source.unsplash.com/400x400/?cat,food,wet',true,'Animais de Estimação',true,false,null),
('pt-002','continente-guarda','Whiskas Adulto Atum 400g','Ração húmida gato atum 400g',1.49,'https://source.unsplash.com/400x400/?cat,food,tuna',true,'Animais de Estimação',true,false,null),
('pt-003','continente-guarda','Whiskas Seco Adulto 1.4kg','Ração seca gato adulto 1.4kg',5.49,'https://source.unsplash.com/400x400/?dry,cat,food',true,'Animais de Estimação',true,false,null),
('pt-004','continente-guarda','Felix Sachê Atum 100g','Ração húmida gato Felix atum',0.59,'https://source.unsplash.com/400x400/?felix,cat,food,sachet',true,'Animais de Estimação',false,false,null),
('pt-005','continente-guarda','Felix Sachê Salmão 100g','Ração húmida gato Felix salmão',0.59,'https://source.unsplash.com/400x400/?felix,salmon,cat',true,'Animais de Estimação',false,false,null),
('pt-006','continente-guarda','Purina One Gato Adulto Salmão 1.5kg','Ração seca gato salmão 1.5kg',8.99,'https://source.unsplash.com/400x400/?purina,one,cat,salmon',true,'Animais de Estimação',false,false,null),
('pt-007','continente-guarda','Pedigree Adult Frango 400g','Ração húmida cão frango 400g',1.29,'https://source.unsplash.com/400x400/?pedigree,dog,food,wet',true,'Animais de Estimação',true,false,null),
('pt-008','continente-guarda','Pedigree Seco Mini Adult 1.5kg','Ração seca cão mini adulto 1.5kg',5.99,'https://source.unsplash.com/400x400/?dog,food,dry,small',true,'Animais de Estimação',true,false,null),
('pt-009','continente-guarda','Pedigree Seco Adult 3kg','Ração seca cão adulto 3kg',8.99,'https://source.unsplash.com/400x400/?pedigree,dog,dry,food',true,'Animais de Estimação',false,false,null),
('pt-010','continente-guarda','Royal Canin Mini Adult 2kg','Ração cão raça mini adulto 2kg',14.99,'https://source.unsplash.com/400x400/?royal,canin,small,dog',true,'Animais de Estimação',false,false,null),
('pt-011','continente-guarda','Purina Pro Plan Cão Salmão 3kg','Ração premium cão salmão 3kg',19.99,'https://source.unsplash.com/400x400/?purina,proplan,dog,salmon',true,'Animais de Estimação',false,false,null),
('pt-012','continente-guarda','Areia para Gatos Sanitária 5L','Areia aglomerante gatos 5L',3.49,'https://source.unsplash.com/400x400/?cat,litter,sand',true,'Animais de Estimação',true,false,null),
('pt-013','continente-guarda','Areia para Gatos Extra 10L','Areia perfumada gatos 10L',5.99,'https://source.unsplash.com/400x400/?cat,litter,clumping',true,'Animais de Estimação',false,false,null),
('pt-014','continente-guarda','Osso Mastigável Cão L','Osso mastigável para cão 1 un',1.99,'https://source.unsplash.com/400x400/?dog,bone,chew',true,'Animais de Estimação',false,false,null),
('pt-015','continente-guarda','Petisco Pedigree Dentastix 7un','Palitos dentais cão médio 7 un',2.99,'https://source.unsplash.com/400x400/?dentastix,dog,dental',true,'Animais de Estimação',true,false,null),

-- ── FRUTOS SECOS ─────────────────────────────────────────────
('fs-001','continente-guarda','Nozes Miolo 200g','Miolo de noz natural 200g',3.99,'https://source.unsplash.com/400x400/?walnuts,natural,shelled',true,'Frutos Secos',false,false,null),
('fs-002','continente-guarda','Amêndoa Natural 200g','Amêndoa crua sem sal 200g',4.49,'https://source.unsplash.com/400x400/?almonds,raw,natural',true,'Frutos Secos',true,false,null),
('fs-003','continente-guarda','Amêndoa Torrada Salgada 200g','Amêndoa torrada com sal 200g',4.49,'https://source.unsplash.com/400x400/?almonds,salted,roasted',true,'Frutos Secos',true,false,null),
('fs-004','continente-guarda','Castanha do Caju 200g','Castanha caju torrada 200g',5.99,'https://source.unsplash.com/400x400/?cashews,roasted,nuts',true,'Frutos Secos',true,false,null),
('fs-005','continente-guarda','Avelãs Torradas 200g','Avelãs torradas sem casca 200g',3.99,'https://source.unsplash.com/400x400/?hazelnuts,roasted',true,'Frutos Secos',false,false,null),
('fs-006','continente-guarda','Pinhões 100g','Pinhão português 100g',4.99,'https://source.unsplash.com/400x400/?pine,nuts,small',true,'Frutos Secos',false,false,null),
('fs-007','continente-guarda','Pistácios 150g','Pistácios torrados com casca 150g',4.49,'https://source.unsplash.com/400x400/?pistachios,bag,green',true,'Frutos Secos',false,false,null),
('fs-008','continente-guarda','Mix Trail Frutos Secos 200g','Mix frutos secos e bagas 200g',4.99,'https://source.unsplash.com/400x400/?trail,mix,nuts,dried,fruit',true,'Frutos Secos',false,false,null),
('fs-009','continente-guarda','Passas de Uva 200g','Passas de uva sultana 200g',1.99,'https://source.unsplash.com/400x400/?raisins,sultana,dried',true,'Frutos Secos',false,false,null),
('fs-010','continente-guarda','Tâmaras 200g','Tâmaras medjool naturais 200g',3.49,'https://source.unsplash.com/400x400/?dates,medjool,dried',true,'Frutos Secos',false,false,null),
('fs-011','continente-guarda','Sementes de Chia 200g','Sementes chia naturais 200g',3.99,'https://source.unsplash.com/400x400/?chia,seeds,superfood',true,'Frutos Secos',false,false,null),
('fs-012','continente-guarda','Sementes de Abóbora 200g','Sementes abóbora torradas 200g',2.99,'https://source.unsplash.com/400x400/?pumpkin,seeds,green',true,'Frutos Secos',false,false,null),
('fs-013','continente-guarda','Sementes de Linhaça 250g','Linhaça dourada 250g',1.99,'https://source.unsplash.com/400x400/?flaxseed,golden,seeds',true,'Frutos Secos',false,false,null),
('fs-014','continente-guarda','Cranberries Secas 100g','Cranberries desidratadas adoçadas',2.49,'https://source.unsplash.com/400x400/?cranberries,dried,red',true,'Frutos Secos',false,false,null),
('fs-015','continente-guarda','Coco Ralado 100g','Coco ralado desidratado 100g',1.29,'https://source.unsplash.com/400x400/?coconut,shredded,dried',true,'Frutos Secos',false,false,null),

-- ── TEMPEROS E ESPECIARIAS ───────────────────────────────────
('tp-001','continente-guarda','Pimenta Preta Moída 50g','Pimenta preta moída 50g',1.49,'https://source.unsplash.com/400x400/?black,pepper,ground',true,'Temperos e Especiarias',true,false,null),
('tp-002','continente-guarda','Pimenta em Grão 50g','Pimenta preta em grão 50g',1.49,'https://source.unsplash.com/400x400/?peppercorns,whole,black',true,'Temperos e Especiarias',false,false,null),
('tp-003','continente-guarda','Canela em Pó 35g','Canela moída ceylon 35g',1.29,'https://source.unsplash.com/400x400/?cinnamon,powder,spice',true,'Temperos e Especiarias',false,false,null),
('tp-004','continente-guarda','Canela em Pau 25g','Canela em pau 25g',1.49,'https://source.unsplash.com/400x400/?cinnamon,sticks,spice',true,'Temperos e Especiarias',false,false,null),
('tp-005','continente-guarda','Paprika Doce 40g','Paprika doce húngara 40g',1.29,'https://source.unsplash.com/400x400/?paprika,sweet,red,spice',true,'Temperos e Especiarias',false,false,null),
('tp-006','continente-guarda','Paprika Fumada 40g','Paprika fumada espanhola 40g',1.49,'https://source.unsplash.com/400x400/?smoked,paprika,spice',true,'Temperos e Especiarias',false,false,null),
('tp-007','continente-guarda','Curcuma em Pó 40g','Curcuma açafrão da índia 40g',1.49,'https://source.unsplash.com/400x400/?turmeric,powder,yellow',true,'Temperos e Especiarias',false,false,null),
('tp-008','continente-guarda','Cominhos em Pó 35g','Cominhos moídos 35g',1.29,'https://source.unsplash.com/400x400/?cumin,powder,spice',true,'Temperos e Especiarias',false,false,null),
('tp-009','continente-guarda','Orégãos Secos 15g','Orégãos secos mediterrâneos 15g',0.79,'https://source.unsplash.com/400x400/?oregano,dried,herbs',true,'Temperos e Especiarias',true,false,null),
('tp-010','continente-guarda','Manjericão Seco 15g','Manjericão seco 15g',0.79,'https://source.unsplash.com/400x400/?basil,dried,herb',true,'Temperos e Especiarias',false,false,null),
('tp-011','continente-guarda','Tomilho Seco 15g','Tomilho seco 15g',0.79,'https://source.unsplash.com/400x400/?thyme,dried,herb',true,'Temperos e Especiarias',false,false,null),
('tp-012','continente-guarda','Salsa Seca 15g','Salsa desidratada 15g',0.79,'https://source.unsplash.com/400x400/?parsley,dried,flakes',true,'Temperos e Especiarias',false,false,null),
('tp-013','continente-guarda','Alho em Pó 60g','Alho em pó 60g',1.29,'https://source.unsplash.com/400x400/?garlic,powder,spice',true,'Temperos e Especiarias',true,false,null),
('tp-014','continente-guarda','Cebola em Pó 60g','Cebola desidratada em pó 60g',1.29,'https://source.unsplash.com/400x400/?onion,powder,spice',true,'Temperos e Especiarias',false,false,null),
('tp-015','continente-guarda','Caril em Pó 40g','Caril suave em pó 40g',1.49,'https://source.unsplash.com/400x400/?curry,powder,indian',true,'Temperos e Especiarias',false,false,null),
('tp-016','continente-guarda','Açafrão Real 0.4g','Açafrão puro em fios 0.4g',3.49,'https://source.unsplash.com/400x400/?saffron,threads,real',true,'Temperos e Especiarias',false,false,null),
('tp-017','continente-guarda','Baunilha Extrato 50ml','Extrato de baunilha puro 50ml',2.99,'https://source.unsplash.com/400x400/?vanilla,extract,bottle',true,'Temperos e Especiarias',false,false,null),
('tp-018','continente-guarda','Fermento em Pó 16g','Fermento químico 16g',0.59,'https://source.unsplash.com/400x400/?baking,powder,yeast',true,'Temperos e Especiarias',false,false,null),
('tp-019','continente-guarda','Fermento de Padeiro 11g','Levedura de padeiro seca 11g',0.89,'https://source.unsplash.com/400x400/?yeast,bread,dried',true,'Temperos e Especiarias',false,false,null),
('tp-020','continente-guarda','Noz Moscada Moída 35g','Noz moscada moída 35g',1.29,'https://source.unsplash.com/400x400/?nutmeg,ground,spice',true,'Temperos e Especiarias',false,false,null),
('tp-021','continente-guarda','Piri-Piri Seco 20g','Piri-piri seco moído 20g',1.49,'https://source.unsplash.com/400x400/?piri,piri,dry,chili',true,'Temperos e Especiarias',false,false,null),
('tp-022','continente-guarda','Colorau Doce 100g','Colorau doce paprika 100g',0.89,'https://source.unsplash.com/400x400/?colorau,paprika,portuguese',true,'Temperos e Especiarias',true,false,null),
('tp-023','continente-guarda','Vinagre Balsâmico Creme 150ml','Creme de vinagre balsâmico 150ml',2.99,'https://source.unsplash.com/400x400/?balsamic,cream,glaze',true,'Temperos e Especiarias',false,false,null),
('tp-024','continente-guarda','Bicarbonato de Sódio 200g','Bicarbonato alimentar 200g',0.79,'https://source.unsplash.com/400x400/?baking,soda,sodium',true,'Temperos e Especiarias',false,false,null),
('tp-025','continente-guarda','Gelatina em Folhas 12g','Gelatina em folhas 12g',0.99,'https://source.unsplash.com/400x400/?gelatin,sheets,clear',true,'Temperos e Especiarias',false,false,null)

ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- ETAPA 5 — CORRIGIR PREÇOS ABSURDOS
-- ============================================================

-- Corrigir preços a zero ou null
UPDATE products
SET price = 1.99
WHERE (price IS NULL OR price = 0)
AND restaurant_id = 'continente-guarda';

-- Normalizar preços > 100 (provavelmente erro de entrada)
UPDATE products
SET price = price / 10
WHERE price > 100
AND restaurant_id = 'continente-guarda';

-- ============================================================
-- ETAPA 8 — GARANTIR 100% DAS IMAGENS
-- ============================================================

-- Preencher photo_url vazios com Unsplash baseado no nome
UPDATE products
SET photo_url = 'https://source.unsplash.com/400x400/?' ||
  REPLACE(REPLACE(LOWER(name), ' ', ','), '''', '')
WHERE (photo_url IS NULL OR photo_url = '')
AND restaurant_id = 'continente-guarda';

-- ============================================================
-- VALIDAÇÃO FINAL (copiar e executar separadamente)
-- ============================================================
-- SELECT COUNT(*) AS total FROM products;
-- SELECT COUNT(*) AS sem_imagem FROM products WHERE photo_url IS NULL OR photo_url = '';
-- SELECT COUNT(*) AS sem_preco FROM products WHERE price IS NULL OR price = 0;
-- SELECT COUNT(*) AS preco_absurdo FROM products WHERE price > 50 OR price < 0.10;
-- SELECT category, COUNT(*) AS total FROM products GROUP BY category ORDER BY total DESC;
