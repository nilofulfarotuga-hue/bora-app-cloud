
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

  -- ===== Veredicto mecânico =====
  v_out := v_out || jsonb_build_object(
    'antes', v_antes,
    'depois', v_depois,
    'defeito', v_defeito,
    'ataques_passavam_antes', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE (k LIKE 'o_\_ataque%' OR k LIKE 'c_\_ataque%') AND v LIKE 'PASSOU (1)'),
    'ataques_recusados_depois', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_depois) e(k, v) WHERE (k LIKE 'o_\_ataque%' OR k LIKE 'c_\_ataque%') AND v LIKE '42501 %'),
    'ataques_NAO_recusados_depois', (SELECT jsonb_agg(k || '=' || v ORDER BY k) FROM jsonb_each_text(v_depois) e(k, v) WHERE (k LIKE 'o_\_ataque%' OR k LIKE 'c_\_ataque%') AND v NOT LIKE '42501 %'),
    'legitimos_iguais', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE (k LIKE 'l_\_%' OR k LIKE 'c1\_%' OR k LIKE 'c7\_%' OR k LIKE 'c8\_%')
                          AND v = v_depois ->> k),
    'legitimos_MUDARAM', (SELECT jsonb_agg(k || ': ' || v || ' -> ' || (v_depois ->> k) ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v)
                          WHERE (k LIKE 'l_\_%' OR k LIKE 'c1\_%' OR k LIKE 'c7\_%' OR k LIKE 'c8\_%') AND v IS DISTINCT FROM v_depois ->> k),
    'defeito_apanhado', (v_defeito ->> 'd1_sem_estafeta_o4') LIKE 'PASSOU (1)' AND (v_defeito ->> 'd2_total_fora_c2') LIKE 'PASSOU (1)'
                        AND (v_defeito ->> 'd1_loja_continua_o1') LIKE '42501 %' AND (v_defeito ->> 'd2_ganho_continua_c4') LIKE '42501 %');
  RAISE EXCEPTION 'RESULT %', v_out::text;
END
$prova$;
