
  -- ===== DEPOIS =====
  v_depois := pg_temp.n3b_bateria(v_cw);

  -- ===== DEFEITO PLANTADO 1: a guarda dos pedidos "esquece" o estafeta → o ataque o4 tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_recusa(o public.orders, n public.orders)
  RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $d1$
  DECLARE v_uid uuid := auth.uid();
  BEGIN
    IF v_uid IS NULL OR o.user_id IS DISTINCT FROM v_uid THEN RETURN NULL; END IF;
    IF public.is_admin() THEN RETURN NULL; END IF;
    IF n.restaurant_id IS DISTINCT FROM o.restaurant_id THEN RETURN 'restaurant_id'; END IF;
    RETURN NULL;  -- DEFEITO: sem as colunas do estafeta
  END $d1$;
  v_defeito := v_defeito || jsonb_build_object('d1_sem_estafeta_o4', pg_temp.n3b_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'cliente',
    $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  v_defeito := v_defeito || jsonb_build_object('d1_loja_continua_o1', pg_temp.n3b_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'cliente',
    $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));

  -- ===== DEFEITO PLANTADO 2: a guarda das lavagens deixa passar o total → o ataque c2 tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $d2$
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN RETURN NEW; END IF;
    IF NEW.photos_client IS DISTINCT FROM OLD.photos_client AND auth.uid() IS DISTINCT FROM OLD.client_user_id THEN
      RAISE EXCEPTION 'lavagem_fotos_so_do_cliente' USING ERRCODE = '42501';
    END IF;
    IF (to_jsonb(NEW) - 'photos_client' - 'updated_at' - 'total_cents') IS DISTINCT FROM
       (to_jsonb(OLD) - 'photos_client' - 'updated_at' - 'total_cents') THEN  -- DEFEITO: total_cents fora
      RAISE EXCEPTION 'lavagem_so_pelo_servidor' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $d2$;
  v_defeito := v_defeito || jsonb_build_object('d2_total_fora_c2', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    format($$UPDATE public.carwash_bookings SET total_cents = 1 WHERE id = %L$$, v_cw::text)));
  v_defeito := v_defeito || jsonb_build_object('d2_ganho_continua_c4', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, v_cw::text)));

  -- ===== DEFEITO PLANTADO 3: a guarda das lavagens deixa qualquer um mexer nas fotos → o ataque c9 tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $d3$
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN RETURN NEW; END IF;
    -- DEFEITO: sem a regra "fotos só do cliente"
    IF (to_jsonb(NEW) - 'photos_client' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'photos_client' - 'updated_at') THEN
      RAISE EXCEPTION 'lavagem_so_pelo_servidor' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $d3$;
  v_defeito := v_defeito || jsonb_build_object('d3_fotos_livres_c9', pg_temp.n3b_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'cliente',
    format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, v_cw::text)));
  v_defeito := v_defeito || jsonb_build_object('d3_ganho_continua_c6', pg_temp.n3b_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'cliente',
    format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, v_cw::text)));

  -- ===== DEFEITO PLANTADO 4: a guarda do INSERT "esquece" os estafetas excluídos → o ataque o9b tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_guarda()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $d4$
  DECLARE v_motivo text;
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' THEN
      IF public.is_admin() THEN RETURN NEW; END IF;
      v_motivo := CASE WHEN NEW.assigned_driver_id IS NOT NULL THEN 'assigned_driver_id' END;  -- DEFEITO: só o estafeta
    ELSE
      v_motivo := public._pedido_cliente_loja_estafeta_recusa(OLD, NEW);
    END IF;
    IF v_motivo IS NOT NULL THEN
      RAISE EXCEPTION 'pedido_loja_estafeta_so_pelo_servidor (%)', v_motivo USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $d4$;
  v_defeito := v_defeito || jsonb_build_object('d4_insert_sem_excluidos_o9b', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}') RETURNING status$$));
  v_defeito := v_defeito || jsonb_build_object('d4_estafeta_continua_o9d', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, assigned_driver_id)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002') RETURNING status$$));

  -- ===== Veredicto mecânico =====
  -- ataques: chaves o<n>[letra]_ataque / c<n>_ataque · legítimos: l<n>_ e c1/c7/c8 · vazios (não provam nada, só se
  -- mostra que ficaram iguais): v<n>_
  v_out := v_out || jsonb_build_object(
    'antes', v_antes,
    'depois', v_depois,
    'defeito', v_defeito,
    'ataques_passavam_antes', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v LIKE 'PASSOU (1)%'),
    'ataques_ja_travados_antes_por_outra_regra', (SELECT jsonb_agg(k || '=' || v ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v NOT LIKE 'PASSOU (1)%'),
    'ataques_recusados_depois', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_depois) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v LIKE '42501 %'),
    'ataques_NAO_recusados_depois', (SELECT jsonb_agg(k || '=' || v ORDER BY k) FROM jsonb_each_text(v_depois) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v NOT LIKE '42501 %'),
    'legitimos_que_passam_e_iguais', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v)
                          WHERE (k ~ '^l[0-9]+_' OR k ~ '^c[178]_') AND v LIKE 'PASSOU (1)%' AND v = v_depois ->> k),
    'legitimos_MUDARAM_ou_nao_passam', (SELECT jsonb_agg(k || ': ' || v || ' -> ' || (v_depois ->> k) ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v)
                          WHERE (k ~ '^l[0-9]+_' OR k ~ '^c[178]_') AND (v NOT LIKE 'PASSOU (1)%' OR v IS DISTINCT FROM v_depois ->> k)),
    'vazios_iguais', (SELECT jsonb_agg(k || ': ' || v ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^v[0-9]+_' AND v = v_depois ->> k),
    'vazios_MUDARAM', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^v[0-9]+_' AND v IS DISTINCT FROM v_depois ->> k),
    'defeito_apanhado',
         (v_defeito ->> 'd1_sem_estafeta_o4') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd1_loja_continua_o1') LIKE '42501 %'
     AND (v_defeito ->> 'd2_total_fora_c2') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd2_ganho_continua_c4') LIKE '42501 %'
     AND (v_defeito ->> 'd3_fotos_livres_c9') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd3_ganho_continua_c6') LIKE '42501 %'
     AND (v_defeito ->> 'd4_insert_sem_excluidos_o9b') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd4_estafeta_continua_o9d') LIKE '42501 %');
  RAISE EXCEPTION 'RESULT %', v_out::text;
END
$prova$;
