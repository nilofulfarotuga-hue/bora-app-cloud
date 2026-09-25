-- ============================================================================
-- Stripe Connect Fase 1 (parte 2) — RPC de estado para os ecrãs do app.
-- get_my_connect_status: estado da conta do próprio utilizador (nunca aceita id).
-- get_statement: + flag connect_enabled (rodapé "pagamento por transferência").
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.get_my_connect_status(text);
--   (get_statement: reverter para a versão de 20260806120000)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_my_connect_status(p_role text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_role = 'partner' THEN
    SELECT r.id::text AS row_id, r.name, r.stripe_account_id, r.stripe_account_status,
           r.stripe_charges_enabled, r.stripe_payouts_enabled, r.stripe_requirements,
           r.stripe_onboarded_at
      INTO v_row
      FROM restaurants r
     WHERE r.user_ = v_uid OR r.user_id = v_uid
     LIMIT 1;
  ELSIF p_role = 'provider' THEN
    SELECT sp.id::text, sp.name, sp.stripe_account_id, sp.stripe_account_status,
           sp.stripe_charges_enabled, sp.stripe_payouts_enabled, sp.stripe_requirements,
           sp.stripe_onboarded_at
      INTO v_row
      FROM service_providers sp
     WHERE sp.user_id = v_uid
     LIMIT 1;
  ELSIF p_role = 'driver' THEN
    SELECT d.id::text, d.name, d.stripe_account_id, d.stripe_account_status,
           d.stripe_charges_enabled, d.stripe_payouts_enabled, d.stripe_requirements,
           d.stripe_onboarded_at
      INTO v_row
      FROM drivers d
     WHERE d.user_id = v_uid OR d.id = v_uid
     LIMIT 1;
  ELSIF p_role = 'cleaner' THEN
    SELECT c.id::text, c.name, c.stripe_account_id, c.stripe_account_status,
           c.stripe_charges_enabled, c.stripe_payouts_enabled, c.stripe_requirements,
           c.stripe_onboarded_at
      INTO v_row
      FROM cleaners c
     WHERE c.user_id = v_uid OR c.id = v_uid
     LIMIT 1;
  ELSE
    RAISE EXCEPTION 'invalid_role';
  END IF;

  IF v_row IS NULL OR v_row.row_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'row_id',          v_row.row_id,
    'name',            v_row.name,
    'account_id',      v_row.stripe_account_id,
    'status',          COALESCE(v_row.stripe_account_status, 'none'),
    'charges_enabled', COALESCE(v_row.stripe_charges_enabled, false),
    'payouts_enabled', COALESCE(v_row.stripe_payouts_enabled, false),
    'requirements',    v_row.stripe_requirements,
    'onboarded_at',    v_row.stripe_onboarded_at,
    'connect_enabled', COALESCE((SELECT (value #>> '{}')::boolean
                                   FROM platform_settings
                                  WHERE key = 'stripe_connect_enabled'), false)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_connect_status(text) TO authenticated;

-- get_statement v2: + connect_enabled (o resto é idêntico à versão anterior).
CREATE OR REPLACE FUNCTION public.get_statement(p_from timestamptz, p_to timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  WITH owners AS (
    SELECT 'partner' AS owner_type, r.id AS owner_id
      FROM restaurants r WHERE r.user_ = v_uid OR r.user_id = v_uid
    UNION ALL
    SELECT 'provider', sp.id FROM service_providers sp WHERE sp.user_id = v_uid
    UNION ALL
    SELECT 'driver', d.id::text FROM drivers d WHERE d.user_id = v_uid OR d.id = v_uid
    UNION ALL
    SELECT 'cleaner', c.id::text FROM cleaners c WHERE c.user_id = v_uid OR c.id = v_uid
  ),
  sel AS (
    SELECT l.*
      FROM partner_statement_lines l
      JOIN owners o ON o.owner_type = l.owner_type AND o.owner_id = l.owner_id
     WHERE l.occurred_at >= p_from AND l.occurred_at < p_to
  ),
  tot AS (
    SELECT COALESCE(SUM(amount_cents) FILTER (WHERE kind = 'sale'), 0)        AS sold,
           COALESCE(-SUM(amount_cents) FILTER (WHERE kind = 'commission'), 0) AS commission,
           COALESCE(-SUM(amount_cents) FILTER (WHERE kind = 'stripe_fee'), 0) AS fees,
           COALESCE(SUM(amount_cents) FILTER (WHERE kind = 'adjustment'), 0)  AS adjust
      FROM sel
  ),
  lp AS (
    SELECT MAX(l.occurred_at) AS last_payout_at
      FROM partner_statement_lines l
      JOIN owners o ON o.owner_type = l.owner_type AND o.owner_id = l.owner_id
     WHERE l.kind = 'payout'
  )
  SELECT jsonb_build_object(
    'lines', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.occurred_at DESC) FROM sel s), '[]'::jsonb),
    'totals', jsonb_build_object(
      'sold_cents',       tot.sold,
      'commission_cents', tot.commission,
      'stripe_fee_cents', tot.fees,
      'adjustment_cents', tot.adjust,
      'net_cents',        tot.sold - tot.commission - tot.fees + tot.adjust,
      'last_payout_at',   lp.last_payout_at
    ),
    'connect_enabled', COALESCE((SELECT (value #>> '{}')::boolean
                                   FROM platform_settings
                                  WHERE key = 'stripe_connect_enabled'), false)
  ) INTO v_result
  FROM tot, lp;

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_statement(timestamptz, timestamptz) TO authenticated;
