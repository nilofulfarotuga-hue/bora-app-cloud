-- =============================================================================
-- MUDAR DESTINO — 2.ª revisão adversarial (30/09/2026)
-- MÉDIO 1: uma rota calculada noutro momento da corrida (ex.: antes da recolha)
-- podia ser reaproveitada durante 10 min chamando a RPC sem a Edge. Agora a
-- rota vale 60 s e tem de ter sido calculada no MESMO estado da corrida. A Edge
-- calcula sempre uma rota nova em cada cotação e em cada pedido.
-- =============================================================================
ALTER TABLE public.tvde_dest_change_routes ADD COLUMN IF NOT EXISTS ride_status text;

CREATE OR REPLACE FUNCTION public._tvde_dest_change_route(p_ride uuid, p_lat double precision, p_lng double precision)
RETURNS public.tvde_dest_change_routes LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT t.* FROM public.tvde_dest_change_routes t
    JOIN public.tvde_rides r ON r.id = t.ride_id
   WHERE t.ride_id = p_ride
     AND abs(t.dest_lat - p_lat) < 0.00001 AND abs(t.dest_lng - p_lng) < 0.00001
     AND t.created_at > now() - interval '60 seconds'
     AND t.ride_status IS NOT DISTINCT FROM r.status
   ORDER BY t.created_at DESC LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._tvde_dest_change_route(uuid, double precision, double precision) FROM PUBLIC, anon, authenticated;
