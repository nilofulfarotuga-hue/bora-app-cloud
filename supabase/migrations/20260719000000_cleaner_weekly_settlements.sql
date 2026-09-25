-- ============================================================================
-- BORA — Repasse semanal da LIMPEZA (cleaner_weekly_settlements)
-- ----------------------------------------------------------------------------
-- Fecha o buraco da auditoria 2026-07-19: todas as verticais têm fecho/repasse
-- semanal MENOS a limpeza. Cada cleaning_booking já grava cleaner_earnings_cents
-- (85% + produtos, calculado no ato), mas NADA consolidava por semana.
--
-- Copia o padrão JÁ COMPROVADO do estafeta (driver_weekly_settlements) e da
-- beleza (appointment_payouts / compute_provider_weekly_payout):
--   • REUTILIZA driver_settlement_week_bounds(anchor) — semana seg→dom Lisbon.
--   • Conta pela data do SERVIÇO FEITO (completed_at, fallback scheduled_at),
--     NUNCA pela data do pagamento — igual às outras verticais.
--   • Só bookings status='completed' e NÃO-teste entram no ganho.
--   • Cron 'cleaning-weekly-settlement' seg 08:00 (igual à beleza).
--
-- Aditivo e idempotente. NÃO altera valores cobrados/pagos — apenas consolida
-- o que já foi calculado por booking. Marcar "pago" é registo contabilístico
-- (não move dinheiro por si).
-- ============================================================================

BEGIN;

-- ─── Tabela ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cleaner_weekly_settlements (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cleaner_id            UUID NOT NULL REFERENCES public.cleaners(id),
  week_start_at         TIMESTAMPTZ NOT NULL,
  week_end_at           TIMESTAMPTZ NOT NULL,
  total_jobs            INT NOT NULL DEFAULT 0,
  total_earnings_cents  INT NOT NULL DEFAULT 0,   -- SUM(cleaner_earnings_cents)
  total_bora_fee_cents  INT NOT NULL DEFAULT 0,   -- SUM(bora_fee_cents) — informativo
  net_payout_cents      INT NOT NULL DEFAULT 0,   -- o que a Bora deve à profissional
  direction             TEXT NOT NULL DEFAULT 'bora_to_cleaner',
  status                TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','paid','received','disputed')),
  payment_method        TEXT,
  payment_reference     TEXT,
  paid_at               TIMESTAMPTZ,
  paid_by               UUID,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(cleaner_id, week_start_at)
);

CREATE INDEX IF NOT EXISTS idx_cleaner_settlements_status
  ON public.cleaner_weekly_settlements(status);
CREATE INDEX IF NOT EXISTS idx_cleaner_settlements_week
  ON public.cleaner_weekly_settlements(week_start_at);
CREATE INDEX IF NOT EXISTS idx_cleaner_settlements_cleaner_week
  ON public.cleaner_weekly_settlements(cleaner_id, week_start_at);

-- ─── RLS: leitura pelo próprio cleaner (cleaner_id → user_id) OU admin; ──────
--         escrita só admin (a persistência real corre por SECURITY DEFINER).
ALTER TABLE public.cleaner_weekly_settlements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cws_select ON public.cleaner_weekly_settlements;
CREATE POLICY cws_select
  ON public.cleaner_weekly_settlements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.cleaners c
      WHERE c.id = cleaner_weekly_settlements.cleaner_id
        AND (c.user_id = auth.uid() OR public.is_admin())
    )
  );

DROP POLICY IF EXISTS cws_write ON public.cleaner_weekly_settlements;
CREATE POLICY cws_write
  ON public.cleaner_weekly_settlements FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ─── compute_cleaner_weekly_settlement ───────────────────────────────────────
-- Calcula (e opcionalmente persiste) o fecho de UMA semana de UM cleaner.
CREATE OR REPLACE FUNCTION public.compute_cleaner_weekly_settlement(
  p_cleaner_id UUID,
  p_week_start TIMESTAMPTZ DEFAULT NULL,
  p_persist    BOOLEAN     DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_bounds        RECORD;
  v_anchor        TIMESTAMPTZ := COALESCE(p_week_start, now());
  v_total_jobs    INT := 0;
  v_total_earn    INT := 0;
  v_total_fee     INT := 0;
  v_net           INT := 0;
  v_id            UUID;
BEGIN
  -- Gate: só admin ou contexto de sistema (cron/service_role sem auth.uid()).
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds
  FROM public.driver_settlement_week_bounds(v_anchor);

  -- REGRA CRÍTICA: só serviços realmente FEITOS (status='completed'), não-teste,
  -- contados pela data do SERVIÇO (completed_at, fallback scheduled_at), nunca
  -- pela data do pagamento. Cancelados/no-show NÃO entram no ganho (não há regra
  -- de compensação de limpeza documentada → caminho conservador).
  SELECT
    COUNT(*),
    COALESCE(SUM(cleaner_earnings_cents), 0),
    COALESCE(SUM(bora_fee_cents), 0)
  INTO v_total_jobs, v_total_earn, v_total_fee
  FROM public.cleaning_bookings
  WHERE cleaner_id = p_cleaner_id
    AND status = 'completed'
    AND COALESCE(is_test_order, false) = false
    AND COALESCE(completed_at, scheduled_at) >= v_bounds.week_start
    AND COALESCE(completed_at, scheduled_at) <= v_bounds.week_end;

  v_net := v_total_earn;  -- líquido a repassar = o que já foi calculado por booking

  IF p_persist THEN
    INSERT INTO public.cleaner_weekly_settlements (
      cleaner_id, week_start_at, week_end_at,
      total_jobs, total_earnings_cents, total_bora_fee_cents,
      net_payout_cents, direction, status
    ) VALUES (
      p_cleaner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_jobs, v_total_earn, v_total_fee,
      v_net, 'bora_to_cleaner', 'pending'
    )
    ON CONFLICT (cleaner_id, week_start_at) DO UPDATE SET
      week_end_at          = EXCLUDED.week_end_at,
      total_jobs           = EXCLUDED.total_jobs,
      total_earnings_cents = EXCLUDED.total_earnings_cents,
      total_bora_fee_cents = EXCLUDED.total_bora_fee_cents,
      net_payout_cents     = EXCLUDED.net_payout_cents
      -- status/paid_at preservados (não mexe num fecho já pago) — igual à beleza.
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'cleaner_id',           p_cleaner_id,
    'week_start',           v_bounds.week_start,
    'week_end',             v_bounds.week_end,
    'total_jobs',           v_total_jobs,
    'total_earnings_cents', v_total_earn,
    'total_bora_fee_cents', v_total_fee,
    'net_payout_cents',     v_net,
    'settlement_id',        v_id,
    'persisted',            p_persist
  );
