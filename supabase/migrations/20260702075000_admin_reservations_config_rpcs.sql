-- Item 50 do goal paridade-admin-360: Config Reservas Pro no admin.
-- O parceiro já gere pacing em restaurant_pacing_rules (partner_pacing_rules_screen);
-- isto dá ao admin visão global + autoridade para desativar regras e ver a
-- fila de espera do dia. Edição fina continua no parceiro (dono do restaurante).

CREATE OR REPLACE FUNCTION public.admin_list_pacing_rules(p_restaurant_id text DEFAULT NULL)
RETURNS TABLE (
  id uuid, restaurant_id text, restaurant_name text, day_of_week int,
  slot_start time, slot_end time, max_covers int, max_reservations int,
  walk_in_reserved_pct int, active boolean)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT p.id, p.restaurant_id, r.name, p.day_of_week, p.slot_start, p.slot_end,
         p.max_covers, p.max_reservations, p.walk_in_reserved_pct, p.active
  FROM restaurant_pacing_rules p
  JOIN restaurants r ON r.id = p.restaurant_id
  WHERE is_admin()
    AND (p_restaurant_id IS NULL OR p.restaurant_id = p_restaurant_id)
  ORDER BY r.name, p.day_of_week, p.slot_start;
$$;

CREATE OR REPLACE FUNCTION public.admin_toggle_pacing_rule(p_rule_id uuid, p_active boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_rule restaurant_pacing_rules;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin_only'; END IF;
  UPDATE restaurant_pacing_rules SET active = p_active, updated_at = now()
   WHERE id = p_rule_id RETURNING * INTO v_rule;
  IF v_rule.id IS NULL THEN RAISE EXCEPTION 'regra_nao_encontrada'; END IF;

  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), 'pacing_rule_' || CASE WHEN p_active THEN 'ativada' ELSE 'desativada' END,
          'restaurant_pacing_rule', v_rule.id::text,
          jsonb_build_object('restaurant_id', v_rule.restaurant_id,
                             'day_of_week', v_rule.day_of_week));
  RETURN jsonb_build_object('ok', true, 'id', v_rule.id, 'active', v_rule.active);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_waitlist_today()
RETURNS TABLE (restaurant_id text, restaurant_name text, em_espera bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT w.restaurant_id, r.name, count(*)
  FROM reservation_waitlist w
  JOIN restaurants r ON r.id = w.restaurant_id
  WHERE is_admin()
    AND w.status = 'active'
    AND w.target_date = CURRENT_DATE
  GROUP BY w.restaurant_id, r.name
  ORDER BY count(*) DESC;
$$;

REVOKE ALL ON FUNCTION public.admin_list_pacing_rules(text) FROM anon;
REVOKE ALL ON FUNCTION public.admin_toggle_pacing_rule(uuid, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.admin_list_waitlist_today() FROM anon;
