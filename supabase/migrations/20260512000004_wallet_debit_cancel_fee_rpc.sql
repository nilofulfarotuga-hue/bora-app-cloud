-- RPC débito da taxa de cancelamento (CASH ou MBWay não-pago).
-- Espelha pattern wallet_debit_for_order. Hard floor próprio: wallet_cancel_hard_floor_cents (-4000).
-- Idempotência via idempotency_key = 'cancel_fee_<order_id>'.
CREATE OR REPLACE FUNCTION public.wallet_debit_cancel_fee(
  p_user_id   uuid,
  p_order_id  text,
  p_fee_cents integer,
  p_tier      text
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_balance_after  INTEGER;
  v_hard_floor     INTEGER;
  v_idem_key       TEXT;
  v_existing_id    UUID;
BEGIN
  -- Validações input
  IF p_fee_cents <= 0 THEN
    RAISE EXCEPTION 'fee_must_be_positive';
  END IF;
  IF p_tier NOT IN ('before_dispatch','after_accept','after_pickup') THEN
    RAISE EXCEPTION 'invalid_tier: %', p_tier;
  END IF;

  v_idem_key := 'cancel_fee_' || p_order_id;

  -- Idempotência: se já existe débito para este pedido → retornar sem duplicar
  SELECT id INTO v_existing_id
    FROM public.wallet_transactions
    WHERE idempotency_key = v_idem_key
    LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    SELECT free_balance_cents INTO v_balance_after
      FROM public.client_wallets WHERE user_id = p_user_id;
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'debited_cents', p_fee_cents,
      'new_balance_cents', COALESCE(v_balance_after, 0),
      'tier', p_tier
    );
  END IF;

  -- Ler hard floor específico de cancel (default -4000)
  SELECT COALESCE((value::text)::int, -4000) INTO v_hard_floor
    FROM public.platform_settings WHERE key='wallet_cancel_hard_floor_cents';
  v_hard_floor := COALESCE(v_hard_floor, -4000);

  -- Garantir wallet existe + lock
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_balance_after := COALESCE(v_balance_before, 0) - p_fee_cents;

  IF v_balance_after < v_hard_floor THEN
    RAISE EXCEPTION 'wallet_cancel_hard_floor_exceeded: have=% need=% floor=%',
      COALESCE(v_balance_before, 0), p_fee_cents, v_hard_floor
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.client_wallets
    SET free_balance_cents = v_balance_after,
        updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id,
     balance_after_cents, idempotency_key)
  VALUES
    (p_user_id, -p_fee_cents, 'cancel_fee_debit',
     'Taxa de cancelamento ' || p_tier || ' (pedido ' || p_order_id || ')',
     p_order_id, v_balance_after, v_idem_key);

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'debited_cents', p_fee_cents,
    'new_balance_cents', v_balance_after,
    'tier', p_tier
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_debit_cancel_fee(uuid, text, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_debit_cancel_fee(uuid, text, integer, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.wallet_debit_cancel_fee(uuid, text, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.wallet_debit_cancel_fee(uuid, text, integer, text) TO service_role;

COMMENT ON FUNCTION public.wallet_debit_cancel_fee IS
'Débito wallet para taxa de cancelamento CASH ou MBWay não-pago. Hard floor próprio: -4000 cents (€40, vs €20 wallet_debit_for_order). Idempotente por idempotency_key=cancel_fee_<order_id>. Service-role only (Edge Functions cancel-order-with-choice e client-cancel-order).';
