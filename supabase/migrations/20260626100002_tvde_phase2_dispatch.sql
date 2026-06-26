-- ============================================================================
-- BORA MOTORISTA (TVDE) — FASE 2 · Dispatch de passageiros ISOLADO
-- ============================================================================
-- Mirror do padrão PROVADO do delivery (current_offer + tried_driver_ids array +
-- _haversine_km + _dispatch_jwt + net.http_post), mas 100% separado:
-- NÃO toca dispatch-engine, fn_notify_driver_on_offer, orders, pricing.
-- Timeout é SERVER-SIDE (tvde_dispatch_sweep via pg_cron) — não depende do app.
-- ============================================================================

BEGIN;

-- Rotação de ofertas: lista de motoristas já ofertados (recusou/expirou)
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS tried_driver_ids UUID[] NOT NULL DEFAULT '{}';

-- Settings (mesma janela de heartbeat do delivery = 90s)
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_offer_ttl_seconds',        '25', 'TVDE: tempo da oferta antes de passar ao próximo', 'tvde'),
  ('tvde_heartbeat_window_seconds', '90', 'TVDE: janela de heartbeat p/ motorista elegível',  'tvde')
ON CONFLICT (key) DO NOTHING;

-- ── Matching + oferta ao próximo motorista elegível mais próximo ─────────────
CREATE OR REPLACE FUNCTION public.tvde_offer_to_next(p_ride_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ride   public.tvde_rides;
  v_driver UUID;
  v_ttl    INT := (public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int;
  v_hb     INT := (public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;

  -- Elegível: online + heartbeat fresco + carro de passageiros (COLUNA DB) +
  -- não já ofertado/recusado + não em corrida ativa. Mais próximo por haversine.
  SELECT d.id INTO v_driver
  FROM public.drivers d
  WHERE d.is_online = true
    AND d.vehicle_type = 'carro_passageiros'
    AND d.last_heartbeat_at > now() - make_interval(secs => v_hb)
    AND d.lat IS NOT NULL AND d.lng IS NOT NULL
    AND NOT (d.id = ANY(v_ride.tried_driver_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.tvde_rides r2
      WHERE r2.driver_id = d.id
        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
  ORDER BY public._haversine_km(d.lat::numeric, d.lng::numeric,
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
END; $$;
REVOKE ALL ON FUNCTION public.tvde_offer_to_next(UUID) FROM public, anon, authenticated;

-- ── Push ao motorista quando a oferta muda (mirror fn_notify_driver_on_offer) ─
CREATE OR REPLACE FUNCTION public.fn_notify_tvde_driver_on_offer()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','net','extensions' AS $$
DECLARE v_jwt text;
BEGIN
  IF NEW.current_offer_driver_id IS NULL THEN RETURN NEW; END IF;
  IF OLD.current_offer_driver_id IS NOT DISTINCT FROM NEW.current_offer_driver_id THEN RETURN NEW; END IF;
  v_jwt := public._dispatch_jwt();
  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-driver',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_jwt),
    body    := jsonb_build_object('driverId', NEW.current_offer_driver_id::text, 'rideId', NEW.id::text)
  );
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.fn_notify_tvde_driver_on_offer() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS tr_notify_tvde_driver_on_offer ON public.tvde_rides;
CREATE TRIGGER tr_notify_tvde_driver_on_offer
  AFTER UPDATE OF current_offer_driver_id ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_tvde_driver_on_offer();

-- ── Dispara dispatch ao criar a corrida ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_tvde_dispatch_on_request()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'solicitada' THEN
    PERFORM public.tvde_offer_to_next(NEW.id);
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.fn_tvde_dispatch_on_request() FROM public, anon, authenticated;
DROP TRIGGER IF EXISTS tr_tvde_dispatch_on_request ON public.tvde_rides;
CREATE TRIGGER tr_tvde_dispatch_on_request
  AFTER INSERT ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_tvde_dispatch_on_request();

-- ── Sweep SERVER-SIDE: expira ofertas vencidas e passa ao próximo ───────────
CREATE OR REPLACE FUNCTION public.tvde_dispatch_sweep()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT id, current_offer_driver_id FROM public.tvde_rides
    WHERE status='solicitada' AND offer_expires_at IS NOT NULL AND offer_expires_at < now()
      AND current_offer_driver_id IS NOT NULL
  LOOP
    UPDATE public.tvde_rides
       SET tried_driver_ids = array_append(tried_driver_ids, r.current_offer_driver_id),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = r.id;
    INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
      VALUES (r.id,'oferta_expirada','system', jsonb_build_object('driver_id', r.current_offer_driver_id));
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_dispatch_sweep() FROM public, anon, authenticated;

-- ── Accept ATÓMICO (claim condicional; só 1 motorista reivindica) ────────────
CREATE OR REPLACE FUNCTION public.tvde_accept_ride(p_ride_id UUID)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_pre public.tvde_rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_pre FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_pre.status <> 'solicitada' THEN RAISE EXCEPTION 'ride_not_available: %', v_pre.status; END IF;
  IF v_uid = ANY(v_pre.tried_driver_ids) THEN RAISE EXCEPTION 'offer_no_longer_valid'; END IF;

  UPDATE public.tvde_rides
     SET driver_id = v_uid, status = 'motorista_a_caminho',
         current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id AND status = 'solicitada' AND driver_id IS NULL
   RETURNING * INTO v_ride;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_already_taken'; END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_atribuido', 'driver');
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_a_caminho', 'driver');
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_accept_ride(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_accept_ride(UUID) TO authenticated;

COMMIT;
