-- ============================================================================
-- TVDE — DUAL-DRIVER (Parte 2b) · exclusão de ocupado, sentido entrega→corrida
-- ----------------------------------------------------------------------------
-- Regra (decisão Danilo 2026-07-02): um motorista com uma ENTREGA ativa
-- (orders driverAccepted/pickedUp/onTheWay) NÃO recebe ofertas de corrida TVDE.
-- O sentido inverso (corrida ativa → sem ofertas de entrega) vive na
-- dispatch-engine v58 (edge function, autorizada pelo Danilo).
--
-- Mudança ÚNICA nesta migration: 1 condição NOT EXISTS na seleção de
-- candidatos de tvde_offer_to_next. Nota de identidade: tvde_rides.driver_id
-- guarda o auth uid (drivers.user_id), mas orders.assigned_driver_id guarda
-- drivers.id::text — por isso a ponte é d.id::text.
-- Resto da função byte-idêntico à versão em produção.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.tvde_offer_to_next(p_ride_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ride   public.tvde_rides;
  v_driver UUID;
  v_ttl    INT := (public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int;
  v_hb     INT := (public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;

  SELECT d.user_id INTO v_driver
  FROM public.drivers d
  JOIN public.driver_locations dl ON dl.driver_id = d.user_id
  WHERE d.vehicle_type = 'carro_passageiros'
    AND d.approval_status = 'approved'
    AND d.user_id IS NOT NULL
    AND (dl.is_online = true OR d.is_online = true)
    AND GREATEST(COALESCE(dl.last_updated,       '-infinity'::timestamptz),
                 COALESCE(d.last_heartbeat_at,   '-infinity'::timestamptz))
        > now() - make_interval(secs => v_hb)
    AND dl.latitude IS NOT NULL AND dl.longitude IS NOT NULL
    AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.tvde_rides r2
      WHERE r2.driver_id = d.user_id
        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
    -- dual-driver: entrega ativa → sem ofertas de corrida TVDE
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.assigned_driver_id = d.id::text
        AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
  ORDER BY public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) ASC
  LIMIT 1;

  IF v_driver IS NULL THEN
    UPDATE public.tvde_rides
       SET status='sem_motorista', current_offer_driver_id=NULL, offer_expires_at=NULL, updated_at=now()
     WHERE id = p_ride_id;
    INSERT INTO public.tvde_ride_events(ride_id,status,actor) VALUES (p_ride_id,'sem_motorista','system');
    RETURN false;
  END IF;

  UPDATE public.tvde_rides
     SET current_offer_driver_id = v_driver,
         offer_expires_at = now() + make_interval(secs => v_ttl), updated_at = now()
   WHERE id = p_ride_id;
  INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
    VALUES (p_ride_id,'oferta','system', jsonb_build_object('driver_id', v_driver, 'expires_in_s', v_ttl));
  RETURN true;
END; $function$;
