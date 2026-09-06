-- Sessão 5A-2 B-FIX-1 (BLOQUEADOR pré-B12)
-- Bug crítico em 5A-1: agent_get_order_status mapeava estados snake_case
-- (pending/accepted/picked_up/...) que NÃO existem em prod.
-- Estados reais validados via MCP DISTINCT em orders.status:
--   delivered, cancelled, rejected, driverAccepted (camelCase Dart-like).
-- Estados completos do flow OrderStore._statusFlow:
--   created → preparing | rejected
--   preparing → callingDriver
--   callingDriver → driverAccepted
--   driverAccepted → pickedUp
--   pickedUp → onTheWay
--   onTheWay → delivered

CREATE OR REPLACE FUNCTION public.agent_get_order_status(
  p_order_id text
) RETURNS TABLE (
  status text, current_step text, driver_name text,
  driver_eta_min int, can_be_cancelled bool
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
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
      WHEN 'created' THEN 'A aguardar confirmação'
      WHEN 'preparing' THEN 'Em preparação'
      WHEN 'callingDriver' THEN 'À procura de estafeta'
      WHEN 'driverAccepted' THEN 'Estafeta a caminho do parceiro'
      WHEN 'pickedUp' THEN 'Recolhido — a caminho'
      WHEN 'onTheWay' THEN 'A caminho da tua morada'
      WHEN 'delivered' THEN 'Entregue'
      WHEN 'cancelled' THEN 'Cancelado'
      WHEN 'rejected' THEN 'Rejeitado'
      ELSE o.status
    END,
    NULLIF(d.name, ''),
    NULL::int,
    o.status IN ('created', 'preparing', 'callingDriver')
  FROM public.orders o
  LEFT JOIN public.drivers d ON d.id = o.driver_id
  WHERE o.id = p_order_id;
END$fn$;
