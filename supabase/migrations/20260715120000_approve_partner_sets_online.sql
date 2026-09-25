-- BUG: parceiro aprovado ficava sempre "Indisponível" (is_online=false) —
-- register-partner cria com is_online=false e nada o ligava depois da
-- aprovação. approve_partner agora liga is_online=true junto com o approve
-- (loja começa disponível assim que aprovada; admin pode desligar depois
-- via toggle manual no ecrã de gestão do parceiro).

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
      rejection_reason = NULL,
      is_online = true
  WHERE id = p_restaurant_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller, v_caller_email, 'partner_approve', 'restaurant', p_restaurant_id,
      jsonb_build_object(
        'restaurant_name', v_restaurant.name,
        'is_partner', v_restaurant.is_partner,
        'previous_status', v_restaurant.approval_status,
        'is_online_set_true', true
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'approve_partner audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', p_restaurant_id,
    'approval_status', 'approved',
    'is_online', true,
    'approved_by', v_caller,
    'approved_at', now()
  );
END;
$function$;
