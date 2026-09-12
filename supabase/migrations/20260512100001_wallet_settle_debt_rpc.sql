-- RPC liquidação de dívida wallet.
-- Aceita amount > dívida (excedente vira saldo positivo, 100% free_balance_cents — NÃO regra 80/20).
-- Idempotência via idempotency_key construída pelo caller.
-- Service-role only (stripe-webhook + trigger apply_client_debt_settlement_on_cash_delivery).
CREATE OR REPLACE FUNCTION public.wallet_settle_debt(
  p_user_id      uuid,
  p_amount_cents integer,
  p_source       text,
  p_idem_key     text
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_balance_after  INTEGER;
  v_was_debt       INTEGER;
  v_surplus        INTEGER;
  v_existing_id    UUID;
BEGIN
  IF p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_must_be_positive';
  END IF;
  IF p_idem_key IS NULL OR length(trim(p_idem_key)) < 3 THEN
    RAISE EXCEPTION 'idem_key_required';
  END IF;

  SELECT id INTO v_existing_id
    FROM public.wallet_transactions
    WHERE idempotency_key = p_idem_key
    LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    SELECT free_balance_cents INTO v_balance_after
      FROM public.client_wallets WHERE user_id = p_user_id;
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'settled_cents', p_amount_cents,
      'new_balance_cents', COALESCE(v_balance_after, 0),
      'was_debt_cents', 0,
      'surplus_cents', 0
    );
  END IF;

  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_balance_before IS NULL THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  v_was_debt := CASE WHEN v_balance_before < 0 THEN -v_balance_before ELSE 0 END;
  v_balance_after := v_balance_before + p_amount_cents;
  v_surplus := CASE
                 WHEN v_was_debt = 0 THEN p_amount_cents
                 WHEN p_amount_cents > v_was_debt THEN p_amount_cents - v_was_debt
                 ELSE 0
               END;

  UPDATE public.client_wallets
    SET free_balance_cents = v_balance_after,
        updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, balance_after_cents, idempotency_key)
  VALUES
    (p_user_id, p_amount_cents, 'settlement',
     'Pagamento de dívida (' || p_source || ')',
     v_balance_after, p_idem_key);

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'settled_cents', p_amount_cents,
    'new_balance_cents', v_balance_after,
    'was_debt_cents', v_was_debt,
    'surplus_cents', v_surplus
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) TO service_role;

COMMENT ON FUNCTION public.wallet_settle_debt IS
'Liquida dívida wallet (kind=settlement). Aceita amount > dívida (excedente = saldo positivo). Idempotente via idempotency_key. Service-role only.';
