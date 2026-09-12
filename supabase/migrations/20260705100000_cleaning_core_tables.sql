-- ============================================================================
-- LIMPEZA (cleaning) — Tabelas core + índices
-- Vertical PARALELA (tipo Helpling/Oscar): limpezas domésticas AGENDADAS.
-- Isolada da vertical de entregas e do motor de despacho (como TVDE).
-- IDs = UUID (vertical nova, sem legado TEXT). Profissionais = cleaners.
-- Split: 85% profissional / 15% Bora (settings cleaning_*).
-- ============================================================================

-- 1. cleaners — profissionais de limpeza independentes
CREATE TABLE IF NOT EXISTS public.cleaners (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL UNIQUE REFERENCES auth.users(id),
  name               TEXT NOT NULL,
  phone              TEXT NOT NULL DEFAULT '',
  email              TEXT NOT NULL DEFAULT '',
  photo_url          TEXT NOT NULL DEFAULT '',
  bio                TEXT NOT NULL DEFAULT '',
  nif                TEXT NOT NULL DEFAULT '',
  docs               JSONB NOT NULL DEFAULT '{}'::jsonb,  -- urls storage: id_doc, address_proof, ...
  base_lat           DOUBLE PRECISION,
  base_lng           DOUBLE PRECISION,
  base_address       TEXT NOT NULL DEFAULT '',
  service_radius_km  NUMERIC NOT NULL DEFAULT 10 CHECK (service_radius_km > 0 AND service_radius_km <= 100),
  approval_status    TEXT NOT NULL DEFAULT 'pending'
                     CHECK (approval_status IN ('pending','approved','rejected','suspended')),
  approved_at        TIMESTAMPTZ,
  approved_by        UUID,
  rejection_reason   TEXT,
  is_active          BOOLEAN NOT NULL DEFAULT true,   -- interruptor da própria profissional
  rating_avg         NUMERIC NOT NULL DEFAULT 0,
  ratings_count      INTEGER NOT NULL DEFAULT 0,
  cleanings_done     INTEGER NOT NULL DEFAULT 0,
  flagged_low_rating BOOLEAN NOT NULL DEFAULT false,  -- média <4.0 em 10 serviços → revisão admin
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. cleaner_availability — grelha semanal (dias × janelas horárias)
CREATE TABLE IF NOT EXISTS public.cleaner_availability (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cleaner_id  UUID NOT NULL REFERENCES public.cleaners(id) ON DELETE CASCADE,
  weekday     SMALLINT NOT NULL CHECK (weekday BETWEEN 0 AND 6),  -- 0=domingo (ISO dow % 7)
  start_time  TIME NOT NULL,
  end_time    TIME NOT NULL,
  CHECK (end_time > start_time)
);

-- 3. cleaning_bookings — reservas de limpeza (agendadas, não on-demand)
CREATE TABLE IF NOT EXISTS public.cleaning_bookings (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id        UUID NOT NULL REFERENCES auth.users(id),
  cleaner_id            UUID REFERENCES public.cleaners(id),          -- NULL até aceitar
  requested_cleaner_id  UUID REFERENCES public.cleaners(id),          -- escolha do cliente ("favorita")
  recurrence_group_id   UUID,                                         -- série de recorrência
  recurrence            TEXT NOT NULL DEFAULT 'single'
                        CHECK (recurrence IN ('single','weekly','biweekly')),
  cleaning_type         TEXT NOT NULL DEFAULT 'standard'
                        CHECK (cleaning_type IN ('standard','deep','post_works')),
  pricing_mode          TEXT NOT NULL DEFAULT 'fixed'
                        CHECK (pricing_mode IN ('fixed','hourly')),
  home_size             TEXT CHECK (home_size IN ('t0_t1','t2','t3','t4plus')),
  hours                 INTEGER,                                      -- só hourly (>= mínimo)
  scheduled_at          TIMESTAMPTZ NOT NULL,
  duration_min          INTEGER NOT NULL DEFAULT 180,
  address_street        TEXT NOT NULL DEFAULT '',
  address_city          TEXT NOT NULL DEFAULT '',
  address_postal        TEXT NOT NULL DEFAULT '',
  lat                   DOUBLE PRECISION,
  lng                   DOUBLE PRECISION,
  notes                 TEXT NOT NULL DEFAULT '',
  products_by           TEXT NOT NULL DEFAULT 'client'
                        CHECK (products_by IN ('client','cleaner')),  -- cleaner = +taxa produtos
  status                TEXT NOT NULL DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled','accepted','on_the_way','in_progress',
                                          'done','completed','cancelled_client','cancelled_cleaner')),
  -- pagamento (escrow-like; Stripe só após ativação — ver relatório Lista Vermelha)
  payment_method        TEXT NOT NULL DEFAULT 'cash'
                        CHECK (payment_method IN ('card','mbway','cash')),
  payment_status        TEXT NOT NULL DEFAULT 'unpaid'
                        CHECK (payment_status IN ('unpaid','held','released','estornado',
                                                  'cash_pending','cash_settled')),
  stripe_payment_intent_id TEXT,
  -- preço calculado SERVER-SIDE (cents) — nunca confiar no cliente
  base_cents            INTEGER NOT NULL DEFAULT 0,
  type_surcharge_cents  INTEGER NOT NULL DEFAULT 0,
  recurring_discount_cents INTEGER NOT NULL DEFAULT 0,               -- valor descontado (positivo)
  products_fee_cents    INTEGER NOT NULL DEFAULT 0,                  -- 100% para a profissional
  total_cents           INTEGER NOT NULL DEFAULT 0,
  cleaner_earnings_cents INTEGER NOT NULL DEFAULT 0,                 -- 85% + produtos
  bora_fee_cents        INTEGER NOT NULL DEFAULT 0,                  -- 15%
  -- cancelamento
  cancelled_at          TIMESTAMPTZ,
  cancelled_by          TEXT CHECK (cancelled_by IN ('client','cleaner','admin')),
  cancel_reason         TEXT,
  cancel_fee_cents      INTEGER NOT NULL DEFAULT 0,
  cancelled_late        BOOLEAN NOT NULL DEFAULT false,              -- profissional <24h (penalização)
  no_show_client        BOOLEAN NOT NULL DEFAULT false,
  -- oferta / rotation (scheduler próprio, SEM dispatch_engine)
  offer_cleaner_id      UUID REFERENCES public.cleaners(id),
  offer_expires_at      TIMESTAMPTZ,
  offered_cleaner_ids   UUID[] NOT NULL DEFAULT '{}',
  -- timestamps de progresso
  accepted_at           TIMESTAMPTZ,
  on_the_way_at         TIMESTAMPTZ,
  started_at            TIMESTAMPTZ,
  done_at               TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  -- lembretes / auto-confirmação
  reminder_24h_sent_at  TIMESTAMPTZ,
  reminder_2h_sent_at   TIMESTAMPTZ,
  is_test_order         BOOLEAN NOT NULL DEFAULT false,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices operacionais
CREATE INDEX IF NOT EXISTS idx_cleaning_bookings_client   ON public.cleaning_bookings (client_user_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_cleaning_bookings_cleaner  ON public.cleaning_bookings (cleaner_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_cleaning_bookings_status   ON public.cleaning_bookings (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_cleaning_bookings_offer    ON public.cleaning_bookings (offer_cleaner_id) WHERE offer_cleaner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cleaning_bookings_group    ON public.cleaning_bookings (recurrence_group_id) WHERE recurrence_group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cleaner_availability_c     ON public.cleaner_availability (cleaner_id, weekday);
CREATE INDEX IF NOT EXISTS idx_cleaners_status            ON public.cleaners (approval_status);

-- updated_at automático
CREATE OR REPLACE FUNCTION public._cleaning_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER trg_cleaners_touch BEFORE UPDATE ON public.cleaners
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_touch_updated_at();

CREATE OR REPLACE TRIGGER trg_cleaning_bookings_touch BEFORE UPDATE ON public.cleaning_bookings
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_touch_updated_at();

-- Realtime para tracking na app (respeita RLS)
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cleaning_bookings;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
