-- ============================================================================
-- BORA MOTORISTA (TVDE) — matching lê driver_locations (GPS real-time por user_id)
-- ============================================================================
-- Sequência do fix id<>user_id (20260627100000/100001).
--
-- PROBLEMA: tvde_offer_to_next filtrava por drivers.lat/lng/last_heartbeat_at/
--   is_online. Mas driver_update_location grava drivers só WHERE id=auth.uid();
--   no motorista TVDE (id<>user_id) esse UPDATE afeta 0 linhas → drivers.lat/lng/
--   heartbeat NUNCA atualizam → online mas nunca elegível.
--
-- FONTE CORRETA: driver_locations (driver_id=auth.uid()=user_id, escrito pela RPC
--   driver_update_location ~linha 49) — mesma fonte real-time do delivery.
--
-- FIX: o matching passa a ler localização/online/frescura do driver_locations
--   (JOIN por user_id). Mantém vehicle_type da drivers, defesa approval_status=
--   'approved', e a lógica tried/ocupado por user_id. NÃO toca driver_update_location.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.tvde_offer_to_next(p_ride_id uuid)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
    AND dl.is_online = true
    AND dl.last_updated > now() - make_interval(secs => v_hb)
    AND dl.latitude IS NOT NULL AND dl.longitude IS NOT NULL
    AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.tvde_rides r2
      WHERE r2.driver_id = d.user_id
        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
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
REVOKE ALL ON FUNCTION public.tvde_offer_to_next(UUID) FROM public, anon, authenticated;
