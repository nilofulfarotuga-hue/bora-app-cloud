-- ============================================================================
-- BORA — Cancellation Requests (Feature 4)
-- ============================================================================
-- Driver/partner pedem cancelamento → admin aprova/rejeita com refund_method.
-- Cliente continua a poder cancelar directamente via cancel-order-with-choice.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.cancellation_requests (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           TEXT NOT NULL,
  requester_role     TEXT NOT NULL CHECK (requester_role IN ('driver','partner','client')),
  requester_id       UUID NOT NULL REFERENCES auth.users(id),
  reason             TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','approved','rejected','withdrawn')),
  reviewed_by_admin  UUID REFERENCES auth.users(id),
  reviewed_at        TIMESTAMPTZ,
  refund_method      TEXT CHECK (refund_method IN ('stripe','wallet','none')),
  rejection_reason   TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cancel_req_status_created
  ON public.cancellation_requests (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cancel_req_order
  ON public.cancellation_requests (order_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_cancel_req_pending_per_order
  ON public.cancellation_requests (order_id) WHERE status = 'pending';

ALTER TABLE public.cancellation_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cancel_req_select_self" ON public.cancellation_requests;
CREATE POLICY "cancel_req_select_self" ON public.cancellation_requests
  FOR SELECT TO authenticated USING (requester_id = auth.uid());

DROP POLICY IF EXISTS "cancel_req_select_admin" ON public.cancellation_requests;
CREATE POLICY "cancel_req_select_admin" ON public.cancellation_requests
  FOR SELECT TO authenticated USING (
    COALESCE(
      (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
      (auth.jwt() ->> 'role')) = 'admin');

-- ── RPC: request_order_cancel (driver/partner/client) ──────────────────────
CREATE OR REPLACE FUNCTION public.request_order_cancel(
  p_order_id TEXT,
  p_reason   TEXT
)
RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_order RECORD;
  v_req public.cancellation_requests;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  SELECT id, user_id, status, assigned_driver_id, restaurant_id
    INTO v_order FROM public.orders WHERE id = p_order_id;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  -- Resolve requester role
  IF v_order.user_id = v_user THEN
    v_role := 'client';
  ELSIF v_order.assigned_driver_id::text = v_user::text THEN
    v_role := 'driver';
  ELSE
    -- Check if user is a partner of the restaurant
    IF EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = v_order.restaurant_id
        AND r.owner_id = v_user
    ) THEN
      v_role := 'partner';
    ELSE
      RAISE EXCEPTION 'not_authorized_for_order' USING ERRCODE='42501';
    END IF;
  END IF;

  IF v_order.status IN ('delivered','rejected','cancelled') THEN
    RAISE EXCEPTION 'order_terminal: %', v_order.status USING ERRCODE='23514';
  END IF;

  INSERT INTO public.cancellation_requests
    (order_id, requester_role, requester_id, reason, status)
  VALUES (p_order_id, v_role, v_user, trim(p_reason), 'pending')
  RETURNING * INTO v_req;

  RETURN v_req;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'cancellation_already_pending: %', p_order_id USING ERRCODE='23505';
END;
$$;
REVOKE ALL ON FUNCTION public.request_order_cancel(TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_order_cancel(TEXT, TEXT) TO authenticated;

-- ── RPC: admin_approve_cancellation ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_approve_cancellation(
  p_request_id   UUID,
  p_refund_method TEXT
)
RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_req public.cancellation_requests;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_refund_method NOT IN ('stripe','wallet','none') THEN
    RAISE EXCEPTION 'invalid_refund_method';
  END IF;

  UPDATE public.cancellation_requests
  SET status = 'approved',
      reviewed_by_admin = v_admin.admin_id,
      reviewed_at = now(),
      refund_method = p_refund_method
  WHERE id = p_request_id AND status = 'pending'
  RETURNING * INTO v_req;
  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'request_not_found_or_not_pending';
  END IF;

  PERFORM public.log_admin_action(
    'cancellation_approved', 'cancellation_request', v_req.id,
    jsonb_build_object('order_id', v_req.order_id, 'refund_method', p_refund_method,
                       'requester_role', v_req.requester_role));

  -- NOTA: a execução real do refund (Stripe/wallet) deve ser feita por
  -- Edge Function dedicada chamada após esta aprovação. Esta RPC apenas
  -- marca a aprovação para evitar acoplar SQL a Stripe.
  RETURN v_req;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_approve_cancellation(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_cancellation(UUID, TEXT) TO authenticated;

-- ── RPC: admin_reject_cancellation ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reject_cancellation(
  p_request_id UUID,
  p_reason     TEXT
)
RETURNS public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_req public.cancellation_requests;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  UPDATE public.cancellation_requests
  SET status = 'rejected',
      reviewed_by_admin = v_admin.admin_id,
      reviewed_at = now(),
      rejection_reason = trim(p_reason)
  WHERE id = p_request_id AND status = 'pending'
  RETURNING * INTO v_req;
  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'request_not_found_or_not_pending';
  END IF;
  PERFORM public.log_admin_action('cancellation_rejected','cancellation_request', v_req.id,
    jsonb_build_object('order_id', v_req.order_id, 'reason', trim(p_reason)));
  RETURN v_req;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_reject_cancellation(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_cancellation(UUID, TEXT) TO authenticated;

-- ── RPC: admin_list_cancellation_requests ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_cancellation_requests(
  p_status TEXT DEFAULT NULL,
  p_limit  INT  DEFAULT 50,
  p_offset INT  DEFAULT 0
)
RETURNS SETOF public.cancellation_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
    SELECT * FROM public.cancellation_requests
    WHERE p_status IS NULL OR status = p_status
    ORDER BY (status='pending') DESC, created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_cancellation_requests(TEXT, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_cancellation_requests(TEXT, INT, INT) TO authenticated;

COMMIT;
