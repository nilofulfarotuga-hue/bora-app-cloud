-- BUG 6: partner approval workflow.
-- Adds approval_status to restaurants, RPCs to approve/reject/list pending,
-- and a backfill that approves all non-partner stores (legacy chains visible
-- to clients) while keeping every is_partner=true row 'pending' for manual
-- admin review. Decision (a) confirmed by founder before backfill ran.
--
-- RLS policy filtering clients by approval_status='approved' lives in a
-- separate migration (20260503040000_partners_rls_approved_only.sql) which
-- runs after this one — the order matters so existing policies do not break
-- mid-deploy.

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending','approved','rejected')),
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_restaurants_approval_status
  ON public.restaurants(approval_status);

COMMENT ON COLUMN public.restaurants.approval_status IS
  'BUG 6: pending=awaits admin review (default for new partners); approved=visible to clients; rejected=hidden';
COMMENT ON COLUMN public.restaurants.approved_at IS
  'When admin approved/rejected; NULL while pending';
COMMENT ON COLUMN public.restaurants.approved_by IS
  'Admin user id who took the decision';
COMMENT ON COLUMN public.restaurants.rejection_reason IS
  'Required when approval_status=rejected; shown to partner';

-- Backfill: non-partner chains (Mercadona, Lidl, …) keep visible.
-- Partners (is_partner=true) require manual admin approval.
UPDATE public.restaurants
SET approval_status = 'approved',
    approved_at = now()
WHERE is_partner = false;

UPDATE public.restaurants
SET approval_status = 'pending',
    approved_at = NULL
WHERE is_partner = true;

-- ─── RPCs ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.approve_partner(p_restaurant_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin BOOLEAN := false;
  v_restaurant RECORD;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT email, COALESCE(raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin
  FROM auth.users WHERE id = v_caller;

  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_restaurant FROM public.restaurants WHERE id = p_restaurant_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'restaurant_not_found: %', p_restaurant_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.restaurants
  SET approval_status = 'approved',
      approved_at = now(),
      approved_by = v_caller,
      rejection_reason = NULL
  WHERE id = p_restaurant_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller, v_caller_email, 'partner_approve', 'restaurant', p_restaurant_id,
      jsonb_build_object(
        'restaurant_name', v_restaurant.name,
        'is_partner', v_restaurant.is_partner,
        'previous_status', v_restaurant.approval_status
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'approve_partner audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', p_restaurant_id,
    'approval_status', 'approved',
    'approved_by', v_caller,
    'approved_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_partner(p_restaurant_id text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin BOOLEAN := false;
  v_restaurant RECORD;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'rejection_reason_required' USING ERRCODE = '23514';
  END IF;

  SELECT email, COALESCE(raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin
  FROM auth.users WHERE id = v_caller;

  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_restaurant FROM public.restaurants WHERE id = p_restaurant_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'restaurant_not_found: %', p_restaurant_id USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.restaurants
  SET approval_status = 'rejected',
      approved_at = now(),
      approved_by = v_caller,
      rejection_reason = p_reason
  WHERE id = p_restaurant_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller, v_caller_email, 'partner_reject', 'restaurant', p_restaurant_id,
      jsonb_build_object(
        'restaurant_name', v_restaurant.name,
        'is_partner', v_restaurant.is_partner,
        'previous_status', v_restaurant.approval_status,
        'rejection_reason', p_reason
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'reject_partner audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', p_restaurant_id,
    'approval_status', 'rejected',
    'rejection_reason', p_reason,
    'approved_by', v_caller,
    'approved_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_partners_by_status(p_status text DEFAULT NULL)
RETURNS TABLE(
  id text,
  name text,
  email text,
  phone text,
  address text,
  category text,
  is_partner boolean,
  is_active_admin boolean,
  approval_status text,
  approved_at timestamptz,
  approved_by uuid,
  rejection_reason text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin BOOLEAN := false;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT email, COALESCE(raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin
  FROM auth.users WHERE id = v_caller;

  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT r.id, r.name, r.email, r.phone, r.address, r.category,
           r.is_partner, r.is_active_admin, r.approval_status, r.approved_at,
           r.approved_by, r.rejection_reason, r.created_at
    FROM public.restaurants r
    WHERE p_status IS NULL OR r.approval_status = p_status
    ORDER BY r.created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_partner(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_partner(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_partners_by_status(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_partner(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_partner(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_partners_by_status(text) TO authenticated;
