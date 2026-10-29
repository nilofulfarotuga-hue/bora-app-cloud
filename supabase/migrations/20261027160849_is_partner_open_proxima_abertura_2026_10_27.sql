-- 27/10/2026 (Claude.ai). Achado ao provar a pausa: num dia FECHADO (ex.: domingo da Boom)
-- o opens_at devolvia a hora gravada nesse dia ("12:00"), e depois do fecho devolvia a abertura
-- do próprio dia. Agora opens_at = hora da PRÓXIMA abertura real (hoje, fim da pausa, ou o
-- próximo dia aberto até 7 dias), com opens_dia ('hoje','amanhã','segunda'...) e opens_at_ts.
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
  -- próxima abertura
  i              INT;
  v_d            DATE;
  v_dh           JSONB;
  v_o            INT;
  v_bs           INT;
  v_be           INT;
  v_next_min     INT;
  v_next_day     DATE;
  v_dias         TEXT[] := ARRAY['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
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

  v_is_open := false;

  IF v_day_hours IS NOT NULL AND jsonb_typeof(v_day_hours) = 'object'
     AND (v_day_hours->>'closed')::BOOLEAN IS NOT TRUE THEN

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

    -- Pausa do dia (ex.: 14:30-19:00). 27/10/2026.
    v_break_start := public._parse_hhmm_to_minutes(v_day_hours->>'break_start');
    v_break_end   := public._parse_hhmm_to_minutes(v_day_hours->>'break_end');
    IF v_is_open AND v_break_start IS NOT NULL AND v_break_end IS NOT NULL
       AND v_break_start < v_break_end THEN
      IF v_at_minutes >= v_break_start AND v_at_minutes < v_break_end THEN
        RETURN jsonb_build_object(
          'is_open', false, 'override_active', false,
          'closes_in_minutes', NULL, 'opens_at', v_day_hours->>'break_end',
          'opens_dia', 'hoje',
          'opens_at_ts', (v_at_local::DATE + make_interval(mins => v_break_end)) AT TIME ZONE 'Europe/Lisbon',
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
    END IF;
  END IF;

  -- Fechado: procurar a PRÓXIMA abertura real (hoje mais tarde ou nos próximos 7 dias).
  FOR i IN 0..7 LOOP
    v_d  := v_at_local::DATE + i;
    v_dh := NULL;
    IF v_hours ? 'special_dates' AND jsonb_typeof(v_hours->'special_dates') = 'array' THEN
      SELECT elem INTO v_dh
        FROM jsonb_array_elements(v_hours->'special_dates') elem
       WHERE (elem->>'date')::DATE = v_d
       LIMIT 1;
    END IF;
    IF v_dh IS NULL THEN
      v_dh := v_hours->(CASE EXTRACT(DOW FROM v_d)::INT
                 WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue'
                 WHEN 3 THEN 'wed' WHEN 4 THEN 'thu' WHEN 5 THEN 'fri'
                 WHEN 6 THEN 'sat' END);
    END IF;
    CONTINUE WHEN v_dh IS NULL OR jsonb_typeof(v_dh) != 'object'
               OR (v_dh->>'closed')::BOOLEAN IS TRUE;
    v_o := public._parse_hhmm_to_minutes(v_dh->>'open');
    CONTINUE WHEN v_o IS NULL;
    IF i = 0 THEN
      IF v_at_minutes < v_o THEN
        v_next_min := v_o; v_next_day := v_d; EXIT;
      END IF;
      v_bs := public._parse_hhmm_to_minutes(v_dh->>'break_start');
      v_be := public._parse_hhmm_to_minutes(v_dh->>'break_end');
      IF v_bs IS NOT NULL AND v_be IS NOT NULL AND v_bs < v_be
         AND v_at_minutes >= v_bs AND v_at_minutes < v_be THEN
        v_next_min := v_be; v_next_day := v_d; EXIT;
      END IF;
    ELSE
      v_next_min := v_o; v_next_day := v_d; EXIT;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'is_open', false, 'override_active', false,
    'closes_in_minutes', NULL,
    'opens_at', CASE WHEN v_next_min IS NULL THEN NULL
                     ELSE lpad((v_next_min / 60)::TEXT, 2, '0') || ':' || lpad((v_next_min % 60)::TEXT, 2, '0') END,
    'opens_dia', CASE WHEN v_next_day IS NULL THEN NULL
                      WHEN v_next_day = v_at_local::DATE THEN 'hoje'
                      WHEN v_next_day = v_at_local::DATE + 1 THEN 'amanhã'
                      ELSE v_dias[EXTRACT(DOW FROM v_next_day)::INT + 1] END,
    'opens_at_ts', CASE WHEN v_next_day IS NULL THEN NULL
                        ELSE (v_next_day + make_interval(mins => v_next_min)) AT TIME ZONE 'Europe/Lisbon' END
  );
END;
$function$;
