-- =============================================================================
-- BORA APP — Complete Supabase Schema
-- Run this in Supabase SQL Editor (once, on a fresh project).
-- Safe to re-run: uses CREATE TABLE IF NOT EXISTS + ALTER TABLE ADD COLUMN IF NOT EXISTS.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. RESTAURANTS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.restaurants (
  id            TEXT        PRIMARY KEY,
  name          TEXT        NOT NULL DEFAULT '',
  phone         TEXT        NOT NULL DEFAULT '',
  address       TEXT        NOT NULL DEFAULT '',
  email         TEXT        NOT NULL DEFAULT '',
  photo_url     TEXT        NOT NULL DEFAULT '',
  cuisine_type  TEXT        NOT NULL DEFAULT '',
  is_partner    BOOLEAN     NOT NULL DEFAULT FALSE,
  category      TEXT        NOT NULL DEFAULT 'restaurant',
  is_online     BOOLEAN     NOT NULL DEFAULT TRUE,
  lat           FLOAT8,
  lng           FLOAT8
);

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS lat        FLOAT8,
  ADD COLUMN IF NOT EXISTS lng        FLOAT8,
  ADD COLUMN IF NOT EXISTS is_online  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS category   TEXT    NOT NULL DEFAULT 'restaurant',
  ADD COLUMN IF NOT EXISTS cover_url  TEXT;

-- ---------------------------------------------------------------------------
-- 2. PRODUCTS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
  id            TEXT        PRIMARY KEY,
  restaurant_id TEXT        NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name          TEXT        NOT NULL DEFAULT '',
  description   TEXT        NOT NULL DEFAULT '',
  price         FLOAT8      NOT NULL DEFAULT 0,
  photo_url     TEXT        NOT NULL DEFAULT '',
  is_available  BOOLEAN     NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------------
-- 3. DRIVERS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.drivers (
  id            UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name          TEXT        NOT NULL DEFAULT '',
  phone         TEXT        NOT NULL DEFAULT '',
  email         TEXT        NOT NULL DEFAULT '',
  vehicle_type  TEXT        NOT NULL DEFAULT 'motorcycle',
  license_plate TEXT        NOT NULL DEFAULT '',
  is_online     BOOLEAN     NOT NULL DEFAULT FALSE,
  lat           FLOAT8      NOT NULL DEFAULT 38.7223,
  lng           FLOAT8      NOT NULL DEFAULT -9.1393
);

-- ---------------------------------------------------------------------------
-- 4. ORDERS  (primary table — every column toSupabase() sends)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
  -- identity
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id                 UUID        REFERENCES auth.users(id) ON DELETE SET NULL,

  -- status / type
  status                  TEXT        NOT NULL DEFAULT 'created',
  service_type            TEXT        NOT NULL DEFAULT 'storeShopping',
  order_type              TEXT        NOT NULL DEFAULT 'nonPartnerPurchase',

  -- pricing
  price                   FLOAT8      NOT NULL DEFAULT 0,
  subtotal                FLOAT8      NOT NULL DEFAULT 0,
  delivery_fee            FLOAT8      NOT NULL DEFAULT 0,
  service_fee             FLOAT8      NOT NULL DEFAULT 0,
  platform_commission     FLOAT8      NOT NULL DEFAULT 0,
  driver_earnings         FLOAT8      NOT NULL DEFAULT 0,
  distance_km             FLOAT8      NOT NULL DEFAULT 0,
  delivery_price          FLOAT8      NOT NULL DEFAULT 0,

  -- flags
  is_partner_store        BOOLEAN     NOT NULL DEFAULT FALSE,
  apartment_delivery      BOOLEAN     NOT NULL DEFAULT FALSE,

  -- addresses
  vendor_name             TEXT,
  pickup_address          TEXT,
  pickup_street           TEXT,
  pickup_city             TEXT,
  pickup_postal_code      TEXT,
  dropoff_address         TEXT,
  dropoff_street          TEXT,
  dropoff_city            TEXT,
  dropoff_postal_code     TEXT,

  -- customer
  customer_notes          TEXT,
  client_phone            TEXT,
  customer_name           TEXT,

  -- driver assignment
  assigned_driver_id      TEXT,
  current_driver_offer_id TEXT,
  driver_phone            TEXT,
  driver_offer_expires_at TIMESTAMPTZ,
  driver_offer_history    TEXT[]      NOT NULL DEFAULT '{}',

  -- coordinates
  pickup_lat              FLOAT8,
  pickup_lng              FLOAT8,
  dropoff_lat             FLOAT8,
  dropoff_lng             FLOAT8,
  driver_lat              FLOAT8,
  driver_lng              FLOAT8,

  -- payment
  payment_method          TEXT        NOT NULL DEFAULT 'cash',
  payment_status          TEXT        NOT NULL DEFAULT 'pending',
  payment_intent_id       TEXT,
  estimated_total         FLOAT8,
  payment_buffer_total    FLOAT8,
  is_purchase_finalized   BOOLEAN     NOT NULL DEFAULT FALSE,
  final_purchase_value    FLOAT8,
  final_total             FLOAT8,
  refund_amount           FLOAT8,
  extra_charge_amount     FLOAT8,

  -- misc
  substitution_responses  JSONB       NOT NULL DEFAULT '{}',
  requires_car            BOOLEAN     NOT NULL DEFAULT FALSE,
  is_distance_estimated   BOOLEAN     NOT NULL DEFAULT FALSE
);

