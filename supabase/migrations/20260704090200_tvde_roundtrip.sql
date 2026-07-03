-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE-CAMPO-02 · FEATURE 3 — IDA-E-VOLTA "Garantir a volta"
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️ GATE DINHEIRO — NÃO aplicar sem "vai" do Danilo (Lista Vermelha).
--
-- Regras (confirmadas pelo Danilo, TVDE-CAMPO-02):
--   • Opção "Garantir a volta" no pedido. Cliente paga 8 EUR ADIANTADO (pacote único
--     ida+volta, pago de uma vez — reusa o checkout do item A: tvde-plan-payment).
--   • Cobre ida + volta, cada perna ATÉ 6km. Extra por km normal acima (cliente 0,50/km,
--     motorista 0,40/km) — só a BASE muda.
--   • Motorista da IDA ganha o normal (4 EUR base). Motorista da VOLTA (pode ser OUTRO)
--     é ofertado por 3,50 (0,50 abaixo). Bora absorve a maior parte do desconto.
--   • DESACOPLADO: a volta é uma corrida SEPARADA que o cliente dispara quando quiser,
--     dentro de um prazo (vale-volta). NÃO prende motorista à espera.
--   • Uber/Bolt NÃO têm ida-volta com desconto (pesquisado) — diferenciador do Bora.
--
-- ⚠️ EM ABERTO (decisão do Danilo — ver relatório):
--   (a) prazo de validade do vale (sugestão: tvde_roundtrip_validity_hours=6) + se
--       expira/reembolsa quando não usado.
--   (b) se clientes de plano também podem usar ida-volta e se a volta consome a 2.ª
--       corrida grátis do dia ou é extra à parte.
--
-- ⚠️ PAGAMENTO (GATE, PROPOSTA): o encaixe dos 8 EUR reusa tvde-plan-payment (item A) com
--   novas ações roundtrip (create/create_mbway/activate) — a activate chama
--   tvde_create_roundtrip_credit. O deploy da edge function é passo à parte (espera "vai").
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) SETTINGS ────────────────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_roundtrip_price_cents',         '800', 'TVDE: preço do pacote ida-e-volta (cliente, adiantado)', 'tvde'),
  ('tvde_roundtrip_return_driver_cents', '350', 'TVDE: ganho base do motorista da VOLTA (0,50 abaixo)',   'tvde'),
  ('tvde_roundtrip_validity_hours',      '6',   'TVDE: validade do vale-volta em horas (EM ABERTO)',      'tvde')
ON CONFLICT (key) DO NOTHING;

-- 2) FLAGS na corrida (aditivas) ─────────────────────────────────────────────
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS roundtrip_credit_id UUID,
  ADD COLUMN IF NOT EXISTS is_return_leg       BOOLEAN NOT NULL DEFAULT false;

-- 3) TABELA vale-volta ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_roundtrip_credits (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  outbound_ride_id UUID REFERENCES public.tvde_rides(id) ON DELETE SET NULL,
  return_ride_id   UUID REFERENCES public.tvde_rides(id) ON DELETE SET NULL,
  status           TEXT NOT NULL DEFAULT 'ativo'
                     CHECK (status IN ('ativo','usado','expirado')),
  paid_cents       INTEGER NOT NULL,
  payment_intent_id TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tvde_rt_credits_client ON public.tvde_roundtrip_credits (client_id, status);

ALTER TABLE public.tvde_roundtrip_credits ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
    AND tablename='tvde_roundtrip_credits' AND policyname='tvde_rt_credits_select') THEN
    CREATE POLICY tvde_rt_credits_select ON public.tvde_roundtrip_credits FOR SELECT
      USING (public.is_admin() OR client_id = auth.uid());
  END IF;
END $$;

COMMENT ON TABLE public.tvde_roundtrip_credits IS
  'TVDE — vale ida-e-volta (8 EUR adiantado). Volta desacoplada, disparada pelo cliente no prazo.';

-- 4) RPC criar vale (chamada pela edge fn após pagamento confirmado) ──────────
--    SECURITY DEFINER; a edge fn (service role) passa o client_id verificado.
CREATE OR REPLACE FUNCTION public.tvde_create_roundtrip_credit(
  p_client_id UUID, p_outbound_ride_id UUID, p_paid_cents INT, p_payment_intent_id TEXT)
RETURNS public.tvde_roundtrip_credits
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_hours INT; v_credit public.tvde_roundtrip_credits;
BEGIN
  v_hours := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 6);
  -- idempotência: se já existe vale para este PI, devolve-o
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
    WHERE payment_intent_id = p_payment_intent_id LIMIT 1;
  IF FOUND THEN RETURN v_credit; END IF;

  INSERT INTO public.tvde_roundtrip_credits
    (client_id, outbound_ride_id, paid_cents, payment_intent_id, expires_at)
  VALUES
    (p_client_id, p_outbound_ride_id, p_paid_cents, p_payment_intent_id, now() + make_interval(hours => v_hours))
  RETURNING * INTO v_credit;

  -- marca a corrida de ida como prepaga/ligada ao vale
  IF p_outbound_ride_id IS NOT NULL THEN
    UPDATE public.tvde_rides SET roundtrip_credit_id = v_credit.id, updated_at = now()
     WHERE id = p_outbound_ride_id;
  END IF;
  RETURN v_credit;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_create_roundtrip_credit(UUID,UUID,INT,TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_create_roundtrip_credit(UUID,UUID,INT,TEXT) TO authenticated, service_role;

-- 5) RPC disparar a VOLTA (cliente, dentro do prazo) ─────────────────────────
--    Cria uma corrida nova (is_return_leg=true, prepaga pelo vale). Desacoplada:
--    entra no dispatch normal — pode ser outro motorista. Marca o vale como usado.
CREATE OR REPLACE FUNCTION public.tvde_request_return_ride(
  p_credit_id UUID,
  p_origin_lat DOUBLE PRECISION, p_origin_lng DOUBLE PRECISION, p_origin_label TEXT,
  p_dest_lat DOUBLE PRECISION, p_dest_lng DOUBLE PRECISION, p_dest_label TEXT,
  p_est_distance_km NUMERIC)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_credit public.tvde_roundtrip_credits; v_ride public.tvde_rides; v_fare INT;
