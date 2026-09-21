-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) — version 20260921071222 · contas_claras_b10_taxa_pedido_pequeno_nao_desaparece_2026_09_21.
-- Espelho exacto de supabase_migrations.schema_migrations, puxado por REST a 21/09/2026 (Claude Code, missão contas-claras-20260921).
-- A migration original foi aplicada por SUBSTITUIÇÃO DE TEXTO (bloco DO) na definição viva de finalize_storeshopping_purchase;
-- aqui fica como CREATE OR REPLACE normal com o CORPO COMPLETO tal como está vivo (pg_get_functiondef).
-- Bloco original aplicado (para memória):
--   -- CONTAS CLARAS B10 (21/09/2026)
--   -- O QUE ESTOU A MEXER: public.finalize_storeshopping_purchase — a funcao que o
--   -- estafeta dispara ao fechar a compra e que escreve orders.final_total e
--   -- orders.cash_total_due (o que o cliente paga de facto).
--   --
--   -- PORQUE: a taxa de pedido pequeno (small_order_fee_cents = 139, enabled = true)
--   -- e somada ao total do cliente na encomenda — a quote_order_pricing fa-lo em
--   -- v_customer_total := v_pricing.customer_total + v_small_order_fee, e o gatilho
--   -- orders_aa_small_order_fee (BEFORE INSERT) grava-a em orders.small_order_fee.
--   -- Mas ao fechar a compra esta funcao recalculava o total SEM ela:
--   --   v_final_total_cents := bought + added + bag + delivery + service
--   -- Resultado provado em 5 pedidos desde 27/08: faltam exactamente 1,39 EUR em
--   -- cada um (6,95 EUR). Em dinheiro o estafeta cobra 1,39 a menos do que o
--   -- cliente aceitou; em cartao a diferenca e devolvida como reembolso.
--   --
--   -- O QUE MUDA: a parcela volta a entrar na soma, com o valor que o cliente ja
--   -- tinha aceite (orders.small_order_fee). NAO se recalcula a taxa aqui de
--   -- proposito: recalcular sobre o total realmente comprado podia COBRAR MAIS do
--   -- que o orcamento que o cliente viu, e isso e decisao de preco, nao correccao
--   -- de erro. O gatilho e BEFORE INSERT, so dispara na criacao, por isso nao ha
--   -- risco de a taxa ser somada duas vezes.
--   DO $do$
--   DECLARE
--     v_def text;
--     v_n   int;
--   BEGIN
--     SELECT pg_get_functiondef(p.oid) INTO v_def
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--     WHERE n.nspname = 'public' AND p.proname = 'finalize_storeshopping_purchase';
--   
--     IF v_def IS NULL THEN
--       RAISE EXCEPTION 'finalize_storeshopping_purchase nao encontrada';
--     END IF;
--   
--     IF position('v_small_order_fee_cents' in v_def) > 0 THEN
--       RAISE EXCEPTION 'ja tem a parcela da taxa — nada alterado';
--     END IF;
--   
--     -- 1) declarar a variavel
--     v_n := (length(v_def) - length(replace(v_def, '  v_service_fee_cents       INT;', ''))) /
--            length('  v_service_fee_cents       INT;');
--     IF v_n <> 1 THEN RAISE EXCEPTION 'declaracao: esperava 1 ocorrencia, achei %', v_n; END IF;
--     v_def := replace(v_def,
--       '  v_service_fee_cents       INT;',
--       '  v_service_fee_cents       INT;' || chr(10) ||
--       '  v_small_order_fee_cents   INT;');
--   
--     -- 2) ler o valor que o cliente ja aceitou
--     v_n := (length(v_def) - length(replace(v_def,
--             '  v_service_fee_cents  := ROUND(COALESCE(v_order.service_fee, 0) * 100)::int;', ''))) /
--            length('  v_service_fee_cents  := ROUND(COALESCE(v_order.service_fee, 0) * 100)::int;');
--     IF v_n <> 1 THEN RAISE EXCEPTION 'atribuicao: esperava 1 ocorrencia, achei %', v_n; END IF;
--     v_def := replace(v_def,
--       '  v_service_fee_cents  := ROUND(COALESCE(v_order.service_fee, 0) * 100)::int;',
--       '  v_service_fee_cents  := ROUND(COALESCE(v_order.service_fee, 0) * 100)::int;' || chr(10) ||
--       '  -- CONTAS CLARAS 21/09: a taxa de pedido pequeno ja foi orcamentada ao' || chr(10) ||
--       '  -- cliente e gravada pelo gatilho; volta a entrar no total em vez de' || chr(10) ||
--       '  -- desaparecer no fecho da compra.' || chr(10) ||
--       '  v_small_order_fee_cents := ROUND(COALESCE(v_order.small_order_fee, 0) * 100)::int;');
--   
--     -- 3) somar a parcela ao total
--     v_n := (length(v_def) - length(replace(v_def, 'v_service_fee_cents;', ''))) /
--            length('v_service_fee_cents;');
--     IF v_n <> 1 THEN RAISE EXCEPTION 'soma: esperava 1 ocorrencia, achei %', v_n; END IF;
--     v_def := replace(v_def,
--       'v_service_fee_cents;',
--       'v_service_fee_cents' || chr(10) ||
--       '                       + v_small_order_fee_cents;');
--   
--     -- 4) deixar a parcela visivel no registo de auditoria e na resposta
--     v_def := replace(v_def,
--       '''service_fee_cents'',        v_service_fee_cents,',
--       '''service_fee_cents'',        v_service_fee_cents,' || chr(10) ||
--       '        ''small_order_fee_cents'',    v_small_order_fee_cents,');
--     v_def := replace(v_def,
--       '''service_fee_cents'',    v_service_fee_cents,',
--       '''service_fee_cents'',    v_service_fee_cents,' || chr(10) ||
--       '    ''small_order_fee_cents'', v_small_order_fee_cents,');
--   
--     EXECUTE v_def;
--   END $do$;

