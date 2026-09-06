-- T4 (2026-05-20) — Bulk-insert in_app_notifications when admin broadcasts.
-- Before this migration admin_broadcast_notification only sent FCM.
-- Flutter calls admin_save_broadcast_in_app right after the broadcast so
-- the bell shows unread for all recipients even without FCM token.

CREATE OR REPLACE FUNCTION public.admin_save_broadcast_in_app(
  p_segment  text,
  p_kind     text,
  p_title    text,
  p_body     text DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_count int := 0;
BEGIN
  PERFORM public._admin_op_guard();

  IF p_segment IN ('all_clients', 'recent_clients_30d') THEN
    INSERT INTO public.in_app_notifications (user_id, kind, title, body)
    SELECT DISTINCT user_id, p_kind, p_title, p_body
    FROM public.client_push_tokens
    WHERE active = true;

  ELSIF p_segment = 'drivers_online' THEN
    INSERT INTO public.in_app_notifications (user_id, kind, title, body)
    SELECT DISTINCT user_id, p_kind, p_title, p_body
    FROM public.driver_push_tokens
    WHERE active = true;

  ELSIF p_segment = 'partners' THEN
    INSERT INTO public.in_app_notifications (user_id, kind, title, body)
    SELECT DISTINCT user_, p_kind, p_title, p_body
    FROM public.restaurants
    WHERE user_ IS NOT NULL;
  END IF;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_save_broadcast_in_app(text, text, text, text)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_broadcast_in_app(text, text, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.admin_save_broadcast_in_app IS
  'T4 2026-05-20 — Bulk in-app notifications for broadcast segment. Called by Flutter after admin_broadcast_notification.';
