-- ============================================================================
-- LIMPEZA — RPCs core (SECURITY DEFINER, preço 100% server-side)
-- Scheduler próprio "cleaning dispatch" por agendamento (rotation 30 min),
-- SEM tocar no motor de despacho. Push: in-app + FCM via Vault/pg_net
-- (padrão appointments/_appt_notify_client).
-- ============================================================================

-- ---------- helpers de settings ----------
CREATE OR REPLACE FUNCTION public._cleaning_setting_int(p_key text, p_default integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::numeric::integer
                   FROM platform_settings WHERE key = p_key), p_default);
$$;
REVOKE ALL ON FUNCTION public._cleaning_setting_int(text, integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_setting_int(text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public._cleaning_setting_bool(p_key text, p_default boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::boolean
                   FROM platform_settings WHERE key = p_key), p_default);
$$;
REVOKE ALL ON FUNCTION public._cleaning_setting_bool(text, boolean) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_setting_bool(text, boolean) TO service_role;

-- ---------- distância (haversine, km) ----------
CREATE OR REPLACE FUNCTION public._cleaning_distance_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) *
    power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- ---------- notificação (in-app + FCM notify-client via Vault) ----------
CREATE OR REPLACE FUNCTION public._cleaning_notify_user(
  p_user_id uuid, p_kind text, p_title text, p_body text, p_booking_id text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_url text; v_key text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(p_user_id, p_kind, p_title, p_body, p_booking_id);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('clientId', p_user_id::text,
                                   'reservationId', COALESCE(p_booking_id,''),
                                   'title', p_title, 'body', p_body,
                                   'kind', p_kind, 'type', 'cleaning_status')
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_notify_user(uuid, text, text, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_notify_user(uuid, text, text, text, text) TO service_role;

-- aviso ao admin (in-system, fire-and-forget)
CREATE OR REPLACE FUNCTION public._cleaning_notify_admin(p_title text, p_body text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_url text; v_key text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('mode','generic','title',p_title,'body',p_body,'source','cleaning')
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_notify_admin(text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_notify_admin(text, text) TO service_role;

-- ---------- profissional autenticada ----------
CREATE OR REPLACE FUNCTION public._cleaning_current_cleaner()
RETURNS public.cleaners LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v public.cleaners;
BEGIN
  SELECT * INTO v FROM cleaners WHERE user_id = auth.uid();
  IF v.id IS NULL THEN
    RAISE EXCEPTION 'not_a_cleaner' USING ERRCODE = '42501';
  END IF;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_current_cleaner() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_current_cleaner() TO service_role;

-- ---------- orçamento server-side ----------
-- Devolve o breakdown em cents. Regras (Danilo 2026-07-05):
--   fixo por tamanho (T0/T1 35 · T2 45 · T3 55 · T4+ 70) OU por hora (12/h, mín 2h)
--   profunda +40% · pós-obras +60% (aplica-se a fixo E por hora — escolha documentada)
--   recorrência semanal/quinzenal -10% · produtos da profissional +3 (100% dela)
--   split: Bora 15% sobre (total - produtos); profissional recebe o resto + produtos
CREATE OR REPLACE FUNCTION public.cleaning_quote(
  p_cleaning_type text,
  p_pricing_mode  text,
  p_home_size     text DEFAULT NULL,
  p_hours         integer DEFAULT NULL,
  p_recurrence    text DEFAULT 'single',
  p_products_by   text DEFAULT 'client'
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_base int; v_pct int := 0; v_surcharge int; v_subtotal int;
  v_discount int := 0; v_products int := 0; v_total int;
  v_bora_pct int; v_bora int; v_cleaner int;
  v_min_hours int; v_duration int;
BEGIN
  IF p_cleaning_type NOT IN ('standard','deep','post_works') THEN
    RAISE EXCEPTION 'invalid_cleaning_type';
  END IF;
  IF p_pricing_mode NOT IN ('fixed','hourly') THEN
    RAISE EXCEPTION 'invalid_pricing_mode';
  END IF;
  IF p_recurrence NOT IN ('single','weekly','biweekly') THEN
    RAISE EXCEPTION 'invalid_recurrence';
  END IF;
  IF p_products_by NOT IN ('client','cleaner') THEN
    RAISE EXCEPTION 'invalid_products_by';
  END IF;

  IF p_pricing_mode = 'fixed' THEN
    IF p_home_size IS NULL OR p_home_size NOT IN ('t0_t1','t2','t3','t4plus') THEN
      RAISE EXCEPTION 'invalid_home_size';
    END IF;
    v_base := CASE p_home_size
      WHEN 't0_t1'  THEN public._cleaning_setting_int('cleaning_price_t0_t1_cents', 3500)
      WHEN 't2'     THEN public._cleaning_setting_int('cleaning_price_t2_cents', 4500)
      WHEN 't3'     THEN public._cleaning_setting_int('cleaning_price_t3_cents', 5500)
      ELSE               public._cleaning_setting_int('cleaning_price_t4plus_cents', 7000)
    END;
    v_duration := COALESCE((SELECT (value ->> p_home_size)::int
                            FROM platform_settings WHERE key='cleaning_durations_min'), 180);
  ELSE
    v_min_hours := public._cleaning_setting_int('cleaning_min_hours', 2);
    IF p_hours IS NULL OR p_hours < v_min_hours OR p_hours > 12 THEN
      RAISE EXCEPTION 'invalid_hours (min %)', v_min_hours;
    END IF;
    v_base := public._cleaning_setting_int('cleaning_hourly_cents', 1200) * p_hours;
    v_duration := p_hours * 60;
  END IF;

  IF p_cleaning_type = 'deep' THEN
    v_pct := public._cleaning_setting_int('cleaning_deep_pct', 40);
  ELSIF p_cleaning_type = 'post_works' THEN
    v_pct := public._cleaning_setting_int('cleaning_postworks_pct', 60);
  END IF;
  v_surcharge := round(v_base * v_pct / 100.0)::int;
  v_subtotal  := v_base + v_surcharge;

  IF p_recurrence IN ('weekly','biweekly') THEN
    v_discount := round(v_subtotal *
      public._cleaning_setting_int('cleaning_recurring_discount_pct', 10) / 100.0)::int;
  END IF;

  IF p_products_by = 'cleaner' THEN
    v_products := public._cleaning_setting_int('cleaning_products_fee_cents', 300);
  END IF;

  v_total    := v_subtotal - v_discount + v_products;
  v_bora_pct := public._cleaning_setting_int('cleaning_bora_pct', 15);
  v_bora     := round((v_total - v_products) * v_bora_pct / 100.0)::int;
  v_cleaner  := v_total - v_bora;  -- inclui 100% dos produtos

  RETURN jsonb_build_object(
    'base_cents', v_base,
    'type_surcharge_cents', v_surcharge,
    'recurring_discount_cents', v_discount,
    'products_fee_cents', v_products,
    'total_cents', v_total,
    'cleaner_earnings_cents', v_cleaner,
    'bora_fee_cents', v_bora,
    'duration_min', v_duration
  );
END $$;
REVOKE ALL ON FUNCTION public.cleaning_quote(text, text, text, integer, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_quote(text, text, text, integer, text, text) TO authenticated;

-- ---------- disponibilidade de uma profissional num slot ----------
CREATE OR REPLACE FUNCTION public._cleaning_is_available(
  p_cleaner_id uuid, p_start timestamptz, p_duration_min integer
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_local timestamp := p_start AT TIME ZONE 'Europe/Lisbon';
  v_dow smallint := EXTRACT(dow FROM v_local)::smallint;  -- 0=domingo
  v_t_start time := v_local::time;
  v_t_end time;
  v_overnight boolean := false;
BEGIN
  v_t_end := (v_local + make_interval(mins => p_duration_min))::time;
  IF (v_local + make_interval(mins => p_duration_min))::date > v_local::date THEN
    v_overnight := true;  -- atravessa meia-noite → fora de qualquer janela diária
  END IF;
  IF v_overnight THEN RETURN false; END IF;

  -- 1) janela semanal cobre o serviço inteiro
  IF NOT EXISTS (
    SELECT 1 FROM cleaner_availability
    WHERE cleaner_id = p_cleaner_id AND weekday = v_dow
      AND start_time <= v_t_start AND end_time >= v_t_end
  ) THEN
    RETURN false;
  END IF;

  -- 2) sem sobreposição com limpezas já aceites
  IF EXISTS (
    SELECT 1 FROM cleaning_bookings b
    WHERE b.cleaner_id = p_cleaner_id
      AND b.status IN ('accepted','on_the_way','in_progress')
      AND tstzrange(b.scheduled_at, b.scheduled_at + make_interval(mins => b.duration_min))
          && tstzrange(p_start, p_start + make_interval(mins => p_duration_min))
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_is_available(uuid, timestamptz, integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_is_available(uuid, timestamptz, integer) TO service_role;

-- ---------- lista de profissionais disponíveis (Passo 3 do wizard) ----------
CREATE OR REPLACE FUNCTION public.cleaning_list_available_cleaners(
  p_scheduled_at timestamptz,
  p_duration_min integer,
  p_lat double precision,
  p_lng double precision
) RETURNS TABLE (
  id uuid, name text, photo_url text, bio text,
  rating_avg numeric, ratings_count integer, cleanings_done integer,
  is_favorite boolean
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT c.id, c.name, c.photo_url, c.bio,
         c.rating_avg, c.ratings_count, c.cleanings_done,
         EXISTS (
           SELECT 1 FROM cleaning_bookings b
           WHERE b.cleaner_id = c.id AND b.client_user_id = auth.uid()
             AND b.status = 'completed'
         ) AS is_favorite
  FROM cleaners c
  WHERE c.approval_status = 'approved'
    AND c.is_active
    AND c.user_id <> auth.uid()
    AND (c.base_lat IS NULL OR p_lat IS NULL
         OR public._cleaning_distance_km(c.base_lat, c.base_lng, p_lat, p_lng) <= c.service_radius_km)
    AND public._cleaning_is_available(c.id, p_scheduled_at, p_duration_min)
  ORDER BY 8 DESC, c.rating_avg DESC, c.cleanings_done DESC;
END $$;
REVOKE ALL ON FUNCTION public.cleaning_list_available_cleaners(timestamptz, integer, double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_list_available_cleaners(timestamptz, integer, double precision, double precision) TO authenticated;

-- ---------- rotation: oferecer à próxima profissional ----------
CREATE OR REPLACE FUNCTION public._cleaning_next_offer(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_b cleaning_bookings;
  v_next uuid;
  v_timeout int := public._cleaning_setting_int('cleaning_offer_timeout_min', 30);
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;

  -- 1º a escolhida pelo cliente (favorita), depois melhores por rating
  SELECT c.id INTO v_next
  FROM cleaners c
  WHERE c.approval_status = 'approved' AND c.is_active
    AND c.user_id <> v_b.client_user_id
    AND NOT (c.id = ANY (v_b.offered_cleaner_ids))
    AND (c.base_lat IS NULL OR v_b.lat IS NULL
         OR public._cleaning_distance_km(c.base_lat, c.base_lng, v_b.lat, v_b.lng) <= c.service_radius_km)
    AND public._cleaning_is_available(c.id, v_b.scheduled_at, v_b.duration_min)
  ORDER BY (c.id = v_b.requested_cleaner_id) DESC, c.rating_avg DESC, c.cleanings_done DESC
  LIMIT 1;

  IF v_next IS NULL THEN
    UPDATE cleaning_bookings
    SET offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._cleaning_notify_admin(
      'Limpeza sem profissional',
      'Reserva ' || p_booking_id::text || ' para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' sem profissional disponível.');
    RETURN;
  END IF;

  UPDATE cleaning_bookings
  SET offer_cleaner_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_cleaner_ids = offered_cleaner_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public._cleaning_notify_user(
    (SELECT user_id FROM cleaners WHERE id = v_next),
    'cleaning_offer', 'Nova limpeza disponível',
    'Limpeza a ' || to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
    ' — ' || (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $$;
REVOKE ALL ON FUNCTION public._cleaning_next_offer(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_next_offer(uuid) TO service_role;

-- ---------- criar reserva (preço SEMPRE server-side) ----------
CREATE OR REPLACE FUNCTION public.create_cleaning_booking(
  p_cleaning_type text,
  p_pricing_mode  text,
  p_home_size     text,
  p_hours         integer,
  p_scheduled_at  timestamptz,
  p_recurrence    text,
  p_products_by   text,
  p_payment_method text,
  p_address_street text,
  p_address_city   text,
  p_address_postal text,
  p_lat            double precision,
  p_lng            double precision,
  p_notes          text DEFAULT '',
  p_requested_cleaner_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_quote jsonb;
  v_lead int := public._cleaning_setting_int('cleaning_min_lead_hours', 12);
  v_id uuid;
  v_group uuid := NULL;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public._cleaning_setting_bool('cleaning_enabled', true) THEN
    RAISE EXCEPTION 'cleaning_disabled';
  END IF;
  IF p_scheduled_at < now() + make_interval(hours => v_lead) THEN
    RAISE EXCEPTION 'lead_time_too_short (min % h)', v_lead;
  END IF;
  IF p_payment_method NOT IN ('card','mbway','cash') THEN
    RAISE EXCEPTION 'invalid_payment_method';
  END IF;
  IF p_payment_method IN ('card','mbway')
     AND NOT public._cleaning_setting_bool('cleaning_stripe_enabled', false) THEN
    RAISE EXCEPTION 'card_mbway_not_yet_enabled';
  END IF;
  IF p_requested_cleaner_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cleaners
                   WHERE id = p_requested_cleaner_id
                     AND approval_status = 'approved' AND is_active) THEN
      RAISE EXCEPTION 'cleaner_not_available';
    END IF;
  END IF;

  v_quote := public.cleaning_quote(p_cleaning_type, p_pricing_mode, p_home_size,
                                   p_hours, p_recurrence, p_products_by);

  IF p_recurrence IN ('weekly','biweekly') THEN
    v_group := gen_random_uuid();
  END IF;

  INSERT INTO cleaning_bookings (
    client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
    cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
    address_street, address_city, address_postal, lat, lng, notes, products_by,
    payment_method, payment_status,
    base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
    total_cents, cleaner_earnings_cents, bora_fee_cents
  ) VALUES (
    v_uid, p_requested_cleaner_id, v_group, p_recurrence,
    p_cleaning_type, p_pricing_mode, p_home_size,
    CASE WHEN p_pricing_mode = 'hourly' THEN p_hours END,
    p_scheduled_at, (v_quote ->> 'duration_min')::int,
    COALESCE(p_address_street,''), COALESCE(p_address_city,''), COALESCE(p_address_postal,''),
    p_lat, p_lng, COALESCE(p_notes,''), p_products_by,
    p_payment_method, 'unpaid',
    (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
    (v_quote ->> 'recurring_discount_cents')::int, (v_quote ->> 'products_fee_cents')::int,
    (v_quote ->> 'total_cents')::int, (v_quote ->> 'cleaner_earnings_cents')::int,
    (v_quote ->> 'bora_fee_cents')::int
  ) RETURNING id INTO v_id;

  PERFORM public._cleaning_next_offer(v_id);

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = v_id);
END $$;
REVOKE ALL ON FUNCTION public.create_cleaning_booking(text, text, text, integer, timestamptz, text, text, text, text, text, text, double precision, double precision, text, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_cleaning_booking(text, text, text, integer, timestamptz, text, text, text, text, text, text, double precision, double precision, text, uuid) TO authenticated;

-- ---------- profissional aceita / recusa ----------
CREATE OR REPLACE FUNCTION public.cleaner_accept_booking(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me cleaners; v_b cleaning_bookings;
BEGIN
  v_me := public._cleaning_current_cleaner();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status <> 'scheduled' OR v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'offer_not_yours_or_expired';
  END IF;
  IF v_b.offer_expires_at IS NOT NULL AND v_b.offer_expires_at < now() THEN
    RAISE EXCEPTION 'offer_expired';
  END IF;

  UPDATE cleaning_bookings
  SET status = 'accepted', cleaner_id = v_me.id, accepted_at = now(),
      offer_cleaner_id = NULL, offer_expires_at = NULL
  WHERE id = p_booking_id;

  PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_accepted',
    'Limpeza confirmada 🎉',
    v_me.name || ' confirmou a tua limpeza de ' ||
    to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') || '.',
    p_booking_id::text);

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public.cleaner_accept_booking(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaner_accept_booking(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleaner_reject_booking(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me cleaners; v_b cleaning_bookings;
BEGIN
  v_me := public._cleaning_current_cleaner();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status <> 'scheduled' OR v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'offer_not_yours_or_expired';
  END IF;

  UPDATE cleaning_bookings
  SET offer_cleaner_id = NULL, offer_expires_at = NULL
  WHERE id = p_booking_id;

  PERFORM public._cleaning_next_offer(p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public.cleaner_reject_booking(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaner_reject_booking(uuid) TO authenticated;

-- ---------- progresso da limpeza (a caminho / iniciar / concluir) ----------
CREATE OR REPLACE FUNCTION public._cleaning_transition(
  p_booking_id uuid, p_from text, p_to text, p_ts_col text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me cleaners; v_b cleaning_bookings;
BEGIN
  v_me := public._cleaning_current_cleaner();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.cleaner_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> p_from THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;
  EXECUTE format(
    'UPDATE cleaning_bookings SET status = $1, %I = now() WHERE id = $2', p_ts_col)
  USING p_to, p_booking_id;
  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public._cleaning_transition(uuid, text, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_transition(uuid, text, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.cleaning_mark_on_the_way(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  v := public._cleaning_transition(p_booking_id, 'accepted', 'on_the_way', 'on_the_way_at');
  PERFORM public._cleaning_notify_user((v ->> 'client_user_id')::uuid, 'cleaning_on_the_way',
    'A caminho 🚗', 'A tua profissional está a caminho.', p_booking_id::text);
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.cleaning_mark_on_the_way(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_mark_on_the_way(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleaning_mark_started(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  v := public._cleaning_transition(p_booking_id, 'on_the_way', 'in_progress', 'started_at');
  PERFORM public._cleaning_notify_user((v ->> 'client_user_id')::uuid, 'cleaning_started',
    'Limpeza iniciada 🧽', 'A tua limpeza começou.', p_booking_id::text);
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.cleaning_mark_started(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_mark_started(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleaning_mark_done(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  v := public._cleaning_transition(p_booking_id, 'in_progress', 'done', 'done_at');
  PERFORM public._cleaning_notify_user((v ->> 'client_user_id')::uuid, 'cleaning_done',
    'Limpeza concluída ✅',
    'A profissional marcou a limpeza como concluída. Confirma na app para libertar o pagamento.',
    p_booking_id::text);
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.cleaning_mark_done(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_mark_done(uuid) TO authenticated;

-- ---------- cliente confirma conclusão (liberta pagamento) ----------
CREATE OR REPLACE FUNCTION public._cleaning_complete(p_booking_id uuid, p_auto boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'done' THEN RETURN; END IF;

  UPDATE cleaning_bookings
  SET status = 'completed', completed_at = now(),
      payment_status = CASE
        WHEN payment_method = 'cash' THEN 'cash_pending'      -- 15% entra no acerto semanal
        WHEN payment_status = 'held' THEN 'released'          -- captura real: Edge Fn (Lista Vermelha)
        ELSE payment_status
      END
  WHERE id = p_booking_id;

  UPDATE cleaners SET cleanings_done = cleanings_done + 1 WHERE id = v_b.cleaner_id;

  PERFORM public._cleaning_notify_user(
    (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
    'cleaning_completed',
    CASE WHEN p_auto THEN 'Limpeza auto-confirmada 💚' ELSE 'Limpeza confirmada 💚' END,
    'O cliente confirmou a limpeza. Ganhos: ' ||
    (v_b.cleaner_earnings_cents / 100.0)::numeric(10,2) || ' EUR.',
    p_booking_id::text);
END $$;
REVOKE ALL ON FUNCTION public._cleaning_complete(uuid, boolean) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_complete(uuid, boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.client_confirm_cleaning(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL OR v_b.client_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> 'done' THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;
  PERFORM public._cleaning_complete(p_booking_id, false);
  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public.client_confirm_cleaning(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_confirm_cleaning(uuid) TO authenticated;

-- ---------- cancelamento (janelas + penalização profissional) ----------
-- Cliente:  >24h grátis · 24h–2h 50% · <2h 100% (profissional recebe 85% da taxa)
-- Profissional: sem custo p/ cliente; <24h conta p/ suspensão (3 em 30d);
--               re-oferece a reserva às restantes. No-show do cliente (após a
--               hora marcada, pela profissional): taxa 100%.
CREATE OR REPLACE FUNCTION public.cancel_cleaning_booking(
  p_booking_id uuid, p_reason text DEFAULT '', p_no_show boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b cleaning_bookings;
  v_me cleaners;
  v_is_client boolean;
  v_hours numeric;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_half int := public._cleaning_setting_int('cleaning_cancel_half_hours', 2);
  v_fee int := 0;
  v_late boolean := false;
  v_late_count int;
  v_limit int := public._cleaning_setting_int('cleaning_late_cancel_limit', 3);
  v_bora_pct int := public._cleaning_setting_int('cleaning_bora_pct', 15);
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted','on_the_way') THEN
    RAISE EXCEPTION 'cannot_cancel_from_%', v_b.status;
  END IF;

  v_is_client := (v_b.client_user_id = v_uid);
  IF NOT v_is_client THEN
    v_me := public._cleaning_current_cleaner();
    IF v_b.cleaner_id IS DISTINCT FROM v_me.id
       AND v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
      RAISE EXCEPTION 'booking_not_yours';
    END IF;
  END IF;

  v_hours := EXTRACT(epoch FROM (v_b.scheduled_at - now())) / 3600.0;

  IF v_is_client THEN
    IF v_hours >= v_free THEN v_fee := 0;
    ELSIF v_hours >= v_half THEN v_fee := round(v_b.total_cents * 0.5)::int;
    ELSE v_fee := v_b.total_cents;
    END IF;

    UPDATE cleaning_bookings
    SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
        cancel_reason = COALESCE(p_reason,''), cancel_fee_cents = v_fee,
        payment_status = CASE
          WHEN payment_method = 'cash' AND v_fee > 0 THEN 'cash_pending'
          WHEN payment_status = 'held' THEN 'estornado'   -- estorno real: Edge Fn (Lista Vermelha)
          ELSE payment_status
        END,
        offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;

    IF v_b.cleaner_id IS NOT NULL THEN
      PERFORM public._cleaning_notify_user(
        (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
        'cleaning_cancelled', 'Limpeza cancelada',
        'O cliente cancelou a limpeza de ' ||
        to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
        CASE WHEN v_fee > 0
             THEN '. Recebes ' || (round(v_fee * (100 - v_bora_pct) / 100.0) / 100.0)::numeric(10,2) || ' EUR de compensação.'
             ELSE '.' END,
        p_booking_id::text);
    END IF;

  ELSE
    -- profissional cancela (ou marca no-show do cliente)
    IF p_no_show THEN
      IF now() < v_b.scheduled_at THEN
        RAISE EXCEPTION 'no_show_only_after_scheduled_time';
      END IF;
      v_fee := v_b.total_cents;
      UPDATE cleaning_bookings
      SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'cleaner',
          cancel_reason = COALESCE(NULLIF(p_reason,''), 'no_show_cliente'),
          cancel_fee_cents = v_fee, no_show_client = true,
          payment_status = CASE
            WHEN payment_method = 'cash' THEN 'cash_pending'
            WHEN payment_status = 'held' THEN 'released'
            ELSE payment_status END
      WHERE id = p_booking_id;
      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_no_show',
        'Limpeza marcada como não comparência',
        'A profissional não conseguiu aceder à morada à hora marcada. Foi aplicada a taxa prevista.',
        p_booking_id::text);
    ELSE
      v_late := (v_hours < v_free);
      UPDATE cleaning_bookings
      SET status = 'scheduled', cleaner_id = NULL, accepted_at = NULL,
          cancelled_late = v_late OR cancelled_late,
          offer_cleaner_id = NULL, offer_expires_at = NULL,
          offered_cleaner_ids = CASE WHEN v_me.id = ANY (offered_cleaner_ids)
                                     THEN offered_cleaner_ids
                                     ELSE offered_cleaner_ids || v_me.id END
      WHERE id = p_booking_id;

      -- registo de penalização da profissional (contador 30 dias)
      IF v_late THEN
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, true);
        SELECT count(*) INTO v_late_count FROM cleaner_cancel_events
        WHERE cleaner_id = v_me.id AND was_late AND created_at > now() - interval '30 days';
        IF v_late_count >= v_limit THEN
          UPDATE cleaners SET approval_status = 'suspended' WHERE id = v_me.id;
          PERFORM public._cleaning_notify_admin('Profissional suspensa automaticamente',
            v_me.name || ' atingiu ' || v_late_count || ' cancelamentos tardios em 30 dias.');
          PERFORM public._cleaning_notify_user(v_me.user_id, 'cleaner_suspended',
            'Conta suspensa para revisão',
            'Atingiste o limite de cancelamentos tardios. A equipa Bora vai rever a tua conta.',
            NULL);
        END IF;
      ELSE
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, false);
      END IF;

      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_reassigning',
        'A tua limpeza vai ser reatribuída',
        'A profissional cancelou. Estamos a procurar outra profissional para o mesmo horário.',
        p_booking_id::text);
      PERFORM public._cleaning_next_offer(p_booking_id);
    END IF;
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $$;
REVOKE ALL ON FUNCTION public.cancel_cleaning_booking(uuid, text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cancel_cleaning_booking(uuid, text, boolean) TO authenticated;

-- eventos de cancelamento da profissional (para o contador 30d)
CREATE TABLE IF NOT EXISTS public.cleaner_cancel_events (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cleaner_id UUID NOT NULL REFERENCES public.cleaners(id) ON DELETE CASCADE,
  booking_id UUID,
  was_late   BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cleaner_cancel_events ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_cleaner_cancel_events ON public.cleaner_cancel_events (cleaner_id, created_at DESC);

-- ---------- avaliação obrigatória dos dois lados ----------
CREATE OR REPLACE FUNCTION public.cleaning_submit_rating(
  p_booking_id uuid, p_stars smallint, p_comment text DEFAULT ''
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b cleaning_bookings;
  v_subject_type text;
  v_subject_id text;
  v_avg numeric; v_cnt int;
BEGIN
  IF p_stars IS NULL OR p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'invalid_stars';
  END IF;
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('done','completed') THEN
    RAISE EXCEPTION 'booking_not_finished';
  END IF;

  IF v_b.client_user_id = v_uid THEN
    v_subject_type := 'cleaner';
    v_subject_id := v_b.cleaner_id::text;
  ELSIF EXISTS (SELECT 1 FROM cleaners WHERE id = v_b.cleaner_id AND user_id = v_uid) THEN
    v_subject_type := 'cleaning_client';
    v_subject_id := v_b.client_user_id::text;
  ELSE
    RAISE EXCEPTION 'booking_not_yours';
  END IF;

  IF EXISTS (SELECT 1 FROM ratings
             WHERE order_id = p_booking_id AND rater_user_id = v_uid) THEN
    RAISE EXCEPTION 'already_rated';
  END IF;

  INSERT INTO ratings (order_id, rater_user_id, subject_type, subject_id, stars, comment)
  VALUES (p_booking_id, v_uid, v_subject_type, v_subject_id, p_stars, NULLIF(p_comment,''));

  -- agregados + flag qualidade (média <4.0 nos últimos 10 serviços)
  IF v_subject_type = 'cleaner' THEN
    SELECT avg(stars)::numeric(3,2), count(*) INTO v_avg, v_cnt
    FROM ratings WHERE subject_type = 'cleaner' AND subject_id = v_subject_id;
    UPDATE cleaners SET rating_avg = COALESCE(v_avg,0), ratings_count = COALESCE(v_cnt,0)
    WHERE id = v_b.cleaner_id;

    SELECT avg(stars) INTO v_avg FROM (
      SELECT stars FROM ratings
      WHERE subject_type = 'cleaner' AND subject_id = v_subject_id
      ORDER BY created_at DESC LIMIT 10
    ) t;
    IF v_cnt >= 10 AND v_avg < 4.0 THEN
      UPDATE cleaners SET flagged_low_rating = true WHERE id = v_b.cleaner_id;
      PERFORM public._cleaning_notify_admin('Profissional com nota baixa',
        'Média ' || round(v_avg,2) || ' nos últimos 10 serviços — rever no painel.');
    END IF;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.cleaning_submit_rating(uuid, smallint, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_submit_rating(uuid, smallint, text) TO authenticated;

-- ---------- candidatura e perfil da profissional ----------
CREATE OR REPLACE FUNCTION public.cleaner_apply(
  p_name text, p_phone text, p_email text, p_nif text,
  p_bio text DEFAULT '', p_photo_url text DEFAULT '',
  p_base_address text DEFAULT '', p_base_lat double precision DEFAULT NULL,
  p_base_lng double precision DEFAULT NULL, p_service_radius_km numeric DEFAULT 10,
  p_docs jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_existing cleaners; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF length(trim(COALESCE(p_name,''))) < 3 THEN RAISE EXCEPTION 'name_required'; END IF;
  IF length(trim(COALESCE(p_phone,''))) < 9 THEN RAISE EXCEPTION 'phone_required'; END IF;

  SELECT * INTO v_existing FROM cleaners WHERE user_id = v_uid;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.approval_status IN ('pending','approved') THEN
      RAISE EXCEPTION 'application_already_exists';
    END IF;
    -- rejeitada/suspensa → recandidatura (volta a pending)
    UPDATE cleaners
    SET name = p_name, phone = p_phone, email = COALESCE(p_email,''), nif = COALESCE(p_nif,''),
        bio = COALESCE(p_bio,''), photo_url = COALESCE(p_photo_url,''),
        base_address = COALESCE(p_base_address,''), base_lat = p_base_lat, base_lng = p_base_lng,
        service_radius_km = COALESCE(p_service_radius_km, 10), docs = COALESCE(p_docs,'{}'::jsonb),
        approval_status = 'pending', rejection_reason = NULL
    WHERE id = v_existing.id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO cleaners (user_id, name, phone, email, nif, bio, photo_url,
                          base_address, base_lat, base_lng, service_radius_km, docs)
    VALUES (v_uid, p_name, p_phone, COALESCE(p_email,''), COALESCE(p_nif,''),
            COALESCE(p_bio,''), COALESCE(p_photo_url,''), COALESCE(p_base_address,''),
            p_base_lat, p_base_lng, COALESCE(p_service_radius_km, 10), COALESCE(p_docs,'{}'::jsonb))
    RETURNING id INTO v_id;
  END IF;

  PERFORM public._cleaning_notify_admin('Nova candidatura de profissional de limpeza',
    p_name || ' candidatou-se. Rever documentos no painel.');

  RETURN (SELECT to_jsonb(c) FROM cleaners c WHERE c.id = v_id);
END $$;
REVOKE ALL ON FUNCTION public.cleaner_apply(text, text, text, text, text, text, text, double precision, double precision, numeric, jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaner_apply(text, text, text, text, text, text, text, double precision, double precision, numeric, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleaner_set_profile(
  p_bio text DEFAULT NULL, p_photo_url text DEFAULT NULL,
  p_service_radius_km numeric DEFAULT NULL, p_is_active boolean DEFAULT NULL,
  p_base_address text DEFAULT NULL, p_base_lat double precision DEFAULT NULL,
  p_base_lng double precision DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me cleaners;
BEGIN
  v_me := public._cleaning_current_cleaner();
  UPDATE cleaners SET
    bio               = COALESCE(p_bio, bio),
    photo_url         = COALESCE(p_photo_url, photo_url),
    service_radius_km = COALESCE(p_service_radius_km, service_radius_km),
    is_active         = COALESCE(p_is_active, is_active),
    base_address      = COALESCE(p_base_address, base_address),
    base_lat          = COALESCE(p_base_lat, base_lat),
    base_lng          = COALESCE(p_base_lng, base_lng)
  WHERE id = v_me.id;
  RETURN (SELECT to_jsonb(c) FROM cleaners c WHERE c.id = v_me.id);
END $$;
REVOKE ALL ON FUNCTION public.cleaner_set_profile(text, text, numeric, boolean, text, double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaner_set_profile(text, text, numeric, boolean, text, double precision, double precision) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleaner_set_availability(p_slots jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me cleaners; v_slot jsonb;
BEGIN
  v_me := public._cleaning_current_cleaner();
  IF p_slots IS NULL OR jsonb_typeof(p_slots) <> 'array' OR jsonb_array_length(p_slots) > 50 THEN
    RAISE EXCEPTION 'invalid_slots';
  END IF;
  DELETE FROM cleaner_availability WHERE cleaner_id = v_me.id;
  FOR v_slot IN SELECT * FROM jsonb_array_elements(p_slots) LOOP
    INSERT INTO cleaner_availability (cleaner_id, weekday, start_time, end_time)
    VALUES (v_me.id,
            (v_slot ->> 'weekday')::smallint,
            (v_slot ->> 'start')::time,
            (v_slot ->> 'end')::time);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.cleaner_set_availability(jsonb) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaner_set_availability(jsonb) TO authenticated;

-- ---------- ofertas pendentes + ganhos da profissional ----------
CREATE OR REPLACE FUNCTION public.cleaner_earnings_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_me cleaners;
  v_week_start timestamptz := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_week int; v_total int; v_cash_due int; v_count_week int; v_count_total int;
BEGIN
  v_me := public._cleaning_current_cleaner();

  SELECT COALESCE(sum(cleaner_earnings_cents),0), count(*) INTO v_week, v_count_week
  FROM cleaning_bookings
  WHERE cleaner_id = v_me.id AND status = 'completed' AND completed_at >= v_week_start;

  SELECT COALESCE(sum(cleaner_earnings_cents),0), count(*) INTO v_total, v_count_total
  FROM cleaning_bookings
  WHERE cleaner_id = v_me.id AND status = 'completed';

  -- dinheiro: 15% da Bora cobrado em cash fica por entregar no acerto semanal
  SELECT COALESCE(sum(bora_fee_cents),0) INTO v_cash_due
  FROM cleaning_bookings
  WHERE cleaner_id = v_me.id AND payment_method = 'cash' AND payment_status = 'cash_pending';

  RETURN jsonb_build_object(
    'week_cents', v_week, 'week_count', v_count_week,
    'total_cents', v_total, 'total_count', v_count_total,
    'cash_bora_due_cents', v_cash_due,
    'rating_avg', v_me.rating_avg, 'ratings_count', v_me.ratings_count
  );
END $$;
REVOKE ALL ON FUNCTION public.cleaner_earnings_summary() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaner_earnings_summary() TO authenticated;
