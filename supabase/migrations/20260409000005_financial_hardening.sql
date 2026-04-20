-- ============================================================================
-- BORA — Financial System Hardening
-- 1. Admin RPC: server-side JWT claim guard (replaces client-side allowlist)
-- 2. Cash/MBWay: auto-confirm payment_status on delivery (BEFORE trigger)
-- 3. Restaurant ledger user_id: UUID from restaurants table (not vendor_name)
-- 4. RLS: restaurant self-read on ledger + balance snapshot
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Admin RPC — server-side guard
-- ============================================================================
-- Checks auth.jwt() app_metadata.role = 'admin' before returning any data.
-- Set via Supabase dashboard: Auth > Users > {user} > app_metadata > role=admin
-- OR via service-role API: supabase.auth.admin.updateUserById(uid, { app_metadata: { role: 'admin' } })
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_dashboard_metrics()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Server-side authorization: require app_metadata.role = 'admin'
  IF COALESCE(
       (auth.jwt() -> 'app_metadata' ->> 'role'),
       (auth.jwt() ->> 'role')
     ) IS DISTINCT FROM 'admin'
  THEN
    RAISE EXCEPTION 'admin_dashboard_metrics: insufficient privilege'
      USING ERRCODE = 'insufficient_privilege',
            HINT    = 'Set app_metadata.role=admin on this auth user via the service-role API.';
  END IF;

  RETURN json_build_object(
    'platform_revenue', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'platform'
    ),
    'orders_today', (
      SELECT COUNT(*)
      FROM public.orders
      WHERE created_at >= date_trunc('day', now())
    ),
    'drivers_payable', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'driver' AND amount > 0
    ),
    'restaurants_payable', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'restaurant' AND amount > 0
    ),
    'generated_at', now()
  );
END;
$$;

-- Keep grant identical to previous migration — only authenticated can call it,
-- and the function itself enforces the admin claim server-side.
REVOKE ALL ON FUNCTION public.admin_dashboard_metrics() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_metrics() TO authenticated;

COMMENT ON FUNCTION public.admin_dashboard_metrics() IS
  'Admin-only metrics RPC. Server-side guard: auth.jwt() -> app_metadata ->> role must equal ''admin''. Set via service-role API, never client-side.';

-- ============================================================================
-- 2. Cash / MBWay — auto-confirm payment_status BEFORE delivery write
-- ============================================================================
-- Cash: driver collects at the door — payment is confirmed by definition.
-- MBWay: simulated locally — treated as confirmed on delivery.
-- This BEFORE trigger sets payment_status='paid' on NEW before the row is
-- committed, so the AFTER trigger orders_post_to_ledger fires correctly.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_confirm_cod_payment()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.payment_method IN ('cash', 'mbway')
     AND COALESCE(NEW.payment_status, '') IS DISTINCT FROM 'paid'
  THEN
    NEW.payment_status := 'paid';
    RAISE NOTICE 'auto_confirm_cod_payment: order=% method=% → payment_status=paid', NEW.id, NEW.payment_method;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_auto_confirm_cod ON public.orders;
CREATE TRIGGER orders_auto_confirm_cod
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered'
        AND NEW.payment_method IN ('cash', 'mbway'))
  EXECUTE FUNCTION public.auto_confirm_cod_payment();

COMMENT ON FUNCTION public.auto_confirm_cod_payment() IS
  'BEFORE trigger: auto-sets payment_status=paid for cash/mbway orders on delivery. Fires before orders_post_to_ledger so the ledger gate passes.';

-- ============================================================================
-- 3. Restaurant ledger user_id — UUID from restaurants table
-- ============================================================================
-- Replace vendor_name string with the restaurant UUID from public.restaurants.
-- Falls back to vendor_name if no matching row found (prevents data loss).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.post_order_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver           TEXT;
  v_total            NUMERIC(12, 2);
  v_purchase         NUMERIC(12, 2);
  v_base             NUMERIC(12, 2);
  v_driver_earn      NUMERIC(12, 2);
  v_cash_adj         NUMERIC(12, 2);
  v_restaurant_earn  NUMERIC(12, 2);
  v_platform_comm    NUMERIC(12, 2);
  v_vendor_ref       TEXT;
  v_is_partner       BOOLEAN;
  v_is_cash          BOOLEAN;
