DO $prova$
DECLARE
  v_a     uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  v_v     uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  v_t     uuid := '183a32cd-d570-447a-a86d-a86c2a6845d6';
  v_admin uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_drv   uuid := 'dede0000-0000-4000-8000-000000000001';
  v_keli  uuid := 'd4262a65-3c1a-4ba4-8f38-76dfb9916fd7';
  v_aberto jsonb := jsonb_build_object('open','00:00','close','23:59','closed',false);
  v_norm jsonb; v_o jsonb; o record; v_out jsonb := '{}'::jsonb; v_n bigint;
  v_pa text; v_pt text; v_pt2 text; v_pt3 text;
BEGIN
  UPDATE public.restaurants
     SET business_hours = jsonb_build_object('mon',v_aberto,'tue',v_aberto,'wed',v_aberto,'thu',v_aberto,'fri',v_aberto,'sat',v_aberto,'sun',v_aberto)
   WHERE id = 'sabores-brasil-guarda';
  v_norm := jsonb_build_object('service_type','restaurant','vendor_name','Sabores do Brasil - Keli Barbosa','is_partner_store',true,
    'payment_method','cash','distance_km',1.0,
    'pickup_lat',40.5323845,'pickup_lng',-7.2656677,'dropoff_lat',40.5373,'dropoff_lng',-7.2676,
    'pickup_address','R. Dom Manuel Vieira de Matos 25, Guarda','dropoff_address','Rua de prova, Guarda',
    'customer_name','Prova ronda 2','client_phone','920000000','customer_notes','Prova ronda 2 (revertida)',
    'items', jsonb_build_array(jsonb_build_object('productId','09a9503f-1ef2-4a92-9486-e53848dc853c','name','Salgados Grandes','price',3.15,'basePrice',3.15,'quantity',2)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id','09a9503f-1ef2-4a92-9486-e53848dc853c','quantity',2,'unit_price',3.15)));

  -- ===== R1 =====
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_o := public.create_order(v_norm || jsonb_build_object('user_id', v_v));
  SELECT * INTO o FROM public.orders WHERE id = v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('R1_1_A_manda_o_id_de_V', CASE WHEN o.user_id = v_a THEN 'fica no nome de A' WHEN o.user_id = v_v THEN 'fica no nome de V (MAU)' ELSE 'outro' END);
  v_o := public.create_order(v_norm);
  v_pa := v_o ->> 'order_id';
  SELECT * INTO o FROM public.orders WHERE id = v_pa;
  v_out := v_out || jsonb_build_object('R1_2_A_cria_o_seu', jsonb_build_object('dono_A', o.user_id = v_a, 'estado', o.status, 'preco', o.price));

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  v_o := public.create_order(v_norm || jsonb_build_object('user_id', v_t));
  v_pt := v_o ->> 'order_id';
  SELECT * INTO o FROM public.orders WHERE id = v_pt;
  v_out := v_out || jsonb_build_object('R1_3_servidor_chave_de_servico_manda_T', jsonb_build_object('dono_T', o.user_id = v_t, 'estado', o.status));

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com',
                                                             'app_metadata', json_build_object('role', 'admin'))::text, true);
  v_o := public.create_order(v_norm || jsonb_build_object('user_id', v_v));
  SELECT * INTO o FROM public.orders WHERE id = v_o ->> 'order_id';
  v_out := v_out || jsonb_build_object('R1_4_admin_manda_V', CASE WHEN o.user_id = v_v THEN 'fica no nome de V' ELSE 'outro (MAU)' END);

  PERFORM set_config('request.jwt.claim.sub', v_t::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_t, 'role', 'authenticated')::text, true);
  v_o := public.create_order(v_norm);
  v_pt2 := v_o ->> 'order_id';
  SELECT * INTO o FROM public.orders WHERE id = v_pt2;
  v_out := v_out || jsonb_build_object('R1_5_cliente_T_cria_o_seu', jsonb_build_object('dono_T', o.user_id = v_t, 'estado', o.status, 'preco', o.price, 'a_cobrar', o.cash_total_due));
  v_o := public.create_order(v_norm);
  v_pt3 := v_o ->> 'order_id';

  -- ===== R2: o cliente T no seu pedido (created, restaurante parceiro), escrita direta como a API =====
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'preparing' WHERE id = v_pt2;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_a_T_aceita_ele_proprio_o_pedido_da_loja', 'NAO RECUSOU (' || v_n || ')');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_a_T_aceita_ele_proprio_o_pedido_da_loja', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'rejected' WHERE id = v_pt2;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_b_T_poe_rejected', 'NAO RECUSOU (' || v_n || ')');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_b_T_poe_rejected', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'delivered' WHERE id = v_pt2;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_c_T_poe_delivered', 'NAO RECUSOU (' || v_n || ')');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_c_T_poe_delivered', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET payment_status = 'paid' WHERE id = v_pt2;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_d_T_poe_pago', 'NAO RECUSOU (' || v_n || ')');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_d_T_poe_pago', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET cash_total_due = 0 WHERE id = v_pt2;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_e_T_poe_0_euros_a_cobrar', 'NAO RECUSOU (' || v_n || ')');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_e_T_poe_0_euros_a_cobrar', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET customer_notes = 'tocar a campainha' WHERE id = v_pt2;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_f_T_muda_as_notas', v_n || ' linha');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_f_T_muda_as_notas', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;

  -- a loja aceita e marca pronto pelas funcoes dela
  PERFORM set_config('request.jwt.claim.sub', v_keli::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_keli, 'role', 'authenticated')::text, true);
  PERFORM public.partner_accept_order(v_pt2);
  v_out := v_out || jsonb_build_object('R2_g_loja_aceita', (SELECT status FROM public.orders WHERE id = v_pt2));

  -- o servidor cancela antes de o estafeta aceitar (como a Edge client-cancel-order, com a chave de servico)
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  BEGIN
    SET LOCAL ROLE service_role;
    UPDATE public.orders SET status = 'cancelled', cancelled_at = now() WHERE id = v_pt3;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_h_servidor_cancela_antes_de_aceite', v_n || ' linha');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_h_servidor_cancela_antes_de_aceite', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;

  -- o admin cancela pela funcao dele
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com',
                                                             'app_metadata', json_build_object('role', 'admin'))::text, true);
  PERFORM public.admin_cancel_order(v_pt::uuid, 'client_request', 'prova ronda 2 (revertida)');
  v_out := v_out || jsonb_build_object('R2_i_admin_cancela', (SELECT status FROM public.orders WHERE id = v_pt));

  -- o estafeta demo leva o pedido de A (recolhe pela funcao, a caminho por escrita direta, entrega em dinheiro)
  PERFORM set_config('request.jwt.claim.sub', v_drv::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv, 'role', 'authenticated')::text, true);
  PERFORM public.driver_advance_order(v_pa, 'pickedUp');
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'onTheWay' WHERE id = v_pa;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_j_estafeta_a_caminho_escrita_direta', v_n || ' linha');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_j_estafeta_a_caminho_escrita_direta', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;
  PERFORM public.driver_finish_cash_order(v_pa);
  SELECT * INTO o FROM public.orders WHERE id = v_pa;
  v_out := v_out || jsonb_build_object('R2_k_estafeta_entrega', o.status || '/' || o.payment_status);

  -- o cliente A tenta desfazer o pedido entregue
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.orders SET status = 'rejected' WHERE id = v_pa;
    GET DIAGNOSTICS v_n = ROW_COUNT; RESET ROLE;
    v_out := v_out || jsonb_build_object('R2_l_A_poe_rejected_no_entregue', 'NAO RECUSOU (' || v_n || ')');
  EXCEPTION WHEN OTHERS THEN RESET ROLE; v_out := v_out || jsonb_build_object('R2_l_A_poe_rejected_no_entregue', SQLSTATE || ' ' || left(SQLERRM, 90));
  END;

  -- ===== F7 =====
  v_out := v_out || jsonb_build_object('F7_A_com_pedido_entregue_pelo_estafeta', public._checkin_teve_pedido_pago(v_a, 30),
                                       'F7_T_sem_nada_entregue', public._checkin_teve_pedido_pago(v_t, 30));
  RAISE EXCEPTION 'RESULT %', v_out::text;
END $prova$;
