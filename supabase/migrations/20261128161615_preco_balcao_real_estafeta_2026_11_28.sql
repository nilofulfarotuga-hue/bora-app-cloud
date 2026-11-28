-- Aplicada em produção pela Claude.ai por MCP a 28/11/2026 16:16 (Danilo: "Sim", 16:12).
-- Regra do Danilo (pedido KFC 14658088: talão 13,60 €, ao estafeta aparecia 15,67 €):
-- talão MAIS BARATO → o robô corrige o preço de balcão que o ESTAFETA vê; o preço do CLIENTE fica igual
-- e só sobe quando o talão sai mais caro. products.price continua a ser a base do preço do cliente.
-- Nada de dinheiro muda aqui: cobrança ao cliente, reembolso ao estafeta (valor do talão) e ganhos ficam iguais.

alter table public.products
  add column if not exists preco_balcao_real numeric(12,2),
  add column if not exists preco_balcao_real_em timestamptz,
  add column if not exists preco_balcao_real_fonte uuid;

comment on column public.products.preco_balcao_real is
  'Preço de balcão real lido no último talão quando saiu MAIS BARATO que products.price. Só para o estafeta ver (itens do pedido levam balcaoReal). NULL = o balcão é o products.price. Nunca baixa o preço do cliente.';

-- 1) Robô do talão
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
  v_absurdas   int := 0;   -- 09/11/2026
  v_estafeta   int := 0;   -- 28/11/2026: mais barato aplicado só ao preço que o estafeta vê
  v_extras     jsonb := '[]'::jsonb;
  v_extras_pend int := 0;     -- 09/11/2026 (pendencias C3)
  v_xl         jsonb;
  v_xn         text;
  v_oi         record;
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
    SELECT p.id, p.price, p.restaurant_id, p.preco_balcao_real INTO v_prod FROM products p
     WHERE p.id = (v_m->>'product_id') AND p.restaurant_id::text = v_order.restaurant_id::text;
    IF v_prod.id IS NULL OR v_prod.price IS NULL OR v_prod.price <= 0 THEN
      v_sem_match := v_sem_match + 1; CONTINUE;
    END IF;

    IF (v_m->>'extras_talao_cents')::int > ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100) + 1 THEN
      v_extras := v_extras || jsonb_build_object('product_id', v_prod.id, 'grupo', v_m->'grupo',
        'extras_talao_cents', (v_m->>'extras_talao_cents')::int,
        'extras_app_cents', ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100)::int);
      -- 09/11/2026 (pendencias C3): cada EXTRA pago do talão mais caro do que o extra escolhido na
      -- app vira também uma linha PENDENTE em catalog_price_updates (option_item_id = a opção do
      -- menu). Nunca se aplica sozinho: o extra corrige-se nas opções, com o teto Glovo.
      FOR v_xl IN
        SELECT DISTINCT ON (public._talao_norm(l.value->>'name')) l.value
          FROM jsonb_array_elements(v_lines) l
         WHERE (l.value->>'name') IN (SELECT jsonb_array_elements_text(COALESCE(v_m->'grupo', '[]'::jsonb)))
           AND public._talao_e_modificador(l.value->>'name')
           AND COALESCE((l.value->>'unit_price_cents')::int, 0) > 0
         ORDER BY public._talao_norm(l.value->>'name'), (l.value->>'unit_price_cents')::int DESC
      LOOP
        v_xn := btrim(regexp_replace(public._talao_norm(v_xl->>'name'), '^(extra|com|mais|adicional) ', ''));
        SELECT oi.id, oi.name, oi.price_add,
               GREATEST(extensions.similarity(x.n, v_xn), extensions.word_similarity(x.n, v_xn)) AS sim
          INTO v_oi
          FROM (SELECT g.value->>'group' AS grp, gi.value->>'name' AS nome,
                       btrim(regexp_replace(public._talao_norm(gi.value->>'name'), '^(extra|com|mais|adicional) ', '')) AS n
                  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_items->((v_m->>'idx')::int)->'selected_options_priced') = 'array'
                                                 THEN v_items->((v_m->>'idx')::int)->'selected_options_priced'
                                                 ELSE '[]'::jsonb END) g,
                       jsonb_array_elements(CASE WHEN jsonb_typeof(g.value->'items') = 'array'
                                                 THEN g.value->'items' ELSE '[]'::jsonb END) gi
                 WHERE public._talao_e_modificador(gi.value->>'name')) x
          JOIN product_option_groups og ON og.product_id = v_prod.id AND og.name = x.grp
          JOIN product_option_items oi ON oi.group_id = og.id AND oi.name = x.nome
         ORDER BY 4 DESC, oi.price_add DESC
         LIMIT 1;
        CONTINUE WHEN v_oi.id IS NULL OR v_oi.sim < 0.4;
        CONTINUE WHEN (v_xl->>'unit_price_cents')::int <= ROUND(v_oi.price_add * 100) + 1;
        CONTINUE WHEN EXISTS (SELECT 1 FROM catalog_price_updates c
                               WHERE c.receipt_id = p_receipt_id AND c.option_item_id = v_oi.id);
        INSERT INTO catalog_price_updates
          (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao,
           status, option_item_id)
        VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
                ROUND(v_oi.price_add::numeric, 2), ROUND((v_xl->>'unit_price_cents')::numeric / 100.0, 2),
                ROUND(v_oi.sim::numeric, 3),
                'EXTRA: ' || (v_xl->>'name') || ' (na app: ' || v_oi.name || ')', 'pending', v_oi.id);
        v_extras_pend := v_extras_pend + 1;
      END LOOP;
    END IF;

    CONTINUE WHEN v_prod.id = ANY (v_feitos);
    v_feitos := v_feitos || v_prod.id;

    v_new_unit := ROUND((v_m->>'base_talao_cents')::numeric / 100.0, 2);
    v_expected := ROUND(v_prod.price::numeric + (v_m->>'extras_app_outros')::numeric, 2);
    IF v_new_unit = v_expected THEN
      -- 28/11/2026: talão igual ao preço normal → o balcão real volta a ser o preço normal
      UPDATE products SET preco_balcao_real = NULL, preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
       WHERE id = v_prod.id AND preco_balcao_real IS NOT NULL;
      v_iguais := v_iguais + 1; CONTINUE;
    END IF;
    v_new_base := ROUND(v_new_unit - (v_m->>'extras_app_outros')::numeric, 2);
    IF v_new_base <= 0 THEN v_sem_match := v_sem_match + 1; CONTINUE; END IF;
    -- 09/11/2026: leitura partida do talão (ex.: 0,55 para uma caixa de 6,20) não vira proposta.
    IF v_new_base < v_prod.price * 0.4 OR v_new_base > v_prod.price * 2.5 THEN
      v_absurdas := v_absurdas + 1; CONTINUE;
    END IF;

    IF v_new_unit > v_expected AND (v_new_unit - v_expected) / v_expected <= 0.50 THEN
      -- mais caro: sobe o preço do cliente; o balcão real passa a ser o próprio preço
      UPDATE products SET price = v_new_base, preco_balcao_real = NULL,
                          preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
       WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric, 2), v_new_base, ROUND((v_m->>'sim')::numeric, 3),
              (SELECT string_agg(x, ' + ') FROM jsonb_array_elements_text(v_m->'grupo') x), 'applied', now(), 'robot');
      v_aplicadas := v_aplicadas + 1;
    ELSIF v_new_unit < v_expected AND COALESCE((v_m->>'sim')::numeric, 0) >= 0.9 THEN
      -- 28/11/2026: mais barato e o robô tem a certeza → só o preço que o estafeta vê; o cliente fica igual
      IF v_prod.preco_balcao_real IS NOT NULL AND v_prod.preco_balcao_real = v_new_base THEN
        v_iguais := v_iguais + 1; CONTINUE;
      END IF;
      UPDATE products SET preco_balcao_real = v_new_base, preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
       WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric, 2), v_new_base, ROUND((v_m->>'sim')::numeric, 3),
              (SELECT string_agg(x, ' + ') FROM jsonb_array_elements_text(v_m->'grupo') x), 'estafeta', now(), 'robot');
      v_estafeta := v_estafeta + 1;
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
    SELECT p.id, p.price, p.restaurant_id, p.preco_balcao_real INTO v_prod FROM products p
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
      CONTINUE WHEN public._talao_e_deposito(v_line->>'name');
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
    IF v_new_unit = v_expected THEN
      UPDATE products SET preco_balcao_real = NULL, preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
       WHERE id = v_prod.id AND preco_balcao_real IS NOT NULL;
      v_iguais := v_iguais + 1; CONTINUE;
    END IF;

    IF v_new_unit > v_expected THEN
      UPDATE products SET price = v_new_unit, preco_balcao_real = NULL,
                          preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
       WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              v_expected, v_new_unit, ROUND(v_bsim, 3), v_lines->v_bidx->>'name', 'applied', now(), 'robot');
      v_aplicadas := v_aplicadas + 1;
    ELSIF v_bsim >= 0.9 THEN
      IF v_prod.preco_balcao_real IS NOT NULL AND v_prod.preco_balcao_real = v_new_unit THEN
        v_iguais := v_iguais + 1; CONTINUE;
      END IF;
      UPDATE products SET preco_balcao_real = v_new_unit, preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
       WHERE id = v_prod.id;
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              v_expected, v_new_unit, ROUND(v_bsim, 3), v_lines->v_bidx->>'name', 'estafeta', now(), 'robot');
      v_estafeta := v_estafeta + 1;
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
    'so_estafeta', v_estafeta,
    'sem_match', v_sem_match, 'ja_batiam', v_iguais, 'segunda_volta', v_segunda, 'absurdas', v_absurdas,
    'extras_mais_caros', v_extras, 'extras_pendentes', v_extras_pend);
