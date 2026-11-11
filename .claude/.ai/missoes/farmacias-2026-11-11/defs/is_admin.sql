CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
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
$function$
;
