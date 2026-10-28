-- 27/10/2026 (Claude.ai, pedido do Danilo: consertar já o que ficou para trás).
-- is_partner_open ignorava a pausa do dia (break_start/break_end no business_hours).
-- Ex.: Boom! Burger ter-sáb 12:00-22:30 com pausa 14:30-19:00 aparecia ABERTA às 16:00.
-- Agora: dentro da pausa devolve is_open=false, opens_at=break_end e em_pausa=true;
-- antes da pausa, closes_in_minutes conta até ao início da pausa. Resto igual.
CREATE OR REPLACE FUNCTION public.is_partner_open(p_restaurant_id text, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_override     RECORD;
  v_hours        JSONB;
  v_special      JSONB;
  v_day_key      TEXT;
  v_day_hours    JSONB;
  v_at_local     TIMESTAMP;
  v_at_minutes   INT;
  v_open_minutes INT;
  v_close_minutes INT;
  v_break_start  INT;
  v_break_end    INT;
  v_is_open      BOOLEAN;
  v_closes_in    INT;
BEGIN
  SELECT forced_state, ends_at, reason
    INTO v_override
    FROM public.partner_status_override
   WHERE restaurant_id = p_restaurant_id
     AND starts_at <= p_at
     AND (ends_at IS NULL OR ends_at > p_at)
   ORDER BY starts_at DESC
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'is_open',           v_override.forced_state = 'open',
      'override_active',   true,
      'override_reason',   v_override.reason,
      'override_ends_at',  v_override.ends_at,
      'closes_in_minutes', NULL,
      'opens_at',          NULL
    );
  END IF;

  SELECT business_hours INTO v_hours FROM public.restaurants WHERE id = p_restaurant_id;

  IF v_hours IS NULL OR jsonb_typeof(v_hours) != 'object' THEN
    RETURN jsonb_build_object(
      'is_open', true, 'override_active', false,
      'closes_in_minutes', NULL, 'opens_at', NULL,
      'note', 'no_hours_configured'
    );
  END IF;

  v_at_local   := (p_at AT TIME ZONE 'Europe/Lisbon')::TIMESTAMP;
  v_at_minutes := EXTRACT(HOUR FROM v_at_local)::INT * 60 + EXTRACT(MINUTE FROM v_at_local)::INT;

  IF v_hours ? 'special_dates' AND jsonb_typeof(v_hours->'special_dates') = 'array' THEN
    SELECT elem INTO v_special
      FROM jsonb_array_elements(v_hours->'special_dates') elem
     WHERE (elem->>'date')::DATE = v_at_local::DATE
     LIMIT 1;
    IF FOUND THEN v_day_hours := v_special; END IF;
  END IF;

  IF v_day_hours IS NULL THEN
    v_day_key := CASE EXTRACT(DOW FROM v_at_local)::INT
                   WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue'
                   WHEN 3 THEN 'wed' WHEN 4 THEN 'thu' WHEN 5 THEN 'fri'
                   WHEN 6 THEN 'sat' END;
    v_day_hours := v_hours->v_day_key;
  END IF;

  IF v_day_hours IS NULL OR jsonb_typeof(v_day_hours) != 'object'
     OR (v_day_hours->>'closed')::BOOLEAN IS TRUE THEN
    RETURN jsonb_build_object(
      'is_open', false, 'override_active', false,
      'closes_in_minutes', NULL, 'opens_at', v_day_hours->>'open'
    );
  END IF;

  v_open_minutes  := public._parse_hhmm_to_minutes(v_day_hours->>'open');
  v_close_minutes := public._parse_hhmm_to_minutes(v_day_hours->>'close');

  IF v_open_minutes IS NULL OR v_close_minutes IS NULL THEN
    RETURN jsonb_build_object(
      'is_open', true, 'override_active', false,
      'closes_in_minutes', NULL, 'opens_at', NULL, 'note', 'unparseable_hours'
    );
  END IF;

  IF v_close_minutes <= v_open_minutes THEN
    v_is_open := v_at_minutes >= v_open_minutes OR v_at_minutes < v_close_minutes;
    IF v_is_open THEN
      v_closes_in := CASE
        WHEN v_at_minutes >= v_open_minutes THEN (1440 - v_at_minutes) + v_close_minutes
        ELSE v_close_minutes - v_at_minutes
      END;
    END IF;
  ELSE
    v_is_open := v_at_minutes >= v_open_minutes AND v_at_minutes < v_close_minutes;
    IF v_is_open THEN v_closes_in := v_close_minutes - v_at_minutes; END IF;
  END IF;

  -- Pausa do dia (ex.: almoço/tarde 14:30-19:00). 27/10/2026.
  v_break_start := public._parse_hhmm_to_minutes(v_day_hours->>'break_start');
  v_break_end   := public._parse_hhmm_to_minutes(v_day_hours->>'break_end');
  IF v_is_open AND v_break_start IS NOT NULL AND v_break_end IS NOT NULL
     AND v_break_start < v_break_end THEN
    IF v_at_minutes >= v_break_start AND v_at_minutes < v_break_end THEN
      RETURN jsonb_build_object(
        'is_open', false, 'override_active', false,
        'closes_in_minutes', NULL, 'opens_at', v_day_hours->>'break_end',
        'em_pausa', true
      );
    ELSIF v_at_minutes < v_break_start
          AND (v_closes_in IS NULL OR v_break_start - v_at_minutes < v_closes_in) THEN
      v_closes_in := v_break_start - v_at_minutes;
    END IF;
  END IF;

  IF v_is_open THEN
    RETURN jsonb_build_object(
      'is_open', true, 'override_active', false,
      'closes_in_minutes', v_closes_in, 'opens_at', NULL
    );
  ELSE
    RETURN jsonb_build_object(
      'is_open', false, 'override_active', false,
      'closes_in_minutes', NULL, 'opens_at', v_day_hours->>'open'
    );
  END IF;
END;
$function$;
