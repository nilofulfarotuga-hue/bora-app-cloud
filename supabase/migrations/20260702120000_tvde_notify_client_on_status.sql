-- TVDE — Bora Motorista (P1 paridade Uber): push ao PASSAGEIRO nas mudanças de
-- estado da corrida (motorista a caminho / chegou / viagem iniciada / sem
-- motorista / concluída / cancelada pelo motorista).
--
-- Espelha o padrão de fn_notify_tvde_driver_on_offer (net.http_post + _dispatch_jwt).
-- 100% ISOLADO: NÃO toca notify-driver/notify-client nem triggers de orders.
-- Alimenta a edge fn notify-tvde-client (fire-and-forget, 200 sempre).

CREATE OR REPLACE FUNCTION public.fn_notify_tvde_client_on_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE v_jwt text;
BEGIN
  -- Só quando o status muda de facto.
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  -- Só estados relevantes ao passageiro (evita ruído em 'solicitada' etc.).
  IF NEW.status NOT IN (
       'motorista_atribuido','motorista_a_caminho','motorista_chegou',
       'em_andamento','finalizada','sem_motorista','cancelada_motorista'
     ) THEN
    RETURN NEW;
  END IF;

  v_jwt := public._dispatch_jwt();
  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-client',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_jwt),
    body    := jsonb_build_object('rideId', NEW.id::text, 'status', NEW.status)
  );
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS tr_notify_tvde_client_on_status ON public.tvde_rides;
CREATE TRIGGER tr_notify_tvde_client_on_status
  AFTER UPDATE OF status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_tvde_client_on_status();
