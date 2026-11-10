-- PASSO 4 — KFC Guarda: preços pela regra do balcão, nomes e duplicados das bebidas, Pepsi nas opções.
-- Missão volta-deposito-kfc-2026-11-09. Danilo 09/11/2026 19:36: "Eu autorizo" (corrigir o catálogo do KFC
-- pelo que existe no Glovo da Guarda / no balcão). Regra da missão: preço de balcão; sem fonte de balcão,
-- Glovo ÷ 1,24 (rácio medido no talão FS 515/163490 de hoje: Menu Kentucky BBQ 9,15 vs 11,35 no Glovo;
-- Menu Wrap Coronel 8,45 vs 10,45), SÓ para SUBIR e nunca acima do Glovo. Glovo lido a 09/11 ~21:30
-- (preço sem promoção quando havia promoção). Gerado por script (gerar_kfc.mjs), não à mão.
-- Não mexe nos 3 preços do talão de hoje (Menu Kentucky BBQ, Menu Wrap Coronel, Box 6 Hotwings).

create table if not exists public.bkp_products_kfc_volta_20261109 as
  select id, name, price, is_available, now() as em from public.products where restaurant_id = 'kfc-guarda';
alter table public.bkp_products_kfc_volta_20261109 enable row level security;
create table if not exists public.bkp_poi_kfc_volta_20261109 as
  select poi.*, now() as em from public.product_option_items poi
    join public.product_option_groups pog on pog.id = poi.group_id
    join public.products p on p.id = pog.product_id where p.restaurant_id = 'kfc-guarda';
alter table public.bkp_poi_kfc_volta_20261109 enable row level security;