END;
$function$;

-- ─── compute_all_cleaner_weekly_settlements (cron) ───────────────────────────
-- Fecha a SEMANA ANTERIOR (corre segunda). 1 row por cleaner com serviço feito.
CREATE OR REPLACE FUNCTION public.compute_all_cleaner_weekly_settlements()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count  INT := 0;
  v_anchor TIMESTAMPTZ := now() - interval '1 day';  -- ontem = domingo da semana fechada
  v_row    RECORD;
BEGIN
  FOR v_row IN
    SELECT DISTINCT cb.cleaner_id AS id
    FROM public.cleaning_bookings cb,
         public.driver_settlement_week_bounds(v_anchor) b
    WHERE cb.status = 'completed'
      AND COALESCE(cb.is_test_order, false) = false
      AND cb.cleaner_id IS NOT NULL
      AND COALESCE(cb.completed_at, cb.scheduled_at) >= b.week_start
      AND COALESCE(cb.completed_at, cb.scheduled_at) <= b.week_end
  LOOP
    PERFORM public.compute_cleaner_weekly_settlement(v_row.id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

-- ─── Admin RPCs (espelham o trio da beleza) ─────────────────────────────────
-- Listar fechos (join com nome da profissional).
CREATE OR REPLACE FUNCTION public.admin_list_cleaner_settlements(
  p_cleaner_id UUID DEFAULT NULL,
  p_status     TEXT DEFAULT NULL,
  p_limit      INT  DEFAULT 200
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO r FROM (
    SELECT cws.*, c.name AS cleaner_name
    FROM public.cleaner_weekly_settlements cws
    JOIN public.cleaners c ON c.id = cws.cleaner_id
    WHERE (p_cleaner_id IS NULL OR cws.cleaner_id = p_cleaner_id)
      AND (p_status IS NULL OR cws.status = p_status)
    ORDER BY cws.week_start_at DESC
    LIMIT p_limit
  ) t;
  RETURN r;
END;
$function$;

-- Marcar pago (todos os pendentes de 1 profissional).
CREATE OR REPLACE FUNCTION public.admin_mark_cleaner_settlements_paid(
  p_cleaner_id        UUID,
  p_payout_external_id UUID DEFAULT gen_random_uuid(),
  p_payment_method    TEXT DEFAULT 'mbway',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_count int; v_total int;
BEGIN
  PERFORM public._admin_op_guard();
  WITH updated AS (
    UPDATE public.cleaner_weekly_settlements
    SET status            = 'paid',
        paid_at           = now(),
        payment_method    = COALESCE(p_payment_method, payment_method, 'mbway'),
        payment_reference = COALESCE(p_payment_reference, p_payout_external_id::text),
        paid_by           = auth.uid()
    WHERE cleaner_id = p_cleaner_id AND status = 'pending'
    RETURNING net_payout_cents
  )
  SELECT count(*), COALESCE(SUM(net_payout_cents), 0) INTO v_count, v_total FROM updated;
  PERFORM public.log_admin_action(
    'cleaner_settlements_marked_paid', 'cleaner', p_cleaner_id::text,
    jsonb_build_object('count', v_count, 'total_cents', v_total,
                       'external_id', p_payout_external_id, 'method', p_payment_method));
  RETURN jsonb_build_object('success', true, 'count', v_count, 'total_cents', v_total,
                            'payout_external_id', p_payout_external_id);
END;
$function$;

-- Recalcular UMA semana de UMA profissional (botão admin).
CREATE OR REPLACE FUNCTION public.admin_recompute_cleaner_week(
  p_cleaner_id UUID,
  p_week_start TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_res jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  v_res := public.compute_cleaner_weekly_settlement(p_cleaner_id, p_week_start, true);
  PERFORM public.log_admin_action(
    'cleaner_settlement_recomputed', 'cleaner', p_cleaner_id::text, v_res);
  RETURN v_res;
END;
$function$;

-- ─── Grants ──────────────────────────────────────────────────────────────────
-- As funções compute_* só são chamadas por cron / RPCs SECURITY DEFINER.
REVOKE ALL ON FUNCTION public.compute_cleaner_weekly_settlement(UUID, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_all_cleaner_weekly_settlements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_cleaner_settlements(UUID, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_mark_cleaner_settlements_paid(UUID, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_recompute_cleaner_week(UUID, TIMESTAMPTZ) TO authenticated;

-- ─── Cron: segunda 08:00 (idempotente) ──────────────────────────────────────
DO $$
BEGIN
  PERFORM cron.unschedule('cleaning-weekly-settlement');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'cleaning-weekly-settlement',
  '0 8 * * 1',
  $$SELECT public.compute_all_cleaner_weekly_settlements();$$
);

COMMIT;
