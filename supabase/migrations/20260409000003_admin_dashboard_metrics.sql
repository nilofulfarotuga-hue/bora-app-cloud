-- ============================================================================
-- BORA — Admin Dashboard Metrics (read-only RPC)
-- ============================================================================
-- Returns aggregated read-only metrics for the in-app admin dashboard.
-- SECURITY DEFINER so it can read ledger_entries (which has no broad SELECT
-- policy). It only ever returns aggregates — never individual rows.
--
-- TEMPORARY: access is gated on the CLIENT (email allowlist) until a real
-- admin role is introduced. Replace this with `auth.jwt() ->> 'role' = 'admin'`
-- once the admin role exists.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_dashboard_metrics()
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
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
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_metrics() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_metrics() TO authenticated;

COMMENT ON FUNCTION public.admin_dashboard_metrics() IS
  'Aggregated read-only metrics for the in-app admin dashboard. Returns only aggregates, never row-level data. Client-side email allowlist is the temporary access gate.';

COMMIT;
