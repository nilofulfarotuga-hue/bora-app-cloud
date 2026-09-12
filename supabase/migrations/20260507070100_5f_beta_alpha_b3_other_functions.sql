-- 5F-β-α B3: Refactor 2 funções 5B-β1 (current_setting → vault)
-- Lógica preservada integralmente — apenas fonte settings muda
-- Aplicado via apply_migration: 5f_beta_alpha_b3_other_functions (2026-05-07)

-- ============================================================
-- B3.1: fn_notify_admin_pending_action (5B-β1)
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_notify_admin_pending_action()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id uuid;
  v_supabase_url text;
  v_service_key text;
BEGIN
  IF NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_supabase_url
  FROM vault.decrypted_secrets WHERE name = 'project_url';

  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT u.id INTO v_admin_id
  FROM users u
  JOIN auth.users au ON au.id = u.id
  WHERE u.fcm_token IS NOT NULL
    AND au.email IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com')
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/notify-client',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'clientId', v_admin_id,
      'title', 'Nova proposta IA',
      'body', NEW.skill_name || ' — abre o Inbox para aprovar/rejeitar'
    )
  );

  RETURN NEW;
END;
$function$;

-- ============================================================
-- B3.2: admin_approve_action (5B-β1) — apenas branch PASSWORD_RESET muda
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_approve_action(p_action_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_action          support_pending_actions;
  v_result          jsonb;
  v_rows_affected   int;
  v_order_id        text;
  v_target_status   text := 'executed';
  v_user_email      text;
  v_new_name        text;
  v_new_phone       text;
  v_updated         jsonb;
  v_dispatch_target text := NULL;
  v_supabase_url    text;
  v_service_key     text;
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

        SELECT decrypted_secret INTO v_supabase_url
        FROM vault.decrypted_secrets WHERE name = 'project_url';

        SELECT decrypted_secret INTO v_service_key
        FROM vault.decrypted_secrets WHERE name = 'service_role_key';

        IF v_supabase_url IS NULL THEN
          RAISE EXCEPTION 'VAULT_NOT_CONFIGURED';
        END IF;

        PERFORM net.http_post(
          url := v_supabase_url ||
            '/functions/v1/support-password-reset',
          headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_service_key,
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
        v_order_id := v_action.action_payload->>'order_id';
        IF v_order_id IS NULL OR length(v_order_id) = 0 THEN
          RAISE EXCEPTION 'INVALID_ORDER_ID';
        END IF;

        v_dispatch_target := 'admin-cancel-order';
        v_result := jsonb_build_object(
          'action', 'EXTERNAL_DISPATCH_REQUIRED',
          'target', 'admin-cancel-order',
          'order_id', v_order_id,
          'note', 'Flutter despacha admin-cancel-order com admin JWT (pré-purchase)'
        );

      WHEN 'CANCEL_DURING_PURCHASE' THEN
        DECLARE
          v_during_order_id text;
          v_during_status   text;
        BEGIN
          v_during_order_id := v_action.action_payload->>'order_id';
          IF v_during_order_id IS NULL OR length(v_during_order_id) = 0 THEN
            RAISE EXCEPTION 'INVALID_ORDER_ID';
          END IF;

          SELECT status INTO v_during_status
          FROM orders
          WHERE id = v_during_order_id
            AND user_id = v_action.user_id;

          IF NOT FOUND THEN
            RAISE EXCEPTION 'ORDER_NOT_FOUND';
          END IF;

          IF v_during_status NOT IN
             ('callingDriver','driverAccepted','pickedUp','onTheWay') THEN
            RAISE EXCEPTION
              'ORDER_NOT_IN_DURING_PURCHASE_STATE — status: %',
              v_during_status;
          END IF;

          v_dispatch_target := 'admin-cancel-order';
          v_result := jsonb_build_object(
            'action', 'EXTERNAL_DISPATCH_REQUIRED',
            'target', 'admin-cancel-order',
            'order_id', v_during_order_id,
            'status_was', v_during_status,
            'note', 'Flutter despacha admin-cancel-order (during-purchase)'
          );
        END;

      WHEN 'RESERVATION_CANCEL' THEN
        DECLARE
          v_reservation_id      uuid;
          v_reservation_status  text;
          v_scheduled_at        timestamptz;
          v_cancel_window_hours int;
          v_prepayment_cents    int;
          v_hours_until         numeric;
        BEGIN
          BEGIN
            v_reservation_id := (v_action.action_payload->>'reservation_id')::uuid;
          EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'INVALID_RESERVATION_ID';
          END;

          SELECT status, reserved_for
            INTO v_reservation_status, v_scheduled_at
          FROM reservations
          WHERE id = v_reservation_id
            AND client_user_id = v_action.user_id;

          IF NOT FOUND THEN
            RAISE EXCEPTION 'RESERVATION_NOT_FOUND';
          END IF;

          IF v_reservation_status NOT IN ('pending','approved') THEN
            RAISE EXCEPTION
              'RESERVATION_NOT_CANCELLABLE — status: %',
              v_reservation_status;
          END IF;

          v_hours_until := EXTRACT(EPOCH FROM (v_scheduled_at - now())) / 3600.0;

          SELECT (value::text)::int INTO v_cancel_window_hours
          FROM platform_settings
          WHERE key = 'reservation_cancel_window_hours';
          v_cancel_window_hours := coalesce(v_cancel_window_hours, 2);

          SELECT (value::text)::int INTO v_prepayment_cents
          FROM platform_settings
          WHERE key = 'reservation_prepayment_cents';
          v_prepayment_cents := coalesce(v_prepayment_cents, 300);

          v_dispatch_target := 'admin-cancel-reservation';
          v_result := jsonb_build_object(
            'action', 'EXTERNAL_DISPATCH_REQUIRED',
            'target', 'admin-cancel-reservation',
            'reservation_id', v_reservation_id,
            'hours_until_scheduled', round(v_hours_until, 2),
            'cancel_window_hours', v_cancel_window_hours,
            'within_refund_window', v_hours_until >= v_cancel_window_hours,
            'expected_refund_cents',
              CASE WHEN v_hours_until >= v_cancel_window_hours
                   THEN v_prepayment_cents
                   ELSE 0 END,
            'note', 'Flutter despacha admin-cancel-reservation'
          );
        END;

      ELSE
        RAISE EXCEPTION 'UNKNOWN_ACTION_TYPE: %', v_action.action_type;
    END CASE;

    IF v_dispatch_target IS NOT NULL THEN
      v_target_status := 'dispatched';
    ELSE
      v_target_status := 'executed';
    END IF;

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
      executed_at = CASE WHEN v_target_status = 'executed'
                         THEN now() ELSE executed_at END,
      execution_result = v_result,
      dispatch_target  = CASE WHEN v_target_status = 'dispatched'
                              THEN v_dispatch_target ELSE dispatch_target END,
      dispatched_at    = CASE WHEN v_target_status = 'dispatched'
                              THEN now() ELSE dispatched_at END
  WHERE id = p_action_id;

  RETURN v_result;
END;
$function$;
