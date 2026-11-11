CREATE OR REPLACE FUNCTION public._coming_soon_guard_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_coming_soon boolean;
BEGIN
  IF NEW.restaurant_id IS NULL THEN RETURN NEW; END IF;
  -- 27/10/2026 modo demonstracao: so o pedido de teste do cliente demo, na loja e janela definidas.
  IF COALESCE(NEW.is_test_order, false) AND public._modo_demo_loja(NEW.restaurant_id, NEW.user_id) THEN RETURN NEW; END IF;
  SELECT r.coming_soon INTO v_coming_soon FROM public.restaurants r WHERE r.id = NEW.restaurant_id;
  IF COALESCE(v_coming_soon, false) THEN
    RAISE EXCEPTION 'STORE_COMING_SOON: Esta loja ainda nao esta a aceitar pedidos.' USING ERRCODE = 'P0001', HINT = 'STORE_COMING_SOON';
  END IF;
  RETURN NEW;
END;
$function$
;
