-- ============================================================================
-- Serviços / Barbearias — Tabelas core + índices
-- Vertical de marcações (appointments). Separado de restaurants: sem menu,
-- sem delivery, sem dispatch. Padrão: IDs de negócio = TEXT (como restaurants).
-- ============================================================================

-- 1.1 service_providers — barbearias e futuros prestadores de serviços
CREATE TABLE IF NOT EXISTS public.service_providers (
  id                TEXT PRIMARY KEY DEFAULT (gen_random_uuid())::text,
  user_id           UUID REFERENCES auth.users(id),
  name              TEXT NOT NULL,
  category          TEXT NOT NULL DEFAULT 'barbershop',   -- barbershop | salon | ...
  description       TEXT,
  address           TEXT,
  lat               DOUBLE PRECISION,
  lng               DOUBLE PRECISION,
  phone             TEXT,
  photo_url         TEXT DEFAULT '',
  hero_image_url    TEXT DEFAULT '',
  is_online         BOOLEAN NOT NULL DEFAULT false,
  is_active_admin   BOOLEAN NOT NULL DEFAULT true,
  approval_status   TEXT NOT NULL DEFAULT 'pending',      -- pending|approved|rejected
  approved_at       TIMESTAMPTZ,
  approved_by       UUID,
  rejection_reason  TEXT,
  business_hours    JSONB NOT NULL DEFAULT '{"mon":{"open":"09:00","close":"19:00","closed":false},"tue":{"open":"09:00","close":"19:00","closed":false},"wed":{"open":"09:00","close":"19:00","closed":false},"thu":{"open":"09:00","close":"19:00","closed":false},"fri":{"open":"09:00","close":"19:00","closed":false},"sat":{"open":"09:00","close":"17:00","closed":false},"sun":{"open":"09:00","close":"17:00","closed":true}}'::jsonb,
  avg_rating        NUMERIC,
  ratings_count     INTEGER DEFAULT 0,
  fcm_token         TEXT,
  nif               TEXT,
  iban              TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1.2 staff_members — barbeiros/funcionários
CREATE TABLE IF NOT EXISTS public.staff_members (
  id            TEXT PRIMARY KEY DEFAULT (gen_random_uuid())::text,
  provider_id   TEXT NOT NULL REFERENCES public.service_providers(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  bio           TEXT,
  photo_url     TEXT DEFAULT '',
  specialties   TEXT[] DEFAULT '{}',
  is_active     BOOLEAN NOT NULL DEFAULT true,
  sort_order    INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1.3 provider_services — serviços (corte, barba, ...) com duração e preço
CREATE TABLE IF NOT EXISTS public.provider_services (
  id                TEXT PRIMARY KEY DEFAULT (gen_random_uuid())::text,
  provider_id       TEXT NOT NULL REFERENCES public.service_providers(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  duration_minutes  INTEGER NOT NULL DEFAULT 30,
  price_cents       INTEGER NOT NULL,
  photo_url         TEXT DEFAULT '',
  is_active         BOOLEAN NOT NULL DEFAULT true,
  sort_order        INTEGER DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1.4 staff_availability — horário de trabalho por barbeiro (por dia da semana)
CREATE TABLE IF NOT EXISTS public.staff_availability (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id      TEXT NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  day_of_week   SMALLINT NOT NULL,         -- 0=Dom, 1=Seg, ..., 6=Sáb
  start_time    TIME NOT NULL,
  end_time      TIME NOT NULL,
  is_working    BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (staff_id, day_of_week)
);

-- 1.5 appointments — coração do sistema
CREATE TABLE IF NOT EXISTS public.appointments (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id           TEXT NOT NULL REFERENCES public.service_providers(id),
  staff_id              TEXT REFERENCES public.staff_members(id),
  service_id            TEXT REFERENCES public.provider_services(id),
  client_user_id        UUID REFERENCES auth.users(id),
  client_name           TEXT NOT NULL DEFAULT '',
  client_phone          TEXT NOT NULL DEFAULT '',

  -- Horário
  scheduled_at          TIMESTAMPTZ NOT NULL,
  duration_minutes      INTEGER NOT NULL,

  -- Financeiro
  service_price_cents   INTEGER NOT NULL DEFAULT 0,
  deposit_cents         INTEGER NOT NULL DEFAULT 300,
  deposit_pi            TEXT,                              -- Stripe PaymentIntent do sinal
  deposit_status        TEXT NOT NULL DEFAULT 'pending',  -- pending|paid|refunded|retained|waived
  full_payment_method   TEXT,                             -- app|on_site|null
  full_payment_pi       TEXT,
  full_payment_status   TEXT DEFAULT 'pending',           -- pending|paid

  -- Estado
  status                TEXT NOT NULL DEFAULT 'pending_payment',
  -- pending_payment → confirmed → completed | no_show | cancelled | blocked

  -- Timestamps de estado
  confirmed_at          TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  cancelled_at          TIMESTAMPTZ,
  cancel_reason         TEXT,
  cancelled_by          TEXT,                             -- client|partner|admin
  no_show_at            TIMESTAMPTZ,

  -- Lembretes
  reminder_24h_sent_at  TIMESTAMPTZ,
  reminder_2h_sent_at   TIMESTAMPTZ,

  -- Notas
  client_notes          TEXT,
  partner_notes         TEXT,

  -- Walk-in / bloqueio
  is_walk_in            BOOLEAN NOT NULL DEFAULT false,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1.6 appointment_payouts — liquidação semanal ao parceiro (modelo driver_weekly_settlements)
CREATE TABLE IF NOT EXISTS public.appointment_payouts (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id                   TEXT NOT NULL REFERENCES public.service_providers(id),
  week_start_at                 TIMESTAMPTZ NOT NULL,
  week_end_at                   TIMESTAMPTZ NOT NULL,
  total_appointments            INTEGER NOT NULL DEFAULT 0,
  total_service_revenue_cents   INTEGER NOT NULL DEFAULT 0,  -- serviços pagos na app
  total_deposits_retained_cents INTEGER NOT NULL DEFAULT 0,  -- sinais retidos (no-show)
  bora_booking_fees_cents       INTEGER NOT NULL DEFAULT 0,  -- €0,50 × n concluídas
  bora_deposit_cut_cents        INTEGER NOT NULL DEFAULT 0,  -- €0,50 × no-shows
  net_payout_cents              INTEGER NOT NULL DEFAULT 0,  -- o que Bora paga ao parceiro
  direction                     TEXT NOT NULL DEFAULT 'bora_to_partner',
  status                        TEXT NOT NULL DEFAULT 'pending',  -- pending|paid
  payment_method                TEXT,
  payment_reference             TEXT,
  paid_at                       TIMESTAMPTZ,
  paid_by                       UUID,
  notes                         TEXT,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider_id, week_start_at)
);

-- 1.8 Índices essenciais
CREATE INDEX IF NOT EXISTS idx_appointments_provider  ON public.appointments(provider_id);
CREATE INDEX IF NOT EXISTS idx_appointments_staff      ON public.appointments(staff_id);
CREATE INDEX IF NOT EXISTS idx_appointments_client     ON public.appointments(client_user_id);
CREATE INDEX IF NOT EXISTS idx_appointments_scheduled  ON public.appointments(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_appointments_status     ON public.appointments(status);
CREATE INDEX IF NOT EXISTS idx_staff_provider          ON public.staff_members(provider_id);
CREATE INDEX IF NOT EXISTS idx_services_provider       ON public.provider_services(provider_id);
CREATE INDEX IF NOT EXISTS idx_availability_staff      ON public.staff_availability(staff_id);
CREATE INDEX IF NOT EXISTS idx_service_providers_owner ON public.service_providers(user_id);
CREATE INDEX IF NOT EXISTS idx_appointment_payouts_provider ON public.appointment_payouts(provider_id);

-- updated_at trigger reutiliza função genérica se existir; senão cria uma local
CREATE OR REPLACE FUNCTION public._appointments_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_service_providers_updated ON public.service_providers;
CREATE TRIGGER trg_service_providers_updated BEFORE UPDATE ON public.service_providers
  FOR EACH ROW EXECUTE FUNCTION public._appointments_set_updated_at();

DROP TRIGGER IF EXISTS trg_appointments_updated ON public.appointments;
CREATE TRIGGER trg_appointments_updated BEFORE UPDATE ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public._appointments_set_updated_at();
