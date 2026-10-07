-- 07/10/2026: quando só há 1 estafeta, o despacho volta a oferecer ao MESMO estafeta a
-- cada minuto. O gatilho só avisava quando mudava o estafeta, por isso o telemóvel
-- tocava uma vez e ficava calado (McDonald's 947f7206 de 06/10: 20 ofertas ao Danilo,
-- só ~5 avisos enviados). Agora avisa também quando a oferta é renovada (prazo novo).
-- Aplicado em produção por MCP a 07/10/2026.
CREATE OR REPLACE FUNCTION public.fn_notify_driver_on_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE
  v_driver_id text;
  v_order_id  text;
  v_vendor    text;
  v_total     numeric;
  v_jwt       text;
BEGIN
  IF NEW.current_driver_offer_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF OLD.current_driver_offer_id IS NOT DISTINCT FROM NEW.current_driver_offer_id
     AND OLD.driver_offer_expires_at IS NOT DISTINCT FROM NEW.driver_offer_expires_at THEN
    RETURN NEW;
  END IF;

  v_driver_id := NEW.current_driver_offer_id;
  v_order_id  := NEW.id::text;
  v_vendor    := COALESCE(NEW.vendor_name, 'Pedido');
  v_total     := COALESCE(NEW.price, 0);
  v_jwt       := public._dispatch_service_jwt();

  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_jwt
    ),
    body    := jsonb_build_object(
      'driverId',   v_driver_id,
      'orderId',    v_order_id,
      'vendorName', v_vendor,
      'total',      v_total
    )
  );

  RAISE LOG '[fn_notify_driver_on_offer] orderId=% driverId=% vendor=%', v_order_id, v_driver_id, v_vendor;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_notify_driver_on_offer ON public.orders;
CREATE TRIGGER tr_notify_driver_on_offer AFTER UPDATE OF current_driver_offer_id, driver_offer_expires_at ON public.orders FOR EACH ROW EXECUTE FUNCTION fn_notify_driver_on_offer();
