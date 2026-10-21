-- Prova em transacção desfeita (DO … RAISE EXCEPTION 'RESULT %'): N2 Tarefa 3 — acesso igual.
-- Interruptor das encomendas ligado SÓ aqui dentro; demo@bora.app sem acesso SÓ aqui dentro.
-- Os pedidos pg_net de uma transacção desfeita não saem (ninguém real é avisado).
-- Fase A = funções como estão no ar; depois aplica-se o texto da migração (EXECUTE) e Fase B.
DO $$
DECLARE
  c_sem constant uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';  -- demo@bora.app (sem acesso só aqui)
  c_com constant uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';  -- demo.cliente@bora.app (com acesso)
  v_t0 timestamptz := (date_trunc('day', now() at time zone 'Europe/Lisbon') + interval '1 day 10 hours') at time zone 'Europe/Lisbon';
  v_out jsonb := '{}';
  r public.tvde_rides;
  j jsonb;
  v_fase text;
  v_cli uuid;
  v_kind text;
  v_q text;
BEGIN
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'tvde_encomendas_enabled';
  UPDATE public.users SET tvde_access = false WHERE id = c_sem;

  FOREACH v_fase IN ARRAY ARRAY['A_antes', 'B_depois'] LOOP
    IF v_fase = 'B_depois' THEN
      PERFORM set_config('role', 'postgres', true);
      EXECUTE $exec$
DO $mig$
DECLARE
  v_antiga constant text := E'  IF v_ride_kind = ''passageiros'' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;\n';
  v_nova   constant text := E'  PERFORM public._tvde_exige_acesso(v_uid);\n';
  f record;
  v_def text;
  v_md5 text;
  v_acl text;
  v_n int;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
      ('tvde_request_ride',       'e864711391be540dfbe8085efdd05e61', '2273e348a4983024cf90b66b3b7917e9'),
      ('tvde_schedule_ride',      'b3623e1b87a1432b830e417b2a10a48e', '3ab9d0e5083ca09f50a978909f150cb4'),
      ('tvde_schedule_roundtrip', 'ae675690c6b358e51a876250363264aa', '590b12297e0aba6982dfffea97dbbc73')
    ) AS t(nome, md5_antes, md5_depois)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_n <> 1 THEN
      RAISE EXCEPTION '%: % assinaturas (esperava 1) — nada aplicado', f.nome, v_n;
    END IF;
    SELECT pg_get_functiondef(p.oid), md5(p.prosrc), p.proacl::text INTO v_def, v_md5, v_acl
      FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_md5 IS DISTINCT FROM f.md5_antes THEN
      RAISE EXCEPTION '% mudou no ar (md5 % <> %) — nada aplicado', f.nome, v_md5, f.md5_antes;
    END IF;
    IF (length(v_def) - length(replace(v_def, v_antiga, ''))) <> length(v_antiga) THEN
      RAISE EXCEPTION '%: a linha do portão não aparece exactamente 1 vez — nada aplicado', f.nome;
    END IF;
    EXECUTE replace(v_def, v_antiga, v_nova);
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_md5 IS DISTINCT FROM f.md5_depois THEN
      RAISE EXCEPTION '%: md5 depois % <> % — nada aplicado', f.nome, v_md5, f.md5_depois;
    END IF;
    IF (SELECT p.proacl::text FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome) IS DISTINCT FROM v_acl THEN
      RAISE EXCEPTION '%: permissões mudaram — nada aplicado', f.nome;
    END IF;
  END LOOP;
