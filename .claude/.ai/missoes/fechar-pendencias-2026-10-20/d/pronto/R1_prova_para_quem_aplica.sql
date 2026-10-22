-- Prova do R1 para quem aplica (transação revertida: o RAISE do fim desfaz tudo, incluindo a troca da linha).
-- Correr ANTES de R1_aplicar.sql. Resultado esperado (escrito a 21/10/2026):
--   1_A_manda_user_id_V      -> dono_e_A true   (hoje: dono_e_V true — provado a 21/10, ver R1-LEIA.md)
--   2_A_sem_user_id          -> dono_e_A true   (é o que a app instalada faz: não manda user_id)
--   3_servidor_manda_V       -> dono_e_V true   (finalize-order-from-intent, cartão)
--   4_admin_manda_V          -> dono_e_V true
--   5_premio_vale_de_V       -> checkin_premio_sem_vale (o pedido passa a ser de A, que não tem vale); vale de V por_usar
--   igual_fora_da_linha      -> true
-- Todos os pedidos são de contas demo (o gatilho _pedido_demo_em_caixa_fechada põe-nos em teste, dinheiro,
-- estafeta demo). Nada sai da transação: os avisos por pg_net também são desfeitos.
DO $prova$
DECLARE
  v_a     uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  v_v     uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  v_admin uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_def    text := pg_get_functiondef('public.create_order(jsonb)'::regprocedure);
  v_ancora text := $a$  v_user_id := COALESCE((p_input->>'user_id')::UUID, auth.uid());$a$;
  v_nova   text := $n$  -- R1 (21/10/2026, "Vai" do Danilo): com sessao de cliente, o pedido e sempre de quem esta ligado.
  -- So o servidor (service_role, sem sessao) e o admin criam pedidos em nome de outra pessoa.
  v_user_id := CASE
                 WHEN auth.uid() IS NULL
                   OR public.is_admin()
                   OR COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
                 THEN COALESCE((p_input->>'user_id')::UUID, auth.uid())
                 ELSE auth.uid()
               END;$n$;
  v_aberto jsonb := jsonb_build_object('open','00:00','close','23:59','closed',false);
  v_in jsonb; v_norm jsonb; v_o jsonb; v_idv uuid; v_out jsonb := '{}'::jsonb; o record;
BEGIN
  IF md5(v_def) <> '8688fcf8b22429246079ec873d076fd8' THEN RAISE EXCEPTION 'create_order mudou desde 21/10'; END IF;
  EXECUTE replace(v_def, v_ancora, v_nova);
  v_out := v_out || jsonb_build_object('igual_fora_da_linha',
    replace(pg_get_functiondef('public.create_order(jsonb)'::regprocedure), v_nova, v_ancora) = v_def);
  UPDATE public.restaurants
     SET business_hours = jsonb_build_object('mon',v_aberto,'tue',v_aberto,'wed',v_aberto,'thu',v_aberto,'fri',v_aberto,'sat',v_aberto,'sun',v_aberto)
   WHERE id = 'sabores-brasil-guarda';
  v_norm := jsonb_build_object('service_type','restaurant','vendor_name','Sabores do Brasil - Keli Barbosa','is_partner_store',true,
    'payment_method','cash','distance_km',1.0,
    'pickup_lat',40.5323845,'pickup_lng',-7.2656677,'dropoff_lat',40.5373,'dropoff_lng',-7.2676,
    'pickup_address','R. Dom Manuel Vieira de Matos 25, Guarda','dropoff_address','Rua de prova, Guarda',
    'customer_name','Demo Bora','client_phone','920000000','customer_notes','Prova R1 (revertida)',
    'items', jsonb_build_array(jsonb_build_object('productId','09a9503f-1ef2-4a92-9486-e53848dc853c','name','Salgados Grandes','price',3.15,'basePrice',3.15,'quantity',2)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id','09a9503f-1ef2-4a92-9486-e53848dc853c','quantity',2,'unit_price',3.15)));
  v_in := v_norm || jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('product_id','premio-checkin-salgados','name','Prémio Bora Todo Dia: 2 Salgados Grandes','price',0,'basePrice',0,'quantity',1)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id','premio-checkin-salgados','quantity',1,'unit_price',0)));

  -- cliente A
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_o := public.create_order(v_norm || jsonb_build_object('user_id', v_v));
  SELECT * INTO o FROM public.orders WHERE id = v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('1_A_manda_user_id_V', jsonb_build_object('dono_e_A', o.user_id = v_a, 'dono_e_V', o.user_id = v_v));
  v_o := public.create_order(v_norm);
  SELECT * INTO o FROM public.orders WHERE id = v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('2_A_sem_user_id', jsonb_build_object('dono_e_A', o.user_id = v_a, 'preco', o.price));

  -- servidor (como a Edge finalize-order-from-intent, com a chave de servico: sem sessao de cliente)
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  v_o := public.create_order(v_norm || jsonb_build_object('user_id', v_v));
  SELECT * INTO o FROM public.orders WHERE id = v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('3_servidor_manda_V', jsonb_build_object('dono_e_V', o.user_id = v_v));

  -- admin
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com',
                                                             'app_metadata', json_build_object('role', 'admin'))::text, true);
  v_o := public.create_order(v_norm || jsonb_build_object('user_id', v_v));
  SELECT * INTO o FROM public.orders WHERE id = v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('4_admin_manda_V', jsonb_build_object('dono_e_V', o.user_id = v_v));

  -- premio: o vale e de V; A tenta usa-lo mandando user_id = V
  v_idv := (public.admin_checkin_premio_dar(v_v, 'salgados', 'prova R1 (revertida)') ->> 'id')::uuid;
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  BEGIN
    v_o := public.create_order(v_in || jsonb_build_object('user_id', v_v));
    v_out := v_out || jsonb_build_object('5_premio_vale_de_V', 'NAO RECUSOU ' || (v_o ->> 'order_id'));
  EXCEPTION WHEN OTHERS THEN v_out := v_out || jsonb_build_object('5_premio_vale_de_V', SQLSTATE || ' ' || left(SQLERRM, 80));
  END;
  v_out := v_out || jsonb_build_object('5_vale_de_V_depois', (SELECT estado FROM public.checkin_premios_vales WHERE id = v_idv));
  RAISE EXCEPTION 'RESULT %', v_out::text;
END $prova$;
