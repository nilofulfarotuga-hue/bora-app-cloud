-- ============================================================================
-- BORA — orders.delivered_at: timestamp da transição para status=delivered
-- ============================================================================
-- Necessário para settlements semanais — created_at não serve (pode ser dias
-- antes do delivered).
-- ============================================================================

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

UPDATE public.orders
   SET delivered_at = created_at
 WHERE status = 'delivered' AND delivered_at IS NULL;

CREATE OR REPLACE FUNCTION public.set_delivered_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status = 'delivered'
     AND (OLD.status IS DISTINCT FROM 'delivered')
     AND NEW.delivered_at IS NULL
  THEN
    NEW.delivered_at := now();
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS orders_set_delivered_at ON public.orders;
CREATE TRIGGER orders_set_delivered_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_delivered_at();

COMMIT;
