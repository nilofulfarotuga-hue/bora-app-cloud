-- ============================================================================
-- BORA — Sessão 3B-NOVA — RPC wallet_apply_post_delivery_adjustment (B3)
-- + ajustes wallet_debit_for_order (permitir negativo)
-- + ajuste wallet_credit_refund_split (abater dívida se negativo)
-- ============================================================================

BEGIN;

-- ── B3: wallet_apply_post_delivery_adjustment ──────────────────────────────
-- Chamado pelo finalize_storeshopping_purchase quando há extra a cobrar
-- (sacos mercado, substituições, adições) em pedidos card/mbway.
-- Aplica débito directo na wallet, podendo levá-la a saldo negativo.
-- Idempotente via (order_id + kind) → repetir não duplica.
CREATE OR REPLACE FUNCTION public.wallet_apply_post_delivery_adjustment(
  p_order_id      TEXT,
  p_user_id       UUID,
  p_amount_cents  INTEGER,
  p_reason        TEXT,
  p_kind          TEXT DEFAULT 'debit'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller         UUID := auth.uid();
  v_role           TEXT := COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
    (auth.jwt() ->> 'role'));
  v_assigned       TEXT;
  v_balance_before INTEGER;
  v_balance_after  INTEGER;
  v_max_cents      INTEGER;
  v_hard_floor     INTEGER;
  v_idem_key       TEXT;
  v_existing       RECORD;
