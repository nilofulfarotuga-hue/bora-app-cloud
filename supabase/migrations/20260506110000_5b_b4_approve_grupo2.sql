-- Sessão 5B-β1 B1 — Extend admin_approve_action with Grupo 2 + admin_finalize_action
-- Scope: ACCOUNT_UPDATE (UPDATE users.name/phone), PASSWORD_RESET (pg_net), CANCEL_PRE_PURCHASE (EXTERNAL_DISPATCH stub)

CREATE OR REPLACE FUNCTION public.admin_approve_action(
  p_action_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action        support_pending_actions;
  v_result        jsonb;
  v_rows_affected int;
  v_order_id      text;
  v_target_status text := 'executed';
  v_user_email    text;
  v_new_name      text;
  v_new_phone     text;
  v_updated       jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  SELECT * INTO v_action
  FROM support_pending_actions
  WHERE id = p_action_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACTION_NOT_FOUND_OR_NOT_PENDING';
  END IF;

  BEGIN
    CASE v_action.action_type

      WHEN 'UPDATE_DELIVERY_INSTRUCTIONS' THEN
        v_order_id := v_action.action_payload->>'order_id';
        IF v_order_id IS NULL OR length(v_order_id) = 0 THEN
          RAISE EXCEPTION 'INVALID_ORDER_ID';
        END IF;
        IF length(coalesce(v_action.action_payload->>'new_value','')) = 0 THEN
          RAISE EXCEPTION 'EMPTY_NEW_VALUE';
        END IF;
        IF length(v_action.action_payload->>'new_value') > 200 THEN
          RAISE EXCEPTION 'NEW_VALUE_TOO_LONG';
        END IF;

        UPDATE orders
        SET customer_notes = v_action.action_payload->>'new_value'
        WHERE id = v_order_id
          AND user_id = v_action.user_id
          AND status NOT IN ('delivered','cancelled','pickedUp','onTheWay');

        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        IF v_rows_affected = 0 THEN
          RAISE EXCEPTION 'NO_ROWS_AFFECTED — order not found or status incompatible';
        END IF;

        v_result := jsonb_build_object(
          'updated', 'customer_notes',
          'order_id', v_order_id,
          'rows_affected', v_rows_affected
        );

      WHEN 'UPDATE_DELIVERY_ADDRESS' THEN
        v_order_id := v_action.action_payload->>'order_id';
        IF v_order_id IS NULL OR length(v_order_id) = 0 THEN
          RAISE EXCEPTION 'INVALID_ORDER_ID';
        END IF;
        IF length(coalesce(v_action.action_payload->>'new_address','')) = 0 THEN
          RAISE EXCEPTION 'EMPTY_NEW_ADDRESS';
        END IF;

        UPDATE orders
        SET dropoff_address = v_action.action_payload->>'new_address',
            dropoff_lat = NULL,
            dropoff_lng = NULL
        WHERE id = v_order_id
          AND user_id = v_action.user_id
          AND status IN ('created','preparing');

        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        IF v_rows_affected = 0 THEN
          RAISE EXCEPTION 'NO_ROWS_AFFECTED — order may already be dispatched';
        END IF;

        v_result := jsonb_build_object(
          'updated', 'dropoff_address',
          'order_id', v_order_id,
          'rows_affected', v_rows_affected,
          'note', 'coords reset to NULL; will re-geocode on next dispatch'
        );

      WHEN 'ACCOUNT_UPDATE' THEN
        IF v_action.action_payload ? 'email' OR
           v_action.action_payload ? 'password' OR
           v_action.action_payload ? 'role' OR
           v_action.action_payload ? 'wallet' OR
           v_action.action_payload ? 'tokens' OR
           v_action.action_payload ? 'fcm_token' THEN
          RAISE EXCEPTION 'FORBIDDEN_FIELD — only name and phone allowed';
        END IF;

        v_new_name  := v_action.action_payload->>'name';
        v_new_phone := v_action.action_payload->>'phone';

        IF v_new_name IS NULL THEN
          v_new_name := v_action.action_payload->>'full_name';
        END IF;

        IF v_new_name IS NULL AND v_new_phone IS NULL THEN
          RAISE EXCEPTION 'NOTHING_TO_UPDATE';
        END IF;

        IF v_new_name IS NOT NULL THEN
          IF length(trim(v_new_name)) < 2 THEN
            RAISE EXCEPTION 'NAME_TOO_SHORT';
          END IF;
          IF length(v_new_name) > 100 THEN
            RAISE EXCEPTION 'NAME_TOO_LONG';
          END IF;
        END IF;

        IF v_new_phone IS NOT NULL AND
           v_new_phone !~ '^\+?[1-9][0-9]{6,14}$' THEN
          RAISE EXCEPTION 'INVALID_PHONE_FORMAT';
        END IF;

        UPDATE users
        SET
          name  = coalesce(v_new_name,  name),
          phone = coalesce(v_new_phone, phone)
        WHERE id = v_action.user_id;

        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        IF v_rows_affected = 0 THEN
          RAISE EXCEPTION 'USER_NOT_FOUND';
        END IF;

        v_updated := '{}'::jsonb;
        IF v_new_name IS NOT NULL THEN
          v_updated := v_updated || jsonb_build_object('name', true);
        END IF;
        IF v_new_phone IS NOT NULL THEN
          v_updated := v_updated || jsonb_build_object('phone', true);
        END IF;

        v_result := jsonb_build_object(
          'updated', v_updated,
          'user_id', v_action.user_id
        );

      WHEN 'PASSWORD_RESET' THEN
        SELECT email INTO v_user_email
        FROM auth.users WHERE id = v_action.user_id;

        IF v_user_email IS NULL OR length(v_user_email) = 0 THEN
          RAISE EXCEPTION 'USER_EMAIL_NOT_FOUND';
        END IF;

        IF current_setting('app.supabase_url', true) IS NULL THEN
          RAISE EXCEPTION 'PG_NET_NOT_CONFIGURED';
        END IF;

        PERFORM net.http_post(
          url := current_setting('app.supabase_url') ||
            '/functions/v1/support-password-reset',
          headers := jsonb_build_object(
            'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
            'Content-Type', 'application/json'
          ),
          body := jsonb_build_object(
            'user_id', v_action.user_id,
            'email', v_user_email
          )
        );

        v_result := jsonb_build_object(
          'reset_triggered', true,
          'email_partial', substring(v_user_email FROM 1 FOR 3) || '***',
          'note', 'fire-and-forget; email em 1-2min via Supabase Auth'
        );

      WHEN 'CANCEL_PRE_PURCHASE' THEN
        -- Stub: Flutter AdminPendingActionsScreen DEVE detectar este action_type
        -- e despachar para admin-cancel-order Edge Fn (com admin JWT) em vez de
        -- chamar admin_approve_action. Após sucesso, chama admin_finalize_action.
        RAISE EXCEPTION 'EXTERNAL_DISPATCH_REQUIRED — call admin-cancel-order Edge Fn then admin_finalize_action';

      ELSE
        RAISE EXCEPTION 'UNKNOWN_ACTION_TYPE: %', v_action.action_type;
    END CASE;

    v_target_status := 'executed';

  EXCEPTION WHEN OTHERS THEN
    v_target_status := 'failed';
    v_result := jsonb_build_object(
      'error', SQLERRM,
      'sqlstate', SQLSTATE
    );
  END;

  UPDATE support_pending_actions
  SET status = v_target_status,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      executed_at = now(),
      execution_result = v_result
  WHERE id = p_action_id;

  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_approve_action(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_action(uuid) TO authenticated;

-- admin_finalize_action: usado pelo Flutter para CANCEL_PRE_PURCHASE
-- após dispatch externo (admin-cancel-order Edge Fn).
CREATE OR REPLACE FUNCTION public.admin_finalize_action(
  p_action_id uuid,
  p_status    text,
  p_result    jsonb DEFAULT '{}'::jsonb,
  p_reason    text  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_action support_pending_actions;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  IF p_status NOT IN ('executed','failed','rejected') THEN
    RAISE EXCEPTION 'INVALID_STATUS — must be executed/failed/rejected';
  END IF;

  SELECT * INTO v_action
  FROM support_pending_actions
  WHERE id = p_action_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACTION_NOT_FOUND_OR_NOT_PENDING';
  END IF;

  UPDATE support_pending_actions
  SET status = p_status,
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      executed_at = CASE WHEN p_status = 'executed' THEN now() ELSE executed_at END,
      execution_result = p_result,
      rejection_reason = p_reason
  WHERE id = p_action_id;

  RETURN jsonb_build_object('finalized', true, 'status', p_status);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_finalize_action(uuid,text,jsonb,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_finalize_action(uuid,text,jsonb,text) TO authenticated;