-- 4.1 Preços (só sobem; a guarda "price < novo" impede descer se alguém já mudou entretanto)
update public.products p set price = v.novo
  from (values
    ('kfc-20796087-76e8-4da2-897a-7dcfae721c2c', 7.86::numeric),
    ('kfc-5b46320f-9c2a-41a6-87e3-e7ce3a57e600', 9.48::numeric),
    ('kfc-9211f045-a83b-4176-a464-ea3bb1bdfcf7', 8.35::numeric),
    ('kfc-a5ac744e-0999-4303-b81b-62a8bb0780d1', 8.19::numeric),
    ('kfc-8aeb3d0b-69a0-4050-99ec-ea20b75f9f34', 13.23::numeric),
    ('kfc-4deba2fc-23a8-4acd-abb7-2a14fec9a623', 2.06::numeric),
    ('kfc-73a289b2-a3a2-41f9-9ebb-defa76aedbb2', 8.19::numeric),
    ('kfc-996d07c4-8462-41fc-93d0-bd9f65eb9d82', 7.86::numeric),
    ('kfc-756b0227-4676-4df2-bbd8-af3a846ecd34', 11.69::numeric),
    ('kfc-e79f3076-8e3a-4208-8abc-dc96b4f609ea', 10.97::numeric),
    ('kfc-016fe497-a823-4751-ad0c-bd550ba46d06', 12.18::numeric),
    ('kfc-6abb232d-aa76-4ce2-8ab9-615c7effc2b8', 10.48::numeric),
    ('kfc-df51606d-b745-4d5d-a656-94ee5e00f66a', 12.02::numeric),
    ('kfc-6b843796-89c4-453a-b69a-e6b7c90b08c6', 11.69::numeric),
    ('kfc-72b24d64-8736-412b-8bdb-24f5aa2b24a0', 7.25::numeric),
    ('kfc-1a2967c2-09ff-4b0c-9777-736d36cedc97', 6.44::numeric),
    ('kfc-561b4a56-09cb-4df8-8cd2-cd8c356115f1', 2.66::numeric),
    ('kfc-212e0da2-8137-472a-a549-75bd45026f4b', 12.38::numeric),
    ('kfc-aea6d475-6a54-41c8-982c-f416625d7186', 11.90::numeric),
    ('kfc-8fcc6b39-6dbf-4b08-824b-ea36ca90c739', 11.57::numeric),
    ('kfc-d39b3985-b623-49ca-a3f8-812049df237b', 10.69::numeric),
    ('kfc-9132d924-7245-4ac8-9af0-75c5a20a9295', 11.17::numeric),
    ('kfc-252a078a-fba1-4798-8ce9-8712ee62f68e', 8.83::numeric),
    ('kfc-cb18e69f-5821-4f4a-9b1a-b40ed51802f9', 8.43::numeric),
    ('kfc-63c82c16-69d3-4dde-b016-a95a6d93a9ad', 7.94::numeric),
    ('kfc-f65f60cb-5885-4f60-a725-8884d46746cc', 6.73::numeric),
    ('kfc-29d9aa6a-b9db-40cf-a5ab-c8a084feb5fc', 6.57::numeric),
    ('kfc-39aa42bc-2759-4f0d-9d3b-b65cf448aa05', 10.44::numeric),
    ('kfc-8fbde4b8-27ed-4ae4-93fb-fd6f025f1dd1', 7.46::numeric),
    ('kfc-be4e6b26-ff24-42d0-b3f1-82a8be75a034', 8.83::numeric),
    ('kfc-ef911b6e-d2e5-454c-a638-3025d12b875f', 2.26::numeric),
    ('kfc-53055103-77c0-4b13-b00b-3ac5590171f9', 2.26::numeric),
    ('kfc-178ea47d-a6d4-4c67-a512-513cb4268bdb', 17.70::numeric),
    ('kfc-53248777-9bd4-443c-a917-b750d521265a', 10.93::numeric),
    ('kfc-302f3166-e7fb-4ae5-8d9c-311dab3b9681', 9.15::numeric),
    ('kfc-28cf7429-e653-484a-bf10-8c67667b4ec4', 7.22::numeric),
    ('kfc-6b63bed3-10e8-4fc0-8e1c-77eaf18f1425', 17.86::numeric),
    ('kfc-51ec13fc-fd95-42a4-ac60-5c138dcd812e', 9.64::numeric),
    ('kfc-268eff10-1402-4534-9378-5182cd72f064', 7.54::numeric),
    ('kfc-aaa886f2-34fa-4b0f-b679-985b6062ae56', 23.35::numeric),
    ('kfc-5d520586-f639-4710-9d90-5d29d49fec0b', 19.48::numeric),
    ('kfc-44bc6f3b-8210-43bb-9052-6cf5c7be5472', 10.69::numeric),
    ('kfc-f563b810-565b-466c-a0a9-72f8d2b95ba9', 17.86::numeric),
    ('kfc-94850f85-f98a-4696-8998-2a43ba01a427', 9.48::numeric),
    ('kfc-344d6481-1a41-4a45-b8ef-df780ea5dc20', 7.22::numeric),
    ('kfc-beff7c62-ef6c-41c8-8cbc-4d40e0d8c7cc', 17.86::numeric),
    ('kfc-31f6e4c1-87ec-4289-8631-cc3417d19827', 9.48::numeric),
    ('kfc-656ce732-e2ef-4665-94cd-e71d1788d37d', 8.02::numeric),
    ('kfc-a473d4f0-5368-409e-9b5a-5b9783ebbfb7', 7.94::numeric),
    ('kfc-0002ce75-7511-4ab8-b3b8-2beb114486c2', 7.78::numeric),
    ('kfc-475bed0f-878f-4b4f-8c5e-daa129be3130', 7.78::numeric),
    ('kfc-3260caef-60da-4607-9749-0282bd2e6a0f', 3.19::numeric),
    ('kfc-d565e908-aa77-4c0b-877a-ecd863016bc0', 2.82::numeric),
    ('kfc-cc17adc3-05bd-4cda-9a73-4445329586e6', 2.82::numeric),
    ('kfc-0197d73a-b694-497a-a97f-217a904b7513', 2.82::numeric),
    ('kfc-f089c612-13d8-4181-8150-48d79d18be5c', 2.82::numeric),
    ('kfc-a9188ac8-8e47-4339-aa4d-ad7290a27c66', 2.82::numeric),
    ('kfc-9e9f5e81-febd-4022-b7a8-9f4340110d20', 2.38::numeric),
    ('kfc-adebc7dc-854f-432a-a00b-a2b534ce5838', 6.98::numeric),
    ('kfc-bdae1148-c222-4b5e-8361-50ae72e00ef0', 6.49::numeric),
    ('kfc-dd7f7d7f-7a69-434d-a666-a8d90b4d9d00', 5.93::numeric),
    ('kfc-59023be5-a491-4fcf-b24b-f79f489adea1', 5.93::numeric),
    ('kfc-c4a2ca43-acd4-4bcd-88f9-47611eb857dc', 5.93::numeric),
    ('kfc-3c7039be-0b77-4193-ba5e-15b0c0ef0115', 5.93::numeric),
    ('kfc-c4130fa5-cba9-4bbc-9534-7ddfe4f0cf1c', 3.02::numeric),
    ('kfc-d69c9c1d-a2c1-4c57-a266-e0e8ba3daa8b', 3.02::numeric),
    ('kfc-0de34241-d4a9-4325-ba9e-2269a898f431', 2.86::numeric),
    ('kfc-b71a0bd4-3c70-442a-9c6b-5c01d2cb513d', 4.15::numeric),
    ('kfc-d2af12be-200e-4766-92a1-c05fcded8e88', 4.11::numeric),
    ('kfc-cc821190-83bf-4001-be4b-f7370fe5608d', 3.75::numeric),
    ('kfc-b84de246-4c2d-41be-afc3-9e318c56c25e', 3.75::numeric),
    ('kfc-f30a1cce-e177-4eda-abe3-005a5a2269f7', 3.75::numeric),
    ('kfc-bda9de4b-af8e-4d95-81c3-dc2b34cfb029', 3.19::numeric),
    ('kfc-a5a7520d-eece-4741-b3f4-6d71005f8136', 2.86::numeric),
    ('kfc-76e421ae-3c8a-439d-91cc-26a943a8300b', 2.62::numeric),
    ('kfc-3801d598-0bf2-4f17-ba54-03bd94f197b3', 2.41::numeric),
    ('kfc-f43e0544-d887-47ae-b5f5-60d4ef7f19a4', 2.41::numeric),
    ('kfc-fc723e30-2f46-4026-ad57-8843e86cd087', 2.38::numeric),
    ('kfc-3f3bac1d-8a22-46ee-81b4-dcebf07db447', 2.38::numeric),
    ('kfc-0dea50bb-2320-41ae-945d-7be9e25fef43', 2.38::numeric),
    ('kfc-a031be5d-fa02-4f23-bec1-7cd8b6099554', 1.57::numeric),
    ('kfc-55ffee2a-e811-4e52-8204-a7ef127e8c3b', 1.01::numeric),
    ('kfc-3e8ea96c-27b2-4ec2-9de3-7e9f2a5f0ece', 0.93::numeric),
    ('kfc-28592189-84ae-4dee-beb4-b559acf0a4a2', 0.93::numeric),
    ('kfc-b8f7bb73-a596-44b0-8aa6-74831ef1d072', 0.93::numeric),
    ('kfc-e9616d37-4ed2-40ca-8495-024392bc1ed4', 0.93::numeric),
    ('kfc-0e5be0f6-5567-4f9b-858e-906bcd74343e', 0.93::numeric),
    ('kfc-7256d369-dea9-4d1b-9e94-842384a7733d', 0.93::numeric),
    ('kfc-7b3c040e-c91a-465a-a61d-4364348a84a4', 0.93::numeric),
    ('kfc-97d4e35c-0e36-4d79-8bbc-5b57f4e750c9', 2.46::numeric),
    ('kfc-091f0149-566f-4c95-ace0-25defe6a90c5', 2.46::numeric),
    ('kfc-01cba396-046b-4cfe-b607-ad99162c507b', 2.46::numeric),
    ('kfc-7c6510e7-ecc2-4568-be7b-f11d00bbd358', 2.26::numeric),
    ('kfc-71efbb98-2978-4c93-b4cd-f25635156641', 2.26::numeric),
    ('kfc-dfd449c1-6a3d-4d46-8f58-54722ac4fda3', 2.26::numeric),
    ('kfc-5ab93251-c487-4fea-89a5-a996e0e2b009', 2.26::numeric),
    ('kfc-5b77bab0-62c1-4439-a152-ae9a18d8c449', 2.26::numeric),
    ('kfc-afdf79d4-932a-43cb-bfc8-7adc2a91dd5d', 2.26::numeric),
    ('kfc-224d94bd-9c58-438e-aa69-ab4cbedee9c9', 2.26::numeric),
    ('kfc-ef18fe86-bdb5-449d-86ff-c5032cce56de', 2.06::numeric),
    ('kfc-3e106ace-412e-4e9b-90c9-542ec8d665fa', 2.06::numeric),
    ('kfc-64193a8f-05bc-4ddd-bd71-714f8a9f90ec', 1.69::numeric),
    ('kfc-a637f084-fafd-4ab2-87ac-9d877c1b2e0f', 3.19::numeric),
    ('kfc-07f031f7-85f6-4496-a33e-ac0bce281222', 3.19::numeric),
    ('kfc-b9a43d49-e876-460e-a67c-704b7d1c659f', 3.19::numeric),
    ('kfc-1dc78ea8-c862-4fec-a198-e17ed96a0e09', 2.26::numeric),
    ('kfc-5abc2079-9423-425b-9153-71bf30078256', 2.26::numeric),
    ('kfc-a7a1c8c2-fa1b-490a-b7ea-b08bddd0e901', 2.26::numeric),
    ('kfc-8f36ac71-9435-4245-9abf-888222449d90', 7.46::numeric),
    ('kfc-d68be6b8-06c2-49c3-a237-32c9bf71136a', 7.46::numeric),
    ('kfc-f309538f-c66f-4464-bb28-3492db6dbe42', 6.98::numeric),
    ('kfc-d9b06837-bb89-4fa1-9054-1204b616a163', 6.49::numeric),
    ('kfc-08d2c32e-d93d-41bf-8e81-96abf0499bf8', 3.02::numeric),
    ('kfc-104f9743-e561-4295-b1a3-45f1b1ef365d', 2.26::numeric),
    ('kfc-af8ec0ae-180a-422f-8f97-857ca613af69', 1.57::numeric),
    ('kfc-0903b00a-9485-4d62-8bd1-bf6d3b749555', 2.26::numeric),
    ('kfc-a0f85b11-82e9-4e91-b60e-a1574d152f32', 2.26::numeric),
    ('kfc-4525e0b9-a77e-4694-b33a-beee6cd4ab29', 9.15::numeric),
    ('kfc-bbe0d74e-c93b-4eec-a513-cf6fa7c97945', 7.46::numeric),
    ('kfc-367ec05c-21a0-4f78-b364-3faad7196d21', 8.19::numeric),
    ('kfc-48f68bac-4ce1-4a58-9085-a98398bcc906', 8.19::numeric),
    ('kfc-a629106c-b169-4486-b4f4-8c3a0b051d8a', 3.19::numeric),
    ('kfc-e738508e-4e8b-4467-b31d-b8b2bc3fcfb9', 1.37::numeric),
    ('kfc-3202f966-c03f-4434-a09c-b62749c936bd', 3.19::numeric),
    ('kfc-5f75782f-85a7-45b2-a47f-dbba964d2cd8', 3.19::numeric),
    ('kfc-9a841120-6a57-46e6-9019-575d9491f912', 3.19::numeric),
    ('kfc-5c21a518-5239-4aee-87da-0cc8c6260d19', 3.19::numeric),
    ('kfc-46025b67-2313-47c0-9f93-15f7665e583d', 1.61::numeric),
    ('kfc-d00aaede-a529-4950-8dbf-46fe2d6fd753', 2.26::numeric),
    ('kfc-9b1f1fc4-872a-4668-ba74-a8b61aac70b2', 2.26::numeric),
    ('kfc-88d401f2-5a32-48ae-b261-29aeb7319e6a', 0.08::numeric),
    ('kfc-90d0b6cf-cb27-4878-8700-6db20785cb04', 0.24::numeric)
  ) as v(id, novo)
 where p.id = v.id and p.restaurant_id = 'kfc-guarda' and p.price < v.novo;

