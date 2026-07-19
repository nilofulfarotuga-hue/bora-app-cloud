-- ============================================================================
-- BORA — Beleza: taxa de €0,50 por walk-in + saldo semanal NEGATIVO
-- ----------------------------------------------------------------------------
-- Decisão de negócio do Danilo (2026-07-19): quando o parceiro cria um walk-in
-- (marcação de balcão, is_walk_in=true), está a usar o sistema da Bora, logo
-- DEVE €0,50 à Bora por cada walk-in. Esses €0,50 são DESCONTADOS do repasse
-- semanal e o saldo PODE ficar NEGATIVO (se dever mais do que recebe, o
-- parceiro paga a Bora — igual ao padrão de saldo negativo do TVDE).
--
-- ESCOLHAS DOCUMENTADAS (caminho conservador — "só conta o que aconteceu"):
--   • O €0,50 do walk-in cobra-se APENAS quando status='completed' (serviço
--     REALIZADO). Walk-in cancelado/no-show NÃO cobra. Igual à lógica das
--     outras verticais (conta pela data/estado do serviço feito).
--   • Setting NOVA `appointment_walkin_fee_cents` (default 50) — separada do
--     `appointment_deposit_bora_cut_cents` para ficar configurável sem
--     confundir com o corte do sinal.
--   • Walk-ins NÃO entram no split do sinal (partner_cut €2,50): um walk-in tem
--     deposit_status='waived' e deposit_cents=0 — não há sinal para repartir.
--     Por isso o count 'completed' do lado do parceiro passa a exigir
--     is_walk_in=false; o walk-in só contribui com a taxa de −€0,50.
--
-- Aditivo e reversível. NÃO altera valores cobrados a clientes; só ajusta a
-- consolidação do repasse ao parceiro (que ainda é registo contabilístico —
-- marcar "pago" não move dinheiro por si).
-- ============================================================================

BEGIN;

-- ─── Colunas novas (aditivas) ───────────────────────────────────────────────
ALTER TABLE public.appointment_payouts
  ADD COLUMN IF NOT EXISTS total_walkins           INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_walkin_fees_cents INT NOT NULL DEFAULT 0;

-- ─── Setting nova (idempotente — não sobrescreve se já ajustada) ────────────
INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('appointment_walkin_fee_cents', to_jsonb(50), 'appointments',
   'Taxa Bora por walk-in concluído criado pelo parceiro (cents). €0,50 — descontada do repasse semanal do parceiro')
ON CONFLICT (key) DO NOTHING;

