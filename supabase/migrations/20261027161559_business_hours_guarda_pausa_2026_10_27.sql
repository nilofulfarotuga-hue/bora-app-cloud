-- 27/10/2026 (Claude.ai). Achado: o modelo DayHours da app (lib/models/restaurant_model.dart) só
-- conhece open/close/closed e o toJson() não escreve break_start/break_end. Quando o parceiro guarda
-- o horário no painel (partner_guardar_horario) a PAUSA do dia é APAGADA sem aviso (ex.: Boom! Burger
-- 14:30-19:00). Guarda no servidor: se o dia novo não traz NENHUMA das chaves break_start/break_end
-- (app antiga), mantém a pausa que lá estava. Uma app que queira tirar a pausa manda as chaves a null.
CREATE OR REPLACE FUNCTION public.fn_business_hours_guarda_pausa()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  k     text;
  v_old jsonb;
  v_new jsonb;
BEGIN
  IF OLD.business_hours IS NULL OR jsonb_typeof(OLD.business_hours) <> 'object'
     OR NEW.business_hours IS NULL OR jsonb_typeof(NEW.business_hours) <> 'object' THEN
    RETURN NEW;
  END IF;
  FOREACH k IN ARRAY ARRAY['mon','tue','wed','thu','fri','sat','sun'] LOOP
    v_old := OLD.business_hours->k;
    v_new := NEW.business_hours->k;
    IF jsonb_typeof(v_old) = 'object' AND jsonb_typeof(v_new) = 'object'
       AND (v_old ? 'break_start' OR v_old ? 'break_end')
       AND NOT (v_new ? 'break_start') AND NOT (v_new ? 'break_end') THEN
      NEW.business_hours := jsonb_set(
        NEW.business_hours, ARRAY[k],
        v_new || jsonb_strip_nulls(jsonb_build_object(
          'break_start', v_old->'break_start',
          'break_end',   v_old->'break_end')));
    END IF;
  END LOOP;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_business_hours_guarda_pausa
  BEFORE UPDATE OF business_hours ON public.restaurants
  FOR EACH ROW EXECUTE FUNCTION public.fn_business_hours_guarda_pausa();
