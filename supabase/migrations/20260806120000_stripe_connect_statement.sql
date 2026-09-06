-- ============================================================================
-- Stripe Connect Fase 1 — extrato + eventos de webhook + espelho de conta.
-- NÃO move dinheiro: o acerto semanal continua manual. Transferências = Fase 2.
-- Rollback no fim do ficheiro (comentado).
-- ============================================================================

-- 1. Idempotência do webhook de Connect --------------------------------------
CREATE TABLE IF NOT EXISTS public.stripe_connect_events (
  event_id    text PRIMARY KEY,
  type        text NOT NULL,
  account_id  text,
  payload     jsonb,
  received_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.stripe_connect_events ENABLE ROW LEVEL SECURITY;
-- Sem policies: só service_role (webhook) lê/escreve.

-- 2. Linhas do extrato --------------------------------------------------------
-- owner_id é TEXT (não uuid): restaurants.id e service_providers.id são TEXT
-- legado; drivers/cleaners guardam o uuid como texto.
CREATE TABLE IF NOT EXISTS public.partner_statement_lines (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_type    text NOT NULL CHECK (owner_type IN ('partner','provider','driver','cleaner')),
  owner_id      text NOT NULL,
  occurred_at   timestamptz NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('sale','commission','stripe_fee','payout','adjustment')),
  reference     text,
  gross_cents   integer NOT NULL DEFAULT 0,
  amount_cents  integer NOT NULL,  -- positivo = entra, negativo = sai
  description   text NOT NULL,
  settlement_id uuid,
  created_at    timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_statement_owner
  ON public.partner_statement_lines (owner_type, owner_id, occurred_at DESC);

-- Dono: restaurants tem DUAS colunas de dono (user_ e user_id) — ler AMBAS.
CREATE OR REPLACE FUNCTION public.statement_owner_matches(p_owner_type text, p_owner_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE p_owner_type
    WHEN 'partner'  THEN EXISTS (SELECT 1 FROM restaurants r
                                 WHERE r.id = p_owner_id
                                   AND (r.user_ = auth.uid() OR r.user_id = auth.uid()))
    WHEN 'provider' THEN EXISTS (SELECT 1 FROM service_providers sp
                                 WHERE sp.id = p_owner_id AND sp.user_id = auth.uid())
    WHEN 'driver'   THEN EXISTS (SELECT 1 FROM drivers d
                                 WHERE d.id::text = p_owner_id
                                   AND (d.user_id = auth.uid() OR d.id = auth.uid()))
    WHEN 'cleaner'  THEN EXISTS (SELECT 1 FROM cleaners c
                                 WHERE c.id::text = p_owner_id
                                   AND (c.user_id = auth.uid() OR c.id = auth.uid()))
    ELSE false
  END;
$$;

ALTER TABLE public.partner_statement_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY statement_owner_select ON public.partner_statement_lines
  FOR SELECT TO authenticated
  USING (public.statement_owner_matches(owner_type, owner_id) OR public.is_admin());
-- Escrita: nenhuma policy → só service_role.

-- 3. Função ÚNICA de taxa Stripe (lê platform_settings, nunca hardcoded) ------
-- p_kind: 'processing' (por venda) ou 'payout' (rateio do pagamento semanal).
-- stripe_fee_bearer='platform' → parceiro vê 0 (a Bora absorve).
CREATE OR REPLACE FUNCTION public.stripe_connect_fee_cents(p_gross_cents integer, p_kind text DEFAULT 'processing')
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_bearer text;
  v_pct    numeric;
  v_fixed  numeric;
BEGIN
  SELECT COALESCE(value #>> '{}', 'partner') INTO v_bearer
    FROM platform_settings WHERE key = 'stripe_fee_bearer';
  IF v_bearer = 'platform' THEN
    RETURN 0;
  END IF;
  IF p_kind = 'payout' THEN
    v_pct   := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key = 'stripe_payout_fee_pct'), 0.0025);
    v_fixed := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key = 'stripe_payout_fee_fixed_cents'), 25);
  ELSE
    v_pct   := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key = 'stripe_processing_fee_pct'), 0.015);
    v_fixed := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key = 'stripe_processing_fee_fixed_cents'), 25);
  END IF;
  RETURN ROUND(COALESCE(p_gross_cents, 0) * v_pct)::integer + ROUND(v_fixed)::integer;
