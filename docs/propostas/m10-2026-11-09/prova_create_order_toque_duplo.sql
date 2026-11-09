-- Prova em ROLLBACK do embrulho do create_order (M10 09/11/2026). Corre-se no MESMO envio que a migracao
-- 20261109060000: a excecao do fim desfaz tudo (migracao, pedidos de teste, fila do pg_net).
-- Cliente e loja de demonstracao (_modo_demo_def), so dinheiro.
do $prova$
declare
  v_def jsonb := public._modo_demo_def();
  v_uid uuid := (v_def->>'cliente_user_id')::uuid;
  v_r record; v_in jsonb; v_in2 jsonb; r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
  n_antes int; n_depois int; n_cadeado int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  -- A loja de demonstracao estava fechada a hora da prova: so a guarda de loja fechada le esta definicao
  -- (confirmado por pg_trigger), e tudo se desfaz no fim.
  perform set_config('app.parceiro_chama_estafeta', 'on', true);
  select id, name, lat, lng, address into v_r from public.restaurants where id = v_def->>'restaurant_id';
  v_in := jsonb_build_object(
    'service_type', 'restaurant', 'vendor_name', v_r.name, 'is_partner_store', true, 'distance_km', 0.8,
    'payment_method', 'cash', 'subtotal', 1.17, 'apartment_delivery', false, 'order_type', 'partnerRestaurant',
    'bag_count', 1, 'requires_car', false, 'wallet_applied_cents', 0,
    'pickup_lat', v_r.lat, 'pickup_lng', v_r.lng, 'pickup_address', v_r.address,
    'dropoff_lat', 40.5373, 'dropoff_lng', -7.2676, 'dropoff_address', 'Praca Luis de Camoes, Guarda (prova M10)',
    'dropoff_street', 'Praca Luis de Camoes', 'dropoff_city', 'Guarda',
    'customer_name', 'Cliente Demonstracao', 'customer_notes', 'PROVA M10 toque duplo (rollback)',
    'items', jsonb_build_array(jsonb_build_object('name', 'Maionese caseira', 'price', 1.17, 'quantity', 1,
              'basePrice', 1.17, 'productId', 'boom-maionese-caseira-extra', 'purchaseStatus', 'pending',
              'selected_options', '[]'::jsonb)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id', 'boom-maionese-caseira-extra',
              'quantity', 1, 'unit_price', 1.17, 'name', 'Maionese caseira')));
  v_in2 := jsonb_set(jsonb_set(v_in, '{product_lines,0,quantity}', '2'), '{items,0,quantity}', '2');

  select count(*) into n_antes from public.orders where user_id = v_uid;
  r1 := public.create_order(v_in);
  r2 := public.create_order(v_in);    -- toque duplo: tem de devolver o mesmo pedido
  r3 := public.create_order(v_in2);   -- pedido diferente: tem de criar outro
  select count(*) into n_depois from public.orders where user_id = v_uid;

  -- sem cliente (service_role / Edge do Stripe): vai direto ao corpo, nao escreve na tabela
  perform set_config('request.jwt.claims', '', true);
  select count(*) into n_cadeado from public.create_order_recentes;

  raise exception 'PROVA_OK %', jsonb_build_object(
    'r1_id', r1->>'order_id', 'r2_id', r2->>'order_id', 'r2_repetido', r2->>'repetido',
    'r3_id', r3->>'order_id', 'r1_price', r1->>'price', 'r3_price', r3->>'price',
    'pedidos_novos', n_depois - n_antes, 'linhas_recentes', n_cadeado,
    'promocoes_prontas', public._promotions_server_ready(),
    'core_existe', to_regprocedure('public._create_order_core(jsonb)') is not null,
    'anon_core', has_function_privilege('anon', 'public._create_order_core(jsonb)', 'execute'),
    'auth_core', has_function_privilege('authenticated', 'public._create_order_core(jsonb)', 'execute'),
    'auth_embrulho', has_function_privilege('authenticated', 'public.create_order(jsonb)', 'execute'),
    'anon_embrulho', has_function_privilege('anon', 'public.create_order(jsonb)', 'execute'));
end $prova$;

-- Saida literal (09/11/2026 ~00:23, antes de aplicar, migracao + prova no mesmo envio):
-- ERROR: P0001: PROVA_OK {"r1_id": "caa40b8f-6fc5-47d6-a6ce-208a03a496a2", "r2_id": "caa40b8f-6fc5-47d6-a6ce-208a03a496a2",
--   "r3_id": "f79fe041-96b9-4dbd-b7af-69d5c818217a", "r1_price": "4.03", "r3_price": "5.26", "anon_core": false,
--   "auth_core": false, "core_existe": true, "r2_repetido": "true", "anon_embrulho": false, "auth_embrulho": true,
--   "pedidos_novos": 2, "linhas_recentes": 2, "promocoes_prontas": true}
-- Depois de aplicar (versao 20261109002344): md5 do corpo com o nome antigo = 70a937fdc7e9926d19772f04f0a070c6
-- (igual ao create_order de antes), _promotions_server_ready() = true, create_order_recentes com RLS.