END $function$;

-- 2) Aprovar no painel: proposta MAIS BARATA vai só para o estafeta (nunca baixa o cliente)
CREATE OR REPLACE FUNCTION public.admin_approve_catalog_price_update(p_update_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_u record; v_preco numeric;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO v_u FROM catalog_price_updates WHERE id = p_update_id FOR UPDATE;
  IF v_u.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  IF v_u.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nao_esta_pendente', 'status', v_u.status);
  END IF;
  -- 09/11/2026 (pendencias C3): linha de EXTRA (opção do menu) nunca mexe no preço do produto.
  IF v_u.option_item_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'extra_corrige_se_nas_opcoes',
      'option_item_id', v_u.option_item_id, 'preco_balcao', v_u.new_base);
  END IF;
  SELECT price INTO v_preco FROM products WHERE id = v_u.product_id;
  IF v_preco IS NOT NULL AND v_u.new_base < v_preco THEN
    -- 28/11/2026: mais barato → só o estafeta vê o valor novo; o cliente continua a pagar o mesmo
    UPDATE products SET preco_balcao_real = v_u.new_base, preco_balcao_real_em = now(),
                        preco_balcao_real_fonte = v_u.receipt_id
     WHERE id = v_u.product_id;
    UPDATE catalog_price_updates SET status='estafeta', decided_at=now(), decided_by=auth.uid()::text
      WHERE id = p_update_id;
    PERFORM public.log_admin_action('catalog_price_estafeta', 'product', v_u.product_id,
      jsonb_build_object('balcao_real', v_u.new_base, 'preco_cliente_base', v_preco, 'update_id', p_update_id));
    RETURN jsonb_build_object('ok', true, 'so_estafeta', true, 'balcao_real', v_u.new_base);
  END IF;
  UPDATE products SET price = v_u.new_base, preco_balcao_real = NULL, preco_balcao_real_em = now()
   WHERE id = v_u.product_id;
  UPDATE catalog_price_updates SET status='approved', decided_at=now(), decided_by=auth.uid()::text
    WHERE id = p_update_id;
  PERFORM public.log_admin_action('catalog_price_approved', 'product', v_u.product_id,
    jsonb_build_object('de', v_u.old_base, 'para', v_u.new_base, 'update_id', p_update_id));
  RETURN jsonb_build_object('ok', true, 'preco_novo', v_u.new_base);
