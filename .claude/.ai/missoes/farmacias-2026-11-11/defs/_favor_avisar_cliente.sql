CREATE OR REPLACE FUNCTION public._favor_avisar_cliente(p_order_id text, p_titulo text, p_corpo text, p_tocar_segundos integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net'
AS $function$
DECLARE v_user uuid; v_url text; v_key text;
BEGIN
  SELECT user_id INTO v_user FROM public.orders WHERE id = p_order_id;
  IF v_user IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(v_user, 'errand_budget_request', p_titulo, p_corpo, p_order_id);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'sininho cliente: %', SQLERRM; END;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('clientId', v_user, 'orderId', p_order_id, 'status', 'errand_budget_request',
                                   'type', 'errand_budget_request', 'title', p_titulo, 'body', p_corpo,
                                   'ring', COALESCE(p_tocar_segundos, 0) > 0,
                                   'ring_seconds', COALESCE(p_tocar_segundos, 0)));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-client: %', SQLERRM; END;
  END IF;
END $function$
;
