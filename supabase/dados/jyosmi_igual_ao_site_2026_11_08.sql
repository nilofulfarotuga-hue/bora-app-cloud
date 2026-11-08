-- Jyosmi Sushi: catálogo da app igual ao site da loja (https://strangeroasis.com/encomendas/), lido a 08/11/2026.
-- Preparado sem escrever na base (só SELECT). Quem aplica: a sessão principal, de uma vez.
-- Regras: só INSERT/UPDATE (o bloco 0 cria as cópias de segurança); nada se apaga; produto que sai fica indisponível.
-- Preço guardado = preço de BALCÃO do site; a app soma a margem de não-parceiro sozinha (PricingService.applyMarkup).
-- Pode correr duas vezes sem estragar nada (backups com IF NOT EXISTS, upserts por id, updates com valores fixos).
-- Proposta e tabela produto a produto: docs/propostas/jyosmi-sushi-igual-ao-site-2026-11-08.md

begin;

-- 0) Cópias de segurança (a primeira corrida guarda o estado de antes; as seguintes não mexem)
create table if not exists public.bkp_jyosmi_products_20261108 as
  select now() as guardado_em, p.*
    from public.products p
   where p.restaurant_id = 'jyosmi-sushi-guarda';
alter table public.bkp_jyosmi_products_20261108 enable row level security;

create table if not exists public.bkp_jyosmi_opcoes_20261108 as
  select now() as guardado_em,
         g.id as group_id, g.product_id, g.name as group_name, g.description as group_description,
         g.is_required, g.min_choices, g.max_choices, g.sort_order as group_sort,
         i.id as item_id, i.group_id as item_group_id, i.name as item_name, i.price_add,
         i.is_available as item_available, i.sort_order as item_sort
    from public.product_option_groups g
    join public.products p on p.id = g.product_id
    left join public.product_option_items i on i.group_id = g.id
   where p.restaurant_id = 'jyosmi-sushi-guarda';
alter table public.bkp_jyosmi_opcoes_20261108 enable row level security;

create table if not exists public.bkp_jyosmi_restaurante_20261108 as
  select now() as guardado_em, r.id, r.takeaway_default_prep_minutes, r.phone_prep_minutes, r.dispatch_delay_minutes
    from public.restaurants r
   where r.id = 'jyosmi-sushi-guarda';
alter table public.bkp_jyosmi_restaurante_20261108 enable row level security;

-- 1) Nomes iguais ao site e fotos reais onde a app não tinha nenhuma
update public.products p
   set name         = coalesce(v.nome, p.name),
       description  = coalesce(v.descricao, p.description),
       photo_url    = coalesce(v.foto, p.photo_url),
       image_source = case when v.foto is not null then 'site_jyosmi_2026_11_08' else p.image_source end,
       needs_photo  = case when v.foto is not null then false else p.needs_photo end
  from (values
    ('jyosmi-ts04', 'Caixa de Sushi Fritos'::text, 'Caixa de sushi fritos. Pequena 12 peças, média 18, grande 44.'::text, null::text),  -- nome do site (era "Caixa Crocante")
    ('jyosmi-ta07', 'Gyoza Frio', null, null),  -- nome do site (era "Ravioli Frito (Gyoza)")
    ('jyosmi-ex07', 'Molho Soja', null, 'https://strangeroasis.com/wp-content/uploads/2026/07/Soja-souce.png'),  -- nome do site (era "Soja") + foto
    ('jyosmi-ex01', null, null, 'https://strangeroasis.com/wp-content/uploads/2026/07/Molho-Agridoce-Simples.png'),  -- foto real do site (estava sem foto)
    ('jyosmi-ex02', null, null, 'https://strangeroasis.com/wp-content/uploads/2026/07/TeriyakiSauce.png'),  -- foto real do site (estava sem foto)
    ('jyosmi-ex03', null, null, 'https://strangeroasis.com/wp-content/uploads/2026/07/Sweet-chilli.png'),  -- foto real do site (estava sem foto)
    ('jyosmi-ex05', null, null, 'https://strangeroasis.com/wp-content/uploads/2026/07/Gingebre.png'),  -- foto real do site (estava sem foto)
    ('jyosmi-ex06', null, null, 'https://strangeroasis.com/wp-content/uploads/2026/07/Wassabi.png'),  -- foto real do site (estava sem foto)
    ('jyosmi-ts05a', null, null, 'https://strangeroasis.com/wp-content/uploads/2026/06/Hossomaki-Mix.png')  -- foto real do site (estava sem foto)
  ) as v(id, nome, descricao, foto)
 where p.id = v.id
   and p.restaurant_id = 'jyosmi-sushi-guarda';

