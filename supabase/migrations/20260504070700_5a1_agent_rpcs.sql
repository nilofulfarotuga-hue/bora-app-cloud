-- Sessão 5A-1 B8 — 5 RPCs whitelisted para tool-calling do agente IA.
-- TODAS SECURITY DEFINER + auth.uid() directo (sem p_user_id, defesa impersonation).

-- B8.1 — últimos pedidos do user
CREATE OR REPLACE FUNCTION public.agent_get_user_orders_summary(
  p_limit int DEFAULT 5
)
RETURNS TABLE (
  order_id text, status text, created_at timestamptz,
  partner_name text, total_cents int, can_be_cancelled bool
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  RETURN QUERY
  SELECT
    o.id,
    o.status,
    o.created_at,
    COALESCE(r.name, 'N/D'),
    ROUND(
      (COALESCE(o.final_total_numeric, o.final_total::numeric, 0))*100
    )::int,
    o.status IN ('pending','accepted')
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.user_id = auth.uid()
  ORDER BY o.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 20);
END$$;

REVOKE ALL ON FUNCTION public.agent_get_user_orders_summary(int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_user_orders_summary(int) TO authenticated;

-- B8.2 — status detalhado de 1 pedido
CREATE OR REPLACE FUNCTION public.agent_get_order_status(
  p_order_id text
)
RETURNS TABLE (
  status text, current_step text, driver_name text,
  driver_eta_min int, can_be_cancelled bool
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.orders
    WHERE id = p_order_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND_OR_NOT_OWNER';
  END IF;
  RETURN QUERY
  SELECT
    o.status,
    CASE o.status
      WHEN 'pending' THEN 'A aguardar confirmação'
      WHEN 'accepted' THEN 'Aceite — preparação'
      WHEN 'preparing' THEN 'Em preparação'
      WHEN 'driver_assigned' THEN 'Estafeta a caminho'
      WHEN 'picked_up' THEN 'Recolhido — a entregar'
      WHEN 'delivered' THEN 'Entregue'
      WHEN 'cancelled' THEN 'Cancelado'
      ELSE o.status
    END,
    NULLIF(d.name, ''),
    NULL::int,  -- ETA real em 5B/5C com driver_locations
    o.status IN ('pending','accepted')
  FROM public.orders o
  LEFT JOIN public.drivers d ON d.id = o.driver_id
  WHERE o.id = p_order_id;
END$$;

REVOKE ALL ON FUNCTION public.agent_get_order_status(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_order_status(text) TO authenticated;

-- B8.3 — wallet free balance + estado bloqueio (AJUSTE: free_balance_cents)
CREATE OR REPLACE FUNCTION public.agent_get_user_wallet_summary()
RETURNS TABLE (
  free_balance_cents int, is_blocked bool,
  soft_floor_cents int, hard_floor_cents int,
  explanation text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_balance int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  SELECT cw.free_balance_cents INTO v_balance
    FROM public.client_wallets cw
    WHERE cw.user_id = auth.uid();
  v_balance := COALESCE(v_balance, 0);
  RETURN QUERY SELECT
    v_balance,
    v_balance <= -1000,  -- soft floor −€10
    -1000, -2000,
    CASE
      WHEN v_balance >= 0 THEN 'Saldo positivo.'
      WHEN v_balance > -1000 THEN
        'Saldo negativo (liquida no próximo pedido).'
      ELSE
        'Bloqueado por dívida acima de €10. ' ||
        'Liquida no próximo pedido para desbloquear.'
    END;
END$$;

REVOKE ALL ON FUNCTION public.agent_get_user_wallet_summary() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_user_wallet_summary() TO authenticated;

-- B8.4 — tokens summary (AJUSTES: expires_at NOT NULL + COALESCE(is_used,false))
CREATE OR REPLACE FUNCTION public.agent_get_user_tokens_summary()
RETURNS TABLE (
  tokens_balance int, expiring_soon_count int
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  RETURN QUERY
  SELECT
    COALESCE(SUM(amount), 0)::int,
    COALESCE(SUM(amount) FILTER (
      WHERE expires_at < now() + interval '7 days'
    ), 0)::int
  FROM public.bora_tokens
  WHERE user_id = auth.uid()
    AND COALESCE(is_used, false) = false
    AND expires_at > now();
END$$;

REVOKE ALL ON FUNCTION public.agent_get_user_tokens_summary() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_user_tokens_summary() TO authenticated;

-- B8.5 — estado refund de 1 pedido (placeholder estrutural)
-- Nota: refund detail dedicado em 5B (quando há tabela refunds dedicada
-- ou logs Stripe centralizados). Por agora retorna info derivada de orders.
CREATE OR REPLACE FUNCTION public.agent_get_refund_status(
  p_order_id text
)
RETURNS TABLE (
  refund_status text, refund_method text,
  refund_amount_cents int, eta_text text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.orders
    WHERE id = p_order_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND_OR_NOT_OWNER';
  END IF;

  SELECT o.status INTO v_status
    FROM public.orders o WHERE o.id = p_order_id;

  RETURN QUERY
  SELECT
    CASE
      WHEN v_status = 'cancelled' THEN 'pending'
      WHEN v_status = 'delivered' THEN 'not_applicable'
      ELSE 'unknown'
    END,
    'unknown'::text,  -- method real virá de tabela refunds em 5B
    0,
    'Cartão: 3-5 dias úteis. Wallet: imediato.'::text;
END$$;

REVOKE ALL ON FUNCTION public.agent_get_refund_status(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_refund_status(text) TO authenticated;
