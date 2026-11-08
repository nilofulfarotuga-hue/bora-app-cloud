---
id: memoria-claude-ai-proposta-m1-2026-11-08-sql-04
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 08/11 — SQL 04 gorjeta, ganho do dia, robô do talão

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-sql-04`, origem `claude-code`, atualizada em 2026-11-08T20:59:30.92096+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 sql 04 · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08 (Claude Code do PC, 08/11/2026). Ficheiro: docs/propostas/m1-dinheiro-favores-2026-11-08/04_gorjeta_conta_ganho_e_robo_talao.sql. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio) — o ramo ai/2026-11-08-m1-dinheiro-favores está só no PC.

```sql
-- ============================================================================
-- Missão m1-dinheiro-favores-2026-11-08 — Bloco 5 (aplicar DEPOIS do 03; nome final:
-- 20261108210300_m1_gorjeta_conta_ganho_e_robo_talao)
-- Caso BK 56fa8623 (08/11): gorjeta 2,00 € gravada com stripe_account='pessoal' num pedido da
-- conta 'empresa' (mesmo PaymentIntent pi_3UZaIh…; o dinheiro está na empresa — confirmado na
-- Stripe). Causa: tips.stripe_account tem DEFAULT 'pessoal' e _orders_gorjeta_checkout_na_criacao
-- não diz a conta. O registo daquela gorjeta já foi corrigido a 08/11 (backup bkp_tips_20261108).
-- Ganho do dia (meu_ganho_ao_vivo) não somava gorjetas. O robô do talão casava menus com a
-- sanduíche sozinha. Não muda preços cobrados nem ganhos por entrega.
-- ============================================================================

-- 1) Gorjeta herda a conta Stripe do pedido ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_tips_herda_conta_do_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_conta text;
BEGIN
  IF NEW.order_id IS NOT NULL THEN
    SELECT o.stripe_account INTO v_conta FROM public.orders o WHERE o.id = NEW.order_id;
    -- junto ao pagamento do pedido: é sempre a conta do pedido. À parte: a do pedido serve de
    -- ponto de partida (o webhook regrava com a conta que recebeu o pagamento).
    IF v_conta IN ('empresa', 'pessoal') THEN NEW.stripe_account := v_conta; END IF;
  ELSIF NEW.tvde_ride_id IS NOT NULL THEN
    NEW.stripe_account := 'pessoal';   -- TVDE vive na conta pessoal (duas contas, 01/11)
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_tips_herda_conta_do_pedido ON public.tips;
CREATE TRIGGER trg_tips_herda_conta_do_pedido
  BEFORE INSERT ON public.tips
  FOR EACH ROW EXECUTE FUNCTION public.fn_tips_herda_conta_do_pedido();

-- A conta do pedido pode ser gravada depois da gorjeta (create-payment-intent): as gorjetas
-- cobradas JUNTO acompanham.
CREATE OR REPLACE FUNCTION public.fn_orders_conta_stripe_nas_gorjetas()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.stripe_account IN ('empresa', 'pessoal') AND NEW.stripe_account IS DISTINCT FROM OLD.stripe_account THEN
    UPDATE public.tips SET stripe_account = NEW.stripe_account
     WHERE order_id = NEW.id AND cobrada_junto AND stripe_account IS DISTINCT FROM NEW.stripe_account;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_orders_conta_stripe_nas_gorjetas ON public.orders;
CREATE TRIGGER trg_orders_conta_stripe_nas_gorjetas
  AFTER UPDATE OF stripe_account ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_conta_stripe_nas_gorjetas();

