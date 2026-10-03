-- =====================================================================
-- CARWASH ENGINE - Lavagem Auto (Bora App)  |  2026-08-27
-- Clona o motor da Limpeza (cleaning_*) para carwash_* / washers.
-- NAO toca em NADA cleaning_*. NAO toca em zonas protegidas.
-- Chave de identidade do lavador: SEMPRE user_id (licao Valdemir 16/08).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. washers  (espelho de cleaners)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.washers (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  name               text NOT NULL DEFAULT '',
  phone              text NOT NULL DEFAULT '',
  email              text NOT NULL DEFAULT '',
  photo_url          text NOT NULL DEFAULT '',
  bio                text NOT NULL DEFAULT '',
  nif                text NOT NULL DEFAULT '',
  docs               jsonb NOT NULL DEFAULT '{}'::jsonb,
  base_lat           double precision,
  base_lng           double precision,
  base_address       text NOT NULL DEFAULT '',
  service_radius_km  numeric NOT NULL DEFAULT 8,
  approval_status    text NOT NULL DEFAULT 'pending'
                     CHECK (approval_status IN ('pending','approved','rejected','suspended')),
  approved_at        timestamptz,
  approved_by        uuid,
  rejection_reason   text,
  is_active          boolean NOT NULL DEFAULT true,
  is_banned          boolean NOT NULL DEFAULT false,
  ban_reason         text,
  banned_at          timestamptz,
  rating_avg         numeric NOT NULL DEFAULT 0,
  ratings_count      integer NOT NULL DEFAULT 0,
  washes_done        integer NOT NULL DEFAULT 0,
  flagged_low_rating boolean NOT NULL DEFAULT false,
  mbway_phone        text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_washers_user_id ON public.washers(user_id);
CREATE INDEX IF NOT EXISTS idx_washers_active  ON public.washers(approval_status, is_active) WHERE is_active;

-- ---------------------------------------------------------------------
-- 2. washer_availability  (espelho de cleaner_availability)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.washer_availability (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  washer_id  uuid NOT NULL REFERENCES public.washers(id) ON DELETE CASCADE,
  weekday    smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time   time NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_washer_avail_washer ON public.washer_availability(washer_id, weekday);

-- ---------------------------------------------------------------------
-- 3. carwash_bookings  (espelho de cleaning_bookings, adaptado ao carro)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.carwash_bookings (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id        uuid NOT NULL,
  washer_id             uuid REFERENCES public.washers(id) ON DELETE SET NULL,
  requested_washer_id   uuid REFERENCES public.washers(id) ON DELETE SET NULL,

  service_type          text NOT NULL CHECK (service_type IN ('exterior','full','interior')),

  plate                 text NOT NULL,
  car_make_model        text NOT NULL DEFAULT '',
  car_color             text NOT NULL DEFAULT '',
  pickup_notes          text NOT NULL DEFAULT '',
  client_phone          text NOT NULL,

  when_mode             text NOT NULL DEFAULT 'now' CHECK (when_mode IN ('now','later')),
  scheduled_at          timestamptz NOT NULL,
  duration_min          integer NOT NULL DEFAULT 60,
  eta_minutes           integer,
  eta_at                timestamptz,

  address_street        text NOT NULL DEFAULT '',
  address_city          text NOT NULL DEFAULT '',
  address_postal        text NOT NULL DEFAULT '',
  lat                   double precision,
  lng                   double precision,
  notes                 text NOT NULL DEFAULT '',

  status                text NOT NULL DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled','accepted','on_the_way','picked_up',
                                          'in_progress','delivering','delivered','completed',
                                          'cancelled_client')),

  payment_method        text NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('card','mbway','cash')),
  payment_status        text NOT NULL DEFAULT 'unpaid',
  stripe_payment_intent_id text,
  base_cents            integer NOT NULL DEFAULT 0,
  total_cents           integer NOT NULL DEFAULT 0,
  washer_earnings_cents integer NOT NULL DEFAULT 0,
  bora_fee_cents        integer NOT NULL DEFAULT 0,

  photos_client         jsonb NOT NULL DEFAULT '[]'::jsonb,
  photos_before         jsonb NOT NULL DEFAULT '[]'::jsonb,
  photos_after          jsonb NOT NULL DEFAULT '[]'::jsonb,

  offer_washer_id       uuid REFERENCES public.washers(id) ON DELETE SET NULL,
  offer_expires_at      timestamptz,
  offered_washer_ids    uuid[] NOT NULL DEFAULT '{}'::uuid[],

  accepted_at           timestamptz,
  on_the_way_at         timestamptz,
  picked_up_at          timestamptz,
  started_at            timestamptz,
  delivering_at         timestamptz,
  delivered_at          timestamptz,
  done_at               timestamptz,
  completed_at          timestamptz,

  cancelled_at          timestamptz,
  cancelled_by          text,
  cancel_reason         text,
  cancel_fee_cents      integer NOT NULL DEFAULT 0,
  cancelled_late        boolean NOT NULL DEFAULT false,
  no_show_client        boolean NOT NULL DEFAULT false,

  rating                integer CHECK (rating BETWEEN 1 AND 5),
  rating_comment        text,

  reminder_2h_sent_at   timestamptz,
  stuck_alerted_at      timestamptz,
  is_test_order         boolean NOT NULL DEFAULT false,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_carwash_client ON public.carwash_bookings(client_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_carwash_washer ON public.carwash_bookings(washer_id, status);
CREATE INDEX IF NOT EXISTS idx_carwash_offer  ON public.carwash_bookings(offer_washer_id) WHERE offer_washer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_carwash_status ON public.carwash_bookings(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_carwash_plate  ON public.carwash_bookings(plate);

-- ---------------------------------------------------------------------
-- 4. carwash_messages  (espelho de cleaning_messages)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.carwash_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  uuid NOT NULL REFERENCES public.carwash_bookings(id) ON DELETE CASCADE,
  sender_role text NOT NULL CHECK (sender_role IN ('client','washer')),
  message     text NOT NULL,
  read        boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_carwash_msg_booking ON public.carwash_messages(booking_id, created_at);

-- ---------------------------------------------------------------------
-- 5. washer_weekly_settlements
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.washer_weekly_settlements (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  washer_id            uuid NOT NULL REFERENCES public.washers(id) ON DELETE CASCADE,
  week_start_at        timestamptz NOT NULL,
  week_end_at          timestamptz NOT NULL,
  total_jobs           integer NOT NULL DEFAULT 0,
  total_earnings_cents integer NOT NULL DEFAULT 0,
  total_bora_fee_cents integer NOT NULL DEFAULT 0,
  net_payout_cents     integer NOT NULL DEFAULT 0,
  direction            text NOT NULL DEFAULT 'bora_to_washer',
  status               text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','cancelled')),
  payment_method       text,
  payment_reference    text,
  paid_at              timestamptz,
  paid_by              uuid,
  notes                text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (washer_id, week_start_at)
);

-- ---------------------------------------------------------------------
-- 6. washer_cancel_events
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.washer_cancel_events (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  washer_id  uuid NOT NULL REFERENCES public.washers(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES public.carwash_bookings(id) ON DELETE SET NULL,
  was_late   boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- RLS - TODAS as tabelas. Chave do lavador = user_id (SEMPRE).
-- Helper partilhado garante que SELECT e UPDATE usam a MESMA chave.
-- =====================================================================
CREATE OR REPLACE FUNCTION public._carwash_my_washer_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT id FROM public.washers WHERE user_id = auth.uid() LIMIT 1;
$fn$;

ALTER TABLE public.washers                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.washer_availability       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carwash_bookings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carwash_messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.washer_weekly_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.washer_cancel_events      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS washers_select_own ON public.washers;
CREATE POLICY washers_select_own ON public.washers FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS washers_update_own ON public.washers;
CREATE POLICY washers_update_own ON public.washers FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS washers_admin_all ON public.washers;
CREATE POLICY washers_admin_all ON public.washers FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS washer_avail_own ON public.washer_availability;
CREATE POLICY washer_avail_own ON public.washer_availability FOR ALL TO authenticated
  USING (washer_id = public._carwash_my_washer_id() OR public.is_admin())
  WITH CHECK (washer_id = public._carwash_my_washer_id() OR public.is_admin());

DROP POLICY IF EXISTS carwash_bookings_select_own ON public.carwash_bookings;
CREATE POLICY carwash_bookings_select_own ON public.carwash_bookings FOR SELECT TO authenticated
  USING (
    client_user_id = auth.uid()
    OR washer_id       = public._carwash_my_washer_id()
    OR offer_washer_id = public._carwash_my_washer_id()
    OR public.is_admin()
  );
DROP POLICY IF EXISTS carwash_bookings_update_own ON public.carwash_bookings;
CREATE POLICY carwash_bookings_update_own ON public.carwash_bookings FOR UPDATE TO authenticated
  USING (
    client_user_id = auth.uid()
    OR washer_id       = public._carwash_my_washer_id()
    OR offer_washer_id = public._carwash_my_washer_id()
    OR public.is_admin()
  )
  WITH CHECK (
    client_user_id = auth.uid()
    OR washer_id       = public._carwash_my_washer_id()
    OR offer_washer_id = public._carwash_my_washer_id()
    OR public.is_admin()
  );
DROP POLICY IF EXISTS carwash_bookings_admin_all ON public.carwash_bookings;
CREATE POLICY carwash_bookings_admin_all ON public.carwash_bookings FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS carwash_messages_select_participant ON public.carwash_messages;
CREATE POLICY carwash_messages_select_participant ON public.carwash_messages FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.carwash_bookings b
    WHERE b.id = carwash_messages.booking_id
      AND (b.client_user_id = auth.uid()
           OR b.washer_id = public._carwash_my_washer_id()
           OR public.is_admin())
  ));
DROP POLICY IF EXISTS carwash_messages_insert_participant ON public.carwash_messages;
CREATE POLICY carwash_messages_insert_participant ON public.carwash_messages FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.carwash_bookings b
    WHERE b.id = carwash_messages.booking_id
      AND b.status IN ('accepted','on_the_way','picked_up','in_progress','delivering','delivered')
      AND ((carwash_messages.sender_role = 'client' AND b.client_user_id = auth.uid())
        OR (carwash_messages.sender_role = 'washer' AND b.washer_id = public._carwash_my_washer_id()))
  ));

