-- ===========================================================
-- admin_live_orders: adicionar filtro is_test_order
-- Data: 2026-05-08 / Sessao 7-alpha-ADMIN-FILTER (#4 maratona)
--
-- Mudancas:
-- 1. Novo parametro: p_include_test_orders BOOLEAN DEFAULT false
--    (default false = comportamento antigo preservado)
-- 2. Retorno passa a incluir coluna is_test_order
-- 3. WHERE filtra conforme parametro
--
-- NOTA: Esta migration foi APLICADA via MCP Supabase em prod
-- antes de ser comitada como ficheiro local. Sync TODO 7-alpha:
-- supabase db pull para sync completo migrations locais (futuro).
-- ===========================================================

-- DROP defensivo: ambas signatures possiveis
DROP FUNCTION IF EXISTS public.admin_live_orders();
DROP FUNCTION IF EXISTS public.admin_live_orders(BOOLEAN);

CREATE OR REPLACE FUNCTION public.admin_live_orders(
  p_include_test_orders BOOLEAN DEFAULT false
)
RETURNS TABLE(
  id text,
  status text,
  service_type text,
  vendor_name text,
  customer_name text,
  total numeric,
  created_at timestamp with time zone,
  pickup_lat numeric,
  pickup_lng numeric,
  dropoff_lat numeric,
  dropoff_lng numeric,
  pickup_address text,
  dropoff_address text,
  assigned_driver_id text,
  is_partner_store boolean,
  is_test_order boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
  SELECT
    o.id,
    o.status,
    o.service_type,
    o.vendor_name,
    o.customer_name,
    COALESCE(o.price, 0)::numeric,
    o.created_at,
    o.pickup_lat::numeric,
    o.pickup_lng::numeric,
    o.dropoff_lat::numeric,
    o.dropoff_lng::numeric,
    o.pickup_address,
    o.dropoff_address,
    o.assigned_driver_id,
    COALESCE(o.is_partner_store, false),
    COALESCE(o.is_test_order, false)
  FROM public.orders o
  WHERE o.status IN ('created', 'preparing', 'callingDriver',
                     'driverAccepted', 'pickedUp', 'onTheWay')
    AND (
      p_include_test_orders = true
      OR COALESCE(o.is_test_order, false) = false
    )
  ORDER BY o.created_at DESC
  LIMIT 100;
END;
$function$;
