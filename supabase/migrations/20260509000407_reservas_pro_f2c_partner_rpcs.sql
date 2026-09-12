-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F2.C — RPCs Parceiro
-- Data: 2026-05-08 / Sessao reservas-pro-F2-BACKEND-CORE
--
-- 6 RPCs SECURITY DEFINER (parceiro):
-- 1. partner_create_floor_plan
-- 2. partner_add_table
-- 3. partner_combine_tables (define mesas combinaveis)
-- 4. partner_seat_walk_in (sentar cliente sem reserva)
-- 5. partner_mark_seated (cliente sentou-se a mesa)
-- 6. partner_mark_finished (cliente saiu)
--
-- Validacoes:
-- - Parceiro tem que ser dono do restaurante (restaurants.user_)
-- ═══════════════════════════════════════════════════════════

-- ─── HELPER privado: validar parceiro dono do restaurante ───
CREATE OR REPLACE FUNCTION public._reservas_pro_assert_partner(p_restaurant_id text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  SELECT user_ INTO v_owner FROM restaurants WHERE id = p_restaurant_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'restaurant_not_found'; END IF;
  IF v_owner != v_uid THEN RAISE EXCEPTION 'not_partner_owner'; END IF;
END;
$$;

-- ─── RPC 1: partner_create_floor_plan ───────────────────────
CREATE OR REPLACE FUNCTION public.partner_create_floor_plan(
  p_restaurant_id text,
  p_name text,
  p_is_default boolean DEFAULT false,
  p_width_cm integer DEFAULT 1000,
  p_height_cm integer DEFAULT 800
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_id uuid;
BEGIN
  PERFORM _reservas_pro_assert_partner(p_restaurant_id);

  -- Se este vai ser default, desmarca os outros
  IF p_is_default THEN
    UPDATE restaurant_floor_plans
    SET is_default = false
    WHERE restaurant_id = p_restaurant_id AND is_default = true;
  END IF;

  INSERT INTO restaurant_floor_plans (restaurant_id, name, is_default, width_cm, height_cm)
  VALUES (p_restaurant_id, p_name, p_is_default, p_width_cm, p_height_cm)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'floor_plan_id', v_id);
END;
$$;

COMMENT ON FUNCTION public.partner_create_floor_plan IS
  'Parceiro cria novo floor plan. Se p_is_default=true, desmarca outros automaticamente.';

-- ─── RPC 2: partner_add_table ───────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_add_table(
  p_restaurant_id text,
  p_numero text,
  p_capacity integer,
  p_zona text DEFAULT 'interior',
  p_floor_plan_id uuid DEFAULT NULL,
  p_pos_x numeric DEFAULT 0,
  p_pos_y numeric DEFAULT 0,
  p_shape text DEFAULT 'rectangle',
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_id uuid;
  v_default_plan_id uuid;
BEGIN
  PERFORM _reservas_pro_assert_partner(p_restaurant_id);

  -- Se floor_plan_id NULL, usa o default do restaurante (se existe)
  IF p_floor_plan_id IS NULL THEN
    SELECT id INTO v_default_plan_id
    FROM restaurant_floor_plans
    WHERE restaurant_id = p_restaurant_id AND is_default = true
    LIMIT 1;
    p_floor_plan_id := v_default_plan_id;
  ELSE
    -- Validar floor_plan pertence ao restaurante
    IF NOT EXISTS (SELECT 1 FROM restaurant_floor_plans WHERE id = p_floor_plan_id AND restaurant_id = p_restaurant_id) THEN
      RAISE EXCEPTION 'floor_plan_not_owned';
    END IF;
  END IF;

  INSERT INTO restaurant_tables (
    restaurant_id, floor_plan_id, numero, capacity, zona,
    pos_x, pos_y, shape, notes
  ) VALUES (
    p_restaurant_id, p_floor_plan_id, p_numero, p_capacity, p_zona,
    p_pos_x, p_pos_y, p_shape, p_notes
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'table_id', v_id);
END;
$$;

COMMENT ON FUNCTION public.partner_add_table IS
  'Parceiro cria mesa nova. Numero unique no restaurante. Se floor_plan_id NULL, usa default plan.';

-- ─── RPC 3: partner_combine_tables ──────────────────────────
CREATE OR REPLACE FUNCTION public.partner_combine_tables(
  p_restaurant_id text,
  p_table_id uuid,
  p_combinable_with uuid[]
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_invalid_count integer;
BEGIN
  PERFORM _reservas_pro_assert_partner(p_restaurant_id);

  -- Validar mesa pertence ao restaurante
  IF NOT EXISTS (SELECT 1 FROM restaurant_tables WHERE id = p_table_id AND restaurant_id = p_restaurant_id) THEN
    RAISE EXCEPTION 'table_not_owned';
  END IF;

  -- Validar todas as mesas em combinable_with pertencem ao mesmo restaurante
  SELECT COUNT(*) INTO v_invalid_count
  FROM unnest(p_combinable_with) AS cw_id
  WHERE NOT EXISTS (
    SELECT 1 FROM restaurant_tables
    WHERE id = cw_id AND restaurant_id = p_restaurant_id
  );
  IF v_invalid_count > 0 THEN RAISE EXCEPTION 'invalid_combinable_tables'; END IF;

  -- Remove o proprio se incluido (sem auto-referencia)
  p_combinable_with := array_remove(p_combinable_with, p_table_id);

  UPDATE restaurant_tables
  SET combinable_with = p_combinable_with
  WHERE id = p_table_id;

  RETURN jsonb_build_object(
    'success', true,
    'table_id', p_table_id,
    'combinable_count', array_length(p_combinable_with, 1)
  );
END;
$$;

COMMENT ON FUNCTION public.partner_combine_tables IS
  'Define quais mesas podem ser combinadas com esta. Validacao: todas tem que pertencer ao restaurante.';

-- ─── RPC 4: partner_seat_walk_in ────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_seat_walk_in(
  p_restaurant_id text,
  p_party integer,
  p_table_id uuid,
  p_client_name text DEFAULT 'Walk-in',
  p_client_phone text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_table record;
  v_reservation_id uuid;
BEGIN
  PERFORM _reservas_pro_assert_partner(p_restaurant_id);
  IF p_party < 1 OR p_party > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;

  -- Validar mesa
  SELECT * INTO v_table FROM restaurant_tables WHERE id = p_table_id;
  IF v_table IS NULL THEN RAISE EXCEPTION 'table_not_found'; END IF;
  IF v_table.restaurant_id != p_restaurant_id THEN RAISE EXCEPTION 'table_not_owned'; END IF;
  IF NOT v_table.active THEN RAISE EXCEPTION 'table_inactive'; END IF;
  IF v_table.capacity < p_party THEN RAISE EXCEPTION 'table_too_small'; END IF;

  -- Cria reserva walk-in (sem prepayment, ja sentado)
  INSERT INTO reservations (
    restaurant_id, client_user_id, client_name, client_phone,
    people, reserved_for, status, prepayment_cents,
    is_walk_in, seated_at, decided_at, arrived_at
  ) VALUES (
    p_restaurant_id, NULL, p_client_name, COALESCE(p_client_phone, ''),
    p_party, NOW(), 'approved', 0,
    true, NOW(), NOW(), NOW()
  ) RETURNING id INTO v_reservation_id;

  -- Liga a mesa
  INSERT INTO reservation_table_assignments (
    reservation_id, table_id, is_primary, assigned_by
  ) VALUES (
    v_reservation_id, p_table_id, true, v_uid
  );

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_reservation_id,
    'table_numero', v_table.numero
  );
END;
$$;

COMMENT ON FUNCTION public.partner_seat_walk_in IS
  'Parceiro senta cliente walk-in directamente. Cria reserva is_walk_in=true ja approved+seated. Liga a mesa.';

-- ─── RPC 5: partner_mark_seated ─────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_mark_seated(
  p_reservation_id uuid,
  p_table_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rsv record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT r.*, rest.user_ as owner_uid
  INTO v_rsv
  FROM reservations r
  JOIN restaurants rest ON rest.id = r.restaurant_id
  WHERE r.id = p_reservation_id;

  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.owner_uid != v_uid THEN RAISE EXCEPTION 'not_partner_owner'; END IF;
  IF v_rsv.status NOT IN ('approved','confirmed') THEN RAISE EXCEPTION 'cannot_seat_status: %', v_rsv.status; END IF;
  IF v_rsv.seated_at IS NOT NULL THEN RAISE EXCEPTION 'already_seated'; END IF;

  UPDATE reservations
  SET seated_at = NOW()
  WHERE id = p_reservation_id;
  -- Trigger trg_reservation_seated envia push cliente automaticamente

  -- Se mesa fornecida, liga (ou actualiza)
  IF p_table_id IS NOT NULL THEN
    -- Validar mesa pertence ao restaurante
    IF NOT EXISTS (
      SELECT 1 FROM restaurant_tables
      WHERE id = p_table_id AND restaurant_id = v_rsv.restaurant_id AND active = true
    ) THEN RAISE EXCEPTION 'invalid_table'; END IF;

    INSERT INTO reservation_table_assignments (reservation_id, table_id, is_primary, assigned_by)
    VALUES (p_reservation_id, p_table_id, true, v_uid)
    ON CONFLICT (reservation_id, table_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object('success', true, 'seated_at', NOW());
END;
$$;

COMMENT ON FUNCTION public.partner_mark_seated IS
  'Parceiro marca cliente sentado. Trigger envia push cliente. Opcional p_table_id liga a mesa.';

-- ─── RPC 6: partner_mark_finished ───────────────────────────
CREATE OR REPLACE FUNCTION public.partner_mark_finished(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rsv record;
  v_turn_minutes numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT r.*, rest.user_ as owner_uid
  INTO v_rsv
  FROM reservations r
  JOIN restaurants rest ON rest.id = r.restaurant_id
  WHERE r.id = p_reservation_id;

  IF v_rsv IS NULL THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_rsv.owner_uid != v_uid THEN RAISE EXCEPTION 'not_partner_owner'; END IF;
  IF v_rsv.seated_at IS NULL THEN RAISE EXCEPTION 'not_seated_yet'; END IF;
  IF v_rsv.finished_at IS NOT NULL THEN RAISE EXCEPTION 'already_finished'; END IF;

  UPDATE reservations
  SET finished_at = NOW()
  WHERE id = p_reservation_id;
  -- Trigger trg_reservation_finished actualiza profile cliente automaticamente

  v_turn_minutes := EXTRACT(EPOCH FROM (NOW() - v_rsv.seated_at)) / 60;

  RETURN jsonb_build_object(
    'success', true,
    'finished_at', NOW(),
    'turn_time_minutes', ROUND(v_turn_minutes)
  );
END;
$$;

COMMENT ON FUNCTION public.partner_mark_finished IS
  'Parceiro marca cliente saiu. Trigger actualiza profile (visits++, auto-VIP, last_visit_at). Devolve turn_time_real para analytics.';