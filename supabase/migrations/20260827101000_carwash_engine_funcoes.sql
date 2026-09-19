-- =====================================================================
-- CARWASH ENGINE - funcoes (motor)  |  2026-08-27
-- Molde: funcoes _cleaning_* / cleaning_* (NAO tocadas).
-- =====================================================================

-- ---------- settings (Bloco B) ----------
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('carwash_enabled',              'true'::jsonb,  'Lavagem Auto ligada (liga/desliga o servico todo)', 'carwash'),
  ('carwash_price_exterior_cents', '1200'::jsonb,  'Preco da Lavagem exterior, em centimos',            'carwash'),
  ('carwash_price_full_cents',     '2000'::jsonb,  'Preco da Lavagem completa, em centimos',            'carwash'),
  ('carwash_price_interior_cents', '1200'::jsonb,  'Preco da lavagem So interior, em centimos',         'carwash'),
  ('carwash_interior_enabled',     'false'::jsonb, 'So interior visivel ao cliente (comeca desligado)', 'carwash'),
  ('carwash_bora_pct',             '15'::jsonb,    'Percentagem da Bora sobre o total',                 'carwash'),
  ('carwash_offer_timeout_min',    '10'::jsonb,    'Minutos que o lavador tem para aceitar a oferta',    'carwash'),
  ('carwash_eta_buffer_min',       '10'::jsonb,    'Minutos somados ao ETA (prometer a mais)',          'carwash'),
  ('carwash_service_radius_km',    '8'::jsonb,     'Raio de servico em km a partir do centro',          'carwash'),
  ('carwash_duration_min',         '{"exterior":60,"full":110,"interior":50}'::jsonb, 'Duracao por servico, em minutos', 'carwash'),
  ('carwash_cancel_free_min',      '15'::jsonb,    'Minutos apos o pedido em que cancelar e gratis',    'carwash'),
  ('carwash_base_lat',             '40.5373'::jsonb, 'Latitude do centro da zona de servico (Guarda)',  'carwash'),
  ('carwash_base_lng',             '-7.2676'::jsonb, 'Longitude do centro da zona de servico (Guarda)', 'carwash'),
  ('carwash_stripe_enabled',       'true'::jsonb,  'Cartao e MB WAY ligados na Lavagem Auto',           'carwash')
ON CONFLICT (key) DO NOTHING;