END
$mig$;
$exec$;
      v_out := v_out || jsonb_build_object('md5_depois', (SELECT jsonb_object_agg(p.proname, md5(p.prosrc))
        FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname IN ('tvde_request_ride', 'tvde_schedule_ride', 'tvde_schedule_roundtrip')));
    END IF;

    FOREACH v_cli IN ARRAY ARRAY[c_sem, c_com] LOOP
      PERFORM set_config('role', 'postgres', true);
      PERFORM set_config('request.jwt.claim.sub', v_cli::text, true);
      PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
      PERFORM set_config('role', 'authenticated', true);
      FOREACH v_kind IN ARRAY ARRAY['passageiros', 'encomendas'] LOOP
        -- 1) na hora, dinheiro, 3 km
        v_q := v_fase || '|' || CASE WHEN v_cli = c_sem THEN 'sem_acesso' ELSE 'com_acesso' END || '|' || v_kind;
        BEGIN
          r := public.tvde_request_ride(40.5373, -7.2675, 'Sé da Guarda', 40.5600, -7.2675, 'Estação',
                 3.0, 'cash', 0, CASE WHEN v_kind = 'passageiros' THEN NULL ELSE v_kind END);
          v_out := v_out || jsonb_build_object(v_q || '|na_hora',
            jsonb_build_array(r.ride_kind, r.est_fare_cents, r.driver_earn_cents, r.bora_cut_cents));
          RAISE EXCEPTION USING ERRCODE = 'P0099';
        EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
                  WHEN OTHERS THEN v_out := v_out || jsonb_build_object(v_q || '|na_hora', SQLERRM);
        END;
        -- 2) reserva, dinheiro, 5 km, amanhã 10:00
        BEGIN
          r := public.tvde_schedule_ride(40.5373, -7.2675, 'Sé da Guarda', 40.5700, -7.2675, 'Hospital',
                 5.0, v_t0, 'cash', NULL, CASE WHEN v_kind = 'passageiros' THEN NULL ELSE v_kind END);
          v_out := v_out || jsonb_build_object(v_q || '|reserva',
            jsonb_build_array(r.ride_kind, r.est_fare_cents, r.driver_earn_cents, r.bora_cut_cents));
          RAISE EXCEPTION USING ERRCODE = 'P0099';
        EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
                  WHEN OTHERS THEN v_out := v_out || jsonb_build_object(v_q || '|reserva', SQLERRM);
        END;
        -- 3) ida-e-volta, dinheiro, 10 km
        BEGIN
          j := public.tvde_schedule_roundtrip(40.5373, -7.2675, 'Sé da Guarda', 40.6200, -7.2675, 'Pêra do Moço',
                 10.0, v_t0, v_t0 + interval '2 hours', 'cash', NULL, CASE WHEN v_kind = 'passageiros' THEN NULL ELSE v_kind END);
          v_out := v_out || jsonb_build_object(v_q || '|ida_e_volta',
            jsonb_build_array(j->'ida'->>'ride_kind', j->'volta'->>'ride_kind', (j->>'price_cents')::int,
              (j->'ida'->>'driver_earn_cents')::int, (j->'volta'->>'driver_earn_cents')::int));
          RAISE EXCEPTION USING ERRCODE = 'P0099';
        EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
                  WHEN OTHERS THEN v_out := v_out || jsonb_build_object(v_q || '|ida_e_volta', SQLERRM);
        END;
      END LOOP;
    END LOOP;
  END LOOP;

  -- interruptor desligado (como no ar): encomendas recusadas a toda a gente, passageiros com acesso igual
  PERFORM set_config('role', 'postgres', true);
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'tvde_encomendas_enabled';
  PERFORM set_config('request.jwt.claim.sub', c_com::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c_com, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    r := public.tvde_request_ride(40.5373, -7.2675, 'Sé da Guarda', 40.5600, -7.2675, 'Estação', 3.0, 'cash', 0, 'encomendas');
    v_out := v_out || jsonb_build_object('C_interruptor_off|com_acesso|encomendas', r.ride_kind);
    RAISE EXCEPTION USING ERRCODE = 'P0099';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
            WHEN OTHERS THEN v_out := v_out || jsonb_build_object('C_interruptor_off|com_acesso|encomendas', SQLERRM);
  END;
  BEGIN
    r := public.tvde_request_ride(40.5373, -7.2675, 'Sé da Guarda', 40.5600, -7.2675, 'Estação', 3.0, 'cash', 0);
    v_out := v_out || jsonb_build_object('C_interruptor_off|com_acesso|chamada_antiga_9_args',
      jsonb_build_array(r.ride_kind, r.est_fare_cents, r.driver_earn_cents, r.bora_cut_cents));
    RAISE EXCEPTION USING ERRCODE = 'P0099';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN NULL;
            WHEN OTHERS THEN v_out := v_out || jsonb_build_object('C_interruptor_off|com_acesso|chamada_antiga_9_args', SQLERRM);
  END;

  PERFORM set_config('role', 'postgres', true);
  v_out := v_out || jsonb_build_object(
    'acl', (SELECT jsonb_object_agg(p.proname, p.proacl::text) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
             AND p.proname IN ('tvde_request_ride', 'tvde_schedule_ride', 'tvde_schedule_roundtrip')),
    'anon_executa', (SELECT bool_or(has_function_privilege('anon', p.oid, 'execute')) FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('tvde_request_ride', 'tvde_schedule_ride', 'tvde_schedule_roundtrip')),
    'pg_net_fila_nesta_tx', (SELECT count(*) FROM net.http_request_queue));
  RAISE EXCEPTION 'RESULT %', v_out::text;
END
$$;
