-- ════════════════════════════════════════════════════════════════════
-- 7-FIX session 2026-05-07
-- BUG-7E-B-005: tokens factor ×20 → ×2 (correcto matemático para 1 token=€0.005)
-- BUG-7E-B-007: add_tokens silent fail (UUID vs TEXT mismatch entre orders.id
--               TEXT e bora_tokens.source_order_id UUID + add_tokens.p_order_id UUID)
-- ════════════════════════════════════════════════════════════════════

-- 1. Migrar bora_tokens.source_order_id de UUID para TEXT
DROP INDEX IF EXISTS idx_bora_tokens_order_role;

ALTER TABLE bora_tokens
  ALTER COLUMN source_order_id TYPE TEXT
  USING source_order_id::TEXT;

CREATE UNIQUE INDEX idx_bora_tokens_order_role
  ON bora_tokens USING btree (source_order_id, role)
  WHERE (source_order_id IS NOT NULL);

-- 2. Recriar add_tokens com p_order_id TEXT
DROP FUNCTION IF EXISTS public.add_tokens(uuid, text, integer, uuid);

CREATE OR REPLACE FUNCTION public.add_tokens(
  p_user_id  uuid,
  p_role     text,
  p_amount   integer,
  p_order_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO bora_tokens (
    user_id, role, amount, expires_at, source_order_id
  )
  VALUES (
    p_user_id, p_role, p_amount,
    now() + INTERVAL '60 days',
    p_order_id
  )
  ON CONFLICT (source_order_id, role)
    WHERE source_order_id IS NOT NULL
    DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

-- 3. Recriar fn_award_tokens_on_delivery — remover ::UUID cast
CREATE OR REPLACE FUNCTION public.fn_award_tokens_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_driver_tokens  INTEGER;
  v_client_tokens  INTEGER;
BEGIN
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  IF NEW.assigned_driver_id IS NOT NULL THEN
    v_driver_tokens := CASE WHEN NEW.is_partner_store THEN 50 ELSE 40 END;
    PERFORM add_tokens(
      NEW.assigned_driver_id::UUID,
      'driver',
      v_driver_tokens,
      NEW.id  -- text directo, sem cast (orders.id é text)
    );
  END IF;

  IF NEW.user_id IS NOT NULL AND NEW.price IS NOT NULL AND NEW.price > 0 THEN
    v_client_tokens := GREATEST(1, ROUND(NEW.price * 3)::INTEGER);
    PERFORM add_tokens(
      NEW.user_id,
      'client',
      v_client_tokens,
      NEW.id  -- text directo, sem cast
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- 4. Recriar wallet_credit_refund_split — fix factor ×20 → ×2 (BUG-005)
CREATE OR REPLACE FUNCTION public.wallet_credit_refund_split(
  p_order_id    text,
  p_user_id     uuid,
  p_total_cents integer,
  p_reason      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_debt_cleared   INTEGER := 0;
  v_remaining      INTEGER;
  v_split_pct      NUMERIC;
  v_free_amount    INTEGER;
  v_tokens_amount  INTEGER;
  v_tokens_count   INTEGER;
  v_balance_mid    INTEGER;
  v_token_id       UUID;
BEGIN
  IF p_total_cents <= 0 THEN RAISE EXCEPTION 'total_must_be_positive'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_required'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0) ON CONFLICT (user_id) DO NOTHING;
  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_remaining := p_total_cents;

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

  IF v_remaining > 0 THEN
    SELECT COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80)
      INTO v_split_pct;

    v_free_amount   := ROUND(v_remaining * v_split_pct);
    v_tokens_amount := v_remaining - v_free_amount;

    -- ★ FIX BUG-7E-B-005: factor ×2 (era ×20)
    -- 1 token = €0.005 → 1 cent gasto em tokens = 2 tokens
    v_tokens_count  := v_tokens_amount * 2;

    UPDATE public.client_wallets
      SET free_balance_cents = free_balance_cents + v_free_amount,
          updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents)
      VALUES (p_user_id, v_free_amount, 'refund_credit_free',
              p_reason, p_order_id, v_balance_mid + v_free_amount);

    -- ★ FIX BUG-7E-B-007: add_tokens aceita text directo agora
    -- Sem try/except — deixar erro propagar para diagnóstico futuro
    IF v_tokens_count > 0 THEN
      v_token_id := public.add_tokens(p_user_id, 'client', v_tokens_count, p_order_id);

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
$function$;