CREATE OR REPLACE FUNCTION public.finalize_storeshopping_purchase(p_order_id text, p_items_status jsonb, p_items_added jsonb DEFAULT '[]'::jsonb, p_bag_count integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_uid              UUID;
  v_order                   RECORD;
  v_markup_pct              NUMERIC;
  v_max_extra_pct           NUMERIC;
  v_per_bag_cents           INT;
  v_bought_total_cents      INT := 0;
  v_unavailable_total_cents INT := 0;
  v_added_total_cents       INT := 0;
  v_bag_fee_cents           INT;
  v_delivery_fee_cents      INT;
  v_service_fee_cents       INT;
  v_small_order_fee_cents   INT;
  v_final_total_cents       INT;
  v_orig_total_cents        INT;
  v_paid_cents              INT;
  v_refund_cents            INT;
  v_extra_charge_cents      INT;
  v_refund_method           TEXT := NULL;
  v_new_payment_status      TEXT;
  v_warning                 TEXT := NULL;
  v_items_added_resolved    JSONB := '[]'::jsonb;
  v_payload_entry           JSONB;
  v_canonical_item          JSONB;
  v_added_item              JSONB;
  v_payload_id              TEXT;
  v_payload_status          TEXT;
  v_canon_price_cents       INT;
  v_canon_qty               INT;
  v_base_cents              INT;
  v_qty                     INT;
  v_final_cents             INT;
  v_status_by_id            JSONB := '{}'::jsonb;
  v_merged_items            JSONB := '[]'::jsonb;
  v_canon_id                TEXT;
  v_canon_status            TEXT;
  v_canon_default_status    TEXT;
  v_is_card                 BOOLEAN;
  v_is_restaurant           BOOLEAN;
  v_cash_extra_cents        INT := 0;
  v_wallet_neg_enabled      BOOLEAN;
  v_adjust_result           JSONB;
  v_adjust_reason           TEXT;
  v_wallet_debit_applied    INT := 0;
  v_wallet_balance_after    INT := NULL;
BEGIN
  v_caller_uid := auth.uid();
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;

  IF v_order.assigned_driver_id IS DISTINCT FROM v_caller_uid::text THEN
    RAISE EXCEPTION 'forbidden_not_assigned_driver: caller=% driver=%',
      v_caller_uid, v_order.assigned_driver_id
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_order.is_purchase_finalized, false) = true THEN
    RAISE EXCEPTION 'already_finalized' USING ERRCODE = '23514';
  END IF;

  IF v_order.service_type NOT IN ('storeShopping','restaurant') THEN
    RAISE EXCEPTION 'wrong_service_type: % (expected storeShopping or restaurant)', v_order.service_type
      USING ERRCODE = '23514';
  END IF;

  v_is_restaurant := v_order.service_type = 'restaurant';
  v_canon_default_status := CASE WHEN v_is_restaurant THEN 'bought' ELSE 'pending' END;

  SELECT COALESCE((value::text)::numeric, 0.15) INTO v_markup_pct
    FROM public.platform_settings WHERE key = 'non_partner_markup_pct';
  v_markup_pct := COALESCE(v_markup_pct, 0.15);

  SELECT COALESCE((value::text)::numeric, 0.30) INTO v_max_extra_pct
    FROM public.platform_settings WHERE key = 'max_extra_charge_pct';
  v_max_extra_pct := COALESCE(v_max_extra_pct, 0.30);

  SELECT COALESCE((value::text)::int, 10) INTO v_per_bag_cents
    FROM public.platform_settings WHERE key = 'bag_fee_supermarket_per_bag_cents';
  v_per_bag_cents := COALESCE(v_per_bag_cents, 10);

  SELECT COALESCE((value::text)::boolean, true) INTO v_wallet_neg_enabled
    FROM public.platform_settings WHERE key='wallet_negative_enabled';
  v_wallet_neg_enabled := COALESCE(v_wallet_neg_enabled, true);

  IF v_is_restaurant THEN
    IF COALESCE(v_order.is_partner_store, false) THEN
      v_bag_fee_cents := 0;
    ELSE
      v_bag_fee_cents := 30;
    END IF;
  ELSE
    IF p_bag_count IS NOT NULL THEN
      IF p_bag_count < 0 OR p_bag_count > 5 THEN
        RAISE EXCEPTION 'invalid_bag_count: % (must be 0-5)', p_bag_count
          USING ERRCODE = '23514';
      END IF;
      v_bag_fee_cents := p_bag_count * v_per_bag_cents;
    ELSE
      v_bag_fee_cents := ROUND(COALESCE(v_order.bag_fee, 0) * 100)::int;
    END IF;
  END IF;

  v_delivery_fee_cents := ROUND(COALESCE(v_order.delivery_fee, 0) * 100)::int;
  v_service_fee_cents  := ROUND(COALESCE(v_order.service_fee, 0) * 100)::int;
  -- CONTAS CLARAS 21/09: a taxa de pedido pequeno ja foi orcamentada ao
  -- cliente e gravada pelo gatilho; volta a entrar no total em vez de
  -- desaparecer no fecho da compra.
  v_small_order_fee_cents := ROUND(COALESCE(v_order.small_order_fee, 0) * 100)::int;

  IF p_items_status IS NOT NULL AND jsonb_typeof(p_items_status) = 'array' THEN
    FOR v_payload_entry IN SELECT jsonb_array_elements(p_items_status)
    LOOP
      v_payload_id := COALESCE(
        v_payload_entry->>'id',
        v_payload_entry->>'productId',
        v_payload_entry->>'product_id'
      );
      v_payload_status := COALESCE(
        v_payload_entry->>'purchase_status',
        v_payload_entry->>'purchaseStatus'
      );
      IF v_payload_id IS NULL OR v_payload_id = '' THEN
        RAISE EXCEPTION 'missing_item_id_in_payload: %', v_payload_entry::text
          USING ERRCODE = '23514';
      END IF;
      v_status_by_id := v_status_by_id || jsonb_build_object(
        v_payload_id, COALESCE(v_payload_status, v_canon_default_status)
      );
    END LOOP;
  END IF;

  IF v_order.items IS NOT NULL AND jsonb_typeof(v_order.items) = 'array' THEN
    FOR v_canonical_item IN SELECT jsonb_array_elements(v_order.items)
    LOOP
      v_canon_id := COALESCE(
        v_canonical_item->>'productId',
        v_canonical_item->>'product_id',
        v_canonical_item->>'id'
      );
      v_canon_price_cents := ROUND(
        COALESCE((v_canonical_item->>'price')::numeric, 0) * 100
      )::int;
      v_canon_qty := COALESCE(
        NULLIF(v_canonical_item->>'quantity','')::int,
        NULLIF(v_canonical_item->>'qty','')::int,
        1
      );
      v_canon_status := COALESCE(
        v_status_by_id->>v_canon_id,
        v_canonical_item->>'purchaseStatus',
        v_canonical_item->>'purchase_status',
        v_canon_default_status
      );
      IF v_canon_status = 'bought' THEN
        v_bought_total_cents := v_bought_total_cents + (v_canon_price_cents * v_canon_qty);
      ELSIF v_canon_status = 'unavailable' THEN
        v_unavailable_total_cents := v_unavailable_total_cents + (v_canon_price_cents * v_canon_qty);
      END IF;
      v_merged_items := v_merged_items || jsonb_build_array(
        v_canonical_item || jsonb_build_object('purchaseStatus', v_canon_status)
      );
      v_status_by_id := v_status_by_id - v_canon_id;
    END LOOP;
  END IF;

  IF jsonb_typeof(v_status_by_id) = 'object' AND v_status_by_id <> '{}'::jsonb THEN
    RAISE EXCEPTION 'unknown_item_id: %s not in orders.items',
      (SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_status_by_id) k)
      USING ERRCODE = '23514';
  END IF;

  IF p_items_added IS NOT NULL AND jsonb_typeof(p_items_added) = 'array' THEN
    FOR v_added_item IN SELECT jsonb_array_elements(p_items_added)
    LOOP
      v_base_cents := COALESCE((v_added_item->>'price_base_cents')::int, 0);
      v_qty := COALESCE(
        NULLIF(v_added_item->>'qty','')::int,
        NULLIF(v_added_item->>'quantity','')::int,
        1
      );
      v_final_cents := ROUND(v_base_cents * (1 + v_markup_pct))::int;
      IF v_base_cents <= 0 THEN
        RAISE EXCEPTION 'invalid_added_item_price: name=%', v_added_item->>'name'
          USING ERRCODE = '23514';
      END IF;
      v_added_total_cents := v_added_total_cents + (v_final_cents * v_qty);
      v_items_added_resolved := v_items_added_resolved || jsonb_build_array(
        jsonb_build_object(
          'name',              v_added_item->>'name',
          'price_base_cents',  v_base_cents,
          'price_final_cents', v_final_cents,
          'qty',               v_qty,
          'reason',            COALESCE(v_added_item->>'reason', 'driver_substitution'),
          'added_at',          to_jsonb(now()),
          'added_by',          to_jsonb(v_caller_uid)
        )
      );
    END LOOP;
  END IF;

  v_orig_total_cents := ROUND(
    COALESCE(v_order.payment_buffer_total, v_order.final_total, 0) * 100
  )::int;
  v_paid_cents := COALESCE(v_order.stripe_charge_cents, 0)
                + COALESCE(v_order.wallet_applied_cents, 0)
                + COALESCE(v_order.tokens_applied_value_cents, 0);
  v_final_total_cents := v_bought_total_cents
                       + v_added_total_cents
                       + v_bag_fee_cents
                       + v_delivery_fee_cents
                       + v_service_fee_cents
                       + v_small_order_fee_cents;
  v_is_card := v_order.payment_method IN ('card', 'mbway');

  IF v_final_total_cents < v_orig_total_cents THEN
    v_refund_cents := LEAST(v_orig_total_cents - v_final_total_cents, v_paid_cents);
    IF v_refund_cents > 0 THEN
      v_refund_method := CASE WHEN v_is_card THEN 'stripe' ELSE 'wallet' END;
      v_new_payment_status := 'refundPending';
    ELSE
      v_new_payment_status := v_order.payment_status;
    END IF;
    v_extra_charge_cents := 0;
  ELSIF v_final_total_cents > v_orig_total_cents THEN
    IF v_is_card THEN
      v_extra_charge_cents := v_final_total_cents - v_orig_total_cents;
      IF v_wallet_neg_enabled THEN
        v_adjust_reason := CASE
          WHEN p_bag_count IS NOT NULL AND v_added_total_cents > 0 THEN 'market_bags_and_substitutions'
          WHEN p_bag_count IS NOT NULL THEN 'market_bags_extra'
          WHEN v_added_total_cents > 0 THEN 'driver_substitutions'
          ELSE 'post_delivery_extra'
        END;
        BEGIN
          v_adjust_result := public.wallet_apply_post_delivery_adjustment(
            p_order_id      => p_order_id,
            p_user_id       => v_order.user_id,
            p_amount_cents  => v_extra_charge_cents,
            p_reason        => v_adjust_reason,
            p_kind          => 'debit'
          );
          v_wallet_debit_applied := v_extra_charge_cents;
          v_wallet_balance_after := (v_adjust_result->>'new_balance_cents')::int;
          v_extra_charge_cents := 0;
          v_new_payment_status := v_order.payment_status;
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'wallet_apply_post_delivery_adjustment failed: % — fallback to extraRequired', SQLERRM;
          v_warning := 'wallet_debit_failed:' || SQLERRM;
          v_new_payment_status := 'extraRequired';
        END;
      ELSE
        v_new_payment_status := 'extraRequired';
      END IF;
    ELSE
      -- Cash com extra: o estafeta cobrou mais
      v_cash_extra_cents := v_final_total_cents - v_orig_total_cents;
      v_extra_charge_cents := 0;
      v_new_payment_status := v_order.payment_status;
    END IF;
    v_refund_cents := 0;
  ELSE
    v_refund_cents := 0;
    v_extra_charge_cents := 0;
    v_new_payment_status := v_order.payment_status;
  END IF;

  IF v_orig_total_cents > 0
     AND (v_extra_charge_cents > ROUND(v_orig_total_cents * v_max_extra_pct)::int
          OR v_wallet_debit_applied > ROUND(v_orig_total_cents * v_max_extra_pct)::int)
  THEN
    v_warning := COALESCE(v_warning || '; ', '') || format(
      'extra_charge exceeds %s%% limit: extra=%s wallet_debit=%s orig=%s',
      ROUND(v_max_extra_pct * 100)::int,
      v_extra_charge_cents, v_wallet_debit_applied, v_orig_total_cents
    );
  END IF;

  PERFORM set_config('app.financial_bypass', 'true', true);

  UPDATE public.orders SET
    items                    = v_merged_items,
    items_added              = v_items_added_resolved,
    bag_count                = CASE WHEN v_is_restaurant THEN 1 ELSE COALESCE(p_bag_count, bag_count) END,
    bag_fee                  = v_bag_fee_cents::numeric / 100.0,
    final_total              = v_final_total_cents::numeric / 100.0,
    refund_amount            = CASE WHEN v_refund_cents > 0
                                    THEN v_refund_cents::numeric / 100.0
                                    ELSE NULL END,
    refund_method            = v_refund_method,
    extra_charge_amount      = CASE WHEN v_extra_charge_cents > 0
                                    THEN v_extra_charge_cents::numeric / 100.0
                                    ELSE NULL END,
    extra_charge_settled_at  = CASE WHEN v_wallet_debit_applied > 0 AND extra_charge_settled_at IS NULL
                                    THEN now()
                                    ELSE extra_charge_settled_at END,
    extra_charge_settled_via = CASE WHEN v_wallet_debit_applied > 0 AND extra_charge_settled_via IS NULL
                                    THEN 'wallet'
                                    ELSE extra_charge_settled_via END,
    -- FIX 2026-05-21: cash_total_due deve ser SEMPRE o final_total para
    -- pagamentos em dinheiro — independentemente de haver extra ou não.
    -- Antes só actualizava quando v_cash_extra_cents > 0, o que deixava
    -- o valor antigo (NET) quando o estafeta comprava menos do estimado.
    cash_total_due           = CASE
                                 WHEN NOT v_is_card
                                   THEN v_final_total_cents::numeric / 100.0
                                 ELSE cash_total_due
                               END,
    is_purchase_finalized    = true,
    payment_status           = v_new_payment_status
  WHERE id = p_order_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller_uid,
      (SELECT email FROM auth.users WHERE id = v_caller_uid),
      'storeshopping_finalize',
      'order',
      p_order_id,
      jsonb_build_object(
        'driver_id',                v_caller_uid,
        'service_type',             v_order.service_type,
        'is_partner_store',         COALESCE(v_order.is_partner_store, false),
        'bought_total_cents',       v_bought_total_cents,
        'unavailable_total_cents',  v_unavailable_total_cents,
        'added_total_cents',        v_added_total_cents,
        'bag_count_input',          p_bag_count,
        'bag_fee_per_bag_cents',    v_per_bag_cents,
        'bag_fee_cents',            v_bag_fee_cents,
        'delivery_fee_cents',       v_delivery_fee_cents,
        'service_fee_cents',        v_service_fee_cents,
        'small_order_fee_cents',    v_small_order_fee_cents,
        'final_total_cents',        v_final_total_cents,
        'orig_total_cents',         v_orig_total_cents,
        'paid_cents',               v_paid_cents,
        'refund_cents',             v_refund_cents,
        'refund_method',            v_refund_method,
        'extra_charge_cents',       v_extra_charge_cents,
        'cash_extra_cents',         v_cash_extra_cents,
        'wallet_debit_cents',       v_wallet_debit_applied,
        'wallet_balance_after',     v_wallet_balance_after,
        'wallet_negative_enabled',  v_wallet_neg_enabled,
        'payment_status_before',    v_order.payment_status,
        'payment_status_after',     v_new_payment_status,
        'items_added_count',        jsonb_array_length(v_items_added_resolved),
        'markup_pct',               v_markup_pct,
        'max_extra_pct',            v_max_extra_pct,
        'warning',                  v_warning,
        'payment_method',           v_order.payment_method,
        'item_price_source',        'orders.items_canonical'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'finalize_storeshopping_purchase: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',              true,
    'order_id',             p_order_id,
    'service_type',         v_order.service_type,
    'is_partner_store',     COALESCE(v_order.is_partner_store, false),
    'final_total_cents',    v_final_total_cents,
    'orig_total_cents',     v_orig_total_cents,
    'paid_cents',           v_paid_cents,
    'refund_cents',         v_refund_cents,
    'refund_method',        v_refund_method,
    'extra_charge_cents',   v_extra_charge_cents,
    'cash_extra_cents',     v_cash_extra_cents,
    'wallet_debit_cents',   v_wallet_debit_applied,
    'wallet_balance_after', v_wallet_balance_after,
    'bag_fee_cents',        v_bag_fee_cents,
    'bag_count',            CASE WHEN v_is_restaurant THEN 1 ELSE COALESCE(p_bag_count, v_order.bag_count) END,
    'delivery_fee_cents',   v_delivery_fee_cents,
    'service_fee_cents',    v_service_fee_cents,
    'small_order_fee_cents', v_small_order_fee_cents,
    'payment_status',       v_new_payment_status,
    'items_added_count',    jsonb_array_length(v_items_added_resolved),
    'items_added',          v_items_added_resolved,
    'markup_pct',           v_markup_pct,
    'warning',              v_warning,
    'item_price_source',    'orders.items_canonical'
  );
END;
$function$;
