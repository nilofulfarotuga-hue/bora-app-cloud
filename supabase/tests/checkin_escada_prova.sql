-- Prova da escada de prémios (tudo desfeito no fim pelo RAISE EXCEPTION).
DO $prova$
DECLARE
  u1 uuid := 'd66d1522-ad8e-426e-9a75-76d636004186';  -- escada: 10 guarda, continuar, 15 troca, levantar recomeça
  u2 uuid := 'b99066c8-88e8-4b69-866e-47caf1b1324a';  -- falhar um dia mantém o patamar
  u3 uuid := '183a32cd-d570-447a-a86d-a86c2a6845d6';  -- último degrau levanta sozinho
  u4 uuid := 'e3126381-2252-46b8-afc0-71a4134d712d';  -- escada desligada = regra antiga
  h  date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  d  date;
  e  public.checkin_escada%ROWTYPE;
  r  jsonb;
  st jsonb;
  n  integer;
  sai text := '';
  falhas integer := 0;

BEGIN
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'checkin_require_phone';
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'checkin_marco_ativo';

  -- ===== U1: dias h-14 .. h-5 (10 dias) =====
  FOR i IN REVERSE 14..5 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u1, h - i, 1, 0);
  END LOOP;
  SELECT * INTO e FROM public.checkin_escada WHERE user_id = u1;
  SELECT count(*) INTO n FROM public.checkin_premios_vales WHERE user_id = u1;
  IF e.guardado_chave = 'salgados' AND e.decisao = 'pendente' AND n = 0 THEN
    sai := sai || ' P1 ok(dia10 guarda salgados, 0 vales)';
  ELSE falhas := falhas + 1; sai := sai || format(' P1 FALHOU(%s,%s,%s)', e.guardado_chave, e.decisao, n); END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', u1, 'role', 'authenticated')::text, true);
  r := public.client_checkin_escada_continuar();
  SELECT * INTO e FROM public.checkin_escada WHERE user_id = u1;
  IF (r ->> 'ok')::boolean AND e.decisao = 'continuar' THEN
    sai := sai || ' P2 ok(continuar marca)';
  ELSE falhas := falhas + 1; sai := sai || ' P2 FALHOU ' || r::text; END IF;

  -- dias h-4 .. h (chega ao 15)
  FOR i IN REVERSE 4..0 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u1, h - i, 1, 0);
  END LOOP;
  SELECT * INTO e FROM public.checkin_escada WHERE user_id = u1;
  SELECT count(*) INTO n FROM public.checkin_premios_vales WHERE user_id = u1;
  IF e.guardado_chave = 'acai' AND e.decisao = 'pendente' AND n = 0
     AND (SELECT count(*) FROM public.checkin_escada WHERE user_id = u1) = 1 THEN
    sai := sai || ' P3 ok(dia15 troca por acai, 1 so guardado, 0 vales)';
  ELSE falhas := falhas + 1; sai := sai || format(' P3 FALHOU(%s,%s,%s)', e.guardado_chave, e.decisao, n); END IF;

  st := public.client_checkin_premios();
  IF st -> 'escada' -> 'guardado' ->> 'chave' = 'acai' AND (st -> 'escada' ->> 'pendente_decisao')::boolean
     AND st -> 'escada' -> 'proximo_maior' ->> 'chave' = 'mes' AND (st ->> 'dia_marco')::int = 15
     AND (st ->> 'ciclo_inicio')::date = h - 14 THEN
    sai := sai || ' P4 ok(app ve acai guardado, proximo maior mes, dia 15)';
  ELSE falhas := falhas + 1; sai := sai || ' P4 FALHOU ' || (st - 'marcos' - 'vales')::text; END IF;

  r := public.client_checkin_escada_levantar();
  SELECT * INTO e FROM public.checkin_escada WHERE user_id = u1;
  SELECT count(*) INTO n FROM public.checkin_premios_vales WHERE user_id = u1;
  IF (r ->> 'ok')::boolean AND r -> 'vale' ->> 'chave' = 'acai' AND n = 1 AND e.guardado_chave IS NULL
     AND e.reinicio_data = h AND e.levantados = 1
     AND (r -> 'estado' ->> 'dia_marco')::int = 0 AND (r -> 'estado' ->> 'hoje_feito')::boolean
     AND (SELECT motivo FROM public.checkin_premios_vales WHERE user_id = u1) = 'escada:levantar' THEN
    sai := sai || format(' P5 ok(levantar: 1 vale acai estado %s, sequencia a 0)', r -> 'vale' ->> 'estado');
  ELSE falhas := falhas + 1; sai := sai || ' P5 FALHOU ' || left(r::text, 400); END IF;

  SELECT dias INTO n FROM public._checkin_seq_marcos(u1, h + 1);
  INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u1, h + 1, 1, 0);
  SELECT dias INTO n FROM public._checkin_seq_marcos(u1, h + 1);
  r := public.client_checkin_escada_levantar();
  IF n = 1 AND NOT (r ->> 'ok')::boolean AND r ->> 'reason' = 'sem_premio' THEN
    sai := sai || ' P6 ok(amanha e o Dia 1; levantar outra vez nao da nada)';
  ELSE falhas := falhas + 1; sai := sai || format(' P6 FALHOU(dias=%s %s)', n, r ->> 'reason'); END IF;

  -- ===== U2: 15 dias (h-20..h-6), falha h-5, volta h-4..h+5 (10 dias) =====
  FOR i IN REVERSE 20..6 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u2, h - i, 1, 0);
  END LOOP;
  FOR i IN REVERSE 4..0 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u2, h - i, 1, 0);
  END LOOP;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u2, 'role', 'authenticated')::text, true);
  st := public.client_checkin_premios();
  IF st -> 'escada' -> 'guardado' ->> 'chave' = 'acai' AND (st ->> 'dia_marco')::int = 5 THEN
    sai := sai || ' P7 ok(falhou um dia: sequencia no 5, acai continua guardado)';
  ELSE falhas := falhas + 1; sai := sai || ' P7 FALHOU ' || (st -> 'escada')::text || ' dia ' || (st ->> 'dia_marco'); END IF;
  FOR i IN 1..5 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u2, h + i, 1, 0);
  END LOOP;
  SELECT * INTO e FROM public.checkin_escada WHERE user_id = u2;
  SELECT count(*) INTO n FROM public.checkin_premios_vales WHERE user_id = u2;
  IF e.guardado_chave = 'acai' AND n = 0 THEN
    sai := sai || ' P8 ok(novo dia 10 nao tira o acai mais alto, 0 vales)';
  ELSE falhas := falhas + 1; sai := sai || format(' P8 FALHOU(%s,%s)', e.guardado_chave, n); END IF;

  -- ===== U3: 30 dias seguidos (h-29..h) =====
  FOR i IN REVERSE 29..0 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u3, h - i, 1, 0);
  END LOOP;
  SELECT * INTO e FROM public.checkin_escada WHERE user_id = u3;
  SELECT count(*) INTO n FROM public.checkin_premios_vales WHERE user_id = u3;
  IF n = 1 AND (SELECT marco_chave FROM public.checkin_premios_vales WHERE user_id = u3) = 'mes'
     AND e.guardado_chave IS NULL AND e.reinicio_data = h AND e.levantados = 1 THEN
    sai := sai || format(' P9 ok(dia 30: 1 vale so, o do mes, estado %s; recomeca)',
                         (SELECT estado FROM public.checkin_premios_vales WHERE user_id = u3));
  ELSE falhas := falhas + 1; sai := sai || format(' P9 FALHOU(n=%s %s %s)', n, e.guardado_chave, e.reinicio_data); END IF;

  -- ===== U4: escada desligada, 10 dias =====
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'checkin_escada_ativa';
  FOR i IN REVERSE 9..0 LOOP
    INSERT INTO public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded) VALUES (u4, h - i, 1, 0);
  END LOOP;
  SELECT count(*) INTO n FROM public.checkin_premios_vales WHERE user_id = u4 AND marco_chave = 'salgados';
  IF n = 1 AND NOT EXISTS (SELECT 1 FROM public.checkin_escada WHERE user_id = u4) THEN
    sai := sai || ' P10 ok(escada desligada: vale no dia 10 como antes)';
  ELSE falhas := falhas + 1; sai := sai || format(' P10 FALHOU(n=%s)', n); END IF;

  SELECT count(*) INTO n FROM public.e2e_log WHERE fluxo = 'checkin_marcos' AND estado = 'falhou' AND created_at > now() - interval '1 minute';
  sai := sai || format(' | falhas_gatilho=%s', n);

  RAISE EXCEPTION 'PROVA(rollback) falhas=% :%', falhas, sai;
END
$prova$;
