-- @@FN _talao_norm
CREATE OR REPLACE FUNCTION public._talao_norm(p text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT btrim(regexp_replace(lower(extensions.unaccent(COALESCE(p, ''))), '[^a-z0-9 ]+', ' ', 'g'))
$function$
-- @@FN _talao_e_modificador
CREATE OR REPLACE FUNCTION public._talao_e_modificador(p text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT public._talao_norm(p) ~ '^(extra|com|sem|mais|adicional|molho|\+)( |$)'
$function$
-- @@FN _talao_e_acompanhamento
CREATE OR REPLACE FUNCTION public._talao_e_acompanhamento(p text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT public._talao_norm(p) ~ '^(batatas?|patatas?|fries|cola|coca|pepsi|fanta|sprite|7 ?up|ice ?tea|nestea|lipton|sumo|agua|bebida|refrigerante|cerveja|sagres|super ?bock|cafe|salada|sobremesa|gelado|sundae|aros|onion)( |$)'
$function$
-- @@FN _talao_casar_itens
CREATE OR REPLACE FUNCTION public._talao_casar_itens(p_items jsonb, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_n      int := COALESCE(jsonb_array_length(p_lines), 0);
  v_usadas int[] := '{}';
  v_out    jsonb := '[]'::jsonb;
  v_item   jsonb;
  v_idx    int := -1;
  v_nome   text;
  v_menu   boolean;
  v_best   int;
  v_bsim   numeric;
  v_sim    numeric;
  v_line   jsonb;
  j        int;
  v_base   int;
  v_extra  int;
  v_ln     text;
  v_up     int;
  v_app_mod   numeric;
  v_app_outro numeric;
  v_grupo  jsonb;
BEGIN
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    v_idx := v_idx + 1;
    v_nome := public._talao_norm(v_item->>'name');
    v_menu := v_nome ~ '(^| )menu( |$)';
    v_nome := btrim(regexp_replace(v_nome, '(^| )menu( |$)', ' ', 'g'));
    v_best := NULL; v_bsim := 0;
    FOR j IN 0 .. v_n - 1 LOOP
      v_line := p_lines->j;
      CONTINUE WHEN j = ANY (v_usadas);
      CONTINUE WHEN COALESCE((v_line->>'unit_price_cents')::int, 0) <= 0;
      CONTINUE WHEN COALESCE((v_line->>'qty')::numeric, 1) <> COALESCE((v_item->>'quantity')::numeric, 1);
      CONTINUE WHEN public._talao_e_modificador(v_line->>'name') OR public._talao_e_acompanhamento(v_line->>'name');
      v_ln := public._talao_norm(v_line->>'name');
      v_sim := GREATEST(extensions.similarity(v_nome, v_ln),
                        extensions.word_similarity(v_ln, v_nome),
                        extensions.similarity(replace(v_nome, ' ', ''), replace(v_ln, ' ', '')));
      IF v_sim > v_bsim THEN v_bsim := v_sim; v_best := j; END IF;
    END LOOP;

    -- extras escolhidos na app (preço de balcão): EXTRA… à parte do resto (bebida/acompanhamento)
    v_app_mod := 0; v_app_outro := 0;
    BEGIN
      SELECT COALESCE(SUM((gi.value->>'price_add')::numeric) FILTER (WHERE public._talao_e_modificador(gi.value->>'name')), 0),
             COALESCE(SUM((gi.value->>'price_add')::numeric) FILTER (WHERE NOT public._talao_e_modificador(gi.value->>'name')), 0)
        INTO v_app_mod, v_app_outro
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_item->'selected_options_priced') = 'array'
                                       THEN v_item->'selected_options_priced' ELSE '[]'::jsonb END) g,
             jsonb_array_elements(CASE WHEN jsonb_typeof(g.value->'items') = 'array'
                                       THEN g.value->'items' ELSE '[]'::jsonb END) gi;
    EXCEPTION WHEN others THEN v_app_mod := NULL; v_app_outro := NULL;
    END;

    IF v_best IS NULL OR v_bsim < 0.5 THEN
      v_out := v_out || jsonb_build_object('idx', v_idx, 'product_id', v_item->>'productId', 'casou', false,
                                           'sim', ROUND(v_bsim, 3));
      CONTINUE;
    END IF;
    v_usadas := v_usadas || v_best;
    v_base := (p_lines->v_best->>'unit_price_cents')::int;
    v_extra := 0;
    v_grupo := jsonb_build_array(p_lines->v_best->>'name');
    j := v_best + 1;
    WHILE j < v_n LOOP
      v_line := p_lines->j;
      v_up := COALESCE((v_line->>'unit_price_cents')::int, 0);
      EXIT WHEN j = ANY (v_usadas);
      IF public._talao_e_modificador(v_line->>'name') THEN
        v_extra := v_extra + v_up;
      ELSIF v_menu AND public._talao_e_acompanhamento(v_line->>'name') THEN
        v_base := v_base + v_up;
      ELSIF v_up = 0 THEN
        NULL;                       -- linha descritiva (ex.: "3C Whopper"), não fecha o grupo
      ELSE
        EXIT;
      END IF;
      v_usadas := v_usadas || j;
      v_grupo := v_grupo || to_jsonb(v_line->>'name');
      j := j + 1;
    END LOOP;
    v_out := v_out || jsonb_build_object(
      'idx', v_idx, 'product_id', v_item->>'productId', 'casou', true, 'sim', ROUND(v_bsim, 3),
      'linha', p_lines->v_best->>'name', 'grupo', v_grupo, 'menu', v_menu,
      'base_talao_cents', v_base, 'extras_talao_cents', v_extra,
      'extras_app_mod', v_app_mod, 'extras_app_outros', v_app_outro);
  END LOOP;
  RETURN v_out;
END $function$
-- @@FN admin_approve_catalog_price_update
CREATE OR REPLACE FUNCTION public.admin_approve_catalog_price_update(p_update_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_u record;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_u FROM catalog_price_updates WHERE id = p_update_id FOR UPDATE;
  IF v_u.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  IF v_u.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nao_esta_pendente', 'status', v_u.status);
  END IF;
  UPDATE products SET price = v_u.new_base WHERE id = v_u.product_id;
  UPDATE catalog_price_updates SET status='approved', decided_at=now(), decided_by=auth.uid()::text
    WHERE id = p_update_id;
  PERFORM public.log_admin_action('catalog_price_approved', 'product', v_u.product_id,
    jsonb_build_object('de', v_u.old_base, 'para', v_u.new_base, 'update_id', p_update_id));
  RETURN jsonb_build_object('ok', true, 'preco_novo', v_u.new_base);
END $function$
-- @@FN catalog_price_update_from_receipt
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
END $function$