BEGIN
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits WHERE id = p_credit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credit_not_found'; END IF;
  IF v_credit.client_id <> v_uid THEN RAISE EXCEPTION 'not_credit_owner'; END IF;
  IF v_credit.status <> 'ativo' THEN RAISE EXCEPTION 'credit_not_active: %', v_credit.status; END IF;
  IF now() > v_credit.expires_at THEN
    UPDATE public.tvde_roundtrip_credits SET status = 'expirado' WHERE id = p_credit_id;
    RAISE EXCEPTION 'credit_expired';
  END IF;

  v_fare := public.tvde_calculate_fare(p_est_distance_km);  -- referência (prepago)

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, payment_method, status,
    roundtrip_credit_id, is_return_leg)
  VALUES (
    v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_fare, 'cash', 'solicitada',
    p_credit_id, true)
  RETURNING * INTO v_ride;

  UPDATE public.tvde_roundtrip_credits
     SET status = 'usado', return_ride_id = v_ride.id WHERE id = p_credit_id;
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_request_return_ride(UUID,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_request_return_ride(UUID,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,TEXT,NUMERIC) TO authenticated;

-- 6) RPC ler vale ativo do cliente (para a UI mostrar "Chamar a minha volta") ─
CREATE OR REPLACE FUNCTION public.tvde_active_roundtrip_credit()
RETURNS public.tvde_roundtrip_credits
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.tvde_roundtrip_credits
   WHERE client_id = auth.uid() AND status = 'ativo' AND now() <= expires_at
   ORDER BY created_at DESC LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.tvde_active_roundtrip_credit() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_active_roundtrip_credit() TO authenticated;

-- 7) FINISH — pernas de ida-volta (supersede F1: inclui paradas + roundtrip) ──
--    Base sobre a versão F1 (paradas). Novidade: perna de VOLTA → base do motorista
--    = tvde_roundtrip_return_driver_cents (3,50). Corridas do vale (ida ou volta) são
--    PREPAGAS → o cliente não paga cash no finish (como coberta pelo plano); a fatia do
--    motorista liquida-se contra o pré-pago. ⚠️ EM ABERTO: mecânica de liquidação do
--    pré-pago (a Bora encaixa 8 via Stripe e deve pagar os motoristas) — ver relatório.
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(p_ride_id UUID, p_final_distance_km NUMERIC)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_stops_fee INT; v_stops_drv INT; v_total_fare INT; v_settle INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_prepaid BOOLEAN;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_fare     := public.tvde_calculate_fare(p_final_distance_km);
  -- base do motorista: VOLTA = 3,50; ida/normal = 4,00
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm  := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;

  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);

  v_driver_earn := v_d_base + v_extra_km * v_d_perkm + v_stops_drv;
  v_total_fare  := v_fare + v_stops_fee;
  v_bora_cut    := v_total_fare - v_driver_earn;

  v_prepaid := v_ride.roundtrip_credit_id IS NOT NULL;  -- perna prepaga pelo vale

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false) OR v_prepaid;
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  UPDATE public.tvde_rides SET
    status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_total_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = COALESCE((v_sub->>'covered')::boolean, false),
    subscription_id = v_sub_id, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- Liquidação CASH: coberto (plano OU prepago) → só a fatia Bora das PARADAS
  -- (a corrida-base não gera cash aqui). Senão → fatia Bora do total.
  IF v_covered IS TRUE THEN
    v_settle := v_stops_fee - v_stops_drv;
  ELSE
    v_settle := v_bora_cut;
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
        'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid, 'subscription', v_sub));
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_finish_ride(UUID, NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_finish_ride(UUID, NUMERIC) TO authenticated;

-- 8) ADMIN — listar vales-volta ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tvde_roundtrips(p_limit INT DEFAULT 100)
RETURNS TABLE (
  id UUID, client_id UUID, status TEXT, paid_cents INT,
  outbound_ride_id UUID, return_ride_id UUID,
  created_at TIMESTAMPTZ, expires_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c.id, c.client_id, c.status, c.paid_cents, c.outbound_ride_id, c.return_ride_id,
         c.created_at, c.expires_at
    FROM public.tvde_roundtrip_credits c
   WHERE public.is_admin()
   ORDER BY c.created_at DESC LIMIT COALESCE(p_limit, 100);
$$;
REVOKE ALL ON FUNCTION public.admin_tvde_roundtrips(INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_roundtrips(INT) TO authenticated;