END;
$$;

-- 4. Espelho da conta Connect (fonte única — o webhook chama isto) ------------
-- Deriva o status: disabled > restricted > enabled > pending.
CREATE OR REPLACE FUNCTION public.apply_stripe_account_update(
  p_account_id      text,
  p_charges_enabled boolean,
  p_payouts_enabled boolean,
  p_currently_due   jsonb,
  p_disabled_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_status text;
  v_req    jsonb;
  v_found  text[] := '{}';
BEGIN
  v_status := CASE
    WHEN COALESCE(p_disabled_reason, '') <> '' THEN 'disabled'
    WHEN COALESCE(jsonb_array_length(p_currently_due), 0) > 0 THEN 'restricted'
    WHEN COALESCE(p_payouts_enabled, false) THEN 'enabled'
    ELSE 'pending'
  END;
  v_req := jsonb_build_object(
    'currently_due',   COALESCE(p_currently_due, '[]'::jsonb),
    'disabled_reason', p_disabled_reason
  );

  UPDATE restaurants SET
      stripe_charges_enabled = COALESCE(p_charges_enabled, false),
      stripe_payouts_enabled = COALESCE(p_payouts_enabled, false),
      stripe_requirements    = v_req,
      stripe_account_status  = v_status,
      stripe_onboarded_at    = COALESCE(stripe_onboarded_at,
                                 CASE WHEN v_status = 'enabled' THEN now() END)
    WHERE stripe_account_id = p_account_id;
  IF FOUND THEN v_found := array_append(v_found, 'partner'); END IF;

  UPDATE service_providers SET
      stripe_charges_enabled = COALESCE(p_charges_enabled, false),
      stripe_payouts_enabled = COALESCE(p_payouts_enabled, false),
      stripe_requirements    = v_req,
      stripe_account_status  = v_status,
      stripe_onboarded_at    = COALESCE(stripe_onboarded_at,
                                 CASE WHEN v_status = 'enabled' THEN now() END)
    WHERE stripe_account_id = p_account_id;
  IF FOUND THEN v_found := array_append(v_found, 'provider'); END IF;

  UPDATE drivers SET
      stripe_charges_enabled = COALESCE(p_charges_enabled, false),
      stripe_payouts_enabled = COALESCE(p_payouts_enabled, false),
      stripe_requirements    = v_req,
      stripe_account_status  = v_status,
      stripe_onboarded_at    = COALESCE(stripe_onboarded_at,
                                 CASE WHEN v_status = 'enabled' THEN now() END)
    WHERE stripe_account_id = p_account_id;
  IF FOUND THEN v_found := array_append(v_found, 'driver'); END IF;

  UPDATE cleaners SET
      stripe_charges_enabled = COALESCE(p_charges_enabled, false),
      stripe_payouts_enabled = COALESCE(p_payouts_enabled, false),
      stripe_requirements    = v_req,
      stripe_account_status  = v_status,
      stripe_onboarded_at    = COALESCE(stripe_onboarded_at,
                                 CASE WHEN v_status = 'enabled' THEN now() END)
    WHERE stripe_account_id = p_account_id;
  IF FOUND THEN v_found := array_append(v_found, 'cleaner'); END IF;

  RETURN jsonb_build_object('status', v_status, 'found', to_jsonb(v_found));
END;
$$;
-- Só o webhook (service_role) pode chamar.
REVOKE ALL ON FUNCTION public.apply_stripe_account_update(text, boolean, boolean, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_stripe_account_update(text, boolean, boolean, jsonb, text) TO service_role;

-- 5. RPC do extrato (utilizador autenticado; nunca aceita owner_id do cliente)
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
    )
  ) INTO v_result
  FROM tot, lp;

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_statement(timestamptz, timestamptz) TO authenticated;

