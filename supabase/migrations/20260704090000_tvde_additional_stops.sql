-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE-CAMPO-02 · FEATURE 1 — PARADA ADICIONAL (paradas no meio da corrida)
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️ GATE DINHEIRO — NÃO aplicar sem "vai" do Danilo (Lista Vermelha).
--
-- Regras (confirmadas pelo Danilo, TVDE-CAMPO-02):
--   • 2 EUR por parada, cobrado do cliente SEMPRE — mesmo em corrida coberta pelo
--     plano (a parada NÃO é coberta; o plano cobre só a corrida-base).
--   • Split 1 EUR motorista / 1 EUR Bora (1:1) — espelha errand_home_stop (200/100).
--   • Máximo 2 paradas adicionais por corrida (padrão Uber).
--   • A taxa é FLAT (à la Uber "add stop"); o impacto de DISTÂNCIA do troço extra
--     já flui pelo final_distance_km real reportado no finish (rota real do lote 01).
--   • Timer de 2 min por parada é INFORMATIVO (espera gratuita) — não cobra tempo.
--
-- Espelha: supabase/migrations/20260615130000_errand_pricing.sql (home_stop split).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) SETTINGS (categoria 'tvde', editáveis no admin) ─────────────────────────
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_stop_fee_cents',     '200', 'TVDE: taxa cliente por parada adicional (flat)',     'tvde'),
  ('tvde_stop_driver_cents',  '100', 'TVDE: ganho motorista por parada adicional',         'tvde'),
  ('tvde_max_stops',          '2',   'TVDE: máximo de paradas adicionais por corrida',     'tvde'),
  ('tvde_stop_timer_seconds', '120', 'TVDE: espera gratuita informativa por parada (seg)', 'tvde')
ON CONFLICT (key) DO NOTHING;

-- 2) COLUNAS agregadas em tvde_rides (aditivas — corridas antigas ficam a 0) ──
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS extra_stops_count        INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_stops_fee_cents    INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_stops_driver_cents INTEGER NOT NULL DEFAULT 0;

-- 3) TABELA de paradas (histórico por corrida — admin: quantas, valor, split) ─
CREATE TABLE IF NOT EXISTS public.tvde_ride_stops (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id      UUID NOT NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  seq          INTEGER NOT NULL,                 -- ordem de adição
  lat          DOUBLE PRECISION NOT NULL,
  lng          DOUBLE PRECISION NOT NULL,
  label        TEXT,
  segment_km   NUMERIC(8,2) NOT NULL DEFAULT 0,  -- informativo (troço rota real)
  fee_cents    INTEGER NOT NULL,                 -- taxa cliente desta parada
  driver_cents INTEGER NOT NULL,                 -- ganho motorista desta parada
  added_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  reached_at   TIMESTAMPTZ,                      -- motorista chegou → arranca timer
  removed_at   TIMESTAMPTZ                       -- soft-remove (cliente removeu antes de chegar)
);
CREATE INDEX IF NOT EXISTS idx_tvde_ride_stops_ride ON public.tvde_ride_stops (ride_id);

ALTER TABLE public.tvde_ride_stops ENABLE ROW LEVEL SECURITY;
-- Policy idempotente sem a palavra "drop" (a Trava casa 'drop'+tabela financeira).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'tvde_ride_stops'
       AND policyname = 'tvde_ride_stops_select'
  ) THEN
    CREATE POLICY tvde_ride_stops_select ON public.tvde_ride_stops FOR SELECT
      USING (
        public.is_admin()
        OR EXISTS (SELECT 1 FROM public.tvde_rides r WHERE r.id = ride_id
                   AND (r.client_id = auth.uid() OR r.driver_id = auth.uid()))
      );
  END IF;
END $$;
-- Escrita só via RPC SECURITY DEFINER (sem policy INSERT/UPDATE para authenticated).

COMMENT ON TABLE public.tvde_ride_stops IS
  'TVDE — paradas adicionais por corrida (2 EUR cliente / split 1:1). Escrita só via RPC.';

