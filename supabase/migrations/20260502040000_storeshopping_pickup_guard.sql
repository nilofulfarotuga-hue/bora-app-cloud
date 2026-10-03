-- ============================================================================
-- BORA — BUG 30: server-side guard pickup requires finalized purchase
-- ============================================================================
-- Bloqueia transição para pickedUp/onTheWay em storeShopping NÃO-PARCEIRO
-- quando is_purchase_finalized=false. Defesa em profundidade contra
-- driver fraud (fingir que comprou) e quebra de ledger.
--
-- StoreShopping PARTNER tem fluxo restaurant — não cai neste guard.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_storeshopping_finalize_before_pickup()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.service_type = 'storeShopping'
     AND COALESCE(NEW.is_partner_store, false) = false
     AND NEW.status IN ('pickedUp', 'onTheWay')
     AND COALESCE(OLD.status, '') NOT IN ('pickedUp', 'onTheWay')
     AND COALESCE(NEW.is_purchase_finalized, false) = false
  THEN
    RAISE EXCEPTION 'finalize_purchase_before_pickup: cannot mark storeShopping non-partner as pickedUp before is_purchase_finalized=true (order=%)', NEW.id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS orders_storeshopping_pickup_guard ON public.orders;
CREATE TRIGGER orders_storeshopping_pickup_guard
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_storeshopping_finalize_before_pickup();

COMMIT;