-- 4.2 Duplicados das bebidas: fica o nome limpo com o maior preço dos dois (nunca acima do Glovo);
--     o "V …" sai da loja (is_available=false; os pedidos antigos continuam a apontar para ele).
update public.products set price = least(2.00, greatest(price, (select price from public.products where id like 'kfc-aa770115%' limit 1), round(2.00 / 1.24, 2)))
 where id like 'kfc-46025b67%' and restaurant_id = 'kfc-guarda';
update public.products set is_available = false where id like 'kfc-aa770115%' and restaurant_id = 'kfc-guarda';
update public.products set price = least(3.05, greatest(price, (select price from public.products where id like 'kfc-fd1a6425%' limit 1), round(3.05 / 1.24, 2)))
 where id like 'kfc-97d4e35c%' and restaurant_id = 'kfc-guarda';
update public.products set is_available = false where id like 'kfc-fd1a6425%' and restaurant_id = 'kfc-guarda';

-- 4.3 Nomes de caixa → nomes de gente (o produto e os pedidos antigos ficam iguais)
update public.products set name = 'Pepsi Lata 33cl' where id like 'kfc-7c6510e7%' and name = 'V Pepsi Lata';
update public.products set name = 'Pepsi Zero Lata 33cl' where id like 'kfc-dfd449c1%' and name = 'V Pepsi Zero Lata';
update public.product_option_items poi set name = 'Red Bull Energy Drink'
  from public.product_option_groups pog join public.products p on p.id = pog.product_id
 where pog.id = poi.group_id and p.restaurant_id = 'kfc-guarda' and poi.name = 'Bull Energy Drink';

-- 4.4 Pepsi e Pepsi Zero (o balcão tem; nos menus faltavam) em todos os grupos de bebida dos menus,
--     com depósito Volta (lata). Preço: igual ao 7Up do mesmo grupo.
insert into public.product_option_items (group_id, name, price_add, is_available, sort_order, deposit_units, deposit_origem)
select pog.id, x.nome, sete.price_add, true, coalesce(sete.sort_order, 0) + x.ord, 1, 'regra'
  from public.product_option_groups pog
  join public.products p on p.id = pog.product_id and p.restaurant_id = 'kfc-guarda'
  join lateral (select poi.price_add, poi.sort_order from public.product_option_items poi
                 where poi.group_id = pog.id and poi.name = '7Up Lata 33cl' limit 1) sete on true
  cross join (values ('Pepsi Lata 33cl', 1), ('Pepsi Zero Lata 33cl', 2)) as x(nome, ord)
 where not exists (select 1 from public.product_option_items o2 where o2.group_id = pog.id and o2.name = x.nome);

-- Prova (SELECT)
select count(*) filter (where p.price > b.price) as subiram, count(*) filter (where p.price < b.price) as desceram
  from public.products p join public.bkp_products_kfc_volta_20261109 b on b.id = p.id;
