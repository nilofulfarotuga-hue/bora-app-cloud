-- Missão boom-burger-2026-10-27, adendo 3 (F2): erro achado pelo caminho e consertado logo.
-- O painel admin manda só os 7 dias (BusinessHours.toJson não leva special_dates) e o admin_update_partner_hours
-- substituía o business_hours inteiro: cada "Salvar horários" apagava feriados e dias fechados da loja
-- (a 27/10 nenhuma loja tinha special_dates: nada se perdeu). Agora os dias vêm do p_hours e o resto mantém-se.
CREATE OR REPLACE FUNCTION public.admin_update_partner_hours(p_restaurant_id text, p_hours jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_admin RECORD; v_old JSONB; v_new JSONB; v_day TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_hours IS NULL OR jsonb_typeof(p_hours) != 'object' THEN RAISE EXCEPTION 'hours must be JSONB object'; END IF;
  FOREACH v_day IN ARRAY ARRAY['mon','tue','wed','thu','fri','sat','sun'] LOOP
    IF p_hours ? v_day AND jsonb_typeof(p_hours->v_day) != 'object' THEN
      RAISE EXCEPTION '% must be object', v_day;
    END IF;
  END LOOP;
  SELECT business_hours INTO v_old FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'restaurant not found'; END IF;
  -- 27/10/2026: o painel admin manda so os 7 dias (BusinessHours.toJson nao leva special_dates) e isto
  -- substituia o horario inteiro, apagando feriados e dias fechados. Agora os dias vem do p_hours e o
  -- resto (special_dates, etc.) mantem-se, salvo se vier no p_hours.
  v_new := CASE WHEN jsonb_typeof(v_old) = 'object'
                THEN (v_old - ARRAY['mon','tue','wed','thu','fri','sat','sun']) || p_hours
                ELSE p_hours END;
  UPDATE public.restaurants SET business_hours = v_new WHERE id = p_restaurant_id;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'partner_hours_updated', 'restaurant', p_restaurant_id,
    jsonb_build_object('old_hours', v_old, 'new_hours', v_new));
  PERFORM public._notify_partner_status_change(p_restaurant_id, 'Horário actualizado', 'O administrador actualizou o horário da loja.');
  RETURN jsonb_build_object('success', true, 'restaurant_id', p_restaurant_id);
END;
$function$;
