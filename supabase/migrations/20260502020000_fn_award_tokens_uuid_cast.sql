-- ============================================================================
-- BORA — BUG 37: fn_award_tokens_on_delivery cast UUID em NEW.id
-- ============================================================================
-- Trigger falhava em entregas cash com:
--   "function add_tokens(uuid, unknown, integer, text) does not exist"
-- Causa: orders.id é TEXT (legacy compat), mas add_tokens.p_order_id é UUID.
-- Faltava ::UUID em NEW.id em ambas as chamadas (driver + client).
--
-- Lógica de tokens permanece IDÊNTICA — só cast.
--   • driver: 50 tokens partner | 40 não-partner
--   • client: ROUND(price * 3), min 1
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_award_tokens_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_driver_tokens  INTEGER;
  v_client_tokens  INTEGER;
BEGIN
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  IF NEW.assigned_driver_id IS NOT NULL THEN
    v_driver_tokens := CASE WHEN NEW.is_partner_store THEN 50 ELSE 40 END;
    PERFORM add_tokens(
      NEW.assigned_driver_id::UUID,
      'driver',
      v_driver_tokens,
      NEW.id::UUID
    );
  END IF;

  IF NEW.user_id IS NOT NULL AND NEW.price IS NOT NULL AND NEW.price > 0 THEN
    v_client_tokens := GREATEST(1, ROUND(NEW.price * 3)::INTEGER);
    PERFORM add_tokens(
      NEW.user_id,
      'client',
      v_client_tokens,
      NEW.id::UUID
    );
  END IF;

  RETURN NEW;
END;
$function$;

COMMIT;