-- 6. RPC admin: lista das contas Connect (painel PT-BR) -----------------------
CREATE OR REPLACE FUNCTION public.admin_list_connect_accounts()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(j ORDER BY j->>'role', j->>'name')
    FROM (
      SELECT jsonb_build_object(
        'role', 'partner', 'row_id', r.id::text, 'name', r.name,
        'account_id', r.stripe_account_id, 'status', r.stripe_account_status,
        'charges_enabled', r.stripe_charges_enabled, 'payouts_enabled', r.stripe_payouts_enabled,
        'requirements', r.stripe_requirements, 'onboarded_at', r.stripe_onboarded_at) AS j
      FROM restaurants r
      WHERE r.user_ IS NOT NULL OR r.user_id IS NOT NULL OR r.stripe_account_id IS NOT NULL
      UNION ALL
      SELECT jsonb_build_object(
        'role', 'provider', 'row_id', sp.id::text, 'name', sp.name,
        'account_id', sp.stripe_account_id, 'status', sp.stripe_account_status,
        'charges_enabled', sp.stripe_charges_enabled, 'payouts_enabled', sp.stripe_payouts_enabled,
        'requirements', sp.stripe_requirements, 'onboarded_at', sp.stripe_onboarded_at)
      FROM service_providers sp
      UNION ALL
      SELECT jsonb_build_object(
        'role', 'driver', 'row_id', d.id::text, 'name', d.name,
        'account_id', d.stripe_account_id, 'status', d.stripe_account_status,
        'charges_enabled', d.stripe_charges_enabled, 'payouts_enabled', d.stripe_payouts_enabled,
        'requirements', d.stripe_requirements, 'onboarded_at', d.stripe_onboarded_at)
      FROM drivers d
      UNION ALL
      SELECT jsonb_build_object(
        'role', 'cleaner', 'row_id', c.id::text, 'name', c.name,
        'account_id', c.stripe_account_id, 'status', c.stripe_account_status,
        'charges_enabled', c.stripe_charges_enabled, 'payouts_enabled', c.stripe_payouts_enabled,
        'requirements', c.stripe_requirements, 'onboarded_at', c.stripe_onboarded_at)
      FROM cleaners c
    ) t
  ), '[]'::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_connect_accounts() TO authenticated;

-- 7. Backfill retroativo a partir dos acertos semanais (idempotente) ----------
-- Estafetas (valores em euros → cêntimos).
INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'driver', s.driver_id::text, s.week_end_at, 'sale', NULL,
       ROUND(s.total_earnings * 100)::int, ROUND(s.total_earnings * 100)::int,
       'Ganhos da semana ' || to_char(s.week_start_at, 'DD/MM') || '–' || to_char(s.week_end_at, 'DD/MM'),
       s.id
FROM driver_weekly_settlements s
WHERE NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'sale');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'driver', s.driver_id::text, s.week_end_at, 'adjustment', NULL,
       0, ROUND((s.net_balance - s.total_earnings) * 100)::int,
       'Acertos da semana (dinheiro recebido / tokens)',
       s.id
FROM driver_weekly_settlements s
WHERE ROUND((s.net_balance - s.total_earnings) * 100)::int <> 0
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'adjustment');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'driver', s.driver_id::text, s.paid_at, 'payout', s.payment_reference,
       0, -ROUND(s.net_balance * 100)::int,
       'Pagamento semanal',
       s.id
FROM driver_weekly_settlements s
WHERE s.paid_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'payout');