END $function$;

-- 3) Reverter: uma correção "só estafeta" volta a mostrar o preço normal
CREATE OR REPLACE FUNCTION public.admin_revert_catalog_price_update(p_update_id uuid)
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
  IF v_u.status = 'estafeta' THEN
    UPDATE products SET preco_balcao_real = NULL, preco_balcao_real_em = now(), preco_balcao_real_fonte = NULL
     WHERE id = v_u.product_id;
    UPDATE catalog_price_updates SET status='reverted', decided_at=now(), decided_by=auth.uid()::text
      WHERE id = p_update_id;
    PERFORM public.log_admin_action('catalog_price_estafeta_reverted', 'product', v_u.product_id,
      jsonb_build_object('balcao_real_tirado', v_u.new_base, 'update_id', p_update_id));
    RETURN jsonb_build_object('ok', true, 'balcao_real', null);
  END IF;
  IF v_u.status NOT IN ('applied','approved') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nada_para_reverter', 'status', v_u.status);
  END IF;
  UPDATE products SET price = v_u.old_base WHERE id = v_u.product_id;
  UPDATE catalog_price_updates SET status='reverted', decided_at=now(), decided_by=auth.uid()::text
    WHERE id = p_update_id;
  PERFORM public.log_admin_action('catalog_price_reverted', 'product', v_u.product_id,
    jsonb_build_object('de', v_u.new_base, 'para', v_u.old_base, 'update_id', p_update_id));
  RETURN jsonb_build_object('ok', true, 'preco_reposto', v_u.old_base);
