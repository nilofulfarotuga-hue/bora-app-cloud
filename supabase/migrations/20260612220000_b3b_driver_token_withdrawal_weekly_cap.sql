-- B3b (2026-06-12) — Cap semanal de saque de tokens do estafeta.
-- BUG confirmado: o fluxo antigo era 100% client-side (consume_tokens +
-- INSERT manual em driver_transactions + UPDATE driver_balances) e o cap de
-- 50% era só por chamada — o estafeta podia sacar 50%+50%+50%... até esvaziar
-- o saldo na mesma semana.
-- Regra: máx token_withdrawal_max_pct_weekly (50%) do saldo POR SEMANA
-- (segunda 00:00 → domingo 23:59; date_trunc('week') = segunda).
-- Fórmula (spec Danilo): ja_sacado_na_semana + novo > saldo_atual × pct →
-- RAISE token_withdrawal_weekly_cap_exceeded.
-- Nova RPC atómica driver_convert_tokens(p_amount): valida cap → consome
-- tokens → regista driver_transactions (type=token_conversion, lido pelo
-- compute_driver_settlement) → credita driver_balances. O Flutter passa a
-- chamar só esta RPC.

CREATE OR REPLACE FUNCTION public.driver_convert_tokens(p_amount integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_driver_id        UUID;
  v_balance          INTEGER;
  v_pct              NUMERIC;
  v_token_value_eur  NUMERIC;
  v_week_start       TIMESTAMPTZ;
  v_already_eur      NUMERIC;
  v_already_tokens   INTEGER;
  v_cap_tokens       INTEGER;
  v_amount_eur       NUMERIC;
  v_consumed         BOOLEAN;
BEGIN
  v_driver_id := auth.uid();
  IF v_driver_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: driver_convert_tokens requires an authenticated session';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM drivers WHERE id = v_driver_id) THEN
    RAISE EXCEPTION 'NOT_A_DRIVER: %', v_driver_id;
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: %', p_amount;
  END IF;

  SELECT (value::text)::NUMERIC INTO v_pct
    FROM platform_settings WHERE key = 'token_withdrawal_max_pct_weekly';
  v_pct := COALESCE(v_pct, 50);

  -- token_value_cents_x100 = 50 → 1 token = 0,5 cents = €0,005.
  SELECT (value::text)::NUMERIC INTO v_token_value_eur
    FROM platform_settings WHERE key = 'token_value_cents_x100';
  v_token_value_eur := COALESCE(v_token_value_eur, 50) / 10000.0;

  v_balance := COALESCE(get_user_tokens(v_driver_id), 0);

  -- Semana civil: segunda 00:00 → domingo 23:59.
  v_week_start := date_trunc('week', now());

  SELECT COALESCE(SUM(amount), 0) INTO v_already_eur
    FROM driver_transactions
    WHERE driver_id = v_driver_id
      AND type = 'token_conversion'
      AND status = 'completed'
      AND created_at >= v_week_start;
  v_already_tokens := ROUND(v_already_eur / v_token_value_eur)::INTEGER;

  v_cap_tokens := FLOOR(v_balance * v_pct / 100.0)::INTEGER;
  IF v_already_tokens + p_amount > v_cap_tokens THEN
    RAISE EXCEPTION 'token_withdrawal_weekly_cap_exceeded: already=% new=% cap=% balance=%',
      v_already_tokens, p_amount, v_cap_tokens, v_balance USING ERRCODE = '23514';
  END IF;

  v_consumed := consume_tokens(v_driver_id, p_amount);
  IF NOT v_consumed THEN
    RAISE EXCEPTION 'INSUFFICIENT_TOKENS: balance=% requested=%', v_balance, p_amount;
  END IF;

  v_amount_eur := ROUND(p_amount * v_token_value_eur, 2);

  INSERT INTO driver_transactions (driver_id, amount, type, status, notes)
  VALUES (v_driver_id, v_amount_eur, 'token_conversion', 'completed',
          p_amount || ' tokens convertidos (cap semanal ' || v_pct || '%)');

  UPDATE driver_balances SET balance = balance + v_amount_eur
    WHERE driver_id = v_driver_id;
  IF NOT FOUND THEN
    INSERT INTO driver_balances (driver_id, balance)
    VALUES (v_driver_id, v_amount_eur);
  END IF;

  RETURN jsonb_build_object(
    'converted_tokens', p_amount,
    'amount_eur', v_amount_eur,
    'week_converted_tokens_before', v_already_tokens,
    'weekly_cap_tokens', v_cap_tokens,
    'balance_before', v_balance
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.driver_convert_tokens(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_convert_tokens(integer) TO authenticated;
