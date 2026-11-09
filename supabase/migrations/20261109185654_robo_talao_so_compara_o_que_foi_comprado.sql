-- 20261109185654_robo_talao_so_compara_o_que_foi_comprado: aplicada em produção a 09/11/2026 e escrita no repo a partir de
-- supabase_migrations.schema_migrations.statements (missão pendencias-2026-11-09).
-- 09/11/2026 18:55, Danilo autorizou (3) no pedido da Dona Isabel (b2261d50):
-- a) o robo do talao casou o vinho Vermelhusco (acrescentado) com o Cacho Fresco (em falta)
--    e subiu o preco do Cacho Fresco. Agora so compara com o que foi MESMO comprado
--    (tira os produtos marcados "Nao ha" ou trocados).
-- b) regra dele: "sempre que tiver o preco maior na prateleira, tem que subir". O robo deixava
--    escapar os ovos (talao escreve "OVOS DE SOLO..." em vez de "Ovos Classe...") e a pota
--    (o estafeta acrescentou uma lata, a quantidade deixou de bater). Segunda volta: so para
--    o que ficou sem par, sem exigir a mesma quantidade, nome parecido (>= 0,40) E preco da
--    linha a menos de 25% do preco de balcao da app (para nao casar produtos diferentes).
CREATE OR REPLACE FUNCTION public.catalog_price_update_from_receipt(p_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_r          record;
  v_order      record;
  v_m          jsonb;
  v_prod       record;
  v_new_unit   numeric(12,2);
  v_expected   numeric(12,2);
  v_new_base   numeric(12,2);
  v_aplicadas  int := 0;
  v_pendentes  int := 0;
  v_sem_match  int := 0;
  v_iguais     int := 0;
  v_segunda    int := 0;
  v_extras     jsonb := '[]'::jsonb;
  v_enabled    boolean;
  v_feitos     text[] := '{}';
  v_items      jsonb;
  v_lines      jsonb;
  v_n          int;
  v_usadas_nomes text[] := '{}';
  v_usadas_idx int[] := '{}';
  v_sem_par    int[] := '{}';
  v_k          int;
  v_item       jsonb;
  v_line       jsonb;
  v_nome       text;
  v_ln         text;
  v_sim        numeric;
  v_bsim       numeric;
  v_bidx       int;
  v_up         int;
  j            int;
BEGIN
  SELECT (value::text IN ('true', '"true"')) INTO v_enabled
    FROM platform_settings WHERE key = 'catalog_price_live_update_enabled';
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'kill_switch_off');
  END IF;

  SELECT r.id, r.order_id, r.receipt_parsed INTO v_r FROM order_receipts_v2 r WHERE r.id = p_receipt_id;
  IF v_r.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'receipt_not_found'); END IF;
  IF v_r.receipt_parsed IS NULL
     OR jsonb_typeof(v_r.receipt_parsed->'lines') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_r.receipt_parsed->'lines') = 0 THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'sem_linhas_no_talao');
  END IF;
  v_lines := v_r.receipt_parsed->'lines';
  v_n := jsonb_array_length(v_lines);

  SELECT o.id, o.restaurant_id, o.is_partner_store, o.items INTO v_order FROM orders o WHERE o.id = v_r.order_id;
  IF v_order.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'order_not_found'); END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN RETURN jsonb_build_object('ok', true, 'skipped', 'loja_parceira'); END IF;

  -- (a) so o que foi MESMO comprado: fora o que o estafeta marcou "Nao ha" ou trocou.
  SELECT COALESCE(jsonb_agg(i), '[]'::jsonb) INTO v_items
    FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb)) i
   WHERE NOT EXISTS (SELECT 1 FROM order_purchase_items_v2 pi
                      WHERE pi.order_id = v_order.id
                        AND pi.status IN ('unavailable', 'replaced')
                        AND pi.original_name = i->>'name');

  FOR v_m IN SELECT * FROM jsonb_array_elements(public._talao_casar_itens(v_items, v_lines)) LOOP
    IF NOT (v_m->>'casou')::boolean THEN
      v_sem_par := v_sem_par || (v_m->>'idx')::int;   -- tenta na segunda volta
      CONTINUE;
    END IF;
    SELECT array_agg(x) INTO STRICT v_usadas_nomes
      FROM (SELECT unnest(v_usadas_nomes) x
            UNION ALL SELECT jsonb_array_elements_text(COALESCE(v_m->'grupo', '[]'::jsonb))) s;
    IF (v_m->>'extras_app_outros') IS NULL THEN
      v_sem_match := v_sem_match + 1; CONTINUE;
    END IF;
    SELECT p.id, p.price, p.restaurant_id INTO v_prod FROM products p
     WHERE p.id = (v_m->>'product_id') AND p.restaurant_id::text = v_order.restaurant_id::text;
    IF v_prod.id IS NULL OR v_prod.price IS NULL OR v_prod.price <= 0 THEN
      v_sem_match := v_sem_match + 1; CONTINUE;
    END IF;

    IF (v_m->>'extras_talao_cents')::int > ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100) + 1 THEN
      v_extras := v_extras || jsonb_build_object('product_id', v_prod.id, 'grupo', v_m->'grupo',
        'extras_talao_cents', (v_m->>'extras_talao_cents')::int,
        'extras_app_cents', ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100)::int);
    END IF;

    CONTINUE WHEN v_prod.id = ANY (v_feitos);
    v_feitos := v_feitos || v_prod.id;

    v_new_unit := ROUND((v_m->>'base_talao_cents')::numeric / 100.0, 2);
    v_expected := ROUND(v_prod.price::numeric + (v_m->>'extras_app_outros')::numeric, 2);
    IF v_new_unit = v_expected THEN v_iguais := v_iguais + 1; CONTINUE; END IF;
    v_new_base := ROUND(v_new_unit - (v_m->>'extras_app_outros')::numeric, 2);
    IF v_new_base <= 0 THEN v_sem_match := v_sem_match + 1; CONTINUE; END IF;

    IF v_new_unit > v_expected AND (v_new_unit - v_expected) / v_expected <= 0.50 THEN
      UPDATE products SET price = v_new_base WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric, 2), v_new_base, ROUND((v_m->>'sim')::numeric, 3),
              (SELECT string_agg(x, ' + ') FROM jsonb_array_elements_text(v_m->'grupo') x), 'applied', now(), 'robot');
      v_aplicadas := v_aplicadas + 1;
    ELSE
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric, 2), v_new_base, ROUND((v_m->>'sim')::numeric, 3),
              (SELECT string_agg(x, ' + ') FROM jsonb_array_elements_text(v_m->'grupo') x), 'pending');
      v_pendentes := v_pendentes + 1;
    END IF;
  END LOOP;

  -- linhas do talao ja usadas na primeira volta
  FOR j IN 0 .. v_n - 1 LOOP
    IF (v_lines->j->>'name') = ANY (v_usadas_nomes) THEN v_usadas_idx := v_usadas_idx || j; END IF;
  END LOOP;

  -- (b) segunda volta: nome parecido + preco perto do da app, quantidade livre.
  FOREACH v_k IN ARRAY v_sem_par LOOP
    v_item := v_items->v_k;
    IF v_item IS NULL THEN v_sem_match := v_sem_match + 1; CONTINUE; END IF;
    IF jsonb_typeof(v_item->'selected_options_priced') = 'array'
       AND jsonb_array_length(v_item->'selected_options_priced') > 0 THEN
      v_sem_match := v_sem_match + 1; CONTINUE;      -- menus com opcoes: so na primeira volta
    END IF;
    SELECT p.id, p.price, p.restaurant_id INTO v_prod FROM products p
     WHERE p.id = (v_item->>'productId') AND p.restaurant_id::text = v_order.restaurant_id::text;
    IF v_prod.id IS NULL OR v_prod.price IS NULL OR v_prod.price <= 0 OR v_prod.id = ANY (v_feitos) THEN
      v_sem_match := v_sem_match + 1; CONTINUE;
    END IF;

    v_nome := public._talao_norm(v_item->>'name');
    v_bidx := NULL; v_bsim := 0;
    FOR j IN 0 .. v_n - 1 LOOP
      CONTINUE WHEN j = ANY (v_usadas_idx);
      v_line := v_lines->j;
      v_up := COALESCE((v_line->>'unit_price_cents')::int, 0);
      CONTINUE WHEN v_up <= 0;
      CONTINUE WHEN public._talao_e_modificador(v_line->>'name') OR public._talao_e_acompanhamento(v_line->>'name');
      v_ln := public._talao_norm(v_line->>'name');
      CONTINUE WHEN v_ln ~ '(^| )saco( |$)';
      CONTINUE WHEN abs(v_up - v_prod.price * 100) > v_prod.price * 100 * 0.25;
      v_sim := GREATEST(extensions.similarity(v_nome, v_ln),
                        extensions.word_similarity(v_ln, v_nome),
                        extensions.similarity(replace(v_nome, ' ', ''), replace(v_ln, ' ', '')));
      IF v_sim > v_bsim THEN v_bsim := v_sim; v_bidx := j; END IF;
    END LOOP;

    IF v_bidx IS NULL OR v_bsim < 0.40 THEN v_sem_match := v_sem_match + 1; CONTINUE; END IF;
    v_usadas_idx := v_usadas_idx || v_bidx;
    v_feitos := v_feitos || v_prod.id;
    v_segunda := v_segunda + 1;

    v_new_unit := ROUND((v_lines->v_bidx->>'unit_price_cents')::numeric / 100.0, 2);
    v_expected := ROUND(v_prod.price::numeric, 2);
    IF v_new_unit = v_expected THEN v_iguais := v_iguais + 1; CONTINUE; END IF;

    IF v_new_unit > v_expected THEN
      UPDATE products SET price = v_new_unit WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              v_expected, v_new_unit, ROUND(v_bsim, 3), v_lines->v_bidx->>'name', 'applied', now(), 'robot');
      v_aplicadas := v_aplicadas + 1;
    ELSE
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              v_expected, v_new_unit, ROUND(v_bsim, 3), v_lines->v_bidx->>'name', 'pending');
      v_pendentes := v_pendentes + 1;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_extras) > 0 THEN
    INSERT INTO admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    VALUES ('catalogo_extra_mais_caro', 'low', 'order', v_order.id,
            'Talão do pedido ' || left(v_order.id, 8) || ': há EXTRAS mais caros ao balcão do que na app ('
              || jsonb_array_length(v_extras) || '). Rever o preço das opções.',
            jsonb_build_object('receipt_id', p_receipt_id, 'extras', v_extras));
  END IF;

  RETURN jsonb_build_object('ok', true, 'aplicadas', v_aplicadas, 'pendentes', v_pendentes,
    'sem_match', v_sem_match, 'ja_batiam', v_iguais, 'segunda_volta', v_segunda,
    'extras_mais_caros', v_extras);
END $function$;
