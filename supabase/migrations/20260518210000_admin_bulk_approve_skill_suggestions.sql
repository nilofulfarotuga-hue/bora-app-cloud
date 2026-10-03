CREATE OR REPLACE FUNCTION public.admin_bulk_approve_skill_suggestions(
  p_ids UUID[]
) RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_id UUID;
  v_approved INT := 0;
  v_skipped  INT := 0;
  v_errors   INT := 0;
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') != 'admin' THEN
    RAISE EXCEPTION 'insufficient_privilege';
  END IF;
  FOREACH v_id IN ARRAY p_ids LOOP
    IF EXISTS (
      SELECT 1 FROM public.skill_suggestions
      WHERE id = v_id AND zone_type = 'safe' AND status = 'pending'
    ) THEN
      BEGIN
        PERFORM public.admin_approve_skill_suggestion(v_id);
        v_approved := v_approved + 1;
      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
      END;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'approved', v_approved,
    'skipped_critical', v_skipped,
    'errors', v_errors
  );
END;
$function$;