BEGIN
  -- ── Gates ────────────────────────────────────────────────────────────────
  IF NEW.status IS DISTINCT FROM 'delivered'    THEN RETURN NEW; END IF;
  IF OLD.status = 'delivered'                   THEN RETURN NEW; END IF;
  IF NEW.payment_status IS DISTINCT FROM 'paid' THEN
    RAISE NOTICE 'post_order_to_ledger: order % delivered but payment_status=% — skipping', NEW.id, NEW.payment_status;
    RETURN NEW;
  END IF;

  v_driver     := NEW.assigned_driver_id;
  v_is_partner := COALESCE(NEW.is_partner_store, false);
  v_is_cash    := (NEW.payment_method = 'cash');
  v_total      := ROUND(COALESCE(NEW.final_total, NEW.price, 0)::NUMERIC, 2);
  v_purchase   := ROUND(COALESCE(NEW.final_purchase_value, 0)::NUMERIC, 2);
  v_base       := ROUND(COALESCE(NEW.final_purchase_value, NEW.subtotal, 0)::NUMERIC, 2);

  -- ── Driver: delivery earning ──────────────────────────────────────────────
  v_driver_earn := ROUND(COALESCE(NEW.driver_earnings, 0)::NUMERIC, 2);
  IF v_driver IS NOT NULL AND v_driver_earn > 0 THEN
    INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
    VALUES (v_driver, 'driver', NEW.id::UUID, v_driver_earn, 'earning', 'delivery_earning')
    ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
  END IF;

  -- ── Driver: cash adjustment ───────────────────────────────────────────────
  IF v_driver IS NOT NULL AND v_is_cash THEN
    v_cash_adj := -ROUND(v_total - v_purchase, 2);
    IF v_cash_adj <> 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v_driver, 'driver', NEW.id::UUID, v_cash_adj, 'cash_adjustment', 'cash_adjustment')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  -- ── Restaurant + Platform commission ─────────────────────────────────────
  IF v_is_partner THEN
    -- Resolve stable UUID from restaurants table; fall back to vendor_name
    SELECT id::TEXT INTO v_vendor_ref
    FROM public.restaurants
    WHERE name = COALESCE(NEW.vendor_name, '')
    LIMIT 1;

    IF v_vendor_ref IS NULL THEN
      v_vendor_ref := COALESCE(NEW.vendor_name, 'unknown');
      RAISE NOTICE 'post_order_to_ledger: no restaurant UUID for vendor_name=% — using name as fallback', NEW.vendor_name;
    END IF;

    v_restaurant_earn := ROUND(v_base * 0.90, 2);
    v_platform_comm   := ROUND(v_base - v_restaurant_earn, 2);

    IF v_restaurant_earn > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v_vendor_ref, 'restaurant', NEW.id::UUID, v_restaurant_earn, 'earning', 'partner_share')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;

    IF v_platform_comm > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES ('platform', 'platform', NEW.id::UUID, v_platform_comm, 'commission', 'partner_commission')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  ELSE
    v_platform_comm := ROUND(COALESCE(NEW.platform_commission, 0)::NUMERIC, 2);
    IF v_platform_comm > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES ('platform', 'platform', NEW.id::UUID, v_platform_comm, 'commission', 'service_commission')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  RAISE NOTICE 'post_order_to_ledger: order=% driver=% partner=% cash=% base=% restaurant=%',
    NEW.id, v_driver, v_is_partner, v_is_cash, v_base, v_vendor_ref;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.post_order_to_ledger() IS
  'Posts all financial entries for a delivered+paid order. Restaurant user_id is now the UUID from public.restaurants (falls back to vendor_name). Atomic + idempotent + SECURITY DEFINER.';

-- ============================================================================
-- 4. RLS — restaurant self-read on ledger + balance snapshot
-- ============================================================================
-- Partners authenticate via Supabase Auth (email). The restaurants table has
-- an email column that maps auth.users.email → restaurant id.
-- ============================================================================

-- Ledger: restaurant can read its own earning/payout rows
DROP POLICY IF EXISTS ledger_restaurant_self_read ON public.ledger_entries;
CREATE POLICY ledger_restaurant_self_read ON public.ledger_entries FOR SELECT
  USING (
    user_type = 'restaurant'
    AND user_id = (
      SELECT r.id::TEXT
      FROM public.restaurants r
      JOIN auth.users u ON u.email = r.email
      WHERE u.id = auth.uid()
      LIMIT 1
    )
  );

-- Balance snapshot: restaurant can read its own balance
DROP POLICY IF EXISTS snapshots_restaurant_self_read ON public.user_balance_snapshots;
CREATE POLICY snapshots_restaurant_self_read ON public.user_balance_snapshots FOR SELECT
  USING (
    user_type = 'restaurant'
    AND user_id = (
      SELECT r.id::TEXT
      FROM public.restaurants r
      JOIN auth.users u ON u.email = r.email
      WHERE u.id = auth.uid()
      LIMIT 1
    )
  );

COMMIT;
