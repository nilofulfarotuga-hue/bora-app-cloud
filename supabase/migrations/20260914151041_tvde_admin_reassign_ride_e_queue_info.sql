-- ============================================================================
-- TVDE — sobreposição: reatribuição pelo admin + informação da fila
-- 2026-09-14 · missão tvde-sobreposicao-back-to-back · Bloco A.3/A.4 + C + D
--
-- PORQUE EXISTE: hoje às 15:26 a corrida 45bcad34 teve de ser passada ao
-- Valdemir À MÃO, por SQL, porque existe admin_reassign_order (entregas) e
-- admin_reassign_carwash_booking (lavagem) mas nada para uma corrida TVDE viva.
--
-- O QUE ENTRA:
--   • admin_tvde_reassign_ride(p_ride_id, p_driver_id, p_motivo) — faz o que
--     foi feito à mão, mas em código e auditado: destino livre → atribui
--     directo ('motorista_a_caminho'); destino ocupado → entra na fila dele
--     (is_queued=true, 'motorista_atribuido'), respeitando
--     tvde_backtoback_max_queue. Limpa oferta/tried_driver_ids/no_driver_since,
--     grava evento com actor 'admin' e o motivo, sobe a fila do motorista
--     antigo se lhe tirámos a corrida que levava, avisa os dois motoristas por
--     push (kinds novos 'queued_added' / 'ride_assigned' /
--     'ride_reassigned_away' na notify-tvde-driver) e regista no audit do
--     admin. Aceita p_driver_id em QUALQUER dos dois formatos (drivers.id ou
--     drivers.user_id) e grava sempre user_id em tvde_rides.driver_id — é o
--     que a RLS e a app esperam (armadilha real: no Valdemir os dois ids são
--     diferentes).
--   • tvde_ride_queue_info(p_ride_id) — para o CLIENTE em fila (e para o
--     admin): quanto falta da corrida que o motorista leva + a ligação até à
--     recolha dele, com a velocidade média eta_avg_speed_kmh das settings.
--     Não expõe coordenadas nem dados do outro passageiro — só números.
--   • admin_tvde_rides_list passa a dizer, por corrida, atrás de quem está em
--     fila (queued_behind_ride_id) e quem leva atrás (queue_next_ride_id).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_tvde_reassign_ride(p_ride_id uuid, p_driver_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_ride public.tvde_rides;
  v_uid uuid;                    -- drivers.user_id do destino (o que tvde_rides.driver_id guarda)
  v_from uuid;                   -- motorista anterior (user_id), se havia
  v_was_queued boolean;
  v_was_active_nonqueued boolean;
  v_busy uuid;                   -- corrida activa não-fila do destino, se ocupado
  v_nq int;
  v_maxq int := COALESCE((public.get_setting('tvde_backtoback_max_queue') #>> '{}')::int, 1);
  v_queued boolean;
  v_next uuid;
  v_status text;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  IF p_driver_id IS NULL THEN RAISE EXCEPTION 'driver_required'; END IF;

  -- Aceita drivers.id OU drivers.user_id; grava sempre user_id.
  SELECT d.user_id INTO v_uid
    FROM public.drivers d
   WHERE d.user_id = p_driver_id OR d.id = p_driver_id
   ORDER BY (d.user_id = p_driver_id) DESC
   LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'driver_not_found'; END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.status NOT IN ('solicitada','sem_motorista','motorista_atribuido','motorista_a_caminho','motorista_chegou') THEN
    RAISE EXCEPTION 'ride_not_reassignable: %', v_ride.status;
  END IF;
  IF v_ride.driver_id = v_uid THEN RAISE EXCEPTION 'same_driver'; END IF;

  v_from := v_ride.driver_id;
  v_was_queued := COALESCE(v_ride.is_queued, false);
  v_was_active_nonqueued := v_from IS NOT NULL AND NOT v_was_queued
    AND v_ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou');

  -- O destino está ocupado? (a corrida activa não-fila mais comprometida)
  SELECT r.id INTO v_busy FROM public.tvde_rides r
   WHERE r.driver_id = v_uid AND r.id <> p_ride_id AND r.is_queued = false
     AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
   ORDER BY CASE r.status WHEN 'em_andamento' THEN 4 WHEN 'motorista_chegou' THEN 3
                          WHEN 'motorista_a_caminho' THEN 2 ELSE 1 END DESC,
            r.updated_at DESC
   LIMIT 1;
  v_queued := v_busy IS NOT NULL;
  IF v_queued THEN
    SELECT count(*) INTO v_nq FROM public.tvde_rides r3
     WHERE r3.driver_id = v_uid AND r3.id <> p_ride_id
       AND r3.is_queued = true AND r3.status = 'motorista_atribuido';
    IF v_nq >= GREATEST(v_maxq, 1) THEN RAISE EXCEPTION 'queue_full'; END IF;
  END IF;
  v_status := CASE WHEN v_queued THEN 'motorista_atribuido' ELSE 'motorista_a_caminho' END;

  UPDATE public.tvde_rides
     SET driver_id = v_uid, status = v_status, is_queued = v_queued,
         current_offer_driver_id = NULL, offer_expires_at = NULL, no_driver_since = NULL,
         tried_driver_ids = '{}', updated_at = now()
   WHERE id = p_ride_id
   RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (p_ride_id, v_status, 'admin',
          jsonb_build_object('reatribuicao_manual', true, 'motivo', p_motivo,
                             'de_driver', v_from, 'para_driver', v_uid, 'para_driver_pedido', p_driver_id,
                             'queued', v_queued, 'behind_ride_id', v_busy, 'admin_id', v_admin.admin_id));

  -- Se tirámos ao motorista antigo a corrida que ele LEVAVA, a fila dele sobe
  -- (o mesmo que tvde_cancel_ride faz quando a activa cai).
  IF v_was_active_nonqueued THEN
    UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                  WHERE r3.driver_id = v_from AND r3.is_queued = true AND r3.status = 'motorista_atribuido'
                  ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system',
              jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_admin_reassign', true));
    END IF;
  END IF;

  -- Avisos por push (tvde_reservation_push é o ajudante genérico que chama a
  -- notify-tvde-driver com um kind; os kinds novos vivem num ramo próprio lá).
  PERFORM public.tvde_reservation_push(v_uid, p_ride_id, CASE WHEN v_queued THEN 'queued_added' ELSE 'ride_assigned' END);
  IF v_from IS NOT NULL THEN
    PERFORM public.tvde_reservation_push(v_from, p_ride_id, 'ride_reassigned_away');
  END IF;

  PERFORM public.log_admin_action('tvde_ride_reassigned', 'tvde_ride', p_ride_id::text,
    jsonb_build_object('de', v_from, 'para', v_uid, 'queued', v_queued, 'behind_ride_id', v_busy, 'motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'ride_id', p_ride_id, 'driver_id', v_uid, 'queued', v_queued,
                            'behind_ride_id', v_busy, 'status', v_status, 'previous_driver_id', v_from,
                            'promoted_ride_id', v_next);
END; $function$;

REVOKE ALL ON FUNCTION public.admin_tvde_reassign_ride(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_reassign_ride(uuid, uuid, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- tvde_ride_queue_info — o cliente em fila vê "o motorista está a terminar uma
-- corrida aqui perto" com um ETA que SOMA: o que falta da corrida em curso +
-- destino dela → recolha dele. Só números; nada do outro passageiro.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tvde_ride_queue_info(p_ride_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.tvde_rides;
  v_cur  public.tvde_rides;
  v_speed numeric := COALESCE((public.get_setting('eta_avg_speed_kmh') #>> '{}')::numeric, 28);
  v_lat numeric; v_lng numeric;
  v_plat numeric; v_plng numeric;
  v_km_cur numeric := 0; v_km_link numeric := 0;
  v_stops int := 0;
  s record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.client_id IS DISTINCT FROM v_uid AND v_ride.driver_id IS DISTINCT FROM v_uid
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_ride_party';
  END IF;
  IF NOT COALESCE(v_ride.is_queued, false) OR v_ride.driver_id IS NULL THEN
    RETURN jsonb_build_object('queued', false);
  END IF;

  SELECT * INTO v_cur FROM public.tvde_rides r
   WHERE r.driver_id = v_ride.driver_id AND r.id <> p_ride_id AND r.is_queued = false
     AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
   ORDER BY CASE r.status WHEN 'em_andamento' THEN 4 WHEN 'motorista_chegou' THEN 3
                          WHEN 'motorista_a_caminho' THEN 2 ELSE 1 END DESC,
            r.updated_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('queued', true, 'ahead_status', NULL, 'eta_minutes', NULL);
  END IF;

  -- posição viva do motorista (chave dupla tolerante, como no cartão)
  SELECT l.latitude, l.longitude INTO v_lat, v_lng
    FROM public.drivers d
    JOIN public.driver_locations l ON l.driver_id IN (d.user_id, d.id)
   WHERE d.user_id = v_ride.driver_id
   ORDER BY l.last_updated DESC NULLS LAST
   LIMIT 1;

  -- o que falta da corrida em curso: posição → (recolha, se ainda não embarcou)
  -- → paradas por alcançar → destino
  IF v_lat IS NOT NULL THEN
    v_plat := v_lat; v_plng := v_lng;
    IF v_cur.status <> 'em_andamento' THEN
      v_km_cur := v_km_cur + public._haversine_km(v_plat, v_plng, v_cur.origin_lat::numeric, v_cur.origin_lng::numeric);
      v_plat := v_cur.origin_lat; v_plng := v_cur.origin_lng;
    END IF;
  ELSE
    v_plat := v_cur.origin_lat; v_plng := v_cur.origin_lng;
    v_km_cur := 0;
  END IF;
  FOR s IN SELECT st.lat, st.lng FROM public.tvde_ride_stops st
            WHERE st.ride_id = v_cur.id AND st.removed_at IS NULL AND st.reached_at IS NULL
            ORDER BY st.seq
  LOOP
    v_km_cur := v_km_cur + public._haversine_km(v_plat, v_plng, s.lat::numeric, s.lng::numeric);
    v_plat := s.lat; v_plng := s.lng; v_stops := v_stops + 1;
  END LOOP;
  v_km_cur := v_km_cur + public._haversine_km(v_plat, v_plng, v_cur.dest_lat::numeric, v_cur.dest_lng::numeric);
  -- ligação: destino da corrida em curso → recolha desta
  v_km_link := public._haversine_km(v_cur.dest_lat::numeric, v_cur.dest_lng::numeric,
                                    v_ride.origin_lat::numeric, v_ride.origin_lng::numeric);

  RETURN jsonb_build_object(
    'queued', true,
    'ahead_status', v_cur.status,
    'ahead_pending_stops', v_stops,
    'km_current_remaining', round(v_km_cur, 2),
    'km_link', round(v_km_link, 2),
    'speed_kmh', v_speed,
    'eta_minutes', GREATEST(1, CEIL(((v_km_cur + v_km_link) / NULLIF(v_speed, 0)) * 60))::int,
    'driver_lat', v_lat, 'driver_lng', v_lng
  );
END; $function$;

REVOKE ALL ON FUNCTION public.tvde_ride_queue_info(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_ride_queue_info(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- admin_tvde_rides_list — quem está em fila e atrás de quê
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_tvde_rides_list(p_scope text DEFAULT 'all'::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
        'is_queued',              ride.is_queued,
        -- sobreposição: atrás de que corrida esta está em fila / quem leva atrás
        'queued_behind_ride_id',  CASE WHEN ride.is_queued THEN
                                    (SELECT r2.id FROM public.tvde_rides r2
                                      WHERE r2.driver_id = ride.driver_id AND r2.id <> ride.id AND r2.is_queued = false
                                        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
                                      ORDER BY r2.updated_at DESC LIMIT 1)
                                  END,
        'queue_next_ride_id',     CASE WHEN NOT ride.is_queued AND ride.driver_id IS NOT NULL
                                        AND ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento') THEN
                                    (SELECT r3.id FROM public.tvde_rides r3
                                      WHERE r3.driver_id = ride.driver_id AND r3.is_queued = true AND r3.status = 'motorista_atribuido'
                                      ORDER BY r3.created_at ASC LIMIT 1)
                                  END,
        'arrived_at',             ride.arrived_at,
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
END; $function$;
