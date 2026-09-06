-- ============================================================================
-- BORA MOTORISTA (TVDE) — FASE 1 · Schema isolado
-- ============================================================================
-- Vertical de transporte de passageiros, 100% ISOLADA do delivery.
-- NÃO toca: orders, order_financials, ledger_entries, pricing_calculate,
-- dispatch-engine, bora_tokens, webhooks Stripe.
-- Tudo paralelo: tvde_* + tvde_calculate_fare + tvde_driver_balances.
-- ============================================================================

BEGIN;

-- ── Gate de acesso (categoria escondida) ────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS tvde_access BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users.tvde_access IS
  'TVDE: categoria Bora Motorista só aparece ao cliente quando true (aprovado pelo admin).';

-- ── drivers.vehicle_type ────────────────────────────────────────────────────
-- vehicle_type é TEXT livre (sem CHECK constraint). O valor canónico para
-- motorista de passageiros é 'carro_passageiros'. O MATCHING de corridas filtra
-- SEMPRE por esta coluna (nunca pelo enum do Flutter). Index parcial p/ dispatch.
CREATE INDEX IF NOT EXISTS idx_drivers_passenger_online
  ON public.drivers (is_online)
  WHERE vehicle_type = 'carro_passageiros';

-- ── Pedidos de acesso (cliente → aprovação admin) ───────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_access_requests (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status        TEXT NOT NULL DEFAULT 'pendente'
                  CHECK (status IN ('pendente','aprovado','recusado')),
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at    TIMESTAMPTZ,
  decided_by    UUID REFERENCES auth.users(id),
  decision_note TEXT
);
CREATE INDEX IF NOT EXISTS idx_tvde_acc_req_client ON public.tvde_access_requests (client_id);
CREATE INDEX IF NOT EXISTS idx_tvde_acc_req_status ON public.tvde_access_requests (status);
-- No máximo 1 pedido pendente por cliente
CREATE UNIQUE INDEX IF NOT EXISTS uq_tvde_acc_req_pending
  ON public.tvde_access_requests (client_id) WHERE status = 'pendente';

