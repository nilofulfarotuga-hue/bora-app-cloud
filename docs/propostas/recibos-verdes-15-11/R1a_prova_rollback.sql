-- =====================================================================================
-- R1a — PROVA EM ROLLBACK (recibos verdes: trava do pagamento) — NADA FICA GRAVADO
-- Missão 12 "recibos-verdes-15-11". Escrito pelo Claude Code a 15/11/2026.
-- Correr DEPOIS de aplicar R1a_servidor.PROPOSTA.sql (o passo P0 confere isso).
-- Como correr: execute_sql com o texto todo, numa ligação direta (postgres), de uma vez.
--
-- O QUE PROVA, COM DADOS REAIS DE PRODUÇÃO (entregas de novembro/2026 e acertos reais):
--   A) quem tem o recibo de novembro com PDF é pago normalmente;
--   B) quem não tem, depois do dia 10, fica retido ("Marcar pago" bloqueado, nos dois botões);
--   C) quem DEVE à Bora continua a ser cobrado como hoje ("recebido" passa, mesmo retido);
--   D) quando anexa, a trava cai, as semanas guardadas pagam-se todas e o total bate certo
--      ao cêntimo (nenhum valor muda);
--   E) conta do dono: saltada com fecho_dono_passa_recibo=false; travada com true; e o admin
--      solta uma semana com motivo (fica na auditoria);
--   F) o interruptor recibos_trava_ativa desliga a trava.
--
-- COMO É QUE NADA FICA GRAVADO:
--   * "Hoje" é fingido como 11/12/2026 só dentro desta transação (bora.recibo_hoje_teste, que
--     só vale numa ligação direta postgres).
--   * Reabrem-se 4 a 5 acertos reais já pagos/recebidos (passam a "por pagar" com o MESMO
--     valor), cria-se a linha do ficheiro no armazenamento sem ficheiro nenhum, e mudam-se
--     2 definições — tudo dentro da transação.
--   * O bloco acaba SEMPRE com um erro de propósito que traz o resultado (PROVA_R1a TUDO_OK
--     ou HA_FALHAS + a lista de passos). O erro desfaz tudo; o ROLLBACK do fim fecha.
--   * Os pedidos HTTP do pg_net (recibo semanal ao prestador, avisos) só saem depois de
--     COMMIT; aqui não há COMMIT, por isso não sai nada. A prova NÃO chama a função do aviso
--     do dia 10 (só conta quem a receberia).
--   * Se a ferramenta mostrar só "erro": é esse o resultado. Ler o texto depois de PROVA_R1a.
-- =====================================================================================
BEGIN;

DO $prova$
DECLARE
  v_admin uuid;
  v_a uuid;
  v_b uuid;
  v_dono uuid;
  v_lista jsonb;
  v_res jsonb;
  v_t jsonb;
  v_item jsonb;
  v_erro text;
  v_tmp text;
  v_ok boolean;
  v_tudo boolean := true;
  v_out jsonb := '[]'::jsonb;
  v_a_id uuid;  v_a_ws date;
  v_w1 uuid;    v_w1_ws date;  v_w1_c bigint;
  v_w2 uuid;    v_w2_ws date;  v_w2_c bigint;
  v_wd uuid;    v_wd_ws date;  v_wd_c bigint;
  v_do_id uuid; v_do_ws date;
  v_pp_antes bigint;
  v_pp_depois bigint;
  v_soma bigint;
  v_n int;
  v_antes jsonb;