-- Parceiros (restaurantes).
INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'partner', s.partner_id, s.week_end_at, 'sale', NULL,
       ROUND(s.gross_sales * 100)::int, ROUND(s.gross_sales * 100)::int,
       'Vendas da semana ' || to_char(s.week_start_at, 'DD/MM') || '–' || to_char(s.week_end_at, 'DD/MM'),
       s.id
FROM partner_weekly_settlements s
WHERE NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'sale');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'partner', s.partner_id, s.week_end_at, 'commission', NULL,
       0, -ROUND(s.commission_total * 100)::int,
       'Comissão Bora da semana',
       s.id
FROM partner_weekly_settlements s
WHERE ROUND(s.commission_total * 100)::int <> 0
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'commission');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'partner', s.partner_id, s.paid_at, 'payout', s.payment_reference,
       0, -ROUND(s.net_balance * 100)::int,
       'Pagamento semanal',
       s.id
FROM partner_weekly_settlements s
WHERE s.paid_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'payout');

-- Limpeza (valores já em cêntimos).
INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'cleaner', s.cleaner_id::text, s.week_end_at, 'sale', NULL,
       s.total_earnings_cents, s.total_earnings_cents,
       'Serviços da semana ' || to_char(s.week_start_at, 'DD/MM') || '–' || to_char(s.week_end_at, 'DD/MM'),
       s.id
FROM cleaner_weekly_settlements s
WHERE NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'sale');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'cleaner', s.cleaner_id::text, s.week_end_at, 'commission', NULL,
       0, -s.total_bora_fee_cents,
       'Taxa Bora da semana',
       s.id
FROM cleaner_weekly_settlements s
WHERE COALESCE(s.total_bora_fee_cents, 0) <> 0
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'commission');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'cleaner', s.cleaner_id::text, s.paid_at, 'payout', s.payment_reference,
       0, -s.net_payout_cents,
       'Pagamento semanal',
       s.id
FROM cleaner_weekly_settlements s
WHERE s.paid_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'payout');

-- Serviços/marcações (appointment_payouts, valores em cêntimos).
INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'provider', s.provider_id, s.week_end_at, 'sale', NULL,
       s.total_service_revenue_cents, s.total_service_revenue_cents,
       'Marcações da semana ' || to_char(s.week_start_at, 'DD/MM') || '–' || to_char(s.week_end_at, 'DD/MM'),
       s.id
FROM appointment_payouts s
WHERE NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'sale');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'provider', s.provider_id, s.week_end_at, 'commission', NULL,
       0, -(COALESCE(s.bora_booking_fees_cents, 0) + COALESCE(s.bora_deposit_cut_cents, 0)),
       'Taxas Bora da semana',
       s.id
FROM appointment_payouts s
WHERE (COALESCE(s.bora_booking_fees_cents, 0) + COALESCE(s.bora_deposit_cut_cents, 0)) <> 0
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'commission');

INSERT INTO public.partner_statement_lines
  (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
SELECT 'provider', s.provider_id, s.paid_at, 'payout', s.payment_reference,
       0, -s.net_payout_cents,
       'Pagamento semanal',
       s.id
FROM appointment_payouts s
WHERE s.paid_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'payout');

-- ============================================================================
-- ROLLBACK (executar por esta ordem se for preciso reverter):
--   DROP FUNCTION IF EXISTS public.admin_list_connect_accounts();
--   DROP FUNCTION IF EXISTS public.get_statement(timestamptz, timestamptz);
--   DROP FUNCTION IF EXISTS public.apply_stripe_account_update(text, boolean, boolean, jsonb, text);
--   DROP FUNCTION IF EXISTS public.stripe_connect_fee_cents(integer, text);
--   DROP POLICY IF EXISTS statement_owner_select ON public.partner_statement_lines;
--   DROP FUNCTION IF EXISTS public.statement_owner_matches(text, text);
--   DROP TABLE IF EXISTS public.partner_statement_lines;
--   DROP TABLE IF EXISTS public.stripe_connect_events;
-- ============================================================================