-- 2) Ganho do dia com as gorjetas -------------------------------------------------------------
-- Igual ao que está no ar a 08/11 + a linha 'gorjetas' (líquido que o prestador recebe; as de
-- checkout chegam inteiras). Soma por paid_at, à hora de Lisboa.
CREATE OR REPLACE FUNCTION public.meu_ganho_ao_vivo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_dia timestamptz;
  v_sem timestamptz;
  v_cleaner_id uuid;
  v_washer_id uuid;
  v_linhas jsonb := '[]'::jsonb;
  v_falhas jsonb := '[]'::jsonb;
  v_hoje bigint := 0;
  v_semana bigint := 0;
  h bigint; s bigint; nh int; ns int;
  v_driver jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  v_dia := date_trunc('day',  now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_sem := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  BEGIN
    IF EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = v_uid) THEN
      v_driver := public.driver_earnings_summary();
      IF v_driver->>'ok' = 'true' THEN
        h := COALESCE((v_driver->'dia'->>'total_cents')::bigint, 0);
        s := COALESCE((v_driver->'semana'->>'total_cents')::bigint, 0);
        v_hoje := v_hoje + h;
        v_semana := v_semana + s;
        v_linhas := v_linhas || jsonb_build_object(
          'papel', 'driver', 'titulo', 'Entregas e corridas',
          'hoje_cents', h, 'semana_cents', s);
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('driver'::text);
  END;
  BEGIN
    SELECT c.id INTO v_cleaner_id FROM public.cleaners c WHERE c.user_id = v_uid;
    IF v_cleaner_id IS NOT NULL THEN
      SELECT COALESCE(sum(b.cleaner_earnings_cents) FILTER (WHERE b.completed_at >= v_dia), 0),
             COALESCE(sum(b.cleaner_earnings_cents) FILTER (WHERE b.completed_at >= v_sem), 0),
             count(*) FILTER (WHERE b.completed_at >= v_dia),
             count(*) FILTER (WHERE b.completed_at >= v_sem)
        INTO h, s, nh, ns
        FROM public.cleaning_bookings b
       WHERE b.cleaner_id = v_cleaner_id AND b.status = 'completed'
         AND COALESCE(b.is_test_order, false) = false;
      v_hoje := v_hoje + h; v_semana := v_semana + s;
      v_linhas := v_linhas || jsonb_build_object(
        'papel', 'cleaner', 'titulo', 'Limpeza',
        'hoje_cents', h, 'semana_cents', s,
        'trabalhos_hoje', nh, 'trabalhos_semana', ns);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('cleaner'::text);
  END;
  BEGIN
    SELECT w.id INTO v_washer_id FROM public.washers w WHERE w.user_id = v_uid;
    IF v_washer_id IS NOT NULL THEN
      SELECT COALESCE(sum(b.washer_earnings_cents) FILTER (WHERE b.completed_at >= v_dia), 0),
             COALESCE(sum(b.washer_earnings_cents) FILTER (WHERE b.completed_at >= v_sem), 0),
             count(*) FILTER (WHERE b.completed_at >= v_dia),
             count(*) FILTER (WHERE b.completed_at >= v_sem)
        INTO h, s, nh, ns
        FROM public.carwash_bookings b
       WHERE b.washer_id = v_washer_id AND b.status = 'completed';
      v_hoje := v_hoje + h; v_semana := v_semana + s;
      v_linhas := v_linhas || jsonb_build_object(
        'papel', 'washer', 'titulo', 'Lavagem de carros',
        'hoje_cents', h, 'semana_cents', s,
        'trabalhos_hoje', nh, 'trabalhos_semana', ns);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('washer'::text);
  END;
  -- M1 08/11: gorjetas recebidas (todas as funções), pelo líquido do prestador.
  BEGIN
    SELECT COALESCE(sum(t.liquido_prestador_cents) FILTER (WHERE t.paid_at >= v_dia), 0),
           COALESCE(sum(t.liquido_prestador_cents) FILTER (WHERE t.paid_at >= v_sem), 0),
           count(*) FILTER (WHERE t.paid_at >= v_dia),
           count(*) FILTER (WHERE t.paid_at >= v_sem)
      INTO h, s, nh, ns
      FROM public.tips t
     WHERE t.provider_user_id = v_uid AND t.status = 'succeeded' AND t.paid_at >= v_sem;
    IF s > 0 THEN
      v_hoje := v_hoje + h; v_semana := v_semana + s;
      v_linhas := v_linhas || jsonb_build_object(
        'papel', 'gorjetas', 'titulo', 'Gorjetas',
        'hoje_cents', h, 'semana_cents', s,
        'trabalhos_hoje', nh, 'trabalhos_semana', ns);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('gorjetas'::text);
  END;
  RETURN jsonb_build_object(
    'ok', true,
    'hoje_cents', v_hoje,
    'semana_cents', v_semana,
    'por_papel', v_linhas,
    'papeis_com_falha', v_falhas);
END $function$;