-- Ensure all columns exist when migrating an existing table.
DO $$
DECLARE col RECORD;
BEGIN
  FOR col IN VALUES
    ('platform_commission',     'FLOAT8      NOT NULL DEFAULT 0'),
    ('driver_earnings',         'FLOAT8      NOT NULL DEFAULT 0'),
    ('delivery_price',          'FLOAT8      NOT NULL DEFAULT 0'),
    ('pickup_street',           'TEXT'),
    ('pickup_city',             'TEXT'),
    ('pickup_postal_code',      'TEXT'),
    ('dropoff_street',          'TEXT'),
    ('dropoff_city',            'TEXT'),
    ('dropoff_postal_code',     'TEXT'),
    ('client_phone',            'TEXT'),
    ('customer_name',           'TEXT'),
    ('driver_offer_history',    'TEXT[] NOT NULL DEFAULT ''{}'''),
    ('pickup_lat',              'FLOAT8'),
    ('pickup_lng',              'FLOAT8'),
    ('dropoff_lat',             'FLOAT8'),
    ('dropoff_lng',             'FLOAT8'),
    ('driver_lat',              'FLOAT8'),
    ('driver_lng',              'FLOAT8'),
    ('payment_status',          'TEXT NOT NULL DEFAULT ''pending'''),
    ('estimated_total',         'FLOAT8'),
    ('payment_buffer_total',    'FLOAT8'),
    ('is_purchase_finalized',   'BOOLEAN NOT NULL DEFAULT FALSE'),
    ('final_purchase_value',    'FLOAT8'),
    ('final_total',             'FLOAT8'),
    ('refund_amount',           'FLOAT8'),
    ('extra_charge_amount',     'FLOAT8'),
    ('substitution_responses',  'JSONB NOT NULL DEFAULT ''{}'''),
    ('requires_car',            'BOOLEAN NOT NULL DEFAULT FALSE'),
    ('is_distance_estimated',   'BOOLEAN NOT NULL DEFAULT FALSE'),
    ('current_driver_offer_id', 'TEXT'),
    ('driver_offer_expires_at', 'TIMESTAMPTZ'),
    ('tried_driver_ids',        'TEXT[] NOT NULL DEFAULT ''{}''')
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name   = 'orders'
        AND column_name  = col.column1
    ) THEN
      EXECUTE format('ALTER TABLE public.orders ADD COLUMN %I %s', col.column1, col.column2);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------

ALTER TABLE public.orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drivers     ENABLE ROW LEVEL SECURITY;

-- Drop old policies if they exist (idempotent)
DROP POLICY IF EXISTS "orders_all_authenticated"        ON public.orders;
DROP POLICY IF EXISTS "restaurants_all_authenticated"   ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_public_read"         ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_auth_write"          ON public.restaurants;
DROP POLICY IF EXISTS "products_all_authenticated"      ON public.products;
DROP POLICY IF EXISTS "products_public_read"            ON public.products;
DROP POLICY IF EXISTS "products_auth_write"             ON public.products;
DROP POLICY IF EXISTS "drivers_all_authenticated"       ON public.drivers;

-- Orders: authenticated only (includes anonymous sign-in).
CREATE POLICY "orders_all_authenticated"
  ON public.orders
  FOR ALL
  USING      (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- Restaurants: public read (any visitor can browse), authenticated write.
-- This prevents the race-condition where the anonymous Supabase session has
-- not been established yet when RestaurantStore._init() first runs.
CREATE POLICY "restaurants_public_read"
  ON public.restaurants
  FOR SELECT
  USING (true);

CREATE POLICY "restaurants_auth_write"
  ON public.restaurants
  FOR ALL
  USING      (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- Products: public read, authenticated write.
CREATE POLICY "products_public_read"
  ON public.products
  FOR SELECT
  USING (true);

CREATE POLICY "products_auth_write"
  ON public.products
  FOR ALL
  USING      (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- Drivers: authenticated only.
CREATE POLICY "drivers_all_authenticated"
  ON public.drivers
  FOR ALL
  USING      (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- ---------------------------------------------------------------------------
-- 5b. MESSAGES  (chat between client and driver per order)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
  id          TEXT        PRIMARY KEY,
  order_id    TEXT        NOT NULL,
  sender_id   TEXT        NOT NULL,
  sender_role TEXT        NOT NULL DEFAULT 'client',
  type        TEXT        NOT NULL DEFAULT 'text',
  content     TEXT        NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotent: add columns that may be missing on existing tables.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS sender_role TEXT NOT NULL DEFAULT 'client',
  ADD COLUMN IF NOT EXISTS type        TEXT NOT NULL DEFAULT 'text';

-- ---------------------------------------------------------------------------
-- 5c. ROW LEVEL SECURITY for messages
-- ---------------------------------------------------------------------------
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_all_authenticated" ON public.messages;

-- Any authenticated session (including anonymous) can read and write messages.
-- Sender identity is validated at the app level, not in the DB policy.
CREATE POLICY "messages_all_authenticated"
  ON public.messages
  FOR ALL
  USING      (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- ---------------------------------------------------------------------------
-- 6. REALTIME  (enable publication for the channels used by the app)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurants;
  EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  EXCEPTION WHEN others THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  EXCEPTION WHEN others THEN NULL; END;
END $$;

-- ---------------------------------------------------------------------------
-- Done. Verify with:
--   SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
-- ---------------------------------------------------------------------------
