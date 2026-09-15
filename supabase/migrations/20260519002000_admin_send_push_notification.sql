-- Add admin_send_push_notification RPC
-- Calls FCM Edge Functions + in-app notification

CREATE OR REPLACE FUNCTION public.admin_send_push_notification(
  p_recipient_type text,
  p_recipient_id uuid,
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'net', 'vault'
AS $fn$
DECLARE
  v_url text;
  v_key text;
  v_fcm_token text;
  v_restaurant_id uuid;
  v_function_name text;
  v_payload jsonb;
BEGIN
  -- Guard: only admins can call
  PERFORM public._admin_op_guard();

  -- Get secrets from vault
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';

  -- Always save in-app notification
  PERFORM public._push_in_app_notification(
    p_recipient_id,
    'admin_push',
    p_title,
    p_body,
    NULL
  );

  -- Route to correct Edge Function based on recipient type
  IF p_recipient_type = 'client' THEN
    v_function_name := 'notify-client';
    SELECT fcm_token INTO v_fcm_token
    FROM public.client_push_tokens
    WHERE user_id = p_recipient_id AND active = true
    ORDER BY last_used_at DESC NULLS LAST LIMIT 1;

    v_payload := jsonb_build_object(
      'userId', p_recipient_id,
      'title', p_title,
      'body', p_body,
      'type', 'admin_message'
    );

  ELSIF p_recipient_type = 'driver' THEN
    v_function_name := 'notify-driver';
    SELECT fcm_token INTO v_fcm_token
    FROM public.driver_push_tokens
    WHERE user_id = p_recipient_id AND active = true
    ORDER BY last_used_at DESC NULLS LAST LIMIT 1;

    v_payload := jsonb_build_object(
      'driverId', p_recipient_id,
      'title', p_title,
      'body', p_body,
      'type', 'admin_message'
    );

  ELSIF p_recipient_type = 'partner' THEN
    v_function_name := 'notify-partner';
    -- Partner: get restaurant_id and fcm_token
    SELECT id, fcm_token INTO v_restaurant_id, v_fcm_token
    FROM public.restaurants
    WHERE user_ = p_recipient_id AND fcm_token IS NOT NULL
    LIMIT 1;

    v_payload := jsonb_build_object(
      'restaurantId', v_restaurant_id,
      'orderId', '00000000-0000-0000-0000-000000000000'::uuid,
      'customTitle', p_title,
      'customBody', p_body,
      'kind', 'admin_message'
    );
  END IF;

  -- Call Edge Function if we have a token
  IF v_url IS NOT NULL AND v_key IS NOT NULL AND v_fcm_token IS NOT NULL THEN
    PERFORM net.http_post(
      url := v_url || '/functions/v1/' || v_function_name,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_key,
        'Content-Type', 'application/json'
      ),
      body := v_payload::text
    );
  END IF;

  -- Log admin action
  PERFORM public.log_admin_action(
    'send_push_notification',
    'user',
    p_recipient_id::text,
    jsonb_build_object(
      'type', p_recipient_type,
      'title', p_title,
      'fcm_sent', v_fcm_token IS NOT NULL
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'fcm_token_found', v_fcm_token IS NOT NULL,
    'function_called', v_function_name,
    'in_app_saved', true
  );
END;
$fn$;

COMMENT ON FUNCTION public.admin_send_push_notification IS 'Admin: send push FCM + in-app notification to single user (client/driver/partner).';
