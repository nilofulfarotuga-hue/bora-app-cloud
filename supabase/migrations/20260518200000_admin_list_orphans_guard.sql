-- Defence-in-depth guard for admin_list_orphans
-- Previously only had GRANT TO service_role (no body-level auth check).
-- Flutter admin panel uses authenticated JWT — this guard ensures only
-- app_metadata.role='admin' users can invoke it even if grant is widened.
-- Idempotent: CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.admin_list_orphans()
  RETURNS TABLE(
    kind TEXT,
    id TEXT,
    user_id UUID,
    payment_intent_id TEXT,
    amount NUMERIC,
    age_minutes NUMERIC,
    notes TEXT
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') != 'admin' THEN
    RAISE EXCEPTION 'insufficient_privilege';
  END IF;

  RETURN QUERY
    -- Drafts pendentes (sem order ainda)
    SELECT 'payment_draft'::TEXT AS kind,
           pd.id::TEXT,
           pd.user_id,
           pd.payment_intent_id,
           (pd.amount_cents / 100.0)::NUMERIC AS amount,
           EXTRACT(EPOCH FROM (NOW() - pd.created_at)) / 60 AS age_minutes,
           CASE
             WHEN pd.expires_at < NOW() THEN 'expired'
             WHEN pd.used_at IS NOT NULL THEN 'used'
             ELSE 'pending'
           END AS notes
    FROM public.payment_drafts pd
    WHERE pd.used_at IS NULL
    UNION ALL
    -- Orders cancelled_no_charge (BUG 3 marcadas)
    SELECT 'order_no_charge'::TEXT AS kind,
           o.id,
           o.user_id::UUID,
           o.payment_intent_id,
           o.total::NUMERIC AS amount,
           EXTRACT(EPOCH FROM (NOW() - o.created_at)) / 60 AS age_minutes,
           COALESCE(o.cancel_reason, 'unknown') AS notes
    FROM public.orders o
    WHERE o.payment_status = 'cancelled_no_charge'
    ORDER BY age_minutes DESC
    LIMIT 100;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_list_orphans() TO service_role;
