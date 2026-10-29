-- 22/10/2026 · Danilo: reserva em que o passageiro nao apareceu aparecia como "sem motorista"
-- (e o app do cliente dizia "o reembolso e automatico", o que e falso: nao ha reembolso).
ALTER TABLE public.tvde_rides DROP CONSTRAINT IF EXISTS tvde_rides_reservation_status_check;
ALTER TABLE public.tvde_rides ADD CONSTRAINT tvde_rides_reservation_status_check CHECK (
  reservation_status IS NULL OR reservation_status = ANY (ARRAY[
    'aguarda_pagamento','a_procurar','atribuida','ativada','sem_motorista','cancelada','nao_compareceu']));

CREATE OR REPLACE FUNCTION public.fn_tvde_reservation_close_on_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.scheduled_at IS NULL THEN RETURN NEW; END IF;
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  IF NEW.status IN ('cancelada_cliente','cancelada_motorista') THEN
    NEW.reservation_status := 'cancelada';
  ELSIF NEW.status = 'no_show' THEN
    NEW.reservation_status := 'nao_compareceu';
  ELSIF NEW.status = 'sem_motorista' THEN
    NEW.reservation_status := 'sem_motorista';
  END IF;
  RETURN NEW;
END; $function$;

UPDATE public.tvde_rides SET reservation_status = 'nao_compareceu'
 WHERE status = 'no_show' AND reservation_status = 'sem_motorista';
