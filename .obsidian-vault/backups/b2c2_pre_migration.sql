-- Sync Obsidian — backup pre-migration B2 commit 2
-- Original: .claude/.ai/backups/b2c2_pre_migration_20260505.sql
-- Data: 2026-05-05

-- Trigger:
CREATE TRIGGER trg_zz_final_total_dual_write
  BEFORE INSERT OR UPDATE OF final_total
  ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION fn_sync_final_total_numeric();

-- Função:
CREATE OR REPLACE FUNCTION public.fn_sync_final_total_numeric()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.final_total_numeric := NEW.final_total::numeric;
  RETURN NEW;
END;
$function$;

-- RPC original (referencia final_total_numeric):
CREATE OR REPLACE FUNCTION public.agent_get_user_orders_summary(p_limit integer DEFAULT 5)
 RETURNS TABLE(order_id text, status text, created_at timestamp with time zone, partner_name text, total_cents integer, can_be_cancelled boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  RETURN QUERY
  SELECT
    o.id, o.status, o.created_at,
    COALESCE(r.name, 'N/D'),
    ROUND((COALESCE(o.final_total_numeric, o.final_total::numeric, 0))*100)::int,
    o.status IN ('pending','accepted')
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.user_id = auth.uid()
  ORDER BY o.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 20);
END$function$;
