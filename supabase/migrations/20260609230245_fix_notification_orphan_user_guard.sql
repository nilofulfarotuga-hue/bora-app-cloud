-- M2 — Notificações NUNCA quebram a transação principal quando o user do pedido
-- foi apagado (FK in_app_notifications.user_id → auth.users.id).
-- Bug confirmado: _notify_on_order_cancel → _push_in_app_notification violava FK
-- ao cancelar pedido de user apagado, abortando a transação inteira do cancel.

-- 1) Guard central no helper único de INSERT.
CREATE OR REPLACE FUNCTION public._push_in_app_notification(
  p_user_id uuid, p_kind text, p_title text,
  p_body text DEFAULT NULL::text, p_related_id text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  -- Guard: user órfão (apagado de auth.users) → no-op silencioso.
  -- A FK real é para auth.users (ON DELETE CASCADE), não public.users.
  IF p_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users au WHERE au.id = p_user_id) THEN
    RETURN NULL;
  END IF;

  INSERT INTO in_app_notifications (user_id, kind, title, body, related_id)
    VALUES (p_user_id, p_kind, p_title, p_body, p_related_id)
    RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  -- Safety net (race com delete-account entre o guard e o INSERT, etc.):
  -- uma notificação falhada nunca pode abortar a transação que a originou.
  RAISE NOTICE '[_push_in_app_notification] skipped for user %: %', p_user_id, SQLERRM;
  RETURN NULL;
END;
$function$;

-- 2) admin_broadcast_notification — INSERT direto: filtrar users órfãos.
CREATE OR REPLACE FUNCTION public.admin_broadcast_notification(
  p_segment text, p_kind text, p_title text, p_body text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_ids    uuid[];
  v_count       int;
  v_fcm_segment text;
BEGIN
  PERFORM public._admin_op_guard();

  CASE p_segment
    WHEN 'all_clients' THEN
      SELECT array_agg(id) INTO v_user_ids FROM users WHERE role = 'client';
      v_fcm_segment := 'clients';
    WHEN 'drivers_online' THEN
      SELECT array_agg(id) INTO v_user_ids FROM drivers WHERE COALESCE(is_online, false);
      v_fcm_segment := 'drivers';
    WHEN 'partners' THEN
      SELECT array_agg(id) INTO v_user_ids FROM users WHERE role = 'partner';
      v_fcm_segment := 'partners';
    WHEN 'all_users' THEN
      SELECT array_agg(id) INTO v_user_ids FROM users WHERE role IN ('client','partner');
      v_fcm_segment := 'all';
    WHEN 'recent_clients_30d' THEN
      SELECT array_agg(DISTINCT user_id) INTO v_user_ids FROM orders
       WHERE created_at > NOW() - INTERVAL '30 days' AND user_id IS NOT NULL;
      v_fcm_segment := 'clients';
    ELSE
      RAISE EXCEPTION 'invalid_segment: %', p_segment;
  END CASE;

  -- 1. In-app notification (sininho)
  IF v_user_ids IS NOT NULL AND array_length(v_user_ids, 1) IS NOT NULL THEN
    INSERT INTO in_app_notifications (user_id, kind, title, body)
      SELECT u, p_kind, p_title, p_body FROM unnest(v_user_ids) AS u
      WHERE EXISTS (SELECT 1 FROM auth.users au WHERE au.id = u);  -- guard órfãos
    GET DIAGNOSTICS v_count = ROW_COUNT;
  ELSE
    v_count := 0;
  END IF;

  -- 2. Fila FCM — execute-broadcast cron processa em <2 min
  INSERT INTO push_broadcasts (segment, title, body, status, created_by)
  VALUES (v_fcm_segment, p_title, p_body, 'pending', auth.uid());

  PERFORM log_admin_action('broadcast_notification', 'segment', p_segment,
    jsonb_build_object('kind', p_kind, 'title', p_title, 'in_app_count', v_count));

  RETURN v_count;
END;
$function$;

-- 3) admin_save_broadcast_in_app — INSERT direto: filtrar users órfãos.
CREATE OR REPLACE FUNCTION public.admin_save_broadcast_in_app(
  p_segment text, p_kind text, p_title text, p_body text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_ids uuid[];
  v_count    int := 0;
BEGIN
  PERFORM public._admin_op_guard();

  CASE p_segment
    WHEN 'all_clients' THEN
      SELECT array_agg(DISTINCT cpt.user_id) INTO v_user_ids
      FROM client_push_tokens cpt WHERE cpt.active = true;

    WHEN 'recent_clients_30d' THEN
      SELECT array_agg(DISTINCT o.user_id) INTO v_user_ids
      FROM orders o
      WHERE o.created_at > NOW() - INTERVAL '30 days'
        AND o.user_id IS NOT NULL;

    WHEN 'drivers_online' THEN
      SELECT array_agg(DISTINCT dpt.user_id) INTO v_user_ids
      FROM driver_push_tokens dpt WHERE dpt.active = true;

    WHEN 'partners' THEN
      SELECT array_agg(DISTINCT r.user_id) INTO v_user_ids
      FROM restaurants r
      WHERE r.user_id IS NOT NULL AND r.is_active_admin = true;

    WHEN 'all_users' THEN
      SELECT array_agg(DISTINCT uid) INTO v_user_ids FROM (
        SELECT cpt.user_id AS uid FROM client_push_tokens cpt WHERE cpt.active = true
        UNION
        SELECT dpt.user_id AS uid FROM driver_push_tokens dpt WHERE dpt.active = true
        UNION
        SELECT r.user_id AS uid FROM restaurants r WHERE r.user_id IS NOT NULL
      ) t;

    ELSE
      RETURN 0;
  END CASE;

  IF v_user_ids IS NULL OR array_length(v_user_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  INSERT INTO in_app_notifications (user_id, kind, title, body)
    SELECT u, p_kind, p_title, p_body FROM unnest(v_user_ids) AS u
    WHERE EXISTS (SELECT 1 FROM auth.users au WHERE au.id = u);  -- guard órfãos
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_count;
END;
$function$;