-- ── Corridas (ISOLADA de orders) ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_rides (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id               UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  driver_id               UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
  -- localização
  origin_lat              DOUBLE PRECISION NOT NULL,
  origin_lng              DOUBLE PRECISION NOT NULL,
  origin_label            TEXT,
  dest_lat                DOUBLE PRECISION NOT NULL,
  dest_lng                DOUBLE PRECISION NOT NULL,
  dest_label              TEXT,
  -- tarifa (cents)
  est_distance_km         NUMERIC(8,2) NOT NULL,
  est_fare_cents          INTEGER NOT NULL,
  final_distance_km       NUMERIC(8,2),
  final_fare_cents        INTEGER,
  driver_earn_cents       INTEGER,
  bora_cut_cents          INTEGER,
  -- pagamento / assinatura
  payment_method          TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash')),
  subscription_id         UUID,
  used_subscription_ride  BOOLEAN NOT NULL DEFAULT false,
  -- cancelamento
  cancel_fee_cents        INTEGER NOT NULL DEFAULT 0,
  cancel_reason           TEXT,
  -- ciclo de vida
  status                  TEXT NOT NULL DEFAULT 'solicitada'
                            CHECK (status IN ('solicitada','motorista_atribuido',
                              'motorista_a_caminho','motorista_chegou','em_andamento',
                              'finalizada','cancelada_cliente','cancelada_motorista',
                              'no_show','sem_motorista')),
  -- oferta de dispatch (fonte de verdade da oferta ativa)
  current_offer_driver_id UUID,
  offer_expires_at        TIMESTAMPTZ,
  -- avaliação bidirecional (cache; ratings vivem em public.ratings)
  rated_by_client         BOOLEAN NOT NULL DEFAULT false,
  rated_by_driver         BOOLEAN NOT NULL DEFAULT false,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tvde_rides_client ON public.tvde_rides (client_id);
CREATE INDEX IF NOT EXISTS idx_tvde_rides_driver ON public.tvde_rides (driver_id);
CREATE INDEX IF NOT EXISTS idx_tvde_rides_status ON public.tvde_rides (status);
CREATE INDEX IF NOT EXISTS idx_tvde_rides_offer ON public.tvde_rides (current_offer_driver_id)
  WHERE current_offer_driver_id IS NOT NULL;

COMMENT ON TABLE public.tvde_rides IS
  'TVDE Bora Motorista — corridas de passageiros. ISOLADA de orders/dispatch-engine.';

-- ── Histórico de estados da corrida ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_ride_events (
  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id  UUID NOT NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  status   TEXT NOT NULL,
  actor    TEXT,              -- 'client' | 'driver' | 'system' | 'admin'
  meta     JSONB,
  at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tvde_ride_events_ride ON public.tvde_ride_events (ride_id);

-- ── Assinaturas (2 corridas/dia incluídas) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_subscriptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  plan            TEXT NOT NULL CHECK (plan IN ('semanal','quinzenal','mensal')),
  rides_total     INTEGER NOT NULL,
  rides_used      INTEGER NOT NULL DEFAULT 0,
  daily_included  INTEGER NOT NULL DEFAULT 2,
  price_cents     INTEGER NOT NULL,
  granted_by      UUID REFERENCES auth.users(id),
  starts_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at         TIMESTAMPTZ NOT NULL,
  active          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tvde_subs_client ON public.tvde_subscriptions (client_id);
CREATE INDEX IF NOT EXISTS idx_tvde_subs_active ON public.tvde_subscriptions (client_id, active) WHERE active;

-- ── Contador diário de corridas ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_ride_counters (
  client_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  day          DATE NOT NULL,
  rides_count  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (client_id, day)
);

-- ── Liquidação CASH isolada (mirror driver_balances) ────────────────────────
-- balance = euros que o motorista DEVE ao Bora (parte do Bora recebida em cash).
CREATE TABLE IF NOT EXISTS public.tvde_driver_balances (
  driver_id   UUID PRIMARY KEY REFERENCES public.drivers(id) ON DELETE CASCADE,
  balance     NUMERIC(12,2) NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.tvde_driver_balances IS
  'TVDE: dívida do motorista ao Bora por corridas cash (mirror driver_balances). Settle semanal. NUNCA ledger_entries/orders.';

-- ════════════════════════════════════════════════════════════════════════════
-- RLS — leitura direta para as partes; escrita só via RPC SECURITY DEFINER.
-- Admin lê via is_admin() (helper já existente).
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.tvde_access_requests  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tvde_rides            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tvde_ride_events      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tvde_subscriptions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tvde_ride_counters    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tvde_driver_balances  ENABLE ROW LEVEL SECURITY;

-- access_requests
DROP POLICY IF EXISTS tvde_acc_req_select ON public.tvde_access_requests;
CREATE POLICY tvde_acc_req_select ON public.tvde_access_requests
  FOR SELECT TO authenticated
  USING (client_id = auth.uid() OR public.is_admin());

-- rides: cliente, motorista atribuído, ou motorista ofertado; admin tudo
DROP POLICY IF EXISTS tvde_rides_select ON public.tvde_rides;
CREATE POLICY tvde_rides_select ON public.tvde_rides
  FOR SELECT TO authenticated
  USING (client_id = auth.uid()
         OR driver_id = auth.uid()
         OR current_offer_driver_id = auth.uid()
         OR public.is_admin());

-- ride_events: quem participa na corrida + admin
DROP POLICY IF EXISTS tvde_ride_events_select ON public.tvde_ride_events;
CREATE POLICY tvde_ride_events_select ON public.tvde_ride_events
  FOR SELECT TO authenticated
  USING (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.tvde_rides r
    WHERE r.id = ride_id
      AND (r.client_id = auth.uid() OR r.driver_id = auth.uid()
           OR r.current_offer_driver_id = auth.uid())
  ));

-- subscriptions
DROP POLICY IF EXISTS tvde_subs_select ON public.tvde_subscriptions;
CREATE POLICY tvde_subs_select ON public.tvde_subscriptions
  FOR SELECT TO authenticated
  USING (client_id = auth.uid() OR public.is_admin());

-- counters
DROP POLICY IF EXISTS tvde_counters_select ON public.tvde_ride_counters;
CREATE POLICY tvde_counters_select ON public.tvde_ride_counters
  FOR SELECT TO authenticated
  USING (client_id = auth.uid() OR public.is_admin());

-- driver balances
DROP POLICY IF EXISTS tvde_driver_bal_select ON public.tvde_driver_balances;
CREATE POLICY tvde_driver_bal_select ON public.tvde_driver_balances
  FOR SELECT TO authenticated
  USING (driver_id = auth.uid() OR public.is_admin());

-- ════════════════════════════════════════════════════════════════════════════
-- platform_settings — chaves TVDE (categoria 'tvde')
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_base_fare_cents',     '500',   'TVDE: tarifa base cliente (até 6km)',        'tvde'),
  ('tvde_base_distance_km',    '6',     'TVDE: distância incluída na base (km)',      'tvde'),
  ('tvde_extra_per_km_cents',  '50',    'TVDE: €/km cliente acima da base',           'tvde'),
  ('tvde_driver_base_cents',   '400',   'TVDE: ganho base do motorista',              'tvde'),
  ('tvde_driver_per_km_cents', '40',    'TVDE: €/km extra do motorista',              'tvde'),
  ('tvde_plan_weekly_cents',   '5600',  'TVDE: plano semanal (14 corridas)',          'tvde'),
  ('tvde_plan_biweekly_cents', '10500', 'TVDE: plano quinzenal (30 corridas)',        'tvde'),
  ('tvde_plan_monthly_cents',  '18000', 'TVDE: plano mensal (60 corridas)',           'tvde'),
  ('tvde_extra_ride_cents',    '450',   'TVDE: corrida extra acima do incluído',      'tvde'),
  ('tvde_plan_daily_included', '2',     'TVDE: corridas incluídas por dia',           'tvde'),
  ('tvde_cancel_fee_cents',    '0',     'TVDE: taxa de cancelamento (placeholder)',   'tvde')
ON CONFLICT (key) DO NOTHING;

-- ════════════════════════════════════════════════════════════════════════════
-- tvde_calculate_fare(distance_km) — ISOLADA de pricing_calculate
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tvde_calculate_fare(p_distance_km NUMERIC)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (public.get_setting('tvde_base_fare_cents') #>> '{}')::int
       + GREATEST(0, CEIL(p_distance_km
           - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
         * (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
$$;
REVOKE ALL ON FUNCTION public.tvde_calculate_fare(NUMERIC) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_calculate_fare(NUMERIC) TO authenticated;

-- ── Realtime (mapa/estado ao vivo no cliente e motorista) ───────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='tvde_rides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tvde_rides;
  END IF;
END $$;

COMMIT;
