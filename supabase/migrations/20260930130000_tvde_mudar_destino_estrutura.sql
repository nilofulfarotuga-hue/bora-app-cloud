-- =============================================================================
-- TVDE — MUDAR DESTINO a meio da corrida (missão tvde-mudar-destino, 30/09/2026)
-- Autorização do Danilo: "sim" (30/09/2026 12:51). Regra fechada por ele:
--   1. novo total de km = km feitos desde a recolha (antes da recolha = 0, conta
--      da origem) + km da rota da posição do carro até ao destino novo;
--   2. preço novo = a mesma tabela do pedido, com os mesmos ajustes (sócio,
--      preço à medida); paragens ficam à parte;
--   3. km novos > km combinados -> paga (preço novo - preço combinado ATUAL),
--      mínimo tvde_dest_change_min_cents (200);
--   4. km novos <= km combinados -> 0, não recebe nada de volta, preço fica;
--   5. motorista: diferença da tabela dele (80/km), mínimo
--      tvde_dest_change_min_driver_cents (100) quando há cobrança;
--   6. o cliente vê tudo antes de aceitar; sem aceitar nada muda;
--   7. cartão/MB Way cobra logo (Edge tvde-payment) e só aplica depois do
--      pagamento confirmado; dinheiro soma ao que o motorista cobra no fim;
--   8. várias mudanças: cada uma contra o preço combinado ATUAL.
-- Pacote ida-e-volta e plano: diferença pela tabela normal, sem desconto.
-- Corrida de balcão: só o admin muda, com o valor novo combinado à mão.
--
-- ADITIVO: tabela nova, colunas novas (default 0) e funções novas. A única
-- função existente tocada é a tvde_finish_ride, na migration seguinte.
-- =============================================================================

-- 1) Definições ---------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, description, category) VALUES
 ('tvde_dest_change_enabled', 'true'::jsonb,
  'Mudar destino a meio da corrida TVDE: o cliente vê o destino novo, o preço novo e a diferença antes de aceitar (Lei 45/2018 art. 15.º n.º 4). false = botão escondido e servidor recusa.', 'tvde'),
 ('tvde_dest_change_min_cents', '200'::jsonb,
  'Mudar destino: mínimo que o cliente paga por cada mudança quando a nova distância total é MAIOR que a combinada (cêntimos). Destino mais perto = 0.', 'tvde'),
 ('tvde_dest_change_min_driver_cents', '100'::jsonb,
  'Mudar destino: mínimo que o motorista ganha a mais por cada mudança com cobrança (cêntimos). Acima disso ganha a diferença da tabela dele (tvde_driver_per_km_cents por km).', 'tvde')
ON CONFLICT (key) DO NOTHING;

-- 2) Colunas na corrida (todas a 0 = comportamento de hoje) ---------------------
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS dest_change_count              integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_fee_cents          integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_driver_cents       integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_cash_cents         integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_extra_fee_cents    integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_extra_driver_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_paid_extra_km      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dest_change_base_price_cents   integer,
  ADD COLUMN IF NOT EXISTS dest_change_base_driver_cents  integer;

COMMENT ON COLUMN public.tvde_rides.dest_change_fee_cents IS
  'Mudar destino: soma do que o cliente aceitou pagar a mais (todas as mudanças). Para mostrar; o dinheiro entra no fim pela tvde_finish_ride.';
COMMENT ON COLUMN public.tvde_rides.dest_change_driver_cents IS
  'Mudar destino: soma do que o motorista ganha a mais (todas as mudanças). Para mostrar.';
COMMENT ON COLUMN public.tvde_rides.dest_change_cash_cents IS
  'Mudar destino: parte de dest_change_fee_cents paga em DINHEIRO (o motorista recolhe em mão; entra no acerto tvde_driver_balances).';
COMMENT ON COLUMN public.tvde_rides.dest_change_extra_fee_cents IS
  'Mudar destino: o que a tvde_finish_ride soma à tarifa, para além do que ela já recalcula sozinha pela est_distance_km nova (mínimos, plano, pacote, destino mais perto). Garante que o preço final é exatamente o aceite.';
COMMENT ON COLUMN public.tvde_rides.dest_change_extra_driver_cents IS
  'Mudar destino: o que a tvde_finish_ride soma ao ganho do motorista, para além do recálculo pela est_distance_km nova.';
COMMENT ON COLUMN public.tvde_rides.dest_change_paid_extra_km IS
  'Mudar destino na VOLTA do pacote: km extra já pagos pela mudança, descontados da regra do km a mais na volta (caso Stela 18/09) para não cobrar duas vezes.';
COMMENT ON COLUMN public.tvde_rides.dest_change_base_price_cents IS
  'Mudar destino: preço da tabela à distância combinada ANTES da primeira mudança. Preço combinado atual = isto + dest_change_fee_cents.';