BEGIN
  -- 1. Validar parâmetros
  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_must_be_positive: %', p_amount_cents
      USING ERRCODE = '23514';
  END IF;
  IF p_kind NOT IN ('debit','adjustment') THEN
    RAISE EXCEPTION 'invalid_kind: % (expected debit|adjustment)', p_kind
      USING ERRCODE = '23514';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  -- 2. Cap absoluto €10/pedido
  SELECT COALESCE((value::text)::int, 1000) INTO v_max_cents
    FROM public.platform_settings WHERE key='max_extra_charge_cents';
  v_max_cents := COALESCE(v_max_cents, 1000);
  IF p_amount_cents > v_max_cents THEN
    RAISE EXCEPTION 'amount_exceeds_cap: requested=% cap=%',
      p_amount_cents, v_max_cents
      USING ERRCODE = '23514';
  END IF;

  -- 3. Authz: caller deve ser estafeta atribuído OR admin OR service_role
  SELECT assigned_driver_id INTO v_assigned
    FROM public.orders WHERE id = p_order_id;
  IF v_assigned IS NULL THEN
    RAISE EXCEPTION 'order_not_found_or_not_assigned: %', p_order_id
      USING ERRCODE = 'P0002';
  END IF;
  IF v_role <> 'admin'
     AND v_role <> 'service_role'
     AND v_assigned IS DISTINCT FROM v_caller::text THEN
    RAISE EXCEPTION 'forbidden: caller=% is not assigned driver/admin', v_caller
      USING ERRCODE = '42501';
  END IF;

  -- 4. Idempotency: chave determinística (order_id + kind)
  v_idem_key := 'adj_' || p_order_id || '_' || p_kind;
  SELECT * INTO v_existing
    FROM public.wallet_transactions
    WHERE idempotency_key = v_idem_key
    LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'idempotent_replay', true,
      'idempotency_key', v_idem_key,
      'amount_cents', -v_existing.amount_cents,
      'new_balance_cents', v_existing.balance_after_cents
    );
  END IF;

  -- 5. Hard floor defensivo (espelho do CHECK)
  SELECT COALESCE((value::text)::int, -2000) INTO v_hard_floor
    FROM public.platform_settings WHERE key='wallet_hard_floor_cents';
  v_hard_floor := COALESCE(v_hard_floor, -2000);

  -- 6. SELECT FOR UPDATE wallet (cria se não existe)
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets
    WHERE user_id = p_user_id
    FOR UPDATE;

  v_balance_after := v_balance_before - p_amount_cents;
  IF v_balance_after < v_hard_floor THEN
    RAISE EXCEPTION 'wallet_hard_floor_exceeded: would_be=% floor=%',
      v_balance_after, v_hard_floor
      USING ERRCODE = '23514';
  END IF;

  -- 7. UPDATE wallet + INSERT transaction (com idempotency_key + balance_after)
  UPDATE public.client_wallets
    SET free_balance_cents = v_balance_after,
        updated_at = now()
    WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id,
     balance_after_cents, idempotency_key)
  VALUES
    (p_user_id, -p_amount_cents, p_kind, p_reason, p_order_id,
     v_balance_after, v_idem_key);

  -- 8. Audit log (best-effort)
  BEGIN
    INSERT INTO public.admin_audit_log
      (action, entity_type, entity_id_text, details)
    VALUES (
      'wallet_post_delivery_adjustment',
      'order',
      p_order_id,
      jsonb_build_object(
        'user_id', p_user_id,
        'amount_cents', p_amount_cents,
        'kind', p_kind,
        'reason', p_reason,
        'balance_before_cents', v_balance_before,
        'balance_after_cents', v_balance_after,
        'crossed_zero', (v_balance_before >= 0 AND v_balance_after < 0)
      ));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'wallet_apply_post_delivery_adjustment audit failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'idempotent_replay', false,
    'idempotency_key', v_idem_key,
    'amount_cents', p_amount_cents,
    'balance_before_cents', v_balance_before,
    'new_balance_cents', v_balance_after,
    'was_negative_before', v_balance_before < 0,
    'is_negative_after', v_balance_after < 0,
    'crossed_zero', (v_balance_before >= 0 AND v_balance_after < 0)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_apply_post_delivery_adjustment(TEXT, UUID, INTEGER, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_apply_post_delivery_adjustment(TEXT, UUID, INTEGER, TEXT, TEXT) TO authenticated, service_role;

-- ── B3b: wallet_debit_for_order — permitir negativo até hard floor ────────
-- (Usado por create_order quando cliente aplica saldo no checkout.)
-- Continua a RAISE quando ultrapassa hard floor; remove o gate antigo
-- 'insufficient_balance' que assumia floor=0.
CREATE OR REPLACE FUNCTION public.wallet_debit_for_order(
  p_user_id     UUID,
  p_order_id    TEXT,
  p_amount_cents INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance_before INTEGER;
  v_balance_after  INTEGER;
  v_hard_floor     INTEGER;
BEGIN
  IF p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_must_be_positive';
  END IF;

  SELECT COALESCE((value::text)::int, -2000) INTO v_hard_floor
    FROM public.platform_settings WHERE key='wallet_hard_floor_cents';
  v_hard_floor := COALESCE(v_hard_floor, -2000);

  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_balance_after := COALESCE(v_balance_before, 0) - p_amount_cents;

  IF v_balance_after < v_hard_floor THEN
    RAISE EXCEPTION 'wallet_hard_floor_exceeded: have=% need=% floor=%',
      COALESCE(v_balance_before, 0), p_amount_cents, v_hard_floor
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.client_wallets
    SET free_balance_cents = v_balance_after,
        updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id,
     balance_after_cents)
  VALUES
    (p_user_id, -p_amount_cents, 'order_payment',
     'Pagamento pedido com saldo livre', p_order_id, v_balance_after);

  RETURN jsonb_build_object(
    'success', true,
    'debited_cents', p_amount_cents,
    'new_balance_cents', v_balance_after
  );
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_debit_for_order(UUID, TEXT, INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_debit_for_order(UUID, TEXT, INTEGER) TO authenticated, service_role;

-- ── B3c: wallet_credit_refund_split — abater dívida primeiro ──────────────
-- Se balance < 0, parte do refund vai para zerar a dívida; só o resto entra
-- no split 80/20 livre/tokens.
CREATE OR REPLACE FUNCTION public.wallet_credit_refund_split(
  p_order_id    TEXT,
  p_user_id     UUID,
  p_total_cents INTEGER,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance_before INTEGER;
  v_debt_cleared   INTEGER := 0;
  v_remaining      INTEGER;
  v_split_pct      NUMERIC;
  v_free_amount    INTEGER;
  v_tokens_amount  INTEGER;
  v_tokens_count   INTEGER;
  v_balance_mid    INTEGER;
BEGIN
  IF p_total_cents <= 0 THEN RAISE EXCEPTION 'total_must_be_positive'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_required'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  -- 0. Lock + ler balance
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0) ON CONFLICT (user_id) DO NOTHING;
  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_remaining := p_total_cents;

  -- 1. Se balance negativo: abater dívida primeiro (kind='settlement')
  IF v_balance_before < 0 THEN
    v_debt_cleared := LEAST(-v_balance_before, v_remaining);
    v_balance_mid  := v_balance_before + v_debt_cleared;
    UPDATE public.client_wallets
      SET free_balance_cents = v_balance_mid, updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents)
      VALUES (p_user_id, v_debt_cleared, 'settlement',
              p_reason || ' (refund→settle debt)', p_order_id, v_balance_mid);
    v_remaining := v_remaining - v_debt_cleared;
  ELSE
    v_balance_mid := v_balance_before;
  END IF;

  -- 2. Split 80/20 do remanescente
  IF v_remaining > 0 THEN
    SELECT COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80)
      INTO v_split_pct;

    v_free_amount   := ROUND(v_remaining * v_split_pct);
    v_tokens_amount := v_remaining - v_free_amount;
    v_tokens_count  := v_tokens_amount * 20;

    -- Free
    UPDATE public.client_wallets
      SET free_balance_cents = free_balance_cents + v_free_amount,
          updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents)
      VALUES (p_user_id, v_free_amount, 'refund_credit_free',
              p_reason, p_order_id, v_balance_mid + v_free_amount);

    -- Tokens
    IF v_tokens_count > 0 THEN
      BEGIN
        PERFORM public.add_tokens(p_user_id, 'client', v_tokens_count, p_order_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'add_tokens failed in refund_split: %', SQLERRM;
      END;
      INSERT INTO public.wallet_transactions
        (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents)
        VALUES (p_user_id, v_tokens_amount, 'refund_credit_tokens',
                p_reason || ' (' || v_tokens_count || ' tokens)', p_order_id,
                v_balance_mid + v_free_amount);
    END IF;
  ELSE
    v_free_amount   := 0;
    v_tokens_amount := 0;
    v_tokens_count  := 0;
    v_split_pct     := COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80);
  END IF;

  BEGIN
    PERFORM public.log_admin_action('wallet_refund_split','order',NULL,
      jsonb_build_object('order_id',p_order_id,'user_id',p_user_id,
        'total_cents',p_total_cents,'debt_cleared_cents',v_debt_cleared,
        'free_cents',v_free_amount,'tokens_cents_value',v_tokens_amount,
        'tokens_count',v_tokens_count,'split_pct',v_split_pct,
        'balance_before_cents',v_balance_before));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'debt_cleared_cents', v_debt_cleared,
    'free_cents', v_free_amount,
    'tokens_count', v_tokens_count,
    'tokens_value_cents', v_tokens_amount,
    'split_pct', v_split_pct,
    'balance_before_cents', v_balance_before
  );
END;
$$;
REVOKE ALL ON FUNCTION public.wallet_credit_refund_split(TEXT, UUID, INTEGER, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.wallet_credit_refund_split(TEXT, UUID, INTEGER, TEXT) TO authenticated, service_role;

COMMIT;
