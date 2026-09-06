-- Sessão 5B-α B2 — RPCs shadow approval flow
-- Scope: 2 actions (UPDATE_DELIVERY_INSTRUCTIONS→customer_notes, UPDATE_DELIVERY_ADDRESS)
-- OTP_RESEND adiado para 5B-β.
-- orders.id é TEXT (legado) — aceitar string sem cast UUID.

-- 1. agent_propose_action (service_role only)
CREATE OR REPLACE FUNCTION public.agent_propose_action(
  p_session_id      uuid,
  p_user_id         uuid,
  p_skill_name      text,
  p_action_type     text,
  p_action_payload  jsonb,
  p_user_message    text DEFAULT NULL,
  p_agent_reasoning text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO support_pending_actions (
    session_id, user_id, skill_name, action_type,
    action_payload, user_message, agent_reasoning
  ) VALUES (
    p_session_id, p_user_id, p_skill_name, p_action_type,
    p_action_payload, p_user_message, p_agent_reasoning
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.agent_propose_action(uuid,uuid,text,text,jsonb,text,text)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.agent_propose_action(uuid,uuid,text,text,jsonb,text,text)
  TO service_role;

-- 2. admin_approve_action
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

        -- skill UPDATE_DELIVERY_INSTRUCTIONS escreve em orders.customer_notes
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
          'rows_affected', v_rows_affected,
          'note', 'skill UPDATE_DELIVERY_INSTRUCTIONS maps to orders.customer_notes column'
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

-- 3. admin_reject_action
CREATE OR REPLACE FUNCTION public.admin_reject_action(
  p_action_id uuid,
  p_reason    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  UPDATE support_pending_actions
  SET status = 'rejected',
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      rejection_reason = p_reason
  WHERE id = p_action_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACTION_NOT_FOUND_OR_NOT_PENDING';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_reject_action(uuid,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_action(uuid,text) TO authenticated;

-- 4. admin_list_pending_actions
CREATE OR REPLACE FUNCTION public.admin_list_pending_actions(
  p_status text DEFAULT 'pending',
  p_limit  int  DEFAULT 50
)
RETURNS TABLE (
  id               uuid,
  skill_name       text,
  action_type      text,
  action_payload   jsonb,
  user_message     text,
  agent_reasoning  text,
  proposed_at      timestamptz,
  reviewed_at      timestamptz,
  executed_at      timestamptz,
  user_email       text,
  status           text,
  execution_result jsonb,
  rejection_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  RETURN QUERY
  SELECT
    a.id, a.skill_name, a.action_type,
    a.action_payload, a.user_message, a.agent_reasoning,
    a.proposed_at, a.reviewed_at, a.executed_at,
    u.email, a.status, a.execution_result, a.rejection_reason
  FROM support_pending_actions a
  LEFT JOIN users u ON u.id = a.user_id
  WHERE (p_status = 'all' OR a.status = p_status)
  ORDER BY a.proposed_at DESC
  LIMIT p_limit;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_pending_actions(text,int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_pending_actions(text,int) TO authenticated;
