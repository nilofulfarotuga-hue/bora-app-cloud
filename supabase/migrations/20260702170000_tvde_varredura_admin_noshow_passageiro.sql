-- ============================================================================
-- TVDE — VARREDURA FINAL (Parte 4) · admin por user_id + no-show + passageiro
-- ----------------------------------------------------------------------------
-- 4a) BUG (flag da sessão anterior): admin_tvde_drivers_list cruzava
--     tvde_rides.driver_id (= auth uid) com drivers.id → contagens 0 para
--     motoristas reais. MESMA causa-raiz no join de tvde_driver_balances
--     (o saldo é gravado por auth uid em tvde_finish_ride). Ambos → d.user_id.
-- 4d) Estado dual no admin: has_active_delivery (entrega ativa via
--     orders.assigned_driver_id = d.id::text) + is_queued nas corridas ao vivo.
-- 4c) Espera no pickup: arrived_at (set em tvde_driver_arrived) + janela
--     tvde_noshow_wait_minutes (default 5) — o botão "Passageiro não
--     apareceu" só habilita depois da janela. SEM cobrança de no-show (P2).
-- M16) Nome do passageiro para o motorista da corrida (RPC dedicada, não
--      expõe users por RLS).
-- ============================================================================

-- ── 4c · coluna + setting ───────────────────────────────────────────────────
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS arrived_at timestamptz;

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_noshow_wait_minutes', to_jsonb(5),
        'Minutos de espera no pickup antes de o motorista poder marcar "Passageiro não apareceu".',
        'tvde')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.tvde_driver_arrived(p_ride_id uuid)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status NOT IN ('motorista_a_caminho','motorista_atribuido') THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;
  UPDATE public.tvde_rides SET status = 'motorista_chegou', arrived_at = now(), updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor) VALUES (p_ride_id, 'motorista_chegou', 'driver');
  RETURN v_ride;
END; $function$;

-- ── M16 · nome do passageiro (só o motorista da corrida vê) ────────────────
CREATE OR REPLACE FUNCTION public.tvde_ride_passenger_name(p_ride_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_ride public.tvde_rides; v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  SELECT COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data->>'bora_name')
    INTO v_name
  FROM public.users u
  LEFT JOIN auth.users au ON au.id = u.id
  WHERE u.id = v_ride.client_id;
  RETURN v_name;
END; $function$;

REVOKE ALL ON FUNCTION public.tvde_ride_passenger_name(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_ride_passenger_name(uuid) TO authenticated;

-- ── 4a+4d · admin_tvde_drivers_list corrigida (user_id) + estado dual ──────
CREATE OR REPLACE FUNCTION public.admin_tvde_drivers_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        'user_id',         d.user_id,
        'name',            d.name,
        'phone',           d.phone,
        'vehicle_type',    d.vehicle_type,
        'work_mode',       COALESCE(d.work_mode, 'everything'),
        'is_online',       d.is_online,
        'approval_status', d.approval_status,
        'rating',          d.avg_rating,
        'ratings_count',   d.ratings_count,
        'is_banned',       (d.banned_until IS NOT NULL AND d.banned_until > now()) OR COALESCE(d.is_banned, false),
        'banned_until',    d.banned_until,
        'ban_reason',      d.ban_reason,
        'tvde_balance',    COALESCE(b.balance, 0),
        'last_heartbeat_at',   d.last_heartbeat_at,
        'location_updated_at', dl.last_updated,
        'has_fcm_token',       (d.fcm_token IS NOT NULL AND length(d.fcm_token) > 0),
        'active_rides',    (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.user_id
                                AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')),
        'queued_rides',    (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.user_id
                                AND r.is_queued = true AND r.status = 'motorista_atribuido'),
        'total_rides',     (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.user_id AND r.status = 'finalizada'),
        'has_active_delivery', EXISTS (SELECT 1 FROM public.orders o
                              WHERE o.assigned_driver_id = d.id::text
                                AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
      ) AS row
    FROM public.drivers d
    LEFT JOIN public.tvde_driver_balances b ON b.driver_id = d.user_id
    LEFT JOIN public.driver_locations dl ON dl.driver_id = d.user_id
    WHERE d.vehicle_type = 'carro_passageiros'
  ) s;

  RETURN v_out;
END; $function$;

-- ── 4d · corridas ao vivo com is_queued/arrived_at (badge back-to-back) ────
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
