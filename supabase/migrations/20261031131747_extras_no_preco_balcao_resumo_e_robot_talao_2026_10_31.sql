-- 31/10/2026 (Claude.ai, ao montar os tamanhos do Jyosmi Sushi):
-- o preço base guardado no item do pedido (basePrice) NÃO inclui o tamanho/extras escolhidos
-- (price_add, em preço de balcão). Duas funções ignoravam isso:
--  1) encomenda_telefone_resumo: o TOTAL BALCÃO do aviso "LIGAR À LOJA" saía ao preço da caixa pequena;
--  2) catalog_price_update_from_receipt (robot do talão): comparava a linha do talão (que já traz o
--     tamanho/extra) com o preço base sozinho e ia SUBIR o preço base do produto por engano.

CREATE OR REPLACE FUNCTION public.encomenda_telefone_resumo(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o public.orders%ROWTYPE;
  r public.restaurants%ROWTYPE;
  it jsonb; g jsonb;
  v_txt text := ''; v_total numeric := 0; v_unit numeric; v_q int; v_ops text; v_extra numeric;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO r FROM public.restaurants WHERE id = o.restaurant_id;
  FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(o.items, '[]'::jsonb)) LOOP
    v_q := COALESCE((it->>'quantity')::int, 1);
    v_extra := 0;
    BEGIN
      SELECT COALESCE(SUM((gi.value->>'price_add')::numeric), 0) INTO v_extra
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(it->'selected_options_priced') = 'array'
                                       THEN it->'selected_options_priced' ELSE '[]'::jsonb END) gg,
             jsonb_array_elements(CASE WHEN jsonb_typeof(gg.value->'items') = 'array'
                                       THEN gg.value->'items' ELSE '[]'::jsonb END) gi;
    EXCEPTION WHEN others THEN v_extra := 0;
    END;
    IF (it->>'basePrice') IS NOT NULL THEN
      v_unit := ROUND((it->>'basePrice')::numeric + COALESCE(v_extra, 0), 2);
    ELSE
      -- sem basePrice: o preço da app já traz os extras; tira-se a margem de 15%
      v_unit := ROUND(COALESCE((it->>'price')::numeric / 1.15, 0), 2);
    END IF;
    v_ops := '';
    FOR g IN SELECT * FROM jsonb_array_elements(COALESCE(it->'selected_options', '[]'::jsonb)) LOOP
      v_ops := v_ops || E'\n     · ' || COALESCE(g->>'group', '') || ': '
            || COALESCE((SELECT string_agg(x, ', ') FROM jsonb_array_elements_text(g->'items') x), '');
    END LOOP;
    v_txt := v_txt || E'\n• ' || v_q || '× ' || COALESCE(it->>'name', '?')
          || ' — ' || to_char(v_unit, 'FM9990.00') || ' €' || v_ops;
    v_total := v_total + v_unit * v_q;
  END LOOP;
  RETURN jsonb_build_object(
    'loja', r.name,
    'telefone', COALESCE(r.phone_order_number, r.phone),
    'cliente', COALESCE(o.customer_name, 'cliente'),
    'hora', to_char(o.created_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI'),
    'itens', v_txt,
    'notas', o.customer_notes,
    'total_balcao', ROUND(v_total, 2),
    'texto', 'Pedido ' || left(o.id, 8) || ' · ' || r.name || ' · '
             || to_char(o.created_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI')
             || E'\nCliente: ' || COALESCE(o.customer_name, 'cliente')
             || v_txt
             || CASE WHEN COALESCE(o.customer_notes, '') <> '' THEN E'\nNotas: ' || o.customer_notes ELSE '' END
             || E'\nTOTAL BALCÃO: ' || to_char(ROUND(v_total, 2), 'FM9990.00') || ' €'
             || E'\nLigar: ' || COALESCE(r.phone_order_number, r.phone, '?'));
END
$function$;

CREATE OR REPLACE FUNCTION public.catalog_price_update_from_receipt(p_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_r          record;
  v_order      record;
  v_item       jsonb;
  v_line       jsonb;
  v_best_line  jsonb;
  v_best_sim   numeric;
  v_sim        numeric;
  v_prod       record;
  v_new_base   numeric(12,2);
  v_new_unit   numeric(12,2);
  v_expected   numeric(12,2);
  v_extra      numeric;
  v_aplicadas  int := 0;
  v_pendentes  int := 0;
  v_sem_match  int := 0;
  v_iguais     int := 0;
  v_enabled    boolean;
BEGIN
  -- REGRA DO DANILO (05/09/2026): o robot so pode SUBIR o preco sozinho.
  -- Preco do talao mais BARATO que o nosso -> nunca aplica, fica pendente para decisao humana.
  -- Subida absurda (>50%) -> tambem fica pendente (suspeita de linha de menu lida no lugar do item).
  -- 31/10/2026: a linha do talao traz o tamanho/extras escolhidos (price_add); compara-se com
  -- preco base + extras e, se subir, so o preco BASE e corrigido (linha do talao - extras).
  SELECT (value::text IN ('true', '"true"')) INTO v_enabled
    FROM platform_settings WHERE key='catalog_price_live_update_enabled';
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'kill_switch_off');
  END IF;

  SELECT r.id, r.order_id, r.receipt_parsed INTO v_r
    FROM order_receipts_v2 r WHERE r.id = p_receipt_id;
  IF v_r.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'receipt_not_found');
  END IF;
  IF v_r.receipt_parsed IS NULL
     OR jsonb_typeof(v_r.receipt_parsed->'lines') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_r.receipt_parsed->'lines') = 0 THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'sem_linhas_no_talao');
  END IF;

  SELECT o.id, o.restaurant_id, o.is_partner_store, o.items INTO v_order
    FROM orders o WHERE o.id = v_r.order_id;
  IF v_order.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'loja_parceira');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb))
  LOOP
    v_best_line := NULL; v_best_sim := 0;
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_r.receipt_parsed->'lines')
    LOOP
      IF COALESCE((v_line->>'qty')::numeric, 1) = COALESCE((v_item->>'quantity')::numeric, 1)
         AND COALESCE((v_line->>'unit_price_cents')::int, 0) > 0 THEN
        v_sim := extensions.similarity(upper(v_item->>'name'), upper(v_line->>'name'));
        IF v_sim > v_best_sim THEN
          v_best_sim := v_sim; v_best_line := v_line;
        END IF;
      END IF;
    END LOOP;

    IF v_best_line IS NULL OR v_best_sim < 0.45 THEN
      v_sem_match := v_sem_match + 1;
      CONTINUE;
    END IF;

    SELECT p.id, p.price, p.restaurant_id INTO v_prod
      FROM products p
      WHERE p.id = (v_item->>'productId')
        AND p.restaurant_id::text = v_order.restaurant_id::text;
    IF v_prod.id IS NULL OR v_prod.price IS NULL OR v_prod.price <= 0 THEN
      v_sem_match := v_sem_match + 1;
      CONTINUE;
    END IF;

    -- tamanho/extras escolhidos neste item (em preco de balcao)
    v_extra := 0;
    BEGIN
      SELECT COALESCE(SUM((gi.value->>'price_add')::numeric), 0) INTO v_extra
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_item->'selected_options_priced') = 'array'
                                       THEN v_item->'selected_options_priced' ELSE '[]'::jsonb END) g,
             jsonb_array_elements(CASE WHEN jsonb_typeof(g.value->'items') = 'array'
                                       THEN g.value->'items' ELSE '[]'::jsonb END) gi;
    EXCEPTION WHEN others THEN v_extra := NULL;
    END;
    IF v_extra IS NULL THEN
      v_sem_match := v_sem_match + 1;
      CONTINUE;
    END IF;

    v_new_unit := ROUND(((v_best_line->>'unit_price_cents')::numeric) / 100.0, 2);
    IF v_new_unit <= 0 THEN CONTINUE; END IF;
    v_expected := ROUND(v_prod.price::numeric + v_extra, 2);

    IF v_new_unit = v_expected THEN
      v_iguais := v_iguais + 1;
      CONTINUE;
    END IF;

    v_new_base := ROUND(v_new_unit - v_extra, 2);
    IF v_new_base <= 0 THEN
      v_sem_match := v_sem_match + 1;
      CONTINUE;
    END IF;

    IF v_new_unit > v_expected
       AND (v_new_unit - v_expected) / v_expected <= 0.50 THEN
      UPDATE products SET price = v_new_base WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric,2), v_new_base, ROUND(v_best_sim,3),
              v_best_line->>'name', 'applied', now(), 'robot');
      v_aplicadas := v_aplicadas + 1;
    ELSE
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric,2), v_new_base, ROUND(v_best_sim,3),
              v_best_line->>'name', 'pending');
      v_pendentes := v_pendentes + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'aplicadas', v_aplicadas,
    'pendentes', v_pendentes, 'sem_match', v_sem_match, 'ja_batiam', v_iguais);
END
$function$;
