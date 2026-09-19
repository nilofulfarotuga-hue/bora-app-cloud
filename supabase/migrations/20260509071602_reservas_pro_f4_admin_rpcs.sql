-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F4 ADMIN — RPCs admin acesso TOTAL
-- Data: 2026-05-09
--
-- 4 RPCs SECURITY DEFINER (admin acesso total):
-- 1. admin_force_create_reservation: cria reserva manual em nome cliente
-- 2. admin_seat_walk_in: senta walk-in em nome do parceiro
-- 3. admin_block_client: banir cliente abusivo
-- 4. admin_get_reservations_stats: analytics agregadas
--
-- Validacao admin: via funcao is_admin() ja existente OU
-- service_role bypass.
-- ═══════════════════════════════════════════════════════════

-- Helper: validar admin (usa pattern existente do projecto)
CREATE OR REPLACE FUNCTION public._reservas_pro_assert_admin()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  -- Tenta usar is_admin() do projecto se existe
  BEGIN
    SELECT is_admin INTO v_is_admin FROM users WHERE id = v_uid;
  EXCEPTION WHEN OTHERS THEN
    v_is_admin := false;
  END;

  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'admin_required';
  END IF;
END;
$$;

-- ─── RPC 1: admin_force_create_reservation ──────────────────
CREATE OR REPLACE FUNCTION public.admin_force_create_reservation(
  p_restaurant_id text,
  p_client_user_id uuid,  -- pode ser NULL se walk-in convidado
  p_client_name text,
  p_client_phone text,
  p_people integer,
  p_reserved_for timestamptz,
  p_status text DEFAULT 'approved',  -- admin pode criar ja approved
  p_notes text DEFAULT NULL,
  p_skip_prepayment boolean DEFAULT true
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_id uuid;
BEGIN
  PERFORM _reservas_pro_assert_admin();

  IF p_people < 1 OR p_people > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;

  -- Validar restaurante existe
  IF NOT EXISTS (SELECT 1 FROM restaurants WHERE id = p_restaurant_id) THEN
    RAISE EXCEPTION 'restaurant_not_found';
  END IF;

  INSERT INTO reservations (
    restaurant_id, client_user_id, client_name, client_phone,
    people, reserved_for, status, notes,
    prepayment_cents, decided_at
  ) VALUES (
    p_restaurant_id, p_client_user_id, p_client_name, p_client_phone,
    p_people, p_reserved_for, p_status, p_notes,
    CASE WHEN p_skip_prepayment THEN 0 ELSE 300 END,
    CASE WHEN p_status = 'approved' THEN NOW() ELSE NULL END
  ) RETURNING id INTO v_id;

  -- Log admin action
  PERFORM log_admin_action(
    'admin_force_create_reservation',
    'reservation',
    v_id::text,
    jsonb_build_object('restaurant_id', p_restaurant_id, 'people', p_people)
  );

  RETURN jsonb_build_object('success', true, 'reservation_id', v_id);
END;
$$;

-- ─── RPC 2: admin_seat_walk_in ──────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_seat_walk_in(
  p_restaurant_id text,
  p_party integer,
  p_table_id uuid,
  p_client_name text DEFAULT 'Walk-in admin',
  p_client_phone text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_table record;
  v_reservation_id uuid;
BEGIN
  PERFORM _reservas_pro_assert_admin();
  IF p_party < 1 OR p_party > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;

  SELECT * INTO v_table FROM restaurant_tables WHERE id = p_table_id;
  IF v_table IS NULL THEN RAISE EXCEPTION 'table_not_found'; END IF;
  IF v_table.restaurant_id != p_restaurant_id THEN RAISE EXCEPTION 'table_wrong_restaurant'; END IF;
  IF NOT v_table.active THEN RAISE EXCEPTION 'table_inactive'; END IF;
  IF v_table.capacity < p_party THEN RAISE EXCEPTION 'table_too_small'; END IF;

  INSERT INTO reservations (
    restaurant_id, client_user_id, client_name, client_phone,
    people, reserved_for, status, prepayment_cents,
    is_walk_in, seated_at, decided_at, arrived_at
  ) VALUES (
    p_restaurant_id, NULL, p_client_name, COALESCE(p_client_phone, ''),
    p_party, NOW(), 'approved', 0,
    true, NOW(), NOW(), NOW()
  ) RETURNING id INTO v_reservation_id;

  INSERT INTO reservation_table_assignments (
    reservation_id, table_id, is_primary, assigned_by
  ) VALUES (
    v_reservation_id, p_table_id, true, v_uid
  );

  PERFORM log_admin_action(
    'admin_seat_walk_in',
    'reservation',
    v_reservation_id::text,
    jsonb_build_object('table_id', p_table_id, 'people', p_party)
  );

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_reservation_id,
    'table_numero', v_table.numero
  );
END;
$$;

-- ─── RPC 3: admin_block_client ──────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_block_client(
  p_client_user_id uuid,
  p_restaurant_id text,
  p_reason text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  PERFORM _reservas_pro_assert_admin();

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  -- Upsert profile
  INSERT INTO client_restaurant_profiles (
    client_user_id, restaurant_id, is_blocked, blocked_reason, blocked_at
  ) VALUES (
    p_client_user_id, p_restaurant_id, true, p_reason, NOW()
  )
  ON CONFLICT (client_user_id, restaurant_id) DO UPDATE
  SET is_blocked = true,
      blocked_reason = EXCLUDED.blocked_reason,
      blocked_at = NOW();

  PERFORM log_admin_action(
    'admin_block_client',
    'client_restaurant_profile',
    p_client_user_id::text || ':' || p_restaurant_id,
    jsonb_build_object('reason', p_reason)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ─── RPC 4: admin_unblock_client ────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_unblock_client(
  p_client_user_id uuid,
  p_restaurant_id text,
  p_note text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='public' AS $$
BEGIN
  PERFORM _reservas_pro_assert_admin();

  UPDATE client_restaurant_profiles
  SET is_blocked = false, blocked_reason = NULL, blocked_at = NULL
  WHERE client_user_id = p_client_user_id AND restaurant_id = p_restaurant_id;

  PERFORM log_admin_action(
    'admin_unblock_client',
    'client_restaurant_profile',
    p_client_user_id::text || ':' || p_restaurant_id,
    jsonb_build_object('note', p_note)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ─── RPC 5: admin_get_reservations_stats ────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_reservations_stats(
  p_restaurant_id text DEFAULT NULL,  -- NULL = todos
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_start date := COALESCE(p_start_date, CURRENT_DATE - 30);
  v_end date := COALESCE(p_end_date, CURRENT_DATE);
  v_result jsonb;
BEGIN
  PERFORM _reservas_pro_assert_admin();

  WITH stats AS (
    SELECT
      count(*) FILTER (WHERE status='pending') as pending,
      count(*) FILTER (WHERE status='approved') as approved,
      count(*) FILTER (WHERE status IN ('cancelled_refunded','cancelled_no_refund','rejected_refunded','cancelled')) as cancelled,
      count(*) FILTER (WHERE status='no_show') as no_show,
      count(*) FILTER (WHERE seated_at IS NOT NULL) as seated,
      count(*) FILTER (WHERE finished_at IS NOT NULL) as finished,
      count(*) FILTER (WHERE is_walk_in=true) as walk_ins,
      coalesce(sum(people), 0) as total_covers,
      coalesce(avg(people), 0) as avg_party_size,
      count(*) as total
    FROM reservations
    WHERE (p_restaurant_id IS NULL OR restaurant_id = p_restaurant_id)
      AND reserved_for::date BETWEEN v_start AND v_end
  )
  SELECT to_jsonb(stats.*) INTO v_result FROM stats;

  RETURN jsonb_build_object(
    'success', true,
    'period', jsonb_build_object('start', v_start, 'end', v_end),
    'restaurant_id', p_restaurant_id,
    'stats', v_result
  );
END;
$$;
