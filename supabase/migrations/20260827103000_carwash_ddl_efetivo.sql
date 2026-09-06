-- DDL EFETIVO da Lavagem Auto, extraido da BASE DE PRODUCAO em 2026-08-27.
-- Gerado por _carwash_dump_ddl(): espelho fiel do que esta aplicado.
-- As tabelas/indices/triggers estao em 20260827100000_carwash_engine_2026_08_27.sql
-- Os GRANTs finais estao em 20260827104000_carwash_grants.sql

CREATE OR REPLACE FUNCTION public._carwash_audit(p_action text, p_entity_id uuid, p_details jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (auth.uid(),
          (SELECT email FROM auth.users WHERE id = auth.uid()),
          p_action, 'carwash', p_entity_id, COALESCE(p_details,'{}'::jsonb));
EXCEPTION WHEN OTHERS THEN NULL;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_complete(p_booking_id uuid, p_auto boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b carwash_bookings; v_washer_user uuid;
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'delivered' THEN RETURN; END IF;

  UPDATE carwash_bookings
  SET status = 'completed', completed_at = now(),
      payment_status = CASE
        WHEN payment_method = 'cash' THEN 'cash_pending'
        WHEN payment_status = 'held' THEN 'released'
        ELSE payment_status END
  WHERE id = p_booking_id;

  UPDATE washers SET washes_done = washes_done + 1 WHERE id = v_b.washer_id;
  v_washer_user := (SELECT user_id FROM washers WHERE id = v_b.washer_id);

  -- PONTO DE LIGACAO DOS TOKENS: bloqueado pela Trava (zona vermelha).
  -- Fica por aplicar ate o Danilo dizer "vai". Ver relatorio da missao.

  PERFORM public._carwash_notify_user(v_washer_user, 'carwash_completed',
    CASE WHEN p_auto THEN 'Lavagem auto-confirmada' ELSE 'Lavagem confirmada' END,
    'O cliente confirmou. Ganhos: ' || (v_b.washer_earnings_cents / 100.0)::numeric(10,2) || ' EUR.',
    p_booking_id::text);
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_cron_offer_timeout()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM carwash_bookings
           WHERE status='scheduled' AND offer_washer_id IS NOT NULL AND offer_expires_at < now()
  LOOP
    UPDATE carwash_bookings SET offer_washer_id=NULL, offer_expires_at=NULL WHERE id=r.id;
    PERFORM public._carwash_next_offer(r.id);
  END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_cron_retry_unoffered()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM carwash_bookings
           WHERE status='scheduled' AND offer_washer_id IS NULL
             AND created_at > now() - interval '12 hours'
             AND scheduled_at < now() + interval '2 hours'
  LOOP
    UPDATE carwash_bookings SET offered_washer_ids='{}'::uuid[] WHERE id=r.id;
    PERFORM public._carwash_next_offer(r.id);
  END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_cron_stuck()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN SELECT id, plate, status FROM carwash_bookings
           WHERE status IN ('picked_up','in_progress','delivering')
             AND started_at < now() - interval '4 hours'
             AND stuck_alerted_at IS NULL
  LOOP
    UPDATE carwash_bookings SET stuck_alerted_at=now() WHERE id=r.id;
    PERFORM public._carwash_notify_admin('Lavagem parada ha muito tempo',
      'Pedido ' || r.id::text || ' (' || r.plate || ') esta em ' || r.status || ' ha mais de 4 horas.');
  END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_current_washer()
 RETURNS washers
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v public.washers;
BEGIN
  SELECT * INTO v FROM washers WHERE user_id = auth.uid();
  IF v.id IS NULL THEN
    RAISE EXCEPTION 'not_a_washer' USING ERRCODE = '42501';
  END IF;
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_distance_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) *
    power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$function$
;

CREATE OR REPLACE FUNCTION public._carwash_is_available(p_washer_id uuid, p_start timestamp with time zone, p_duration_min integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_local timestamp := p_start AT TIME ZONE 'Europe/Lisbon';
  v_dow smallint := EXTRACT(dow FROM (p_start AT TIME ZONE 'Europe/Lisbon'))::smallint;
  v_t_start time := (p_start AT TIME ZONE 'Europe/Lisbon')::time;
  v_t_end time;
BEGIN
  v_t_end := (v_local + make_interval(mins => p_duration_min))::time;
  IF (v_local + make_interval(mins => p_duration_min))::date > v_local::date THEN
    RETURN false;
  END IF;

  IF EXISTS (SELECT 1 FROM washer_availability WHERE washer_id = p_washer_id) THEN
    IF NOT EXISTS (
      SELECT 1 FROM washer_availability
      WHERE washer_id = p_washer_id AND weekday = v_dow
        AND start_time <= v_t_start AND end_time >= v_t_end
    ) THEN
      RETURN false;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM carwash_bookings b
    WHERE b.washer_id = p_washer_id
      AND b.status IN ('accepted','on_the_way','picked_up','in_progress','delivering')
      AND tstzrange(b.scheduled_at, b.scheduled_at + make_interval(mins => b.duration_min))
          && tstzrange(p_start, p_start + make_interval(mins => p_duration_min))
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_my_washer_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT id FROM public.washers WHERE user_id = auth.uid() LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public._carwash_next_offer(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b carwash_bookings;
  v_next uuid;
  v_next_user uuid;
  v_timeout int := public._carwash_setting_int('carwash_offer_timeout_min', 10);
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;

  SELECT w.id, w.user_id INTO v_next, v_next_user
  FROM washers w
  WHERE w.approval_status = 'approved' AND w.is_active AND NOT w.is_banned
    AND w.user_id <> v_b.client_user_id
    AND NOT (w.id = ANY (v_b.offered_washer_ids))
    AND (w.base_lat IS NULL OR v_b.lat IS NULL
         OR public._carwash_distance_km(w.base_lat, w.base_lng, v_b.lat, v_b.lng) <= w.service_radius_km)
    AND public._carwash_is_available(w.id, v_b.scheduled_at, v_b.duration_min)
  ORDER BY (w.id = v_b.requested_washer_id) DESC, w.rating_avg DESC, w.washes_done DESC
  LIMIT 1;

  IF v_next IS NULL THEN
    UPDATE carwash_bookings SET offer_washer_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._carwash_notify_admin(
      'Lavagem sem lavador',
      'Pedido ' || p_booking_id::text || ' (' || v_b.plate || ') para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' sem lavador disponivel.');
    RETURN;
  END IF;

  UPDATE carwash_bookings
  SET offer_washer_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_washer_ids = offered_washer_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(
    v_next_user, 'carwash_offer', 'Nova lavagem disponivel',
    'Lavagem ' || CASE v_b.service_type WHEN 'exterior' THEN 'exterior'
                                        WHEN 'full' THEN 'completa'
                                        ELSE 'so interior' END ||
    ' - ' || (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_notify_admin(p_title text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_url text; v_key text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('mode','generic','title',p_title,'body',p_body,'source','carwash')
      );
    ELSE
      INSERT INTO public.notification_failures (user_id, kind, source, erro)
      VALUES (NULL, 'carwash_admin', '_carwash_notify_admin', 'vault project_url/service_role_key em falta');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (NULL, 'carwash_admin', '_carwash_notify_admin', SQLERRM);
  END;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_notify_user(p_user_id uuid, p_kind text, p_title text, p_body text, p_booking_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_url text; v_key text; v_type text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  v_type := CASE WHEN p_kind ILIKE '%offer%' OR p_kind ILIKE '%oferta%'
                 THEN 'carwash_offer' ELSE 'carwash_status' END;

  BEGIN
    PERFORM public._push_in_app_notification(p_user_id, p_kind, p_title, p_body, p_booking_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_kind, '_carwash_notify_user:in_app', SQLERRM);
  END;

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NULL OR v_key IS NULL THEN
      INSERT INTO public.notification_failures (user_id, kind, source, erro)
      VALUES (p_user_id, p_kind, '_carwash_notify_user:fcm', 'vault project_url/service_role_key em falta');
    ELSE
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-washer',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object(
          'targetUserId', p_user_id::text,
          'bookingId', COALESCE(p_booking_id,''),
          'title', p_title, 'body', p_body,
          'kind', p_kind, 'type', v_type)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_kind, '_carwash_notify_user:fcm', SQLERRM);
  END;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_require_admin()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_admin' USING ERRCODE = '42501';
  END IF;
END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_setting_bool(p_key text, p_default boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT (value #>> '{}')::boolean
                   FROM platform_settings WHERE key = p_key), p_default);
$function$
;

CREATE OR REPLACE FUNCTION public._carwash_setting_int(p_key text, p_default integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT (value #>> '{}')::numeric::integer
                   FROM platform_settings WHERE key = p_key), p_default);
$function$
;

CREATE OR REPLACE FUNCTION public._carwash_setting_num(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT (value #>> '{}')::numeric
                   FROM platform_settings WHERE key = p_key), p_default);
$function$
;

CREATE OR REPLACE FUNCTION public._carwash_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.updated_at := now(); RETURN NEW; END $function$
;

CREATE OR REPLACE FUNCTION public._carwash_transition(p_booking_id uuid, p_from text, p_to text, p_ts_col text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_me washers; v_b carwash_bookings;
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> p_from THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;
  EXECUTE format('UPDATE carwash_bookings SET status = $1, %I = now() WHERE id = $2', p_ts_col)
  USING p_to, p_booking_id;
  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_cancel_carwash_booking(p_id uuid, p_reason text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_b carwash_bookings;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;

  UPDATE carwash_bookings
  SET status='cancelled_client', cancelled_at=now(), cancelled_by='admin',
      cancel_reason=COALESCE(p_reason,''), cancel_fee_cents=0,
      offer_washer_id=NULL, offer_expires_at=NULL
  WHERE id = p_id;

  PERFORM public._carwash_audit('carwash_cancel', p_id, jsonb_build_object('reason', p_reason));
  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_cancelled',
    'Lavagem cancelada', 'A tua lavagem foi cancelada pela equipa Bora.', p_id::text);
  IF v_b.washer_id IS NOT NULL THEN
    PERFORM public._carwash_notify_user((SELECT user_id FROM washers WHERE id=v_b.washer_id),
      'carwash_cancelled', 'Lavagem cancelada',
      'A equipa Bora cancelou o pedido (' || v_b.plate || ').', p_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_carwash_booking_detail(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT to_jsonb(b) || jsonb_build_object(
           'washer_name', COALESCE(w.name,''),
           'washer_phone', COALESCE(w.phone,''),
           'client_email', COALESCE((SELECT email FROM auth.users WHERE id = b.client_user_id),''),
           'messages', COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.created_at)
                                 FROM carwash_messages m WHERE m.booking_id = b.id), '[]'::jsonb))
  INTO v
  FROM carwash_bookings b LEFT JOIN washers w ON w.id = b.washer_id
  WHERE b.id = p_id;
  IF v IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_carwash_group_trips(p_from timestamp with time zone, p_to timestamp with time zone, p_radius_km numeric DEFAULT 1.5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public._carwash_require_admin();

  SELECT COALESCE(jsonb_agg(g ORDER BY (g->>'quantos')::int DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT jsonb_build_object(
      'ancora_id', a.id,
      'ancora_morada', a.address_street,
      'ancora_hora', a.scheduled_at,
      'quantos', count(*) FILTER (WHERE b.id IS NOT NULL) + 1,
      'perto', COALESCE(jsonb_agg(jsonb_build_object(
                 'id', b.id, 'plate', b.plate, 'morada', b.address_street,
                 'hora', b.scheduled_at, 'servico', b.service_type,
                 'km', round(public._carwash_distance_km(a.lat,a.lng,b.lat,b.lng)::numeric, 2)
               ) ORDER BY b.scheduled_at) FILTER (WHERE b.id IS NOT NULL), '[]'::jsonb),
      'total_cents', a.total_cents + COALESCE(sum(b.total_cents) FILTER (WHERE b.id IS NOT NULL), 0)
    ) AS g
    FROM carwash_bookings a
    LEFT JOIN carwash_bookings b
      ON b.id <> a.id
     AND b.scheduled_at BETWEEN p_from AND p_to
     AND b.status IN ('scheduled','accepted')
     AND b.lat IS NOT NULL AND a.lat IS NOT NULL
     AND public._carwash_distance_km(a.lat, a.lng, b.lat, b.lng) <= p_radius_km
    WHERE a.scheduled_at BETWEEN p_from AND p_to
      AND a.status IN ('scheduled','accepted')
    GROUP BY a.id, a.address_street, a.scheduled_at, a.total_cents
  ) s
  WHERE (g->>'quantos')::int > 1;

  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_carwash_recalc_settlement(p_washer_id uuid, p_week_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_start timestamptz := (p_week_start::timestamp AT TIME ZONE 'Europe/Lisbon');
  v_end   timestamptz := ((p_week_start + 7)::timestamp AT TIME ZONE 'Europe/Lisbon');
  v_jobs int; v_earn int; v_fee int; v_id uuid;
BEGIN
  PERFORM public._carwash_require_admin();

  SELECT count(*), COALESCE(sum(washer_earnings_cents),0), COALESCE(sum(bora_fee_cents),0)
  INTO v_jobs, v_earn, v_fee
  FROM carwash_bookings
  WHERE washer_id = p_washer_id AND status = 'completed'
    AND completed_at >= v_start AND completed_at < v_end
    AND NOT is_test_order;

  INSERT INTO washer_weekly_settlements (washer_id, week_start_at, week_end_at,
    total_jobs, total_earnings_cents, total_bora_fee_cents, net_payout_cents, status)
  VALUES (p_washer_id, v_start, v_end, v_jobs, v_earn, v_fee, v_earn, 'pending')
  ON CONFLICT (washer_id, week_start_at) DO UPDATE
    SET total_jobs = EXCLUDED.total_jobs,
        total_earnings_cents = EXCLUDED.total_earnings_cents,
        total_bora_fee_cents = EXCLUDED.total_bora_fee_cents,
        net_payout_cents = EXCLUDED.net_payout_cents
  RETURNING id INTO v_id;

  PERFORM public._carwash_audit('carwash_settlement_recalc', v_id,
    jsonb_build_object('washer', p_washer_id, 'semana', p_week_start, 'jobs', v_jobs));

  RETURN (SELECT to_jsonb(s) FROM washer_weekly_settlements s WHERE s.id = v_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_carwash_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'key', key, 'value', value, 'description', description) ORDER BY key), '[]'::jsonb)
  INTO v FROM platform_settings WHERE key LIKE 'carwash%';
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_create_carwash_booking(p_service_type text, p_plate text, p_client_phone text, p_scheduled_at timestamp with time zone, p_address_street text, p_address_city text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_payment_method text DEFAULT 'cash'::text, p_car_make_model text DEFAULT ''::text, p_car_color text DEFAULT ''::text, p_pickup_notes text DEFAULT ''::text, p_notes text DEFAULT ''::text, p_client_user_id uuid DEFAULT NULL::uuid, p_washer_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_quote jsonb; v_id uuid; v_client uuid;
BEGIN
  PERFORM public._carwash_require_admin();
  v_client := COALESCE(p_client_user_id, auth.uid());
  v_quote := public.carwash_quote(p_service_type);

  INSERT INTO carwash_bookings (
    client_user_id, service_type, plate, car_make_model, car_color, pickup_notes,
    client_phone, when_mode, scheduled_at, duration_min,
    address_street, address_city, lat, lng, notes,
    payment_method, payment_status, base_cents, total_cents,
    washer_earnings_cents, bora_fee_cents,
    washer_id, status, accepted_at
  ) VALUES (
    v_client, p_service_type, upper(trim(p_plate)), p_car_make_model, p_car_color, p_pickup_notes,
    p_client_phone, 'later', p_scheduled_at, (v_quote->>'duration_min')::int,
    p_address_street, p_address_city, p_lat, p_lng, p_notes,
    p_payment_method, 'unpaid', (v_quote->>'base_cents')::int, (v_quote->>'total_cents')::int,
    (v_quote->>'washer_earnings_cents')::int, (v_quote->>'bora_fee_cents')::int,
    p_washer_id,
    CASE WHEN p_washer_id IS NULL THEN 'scheduled' ELSE 'accepted' END,
    CASE WHEN p_washer_id IS NULL THEN NULL ELSE now() END
  ) RETURNING id INTO v_id;

  PERFORM public._carwash_audit('carwash_create_walkin', v_id,
    jsonb_build_object('plate', upper(trim(p_plate)), 'service', p_service_type));

  IF p_washer_id IS NULL THEN PERFORM public._carwash_next_offer(v_id); END IF;

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = v_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_export_carwash_csv(p_from date, p_to date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v text;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT 'id,data,estado,servico,matricula,carro,morada,telefone,lavador,total_eur,bora_eur,lavador_eur,pagamento' ||
         E'\n' || COALESCE(string_agg(
    b.id::text || ',' ||
    to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI') || ',' ||
    b.status || ',' || b.service_type || ',' || b.plate || ',' ||
    '"' || replace(b.car_make_model,'"','""') || '",' ||
    '"' || replace(b.address_street,'"','""') || '",' ||
    b.client_phone || ',' ||
    '"' || replace(COALESCE(w.name,''),'"','""') || '",' ||
    (b.total_cents/100.0)::numeric(10,2) || ',' ||
    (b.bora_fee_cents/100.0)::numeric(10,2) || ',' ||
    (b.washer_earnings_cents/100.0)::numeric(10,2) || ',' ||
    b.payment_method, E'\n' ORDER BY b.scheduled_at), '')
  INTO v
  FROM carwash_bookings b LEFT JOIN washers w ON w.id = b.washer_id
  WHERE (b.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date BETWEEN p_from AND p_to;
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_list_carwash_bookings(p_status text DEFAULT NULL::text, p_day date DEFAULT NULL::date, p_washer_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_rows jsonb; v_total int;
BEGIN
  PERFORM public._carwash_require_admin();

  SELECT count(*) INTO v_total FROM carwash_bookings b
  WHERE (p_status IS NULL OR b.status = p_status)
    AND (p_day IS NULL OR (b.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date = p_day)
    AND (p_washer_id IS NULL OR b.washer_id = p_washer_id)
    AND (p_search IS NULL OR p_search = '' OR
         b.plate ILIKE '%'||p_search||'%' OR
         b.car_make_model ILIKE '%'||p_search||'%' OR
         b.address_street ILIKE '%'||p_search||'%' OR
         b.client_phone ILIKE '%'||p_search||'%');

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'scheduled_at' DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT to_jsonb(b) || jsonb_build_object(
             'washer_name', COALESCE(w.name,''),
             'washer_phone', COALESCE(w.phone,'')) AS x
    FROM carwash_bookings b
    LEFT JOIN washers w ON w.id = b.washer_id
    WHERE (p_status IS NULL OR b.status = p_status)
      AND (p_day IS NULL OR (b.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date = p_day)
      AND (p_washer_id IS NULL OR b.washer_id = p_washer_id)
      AND (p_search IS NULL OR p_search = '' OR
           b.plate ILIKE '%'||p_search||'%' OR
           b.car_make_model ILIKE '%'||p_search||'%' OR
           b.address_street ILIKE '%'||p_search||'%' OR
           b.client_phone ILIKE '%'||p_search||'%')
    ORDER BY b.scheduled_at DESC
    LIMIT p_limit OFFSET p_offset
  ) s;

  RETURN jsonb_build_object('total', v_total, 'rows', v_rows);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_list_carwash_settlements(p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT COALESCE(jsonb_agg(to_jsonb(s) || jsonb_build_object('washer_name', w.name)
                            ORDER BY s.week_start_at DESC), '[]'::jsonb) INTO v
  FROM washer_weekly_settlements s JOIN washers w ON w.id = s.washer_id
  WHERE (p_status IS NULL OR s.status = p_status);
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_mark_carwash_settlement_paid(p_id uuid, p_method text DEFAULT 'mbway'::text, p_reference text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public._carwash_require_admin();
  UPDATE washer_weekly_settlements
  SET status='paid', paid_at=now(), paid_by=auth.uid(),
      payment_method=p_method, payment_reference=p_reference
  WHERE id = p_id;
  PERFORM public._carwash_audit('carwash_settlement_paid', p_id,
    jsonb_build_object('metodo', p_method, 'referencia', p_reference));
  RETURN (SELECT to_jsonb(s) FROM washer_weekly_settlements s WHERE s.id = p_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_reassign_carwash_booking(p_id uuid, p_washer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_b carwash_bookings; v_old uuid; v_new washers;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status IN ('completed','cancelled_client') THEN
    RAISE EXCEPTION 'cannot_reassign_from_%', v_b.status;
  END IF;

  SELECT * INTO v_new FROM washers WHERE id = p_washer_id;
  IF v_new.id IS NULL THEN RAISE EXCEPTION 'washer_not_found'; END IF;
  IF v_new.approval_status <> 'approved' OR NOT v_new.is_active OR v_new.is_banned THEN
    RAISE EXCEPTION 'washer_not_available';
  END IF;

  v_old := v_b.washer_id;

  UPDATE carwash_bookings
  SET washer_id = p_washer_id,
      status = CASE WHEN status = 'scheduled' THEN 'accepted' ELSE status END,
      accepted_at = COALESCE(accepted_at, now()),
      offer_washer_id = NULL, offer_expires_at = NULL,
      offered_washer_ids = CASE WHEN p_washer_id = ANY (offered_washer_ids)
                                THEN offered_washer_ids ELSE offered_washer_ids || p_washer_id END
  WHERE id = p_id;

  PERFORM public._carwash_audit('carwash_reassign', p_id,
    jsonb_build_object('de', v_old, 'para', p_washer_id));

  PERFORM public._carwash_notify_user(v_new.user_id, 'carwash_assigned',
    'Lavagem atribuida a ti',
    'A equipa Bora passou-te o pedido (' || v_b.plate || ').', p_id::text);
  IF v_old IS NOT NULL AND v_old <> p_washer_id THEN
    PERFORM public._carwash_notify_user((SELECT user_id FROM washers WHERE id=v_old),
      'carwash_unassigned', 'Lavagem reatribuida',
      'O pedido (' || v_b.plate || ') passou para outro lavador.', p_id::text);
  END IF;
  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_reassigned',
    'Novo lavador', v_new.name || ' vai tratar do teu carro.', p_id::text);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_set_carwash_setting(p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_old jsonb;
BEGIN
  PERFORM public._carwash_require_admin();
  IF p_key NOT LIKE 'carwash%' THEN
    RAISE EXCEPTION 'only_carwash_settings';
  END IF;
  SELECT value INTO v_old FROM platform_settings WHERE key = p_key;

  INSERT INTO platform_settings (key, value, category, updated_at, updated_by)
  VALUES (p_key, p_value, 'carwash', now(), auth.uid())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = now(), updated_by = auth.uid();

  PERFORM public._carwash_audit('carwash_setting', NULL,
    jsonb_build_object('key', p_key, 'de', v_old, 'para', p_value));

  RETURN jsonb_build_object('key', p_key, 'value', p_value);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_update_carwash_booking(p_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_b carwash_bookings;
BEGIN
  PERFORM public._carwash_require_admin();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;

  UPDATE carwash_bookings SET
    plate           = COALESCE(upper(trim(p_patch->>'plate')), plate),
    car_make_model  = COALESCE(p_patch->>'car_make_model', car_make_model),
    car_color       = COALESCE(p_patch->>'car_color', car_color),
    pickup_notes    = COALESCE(p_patch->>'pickup_notes', pickup_notes),
    client_phone    = COALESCE(p_patch->>'client_phone', client_phone),
    address_street  = COALESCE(p_patch->>'address_street', address_street),
    address_city    = COALESCE(p_patch->>'address_city', address_city),
    address_postal  = COALESCE(p_patch->>'address_postal', address_postal),
    notes           = COALESCE(p_patch->>'notes', notes),
    scheduled_at    = COALESCE((p_patch->>'scheduled_at')::timestamptz, scheduled_at),
    lat             = COALESCE((p_patch->>'lat')::double precision, lat),
    lng             = COALESCE((p_patch->>'lng')::double precision, lng)
  WHERE id = p_id;

  PERFORM public._carwash_audit('carwash_update', p_id, p_patch);

  IF p_patch ? 'scheduled_at' THEN
    PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_rescheduled',
      'Lavagem reagendada',
      'A tua lavagem passou para ' ||
      to_char((p_patch->>'scheduled_at')::timestamptz AT TIME ZONE 'Europe/Lisbon', 'DD/MM as HH24:MI') || '.',
      p_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.cancel_carwash_booking(p_booking_id uuid, p_reason text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_b carwash_bookings; v_me washers; v_is_client boolean;
  v_free_min int := public._carwash_setting_int('carwash_cancel_free_min', 15);
  v_mins numeric; v_fee int := 0;
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted','on_the_way') THEN
    RAISE EXCEPTION 'cannot_cancel_from_%', v_b.status;
  END IF;

  v_is_client := (v_b.client_user_id = v_uid);
  IF NOT v_is_client THEN
    v_me := public._carwash_current_washer();
    IF v_b.washer_id IS DISTINCT FROM v_me.id AND v_b.offer_washer_id IS DISTINCT FROM v_me.id THEN
      RAISE EXCEPTION 'booking_not_yours';
    END IF;
  END IF;

  IF v_is_client THEN
    v_mins := EXTRACT(epoch FROM (now() - v_b.created_at)) / 60.0;
    IF v_mins <= v_free_min OR v_b.status = 'scheduled' THEN
      v_fee := 0;
    ELSE
      v_fee := round(v_b.total_cents * 0.5)::int;
    END IF;

    UPDATE carwash_bookings
    SET status='cancelled_client', cancelled_at=now(), cancelled_by='client',
        cancel_reason=COALESCE(p_reason,''), cancel_fee_cents=v_fee,
        payment_status = CASE
          WHEN payment_method='cash' AND v_fee > 0 THEN 'cash_pending'
          WHEN payment_status='held' THEN 'estornado'
          ELSE payment_status END,
        offer_washer_id=NULL, offer_expires_at=NULL
    WHERE id = p_booking_id;

    IF v_b.washer_id IS NOT NULL THEN
      PERFORM public._carwash_notify_user(
        (SELECT user_id FROM washers WHERE id = v_b.washer_id),
        'carwash_cancelled', 'Lavagem cancelada',
        'O cliente cancelou o pedido (' || v_b.plate || ').', p_booking_id::text);
    END IF;
  ELSE
    UPDATE carwash_bookings
    SET status='scheduled', washer_id=NULL, accepted_at=NULL,
        eta_minutes=NULL, eta_at=NULL,
        offer_washer_id=NULL, offer_expires_at=NULL,
        offered_washer_ids = CASE WHEN v_me.id = ANY (offered_washer_ids)
                                  THEN offered_washer_ids ELSE offered_washer_ids || v_me.id END
    WHERE id = p_booking_id;

    INSERT INTO washer_cancel_events (washer_id, booking_id, was_late)
    VALUES (v_me.id, p_booking_id, v_b.status <> 'scheduled');

    PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_reassigning',
      'A procurar outro lavador',
      'O lavador teve um imprevisto. Estamos a procurar outro para o teu carro.', p_booking_id::text);
    PERFORM public._carwash_next_offer(p_booking_id);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_confirm_completion(p_booking_id uuid, p_rating integer DEFAULT NULL::integer, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_b carwash_bookings;
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL OR v_b.client_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;

  IF p_rating IS NOT NULL THEN
    UPDATE carwash_bookings SET rating = p_rating, rating_comment = p_comment WHERE id = p_booking_id;
    UPDATE washers SET
      rating_avg = ((rating_avg * ratings_count) + p_rating) / (ratings_count + 1),
      ratings_count = ratings_count + 1,
      flagged_low_rating = (((rating_avg * ratings_count) + p_rating) / (ratings_count + 1)) < 3.5
    WHERE id = v_b.washer_id;
  END IF;

  PERFORM public._carwash_complete(p_booking_id, false);
  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_mark_delivered(p_booking_id uuid, p_photos jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_me washers; v_b carwash_bookings;
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> 'delivering' THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;

  UPDATE carwash_bookings
  SET status = 'delivered', delivered_at = now(), done_at = now(),
      photos_after = CASE WHEN jsonb_array_length(COALESCE(p_photos,'[]'::jsonb)) > 0
                          THEN p_photos ELSE photos_after END
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_delivered',
    'Carro entregue', 'O carro foi entregue lavado. Confirma na app para fechar o pedido.',
    p_booking_id::text);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_mark_delivering(p_booking_id uuid, p_photos jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_me washers; v_b carwash_bookings;
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> 'in_progress' THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;

  UPDATE carwash_bookings
  SET status = 'delivering', delivering_at = now(),
      photos_after = CASE WHEN jsonb_array_length(COALESCE(p_photos,'[]'::jsonb)) > 0
                          THEN p_photos ELSE photos_after END
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_delivering',
    'A entregar o carro', 'O carro esta lavado e a caminho de volta.', p_booking_id::text);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_mark_on_the_way(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  v := public._carwash_transition(p_booking_id, 'accepted', 'on_the_way', 'on_the_way_at');
  PERFORM public._carwash_notify_user((v ->> 'client_user_id')::uuid, 'carwash_on_the_way',
    'A caminho do carro', 'O lavador esta a caminho para recolher o carro.', p_booking_id::text);
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_mark_picked_up(p_booking_id uuid, p_photos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_me washers; v_b carwash_bookings; v_ang text; v_missing text[] := '{}';
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> 'on_the_way' THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;

  FOREACH v_ang IN ARRAY ARRAY['frente','tras','esquerda','direita'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(p_photos,'[]'::jsonb)) e
      WHERE e ->> 'angle' = v_ang AND COALESCE(e ->> 'url','') <> ''
    ) THEN
      v_missing := v_missing || v_ang;
    END IF;
  END LOOP;
  IF array_length(v_missing, 1) > 0 THEN
    RAISE EXCEPTION 'missing_photos: %', array_to_string(v_missing, ', ');
  END IF;

  UPDATE carwash_bookings
  SET status = 'picked_up', picked_up_at = now(), photos_before = p_photos
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_picked_up',
    'Carro recolhido', 'O lavador recolheu o carro e ja tirou as fotos.', p_booking_id::text);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_mark_started(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  v := public._carwash_transition(p_booking_id, 'picked_up', 'in_progress', 'started_at');
  PERFORM public._carwash_notify_user((v ->> 'client_user_id')::uuid, 'carwash_started',
    'A lavar o carro', 'A lavagem comecou.', p_booking_id::text);
  RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION public.carwash_quote(p_service_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_base int; v_total int; v_bora_pct int; v_bora int; v_washer int; v_duration int;
BEGIN
  IF p_service_type NOT IN ('exterior','full','interior') THEN
    RAISE EXCEPTION 'invalid_service_type';
  END IF;
  IF p_service_type = 'interior'
     AND NOT public._carwash_setting_bool('carwash_interior_enabled', false) THEN
    RAISE EXCEPTION 'service_not_enabled';
  END IF;

  v_base := CASE p_service_type
    WHEN 'exterior' THEN public._carwash_setting_int('carwash_price_exterior_cents', 1200)
    WHEN 'full'     THEN public._carwash_setting_int('carwash_price_full_cents', 2000)
    ELSE                 public._carwash_setting_int('carwash_price_interior_cents', 1200)
  END;

  v_total := v_base;

  v_duration := COALESCE((SELECT (value ->> p_service_type)::int
                          FROM platform_settings WHERE key='carwash_duration_min'), 60);

  v_bora_pct := public._carwash_setting_int('carwash_bora_pct', 15);
  v_bora     := round(v_total * v_bora_pct / 100.0)::int;
  v_washer   := v_total - v_bora;

  RETURN jsonb_build_object(
    'service_type', p_service_type,
    'base_cents', v_base,
    'total_cents', v_total,
    'washer_earnings_cents', v_washer,
    'bora_fee_cents', v_bora,
    'duration_min', v_duration
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.create_carwash_booking(p_service_type text, p_plate text, p_client_phone text, p_when_mode text, p_scheduled_at timestamp with time zone, p_address_street text, p_address_city text, p_address_postal text, p_lat double precision, p_lng double precision, p_payment_method text, p_car_make_model text DEFAULT ''::text, p_car_color text DEFAULT ''::text, p_pickup_notes text DEFAULT ''::text, p_notes text DEFAULT ''::text, p_photos_client jsonb DEFAULT '[]'::jsonb, p_requested_washer_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_quote jsonb;
  v_id uuid;
  v_when timestamptz;
  v_radius numeric := public._carwash_setting_num('carwash_service_radius_km', 8);
  v_blat double precision := public._carwash_setting_num('carwash_base_lat', 40.5373);
  v_blng double precision := public._carwash_setting_num('carwash_base_lng', -7.2676);
  v_dist double precision;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public._carwash_setting_bool('carwash_enabled', true) THEN
    RAISE EXCEPTION 'carwash_disabled';
  END IF;

  IF p_when_mode NOT IN ('now','later') THEN RAISE EXCEPTION 'invalid_when_mode'; END IF;
  IF p_payment_method NOT IN ('card','mbway','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_payment_method IN ('card','mbway')
     AND NOT public._carwash_setting_bool('carwash_stripe_enabled', true) THEN
    RAISE EXCEPTION 'card_mbway_not_enabled';
  END IF;
  IF COALESCE(trim(p_plate),'') = '' THEN RAISE EXCEPTION 'plate_required'; END IF;
  IF COALESCE(trim(p_client_phone),'') = '' THEN RAISE EXCEPTION 'phone_required'; END IF;

  v_when := CASE WHEN p_when_mode = 'now' THEN now() ELSE p_scheduled_at END;
  IF v_when IS NULL THEN RAISE EXCEPTION 'scheduled_at_required'; END IF;
  IF p_when_mode = 'later' AND v_when < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'scheduled_in_the_past';
  END IF;

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_dist := public._carwash_distance_km(v_blat, v_blng, p_lat, p_lng);
    IF v_dist > v_radius THEN
      RAISE EXCEPTION 'out_of_service_area (%.1f km)', v_dist;
    END IF;
  END IF;

  IF p_requested_washer_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM washers WHERE id = p_requested_washer_id
                     AND approval_status='approved' AND is_active AND NOT is_banned) THEN
      RAISE EXCEPTION 'washer_not_available';
    END IF;
  END IF;

  v_quote := public.carwash_quote(p_service_type);

  INSERT INTO carwash_bookings (
    client_user_id, requested_washer_id, service_type, plate, car_make_model, car_color,
    pickup_notes, client_phone, when_mode, scheduled_at, duration_min,
    address_street, address_city, address_postal, lat, lng, notes,
    payment_method, payment_status, photos_client,
    base_cents, total_cents, washer_earnings_cents, bora_fee_cents
  ) VALUES (
    v_uid, p_requested_washer_id, p_service_type, upper(trim(p_plate)),
    COALESCE(p_car_make_model,''), COALESCE(p_car_color,''),
    COALESCE(p_pickup_notes,''), trim(p_client_phone), p_when_mode, v_when,
    (v_quote ->> 'duration_min')::int,
    COALESCE(p_address_street,''), COALESCE(p_address_city,''), COALESCE(p_address_postal,''),
    p_lat, p_lng, COALESCE(p_notes,''),
    p_payment_method, 'unpaid', COALESCE(p_photos_client,'[]'::jsonb),
    (v_quote ->> 'base_cents')::int, (v_quote ->> 'total_cents')::int,
    (v_quote ->> 'washer_earnings_cents')::int, (v_quote ->> 'bora_fee_cents')::int
  ) RETURNING id INTO v_id;

  PERFORM public._carwash_notify_admin(
    'Nova Lavagem Auto',
    'Pedido novo (' || upper(trim(p_plate)) || ') - ' ||
    ((v_quote ->> 'total_cents')::int / 100.0)::numeric(10,2) || ' EUR, ' ||
    CASE p_when_mode WHEN 'now' THEN 'para agora' ELSE 'agendado' END || '.');

  PERFORM public._carwash_next_offer(v_id);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = v_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.washer_accept_booking(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me washers; v_b carwash_bookings;
  v_dist double precision; v_eta int;
  v_buffer int := public._carwash_setting_int('carwash_eta_buffer_min', 10);
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status <> 'scheduled' OR v_b.offer_washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'offer_not_yours_or_expired';
  END IF;
  IF v_b.offer_expires_at IS NOT NULL AND v_b.offer_expires_at < now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;

  IF v_me.base_lat IS NOT NULL AND v_b.lat IS NOT NULL THEN
    v_dist := public._carwash_distance_km(v_me.base_lat, v_me.base_lng, v_b.lat, v_b.lng);
    v_eta  := ceil(((v_dist / 25.0) * 60.0 + v_buffer) / 5.0)::int * 5;
  ELSE
    v_eta := ceil((15 + v_buffer) / 5.0)::int * 5;
  END IF;

  UPDATE carwash_bookings
  SET status = 'accepted', washer_id = v_me.id, accepted_at = now(),
      eta_minutes = v_eta, eta_at = now() + make_interval(mins => v_eta),
      offer_washer_id = NULL, offer_expires_at = NULL
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_accepted',
    'Lavador a caminho',
    v_me.name || ' aceitou. Chega por volta das ' ||
    to_char((now() + make_interval(mins => v_eta)) AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') || '.',
    p_booking_id::text);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.washer_reject_booking(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_me washers; v_b carwash_bookings;
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status <> 'scheduled' OR v_b.offer_washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'offer_not_yours_or_expired';
  END IF;

  UPDATE carwash_bookings SET offer_washer_id = NULL, offer_expires_at = NULL
  WHERE id = p_booking_id;

  PERFORM public._carwash_next_offer(p_booking_id);
END $function$
;

DROP POLICY IF EXISTS carwash_bookings_admin_all ON public.carwash_bookings;
CREATE POLICY carwash_bookings_admin_all ON public.carwash_bookings FOR ALL TO public
  USING (is_admin())
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS carwash_bookings_select_own ON public.carwash_bookings;
CREATE POLICY carwash_bookings_select_own ON public.carwash_bookings FOR SELECT TO authenticated
  USING (((client_user_id = auth.uid()) OR (washer_id = _carwash_my_washer_id()) OR (offer_washer_id = _carwash_my_washer_id()) OR is_admin()));

DROP POLICY IF EXISTS carwash_bookings_update_own ON public.carwash_bookings;
CREATE POLICY carwash_bookings_update_own ON public.carwash_bookings FOR UPDATE TO authenticated
  USING (((client_user_id = auth.uid()) OR (washer_id = _carwash_my_washer_id()) OR (offer_washer_id = _carwash_my_washer_id()) OR is_admin()))
  WITH CHECK (((client_user_id = auth.uid()) OR (washer_id = _carwash_my_washer_id()) OR (offer_washer_id = _carwash_my_washer_id()) OR is_admin()));

DROP POLICY IF EXISTS carwash_messages_insert_participant ON public.carwash_messages;
CREATE POLICY carwash_messages_insert_participant ON public.carwash_messages FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM carwash_bookings b
  WHERE ((b.id = carwash_messages.booking_id) AND (b.status = ANY (ARRAY['accepted'::text, 'on_the_way'::text, 'picked_up'::text, 'in_progress'::text, 'delivering'::text, 'delivered'::text])) AND (((carwash_messages.sender_role = 'client'::text) AND (b.client_user_id = auth.uid())) OR ((carwash_messages.sender_role = 'washer'::text) AND (b.washer_id = _carwash_my_washer_id())))))));

DROP POLICY IF EXISTS carwash_messages_select_participant ON public.carwash_messages;
CREATE POLICY carwash_messages_select_participant ON public.carwash_messages FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM carwash_bookings b
  WHERE ((b.id = carwash_messages.booking_id) AND ((b.client_user_id = auth.uid()) OR (b.washer_id = _carwash_my_washer_id()) OR is_admin())))));

DROP POLICY IF EXISTS washer_avail_own ON public.washer_availability;
CREATE POLICY washer_avail_own ON public.washer_availability FOR ALL TO authenticated
  USING (((washer_id = _carwash_my_washer_id()) OR is_admin()))
  WITH CHECK (((washer_id = _carwash_my_washer_id()) OR is_admin()));

DROP POLICY IF EXISTS washers_admin_all ON public.washers;
CREATE POLICY washers_admin_all ON public.washers FOR ALL TO public
  USING (is_admin())
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS washers_select_own ON public.washers;
CREATE POLICY washers_select_own ON public.washers FOR SELECT TO authenticated
  USING (((user_id = auth.uid()) OR is_admin()));

DROP POLICY IF EXISTS washers_update_own ON public.washers;
CREATE POLICY washers_update_own ON public.washers FOR UPDATE TO authenticated
  USING (((user_id = auth.uid()) OR is_admin()))
  WITH CHECK (((user_id = auth.uid()) OR is_admin()));

DROP POLICY IF EXISTS wce_select ON public.washer_cancel_events;
CREATE POLICY wce_select ON public.washer_cancel_events FOR SELECT TO authenticated
  USING (((washer_id = _carwash_my_washer_id()) OR is_admin()));

DROP POLICY IF EXISTS wce_write ON public.washer_cancel_events;
CREATE POLICY wce_write ON public.washer_cancel_events FOR ALL TO public
  USING (is_admin())
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS wws_select ON public.washer_weekly_settlements;
CREATE POLICY wws_select ON public.washer_weekly_settlements FOR SELECT TO authenticated
  USING (((washer_id = _carwash_my_washer_id()) OR is_admin()));

DROP POLICY IF EXISTS wws_write ON public.washer_weekly_settlements;
CREATE POLICY wws_write ON public.washer_weekly_settlements FOR ALL TO public
  USING (is_admin())
  WITH CHECK (is_admin());