COMMENT ON COLUMN public.tvde_rides.dest_change_base_driver_cents IS
  'Mudar destino: ganho da tabela do motorista antes da primeira mudança. Ganho combinado atual = isto + dest_change_driver_cents.';

-- 3) Histórico das mudanças -----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tvde_destination_changes (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id                uuid NOT NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  client_id              uuid,
  driver_id              uuid,
  ride_status            text,
  old_dest_lat           double precision,
  old_dest_lng           double precision,
  old_dest_label         text,
  new_dest_lat           double precision NOT NULL,
  new_dest_lng           double precision NOT NULL,
  new_dest_label         text,
  km_done                numeric NOT NULL DEFAULT 0,
  km_remaining           numeric NOT NULL DEFAULT 0,
  km_new_total           numeric NOT NULL,
  km_before              numeric,
  price_before_cents     integer,
  price_new_cents        integer,
  table_diff_cents       integer,
  client_diff_cents      integer NOT NULL DEFAULT 0,
  driver_before_cents    integer,
  driver_new_cents       integer,
  driver_table_diff_cents integer,
  driver_diff_cents      integer NOT NULL DEFAULT 0,
  min_applied            boolean NOT NULL DEFAULT false,
  driver_min_applied     boolean NOT NULL DEFAULT false,
  pricing_branch         text,
  extra_fee_cents        integer,
  extra_driver_cents     integer,
  method                 text CHECK (method IN ('cash','card','mbway','nenhum','balcao')),
  payment_intent_id      text,
  estado                 text NOT NULL DEFAULT 'proposta'
                         CHECK (estado IN ('proposta','paga','aplicada','recusada','falhada')),
  motivo                 text,
  created_by             uuid,
  created_by_role        text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  paid_at                timestamptz,
  applied_at             timestamptz,
  updated_at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tvde_destination_changes_ride_idx ON public.tvde_destination_changes (ride_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS tvde_destination_changes_pi_uidx
  ON public.tvde_destination_changes (payment_intent_id) WHERE payment_intent_id IS NOT NULL;

ALTER TABLE public.tvde_destination_changes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tvde_destination_changes_select ON public.tvde_destination_changes;
CREATE POLICY tvde_destination_changes_select ON public.tvde_destination_changes
  FOR SELECT TO authenticated
  USING (client_id = auth.uid() OR driver_id = auth.uid() OR public.is_admin());
-- Sem políticas de escrita: só as funções abaixo (SECURITY DEFINER) escrevem.
REVOKE ALL ON public.tvde_destination_changes FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.tvde_destination_changes FROM authenticated;
GRANT SELECT ON public.tvde_destination_changes TO authenticated;

-- 4) Preço de tabela ----------------------------------------------------------
-- Tabela pura do cliente (sem ajustes): base + km extra.
CREATE OR REPLACE FUNCTION public._tvde_table_fare_cents(p_km numeric)
RETURNS integer LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT (public.get_setting('tvde_base_fare_cents') #>> '{}')::int
       + GREATEST(0, CEIL(COALESCE(p_km,0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
         * (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
$$;

-- Tabela do motorista (corrida normal): base + 80/km extra.
CREATE OR REPLACE FUNCTION public._tvde_table_driver_cents(p_km numeric)
RETURNS integer LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT (public.get_setting('tvde_driver_base_cents') #>> '{}')::int
       + GREATEST(0, CEIL(COALESCE(p_km,0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
         * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
$$;

-- Preço ao cliente pela regra 2 (mesmos ajustes do pedido — tvde_request_ride):
--   pacote / plano -> tabela normal (o pacote/plano só cobre a rota combinada);
--   preço à medida (tvde_client_fare_overrides) -> o fixo, se couber no max_km;
--   sócio de plano (sem corrida coberta) -> tvde_extra_ride_cents + km extra;
--   resto -> tabela.
CREATE OR REPLACE FUNCTION public._tvde_dest_price_cents(p_ride public.tvde_rides, p_km numeric)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_fixed int; v_member boolean;
BEGIN
  IF p_ride.roundtrip_credit_id IS NOT NULL OR COALESCE(p_ride.used_subscription_ride, false) THEN
    RETURN public._tvde_table_fare_cents(p_km);
  END IF;
  v_fixed := public.tvde_client_fixed_fare_cents(p_ride.client_id, p_km);
  IF v_fixed IS NOT NULL THEN RETURN v_fixed; END IF;
  SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
     WHERE client_id = p_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
    INTO v_member;
  IF v_member THEN
    RETURN (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int
         + GREATEST(0, CEIL(COALESCE(p_km,0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
           * (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
  END IF;
  RETURN public._tvde_table_fare_cents(p_km);
END $$;

-- Espelho da parte da tvde_finish_ride que DEPENDE da est_distance_km (sem
-- paragens, promo e tokens). Serve para saber quanto a finish já vai mexer
-- sozinha quando a est_distance_km sobe, e guardar só o resto nas colunas
-- dest_change_extra_*. Mantém-se igual aos ramos da finish (30/09/2026).
CREATE OR REPLACE FUNCTION public._tvde_finish_km_part(p_ride public.tvde_rides, p_km numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_fare int := 0; v_drv int; v_base int; v_extra_km int; v_plan_fixed int;
  v_member boolean; v_fixed int; v_fixed_drv int; v_branch text;
BEGIN
  v_extra_km := GREATEST(0, CEIL(COALESCE(p_km,0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  IF p_ride.roundtrip_credit_id IS NOT NULL THEN
    -- Pacote: a finish cobra pela distância FINAL (não pela combinada); a tarifa
    -- da perna é 0. O ganho do motorista sobe com os km reais — conta-se aqui
    -- com a distância combinada nova como a melhor estimativa desses km.
    IF COALESCE(p_ride.is_return_leg, false) THEN
      v_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
      v_branch := 'pacote_volta';
    ELSE
      v_base := COALESCE((public.get_setting('tvde_roundtrip_outbound_driver_cents') #>> '{}')::int,
                         (public.get_setting('tvde_driver_base_cents') #>> '{}')::int);
      v_branch := 'pacote_ida';
    END IF;
    v_drv := v_base + v_extra_km * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
    RETURN jsonb_build_object('fare', 0, 'driver', v_drv, 'branch', v_branch);
  END IF;
  IF COALESCE(p_ride.used_subscription_ride, false) THEN
    SELECT driver_earn_cents INTO v_plan_fixed FROM public.tvde_subscriptions WHERE id = p_ride.subscription_id;
    IF v_plan_fixed IS NOT NULL THEN
      RETURN jsonb_build_object('fare', 0, 'driver', v_plan_fixed, 'branch', 'plano_ganho_fixo');
    END IF;
    RETURN jsonb_build_object('fare', 0, 'driver', ROUND(public._tvde_table_driver_cents(p_km) * 0.85)::int, 'branch', 'plano');
  END IF;
  v_branch := 'normal';
  v_fare := public._tvde_table_fare_cents(p_km);
  v_drv := public._tvde_table_driver_cents(p_km);
  SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
     WHERE client_id = p_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
    INTO v_member;
  IF v_member THEN
    v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    v_branch := 'socio';
  END IF;
  v_fixed := public.tvde_client_fixed_fare_cents(p_ride.client_id, p_km);
  v_fixed_drv := public.tvde_client_fixed_driver_earn_cents(p_ride.client_id, p_km);
  IF v_fixed IS NOT NULL THEN v_fare := v_fixed; v_branch := 'preco_a_medida'; END IF;
  IF v_fixed_drv IS NOT NULL THEN v_drv := v_fixed_drv; END IF;
  IF p_ride.agreed_fare_cents IS NOT NULL THEN v_fare := p_ride.agreed_fare_cents; v_branch := 'balcao'; END IF;
  IF p_ride.agreed_driver_earn_cents IS NOT NULL THEN v_drv := p_ride.agreed_driver_earn_cents; END IF;
  RETURN jsonb_build_object('fare', v_fare, 'driver', v_drv, 'branch', v_branch);
END $$;

-- 5) Cálculo (não grava nada) -------------------------------------------------
CREATE OR REPLACE FUNCTION public._tvde_dest_change_calc(
  p_ride public.tvde_rides, p_dest_lat double precision, p_dest_lng double precision,
  p_done_km numeric, p_remaining_km numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_done numeric; v_rem numeric; v_total numeric; v_before numeric;
  v_drv_lat double precision; v_drv_lng double precision;
  v_from_lat double precision; v_from_lng double precision;
  v_min int; v_min_drv int;
  v_base_price int; v_price_before int; v_price_new int; v_table_diff int; v_client int := 0;
  v_base_drv int; v_drv_before int; v_drv_new int; v_drv_table_diff int; v_drv int := 0;
  v_min_applied boolean := false; v_drv_min_applied boolean := false;
BEGIN
  v_min := COALESCE((public.get_setting('tvde_dest_change_min_cents') #>> '{}')::int, 200);
  v_min_drv := COALESCE((public.get_setting('tvde_dest_change_min_driver_cents') #>> '{}')::int, 100);
  SELECT d.lat, d.lng INTO v_drv_lat, v_drv_lng FROM public.drivers d WHERE d.user_id = p_ride.driver_id LIMIT 1;

  -- Regra 1. Antes da recolha: 0 km feitos, rota a partir da ORIGEM.
  IF p_ride.status = 'em_andamento' THEN
    v_done := GREATEST(COALESCE(p_done_km, 0), 0);
    -- Nunca menos do que a linha reta origem -> carro (a app não pode encolher).
    IF v_drv_lat IS NOT NULL AND p_ride.origin_lat IS NOT NULL THEN
      v_done := GREATEST(v_done, public._haversine_km(p_ride.origin_lat, p_ride.origin_lng, v_drv_lat, v_drv_lng)::numeric);
    END IF;
    v_from_lat := COALESCE(v_drv_lat, p_ride.origin_lat); v_from_lng := COALESCE(v_drv_lng, p_ride.origin_lng);
  ELSE
    v_done := 0;
    v_from_lat := p_ride.origin_lat; v_from_lng := p_ride.origin_lng;
  END IF;
  v_rem := GREATEST(COALESCE(p_remaining_km, 0), 0);
  IF v_from_lat IS NOT NULL THEN
    v_rem := GREATEST(v_rem, public._haversine_km(v_from_lat, v_from_lng, p_dest_lat, p_dest_lng)::numeric);
  END IF;
  v_done := ROUND(v_done, 2); v_rem := ROUND(v_rem, 2);
  v_total := v_done + v_rem;
  v_before := COALESCE(p_ride.est_distance_km, 0);

  -- Regras 2, 3, 4 e 8: contra o preço combinado ATUAL.
  v_base_price := COALESCE(p_ride.dest_change_base_price_cents, public._tvde_dest_price_cents(p_ride, v_before));
  v_price_before := v_base_price + COALESCE(p_ride.dest_change_fee_cents, 0);
  v_price_new := public._tvde_dest_price_cents(p_ride, v_total);
  v_table_diff := v_price_new - v_price_before;
  v_base_drv := COALESCE(p_ride.dest_change_base_driver_cents, public._tvde_table_driver_cents(v_before));
  v_drv_before := v_base_drv + COALESCE(p_ride.dest_change_driver_cents, 0);
  v_drv_new := public._tvde_table_driver_cents(v_total);
  v_drv_table_diff := v_drv_new - v_drv_before;

  IF v_total > v_before THEN
    v_client := GREATEST(v_table_diff, v_min);
    v_min_applied := v_table_diff < v_min;
    -- Regra 5: motorista ganha a diferença da tabela dele, mínimo quando há cobrança.
    v_drv := GREATEST(v_drv_table_diff, v_min_drv);
    v_drv_min_applied := v_drv_table_diff < v_min_drv;
  END IF;

  RETURN jsonb_build_object(
    'km_done', v_done, 'km_remaining', v_rem, 'km_new_total', v_total, 'km_before', v_before,
    'price_base_cents', v_base_price, 'price_before_cents', v_price_before,
    'price_new_cents', v_price_new, 'table_diff_cents', v_table_diff,
    'client_diff_cents', v_client, 'min_applied', v_min_applied, 'min_cents', v_min,
    'price_after_cents', v_price_before + v_client,
    'driver_base_cents', v_base_drv, 'driver_before_cents', v_drv_before,
    'driver_new_cents', v_drv_new, 'driver_table_diff_cents', v_drv_table_diff,
    'driver_diff_cents', v_drv, 'driver_min_applied', v_drv_min_applied, 'min_driver_cents', v_min_drv,
    'longer', v_total > v_before,
    'formula', jsonb_build_object(
       'tarifa_base_cents', (public.get_setting('tvde_base_fare_cents') #>> '{}')::int,
       'km_incluidos', (public.get_setting('tvde_base_distance_km') #>> '{}')::int,
       'preco_km_extra_cents', (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int));
END $$;

-- Validação comum (cliente) ----------------------------------------------------
CREATE OR REPLACE FUNCTION public._tvde_dest_change_check(p_ride public.tvde_rides)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT COALESCE((public.get_setting('tvde_dest_change_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'dest_change_disabled'; END IF;
  IF p_ride.client_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'not_ride_client'; END IF;
  IF p_ride.status NOT IN ('motorista_a_caminho','motorista_chegou','em_andamento') THEN
    RAISE EXCEPTION 'invalid_ride_state_for_dest_change: %', p_ride.status; END IF;
  IF p_ride.agreed_fare_cents IS NOT NULL THEN
    -- Balcão: o cliente não tem app; só o admin muda, com valor combinado à mão.
    RAISE EXCEPTION 'counter_ride_admin_only'; END IF;
END $$;

-- 6) RPC de COTAÇÃO (só calcula; não grava) ------------------------------------
CREATE OR REPLACE FUNCTION public.tvde_dest_change_quote(
  p_ride_id uuid, p_dest_lat double precision, p_dest_lng double precision,
  p_dest_label text DEFAULT NULL, p_done_km numeric DEFAULT 0, p_remaining_km numeric DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ride public.tvde_rides; v_calc jsonb;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  PERFORM public._tvde_dest_change_check(v_ride);
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  v_calc := public._tvde_dest_change_calc(v_ride, p_dest_lat, p_dest_lng, p_done_km, p_remaining_km);
  IF (v_calc->>'km_new_total')::numeric > 300 THEN RAISE EXCEPTION 'dest_too_far'; END IF;
  RETURN v_calc || jsonb_build_object('ride_id', v_ride.id, 'dest_label', p_dest_label,
    'payment_method', COALESCE(v_ride.payment_method, 'cash'),
    'needs_payment', (v_calc->>'client_diff_cents')::int > 0 AND COALESCE(v_ride.payment_method,'cash') <> 'cash');
END $$;

-- 7) APLICAR (interna) --------------------------------------------------------
CREATE OR REPLACE FUNCTION public._tvde_dest_change_apply(p_change_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net', 'extensions' AS $$
DECLARE
  v_ch public.tvde_destination_changes; v_ride public.tvde_rides;
  v_new_est numeric; v_part_old jsonb; v_part_new jsonb;
  v_nat_fare int; v_nat_drv int; v_extra_fee int; v_extra_drv int; v_paid_km int := 0;
  v_cash int := 0; v_jwt text;
BEGIN
  SELECT * INTO v_ch FROM public.tvde_destination_changes WHERE id = p_change_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'dest_change_not_found'; END IF;
  IF v_ch.estado = 'aplicada' THEN
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'aplicada', 'already', true);
  END IF;
  IF v_ch.estado NOT IN ('proposta','paga') THEN RAISE EXCEPTION 'dest_change_not_applicable: %', v_ch.estado; END IF;
  IF v_ch.method IN ('card','mbway') AND v_ch.estado <> 'paga' THEN RAISE EXCEPTION 'dest_change_not_paid'; END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = v_ch.ride_id FOR UPDATE;
  IF v_ride.status NOT IN ('motorista_a_caminho','motorista_chegou','em_andamento') THEN
    UPDATE public.tvde_destination_changes SET estado = 'falhada', motivo = 'corrida_' || v_ride.status, updated_at = now()
     WHERE id = v_ch.id;
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'falhada', 'motivo', 'corrida_' || v_ride.status);
  END IF;
  -- Outra mudança entrou entretanto: esta foi calculada contra um preço que já não é o atual.
  IF COALESCE(v_ride.est_distance_km, 0) <> COALESCE(v_ch.km_before, 0)
     OR COALESCE(v_ride.dest_change_count, 0) <> (SELECT count(*) FROM public.tvde_destination_changes
                                                   WHERE ride_id = v_ride.id AND estado = 'aplicada') THEN
    UPDATE public.tvde_destination_changes SET estado = 'falhada', motivo = 'corrida_mudou', updated_at = now()
     WHERE id = v_ch.id;
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'falhada', 'motivo', 'corrida_mudou');
  END IF;

  -- Destino mais perto: a distância combinada NÃO desce (o preço fica igual e
  -- a finish não pode recalcular para baixo).
  v_new_est := GREATEST(COALESCE(v_ride.est_distance_km, 0), v_ch.km_new_total);
  v_part_old := public._tvde_finish_km_part(v_ride, COALESCE(v_ride.est_distance_km, 0));
  v_part_new := public._tvde_finish_km_part(v_ride, v_new_est);
  v_nat_fare := (v_part_new->>'fare')::int - (v_part_old->>'fare')::int;
  v_nat_drv  := (v_part_new->>'driver')::int - (v_part_old->>'driver')::int;
  v_extra_fee := v_ch.client_diff_cents - v_nat_fare;
  v_extra_drv := v_ch.driver_diff_cents - v_nat_drv;
  IF v_ride.roundtrip_credit_id IS NOT NULL AND COALESCE(v_ride.is_return_leg, false) THEN
    v_paid_km := GREATEST(0,
        GREATEST(0, CEIL(v_new_est - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
      - GREATEST(0, CEIL(COALESCE(v_ride.est_distance_km,0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int);
  END IF;
  IF v_ch.method = 'cash' THEN v_cash := v_ch.client_diff_cents; END IF;

  UPDATE public.tvde_rides SET
    dest_lat = v_ch.new_dest_lat, dest_lng = v_ch.new_dest_lng, dest_label = v_ch.new_dest_label,
    est_distance_km = v_new_est,
    est_fare_cents = COALESCE(est_fare_cents, 0) + v_ch.client_diff_cents,
    driver_earn_cents = COALESCE(driver_earn_cents, 0) + v_ch.driver_diff_cents,
    bora_cut_cents = COALESCE(bora_cut_cents, 0) + v_ch.client_diff_cents - v_ch.driver_diff_cents,
    dest_change_base_price_cents = COALESCE(dest_change_base_price_cents, (v_ch.price_before_cents - dest_change_fee_cents)),
    dest_change_base_driver_cents = COALESCE(dest_change_base_driver_cents, (v_ch.driver_before_cents - dest_change_driver_cents)),
    dest_change_count = dest_change_count + 1,
    dest_change_fee_cents = dest_change_fee_cents + v_ch.client_diff_cents,
    dest_change_driver_cents = dest_change_driver_cents + v_ch.driver_diff_cents,
    dest_change_cash_cents = dest_change_cash_cents + v_cash,
    dest_change_extra_fee_cents = dest_change_extra_fee_cents + v_extra_fee,
    dest_change_extra_driver_cents = dest_change_extra_driver_cents + v_extra_drv,
    dest_change_paid_extra_km = dest_change_paid_extra_km + v_paid_km,
    updated_at = now()
   WHERE id = v_ride.id RETURNING * INTO v_ride;

  UPDATE public.tvde_destination_changes SET estado = 'aplicada', applied_at = now(), updated_at = now(),
    extra_fee_cents = v_extra_fee, extra_driver_cents = v_extra_drv, pricing_branch = v_part_new->>'branch'
   WHERE id = v_ch.id RETURNING * INTO v_ch;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, v_ride.status, COALESCE(v_ch.created_by_role, 'cliente'), jsonb_build_object(
      'event', 'dest_changed', 'change_id', v_ch.id,
      'old_dest_label', v_ch.old_dest_label, 'new_dest_label', v_ch.new_dest_label,
      'km_done', v_ch.km_done, 'km_remaining', v_ch.km_remaining, 'km_new_total', v_ch.km_new_total,
      'km_before', v_ch.km_before, 'est_distance_km', v_new_est,
      'price_before_cents', v_ch.price_before_cents, 'price_new_cents', v_ch.price_new_cents,
      'client_diff_cents', v_ch.client_diff_cents, 'driver_diff_cents', v_ch.driver_diff_cents,
      'min_applied', v_ch.min_applied, 'method', v_ch.method, 'payment_intent_id', v_ch.payment_intent_id,
      'extra_fee_cents', v_extra_fee, 'extra_driver_cents', v_extra_drv, 'paid_extra_km', v_paid_km,
      'branch', v_part_new->>'branch'));

  -- Push ao motorista (fire-and-forget; nunca falha a mudança por causa do push).
  BEGIN
    IF v_ride.driver_id IS NOT NULL THEN
      v_jwt := public._dispatch_jwt();
      PERFORM net.http_post(
        url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-driver',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_jwt),
        body    := jsonb_build_object('kind','dest_changed',
                     'driverId', v_ride.driver_id::text,
                     'rideId', v_ride.id::text,
                     'destLabel', v_ch.new_dest_label,
                     'driverDiffCents', v_ch.driver_diff_cents,
                     'paidOnline', v_ch.method IN ('card','mbway')));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'aplicada',
    'client_diff_cents', v_ch.client_diff_cents, 'driver_diff_cents', v_ch.driver_diff_cents,
    'est_distance_km', v_ride.est_distance_km, 'est_fare_cents', v_ride.est_fare_cents,
    'dest_change_fee_cents', v_ride.dest_change_fee_cents);
END $$;

-- 8) PEDIDO do cliente (depois de "Aceitar") ------------------------------------
-- Dinheiro ou diferença 0 -> aplica já. Cartão/MB Way com diferença -> fica
-- 'proposta' e a Edge tvde-payment cobra; só aplica com o pagamento confirmado.
CREATE OR REPLACE FUNCTION public.tvde_dest_change_request(
  p_ride_id uuid, p_dest_lat double precision, p_dest_lng double precision,
  p_dest_label text DEFAULT NULL, p_done_km numeric DEFAULT 0, p_remaining_km numeric DEFAULT 0,
  p_expected_client_diff_cents integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ride public.tvde_rides; v_calc jsonb; v_ch public.tvde_destination_changes;
  v_method text; v_diff int; v_res jsonb;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  PERFORM public._tvde_dest_change_check(v_ride);
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  v_calc := public._tvde_dest_change_calc(v_ride, p_dest_lat, p_dest_lng, p_done_km, p_remaining_km);
  IF (v_calc->>'km_new_total')::numeric > 300 THEN RAISE EXCEPTION 'dest_too_far'; END IF;
  v_diff := (v_calc->>'client_diff_cents')::int;
  -- Regra 6: o que o cliente viu é o que se cobra. Se o servidor der outro valor, não aplica.
  IF p_expected_client_diff_cents IS NOT NULL AND p_expected_client_diff_cents <> v_diff THEN
    RAISE EXCEPTION 'dest_change_price_changed: %', v_diff; END IF;

  -- Uma proposta por pagar de cada vez: a nova substitui a anterior.
  UPDATE public.tvde_destination_changes SET estado = 'recusada', motivo = 'substituida', updated_at = now()
   WHERE ride_id = v_ride.id AND estado = 'proposta';

  v_method := CASE WHEN v_diff = 0 THEN 'nenhum' ELSE COALESCE(v_ride.payment_method, 'cash') END;
  INSERT INTO public.tvde_destination_changes (ride_id, client_id, driver_id, ride_status,
    old_dest_lat, old_dest_lng, old_dest_label, new_dest_lat, new_dest_lng, new_dest_label,
    km_done, km_remaining, km_new_total, km_before, price_before_cents, price_new_cents, table_diff_cents,
    client_diff_cents, driver_before_cents, driver_new_cents, driver_table_diff_cents, driver_diff_cents,
    min_applied, driver_min_applied, method, estado, created_by, created_by_role)
  VALUES (v_ride.id, v_ride.client_id, v_ride.driver_id, v_ride.status,
    v_ride.dest_lat, v_ride.dest_lng, v_ride.dest_label, p_dest_lat, p_dest_lng, p_dest_label,
    (v_calc->>'km_done')::numeric, (v_calc->>'km_remaining')::numeric, (v_calc->>'km_new_total')::numeric,
    (v_calc->>'km_before')::numeric, (v_calc->>'price_before_cents')::int, (v_calc->>'price_new_cents')::int,
    (v_calc->>'table_diff_cents')::int, v_diff, (v_calc->>'driver_before_cents')::int,
    (v_calc->>'driver_new_cents')::int, (v_calc->>'driver_table_diff_cents')::int,
    (v_calc->>'driver_diff_cents')::int, (v_calc->>'min_applied')::boolean,
    (v_calc->>'driver_min_applied')::boolean, v_method, 'proposta', auth.uid(), 'cliente')
  RETURNING * INTO v_ch;

  IF v_method IN ('card','mbway') THEN
    RETURN v_calc || jsonb_build_object('change_id', v_ch.id, 'estado', 'proposta',
      'needs_payment', true, 'method', v_method);
  END IF;
  v_res := public._tvde_dest_change_apply(v_ch.id);
  RETURN v_calc || v_res || jsonb_build_object('needs_payment', false, 'method', v_method);
END $$;

-- 9) Chamadas do SERVIDOR (Edge tvde-payment, service_role) --------------------
-- Guardar o PaymentIntent criado para a proposta.
CREATE OR REPLACE FUNCTION public.tvde_dest_change_set_pi(p_change_id uuid, p_payment_intent_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.tvde_destination_changes SET payment_intent_id = p_payment_intent_id, updated_at = now()
   WHERE id = p_change_id AND estado = 'proposta';
  IF NOT FOUND THEN RAISE EXCEPTION 'dest_change_not_pending'; END IF;
END $$;

-- Pagamento confirmado pela Stripe -> 'paga' -> aplica. Valor e dono conferidos.
CREATE OR REPLACE FUNCTION public.tvde_dest_change_confirm_paid(
  p_change_id uuid, p_payment_intent_id text, p_amount_cents integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ch public.tvde_destination_changes;
BEGIN
  SELECT * INTO v_ch FROM public.tvde_destination_changes WHERE id = p_change_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'dest_change_not_found'; END IF;
  IF v_ch.estado = 'aplicada' THEN
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'aplicada', 'already', true); END IF;
  IF v_ch.estado <> 'proposta' THEN
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', v_ch.estado, 'refund', true); END IF;
  IF v_ch.payment_intent_id IS DISTINCT FROM p_payment_intent_id THEN RAISE EXCEPTION 'pi_mismatch'; END IF;
  IF p_amount_cents <> v_ch.client_diff_cents THEN RAISE EXCEPTION 'amount_mismatch'; END IF;
  UPDATE public.tvde_destination_changes SET estado = 'paga', paid_at = now(), updated_at = now()
   WHERE id = v_ch.id;
  RETURN public._tvde_dest_change_apply(v_ch.id);
END $$;

-- Pagamento falhou / cancelado -> destino não muda.
CREATE OR REPLACE FUNCTION public.tvde_dest_change_fail(p_change_id uuid, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.tvde_destination_changes SET estado = 'falhada', motivo = left(p_motivo, 200), updated_at = now()
   WHERE id = p_change_id AND estado = 'proposta';
END $$;

-- Cliente desistiu enquanto pagava.
CREATE OR REPLACE FUNCTION public.tvde_dest_change_cancel(p_change_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.tvde_destination_changes SET estado = 'recusada', motivo = 'cliente_cancelou', updated_at = now()
   WHERE id = p_change_id AND estado = 'proposta' AND client_id = auth.uid();
END $$;

-- 10) ADMIN -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_tvde_dest_changes(p_ride_id uuid)
RETURNS SETOF public.tvde_destination_changes LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN QUERY SELECT * FROM public.tvde_destination_changes WHERE ride_id = p_ride_id ORDER BY created_at;
END $$;

-- Corrida de BALCÃO: o admin muda o destino e escreve o valor novo combinado à
-- mão com o cliente (a tvde_finish_ride usa o agreed_* — nada de tabela).
CREATE OR REPLACE FUNCTION public.admin_tvde_dest_change_counter(
  p_ride_id uuid, p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_new_agreed_fare_cents integer, p_new_agreed_driver_earn_cents integer DEFAULT NULL,
  p_est_distance_km numeric DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net', 'extensions' AS $$
DECLARE v_ride public.tvde_rides; v_ch public.tvde_destination_changes; v_old_fare int; v_old_drv int;
  v_jwt text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.agreed_fare_cents IS NULL THEN RAISE EXCEPTION 'not_counter_ride'; END IF;
  IF v_ride.status NOT IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento') THEN
    RAISE EXCEPTION 'invalid_ride_state_for_dest_change: %', v_ride.status; END IF;
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  IF p_new_agreed_fare_cents IS NULL OR p_new_agreed_fare_cents < 0 THEN RAISE EXCEPTION 'invalid_fare'; END IF;
  v_old_fare := v_ride.agreed_fare_cents;
  v_old_drv := COALESCE(v_ride.agreed_driver_earn_cents, v_ride.driver_earn_cents);

  INSERT INTO public.tvde_destination_changes (ride_id, client_id, driver_id, ride_status,
    old_dest_lat, old_dest_lng, old_dest_label, new_dest_lat, new_dest_lng, new_dest_label,
    km_new_total, km_before, price_before_cents, price_new_cents, client_diff_cents,
    driver_before_cents, driver_new_cents, driver_diff_cents, pricing_branch, method, estado,
    motivo, created_by, created_by_role, applied_at, extra_fee_cents, extra_driver_cents)
  VALUES (v_ride.id, v_ride.client_id, v_ride.driver_id, v_ride.status,
    v_ride.dest_lat, v_ride.dest_lng, v_ride.dest_label, p_dest_lat, p_dest_lng, p_dest_label,
    COALESCE(p_est_distance_km, v_ride.est_distance_km, 0), v_ride.est_distance_km, v_old_fare, p_new_agreed_fare_cents,
    p_new_agreed_fare_cents - v_old_fare, v_old_drv, COALESCE(p_new_agreed_driver_earn_cents, v_old_drv),
    COALESCE(p_new_agreed_driver_earn_cents, v_old_drv) - v_old_drv, 'balcao', 'balcao', 'aplicada',
    p_reason, auth.uid(), 'admin', now(), 0, 0)
  RETURNING * INTO v_ch;

  UPDATE public.tvde_rides SET
    dest_lat = p_dest_lat, dest_lng = p_dest_lng, dest_label = p_dest_label,
    est_distance_km = COALESCE(p_est_distance_km, est_distance_km),
    agreed_fare_cents = p_new_agreed_fare_cents,
    agreed_driver_earn_cents = COALESCE(p_new_agreed_driver_earn_cents, agreed_driver_earn_cents),
    est_fare_cents = p_new_agreed_fare_cents,
    driver_earn_cents = COALESCE(p_new_agreed_driver_earn_cents, driver_earn_cents),
    bora_cut_cents = p_new_agreed_fare_cents - COALESCE(p_new_agreed_driver_earn_cents, driver_earn_cents),
    dest_change_count = dest_change_count + 1,
    updated_at = now()
   WHERE id = v_ride.id RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, v_ride.status, 'admin', jsonb_build_object('event', 'dest_changed', 'change_id', v_ch.id,
      'counter', true, 'old_dest_label', v_ch.old_dest_label, 'new_dest_label', p_dest_label,
      'old_agreed_fare_cents', v_old_fare, 'new_agreed_fare_cents', p_new_agreed_fare_cents,
      'old_driver_cents', v_old_drv, 'new_driver_cents', v_ch.driver_new_cents, 'reason', p_reason));

  BEGIN
    IF v_ride.driver_id IS NOT NULL THEN
      v_jwt := public._dispatch_jwt();
      PERFORM net.http_post(
        url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-driver',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_jwt),
        body    := jsonb_build_object('kind','dest_changed', 'driverId', v_ride.driver_id::text,
                     'rideId', v_ride.id::text, 'destLabel', p_dest_label,
                     'driverDiffCents', v_ch.driver_diff_cents, 'paidOnline', false));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'aplicada',
    'agreed_fare_cents', v_ride.agreed_fare_cents, 'agreed_driver_earn_cents', v_ride.agreed_driver_earn_cents);
END $$;

-- 11) Permissões ----------------------------------------------------------------
REVOKE ALL ON FUNCTION public._tvde_table_fare_cents(numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_table_driver_cents(numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_dest_price_cents(public.tvde_rides, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_finish_km_part(public.tvde_rides, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_dest_change_calc(public.tvde_rides, double precision, double precision, numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_dest_change_check(public.tvde_rides) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_dest_change_apply(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_dest_change_set_pi(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_dest_change_confirm_paid(uuid, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_dest_change_fail(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_set_pi(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_confirm_paid(uuid, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_fail(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.tvde_dest_change_quote(uuid, double precision, double precision, text, numeric, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tvde_dest_change_request(uuid, double precision, double precision, text, numeric, numeric, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tvde_dest_change_cancel(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_tvde_dest_changes(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_tvde_dest_change_counter(uuid, double precision, double precision, text, integer, integer, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_quote(uuid, double precision, double precision, text, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_request(uuid, double precision, double precision, text, numeric, numeric, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_cancel(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tvde_dest_changes(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tvde_dest_change_counter(uuid, double precision, double precision, text, integer, integer, numeric, text) TO authenticated;
