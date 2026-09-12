-- ═══════════════════════════════════════════════════════════
-- BUG-7E-D-001 (MEDIUM) FIX — Drivers RLS strict
-- Data: 2026-05-09
--
-- Problema: drivers_select_authenticated qual="auth.uid() IS NOT NULL"
-- -> qualquer driver autenticado ve TODOS os drivers.
--
-- Fix:
-- 1. Driver so ve si proprio
-- 2. Admin ve tudo (service_role bypass)
-- 3. Cliente ve estafeta da sua order via RPC dedicada
-- ═══════════════════════════════════════════════════════════

DROP POLICY IF EXISTS drivers_select_authenticated ON public.drivers;

-- Driver ve si proprio
CREATE POLICY drivers_select_own
  ON public.drivers
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

COMMENT ON POLICY drivers_select_own ON public.drivers IS
  'BUG-7E-D-001 FIX (2026-05-09): driver so ve dados proprios. Cliente ve estafeta da sua order via RPC client_get_assigned_driver. Admin via service_role.';

-- RPC para cliente ver estafeta da sua order (foto, nome, rating, telefone)
CREATE OR REPLACE FUNCTION public.client_get_assigned_driver(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_order record;
  v_driver record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT id, user_id, assigned_driver_id, status
  INTO v_order
  FROM orders WHERE id = p_order_id;

  IF v_order IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_order.user_id != v_uid THEN RAISE EXCEPTION 'not_your_order'; END IF;
  IF v_order.assigned_driver_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'driver', null);
  END IF;

  SELECT id, name, phone, vehicle_type, license_plate, photo_url, avg_rating
  INTO v_driver
  FROM drivers WHERE id = v_order.assigned_driver_id;

  IF v_driver IS NULL THEN
    RETURN jsonb_build_object('success', true, 'driver', null);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'driver', jsonb_build_object(
      'id', v_driver.id,
      'name', v_driver.name,
      'phone', v_driver.phone,
      'vehicle_type', v_driver.vehicle_type,
      'license_plate', v_driver.license_plate,
      'photo_url', v_driver.photo_url,
      'avg_rating', v_driver.avg_rating
    )
  );
END;
$$;

COMMENT ON FUNCTION public.client_get_assigned_driver IS
  'Cliente ve dados estafeta da sua order (foto/nome/rating/telefone/matricula). RLS bypass via SECURITY DEFINER. Valida ownership via orders.user_id.';
