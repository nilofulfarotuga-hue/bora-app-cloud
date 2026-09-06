-- ============================================================================
-- TVDE P0 (2026-07-02) — cliente nao acha motorista / aba sumida / admin
-- ============================================================================
-- Evidencia (2026-07-01 ~23h UTC): motorista 4f61dd31 is_online=true,
-- last_heartbeat_at FRESCO, mas tvde_offer_to_next exigia
-- driver_locations.last_updated fresco — que so atualiza quando o GPS SE MOVE.
-- Motorista parado = invisivel → rides 'sem_motorista' com tried=[].
--
-- 3 correcoes:
--  1) vehicle_type canonico: normaliza as 4 grafias (car, moto,
--     carro_passageiros, motorcycle) + CHECK fechado.
--  2) tvde_offer_to_next: vivo = GPS recente OU heartbeat recente (padrao
--     Uber — heartbeat e a prova de vida; GPS e a ultima posicao conhecida).
--  3) admin: admin_update_driver aceita 'carro_passageiros';
--     admin_tvde_drivers_list expoe heartbeat/GPS/token para diagnostico.

-- ── 1. Normalizacao + CHECK ─────────────────────────────────────────────────
UPDATE public.drivers SET vehicle_type = 'motorcycle'
 WHERE vehicle_type IN ('moto', 'motorbike');
UPDATE public.drivers SET vehicle_type = 'carro_passageiros'
 WHERE vehicle_type = 'carPassengers';
UPDATE public.drivers SET vehicle_type = 'motorcycle'
 WHERE vehicle_type IS NULL
    OR vehicle_type NOT IN ('motorcycle','car','bicycle','carro_passageiros');

ALTER TABLE public.drivers DROP CONSTRAINT IF EXISTS drivers_vehicle_type_canonico;
ALTER TABLE public.drivers ADD CONSTRAINT drivers_vehicle_type_canonico
  CHECK (vehicle_type IN ('motorcycle','car','bicycle','carro_passageiros'));

-- ── 2. Elegibilidade: heartbeat conta como prova de vida ────────────────────
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
    AND (dl.is_online = true OR d.is_online = true)
    -- P0 2026-07-02: motorista PARADO nao gera updates de GPS
    -- (driver_locations.last_updated congela); o heartbeat de 30s
    -- (drivers.last_heartbeat_at) e a prova de vida. Qualquer um fresco = vivo.
    AND GREATEST(COALESCE(dl.last_updated,       '-infinity'::timestamptz),
                 COALESCE(d.last_heartbeat_at,   '-infinity'::timestamptz))
        > now() - make_interval(secs => v_hb)
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

-- ── 3a. admin_update_driver: aceitar o canonico TVDE ────────────────────────
-- (so muda a whitelist do IF de validacao; resto identico ao deployed)
CREATE OR REPLACE FUNCTION public.admin_update_driver(p_driver_id uuid, p_reason text, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_vehicle_type text DEFAULT NULL::text, p_license_plate text DEFAULT NULL::text, p_iban text DEFAULT NULL::text, p_nif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin     RECORD;
  v_driver    RECORD;
  v_changed   TEXT[] := ARRAY[]::TEXT[];
  v_reason_t  TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: update needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;
  v_reason_t := trim(p_reason);

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'driver_deleted: cannot edit soft-deleted driver (reactivate first)'
      USING ERRCODE = '23514';
  END IF;

  IF p_vehicle_type IS NOT NULL
     AND p_vehicle_type NOT IN ('motorcycle', 'car', 'bicycle', 'carro_passageiros') THEN
    RAISE EXCEPTION 'invalid_vehicle_type: % (allowed: motorcycle, car, bicycle, carro_passageiros)',
      p_vehicle_type USING ERRCODE = '22023';
  END IF;

  IF p_name IS NOT NULL AND p_name IS DISTINCT FROM v_driver.name THEN
    UPDATE public.drivers SET name = trim(p_name) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'name',
      v_driver.name, trim(p_name), false, v_reason_t);
    v_changed := array_append(v_changed, 'name');
  END IF;

  IF p_phone IS NOT NULL AND p_phone IS DISTINCT FROM v_driver.phone THEN
    UPDATE public.drivers SET phone = trim(p_phone) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'phone',
      v_driver.phone, trim(p_phone), false, v_reason_t);
    v_changed := array_append(v_changed, 'phone');
  END IF;

  IF p_vehicle_type IS NOT NULL AND p_vehicle_type IS DISTINCT FROM v_driver.vehicle_type THEN
    UPDATE public.drivers SET vehicle_type = p_vehicle_type WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'vehicle_type',
      v_driver.vehicle_type, p_vehicle_type, false, v_reason_t);
    v_changed := array_append(v_changed, 'vehicle_type');
  END IF;

  IF p_license_plate IS NOT NULL AND p_license_plate IS DISTINCT FROM v_driver.license_plate THEN
    UPDATE public.drivers SET license_plate = trim(p_license_plate) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'license_plate',
      v_driver.license_plate, trim(p_license_plate), false, v_reason_t);
    v_changed := array_append(v_changed, 'license_plate');
  END IF;

  IF p_iban IS NOT NULL AND p_iban IS DISTINCT FROM v_driver.iban THEN
    UPDATE public.drivers SET iban = trim(p_iban) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'iban',
      v_driver.iban, trim(p_iban), true, v_reason_t);
    v_changed := array_append(v_changed, 'iban');
  END IF;

  IF p_nif IS NOT NULL AND p_nif IS DISTINCT FROM v_driver.nif THEN
    UPDATE public.drivers SET nif = trim(p_nif) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(
      p_driver_id, v_driver.name, 'nif',
      v_driver.nif, trim(p_nif), true, v_reason_t);
    v_changed := array_append(v_changed, 'nif');
  END IF;

  IF array_length(v_changed, 1) IS NULL THEN
    RAISE EXCEPTION 'no_changes: all provided fields equal current values'
      USING ERRCODE = '23514';
  END IF;

  RETURN jsonb_build_object(
    'success',        true,
    'driver_id',      p_driver_id,
    'fields_changed', v_changed,
    'reason',         v_reason_t,
    'updated_at',     now()
  );
END;
$function$;

-- ── 3b. admin_tvde_drivers_list: telemetria de diagnostico ──────────────────
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
        -- P0 2026-07-02: diagnostico de elegibilidade visivel no admin
        'last_heartbeat_at',   d.last_heartbeat_at,
        'location_updated_at', dl.last_updated,
        'has_fcm_token',       (d.fcm_token IS NOT NULL AND length(d.fcm_token) > 0),
        'active_rides',    (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.id
                                AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')),
        'total_rides',     (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.id AND r.status = 'finalizada')
      ) AS row
    FROM public.drivers d
    LEFT JOIN public.tvde_driver_balances b ON b.driver_id = d.id
    LEFT JOIN public.driver_locations dl ON dl.driver_id = d.user_id
    WHERE d.vehicle_type = 'carro_passageiros'
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_drivers_list() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_drivers_list() TO authenticated;