-- 3) Robô do talão: menus e extras ------------------------------------------------------------
-- Casa cada artigo do pedido com a linha principal do talão (sem acentos; "menu" sai só para
-- ENCONTRAR a sanduíche) e junta-lhe as linhas que vêm a seguir: as de 0 €, os modificadores
-- (EXTRA…, Com…, Sem…) e, se o artigo é um menu, os acompanhamentos e a bebida. Assim
-- "Triple Whopper Spicy Menu" compara com Tripwhopper + batatas + bebida, nunca com a sanduíche
-- sozinha (cicatriz 05/09: "menu" não é ruído). Os EXTRA comparam-se com os extras da app à parte.
CREATE OR REPLACE FUNCTION public._talao_norm(p text)
RETURNS text LANGUAGE sql STABLE SET search_path TO 'public', 'extensions' AS $$
  SELECT btrim(regexp_replace(lower(extensions.unaccent(COALESCE(p, ''))), '[^a-z0-9 ]+', ' ', 'g'))
$$;

CREATE OR REPLACE FUNCTION public._talao_e_modificador(p text)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public', 'extensions' AS $$
  SELECT public._talao_norm(p) ~ '^(extra|com|sem|mais|adicional|molho|\+)( |$)'
$$;

CREATE OR REPLACE FUNCTION public._talao_e_acompanhamento(p text)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public', 'extensions' AS $$
  SELECT public._talao_norm(p) ~ '^(batatas?|patatas?|fries|cola|coca|pepsi|fanta|sprite|7 ?up|ice ?tea|nestea|lipton|sumo|agua|bebida|refrigerante|cerveja|sagres|super ?bock|cafe|salada|sobremesa|gelado|sundae|aros|onion)( |$)'
$$;

CREATE OR REPLACE FUNCTION public._talao_casar_itens(p_items jsonb, p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public', 'extensions' AS $$
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
END $$;

-- O robô: só SOBE sozinho (regra do Danilo 05/09); mais barato ou subida > 50% → pendente;
-- extras do talão mais caros que os da app → aviso no sininho (o robô não mexe em opções).
CREATE OR REPLACE FUNCTION public.catalog_price_update_from_receipt(p_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $$
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
  v_extras     jsonb := '[]'::jsonb;
  v_enabled    boolean;
  v_feitos     text[] := '{}';
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

  SELECT o.id, o.restaurant_id, o.is_partner_store, o.items INTO v_order FROM orders o WHERE o.id = v_r.order_id;
  IF v_order.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'order_not_found'); END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN RETURN jsonb_build_object('ok', true, 'skipped', 'loja_parceira'); END IF;

  FOR v_m IN SELECT * FROM jsonb_array_elements(public._talao_casar_itens(v_order.items, v_r.receipt_parsed->'lines')) LOOP
    IF NOT (v_m->>'casou')::boolean OR (v_m->>'extras_app_outros') IS NULL THEN
      v_sem_match := v_sem_match + 1; CONTINUE;
    END IF;
    SELECT p.id, p.price, p.restaurant_id INTO v_prod FROM products p
     WHERE p.id = (v_m->>'product_id') AND p.restaurant_id::text = v_order.restaurant_id::text;
    IF v_prod.id IS NULL OR v_prod.price IS NULL OR v_prod.price <= 0 THEN
      v_sem_match := v_sem_match + 1; CONTINUE;
    END IF;

    -- extras: o talão mais caro que a app → aviso (preço da opção é decisão humana)
    IF (v_m->>'extras_talao_cents')::int > ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100) + 1 THEN
      v_extras := v_extras || jsonb_build_object('product_id', v_prod.id, 'grupo', v_m->'grupo',
        'extras_talao_cents', (v_m->>'extras_talao_cents')::int,
        'extras_app_cents', ROUND(COALESCE((v_m->>'extras_app_mod')::numeric, 0) * 100)::int);
    END IF;

    -- o mesmo produto duas vezes no pedido: decide-se uma vez (a primeira linha)
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

  IF jsonb_array_length(v_extras) > 0 THEN
    INSERT INTO admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    VALUES ('catalogo_extra_mais_caro', 'low', 'order', v_order.id,
            'Talão do pedido ' || left(v_order.id, 8) || ': há EXTRAS mais caros ao balcão do que na app ('
              || jsonb_array_length(v_extras) || '). Rever o preço das opções.',
            jsonb_build_object('receipt_id', p_receipt_id, 'extras', v_extras));
  END IF;

  RETURN jsonb_build_object('ok', true, 'aplicadas', v_aplicadas, 'pendentes', v_pendentes,
    'sem_match', v_sem_match, 'ja_batiam', v_iguais, 'extras_mais_caros', v_extras);
END $$;

```

