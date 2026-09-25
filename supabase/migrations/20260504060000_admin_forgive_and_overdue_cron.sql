-- ============================================================================
-- BORA — Sessão 3B-NOVA — admin_forgive_wallet_debt + pg_cron alertas (B11+B12)
-- ============================================================================
-- B11: admin perdoa dívida → wallet → 0, audit, INSERT settlement.
-- B12: pg_cron diário 09:00 UTC inserta alerta admin se cliente >90d/180d
--      sem actividade e wallet<0. Deduplica nas últimas 24h.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_forgive_wallet_debt(
  p_user_id UUID,
  p_reason  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance   INT;
  v_admin_id  UUID := auth.uid();
  v_role      TEXT := COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
    (auth.jwt() ->> 'role'));
  v_idem_key  TEXT;
BEGIN
  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'unauthorized: admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  SELECT free_balance_cents INTO v_balance
    FROM client_wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_balance IS NULL OR v_balance >= 0 THEN
    RAISE EXCEPTION 'wallet_not_negative: balance=%', COALESCE(v_balance, 0)
      USING ERRCODE = '23514';
  END IF;

  v_idem_key := 'forgive_' || p_user_id::text || '_' || extract(epoch from now())::bigint::text;

  INSERT INTO wallet_transactions
    (user_id, amount_cents, kind, reason, related_admin_id,
     balance_after_cents, idempotency_key)
  VALUES (p_user_id, -v_balance, 'forgive', p_reason, v_admin_id,
          0, v_idem_key);

  UPDATE client_wallets
    SET free_balance_cents = 0, updated_at = now()
    WHERE user_id = p_user_id;

  BEGIN
    PERFORM public.log_admin_action(
      'wallet_debt_forgiven', 'user', p_user_id,
      jsonb_build_object(
        'forgiven_cents', -v_balance,
        'reason', p_reason,
        'previous_balance', v_balance));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_forgive_wallet_debt audit failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'forgiven_cents', -v_balance,
    'previous_balance', v_balance);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_forgive_wallet_debt(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_forgive_wallet_debt(UUID, TEXT) TO authenticated;

-- ── B12: pg_cron job ──────────────────────────────────────────────────────
-- Garante extensão pg_cron disponível (Supabase production já tem).
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Drop job antigo se existir (idempotência da migration)
DO $$
BEGIN
  PERFORM cron.unschedule('wallet_overdue_alerts');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

SELECT cron.schedule(
  'wallet_overdue_alerts',
  '0 9 * * *',
  $cron$
  INSERT INTO public.admin_audit_log
    (action, entity_type, entity_id_text, details)
  SELECT
    CASE
      WHEN extract(day from now() - last_o.max_at)::int >= 180
        THEN 'wallet_action_required'
      ELSE 'wallet_overdue_alert'
    END,
    'user',
    cw.user_id::text,
    jsonb_build_object(
      'balance_cents', cw.free_balance_cents,
      'last_order_at', last_o.max_at,
      'days_inactive', extract(day from now() - last_o.max_at)::int)
  FROM public.client_wallets cw
  LEFT JOIN LATERAL (
    SELECT MAX(created_at) AS max_at
    FROM public.orders
    WHERE user_id = cw.user_id
  ) last_o ON true
  WHERE cw.free_balance_cents < 0
    AND last_o.max_at IS NOT NULL
    AND last_o.max_at < now() - interval '90 days'
    AND NOT EXISTS (
      SELECT 1 FROM public.admin_audit_log
      WHERE entity_type = 'user'
        AND entity_id_text = cw.user_id::text
        AND action LIKE 'wallet_%'
        AND created_at > now() - interval '24 hours'
    );
  $cron$
);

COMMIT;
