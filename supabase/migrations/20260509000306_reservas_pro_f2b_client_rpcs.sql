-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F2.B — RPCs Cliente
-- Data: 2026-05-08 / Sessao reservas-pro-F2-BACKEND-CORE
--
-- 4 RPCs SECURITY DEFINER (cliente):
-- 1. client_search_availability: slots disponiveis
-- 2. client_join_waitlist: entrar na fila
-- 3. client_join_notify: "avisa-me se vagar"
-- 4. client_arrived: carrega "estou aqui" -> push parceiro
--
-- Validacoes:
-- - Cliente nao pode estar blocked no restaurante
-- - max_advance_days / min_advance_minutes settings
-- - Sem duplicados activos do mesmo cliente
-- ═══════════════════════════════════════════════════════════

-- ─── RPC 1: client_search_availability ──────────────────────
CREATE OR REPLACE FUNCTION public.client_search_availability(
  p_restaurant_id text,
  p_target_date date,
  p_party_size integer,
  p_target_time time DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_max_advance_days integer;
  v_min_advance_minutes integer;
  v_slot_duration integer;
  v_dow integer;
  v_blocked boolean;
  v_turn_time integer;
  v_slots jsonb := '[]'::jsonb;
  v_slot_record record;
  v_target_dt timestamptz;
  v_now timestamptz := NOW();
  v_min_dt timestamptz;
  v_max_dt timestamptz;
  v_max_covers integer;
  v_max_reservations integer;
  v_existing_covers integer;
  v_existing_reservations integer;
  v_available_tables integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_party_size < 1 OR p_party_size > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;

  -- Validar cliente nao bloqueado neste restaurante
  SELECT is_blocked INTO v_blocked
  FROM client_restaurant_profiles
  WHERE client_user_id = v_uid AND restaurant_id = p_restaurant_id;
  IF COALESCE(v_blocked, false) THEN RAISE EXCEPTION 'client_blocked_at_restaurant'; END IF;

  -- Settings
  SELECT (value::text)::integer INTO v_max_advance_days FROM platform_settings WHERE key = 'reservation_max_advance_days';
  SELECT (value::text)::integer INTO v_min_advance_minutes FROM platform_settings WHERE key = 'reservation_min_advance_minutes';
  SELECT (value::text)::integer INTO v_slot_duration FROM platform_settings WHERE key = 'reservation_default_slot_duration_minutes';
  v_max_advance_days := COALESCE(v_max_advance_days, 60);
  v_min_advance_minutes := COALESCE(v_min_advance_minutes, 30);
  v_slot_duration := COALESCE(v_slot_duration, 30);

  -- Validar janela
  v_min_dt := v_now + (v_min_advance_minutes || ' minutes')::interval;
  v_max_dt := v_now + (v_max_advance_days || ' days')::interval;

  IF p_target_date < v_min_dt::date THEN RAISE EXCEPTION 'date_too_close'; END IF;
  IF p_target_date > v_max_dt::date THEN RAISE EXCEPTION 'date_too_far'; END IF;

  v_dow := EXTRACT(DOW FROM p_target_date)::integer;
  v_turn_time := _reservas_pro_get_turn_time(p_restaurant_id, p_party_size, v_dow);

  -- Loop slots do dia (default 30min cada). Se p_target_time fornecido, so esse slot +/- 1h.
  FOR v_slot_record IN
    SELECT
      r.day_of_week, r.slot_start, r.slot_end,
      r.max_covers, r.max_reservations
    FROM restaurant_pacing_rules r
    WHERE r.restaurant_id = p_restaurant_id
      AND r.day_of_week = v_dow
      AND r.active = true
    ORDER BY r.slot_start
  LOOP
    DECLARE
      v_t time := v_slot_record.slot_start;
    BEGIN
      WHILE v_t < v_slot_record.slot_end LOOP
        v_target_dt := (p_target_date + v_t)::timestamptz;

        -- Skip se p_target_time e diferenca > 60min
        IF p_target_time IS NOT NULL AND
           ABS(EXTRACT(EPOCH FROM (v_t - p_target_time)) / 60) > 60 THEN
          v_t := v_t + (v_slot_duration || ' minutes')::interval;
          CONTINUE;
        END IF;

        -- Skip se passou
        IF v_target_dt < v_min_dt THEN
          v_t := v_t + (v_slot_duration || ' minutes')::interval;
          CONTINUE;
        END IF;

        -- Conta reservas/covers a sobrepor neste slot (turn_time)
        SELECT
          COALESCE(SUM(people), 0),
          COUNT(*)
        INTO v_existing_covers, v_existing_reservations
        FROM reservations
        WHERE restaurant_id = p_restaurant_id
          AND status NOT IN ('cancelled','rejected_refunded','cancelled_refunded','cancelled_no_refund','no_show')
          AND reserved_for >= v_target_dt - (v_turn_time || ' minutes')::interval
          AND reserved_for <= v_target_dt + (v_turn_time || ' minutes')::interval;

        -- Mesas livres compativeis (capacity >= party_size, mesma capacidade exacta primeiro)
        SELECT COUNT(*) INTO v_available_tables
        FROM restaurant_tables t
        WHERE t.restaurant_id = p_restaurant_id
          AND t.active = true
          AND t.capacity >= p_party_size;

        v_max_covers := v_slot_record.max_covers;
        v_max_reservations := v_slot_record.max_reservations;

        -- Slot disponivel se:
        --   Limite covers OK (NULL = sem limite)
        --   Limite reservations OK
        --   Pelo menos 1 mesa cabe
        IF (v_max_covers IS NULL OR v_existing_covers + p_party_size <= v_max_covers) AND
           (v_max_reservations IS NULL OR v_existing_reservations < v_max_reservations) AND
           v_available_tables > 0 THEN
          v_slots := v_slots || jsonb_build_object(
            'slot_time', v_target_dt,
            'available_tables', v_available_tables,
            'covers_remaining', CASE WHEN v_max_covers IS NULL THEN -1 ELSE v_max_covers - v_existing_covers END,
            'turn_time_minutes', v_turn_time
          );
        END IF;

        v_t := v_t + (v_slot_duration || ' minutes')::interval;
      END LOOP;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', p_restaurant_id,
    'date', p_target_date,
    'party_size', p_party_size,
    'turn_time_minutes', v_turn_time,
    'slots', v_slots,
    'slots_count', jsonb_array_length(v_slots)
  );
