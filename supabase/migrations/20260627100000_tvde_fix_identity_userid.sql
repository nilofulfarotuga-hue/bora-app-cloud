-- ============================================================================
-- BORA MOTORISTA (TVDE) — FIX CRÍTICO · identidade id ↔ user_id no dispatch
-- ============================================================================
-- CONTEXTO (confirmado em prod via MCP):
--   drivers tem id (PK do registo) E user_id (utilizador auth). Nos motoristas
--   reais id <> user_id (ex.: carro_passageiros id=fe91c821, user_id=4f61dd31).
--   O dispatch estava INCONSISTENTE:
--     • tvde_offer_to_next selecionava/gravava/excluía por d.id
--     • tvde_accept_ride + todo o lifecycle (arrived/start/finish/cancel/rate)
--       e o saldo (tvde_driver_balances) usam auth.uid() = user_id
--   Efeito: recusar não rodava (offer=id vs uid=user_id), exclusão de ocupado
--   falhava, e accept não conferia a posse da oferta (roubo de corrida).
--
-- CORREÇÃO: alinhar TUDO ao user_id (a identidade real do auth).
-- ADITIVO/cirúrgico: só toca funções TVDE isoladas. NÃO toca dispatch-engine,
-- orders, pricing, notify-driver nem qualquer zona de delivery.
-- ============================================================================

BEGIN;

-- ── A) tvde_offer_to_next — identidade do motorista = user_id ────────────────
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

  -- Elegível: online + heartbeat fresco + carro de passageiros + não já
  -- ofertado/recusado + não em corrida ativa. Identidade = d.user_id (auth).
  SELECT d.user_id INTO v_driver
  FROM public.drivers d
  WHERE d.is_online = true
    AND d.vehicle_type = 'carro_passageiros'
    AND d.user_id IS NOT NULL
    AND d.last_heartbeat_at > now() - make_interval(secs => v_hb)
    AND d.lat IS NOT NULL AND d.lng IS NOT NULL
    AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.tvde_rides r2
      WHERE r2.driver_id = d.user_id
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

-- ── B) tvde_accept_ride — conferir a posse da oferta (segurança + consistência)
-- current_offer_driver_id agora = user_id. Antes do UPDATE valida a posse; e o
-- UPDATE acrescenta current_offer_driver_id = v_uid à WHERE (avaliada no valor
-- antigo) → impede roubo de corrida e race entre motoristas.
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
  IF v_pre.current_offer_driver_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'offer_no_longer_valid'; END IF;

  UPDATE public.tvde_rides
     SET driver_id = v_uid, status = 'motorista_a_caminho',
         current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id AND status = 'solicitada' AND driver_id IS NULL
     AND current_offer_driver_id = v_uid
   RETURNING * INTO v_ride;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_already_taken'; END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_atribuido', 'driver');
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_a_caminho', 'driver');
  RETURN v_ride;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_accept_ride(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_accept_ride(UUID) TO authenticated;

-- ── C) admin_tvde_rides_list — join drivers por user_id ─────────────────────
-- ride.driver_id = user_id. O join a drivers tem de ser por d.user_id.
-- driver_locations.driver_id é escrito pela RPC driver_update_location com
-- auth.uid() = user_id, logo o join dl.driver_id = ride.driver_id JÁ está correto.
CREATE OR REPLACE FUNCTION public.admin_tvde_rides_list(
  p_scope TEXT DEFAULT 'all',
  p_limit INTEGER DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 1000 THEN RAISE EXCEPTION 'limit 1..1000'; END IF;

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.created_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      ride.created_at AS created_at,
      jsonb_build_object(
        'id',                     ride.id,
        'status',                 ride.status,
        'created_at',             ride.created_at,
        'updated_at',             ride.updated_at,
        'origin_label',           ride.origin_label,
        'dest_label',             ride.dest_label,
        'est_distance_km',        ride.est_distance_km,
        'est_fare_cents',         ride.est_fare_cents,
        'final_distance_km',      ride.final_distance_km,
        'final_fare_cents',       ride.final_fare_cents,
        'driver_earn_cents',      ride.driver_earn_cents,
        'bora_cut_cents',         ride.bora_cut_cents,
        'cancel_fee_cents',       ride.cancel_fee_cents,
        'cancel_reason',          ride.cancel_reason,
        'payment_method',         ride.payment_method,
        'used_subscription_ride', ride.used_subscription_ride,
        'offer_expires_at',       ride.offer_expires_at,
        'client_id',              ride.client_id,
        'client_name',            COALESCE(au.raw_user_meta_data->>'bora_name', ''),
        'client_phone',           COALESCE(au.raw_user_meta_data->>'bora_phone', ''),
        'driver_id',              ride.driver_id,
        'driver_name',            d.name,
        'driver_phone',           d.phone,
        'driver_is_online',       d.is_online,
        'driver_lat',             dl.latitude,
        'driver_lng',             dl.longitude,
        'driver_loc_updated_at',  dl.last_updated
      ) AS row
    FROM public.tvde_rides ride
    LEFT JOIN auth.users au           ON au.id = ride.client_id
    LEFT JOIN public.drivers d        ON d.user_id = ride.driver_id
    LEFT JOIN public.driver_locations dl ON dl.driver_id = ride.driver_id
    WHERE CASE
      WHEN p_scope = 'live' THEN ride.status IN
        ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
      WHEN p_scope = 'history' THEN ride.status IN
        ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista')
      ELSE true
    END
    ORDER BY ride.created_at DESC
    LIMIT p_limit
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_rides_list(TEXT, INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_rides_list(TEXT, INTEGER) TO authenticated;

-- ── D) admin_tvde_drivers_list — rides e saldo por user_id ──────────────────
-- tvde_rides.driver_id = user_id e tvde_driver_balances.driver_id = user_id.
-- Os joins/subqueries têm de cruzar por d.user_id (não d.id).
CREATE OR REPLACE FUNCTION public.admin_tvde_drivers_list()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.is_online DESC, s.name ASC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      d.is_online AS is_online,
      d.name AS name,
      jsonb_build_object(
        'id',              d.id,
        'name',            d.name,
        'phone',           d.phone,
        'vehicle_type',    d.vehicle_type,
        'is_online',       d.is_online,
        'approval_status', d.approval_status,
        'rating',          d.avg_rating,
        'ratings_count',   d.ratings_count,
        'is_banned',       (d.banned_until IS NOT NULL AND d.banned_until > now()) OR COALESCE(d.is_banned, false),
        'banned_until',    d.banned_until,
        'ban_reason',      d.ban_reason,
        'tvde_balance',    COALESCE(b.balance, 0),
        'active_rides',    (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.user_id
                                AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')),
        'total_rides',     (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.user_id AND r.status = 'finalizada')
      ) AS row
    FROM public.drivers d
    LEFT JOIN public.tvde_driver_balances b ON b.driver_id = d.user_id
    WHERE d.vehicle_type = 'carro_passageiros'
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_drivers_list() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_drivers_list() TO authenticated;

COMMIT;
