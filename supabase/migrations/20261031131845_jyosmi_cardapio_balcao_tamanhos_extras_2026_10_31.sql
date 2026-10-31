-- 31/10/2026: cardápio de balcão (foto do Danilo) do Jyosmi Sushi, página "Sushi e Combinados" + Extras.
-- Os preços de base guardados (caixa pequena) já batiam com o cardápio; faltavam os tamanhos
-- médio e grande, o Hossomaki Mix, a escolha do temaki, a bebida grátis da Especial e os extras.
-- price_add é sempre em preço de BALCÃO (a app soma a margem por cima, como no resto).

-- 1) Nome e descrições
update public.products set name = 'Caixa Crocante',
       description = 'Caixa de sushi crocante. Pequena 12 peças, média 18, grande 44.'
 where id = 'jyosmi-ts04';
update public.products set description = 'Seleção de sushi tradicional e sashimi. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts01';
update public.products set description = 'Caixa premium com sushi fritos. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts02';
update public.products set description = 'Caixa premium sem sushi fritos. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts03';
update public.products set description = 'Sushi braseado na hora. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts05';
update public.products set description = 'Seleção variada de nigiri. Pequena 12 peças, média 18.' where id = 'jyosmi-ts06';
update public.products set description = 'Seleção variada de sashimi fresco. Pequena 12 peças, média 18.' where id = 'jyosmi-ts07';
update public.products set description = '1 temaki. Escolha o sabor: salmão e filadélfia, salmão e fruta, atum ou camarão.' where id = 'jyosmi-ts08';
update public.products set description = 'Caixa especial da casa. Pequena 12 peças; média 18 e grande 44 com 1 bebida grátis (Coca-Cola 33cl, Pepsi 33cl, Ice Tea 33cl ou água 500ml).' where id = 'jyosmi-ts09';
update public.products set description = 'Seleção clássica de sushi e sashimi. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts10';
update public.products set description = 'Sushi criativo com sabores modernos. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts11';
update public.products set description = 'Seleção de sushi 100% vegetal. Pequena 12 peças, média 18, grande 44.' where id = 'jyosmi-ts12';

-- 2) Hossomaki Mix (TS05A) — faltava. Entra logo a seguir ao Sushi Braseado.
update public.products set sort_order = sort_order + 1
 where restaurant_id = 'jyosmi-sushi-guarda' and category = 'Sushi e Combinados' and sort_order >= 7;
insert into public.products (id, restaurant_id, name, description, price, partner_shelf_price, category,
                             is_available, sort_order, source, needs_photo)
values ('jyosmi-ts05a', 'jyosmi-sushi-guarda', 'Hossomaki Mix',
        'Mix de hossomaki (rolinhos finos). Pequena 20 peças, média 24.', 10.00, 10.00, 'Sushi e Combinados',
        true, 7, 'balcao_cardapio_foto_2026_10_31', true);

-- 3) Tamanhos (obrigatório, escolhe 1)
create temp table _tam(pid text, ordem int, nome text, preco_add numeric) on commit drop;
insert into _tam values
 ('jyosmi-ts01',0,'Pequena (12 peças)',0), ('jyosmi-ts01',1,'Média (18 peças)',2.50), ('jyosmi-ts01',2,'Grande (44 peças)',18.50),
 ('jyosmi-ts02',0,'Pequena (12 peças)',0), ('jyosmi-ts02',1,'Média (18 peças)',1.50), ('jyosmi-ts02',2,'Grande (44 peças)',16.00),
 ('jyosmi-ts03',0,'Pequena (12 peças)',0), ('jyosmi-ts03',1,'Média (18 peças)',1.50), ('jyosmi-ts03',2,'Grande (44 peças)',16.50),
 ('jyosmi-ts04',0,'Pequena (12 peças)',0), ('jyosmi-ts04',1,'Média (18 peças)',2.00), ('jyosmi-ts04',2,'Grande (44 peças)',17.00),
 ('jyosmi-ts05',0,'Pequena (12 peças)',0), ('jyosmi-ts05',1,'Média (18 peças)',2.50), ('jyosmi-ts05',2,'Grande (44 peças)',18.50),
 ('jyosmi-ts05a',0,'Pequena (20 peças)',0), ('jyosmi-ts05a',1,'Média (24 peças)',1.00),
 ('jyosmi-ts06',0,'Pequena (12 peças)',0), ('jyosmi-ts06',1,'Média (18 peças)',2.50),
 ('jyosmi-ts07',0,'Pequena (12 peças)',0), ('jyosmi-ts07',1,'Média (18 peças)',2.00),
 ('jyosmi-ts09',0,'Pequena (12 peças)',0), ('jyosmi-ts09',1,'Média (18 peças) + bebida grátis',3.00), ('jyosmi-ts09',2,'Grande (44 peças) + bebida grátis',21.00),
 ('jyosmi-ts10',0,'Pequena (12 peças)',0), ('jyosmi-ts10',1,'Média (18 peças)',3.00), ('jyosmi-ts10',2,'Grande (44 peças)',21.00),
 ('jyosmi-ts11',0,'Pequena (12 peças)',0), ('jyosmi-ts11',1,'Média (18 peças)',3.00), ('jyosmi-ts11',2,'Grande (44 peças)',21.00),
 ('jyosmi-ts12',0,'Pequena (12 peças)',0), ('jyosmi-ts12',1,'Média (18 peças)',2.00), ('jyosmi-ts12',2,'Grande (44 peças)',15.00);