DROP POLICY IF EXISTS wws_select ON public.washer_weekly_settlements;
CREATE POLICY wws_select ON public.washer_weekly_settlements FOR SELECT TO authenticated
  USING (washer_id = public._carwash_my_washer_id() OR public.is_admin());
DROP POLICY IF EXISTS wws_write ON public.washer_weekly_settlements;
CREATE POLICY wws_write ON public.washer_weekly_settlements FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS wce_select ON public.washer_cancel_events;
CREATE POLICY wce_select ON public.washer_cancel_events FOR SELECT TO authenticated
  USING (washer_id = public._carwash_my_washer_id() OR public.is_admin());
DROP POLICY IF EXISTS wce_write ON public.washer_cancel_events;
CREATE POLICY wce_write ON public.washer_cancel_events FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- updated_at
CREATE OR REPLACE FUNCTION public._carwash_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN NEW.updated_at := now(); RETURN NEW; END $fn$;

DROP TRIGGER IF EXISTS trg_carwash_bookings_touch ON public.carwash_bookings;
CREATE TRIGGER trg_carwash_bookings_touch BEFORE UPDATE ON public.carwash_bookings
  FOR EACH ROW EXECUTE FUNCTION public._carwash_touch_updated_at();
DROP TRIGGER IF EXISTS trg_washers_touch ON public.washers;
CREATE TRIGGER trg_washers_touch BEFORE UPDATE ON public.washers
  FOR EACH ROW EXECUTE FUNCTION public._carwash_touch_updated_at();
