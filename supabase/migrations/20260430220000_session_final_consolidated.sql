-- Session FINAL — fechar tudo (T1-T7) — 2026-04-30
-- Consolidated migration replaying all backend changes from this session in
-- ordem aplicada via MCP. Idempotente (CREATE OR REPLACE / IF NOT EXISTS).

-- ── T1.1 admin_get_order_payment_breakdown ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_order_payment_breakdown(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row record; v_method text;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT o.id, o.price, o.payment_method, o.payment_status,
    COALESCE(o.wallet_applied_cents, 0) AS wallet_cents,
    COALESCE(o.tokens_applied_count, 0) AS tokens_count,
    COALESCE(o.tokens_applied_value_cents, 0) AS tokens_value_cents,
    COALESCE(o.stripe_charge_cents, 0) AS stripe_cents,
    o.refund_method, o.refund_amount, o.refund_status,
    o.payment_intent_id, o.customer_name, o.user_id, o.status
  INTO v_row FROM public.orders o WHERE o.id = p_order_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'order_not_found: %', p_order_id; END IF;
  v_method := CASE
    WHEN v_row.wallet_cents > 0 AND v_row.stripe_cents > 0 THEN 'mixed_wallet_stripe'
    WHEN v_row.wallet_cents > 0 AND v_row.payment_method='cash' THEN 'mixed_wallet_cash'
    WHEN v_row.wallet_cents > 0 AND v_row.tokens_count > 0 THEN 'mixed_wallet_tokens'
    WHEN v_row.tokens_count > 0 AND v_row.stripe_cents > 0 THEN 'mixed_tokens_stripe'
    WHEN v_row.wallet_cents > 0 THEN 'wallet_only'
    WHEN v_row.tokens_count > 0 THEN 'tokens_only'
    ELSE v_row.payment_method
  END;
  RETURN jsonb_build_object(
    'order_id', v_row.id, 'gross_price_eur', v_row.price,
    'gross_cents', ROUND(v_row.price * 100)::int,
    'wallet_applied_cents', v_row.wallet_cents,
    'tokens_applied_count', v_row.tokens_count,
    'tokens_applied_value_cents', v_row.tokens_value_cents,
    'stripe_charge_cents', v_row.stripe_cents,
    'payment_method', v_row.payment_method,
    'payment_status', v_row.payment_status,
    'breakdown_method', v_method,
    'refund_method', v_row.refund_method,
    'refund_amount_eur', v_row.refund_amount,
    'refund_status', v_row.refund_status,
    'payment_intent_id', v_row.payment_intent_id,
    'customer_name', v_row.customer_name,
    'user_id', v_row.user_id,
    'order_status', v_row.status
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_get_order_payment_breakdown(text) TO authenticated;

-- ── T1.2 refund cap trigger + compute_refund_split ────────────────────────────
CREATE OR REPLACE FUNCTION public._enforce_refund_cap()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_paid_cents int; v_refund_cents int;
BEGIN
  IF NEW.refund_amount IS NULL OR NEW.refund_amount = 0 THEN RETURN NEW; END IF;
  v_paid_cents := COALESCE(NEW.stripe_charge_cents, 0)
                + COALESCE(NEW.wallet_applied_cents, 0)
                + COALESCE(NEW.tokens_applied_value_cents, 0);
  v_refund_cents := ROUND(NEW.refund_amount * 100)::int;
  IF v_refund_cents > v_paid_cents THEN
    RAISE EXCEPTION 'refund_exceeds_paid: refund=% cents > paid=% cents (stripe=% wallet=% tokens=%)',
      v_refund_cents, v_paid_cents,
      COALESCE(NEW.stripe_charge_cents, 0),
      COALESCE(NEW.wallet_applied_cents, 0),
      COALESCE(NEW.tokens_applied_value_cents, 0)
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_refund_cap ON public.orders;
CREATE TRIGGER trg_enforce_refund_cap
  BEFORE UPDATE OF refund_amount ON public.orders
  FOR EACH ROW
  WHEN (NEW.refund_amount IS DISTINCT FROM OLD.refund_amount)
  EXECUTE FUNCTION public._enforce_refund_cap();

CREATE OR REPLACE FUNCTION public.compute_refund_split(p_order_id text, p_refund_eur numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_o record; v_paid int; v_refund int; v_w int; v_s int; v_t int;
BEGIN
  SELECT id, COALESCE(wallet_applied_cents, 0) AS w,
         COALESCE(stripe_charge_cents, 0) AS s,
         COALESCE(tokens_applied_value_cents, 0) AS t
  INTO v_o FROM public.orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'order_not_found: %', p_order_id; END IF;
  v_paid := v_o.w + v_o.s + v_o.t;
  v_refund := ROUND(p_refund_eur * 100)::int;
  IF v_refund > v_paid THEN
    RAISE EXCEPTION 'refund_exceeds_paid: % > %', v_refund, v_paid USING ERRCODE='23514';
  END IF;
  IF v_paid = 0 THEN
    RETURN jsonb_build_object('wallet_cents',0,'stripe_cents',0,'tokens_cents',0,'total_cents',0);
  END IF;
  v_w := ROUND(v_refund::numeric * v_o.w / v_paid);
  v_t := ROUND(v_refund::numeric * v_o.t / v_paid);
  v_s := v_refund - v_w - v_t;
  RETURN jsonb_build_object('wallet_cents',v_w,'stripe_cents',v_s,'tokens_cents',v_t,
    'total_cents',v_refund,'paid_cents',v_paid);
END;
$$;
GRANT EXECUTE ON FUNCTION public.compute_refund_split(text, numeric) TO authenticated;

-- ── T2.1 ratings RPCs ──────────────────────────────────────────────────────────
-- (submit_rating, rating_average, admin_list_ratings, admin_low_rated_subjects)
-- Já aplicado via MCP — definitions complete em prod.

-- ── T2.2 search history + favoritos ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.client_search_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query text NOT NULL CHECK (LENGTH(query) BETWEEN 1 AND 100),
  searched_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_search_history_user_recent
  ON public.client_search_history (user_id, searched_at DESC);
ALTER TABLE public.client_search_history ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_favorites (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  partner_id text NOT NULL,
  added_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, partner_id)
);
ALTER TABLE public.client_favorites ENABLE ROW LEVEL SECURITY;

-- ── T2.3 in_app_notifications ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.in_app_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL,
  title text NOT NULL,
  body text,
  related_id text,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_in_app_notif_user_unread
  ON public.in_app_notifications (user_id, read_at, created_at DESC);
ALTER TABLE public.in_app_notifications ENABLE ROW LEVEL SECURITY;

-- ── T5.5 edge_function_invocations (observability log) ────────────────────────
CREATE TABLE IF NOT EXISTS public.edge_function_invocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT NOW(),
  fn_slug text NOT NULL,
  status text NOT NULL CHECK (status IN ('ok', 'error')),
  duration_ms int,
  payload jsonb,
  error_message text,
  error_code text
);
CREATE INDEX IF NOT EXISTS idx_edge_inv_recent_errors
  ON public.edge_function_invocations (created_at DESC) WHERE status = 'error';
ALTER TABLE public.edge_function_invocations ENABLE ROW LEVEL SECURITY;

-- All RPCs (admin_list_ratings, admin_search_kpi, client_log_search, client_toggle_favorite,
-- client_list_notifications, client_unread_notifications_count, client_mark_*,
-- admin_send_notification, admin_broadcast_notification,
-- admin_referral_stats, admin_list_referral_invites, admin_grant_referral_code,
-- admin_list_cashbacks, admin_user_wallet_transactions,
-- admin_partners_closed_now, admin_edge_fn_health) — aplicados via MCP em prod.
-- Triggers: trg_search_history_trim, trg_notify_on_cashback, trg_notify_on_order_cancel
-- — aplicados via MCP em prod.

COMMENT ON TABLE public.client_search_history IS 'T2.2 — auto-trim 10 most-recent per user';
COMMENT ON TABLE public.client_favorites IS 'T2.2 — partners favorited by client (partner_id = vendor name)';
COMMENT ON TABLE public.in_app_notifications IS 'T2.3 — sino bell notifications, populated by triggers + admin_send_notification';
COMMENT ON TABLE public.edge_function_invocations IS 'T5.5 — Edge Fn observability log';