insert into public.product_option_groups (id, product_id, name, description, is_required, min_choices, max_choices, sort_order)
select distinct pid || '-g0', pid, 'Tamanho', null, true, 1, 1, 0 from _tam;

insert into public.product_option_items (id, group_id, name, price_add, is_available, sort_order)
select pid || '-g0-i' || ordem, pid || '-g0', nome, preco_add, true, ordem from _tam;

-- 4) Especial JYOSMI: bebida grátis na média e na grande (opcional, sem custo)
insert into public.product_option_groups (id, product_id, name, description, is_required, min_choices, max_choices, sort_order)
values ('jyosmi-ts09-g1', 'jyosmi-ts09', 'Bebida grátis (só na Média ou Grande)',
        'Oferta da casa nas caixas média e grande.', false, 0, 1, 1);
insert into public.product_option_items (id, group_id, name, price_add, is_available, sort_order) values
 ('jyosmi-ts09-g1-i0', 'jyosmi-ts09-g1', 'Coca-Cola 33cl', 0, true, 0),
 ('jyosmi-ts09-g1-i1', 'jyosmi-ts09-g1', 'Pepsi 33cl', 0, true, 1),
 ('jyosmi-ts09-g1-i2', 'jyosmi-ts09-g1', 'Ice Tea 33cl', 0, true, 2),
 ('jyosmi-ts09-g1-i3', 'jyosmi-ts09-g1', 'Água 500ml', 0, true, 3);

-- 5) Temaki: sabor escolhido na app (antes era "indicar nas notas")
insert into public.product_option_groups (id, product_id, name, description, is_required, min_choices, max_choices, sort_order)
values ('jyosmi-ts08-g0', 'jyosmi-ts08', 'Sabor do temaki', null, true, 1, 1, 0);
insert into public.product_option_items (id, group_id, name, price_add, is_available, sort_order) values
 ('jyosmi-ts08-g0-i0', 'jyosmi-ts08-g0', 'Salmão e Filadélfia', 0, true, 0),
 ('jyosmi-ts08-g0-i1', 'jyosmi-ts08-g0', 'Salmão e Fruta', 0, true, 1),
 ('jyosmi-ts08-g0-i2', 'jyosmi-ts08-g0', 'Atum', 0, true, 2),
 ('jyosmi-ts08-g0-i3', 'jyosmi-ts08-g0', 'Camarão', 0, true, 3);

-- 6) Extras do cardápio
insert into public.products (id, restaurant_id, name, description, price, partner_shelf_price, category,
                             is_available, sort_order, source, needs_photo) values
 ('jyosmi-ex01', 'jyosmi-sushi-guarda', 'Molho Agridoce', '', 1.00, 1.00, 'Extras', true, 1, 'balcao_cardapio_foto_2026_10_31', true),
 ('jyosmi-ex02', 'jyosmi-sushi-guarda', 'Molho Teriyaki', '', 1.00, 1.00, 'Extras', true, 2, 'balcao_cardapio_foto_2026_10_31', true),
 ('jyosmi-ex03', 'jyosmi-sushi-guarda', 'Molho Sweet Chili', '', 1.00, 1.00, 'Extras', true, 3, 'balcao_cardapio_foto_2026_10_31', true),
 ('jyosmi-ex04', 'jyosmi-sushi-guarda', 'Pauzinhos', '', 0.50, 0.50, 'Extras', true, 4, 'balcao_cardapio_foto_2026_10_31', true),
 ('jyosmi-ex05', 'jyosmi-sushi-guarda', 'Gengibre', '', 0.50, 0.50, 'Extras', true, 5, 'balcao_cardapio_foto_2026_10_31', true),
 ('jyosmi-ex06', 'jyosmi-sushi-guarda', 'Wasabi', '', 0.50, 0.50, 'Extras', true, 6, 'balcao_cardapio_foto_2026_10_31', true),
 ('jyosmi-ex07', 'jyosmi-sushi-guarda', 'Soja', '', 0.50, 0.50, 'Extras', true, 7, 'balcao_cardapio_foto_2026_10_31', true);