END $function$;

-- 4) Painel admin: pôr ou tirar à mão o preço de balcão real de um produto (NULL/0 = tirar)
CREATE OR REPLACE FUNCTION public.admin_preco_balcao_real(p_product_id text, p_valor numeric DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_p record; v_novo numeric(12,2);
BEGIN
  PERFORM public._admin_op_guard();
  SELECT id, price, preco_balcao_real INTO v_p FROM products WHERE id = p_product_id FOR UPDATE;
  IF v_p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  v_novo := CASE WHEN p_valor IS NULL OR p_valor <= 0 THEN NULL ELSE ROUND(p_valor, 2) END;
  IF v_novo IS NOT NULL AND v_novo >= v_p.price THEN
    RETURN jsonb_build_object('ok', false, 'error', 'balcao_real_tem_de_ser_menor_que_o_preco',
                              'preco', v_p.price);
  END IF;
  UPDATE products SET preco_balcao_real = v_novo, preco_balcao_real_em = now(), preco_balcao_real_fonte = NULL
   WHERE id = p_product_id;
  PERFORM public.log_admin_action('preco_balcao_real_manual', 'product', p_product_id,
    jsonb_build_object('de', v_p.preco_balcao_real, 'para', v_novo));
  RETURN jsonb_build_object('ok', true, 'balcao_real', v_novo);
END $function$;
grant execute on function public.admin_preco_balcao_real(text, numeric) to authenticated;

-- 5) Carimbo no pedido: cada item de loja não-parceira leva "balcaoReal" (base sem extras)
--    quando o produto tem balcão real mais baixo. A app do estafeta mostra balcaoReal ?? basePrice.
CREATE OR REPLACE FUNCTION public._orders_carimba_balcao_real()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_out jsonb := '[]'::jsonb; v_it jsonb; v_real numeric; v_mudou boolean := false;
BEGIN
  IF COALESCE(NEW.is_partner_store, false) THEN RETURN NEW; END IF;
  BEGIN
    IF jsonb_typeof(NEW.items) IS DISTINCT FROM 'array' OR jsonb_array_length(NEW.items) = 0 THEN
      RETURN NEW;
    END IF;
    FOR v_it IN SELECT e.value FROM jsonb_array_elements(NEW.items) e LOOP
      v_real := NULL;
      IF (v_it->>'productId') IS NOT NULL AND (v_it->>'basePrice') IS NOT NULL THEN
        SELECT p.preco_balcao_real INTO v_real FROM products p
         WHERE p.id = v_it->>'productId' AND p.preco_balcao_real IS NOT NULL;
      END IF;
      IF v_real IS NOT NULL AND v_real > 0 AND v_real < (v_it->>'basePrice')::numeric THEN
        v_it := v_it || jsonb_build_object('balcaoReal', ROUND(v_real, 2));
        v_mudou := true;
      END IF;
      v_out := v_out || jsonb_build_array(v_it);
    END LOOP;
    IF v_mudou THEN NEW.items := v_out; END IF;
  EXCEPTION WHEN others THEN NULL;   -- nunca parte a criação do pedido
  END;
  RETURN NEW;
END $function$;

CREATE OR REPLACE TRIGGER zzzzz_orders_carimba_balcao_real
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_carimba_balcao_real();
