-- [ronda 04/10 · app-estafeta #3] "Ganhos de hoje": se a soma de UM papel
-- falhar (p.ex. driver_earnings_summary rebenta), o total dos outros papéis
-- continua a sair. Antes, um erro num papel deitava a RPC inteira abaixo e o
-- cartão/ecrã Ganhos ficavam sem total. Cada papel falhado aparece em
-- 'papeis_com_falha' (para o ecrã/admin saberem que o número está incompleto).
CREATE OR REPLACE FUNCTION public.meu_ganho_ao_vivo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_dia timestamptz;
  v_sem timestamptz;
  v_cleaner_id uuid;
  v_washer_id uuid;
  v_linhas jsonb := '[]'::jsonb;
  v_falhas jsonb := '[]'::jsonb;
  v_hoje bigint := 0;
  v_semana bigint := 0;
  h bigint; s bigint; nh int; ns int;
  v_driver jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  -- Fuso de Lisboa: "hoje" e o dia do prestador, nao o do servidor.
  v_dia := date_trunc('day',  now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_sem := date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';

  -- ENTREGAS E CORRIDAS: reaproveita `driver_earnings_summary()`.
  BEGIN
    IF EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = v_uid) THEN
      v_driver := public.driver_earnings_summary();
      IF v_driver->>'ok' = 'true' THEN
        h := COALESCE((v_driver->'dia'->>'total_cents')::bigint, 0);
        s := COALESCE((v_driver->'semana'->>'total_cents')::bigint, 0);
        v_hoje := v_hoje + h;
        v_semana := v_semana + s;
        v_linhas := v_linhas || jsonb_build_object(
          'papel', 'driver', 'titulo', 'Entregas e corridas',
          'hoje_cents', h, 'semana_cents', s);
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('driver'::text);
  END;

  -- LIMPEZA
  BEGIN
    SELECT c.id INTO v_cleaner_id FROM public.cleaners c WHERE c.user_id = v_uid;
    IF v_cleaner_id IS NOT NULL THEN
      SELECT COALESCE(sum(b.cleaner_earnings_cents) FILTER (WHERE b.completed_at >= v_dia), 0),
             COALESCE(sum(b.cleaner_earnings_cents) FILTER (WHERE b.completed_at >= v_sem), 0),
             count(*) FILTER (WHERE b.completed_at >= v_dia),
             count(*) FILTER (WHERE b.completed_at >= v_sem)
        INTO h, s, nh, ns
        FROM public.cleaning_bookings b
       WHERE b.cleaner_id = v_cleaner_id AND b.status = 'completed'
         AND COALESCE(b.is_test_order, false) = false;
      v_hoje := v_hoje + h; v_semana := v_semana + s;
      v_linhas := v_linhas || jsonb_build_object(
        'papel', 'cleaner', 'titulo', 'Limpeza',
        'hoje_cents', h, 'semana_cents', s,
        'trabalhos_hoje', nh, 'trabalhos_semana', ns);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('cleaner'::text);
  END;

  -- LAVAGEM
  BEGIN
    SELECT w.id INTO v_washer_id FROM public.washers w WHERE w.user_id = v_uid;
    IF v_washer_id IS NOT NULL THEN
      SELECT COALESCE(sum(b.washer_earnings_cents) FILTER (WHERE b.completed_at >= v_dia), 0),
             COALESCE(sum(b.washer_earnings_cents) FILTER (WHERE b.completed_at >= v_sem), 0),
             count(*) FILTER (WHERE b.completed_at >= v_dia),
             count(*) FILTER (WHERE b.completed_at >= v_sem)
        INTO h, s, nh, ns
        FROM public.carwash_bookings b
       WHERE b.washer_id = v_washer_id AND b.status = 'completed';
      v_hoje := v_hoje + h; v_semana := v_semana + s;
      v_linhas := v_linhas || jsonb_build_object(
        'papel', 'washer', 'titulo', 'Lavagem de carros',
        'hoje_cents', h, 'semana_cents', s,
        'trabalhos_hoje', nh, 'trabalhos_semana', ns);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_falhas := v_falhas || to_jsonb('washer'::text);
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'hoje_cents', v_hoje,
    'semana_cents', v_semana,
    'por_papel', v_linhas,
    'papeis_com_falha', v_falhas);
END $function$;