BEGIN
  -- ---------------------------------------------------------------- P0: R1a aplicado?
  IF to_regprocedure('public.prestador_recibo_trava(uuid)') IS NULL
     OR to_regprocedure('public.driver_mark_invoice_issued(integer,integer,text,date,text)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_recibo_trava_pagamento')
     OR NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'recibos-verdes') THEN
    RAISE EXCEPTION 'PROVA_NAO_CORREU: aplique primeiro o R1a_servidor.PROPOSTA.sql';
  END IF;

  -- ---------------------------------------------------------------- P1: contexto
  SELECT u.id INTO v_admin FROM auth.users u
  WHERE lower(u.email) IN ('nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')
  ORDER BY u.created_at LIMIT 1;
  IF v_admin IS NULL THEN
    SELECT u.id INTO v_admin FROM auth.users u
    WHERE u.raw_app_meta_data ->> 'role' = 'admin' ORDER BY u.created_at LIMIT 1;
  END IF;
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'PROVA_NAO_CORREU: não encontrei uma conta de admin';
  END IF;

  PERFORM set_config('bora.recibo_hoje_teste', '2026-12-11', true);
  UPDATE public.platform_settings SET value = 'true'::jsonb  WHERE key = 'recibos_trava_ativa';
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'fecho_dono_passa_recibo';

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_ok := public._recibo_hoje() = date '2026-12-11' AND public.is_admin();
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P1',
    'o_que', 'Contexto: hoje fingido 11/12/2026 (dia a seguir ao prazo de novembro), sessão de admin',
    'esperado', 'hoje=2026-12-11, admin=true',
    'obtido', 'hoje=' || public._recibo_hoje()::text || ', admin=' || public.is_admin()::text,
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  -- ---------------------------------------------------------------- P2: pessoas e acertos reais
  v_lista := public._recibo_resumo_calc(2026, 11, NULL) -> 'prestadores';

  -- B: trabalhou em novembro, sem recibo, com >= 2 acertos "pagos" (a Bora pagou) e >= 1 "recebido" (pagou à Bora)
  SELECT (e ->> 'user_id')::uuid INTO v_b
  FROM jsonb_array_elements(v_lista) e
  WHERE coalesce((e ->> 'conta_para_trava')::boolean, false)
    AND NOT coalesce((e ->> 'tem_pdf')::boolean, false)
    AND (SELECT count(*) FROM public.driver_weekly_settlements s
         WHERE s.driver_id = (e ->> 'user_id')::uuid AND s.status = 'paid' AND s.net_balance > 0) >= 2
    AND EXISTS (SELECT 1 FROM public.driver_weekly_settlements s
                WHERE s.driver_id = (e ->> 'user_id')::uuid AND s.status = 'received' AND s.net_balance < 0)
  ORDER BY (e ->> 'total')::numeric DESC
  LIMIT 1;

  -- A: outra pessoa que trabalhou em novembro, sem recibo ainda, com >= 1 acerto "pago"
  SELECT (e ->> 'user_id')::uuid INTO v_a
  FROM jsonb_array_elements(v_lista) e
  WHERE coalesce((e ->> 'conta_para_trava')::boolean, false)
    AND NOT coalesce((e ->> 'tem_pdf')::boolean, false)
    AND (e ->> 'user_id')::uuid IS DISTINCT FROM v_b
    AND EXISTS (SELECT 1 FROM public.driver_weekly_settlements s
                WHERE s.driver_id = (e ->> 'user_id')::uuid AND s.status = 'paid' AND s.net_balance > 0)
  LIMIT 1;

  -- Dono (boraappbora): trabalhou em novembro e tem >= 1 acerto "pago"
  SELECT (e ->> 'user_id')::uuid INTO v_dono
  FROM jsonb_array_elements(v_lista) e
  WHERE coalesce((e ->> 'conta_dono')::boolean, false)
    AND (e ->> 'total')::numeric > 0
    AND NOT coalesce((e ->> 'tem_pdf')::boolean, false)
    AND EXISTS (SELECT 1 FROM public.driver_weekly_settlements s
                WHERE s.driver_id = (e ->> 'user_id')::uuid AND s.status = 'paid' AND s.net_balance > 0)
  LIMIT 1;

  IF v_a IS NULL OR v_b IS NULL THEN
    RAISE EXCEPTION 'PROVA_SEM_DADOS: não encontrei duas pessoas reais com trabalho em novembro, sem recibo e com acertos pagos (A=%, B=%)', v_a, v_b;
  END IF;

  SELECT s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date
  INTO v_a_id, v_a_ws
  FROM public.driver_weekly_settlements s
  WHERE s.driver_id = v_a AND s.status = 'paid' AND s.net_balance > 0
  ORDER BY s.week_start_at DESC LIMIT 1;

  SELECT s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date, round(s.net_balance * 100)::bigint
  INTO v_w1, v_w1_ws, v_w1_c
  FROM public.driver_weekly_settlements s
  WHERE s.driver_id = v_b AND s.status = 'paid' AND s.net_balance > 0
  ORDER BY s.week_start_at DESC LIMIT 1;

  SELECT s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date, round(s.net_balance * 100)::bigint
  INTO v_w2, v_w2_ws, v_w2_c
  FROM public.driver_weekly_settlements s
  WHERE s.driver_id = v_b AND s.status = 'paid' AND s.net_balance > 0
  ORDER BY s.week_start_at DESC OFFSET 1 LIMIT 1;

  SELECT s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date, round(s.net_balance * 100)::bigint
  INTO v_wd, v_wd_ws, v_wd_c
  FROM public.driver_weekly_settlements s
  WHERE s.driver_id = v_b AND s.status = 'received' AND s.net_balance < 0
  ORDER BY s.week_start_at DESC LIMIT 1;

  SELECT jsonb_object_agg(s.id::text, s.net_balance) INTO v_antes
  FROM public.driver_weekly_settlements s
  WHERE s.id IN (v_a_id, v_w1, v_w2, v_wd);

  -- Reabrir estas linhas reais (só nesta transação): voltam a "por pagar" com o MESMO valor.
  UPDATE public.driver_weekly_settlements
     SET status = 'pending', paid_at = NULL, paid_by = NULL
   WHERE id IN (v_a_id, v_w1, v_w2, v_wd);

  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P2',
    'o_que', 'Pessoas reais de novembro/2026 e acertos reais reabertos (mesmos valores)',
    'esperado', 'A e B encontrados',
    'obtido', 'A=' || left(v_a::text, 8) || ' (semana ' || v_a_ws || '); B=' || left(v_b::text, 8)
              || ' (a receber: ' || v_w1_ws || ' ' || replace(to_char(v_w1_c / 100.0, 'FM999990.00'), '.', ',') || ' € e '
              || v_w2_ws || ' ' || replace(to_char(v_w2_c / 100.0, 'FM999990.00'), '.', ',') || ' €; a pagar à Bora: '
              || v_wd_ws || ' ' || replace(to_char(v_wd_c / 100.0, 'FM999990.00'), '.', ',') || ' €); dono='
              || coalesce(left(v_dono::text, 8), '-'),
    'ok', true));

  -- ---------------------------------------------------------------- P3: A anexa o recibo (como a app nova)
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_a::text, true);

  INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
  VALUES ('recibos-verdes', v_a::text || '/2026-11.pdf', v_a, v_a::text,
          jsonb_build_object('mimetype', 'application/pdf', 'size', 1024))
  ON CONFLICT DO NOTHING;

  BEGIN
    v_res := public.driver_mark_invoice_issued(2026, 11, 'PROVA-A-1', date '2026-12-02', v_a::text || '/2026-11.pdf');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;
  v_ok := v_erro IS NULL AND coalesce((v_res ->> 'tem_pdf')::boolean, false);
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P3a',
    'o_que', 'A marca "Já passei o recibo" de novembro com PDF',
    'esperado', 'ok, tem_pdf=true',
    'obtido', coalesce(v_erro, 'tem_pdf=' || (v_res ->> 'tem_pdf') || ', total=' || (v_res ->> 'total_faturar')),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  BEGIN
    PERFORM public.driver_mark_invoice_issued(2026, 11, 'PROVA-A-X', NULL, v_b::text || '/2026-11.pdf');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM;
  END;
  v_ok := v_erro = 'pdf_caminho_invalido';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P3b',
    'o_que', 'A tenta usar um ficheiro da pasta de outra pessoa',
    'esperado', 'pdf_caminho_invalido', 'obtido', coalesce(v_erro, 'passou (errado)'), 'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  BEGIN
    PERFORM public.driver_mark_invoice_issued(2026, 11, 'PROVA-A-Y', NULL, v_a::text || '/2026-11.png');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM;
  END;
  v_ok := v_erro = 'pdf_nao_encontrado';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P3c',
    'o_que', 'A indica um ficheiro que não foi enviado',
    'esperado', 'pdf_nao_encontrado', 'obtido', coalesce(v_erro, 'passou (errado)'), 'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  BEGIN
    v_res := public.driver_mark_invoice_issued(p_year => 2026, p_month => 11, p_numero => 'PROVA-A-2');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;
  SELECT i.recibo_pdf_path INTO v_tmp FROM public.driver_monthly_invoices i
  WHERE i.user_id = v_a AND i.ano = 2026 AND i.mes = 11;
  SELECT count(*) INTO v_n FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace AND proname = 'driver_mark_invoice_issued';
  v_ok := v_erro IS NULL AND v_tmp IS NOT NULL AND v_n = 1;
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P3d',
    'o_que', 'Chamada da app publicada (3 nomes, sem PDF): resolve sem ambiguidade e não apaga o PDF',
    'esperado', 'ok, PDF mantém-se, 1 só função',
    'obtido', coalesce(v_erro, 'pdf=' || coalesce(v_tmp, 'NULL') || ', funções=' || v_n),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  -- ---------------------------------------------------------------- P4: A é pago normalmente
  v_t := public.prestador_recibo_trava(v_a);
  BEGIN
    v_res := public.admin_set_settlement_state('driver', v_a::text, v_a_ws, NULL, 'PROVA-R1a');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;
  SELECT s.status INTO v_tmp FROM public.driver_weekly_settlements s WHERE s.id = v_a_id;
  v_ok := NOT coalesce((v_t ->> 'retido')::boolean, true) AND v_erro IS NULL AND v_tmp = 'paid';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P4',
    'o_que', 'A (com recibo e PDF) — Marcar pago a semana ' || v_a_ws,
    'esperado', 'não retido; estado paid',
    'obtido', coalesce(v_erro, 'retido=' || coalesce(v_t ->> 'retido', '?') || ', estado=' || coalesce(v_tmp, '?')),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  -- ---------------------------------------------------------------- P5: B sem recibo depois do dia 10
  v_t := public.prestador_recibo_trava(v_b);
  v_pp_antes := coalesce((v_t -> 'por_pagar' ->> 'total_cents')::bigint, 0);
  v_ok := coalesce((v_t ->> 'retido')::boolean, false)
          AND coalesce(v_t ->> 'motivo', '') LIKE '%novembro de 2026%'
          AND v_pp_antes >= v_w1_c + v_w2_c;
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P5a',
    'o_que', 'B (sem recibo) a 11/12: está retido e o dinheiro guardado é o das semanas por pagar',
    'esperado', 'retido; motivo com "novembro de 2026"; guardado >= ' || replace(to_char((v_w1_c + v_w2_c) / 100.0, 'FM999990.00'), '.', ',') || ' €',
    'obtido', coalesce(v_t ->> 'motivo', 'não retido') || ' | guardado: '
              || replace(to_char(v_pp_antes / 100.0, 'FM999990.00'), '.', ',') || ' €',
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  BEGIN
    v_res := public.admin_set_settlement_state('driver', v_b::text, v_w1_ws, NULL, 'PROVA-R1a');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;
  SELECT s.status INTO v_tmp FROM public.driver_weekly_settlements s WHERE s.id = v_w1;
  v_ok := coalesce(v_erro, '') LIKE 'recibo_verde_em_falta:%' AND v_tmp = 'pending';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P5b',
    'o_que', 'B — "Marcar pago" (Acertos da semana) a semana ' || v_w1_ws,
    'esperado', 'bloqueado (recibo_verde_em_falta) e a linha continua por pagar',
    'obtido', coalesce(v_erro, 'passou (errado)') || ' | estado=' || coalesce(v_tmp, '?'),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  BEGIN
    v_res := public.admin_marcar_acerto_pago(v_b, date_trunc('week', v_w2_ws::timestamp)::date, 'transferencia', 'PROVA-R1a');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;
  SELECT s.status INTO v_tmp FROM public.driver_weekly_settlements s WHERE s.id = v_w2;
  v_ok := coalesce(v_erro, '') LIKE 'recibo_verde_em_falta:%' AND v_tmp = 'pending';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P5c',
    'o_que', 'B — botão do acerto unificado (admin_marcar_acerto_pago) a semana ' || v_w2_ws,
    'esperado', 'bloqueado também',
    'obtido', coalesce(v_erro, 'passou (errado)') || ' | estado=' || coalesce(v_tmp, '?'),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  v_res := public.admin_acerto_unificado(date_trunc('week', v_w1_ws::timestamp)::date);
  SELECT i INTO v_item FROM jsonb_array_elements(coalesce(v_res -> 'itens', '[]'::jsonb)) i
  WHERE (i ->> 'user_id')::uuid = v_b LIMIT 1;
  v_ok := coalesce((v_item ->> 'retido')::boolean, false);
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P5d',
    'o_que', 'Painel — a linha de B no acerto unificado diz "Retido" e o motivo',
    'esperado', 'retido=true com motivo',
    'obtido', coalesce(v_item ->> 'retido_motivo', 'sem linha de B nesta semana') || ' | retido=' || coalesce(v_item ->> 'retido', '?'),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  -- ---------------------------------------------------------------- P6: quem deve continua a ser cobrado
  BEGIN
    v_res := public.admin_set_settlement_state('driver', v_b::text, v_wd_ws, NULL, 'PROVA-R1a');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;
  SELECT s.status INTO v_tmp FROM public.driver_weekly_settlements s WHERE s.id = v_wd;
  v_ok := v_erro IS NULL AND v_tmp = 'received';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P6',
    'o_que', 'B (retido) DEVE à Bora na semana ' || v_wd_ws || ' — marcar recebido',
    'esperado', 'passa como hoje (received)',
    'obtido', coalesce(v_erro, 'estado=' || coalesce(v_tmp, '?') || ', valor '
              || replace(to_char(v_wd_c / 100.0, 'FM999990.00'), '.', ',') || ' €'),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  -- ---------------------------------------------------------------- P7: B anexa → solta e acumula certo
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_b::text, true);

  INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
  VALUES ('recibos-verdes', v_b::text || '/2026-11.pdf', v_b, v_b::text,
          jsonb_build_object('mimetype', 'application/pdf', 'size', 1024))
  ON CONFLICT DO NOTHING;

  BEGIN
    v_res := public.driver_mark_invoice_issued(2026, 11, 'PROVA-B-1', date '2026-12-11', v_b::text || '/2026-11.pdf');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM; v_res := NULL;
  END;

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  v_t := public.prestador_recibo_trava(v_b);
  v_ok := v_erro IS NULL
          AND NOT coalesce((v_t ->> 'retido')::boolean, true)
          AND coalesce((v_t -> 'por_pagar' ->> 'total_cents')::bigint, -1) = v_pp_antes;
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P7a',
    'o_que', 'B anexa o recibo de novembro com PDF',
    'esperado', 'deixa de estar retido; o guardado continua igual (nada se perdeu)',
    'obtido', coalesce(v_erro, 'retido=' || coalesce(v_t ->> 'retido', '?') || ' | guardado: '
              || replace(to_char(coalesce((v_t -> 'por_pagar' ->> 'total_cents')::bigint, 0) / 100.0, 'FM999990.00'), '.', ',') || ' €'),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  BEGIN
    PERFORM public.admin_set_settlement_state('driver', v_b::text, v_w1_ws, NULL, 'PROVA-R1a');
    PERFORM public.admin_set_settlement_state('driver', v_b::text, v_w2_ws, NULL, 'PROVA-R1a');
    v_erro := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM;
  END;
  SELECT count(*) FILTER (WHERE s.status = 'paid'), coalesce(sum(round(s.net_balance * 100)), 0)::bigint
  INTO v_n, v_soma
  FROM public.driver_weekly_settlements s
  WHERE s.id IN (v_w1, v_w2);
  v_ok := v_erro IS NULL AND v_n = 2 AND v_soma = v_w1_c + v_w2_c;
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P7b',
    'o_que', 'Primeiro acerto depois do recibo: pagar as 2 semanas guardadas de B',
    'esperado', '2 semanas pagas, total ' || replace(to_char((v_w1_c + v_w2_c) / 100.0, 'FM999990.00'), '.', ',') || ' €',
    'obtido', coalesce(v_erro, v_n || ' semanas pagas, total ' || replace(to_char(v_soma / 100.0, 'FM999990.00'), '.', ',') || ' €'),
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  v_t := public.prestador_recibo_trava(v_b);
  v_pp_depois := coalesce((v_t -> 'por_pagar' ->> 'total_cents')::bigint, -1);
  v_ok := v_pp_depois = v_pp_antes - (v_w1_c + v_w2_c);
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P7c',
    'o_que', 'O guardado de B desce exatamente o que foi pago',
    'esperado', replace(to_char((v_pp_antes - v_w1_c - v_w2_c) / 100.0, 'FM999990.00'), '.', ',') || ' €',
    'obtido', replace(to_char(v_pp_depois / 100.0, 'FM999990.00'), '.', ',') || ' €',
    'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  -- ---------------------------------------------------------------- P8: conta do dono + soltar com motivo
  IF v_dono IS NULL THEN
    v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P8',
      'o_que', 'Conta do dono', 'esperado', '-', 'obtido', 'sem dados do dono em novembro — passo saltado', 'ok', true));
  ELSE
    SELECT s.id, (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date INTO v_do_id, v_do_ws
    FROM public.driver_weekly_settlements s
    WHERE s.driver_id = v_dono AND s.status = 'paid' AND s.net_balance > 0
    ORDER BY s.week_start_at DESC LIMIT 1;
    v_antes := v_antes || coalesce((SELECT jsonb_object_agg(s.id::text, s.net_balance)
                                    FROM public.driver_weekly_settlements s WHERE s.id = v_do_id), '{}'::jsonb);
    UPDATE public.driver_weekly_settlements
       SET status = 'pending', paid_at = NULL, paid_by = NULL
     WHERE id = v_do_id;

    v_t := public.prestador_recibo_trava(v_dono);
    v_ok := coalesce(v_t ->> 'excluido', '') = 'conta_dono' AND NOT coalesce((v_t ->> 'retido')::boolean, true);
    v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P8a',
      'o_que', 'Conta do dono com fecho_dono_passa_recibo=false',
      'esperado', 'saltada (conta_dono), não retida',
      'obtido', 'excluido=' || coalesce(v_t ->> 'excluido', '-') || ', retido=' || coalesce(v_t ->> 'retido', '?'),
      'ok', v_ok));
    v_tudo := v_tudo AND coalesce(v_ok, false);

    UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'fecho_dono_passa_recibo';
    v_t := public.prestador_recibo_trava(v_dono);
    BEGIN
      v_res := public.admin_set_settlement_state('driver', v_dono::text, v_do_ws, NULL, 'PROVA-R1a');
      v_erro := NULL;
    EXCEPTION WHEN OTHERS THEN
      v_erro := SQLERRM; v_res := NULL;
    END;
    v_ok := coalesce((v_t ->> 'retido')::boolean, false) AND coalesce(v_erro, '') LIKE 'recibo_verde_em_falta:%';
    v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P8b',
      'o_que', 'Conta do dono com fecho_dono_passa_recibo=true (sem recibo de novembro)',
      'esperado', 'retida e Marcar pago bloqueado',
      'obtido', 'retido=' || coalesce(v_t ->> 'retido', '?') || ' | ' || coalesce(v_erro, 'passou (errado)'),
      'ok', v_ok));
    v_tudo := v_tudo AND coalesce(v_ok, false);

    BEGIN
      v_res := public.admin_soltar_retido_recibo('driver', v_dono::text, v_do_ws, 'Prova R1a: recibo recebido por email');
      PERFORM public.admin_set_settlement_state('driver', v_dono::text, v_do_ws, NULL, 'PROVA-R1a');
      v_erro := NULL;
    EXCEPTION WHEN OTHERS THEN
      v_erro := SQLERRM;
    END;
    SELECT s.status INTO v_tmp FROM public.driver_weekly_settlements s WHERE s.id = v_do_id;
    v_ok := v_erro IS NULL AND v_tmp = 'paid'
            AND EXISTS (SELECT 1 FROM public.admin_audit_log a
                        WHERE a.action = 'recibo_retido_pago_com_soltura' AND a.entity_id_text = v_do_id::text);
    v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P8c',
      'o_que', 'Admin solta a semana ' || v_do_ws || ' com motivo escrito e marca pago',
      'esperado', 'paid + registo na auditoria',
      'obtido', coalesce(v_erro, 'estado=' || coalesce(v_tmp, '?')),
      'ok', v_ok));
    v_tudo := v_tudo AND coalesce(v_ok, false);
  END IF;

  -- ---------------------------------------------------------------- P9: interruptor
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'recibos_trava_ativa';
  v_t := public.prestador_recibo_trava(coalesce(v_dono, v_b));
  v_ok := coalesce(v_t ->> 'excluido', '') = 'trava_desligada';
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P9',
    'o_que', 'Interruptor recibos_trava_ativa=false',
    'esperado', 'trava_desligada', 'obtido', coalesce(v_t ->> 'excluido', '-'), 'ok', v_ok));
  v_tudo := v_tudo AND coalesce(v_ok, false);
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'recibos_trava_ativa';

  -- ---------------------------------------------------------------- P10: nenhum valor mudou
  SELECT bool_and(s.net_balance = (v_antes ->> s.id::text)::numeric), count(*)
  INTO v_ok, v_n
  FROM public.driver_weekly_settlements s
  WHERE v_antes ? s.id::text;
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P10',
    'o_que', 'Os valores de todas as linhas mexidas ficaram iguais',
    'esperado', 'todos iguais', 'obtido', v_n || ' linhas conferidas, iguais=' || coalesce(v_ok::text, '?'),
    'ok', coalesce(v_ok, false)));
  v_tudo := v_tudo AND coalesce(v_ok, false);

  -- ---------------------------------------------------------------- P11: quem receberia o aviso do dia 10 (sem enviar)
  SELECT count(*) INTO v_n
  FROM jsonb_array_elements(public._recibo_resumo_calc(2026, 11, NULL) -> 'prestadores') e
  WHERE coalesce((e ->> 'precisa_recibo')::boolean, false) AND NOT coalesce((e ->> 'tem_pdf')::boolean, false);
  v_out := v_out || jsonb_build_array(jsonb_build_object('passo', 'P11',
    'o_que', 'Informativo: quantos ainda receberiam o aviso de novembro (nada é enviado)',
    'esperado', '-', 'obtido', v_n || ' pessoa(s)', 'ok', true));

  RAISE EXCEPTION 'PROVA_R1a % %', CASE WHEN v_tudo THEN 'TUDO_OK' ELSE 'HA_FALHAS' END, v_out::text
    USING ERRCODE = 'P0001',
          HINT = 'Este erro é de propósito: é assim que se garante que nada fica gravado (tudo desfeito).';
END
$prova$;

ROLLBACK;