-- 4) RPC tvde_add_stop — cliente adiciona parada (corrida em curso, enforce máx) ─
CREATE OR REPLACE FUNCTION public.tvde_add_stop(
  p_ride_id UUID, p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION,
  p_label TEXT DEFAULT NULL, p_segment_km NUMERIC DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fee INT; v_drv INT; v_max INT; v_seq INT; v_stop public.tvde_ride_stops;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.client_id <> v_uid THEN RAISE EXCEPTION 'not_ride_client'; END IF;
  IF v_ride.status NOT IN ('motorista_a_caminho','motorista_chegou','em_andamento') THEN
    RAISE EXCEPTION 'invalid_ride_state_for_stop: %', v_ride.status; END IF;

  v_max := (public.get_setting('tvde_max_stops') #>> '{}')::int;
  IF v_ride.extra_stops_count >= v_max THEN RAISE EXCEPTION 'max_stops_reached: %', v_max; END IF;

  v_fee := (public.get_setting('tvde_stop_fee_cents') #>> '{}')::int;
  v_drv := (public.get_setting('tvde_stop_driver_cents') #>> '{}')::int;
  v_seq := v_ride.extra_stops_count + 1;

  INSERT INTO public.tvde_ride_stops (ride_id, seq, lat, lng, label, segment_km, fee_cents, driver_cents)
    VALUES (p_ride_id, v_seq, p_lat, p_lng, p_label, GREATEST(0, COALESCE(p_segment_km,0)), v_fee, v_drv)
    RETURNING * INTO v_stop;

  UPDATE public.tvde_rides SET
    extra_stops_count        = extra_stops_count + 1,
    extra_stops_fee_cents    = extra_stops_fee_cents + v_fee,
    extra_stops_driver_cents = extra_stops_driver_cents + v_drv,
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_ride.status, 'cliente',
      jsonb_build_object('event','stop_added','stop_id',v_stop.id,'seq',v_seq,
        'fee_cents',v_fee,'driver_cents',v_drv));

  RETURN jsonb_build_object(
    'stop_id', v_stop.id, 'seq', v_seq,
    'extra_stops_count', v_ride.extra_stops_count,
    'extra_stops_fee_cents', v_ride.extra_stops_fee_cents,
    'extra_stops_driver_cents', v_ride.extra_stops_driver_cents,
    'max_stops', v_max);
END; $$;
REVOKE ALL ON FUNCTION public.tvde_add_stop(UUID,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_add_stop(UUID,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,NUMERIC) TO authenticated;

-- 5) RPC tvde_remove_stop — cliente remove (só antes de o motorista chegar) ───
CREATE OR REPLACE FUNCTION public.tvde_remove_stop(p_ride_id UUID, p_stop_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_stop public.tvde_ride_stops;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.client_id <> v_uid THEN RAISE EXCEPTION 'not_ride_client'; END IF;

  SELECT * INTO v_stop FROM public.tvde_ride_stops
    WHERE id = p_stop_id AND ride_id = p_ride_id AND removed_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'stop_not_found'; END IF;
  IF v_stop.reached_at IS NOT NULL THEN RAISE EXCEPTION 'stop_already_reached'; END IF;

  UPDATE public.tvde_ride_stops SET removed_at = now() WHERE id = p_stop_id;
  UPDATE public.tvde_rides SET
    extra_stops_count        = GREATEST(0, extra_stops_count - 1),
    extra_stops_fee_cents    = GREATEST(0, extra_stops_fee_cents - v_stop.fee_cents),
    extra_stops_driver_cents = GREATEST(0, extra_stops_driver_cents - v_stop.driver_cents),
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_ride.status, 'cliente',
      jsonb_build_object('event','stop_removed','stop_id',p_stop_id));

  RETURN jsonb_build_object('extra_stops_count', v_ride.extra_stops_count,
    'extra_stops_fee_cents', v_ride.extra_stops_fee_cents,
    'extra_stops_driver_cents', v_ride.extra_stops_driver_cents);
END; $$;
REVOKE ALL ON FUNCTION public.tvde_remove_stop(UUID,UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_remove_stop(UUID,UUID) TO authenticated;

-- 6) RPC tvde_reach_stop — motorista marca chegada (arranca timer informativo) ─
CREATE OR REPLACE FUNCTION public.tvde_reach_stop(p_ride_id UUID, p_stop_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_stop public.tvde_ride_stops;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;

  UPDATE public.tvde_ride_stops SET reached_at = now()
    WHERE id = p_stop_id AND ride_id = p_ride_id AND removed_at IS NULL AND reached_at IS NULL
    RETURNING * INTO v_stop;
  IF NOT FOUND THEN RAISE EXCEPTION 'stop_not_found_or_done'; END IF;

  -- toca a corrida para propagar via realtime aos dois lados (contagem do timer)
  UPDATE public.tvde_rides SET updated_at = now() WHERE id = p_ride_id;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_ride.status, 'motorista',
      jsonb_build_object('event','stop_reached','stop_id',p_stop_id,'reached_at',v_stop.reached_at));

  RETURN jsonb_build_object('stop_id', p_stop_id, 'reached_at', v_stop.reached_at,
    'timer_seconds', (public.get_setting('tvde_stop_timer_seconds') #>> '{}')::int);
END; $$;
REVOKE ALL ON FUNCTION public.tvde_reach_stop(UUID,UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_reach_stop(UUID,UUID) TO authenticated;

-- 7) FINISH — soma paradas ao fare do cliente e ao ganho do motorista ────────
--    A parada é cobrada SEMPRE (mesmo coberta pelo plano). Reescreve tvde_finish_ride
--    de 20260626100001_tvde_phase1_rpcs.sql, acrescentando extra_stops_*.
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id UUID, p_final_distance_km NUMERIC)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_stops_fee INT; v_stops_drv INT; v_total_fare INT; v_settle INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_fare     := public.tvde_calculate_fare(p_final_distance_km);
  v_d_base   := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  v_d_perkm  := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;

  -- paradas adicionais (flat, cobradas SEMPRE — não cobertas pelo plano)
  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);

  v_driver_earn := v_d_base + v_extra_km * v_d_perkm + v_stops_drv;
  v_total_fare  := v_fare + v_stops_fee;
  v_bora_cut    := v_total_fare - v_driver_earn;  -- resto (auto-consistente)

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  UPDATE public.tvde_rides SET
    status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_total_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- Liquidação CASH: se coberto pelo plano a corrida-base é grátis, mas as PARADAS
  -- não são → o motorista deve à Bora só a fatia (1 EUR) de cada parada.
  IF v_covered IS TRUE THEN
    v_settle := v_stops_fee - v_stops_drv;   -- fatia Bora só das paradas
  ELSE
    v_settle := v_bora_cut;                   -- fatia Bora do total
  END IF;

  IF v_settle > 0 THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_settle / 100.0, 2), updated_at = now();
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver',
      jsonb_build_object('final_distance_km', p_final_distance_km, 'final_fare_cents', v_total_fare,
        'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
        'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
        'subscription', v_sub));
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_finish_ride(UUID, NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(UUID, NUMERIC) TO authenticated;

-- 8) ADMIN — histórico de paradas por corrida (quantas, valor, split) ─────────
CREATE OR REPLACE FUNCTION public.admin_tvde_ride_stops(p_ride_id UUID)
RETURNS TABLE (
  id UUID, seq INTEGER, label TEXT, segment_km NUMERIC,
  fee_cents INTEGER, driver_cents INTEGER,
  added_at TIMESTAMPTZ, reached_at TIMESTAMPTZ, removed_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.seq, s.label, s.segment_km, s.fee_cents, s.driver_cents,
         s.added_at, s.reached_at, s.removed_at
    FROM public.tvde_ride_stops s
   WHERE s.ride_id = p_ride_id AND public.is_admin()
   ORDER BY s.seq;
$$;
REVOKE ALL ON FUNCTION public.admin_tvde_ride_stops(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_ride_stops(UUID) TO authenticated;