-- ─── compute_provider_weekly_payout (v2: walk-in fee + net negativo) ─────────
CREATE OR REPLACE FUNCTION public.compute_provider_weekly_payout(
  p_provider_id text, p_week_start timestamptz DEFAULT NULL, p_persist boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_bounds record; v_anchor timestamptz;
  v_booking_fee int; v_bora_cut int; v_partner_cut int; v_walkin_fee int;
  v_completed int; v_noshow int; v_cancel_ret int; v_service_rev int; v_deposits_retained int;
  v_walkins int; v_walkin_fees int;
  v_consumed int; v_retained int; v_booking_fees int; v_deposit_cut int; v_net int;
  v_direction text; v_id uuid;
BEGIN
  v_anchor := COALESCE(p_week_start, now());
  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(v_anchor);

  SELECT COALESCE((value::text)::int,50)  INTO v_booking_fee FROM platform_settings WHERE key='appointment_booking_fee_cents';
  SELECT COALESCE((value::text)::int,50)  INTO v_bora_cut    FROM platform_settings WHERE key='appointment_deposit_bora_cut_cents';
  SELECT COALESCE((value::text)::int,250) INTO v_partner_cut FROM platform_settings WHERE key='appointment_deposit_partner_cut_cents';
  SELECT COALESCE((value::text)::int,50)  INTO v_walkin_fee  FROM platform_settings WHERE key='appointment_walkin_fee_cents';
  v_booking_fee := COALESCE(v_booking_fee,50); v_bora_cut := COALESCE(v_bora_cut,50);
  v_partner_cut := COALESCE(v_partner_cut,250); v_walkin_fee := COALESCE(v_walkin_fee,50);

  -- Contagens da semana. O lado do SINAL (completed/no_show/cancel-retained)
  -- exige is_walk_in=false — walk-ins não têm sinal para repartir. Os walk-ins
  -- concluídos contam-se à parte, só para a taxa de −€0,50.
  SELECT
    count(*) FILTER (WHERE status='completed' AND is_walk_in=false),
    count(*) FILTER (WHERE status='no_show'   AND is_walk_in=false),
    count(*) FILTER (WHERE status='cancelled' AND deposit_status='retained' AND is_walk_in=false),
    COALESCE(SUM(service_price_cents) FILTER (WHERE status='completed' AND is_walk_in=false AND full_payment_method='app' AND full_payment_status='paid'),0),
    COALESCE(SUM(deposit_cents) FILTER (WHERE deposit_status='retained' AND is_walk_in=false),0),
    count(*) FILTER (WHERE status='completed' AND is_walk_in=true)
  INTO v_completed, v_noshow, v_cancel_ret, v_service_rev, v_deposits_retained, v_walkins
  FROM appointments
  WHERE provider_id = p_provider_id
    AND scheduled_at >= v_bounds.week_start AND scheduled_at <= v_bounds.week_end;

  v_completed := COALESCE(v_completed,0); v_noshow := COALESCE(v_noshow,0); v_cancel_ret := COALESCE(v_cancel_ret,0);
  v_service_rev := COALESCE(v_service_rev,0); v_deposits_retained := COALESCE(v_deposits_retained,0);
  v_walkins := COALESCE(v_walkins,0);
  v_retained := v_noshow + v_cancel_ret;
  v_consumed := v_completed + v_retained;
  v_booking_fees := v_completed * v_booking_fee;   -- receita Bora (só marcações reais)
  v_deposit_cut  := v_retained * v_bora_cut;        -- receita Bora (sinal retido)
  v_walkin_fees  := v_walkins * v_walkin_fee;        -- receita Bora (uso do sistema), descontada ao parceiro

  -- Repasse líquido: parte do parceiro no sinal + receita de serviço na app,
  -- MENOS a taxa dos walk-ins. Pode ficar NEGATIVO (parceiro deve à Bora).
  v_net := v_consumed * v_partner_cut + v_service_rev - v_walkin_fees;
  v_direction := CASE WHEN v_net >= 0 THEN 'bora_to_partner' ELSE 'partner_to_bora' END;

  IF p_persist THEN
    INSERT INTO appointment_payouts(provider_id, week_start_at, week_end_at, total_appointments,
      total_service_revenue_cents, total_deposits_retained_cents, bora_booking_fees_cents,
      bora_deposit_cut_cents, net_payout_cents, direction, status,
      total_walkins, total_walkin_fees_cents)
    VALUES (p_provider_id, v_bounds.week_start, v_bounds.week_end, v_consumed,
      v_service_rev, v_deposits_retained, v_booking_fees, v_deposit_cut, v_net, v_direction, 'pending',
      v_walkins, v_walkin_fees)
    ON CONFLICT (provider_id, week_start_at) DO UPDATE SET
      week_end_at=EXCLUDED.week_end_at, total_appointments=EXCLUDED.total_appointments,
      total_service_revenue_cents=EXCLUDED.total_service_revenue_cents,
      total_deposits_retained_cents=EXCLUDED.total_deposits_retained_cents,
      bora_booking_fees_cents=EXCLUDED.bora_booking_fees_cents,
      bora_deposit_cut_cents=EXCLUDED.bora_deposit_cut_cents,
      net_payout_cents=EXCLUDED.net_payout_cents,
      direction=EXCLUDED.direction,
      total_walkins=EXCLUDED.total_walkins,
      total_walkin_fees_cents=EXCLUDED.total_walkin_fees_cents
      -- status/paid_at preservados (não mexe num fecho já pago).
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object('provider_id', p_provider_id, 'week_start', v_bounds.week_start,
    'total_appointments', v_consumed, 'total_walkins', v_walkins,
    'walkin_fees_cents', v_walkin_fees, 'net_payout_cents', v_net, 'direction', v_direction,
    'bora_revenue_cents', v_booking_fees + v_deposit_cut + v_walkin_fees, 'payout_id', v_id);
END $$;

-- ─── compute_all_provider_weekly_payouts: incluir providers só-com-walk-ins ──
-- Já apanha status='completed' (walk-ins são completed), mas tornamos explícito
-- que um provider com APENAS walk-ins na semana também fecha (net negativo).
CREATE OR REPLACE FUNCTION public.compute_all_provider_weekly_payouts()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_anchor timestamptz := now() - interval '1 day'; v_p record; v_count int := 0;
BEGIN
  FOR v_p IN
    SELECT DISTINCT a.provider_id
    FROM appointments a, public.driver_settlement_week_bounds(now() - interval '1 day') b
    WHERE a.scheduled_at >= b.week_start AND a.scheduled_at <= b.week_end
      AND (a.status IN ('completed','no_show','cancelled')
           OR (a.is_walk_in AND a.status='completed'))
  LOOP
    PERFORM public.compute_provider_weekly_payout(v_p.provider_id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;

COMMIT;
