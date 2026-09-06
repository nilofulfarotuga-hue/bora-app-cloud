-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F1 — Migration 1/3: Tabelas configuracao restaurante
-- Data: 2026-05-08 / Sessao reservas-pro-F1-SCHEMA
--
-- 4 tabelas:
-- 1. restaurant_floor_plans: multi-layout (normal/eventos)
-- 2. restaurant_tables: mesas fisicas individuais
-- 3. restaurant_pacing_rules: limites por slot horario
-- 4. restaurant_turn_times: tempo medio por party size
--
-- RLS RGPD-compliant: partner so dos seus restaurantes,
-- admin via service_role bypass, anonymous bloqueado.
--
-- Aplicada via MCP em prod antes do ficheiro local.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE public.restaurant_floor_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  is_default boolean NOT NULL DEFAULT false,
  width_cm integer DEFAULT 1000,
  height_cm integer DEFAULT 800,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_floor_plans_restaurant ON public.restaurant_floor_plans(restaurant_id) WHERE active = true;
CREATE UNIQUE INDEX idx_floor_plans_one_default ON public.restaurant_floor_plans(restaurant_id) WHERE is_default = true;

COMMENT ON TABLE public.restaurant_floor_plans IS
  'Multi-layout do restaurante. Permite ter plano "Normal" + "Dia Namorados" + "Eventos" e trocar conforme dia/ocasiao. is_default=true para o plano activo por defeito.';

CREATE TABLE public.restaurant_tables (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  floor_plan_id uuid REFERENCES public.restaurant_floor_plans(id) ON DELETE SET NULL,
  numero text NOT NULL CHECK (length(numero) BETWEEN 1 AND 20),
  capacity integer NOT NULL CHECK (capacity BETWEEN 1 AND 30),
  zona text NOT NULL DEFAULT 'interior'
    CHECK (zona IN ('interior','esplanada','balcao','privé','terraço','bar','outdoor')),
  pos_x numeric(8,2) DEFAULT 0,
  pos_y numeric(8,2) DEFAULT 0,
  rotation_deg integer DEFAULT 0 CHECK (rotation_deg BETWEEN 0 AND 359),
  shape text DEFAULT 'rectangle' CHECK (shape IN ('rectangle','round','square','oval')),
  combinable_with uuid[] DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(restaurant_id, numero)
);

CREATE INDEX idx_tables_restaurant_active ON public.restaurant_tables(restaurant_id) WHERE active = true;
CREATE INDEX idx_tables_floor_plan ON public.restaurant_tables(floor_plan_id) WHERE floor_plan_id IS NOT NULL;

COMMENT ON TABLE public.restaurant_tables IS
  'Mesas fisicas individuais. numero unique por restaurante (T1, T2, Mesa A...). combinable_with: array IDs mesas que podem juntar-se a esta para grupos grandes (sem FK constraint Postgres — integridade na app). pos_x/pos_y: coordenadas no floor plan visual.';

CREATE TABLE public.restaurant_pacing_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  day_of_week integer NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  slot_start time NOT NULL,
  slot_end time NOT NULL,
  max_covers integer CHECK (max_covers IS NULL OR max_covers > 0),
  max_reservations integer CHECK (max_reservations IS NULL OR max_reservations > 0),
  walk_in_reserved_pct integer NOT NULL DEFAULT 25 CHECK (walk_in_reserved_pct BETWEEN 0 AND 100),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (slot_end > slot_start)
);

CREATE INDEX idx_pacing_restaurant_day ON public.restaurant_pacing_rules(restaurant_id, day_of_week) WHERE active = true;

COMMENT ON TABLE public.restaurant_pacing_rules IS
  'Limites de capacidade por slot horario. day_of_week: 0=Domingo,6=Sabado (Postgres DOW). max_covers: limite total de pessoas no slot. walk_in_reserved_pct: % de mesas reservadas para walk-ins (clientes sem reserva). NULL em max_covers/max_reservations = ilimitado.';

CREATE TABLE public.restaurant_turn_times (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  party_size_min integer NOT NULL CHECK (party_size_min >= 1),
  party_size_max integer NOT NULL CHECK (party_size_max >= party_size_min),
  day_of_week integer CHECK (day_of_week IS NULL OR day_of_week BETWEEN 0 AND 6),
  minutes integer NOT NULL CHECK (minutes BETWEEN 15 AND 480),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_turn_times_restaurant ON public.restaurant_turn_times(restaurant_id) WHERE active = true;

COMMENT ON TABLE public.restaurant_turn_times IS
  'Tempo medio que uma mesa fica ocupada por party size. Ex: 2 pessoas=90min, 4 pessoas=120min, 6+=150min. day_of_week NULL = aplica a qualquer dia. Permite turn times diferentes weekend vs semana.';

ALTER TABLE public.restaurant_floor_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_pacing_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_turn_times ENABLE ROW LEVEL SECURITY;

CREATE POLICY floor_plans_partner_owner ON public.restaurant_floor_plans
  FOR ALL TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()))
  WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE POLICY tables_partner_owner ON public.restaurant_tables
  FOR ALL TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()))
  WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE POLICY pacing_partner_owner ON public.restaurant_pacing_rules
  FOR ALL TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()))
  WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE POLICY turn_times_partner_owner ON public.restaurant_turn_times
  FOR ALL TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()))
  WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE POLICY floor_plans_public_read ON public.restaurant_floor_plans
  FOR SELECT TO authenticated USING (active = true);

CREATE POLICY tables_public_read ON public.restaurant_tables
  FOR SELECT TO authenticated USING (active = true);

CREATE OR REPLACE FUNCTION public._reservas_pro_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_floor_plans_updated_at BEFORE UPDATE ON public.restaurant_floor_plans
  FOR EACH ROW EXECUTE FUNCTION public._reservas_pro_set_updated_at();
CREATE TRIGGER trg_tables_updated_at BEFORE UPDATE ON public.restaurant_tables
  FOR EACH ROW EXECUTE FUNCTION public._reservas_pro_set_updated_at();
CREATE TRIGGER trg_pacing_updated_at BEFORE UPDATE ON public.restaurant_pacing_rules
  FOR EACH ROW EXECUTE FUNCTION public._reservas_pro_set_updated_at();
