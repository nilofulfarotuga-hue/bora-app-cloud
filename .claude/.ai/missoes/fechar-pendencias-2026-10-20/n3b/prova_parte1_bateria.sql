DO $prova$
DECLARE
  v_antes  jsonb;
  v_depois jsonb;
  v_defeito jsonb := '{}'::jsonb;
  v_out    jsonb := '{}'::jsonb;
  v_cw     uuid := gen_random_uuid();
BEGIN
  -- ===== Ajudante: corre UMA escrita como a API (cliente, admin ou servidor) e desfaz logo =====
  CREATE FUNCTION pg_temp.n3b_tenta(p_uid uuid, p_tipo text, p_sql text) RETURNS text
  LANGUAGE plpgsql AS $f$
  DECLARE n bigint; v_ret text;
  BEGIN
    IF p_tipo = 'servidor' THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      PERFORM set_config('request.jwt.claims', json_build_object('role','service_role')::text, true);
    ELSIF p_tipo = 'admin' THEN
      PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email','nilofulfarotuga@gmail.com','app_metadata',json_build_object('role','admin'))::text, true);
    ELSE
      PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated')::text, true);
    END IF;
    BEGIN
      IF p_tipo = 'servidor' THEN SET LOCAL ROLE service_role; ELSE SET LOCAL ROLE authenticated; END IF;
      IF p_sql ILIKE '%RETURNING%' THEN EXECUTE p_sql INTO v_ret; ELSE EXECUTE p_sql; END IF;
      GET DIAGNOSTICS n = ROW_COUNT;
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__PASSOU__' || n || COALESCE(') ' || v_ret, ')');
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE '__PASSOU__%' THEN RETURN 'PASSOU (' || substr(SQLERRM, 11); END IF;
      RETURN SQLSTATE || ' ' || left(SQLERRM, 110);
    END;
  END $f$;

  -- ===== A bateria: ataques (devem passar ANTES e dar 42501 DEPOIS) e caminhos legítimos (iguais antes e depois) =====
  -- A = demo@bora.app d5b0c0a1 (dono de ORD 4a3bb2ca, mercado não parceiro), V = e3c166d2 (dono de ORDP ec0506ef,
  -- restaurante parceiro), T = 183a32cd (cliente de teste, dono da lavagem de prova), estafeta demo dede…0001/…0002,
  -- lavador W = 4f61dd31 (lavador "Danilo" 231e1c82, não é admin), admin = c9fccf85.
  CREATE FUNCTION pg_temp.n3b_bateria(p_cw uuid) RETURNS jsonb
  LANGUAGE plpgsql AS $b$
  DECLARE
    A uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
    V uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
    T uuid := '183a32cd-d570-447a-a86d-a86c2a6845d6';
    D uuid := 'dede0000-0000-4000-8000-000000000001';
    W uuid := '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7';
    ADM uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
    r jsonb := '{}'::jsonb;
    cw text := p_cw::text;
  BEGIN
    -- pedidos: ataques do dono
    r := r || jsonb_build_object('o1_ataque_dono_muda_loja', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o2_ataque_dono_tira_parceiro', pg_temp.n3b_tenta(V, 'cliente',
      $$UPDATE public.orders SET is_partner_store = false WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'$$));
    r := r || jsonb_build_object('o3_ataque_dono_muda_nome_loja', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET vendor_name = 'Loja falsa' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o4_ataque_dono_poe_estafeta', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o5_ataque_dono_poe_oferta', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET current_driver_offer_id = 'dede0000-0000-4000-8000-000000000001', driver_offer_expires_at = now() + interval '1 minute' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o6_ataque_dono_pre_atribui', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET preassigned_driver_id = 'dede0000-0000-4000-8000-000000000002' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o7_ataque_dono_exclui_estafetas', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET tried_driver_ids = '{dede0000-0000-4000-8000-000000000002}' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o8_ataque_dono_poe_ajudante', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET helper_driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o9_ataque_cliente_cria_ja_com_estafeta', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, restaurant_id, vendor_name, is_partner_store, price, payment_method, is_test_order, assigned_driver_id, driver_id)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'storeShopping', 'continente-guarda', 'Continente', false, 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002', 'dede0000-0000-4000-8000-000000000001')$$));
    r := r || jsonb_build_object('o9b_ataque_cliente_cria_com_estafetas_excluidos', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}') RETURNING status$$));
    r := r || jsonb_build_object('o9c_ataque_cliente_cria_com_oferta_e_historico', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, driver_offer_expires_at, driver_offer_history)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, now() + interval '1 hour', '[{"x":1}]'::jsonb) RETURNING status$$));
    r := r || jsonb_build_object('o9d_ataque_cliente_cria_pacote_com_estafeta', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, assigned_driver_id)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002') RETURNING status$$));
    r := r || jsonb_build_object('l10_cliente_cria_pacote_sem_estafeta_chega_ao_fim', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true) RETURNING status || ' tried=' || coalesce(tried_driver_ids::text,'-') || ' hist=' || coalesce(driver_offer_history::text,'-')$$));
    r := r || jsonb_build_object('l11_demo_cria_pacote_fica_com_estafeta_demo', pg_temp.n3b_tenta(A, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
        VALUES ('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'created', 'sendPackage', 10, 'cash', true) RETURNING status || ' drv=' || coalesce(assigned_driver_id, '-') || '/' || coalesce(driver_id::text, '-')$$));
    -- pedidos: caminhos legítimos
    r := r || jsonb_build_object('l1_dono_muda_notas', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET customer_notes = 'nota de prova N3b' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('l2_dono_created_para_preparing', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET status = 'preparing' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('v3_vazio_cliente_cria_com_loja_fechada_as_5h', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, restaurant_id, vendor_name, is_partner_store, price, payment_method, is_test_order)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'storeShopping', 'continente-guarda', 'Continente', false, 10, 'cash', true)$$));
    r := r || jsonb_build_object('l4_servidor_muda_loja', pg_temp.n3b_tenta(NULL, 'servidor',
      $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('v5_vazio_admin_sem_politica_update_em_orders', pg_temp.n3b_tenta(ADM, 'admin',
      $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('v6_vazio_cancelDelivery_codigo_morto_ja_RLS', pg_temp.n3b_tenta(D, 'cliente',
      $$UPDATE public.orders SET assigned_driver_id = NULL, current_driver_offer_id = NULL, driver_offer_expires_at = NULL, status = 'callingDriver', tried_driver_ids = '{dede0000-0000-4000-8000-000000000002}' WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'$$));
    r := r || jsonb_build_object('l7_estafeta_manda_localizacao', pg_temp.n3b_tenta(D, 'cliente',
      $$UPDATE public.orders SET driver_lat = 40.5373, driver_lng = -7.2676 WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'$$));
    r := r || jsonb_build_object('l8_dono_V_muda_notas_no_pedido_parceiro', pg_temp.n3b_tenta(V, 'cliente',
      $$UPDATE public.orders SET customer_notes = 'nota V' WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'$$));
    -- o dono que é o estafeta que aceitou (histórico que o cliente não escreve) continua livre, como no R2
    INSERT INTO public.order_status_events (order_id, from_status, to_status, actor_uid, source)
      VALUES ('4a3bb2ca-4fad-40c6-897c-a8827c6c8754', 'callingDriver', 'driverAccepted', A, 'prova_n3b');
    r := r || jsonb_build_object('l9_dono_que_aceitou_como_estafeta', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    DELETE FROM public.order_status_events WHERE order_id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754' AND source = 'prova_n3b';

    -- lavagens (T é o cliente da lavagem de prova; W é o lavador)
    r := r || jsonb_build_object('c1_cliente_anexa_foto', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET photos_client = '["prova-n3b.jpg"]'::jsonb WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c2_ataque_cliente_muda_total', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET total_cents = 1 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c3_ataque_cliente_marca_concluida', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET status = 'completed' WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c4_ataque_cliente_muda_ganho_lavador', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c5_ataque_cliente_marca_pago', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET payment_status = 'paid' WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c6_ataque_lavador_muda_ganho', pg_temp.n3b_tenta(W, 'cliente',
      format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c9_ataque_lavador_troca_foto_do_cliente', pg_temp.n3b_tenta(W, 'cliente',
      format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c7_admin_muda_total', pg_temp.n3b_tenta(ADM, 'admin',
      format($$UPDATE public.carwash_bookings SET total_cents = 2100 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c8_servidor_marca_concluida', pg_temp.n3b_tenta(NULL, 'servidor',
      format($$UPDATE public.carwash_bookings SET status = 'completed' WHERE id = %L$$, cw)));
    RETURN r;
  END $b$;

  -- ===== Preparação (como o servidor, para a auditoria de estafeta não ler "SQL direto") =====
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role','service_role')::text, true);
  UPDATE public.orders SET status = 'created', assigned_driver_id = NULL, driver_id = NULL, current_driver_offer_id = NULL,
         preassigned_driver_id = NULL, helper_driver_id = NULL
   WHERE id IN ('4a3bb2ca-4fad-40c6-897c-a8827c6c8754', 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03');
  UPDATE public.orders SET status = 'driverAccepted', assigned_driver_id = 'dede0000-0000-4000-8000-000000000002',
         driver_id = 'dede0000-0000-4000-8000-000000000001'
   WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49';
  INSERT INTO public.carwash_bookings
    SELECT (jsonb_populate_record(NULL::public.carwash_bookings, to_jsonb(b) || jsonb_build_object(
      'id', v_cw, 'client_user_id', '183a32cd-d570-447a-a86d-a86c2a6845d6', 'is_test_order', true,
      'status', 'scheduled', 'washer_id', '231e1c82-8f49-4d6c-bb30-349e91b6cc26', 'payment_status', 'cash_pending',
      'cancelled_at', NULL, 'cancelled_by', NULL, 'cancel_reason', NULL))).*
      FROM public.carwash_bookings b WHERE b.id = '03e96507-408f-471f-bc03-44eb193a08d0';
  v_out := v_out || jsonb_build_object('preparacao', jsonb_build_object(
    'ord', (SELECT status || '/' || coalesce(assigned_driver_id,'-') FROM public.orders WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'),
    'ordp', (SELECT status || '/parceiro=' || is_partner_store FROM public.orders WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'),
    'ordd', (SELECT status || '/' || assigned_driver_id FROM public.orders WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'),
    'lavagem', (SELECT status || '/' || total_cents FROM public.carwash_bookings WHERE id = v_cw)));

  -- ===== ANTES (como está no ar) =====
  v_antes := pg_temp.n3b_bateria(v_cw);

  -- ===== Aplicar as duas migrações (texto igual aos ficheiros, colado pelo gerador) =====
