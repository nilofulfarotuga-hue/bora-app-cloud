-- BUG 6e: restrict client SELECT on restaurants to approval_status='approved'.
-- Admin bypass via public.is_admin() (SECURITY DEFINER helper that bypasses
-- RLS on auth.users, which anon/authenticated cannot read directly).

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = v_uid
      AND (
        COALESCE(raw_app_meta_data->>'role','') = 'admin'
        OR email IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com')
      )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon;

ALTER POLICY restaurants_public_read ON public.restaurants
  USING (
    approval_status = 'approved'
    OR public.is_admin()
  );

COMMENT ON POLICY restaurants_public_read ON public.restaurants IS
  'BUG 6: clients see approved restaurants only. Admins bypass via public.is_admin().';