-- ---------- helpers ----------
CREATE OR REPLACE FUNCTION public._carwash_setting_int(p_key text, p_default integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT COALESCE((SELECT (value #>> '{}')::numeric::integer
                   FROM platform_settings WHERE key = p_key), p_default);
$fn$;

CREATE OR REPLACE FUNCTION public._carwash_setting_bool(p_key text, p_default boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT COALESCE((SELECT (value #>> '{}')::boolean
                   FROM platform_settings WHERE key = p_key), p_default);
$fn$;

CREATE OR REPLACE FUNCTION public._carwash_setting_num(p_key text, p_default numeric)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT COALESCE((SELECT (value #>> '{}')::numeric
                   FROM platform_settings WHERE key = p_key), p_default);
$fn$;

CREATE OR REPLACE FUNCTION public._carwash_distance_km(lat1 double precision, lng1 double precision,
                                                       lat2 double precision, lng2 double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $fn$
  SELECT 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) *
    power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$fn$;

CREATE OR REPLACE FUNCTION public._carwash_current_washer()
RETURNS public.washers LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v public.washers;
BEGIN
  SELECT * INTO v FROM washers WHERE user_id = auth.uid();
  IF v.id IS NULL THEN
    RAISE EXCEPTION 'not_a_washer' USING ERRCODE = '42501';
  END IF;
  RETURN v;
END $fn$;

-- ---------- notificacoes (DATA-ONLY do lado da Edge Function) ----------
CREATE OR REPLACE FUNCTION public._carwash_notify_admin(p_title text, p_body text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

CREATE OR REPLACE FUNCTION public._carwash_notify_user(p_user_id uuid, p_kind text, p_title text,
                                                       p_body text, p_booking_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

-- ---------- disponibilidade ----------
CREATE OR REPLACE FUNCTION public._carwash_is_available(p_washer_id uuid, p_start timestamptz, p_duration_min integer)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
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

  -- Sem horario definido = disponivel sempre (o lavador so restringe se quiser).
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
END $fn$;

-- ---------- oferta rotativa ----------
CREATE OR REPLACE FUNCTION public._carwash_next_offer(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

-- ---------- orcamento (fonte unica do preco) ----------
CREATE OR REPLACE FUNCTION public.carwash_quote(p_service_type text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
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

  -- Preco final ao cliente: sem taxas por cima.
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
END $fn$;

-- ---------- criar pedido ----------
CREATE OR REPLACE FUNCTION public.create_carwash_booking(
  p_service_type text,
  p_plate text,
  p_client_phone text,
  p_when_mode text,
  p_scheduled_at timestamptz,
  p_address_street text,
  p_address_city text,
  p_address_postal text,
  p_lat double precision,
  p_lng double precision,
  p_payment_method text,
  p_car_make_model text DEFAULT '',
  p_car_color text DEFAULT '',
  p_pickup_notes text DEFAULT '',
  p_notes text DEFAULT '',
  p_photos_client jsonb DEFAULT '[]'::jsonb,
  p_requested_washer_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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

  -- BLOQUEIO ANTES DE QUALQUER COBRANCA (licao 31/07)
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

  -- Raio de servico (so valida quando ha coordenadas; morada escrita a mao nunca trava)
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
END $fn$;

-- ---------- aceitar / recusar (com ETA) ----------
CREATE OR REPLACE FUNCTION public.washer_accept_booking(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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

  -- ETA: distancia -> 25 km/h urbano -> + buffer -> arredonda para cima a 5 min
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
END $fn$;

CREATE OR REPLACE FUNCTION public.washer_reject_booking(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

-- ---------- transicoes ----------
CREATE OR REPLACE FUNCTION public._carwash_transition(p_booking_id uuid, p_from text, p_to text, p_ts_col text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

CREATE OR REPLACE FUNCTION public.carwash_mark_on_the_way(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v jsonb;
BEGIN
  v := public._carwash_transition(p_booking_id, 'accepted', 'on_the_way', 'on_the_way_at');
  PERFORM public._carwash_notify_user((v ->> 'client_user_id')::uuid, 'carwash_on_the_way',
    'A caminho do carro', 'O lavador esta a caminho para recolher o carro.', p_booking_id::text);
  RETURN v;
END $fn$;

-- Recolha: as 4 fotos sao OBRIGATORIAS e validadas NO SERVIDOR.
CREATE OR REPLACE FUNCTION public.carwash_mark_picked_up(p_booking_id uuid, p_photos jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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

  -- Exige as 4 fotos, uma por angulo, com url nao vazia.
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
END $fn$;

CREATE OR REPLACE FUNCTION public.carwash_mark_started(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v jsonb;
BEGIN
  v := public._carwash_transition(p_booking_id, 'picked_up', 'in_progress', 'started_at');
  PERFORM public._carwash_notify_user((v ->> 'client_user_id')::uuid, 'carwash_started',
    'A lavar o carro', 'A lavagem comecou.', p_booking_id::text);
  RETURN v;
END $fn$;

CREATE OR REPLACE FUNCTION public.carwash_mark_delivering(p_booking_id uuid, p_photos jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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

  -- Fotos do "depois" sao OPCIONAIS.
  UPDATE carwash_bookings
  SET status = 'delivering', delivering_at = now(),
      photos_after = CASE WHEN jsonb_array_length(COALESCE(p_photos,'[]'::jsonb)) > 0
                          THEN p_photos ELSE photos_after END
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_delivering',
    'A entregar o carro', 'O carro esta lavado e a caminho de volta.', p_booking_id::text);

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $fn$;

CREATE OR REPLACE FUNCTION public.carwash_mark_delivered(p_booking_id uuid, p_photos jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

-- ---------- fecho ----------
CREATE OR REPLACE FUNCTION public._carwash_complete(p_booking_id uuid, p_auto boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
  -- Fica por aplicar ate o Danilo dizer "vai".
  -- Proposta pronta em: 20260827102000_PROPOSTA_carwash_tokens.sql

  PERFORM public._carwash_notify_user(v_washer_user, 'carwash_completed',
    CASE WHEN p_auto THEN 'Lavagem auto-confirmada' ELSE 'Lavagem confirmada' END,
    'O cliente confirmou. Ganhos: ' || (v_b.washer_earnings_cents / 100.0)::numeric(10,2) || ' EUR.',
    p_booking_id::text);
END $fn$;

CREATE OR REPLACE FUNCTION public.carwash_confirm_completion(p_booking_id uuid, p_rating integer DEFAULT NULL,
                                                             p_comment text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

-- ---------- cancelamento ----------
CREATE OR REPLACE FUNCTION public.cancel_carwash_booking(p_booking_id uuid, p_reason text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
    -- Gratis dentro da janela, ou enquanto ninguem aceitou.
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
    -- Lavador desiste: volta a fila, regista evento, procura outro.
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
END $fn$;

-- ---------- webhook de pagamento (molde do confirm_cleaning_payment_webhook) ----------
CREATE OR REPLACE FUNCTION public.confirm_carwash_payment_webhook(p_booking_id uuid,
                                                                  p_payment_intent_id text,
                                                                  p_amount_cents integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_booking record;
BEGIN
  SELECT * INTO v_booking FROM public.carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
  END IF;
  IF v_booking.payment_status <> 'unpaid' THEN
    RETURN jsonb_build_object('ok', true, 'already_marked', true,
                              'payment_status', v_booking.payment_status);
  END IF;
  IF COALESCE(v_booking.total_cents, 0) <> COALESCE(p_amount_cents, -1) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'amount_mismatch',
                              'expected', v_booking.total_cents, 'received', p_amount_cents);
  END IF;

  UPDATE public.carwash_bookings
  SET payment_status = 'held', stripe_payment_intent_id = p_payment_intent_id
  WHERE id = p_booking_id AND payment_status = 'unpaid';

  RETURN jsonb_build_object('ok', true, 'booking_id', p_booking_id);
END $fn$;

-- ---------- crons ----------
CREATE OR REPLACE FUNCTION public._carwash_cron_offer_timeout()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM carwash_bookings
           WHERE status='scheduled' AND offer_washer_id IS NOT NULL AND offer_expires_at < now()
  LOOP
    UPDATE carwash_bookings SET offer_washer_id=NULL, offer_expires_at=NULL WHERE id=r.id;
    PERFORM public._carwash_next_offer(r.id);
  END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION public._carwash_cron_retry_unoffered()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r record;
BEGIN
  -- Pedidos sem oferta activa (esgotou a lista) voltam a tentar de raiz.
  FOR r IN SELECT id FROM carwash_bookings
           WHERE status='scheduled' AND offer_washer_id IS NULL
             AND created_at > now() - interval '12 hours'
             AND scheduled_at < now() + interval '2 hours'
  LOOP
    UPDATE carwash_bookings SET offered_washer_ids='{}'::uuid[] WHERE id=r.id;
    PERFORM public._carwash_next_offer(r.id);
  END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION public._carwash_cron_stuck()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
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
END $fn$;

-- ---------- permissoes ----------
GRANT EXECUTE ON FUNCTION public.carwash_quote(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.create_carwash_booking(text,text,text,text,timestamptz,text,text,text,double precision,double precision,text,text,text,text,text,jsonb,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.washer_accept_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.washer_reject_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_on_the_way(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_picked_up(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_started(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_delivering(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_delivered(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_confirm_completion(uuid,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_carwash_booking(uuid,text) TO authenticated;
