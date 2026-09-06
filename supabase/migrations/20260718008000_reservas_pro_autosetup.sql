-- MEGA-FIX 2026-07-18 RODADA 2 Parte 7 — reservas: parceiro nasce montado (auto-setup).
--
-- A infra existe (floor_plans, tables, turn_times, pacing_rules) mas um parceiro novo via
-- "Sem planos de sala / Sem tempos definidos". Aqui: função idempotente que monta o básico, e um
-- trigger que a chama quando `reservations_enabled` passa a true ou na aprovação (approval_status).
-- Idempotente por construção (se já há floor plan, não faz nada). SECURITY DEFINER (contexto de
-- trigger/sistema) → insere direto, sem o assert_partner do partner_create_floor_plan (que exige
-- o próprio parceiro como caller).

CREATE OR REPLACE FUNCTION public._reservas_pro_autosetup(p_restaurant_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plan_id uuid;
BEGIN
  IF p_restaurant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'null_id');
  END IF;

  -- Idempotência: se já existe qualquer floor plan, não mexe.
  IF EXISTS (SELECT 1 FROM restaurant_floor_plans WHERE restaurant_id = p_restaurant_id) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true);
  END IF;

  -- 1) Sala Principal (default) — mesma lógica do partner_create_floor_plan.
  INSERT INTO restaurant_floor_plans (restaurant_id, name, is_default, width_cm, height_cm, active)
  VALUES (p_restaurant_id, 'Sala Principal', true, 1000, 800, true)
  RETURNING id INTO v_plan_id;

  -- 2) 6 mesas: 4×2 lugares + 2×4 lugares (grelha simples, o parceiro reposiciona depois).
  INSERT INTO restaurant_tables
    (restaurant_id, floor_plan_id, numero, capacity, zona, pos_x, pos_y, shape, active)
  VALUES
    (p_restaurant_id, v_plan_id, '1', 2, 'interior', 100, 100, 'round',  true),
    (p_restaurant_id, v_plan_id, '2', 2, 'interior', 300, 100, 'round',  true),
    (p_restaurant_id, v_plan_id, '3', 2, 'interior', 500, 100, 'round',  true),
    (p_restaurant_id, v_plan_id, '4', 2, 'interior', 700, 100, 'round',  true),
    (p_restaurant_id, v_plan_id, '5', 4, 'interior', 200, 400, 'square', true),
    (p_restaurant_id, v_plan_id, '6', 4, 'interior', 500, 400, 'square', true);

  -- 3) Turn times default para TODOS os dias (0-6): 2p=90, 4p=120, 6+=150 min.
  INSERT INTO restaurant_turn_times
    (restaurant_id, party_size_min, party_size_max, day_of_week, minutes, active)
  SELECT p_restaurant_id, band.pmin, band.pmax, dow, band.mins, true
  FROM (VALUES (1, 2, 90), (3, 4, 120), (5, 99, 150)) AS band(pmin, pmax, mins)
  CROSS JOIN generate_series(0, 6) AS dow;

  -- 4) Pacing default razoável — todos os dias, 12:00-23:00.
  INSERT INTO restaurant_pacing_rules
    (restaurant_id, day_of_week, slot_start, slot_end, max_covers, max_reservations, walk_in_reserved_pct, active)
  SELECT p_restaurant_id, dow, TIME '12:00', TIME '23:00', 40, 15, 25, true
  FROM generate_series(0, 6) AS dow;

  RETURN jsonb_build_object('success', true, 'floor_plan_id', v_plan_id, 'created', true);
END;
$function$;

-- Trigger: monta o básico quando reservas ligam (insert/update) ou na aprovação.
CREATE OR REPLACE FUNCTION public._trg_reservas_autosetup_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.reservations_enabled IS TRUE THEN
    PERFORM public._reservas_pro_autosetup(NEW.id);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_reservas_autosetup ON public.restaurants;
CREATE TRIGGER trg_reservas_autosetup
  AFTER INSERT OR UPDATE OF reservations_enabled, approval_status ON public.restaurants
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_reservas_autosetup_fn();