END;
$$;

COMMENT ON FUNCTION public.client_search_availability IS
  'Devolve slots disponiveis num dia para um restaurante e party size. Tem em conta pacing rules, turn times, mesas livres. Valida cliente nao blocked.';

-- ─── RPC 2: client_join_waitlist ────────────────────────────
CREATE OR REPLACE FUNCTION public.client_join_waitlist(
  p_restaurant_id text,
  p_party integer,
  p_target_date date,
  p_target_time_start time DEFAULT NULL,
  p_target_time_end time DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_user_record record;
  v_position integer;
  v_existing uuid;
  v_blocked boolean;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_party < 1 OR p_party > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;
  IF p_target_date < CURRENT_DATE THEN RAISE EXCEPTION 'date_in_past'; END IF;

  -- Validar cliente nao blocked
  SELECT is_blocked INTO v_blocked
  FROM client_restaurant_profiles
  WHERE client_user_id = v_uid AND restaurant_id = p_restaurant_id;
  IF COALESCE(v_blocked, false) THEN RAISE EXCEPTION 'client_blocked_at_restaurant'; END IF;

  -- Buscar dados do cliente
  SELECT name, phone INTO v_user_record FROM users WHERE id = v_uid;
  IF v_user_record IS NULL THEN RAISE EXCEPTION 'user_not_found'; END IF;

  -- Verificar duplicado activo
  SELECT id INTO v_existing
  FROM reservation_waitlist
  WHERE client_user_id = v_uid
    AND restaurant_id = p_restaurant_id
    AND target_date = p_target_date
    AND status = 'waiting';
  IF v_existing IS NOT NULL THEN RAISE EXCEPTION 'waitlist_already_active'; END IF;

  -- Position = max + 1 do dia
  SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
  FROM reservation_waitlist
  WHERE restaurant_id = p_restaurant_id
    AND target_date = p_target_date
    AND status = 'waiting';

  -- INSERT
  INSERT INTO reservation_waitlist (
    restaurant_id, client_user_id, client_name, client_phone,
    people, target_date, target_time_start, target_time_end,
    status, position, notes
  ) VALUES (
    p_restaurant_id, v_uid, COALESCE(v_user_record.name, ''), COALESCE(v_user_record.phone, ''),
    p_party, p_target_date, p_target_time_start, p_target_time_end,
    'waiting', v_position, p_notes
  ) RETURNING id INTO v_id;

  -- Trigger trg_waitlist_notify_partner_new ja envia push automatico

  RETURN jsonb_build_object(
    'success', true,
    'waitlist_id', v_id,
    'position', v_position
  );
END;
$$;

COMMENT ON FUNCTION public.client_join_waitlist IS
  'Cliente entra na fila de espera. Valida nao blocked, sem duplicado activo. Position FIFO. Trigger envia push parceiro.';

-- ─── RPC 3: client_join_notify ──────────────────────────────
CREATE OR REPLACE FUNCTION public.client_join_notify(
  p_restaurant_id text,
  p_target_date date,
  p_target_time time,
  p_people integer,
  p_flexibility_minutes integer DEFAULT 30
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_blocked boolean;
  v_existing uuid;
  v_id uuid;
  v_expires_at timestamptz;
  v_expiry_hours integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_people < 1 OR p_people > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;
  IF p_flexibility_minutes < 0 OR p_flexibility_minutes > 180 THEN RAISE EXCEPTION 'invalid_flexibility'; END IF;
  IF p_target_date < CURRENT_DATE THEN RAISE EXCEPTION 'date_in_past'; END IF;

  -- Validar cliente nao blocked
  SELECT is_blocked INTO v_blocked
  FROM client_restaurant_profiles
  WHERE client_user_id = v_uid AND restaurant_id = p_restaurant_id;
  IF COALESCE(v_blocked, false) THEN RAISE EXCEPTION 'client_blocked_at_restaurant'; END IF;

  -- Verificar duplicado activo
  SELECT id INTO v_existing
  FROM reservation_notify_list
  WHERE client_user_id = v_uid
    AND restaurant_id = p_restaurant_id
    AND target_date = p_target_date
    AND target_time = p_target_time
    AND status = 'active';
  IF v_existing IS NOT NULL THEN RAISE EXCEPTION 'notify_already_active'; END IF;

  -- Expira X horas antes do slot (default 24h)
  SELECT (value::text)::integer INTO v_expiry_hours FROM platform_settings WHERE key = 'reservation_notify_list_expiry_hours';
  v_expiry_hours := COALESCE(v_expiry_hours, 24);

  v_expires_at := (p_target_date + p_target_time)::timestamptz - (v_expiry_hours || ' hours')::interval;

  -- Se ja passou, expira em 24h da data alvo (caso degenerado)
  IF v_expires_at < NOW() THEN
    v_expires_at := (p_target_date + p_target_time)::timestamptz;
  END IF;

  INSERT INTO reservation_notify_list (
    restaurant_id, client_user_id, target_date, target_time,
    flexibility_minutes, people, status, expires_at
  ) VALUES (
    p_restaurant_id, v_uid, p_target_date, p_target_time,
    p_flexibility_minutes, p_people, 'active', v_expires_at
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'success', true,
    'notify_id', v_id,
    'expires_at', v_expires_at
  );
END;
$$;

COMMENT ON FUNCTION public.client_join_notify IS
  'Cliente entra na lista "avisa se vagar". Quando ha late cancel compativel, trigger _reservas_pro_match_notify_list manda push automatico.';

-- ─── RPC 4: client_arrived ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_arrived(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rsv record;
  v_partner_user_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT * INTO v_rsv FROM reservations WHERE id = p_reservation_id;
  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.client_user_id != v_uid THEN RAISE EXCEPTION 'not_your_reservation'; END IF;
  IF v_rsv.status NOT IN ('approved','confirmed') THEN RAISE EXCEPTION 'cannot_arrive_status: %', v_rsv.status; END IF;
  IF v_rsv.arrived_at IS NOT NULL THEN RAISE EXCEPTION 'already_arrived'; END IF;

  UPDATE reservations
  SET arrived_at = NOW()
  WHERE id = p_reservation_id;

  -- Push parceiro: cliente chegou
  v_partner_user_id := _reservas_pro_get_partner_user_id(v_rsv.restaurant_id);
  PERFORM _reservas_pro_notify_partner_push(
    v_partner_user_id,
    'reservation_arrived',
    'Cliente chegou',
    v_rsv.client_name || ' • ' || v_rsv.people || ' pessoas • prepara mesa',
    p_reservation_id::text
  );

  RETURN jsonb_build_object(
    'success', true,
    'arrived_at', NOW()
  );
END;
$$;

COMMENT ON FUNCTION public.client_arrived IS
  'Cliente carrega "estou aqui" no app. Marca arrived_at e envia push parceiro para preparar mesa.';