-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F1 — Migration 2/3: Tabelas runtime de reservas
-- Data: 2026-05-08 / Sessao reservas-pro-F1-SCHEMA
--
-- 4 tabelas:
-- 1. reservation_table_assignments: qual(is) mesa(s) atribuida(s)
-- 2. reservation_waitlist: fila de espera quando cheio
-- 3. reservation_notify_list: cliente avisado se vagar
-- 4. client_restaurant_profiles: historico/preferencias por cliente
--
-- RLS RGPD-compliant.
--
-- Aplicada via MCP em prod antes do ficheiro local.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE public.reservation_table_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
  table_id uuid NOT NULL REFERENCES public.restaurant_tables(id) ON DELETE RESTRICT,
  is_primary boolean NOT NULL DEFAULT true,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  UNIQUE(reservation_id, table_id)
);

CREATE INDEX idx_table_assignments_reservation ON public.reservation_table_assignments(reservation_id);
CREATE INDEX idx_table_assignments_table ON public.reservation_table_assignments(table_id);

COMMENT ON TABLE public.reservation_table_assignments IS
  'Liga reserva a mesa(s). Permite combinar mesas para grupos grandes (1 reserva = N mesas). is_primary=true marca a mesa principal quando combinadas. assigned_by: quem atribuiu (parceiro/admin/auto).';

CREATE TABLE public.reservation_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  client_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  client_name text NOT NULL CHECK (length(client_name) BETWEEN 1 AND 120),
  client_phone text NOT NULL CHECK (length(client_phone) BETWEEN 1 AND 30),
  people integer NOT NULL CHECK (people BETWEEN 1 AND 50),
  target_date date NOT NULL,
  target_time_start time,
  target_time_end time,
  status text NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting','notified','seated','expired','cancelled')),
  position integer,
  notified_at timestamptz,
  seated_at timestamptz,
  expired_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (target_time_end IS NULL OR target_time_start IS NULL OR target_time_end >= target_time_start)
);

CREATE INDEX idx_waitlist_restaurant_active ON public.reservation_waitlist(restaurant_id, target_date) WHERE status = 'waiting';
CREATE INDEX idx_waitlist_client ON public.reservation_waitlist(client_user_id) WHERE status IN ('waiting','notified');

COMMENT ON TABLE public.reservation_waitlist IS
  'Fila de espera quando restaurante esta cheio. Cliente entra na fila, recebe push quando ha mesa livre. position: ordem na fila (1=primeiro). target_time_start/end: janela horaria aceitavel.';

CREATE TABLE public.reservation_notify_list (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  client_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_date date NOT NULL,
  target_time time NOT NULL,
  flexibility_minutes integer NOT NULL DEFAULT 30 CHECK (flexibility_minutes BETWEEN 0 AND 180),
  people integer NOT NULL CHECK (people BETWEEN 1 AND 50),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','notified','converted','expired','cancelled')),
  notified_at timestamptz,
  converted_to_reservation_id uuid REFERENCES public.reservations(id) ON DELETE SET NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notify_active ON public.reservation_notify_list(restaurant_id, target_date, target_time) WHERE status = 'active';
CREATE INDEX idx_notify_expiring ON public.reservation_notify_list(expires_at) WHERE status = 'active';
CREATE INDEX idx_notify_client ON public.reservation_notify_list(client_user_id);

COMMENT ON TABLE public.reservation_notify_list IS
  'Lista de "avisar se vagar". Cliente quer 20h sabado -> cheio -> entra Notify -> recebe push se alguem cancelar dentro da janela (target_time +/- flexibility_minutes). Modelo OpenTable Notify / Resy Notify.';

CREATE TABLE public.client_restaurant_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id text NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  total_visits integer NOT NULL DEFAULT 0,
  total_no_shows integer NOT NULL DEFAULT 0,
  total_late_cancels integer NOT NULL DEFAULT 0,
  last_visit_at timestamptz,
  is_vip boolean NOT NULL DEFAULT false,
  is_blocked boolean NOT NULL DEFAULT false,
  blocked_reason text,
  blocked_at timestamptz,
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  partner_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(client_user_id, restaurant_id)
);

CREATE INDEX idx_client_profiles_restaurant ON public.client_restaurant_profiles(restaurant_id);
CREATE INDEX idx_client_profiles_vip ON public.client_restaurant_profiles(restaurant_id) WHERE is_vip = true;
CREATE INDEX idx_client_profiles_blocked ON public.client_restaurant_profiles(restaurant_id) WHERE is_blocked = true;

COMMENT ON TABLE public.client_restaurant_profiles IS
  'Perfil cliente por restaurante. Historico (visits/no-shows), VIP tag, bloqueios (cliente abusivo), preferencias JSONB (alergias, mesa preferida, ocasioes), notas internas do parceiro. UNIQUE(client_user_id, restaurant_id) — 1 perfil por par cliente-restaurante.';

ALTER TABLE public.reservation_table_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservation_notify_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_restaurant_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY assignments_client_owner ON public.reservation_table_assignments
  FOR SELECT TO authenticated
  USING (reservation_id IN (SELECT id FROM public.reservations WHERE client_user_id = auth.uid()));

CREATE POLICY assignments_partner_owner ON public.reservation_table_assignments
  FOR ALL TO authenticated
  USING (reservation_id IN (
    SELECT r.id FROM public.reservations r
    WHERE r.restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid())
  ));

CREATE POLICY waitlist_client_owner ON public.reservation_waitlist
  FOR ALL TO authenticated
  USING (client_user_id = auth.uid())
  WITH CHECK (client_user_id = auth.uid());

CREATE POLICY waitlist_partner_owner ON public.reservation_waitlist
  FOR ALL TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE POLICY notify_client_owner ON public.reservation_notify_list
  FOR ALL TO authenticated
  USING (client_user_id = auth.uid())
  WITH CHECK (client_user_id = auth.uid());

CREATE POLICY notify_partner_read ON public.reservation_notify_list
  FOR SELECT TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE POLICY profiles_client_read ON public.client_restaurant_profiles
  FOR SELECT TO authenticated
  USING (client_user_id = auth.uid());

CREATE POLICY profiles_partner_full ON public.client_restaurant_profiles
  FOR ALL TO authenticated
  USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()))
  WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE user_ = auth.uid()));

CREATE TRIGGER trg_client_profiles_updated_at BEFORE UPDATE ON public.client_restaurant_profiles
  FOR EACH ROW EXECUTE FUNCTION public._reservas_pro_set_updated_at();