-- 2) Sai: San Pellegrino já não está no site (o código BSA15 desapareceu da lista). Fica indisponível, não se apaga.
update public.products
   set is_available   = false,
       removal_reason = 'Não está no site da loja (strangeroasis.com/encomendas) a 08/11/2026'
 where id = 'jyosmi-bsa15'
   and restaurant_id = 'jyosmi-sushi-guarda'
   and is_available;

-- 3) Entram 42 produtos que estão no site e faltavam na app (preço de balcão do site).
--    Cerveja, sidra, vinho e destilados nascem +18 (age_restricted = true).
insert into public.products
  (id, restaurant_id, name, photo_url, is_available, price, partner_shelf_price, category, sort_order,
   age_restricted, needs_photo, image_source, source)
values
  ('jyosmi-bsa09a', 'jyosmi-sushi-guarda', 'Guaraná Antarctica 33cl', 'https://strangeroasis.com/wp-content/uploads/2026/10/Guarana-Antartica.jpg', true, 2.20, 2.20, 'Bebidas', 54, false, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BSA09A site: Gurana Antartica-33cl
  ('jyosmi-bce01', 'jyosmi-sushi-guarda', 'Super Bock 33cl', 'https://strangeroasis.com/wp-content/uploads/2026/08/Super-.jpg', true, 2.20, 2.20, 'Cervejas e sidras', 62, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BCE01 site: Super Bock -33cl
  ('jyosmi-bce02', 'jyosmi-sushi-guarda', 'Super Bock Preta 33cl', 'https://strangeroasis.com/wp-content/uploads/2026/08/Super-preta.jpg', true, 2.20, 2.20, 'Cervejas e sidras', 63, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BCE02 site: Super Bock Preta-33cl
  ('jyosmi-bce03', 'jyosmi-sushi-guarda', 'Super Bock Zero 33cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Super-Bock-zero.jpg', true, 2.20, 2.20, 'Cervejas e sidras', 64, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BCE03 site: Super Bock Zero-33cl
  ('jyosmi-bce04', 'jyosmi-sushi-guarda', 'Sagres 33cl', 'https://strangeroasis.com/wp-content/uploads/2026/08/Sagaras.jpg', true, 2.20, 2.20, 'Cervejas e sidras', 65, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BCE04 site: Sagres -33cl
  ('jyosmi-bce05', 'jyosmi-sushi-guarda', 'Sapporo Japonesa 33cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Sapporo-.jpg', true, 4.00, 4.00, 'Cervejas e sidras', 66, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BCE05 site: Sappro Japones -33cl
  ('jyosmi-bce06', 'jyosmi-sushi-guarda', 'Somersby', 'https://strangeroasis.com/wp-content/uploads/2026/08/Somersbi.jpg', true, 3.00, 3.00, 'Cervejas e sidras', 67, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BCE06 site: Somersby
  ('jyosmi-bv01', 'jyosmi-sushi-guarda', 'Grão Vasco Tinto 37,5cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Grao-vasco-tinto.jpg', true, 6.50, 6.50, 'Vinhos', 68, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV01 site: Grao Vasco Tinto -37.5cl
  ('jyosmi-bv02', 'jyosmi-sushi-guarda', 'Grão Vasco Tinto 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Grao-vasco-tinto.jpg', true, 10.00, 10.00, 'Vinhos', 69, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV02 site: Grao Vasco Tinto -75cl
  ('jyosmi-bv03', 'jyosmi-sushi-guarda', 'Monte Velho Tinto 37,5cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/monte-velho-375ml-red-2024.jpg', true, 7.00, 7.00, 'Vinhos', 70, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV03 site: MonteVelho Tinto-37.5cl
  ('jyosmi-bv04', 'jyosmi-sushi-guarda', 'Monte Velho Tinto 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/monte-velho-375ml-red-2024.jpg', true, 11.00, 11.00, 'Vinhos', 71, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV04 site: MonteVelho Tinto-75cl
  ('jyosmi-bv06', 'jyosmi-sushi-guarda', 'Casal Garcia Branco 37,5cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Casal-garcia.jpg', true, 6.50, 6.50, 'Vinhos', 72, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV06 site: Casal Garcia Branco-37.5cl
  ('jyosmi-bv07', 'jyosmi-sushi-guarda', 'Casal Garcia Branco 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Casal-garcia.jpg', true, 11.00, 11.00, 'Vinhos', 73, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV07 site: Casal Garcia Branco-75cl
  ('jyosmi-bv08', 'jyosmi-sushi-guarda', 'Planalto Douro Branco 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/planalto-reserve-white-2024.jpg', true, 12.00, 12.00, 'Vinhos', 74, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV08 site: Planalto Douro Branco-75cl
  ('jyosmi-bv09', 'jyosmi-sushi-guarda', 'Planalto Douro Branco 37,5cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/planalto-reserve-white-2024.jpg', true, 7.00, 7.00, 'Vinhos', 75, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV09 site: Planalto Douro Branco-37.5cl
  ('jyosmi-bv10', 'jyosmi-sushi-guarda', 'Marquês d''Almeida Branco 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Markis-almeida.jpg', true, 11.00, 11.00, 'Vinhos', 76, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV10 site: MarquesD'Almedia Branco-75cl
  ('jyosmi-bv11', 'jyosmi-sushi-guarda', 'Marquês d''Almeida Tinto 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Markis-almeida-Tinto.jpg', true, 11.00, 11.00, 'Vinhos', 77, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV11 site: MarquesD'Almedia Tinto-75cl
  ('jyosmi-bv12', 'jyosmi-sushi-guarda', 'Carm Urze Branco 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Urz-branco.jpg', true, 11.50, 11.50, 'Vinhos', 78, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV12 site: Carm-Urze Brano-75cl
  ('jyosmi-bv13', 'jyosmi-sushi-guarda', 'Carm Urze Tinto 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Urz-tinto.jpg', true, 11.50, 11.50, 'Vinhos', 79, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV13 site: Carm-Urze Tinto-75cl
  ('jyosmi-bv14', 'jyosmi-sushi-guarda', 'Mateus Rosé 37,5cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Matius-Rose.jpg', true, 6.50, 6.50, 'Vinhos', 80, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV14 site: Mateus Rose-37.5cl
  ('jyosmi-bv15', 'jyosmi-sushi-guarda', 'Mateus Rosé 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Matius-Rose.jpg', true, 11.00, 11.00, 'Vinhos', 81, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV15 site: Mateus Rose-75cl
  ('jyosmi-bv16', 'jyosmi-sushi-guarda', 'Santero Doce 75cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Santero-Doce.jpg', true, 10.00, 10.00, 'Vinhos', 82, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV16 site: Santero Doce-75cl
  ('jyosmi-bv17', 'jyosmi-sushi-guarda', 'D. João Tinto (copo)', 'https://strangeroasis.com/wp-content/uploads/2026/09/D.-Joao-Tinto.jpg', true, 2.50, 2.50, 'Vinhos', 83, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV17 site: D. Joao Tinto-Copo
  ('jyosmi-bv18', 'jyosmi-sushi-guarda', 'D. João Branco (copo)', 'https://strangeroasis.com/wp-content/uploads/2026/09/D.-Joao-Branco.jpg', true, 2.50, 2.50, 'Vinhos', 84, true, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BV18 site: D. Joao Branco-Copo
  ('jyosmi-bca01', 'jyosmi-sushi-guarda', 'Vodka Rodanov 50ml', null, true, 4.00, 4.00, 'Destilados', 85, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA01 site: Vodka Rodanov -50ml
  ('jyosmi-bca02', 'jyosmi-sushi-guarda', 'Macieira 50ml', null, true, 4.00, 4.00, 'Destilados', 86, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA02 site: Macieira -50ml
  ('jyosmi-bca03', 'jyosmi-sushi-guarda', 'Gin Bombay 50ml', null, true, 4.00, 4.00, 'Destilados', 87, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA03 site: Gin Bombay -50ml
  ('jyosmi-bca04', 'jyosmi-sushi-guarda', 'Bushmills 50ml', null, true, 4.50, 4.50, 'Destilados', 88, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA04 site: Bushmills -50ml
  ('jyosmi-bca05', 'jyosmi-sushi-guarda', 'Jameson 50ml', null, true, 4.50, 4.50, 'Destilados', 89, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA05 site: Jameson -50ml
  ('jyosmi-bca06', 'jyosmi-sushi-guarda', 'J&B 50ml', null, true, 4.50, 4.50, 'Destilados', 90, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA06 site: J&B -50ml
  ('jyosmi-bca07', 'jyosmi-sushi-guarda', 'Jack Daniel''s 50ml', null, true, 4.50, 4.50, 'Destilados', 91, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA07 site: Jack Daniel's -50ml
  ('jyosmi-bca08', 'jyosmi-sushi-guarda', 'Martini Branco 50ml', null, true, 4.00, 4.00, 'Destilados', 92, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA08 site: Martini Branco -50ml
  ('jyosmi-bca09', 'jyosmi-sushi-guarda', 'Martini Rosso 50ml', null, true, 4.00, 4.00, 'Destilados', 93, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA09 site: Martini Rosso -50ml
  ('jyosmi-bca10', 'jyosmi-sushi-guarda', 'Martini Dry 50ml', null, true, 4.00, 4.00, 'Destilados', 94, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA10 site: Martini Dry -50ml
  ('jyosmi-bca11', 'jyosmi-sushi-guarda', 'Johnnie Walker Double Black 50ml', null, true, 5.50, 5.50, 'Destilados', 95, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA11 site: J Walker Double Black - 50 cl
  ('jyosmi-bca12', 'jyosmi-sushi-guarda', 'Famous Grouse 50ml', null, true, 4.00, 4.00, 'Destilados', 96, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA12 site: Famous -50ml
  ('jyosmi-bca13', 'jyosmi-sushi-guarda', 'Grant''s 50ml', null, true, 4.00, 4.00, 'Destilados', 97, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA13 site: Grants -50ml
  ('jyosmi-bca14', 'jyosmi-sushi-guarda', 'Saké Japonês 150ml', null, true, 4.50, 4.50, 'Destilados', 98, true, true, null, 'balcao_site_jyosmi_2026_11_08'),  -- BCA14 site: Sake Japones -150ml
  ('jyosmi-bsa18', 'jyosmi-sushi-guarda', 'Café', 'https://strangeroasis.com/wp-content/uploads/2026/09/Cafe.jpg', true, 1.00, 1.00, 'Bebidas quentes', 99, false, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BSA18 site: Café
  ('jyosmi-bsa19', 'jyosmi-sushi-guarda', 'Descafeinado', 'https://strangeroasis.com/wp-content/uploads/2026/09/Cafe.jpg', true, 1.20, 1.20, 'Bebidas quentes', 100, false, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BSA19 site: Descafeinado
  ('jyosmi-bsa20', 'jyosmi-sushi-guarda', 'Chá Verde 70cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Cha.jpg', true, 3.00, 3.00, 'Bebidas quentes', 101, false, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08'),  -- BSA20 site: Chá Verde -70cl
  ('jyosmi-bsa21', 'jyosmi-sushi-guarda', 'Chá de Jasmim 70cl', 'https://strangeroasis.com/wp-content/uploads/2026/09/Cha.jpg', true, 3.50, 3.50, 'Bebidas quentes', 102, false, false, 'site_jyosmi_2026_11_08', 'balcao_site_jyosmi_2026_11_08')  -- BSA21 site: Chá Jasmine -70cl
on conflict (id) do update
   set name                = excluded.name,
       photo_url           = excluded.photo_url,
       is_available        = excluded.is_available,
       price               = excluded.price,
       partner_shelf_price = excluded.partner_shelf_price,
       category            = excluded.category,
       sort_order          = excluded.sort_order,
       age_restricted      = excluded.age_restricted,
       needs_photo         = excluded.needs_photo,
       image_source        = excluded.image_source,
       source              = excluded.source
 where products.restaurant_id = 'jyosmi-sushi-guarda';

-- 4) Ordem do menu igual à do site (Entradas, Combinados, Poke, Bebidas, Sobremesas, Extras).
--    Hoje as Bebidas aparecem primeiro porque todas as categorias começam em 1 e desempata o id.
update public.products p
   set sort_order = v.ordem
  from (values
    ('jyosmi-ta01', 1), ('jyosmi-ta02', 2), ('jyosmi-ta03', 3), ('jyosmi-ta04', 4), ('jyosmi-ta04a', 5), ('jyosmi-ta05', 6),
    ('jyosmi-ta06', 7), ('jyosmi-ta06a', 8), ('jyosmi-ta07', 9), ('jyosmi-ta07a', 10), ('jyosmi-ta07b', 11), ('jyosmi-ta08', 12),
    ('jyosmi-ta09', 13), ('jyosmi-ta10', 14), ('jyosmi-ta11', 15), ('jyosmi-ta12', 16), ('jyosmi-ta13', 17), ('jyosmi-ta14', 18),
    ('jyosmi-ta15', 19), ('jyosmi-ta16', 20), ('jyosmi-ta17', 21), ('jyosmi-ta18', 22), ('jyosmi-ta19', 23), ('jyosmi-ta20', 24),
    ('jyosmi-ta21', 25), ('jyosmi-ta22', 26), ('jyosmi-ts00', 27), ('jyosmi-ts01', 28), ('jyosmi-ts02', 29), ('jyosmi-ts03', 30),
    ('jyosmi-ts04', 31), ('jyosmi-ts05', 32), ('jyosmi-ts05a', 33), ('jyosmi-ts06', 34), ('jyosmi-ts07', 35), ('jyosmi-ts08', 36),
    ('jyosmi-ts09', 37), ('jyosmi-ts10', 38), ('jyosmi-ts11', 39), ('jyosmi-ts12', 40), ('jyosmi-tsp01', 41), ('jyosmi-tsp02', 42),
    ('jyosmi-tsp03', 43), ('jyosmi-bsa01', 44), ('jyosmi-bsa02', 45), ('jyosmi-bsa03', 46), ('jyosmi-bsa04', 47), ('jyosmi-bsa05', 48),
    ('jyosmi-bsa05a', 49), ('jyosmi-bsa06', 50), ('jyosmi-bsa07', 51), ('jyosmi-bsa08', 52), ('jyosmi-bsa09', 53), ('jyosmi-bsa10', 55),
    ('jyosmi-bsa11', 56), ('jyosmi-bsa12', 57), ('jyosmi-bsa13', 58), ('jyosmi-bsa14', 59), ('jyosmi-bsa16', 60), ('jyosmi-bsa17', 61),
    ('jyosmi-sm01', 103), ('jyosmi-sm02', 104), ('jyosmi-sm03', 105), ('jyosmi-sm04', 106), ('jyosmi-sm05', 107), ('jyosmi-sm06', 108),
    ('jyosmi-sm07', 109), ('jyosmi-ex01', 110), ('jyosmi-ex03', 111), ('jyosmi-ex02', 112), ('jyosmi-ex07', 113), ('jyosmi-ex06', 114),
    ('jyosmi-ex05', 115), ('jyosmi-ex04', 116)
  ) as v(id, ordem)
 where p.id = v.id
   and p.restaurant_id = 'jyosmi-sushi-guarda'
   and p.sort_order is distinct from v.ordem;

-- 5) Tamanhos nas entradas (o site só tem Pequena e Média; Grande não existe nas entradas).
--    Grupo obrigatório "Tamanho" (escolher 1), como nos combinados. price_add = preço Média - preço Pequena.
insert into public.product_option_groups (id, product_id, name, description, is_required, min_choices, max_choices, sort_order)
values
  ('jyosmi-ta03-g0', 'jyosmi-ta03', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta04-g0', 'jyosmi-ta04', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta04a-g0', 'jyosmi-ta04a', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta05-g0', 'jyosmi-ta05', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta06-g0', 'jyosmi-ta06', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta06a-g0', 'jyosmi-ta06a', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta07-g0', 'jyosmi-ta07', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta07a-g0', 'jyosmi-ta07a', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta07b-g0', 'jyosmi-ta07b', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta08-g0', 'jyosmi-ta08', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta09-g0', 'jyosmi-ta09', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta10-g0', 'jyosmi-ta10', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta11-g0', 'jyosmi-ta11', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta12-g0', 'jyosmi-ta12', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta13-g0', 'jyosmi-ta13', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta14-g0', 'jyosmi-ta14', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta15-g0', 'jyosmi-ta15', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta16-g0', 'jyosmi-ta16', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta17-g0', 'jyosmi-ta17', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta18-g0', 'jyosmi-ta18', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta19-g0', 'jyosmi-ta19', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta20-g0', 'jyosmi-ta20', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta21-g0', 'jyosmi-ta21', 'Tamanho', null, true, 1, 1, 0),
  ('jyosmi-ta22-g0', 'jyosmi-ta22', 'Tamanho', null, true, 1, 1, 0)
on conflict (id) do update
   set name = excluded.name, is_required = excluded.is_required, min_choices = excluded.min_choices,
       max_choices = excluded.max_choices, sort_order = excluded.sort_order, updated_at = now()
 where product_option_groups.product_id = excluded.product_id;

insert into public.product_option_items (id, group_id, name, price_add, is_available, sort_order)
values
  ('jyosmi-ta03-g0-i0', 'jyosmi-ta03-g0', 'Pequena (10 peças)', 0.00, true, 0),
  ('jyosmi-ta03-g0-i1', 'jyosmi-ta03-g0', 'Média (12 peças)', 1.00, true, 1),  -- TA03 Camarão Panado: 9 / 10 €
  ('jyosmi-ta04-g0-i0', 'jyosmi-ta04-g0', 'Pequena (10 peças)', 0.00, true, 0),
  ('jyosmi-ta04-g0-i1', 'jyosmi-ta04-g0', 'Média (12 peças)', 1.00, true, 1),  -- TA04 Crepe de Camarão: 9 / 10 €
  ('jyosmi-ta04a-g0-i0', 'jyosmi-ta04a-g0', 'Pequena (10 peças)', 0.00, true, 0),
  ('jyosmi-ta04a-g0-i1', 'jyosmi-ta04a-g0', 'Média (12 peças)', 1.00, true, 1),  -- TA04A Camarão com Amêndoas: 10 / 11 €
  ('jyosmi-ta05-g0-i0', 'jyosmi-ta05-g0', 'Pequena (7 peças)', 0.00, true, 0),
  ('jyosmi-ta05-g0-i1', 'jyosmi-ta05-g0', 'Média (9 peças)', 1.00, true, 1),  -- TA05 Crepe de Legumes: 7 / 8 €
  ('jyosmi-ta06-g0-i0', 'jyosmi-ta06-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta06-g0-i1', 'jyosmi-ta06-g0', 'Média', 1.00, true, 1),  -- TA06 Frango Panado: 7 / 8 €
  ('jyosmi-ta06a-g0-i0', 'jyosmi-ta06a-g0', 'Pequena (10 peças)', 0.00, true, 0),
  ('jyosmi-ta06a-g0-i1', 'jyosmi-ta06a-g0', 'Média (15 peças)', 2.00, true, 1),  -- TA06A Mix de Fritos: 9 / 11 €
  ('jyosmi-ta07-g0-i0', 'jyosmi-ta07-g0', 'Pequena (8 peças)', 0.00, true, 0),
  ('jyosmi-ta07-g0-i1', 'jyosmi-ta07-g0', 'Média (10 peças)', 1.00, true, 1),  -- TA07 Gyoza Frio: 8 / 9 €
  ('jyosmi-ta07a-g0-i0', 'jyosmi-ta07a-g0', 'Pequena (10 peças)', 0.00, true, 0),
  ('jyosmi-ta07a-g0-i1', 'jyosmi-ta07a-g0', 'Média (12 peças)', 1.00, true, 1),  -- TA07A Lula Frita: 9 / 10 €
  ('jyosmi-ta07b-g0-i0', 'jyosmi-ta07b-g0', 'Pequena (6 peças)', 0.00, true, 0),
  ('jyosmi-ta07b-g0-i1', 'jyosmi-ta07b-g0', 'Média (10 peças)', 2.00, true, 1),  -- TA07B Queijo Frito: 6 / 8 €
  ('jyosmi-ta08-g0-i0', 'jyosmi-ta08-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta08-g0-i1', 'jyosmi-ta08-g0', 'Média', 2.00, true, 1),  -- TA08 Algas com Oyster: 8 / 10 €
  ('jyosmi-ta09-g0-i0', 'jyosmi-ta09-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta09-g0-i1', 'jyosmi-ta09-g0', 'Média', 2.00, true, 1),  -- TA09 Porco com Oyster: 9 / 11 €
  ('jyosmi-ta10-g0-i0', 'jyosmi-ta10-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta10-g0-i1', 'jyosmi-ta10-g0', 'Média', 1.00, true, 1),  -- TA10 Frango Agridoce e Mel: 7 / 8 €
  ('jyosmi-ta11-g0-i0', 'jyosmi-ta11-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta11-g0-i1', 'jyosmi-ta11-g0', 'Média', 1.50, true, 1),  -- TA11 Legumes e Cogumelos: 5.5 / 7 €
  ('jyosmi-ta12-g0-i0', 'jyosmi-ta12-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta12-g0-i1', 'jyosmi-ta12-g0', 'Média', 1.00, true, 1),  -- TA12 Cogumelos Salteados: 6.5 / 7.5 €
  ('jyosmi-ta13-g0-i0', 'jyosmi-ta13-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta13-g0-i1', 'jyosmi-ta13-g0', 'Média', 1.00, true, 1),  -- TA13 Vitela Salteada: 7.5 / 8.5 €
  ('jyosmi-ta14-g0-i0', 'jyosmi-ta14-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta14-g0-i1', 'jyosmi-ta14-g0', 'Média', 1.00, true, 1),  -- TA14 Camarão Salteado: 8.5 / 9.5 €
  ('jyosmi-ta15-g0-i0', 'jyosmi-ta15-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta15-g0-i1', 'jyosmi-ta15-g0', 'Média', 1.00, true, 1),  -- TA15 Arroz Branco: 3.5 / 4.5 €
  ('jyosmi-ta16-g0-i0', 'jyosmi-ta16-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta16-g0-i1', 'jyosmi-ta16-g0', 'Média', 1.00, true, 1),  -- TA16 Arroz chau-chau: 4 / 5 €
  ('jyosmi-ta17-g0-i0', 'jyosmi-ta17-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta17-g0-i1', 'jyosmi-ta17-g0', 'Média', 1.00, true, 1),  -- TA17 Massa com Legumes: 5.5 / 6.5 €
  ('jyosmi-ta18-g0-i0', 'jyosmi-ta18-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta18-g0-i1', 'jyosmi-ta18-g0', 'Média', 1.00, true, 1),  -- TA18 Massa Salteada com Frango: 6.5 / 7.5 €
  ('jyosmi-ta19-g0-i0', 'jyosmi-ta19-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta19-g0-i1', 'jyosmi-ta19-g0', 'Média', 1.00, true, 1),  -- TA19 Massa Salteada com Porco: 7 / 8 €
  ('jyosmi-ta20-g0-i0', 'jyosmi-ta20-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta20-g0-i1', 'jyosmi-ta20-g0', 'Média', 1.00, true, 1),  -- TA20 Massa com Camarão: 7.5 / 8.5 €
  ('jyosmi-ta21-g0-i0', 'jyosmi-ta21-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta21-g0-i1', 'jyosmi-ta21-g0', 'Média', 1.00, true, 1),  -- TA21 Massa com Vitela: 7.5 / 8.5 €
  ('jyosmi-ta22-g0-i0', 'jyosmi-ta22-g0', 'Pequena', 0.00, true, 0),
  ('jyosmi-ta22-g0-i1', 'jyosmi-ta22-g0', 'Média', 1.00, true, 1)  -- TA22 Massa Fina: 5.5 / 6.5 €
on conflict (id) do update
   set group_id = excluded.group_id, name = excluded.name, price_add = excluded.price_add,
       is_available = excluded.is_available, sort_order = excluded.sort_order
 where product_option_items.id like 'jyosmi-%';

-- 6) Especial JYOSMI: a bebida grátis só na Média e na Grande, com a regra presa no próprio Tamanho.
--    Hoje o grupo "Bebida grátis" é opcional e separado: quem escolhe a Pequena também consegue pedir a bebida.
--    Agora cada opção de Média/Grande já leva a bebida escolhida (Coca-Cola, Pepsi, Ice Tea ou Água, como no site).
--    Reaproveitam-se as 4 linhas antigas do grupo da bebida (mudam para o grupo Tamanho); entram 2 linhas novas.
insert into public.product_option_items (id, group_id, name, price_add, is_available, sort_order)
values
  ('jyosmi-ts09-g0-i0', 'jyosmi-ts09-g0', 'Pequena (12 peças)',                         0.00, true, 0),
  ('jyosmi-ts09-g0-i1', 'jyosmi-ts09-g0', 'Média (18 peças) + Coca-Cola 33cl grátis',   3.00, true, 1),
  ('jyosmi-ts09-g1-i1', 'jyosmi-ts09-g0', 'Média (18 peças) + Pepsi 33cl grátis',       3.00, true, 2),
  ('jyosmi-ts09-g1-i2', 'jyosmi-ts09-g0', 'Média (18 peças) + Ice Tea 33cl grátis',     3.00, true, 3),
  ('jyosmi-ts09-g1-i3', 'jyosmi-ts09-g0', 'Média (18 peças) + Água 500ml grátis',       3.00, true, 4),
  ('jyosmi-ts09-g0-i2', 'jyosmi-ts09-g0', 'Grande (44 peças) + Coca-Cola 33cl grátis', 21.00, true, 5),
  ('jyosmi-ts09-g1-i0', 'jyosmi-ts09-g0', 'Grande (44 peças) + Pepsi 33cl grátis',     21.00, true, 6),
  ('jyosmi-ts09-g0-i3', 'jyosmi-ts09-g0', 'Grande (44 peças) + Ice Tea 33cl grátis',   21.00, true, 7),
  ('jyosmi-ts09-g0-i4', 'jyosmi-ts09-g0', 'Grande (44 peças) + Água 500ml grátis',     21.00, true, 8)
on conflict (id) do update
   set group_id = excluded.group_id, name = excluded.name, price_add = excluded.price_add,
       is_available = excluded.is_available, sort_order = excluded.sort_order
 where product_option_items.id like 'jyosmi-ts09-%';

-- O grupo antigo da bebida fica vazio. Não se apaga aqui (regra: nada de DELETE); passa a servir de aviso.
-- Para o tirar do ecrã de vez: ver o passo opcional no fim da proposta (1 linha, decisão da sessão principal).
update public.product_option_groups
   set name = 'Bebida grátis: escolhe-a no Tamanho, acima',
       description = 'Na Média e na Grande a bebida já vem incluída na escolha do tamanho.',
       is_required = false, min_choices = 0, max_choices = 1, sort_order = 1, updated_at = now()
 where id = 'jyosmi-ts09-g1'
   and product_id = 'jyosmi-ts09';

-- 7) Tempo de preparação: o site diz "Pedidos prontos em 30-45 min". A base só guarda um número;
--    fica o máximo (45), para a app nunca prometer antes do que a loja cumpre. Era 20.
--    phone_prep_minutes = o "fica pronta em X min" dos pedidos feitos por telefone (esta loja encomenda por telefone);
--    takeaway_default_prep_minutes = o mesmo para levantar no restaurante.
--    dispatch_delay_minutes (estafeta chamado 15 min depois) NÃO se mexe aqui: ver dúvidas na proposta.
update public.restaurants
   set phone_prep_minutes = 45,
       takeaway_default_prep_minutes = 45
 where id = 'jyosmi-sushi-guarda'
   and (phone_prep_minutes is distinct from 45 or takeaway_default_prep_minutes is distinct from 45);

commit;

-- 8) Prova (só leitura) — números esperados depois de aplicar:
--    produtos 117 (116 disponíveis + San Pellegrino indisponível); +18 disponíveis 37;
--    grupos "Tamanho" 36 (12 combinados + 24 entradas); itens no Tamanho do Especial 9; prep 45/45.
select
  (select count(*) from public.products where restaurant_id = 'jyosmi-sushi-guarda')                                   as produtos,
  (select count(*) from public.products where restaurant_id = 'jyosmi-sushi-guarda' and is_available)                  as disponiveis,
  (select count(*) from public.products where restaurant_id = 'jyosmi-sushi-guarda' and is_available and age_restricted) as maiores_18,
  (select count(*) from public.product_option_groups g join public.products p on p.id = g.product_id
    where p.restaurant_id = 'jyosmi-sushi-guarda' and g.name = 'Tamanho')                                              as grupos_tamanho,
  (select count(*) from public.product_option_items where group_id = 'jyosmi-ts09-g0' and is_available)                 as especial_tamanhos,
  (select count(*) from public.product_option_items where group_id = 'jyosmi-ts09-g1')                                  as especial_grupo_antigo_itens,
  (select phone_prep_minutes || '/' || takeaway_default_prep_minutes from public.restaurants where id = 'jyosmi-sushi-guarda') as prep;
