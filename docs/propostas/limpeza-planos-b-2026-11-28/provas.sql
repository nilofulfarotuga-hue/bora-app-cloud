-- ============================================================================
-- PROVAS do Bloco B (planos de limpeza) — TUDO dentro de uma transação DESFEITA.
-- Correr DEPOIS de migracao.sql:  psql -v ON_ERROR_STOP=1 -f provas.sql
-- Cada prova é um bloco DO que levanta exceção se falhar (a transação pára aí) e escreve
-- "PROVA_OK Pn …" quando passa. No fim: ROLLBACK — nada fica gravado (nem clientes, nem
-- profissionais, nem carteira). Nenhuma chamada à Stripe: os resultados da Stripe são
-- simulados pelas funções do servidor que as Edge chamam (cleaning_plan_charge_result,
-- cleaning_plan_refund_result, cleaning_plan_card_saved, cleaning_plan_webhook_payment).
--
-- P1 criar plano (+ erros que a app traduz)   P2 ativar (cartão) e gerar visitas
-- P3 preço por vaga (equipa de 2)              P4 exceção da oferta antes de cobrar
-- P5 saltar                                    P6 cobrança com profissional
-- P7 Bora Empresas: cobrança sem profissional, acesso só no dia
-- P8 nova tentativa (cartão recusado, rede, 3D Secure, webhook)
-- P9 devolução (cliente desmarca → carteira; pausa no painel → cartão)
-- P10 chamada repetida com a mesma chave (nada conta duas vezes)
-- P11 cancelar o plano                         P12 painel, guarda do admin e permissões
-- ============================================================================
BEGIN;

-- quem está a chamar (como o PostgREST faz: sub + claims)
CREATE FUNCTION pg_temp.como(p_uid uuid, p_admin boolean DEFAULT false) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_uid::text, ''), true),
         set_config('request.jwt.claim.role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated',
           'email', 'prova@exemplo.pt', 'app_metadata', json_build_object('role', CASE WHEN p_admin THEN 'admin' END))::text, true);
$$;
CREATE FUNCTION pg_temp.prova(p_ok boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF NOT COALESCE(p_ok, false) THEN RAISE EXCEPTION 'PROVA_FALHOU: %', p_msg; END IF; END $$;

CREATE TEMP TABLE ids (k text PRIMARY KEY, v uuid);

-- Cenário: 1 cliente, 1 cliente empresa, 2 profissionais aprovadas e disponíveis todos os dias.
DO $$
DECLARE c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
        k1 uuid; k2 uuid; d int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (c1, 'prova-plano-casa@exemplo.pt'), (c2, 'prova-plano-empresa@exemplo.pt'),
                                            (u1, 'prova-pro-1@exemplo.pt'), (u2, 'prova-pro-2@exemplo.pt');
  INSERT INTO cleaners (user_id, name, approval_status, is_active, service_radius_km, rating_avg, cleanings_done)
  VALUES (u1, 'Prova Ana', 'approved', true, 50, 5, 10) RETURNING id INTO k1;
  INSERT INTO cleaners (user_id, name, approval_status, is_active, service_radius_km, rating_avg, cleanings_done)
  VALUES (u2, 'Prova Bia', 'approved', true, 50, 4.9, 5) RETURNING id INTO k2;
  FOR d IN 0..6 LOOP
    INSERT INTO cleaner_availability (cleaner_id, weekday, start_time, end_time) VALUES (k1, d, '06:00', '23:59'), (k2, d, '06:00', '23:59');
  END LOOP;
  INSERT INTO ids VALUES ('c1', c1), ('c2', c2), ('u1', u1), ('u2', u2), ('k1', k1), ('k2', k2);
  -- interruptores no estado de produção para a prova (desfaz-se no ROLLBACK)
  -- (wallet_split_free_pct = 1: 100 % saldo livre, como está no ar desde 28/10/2026)
  INSERT INTO platform_settings (key, value) VALUES ('cleaning_stripe_enabled', 'true'::jsonb), ('cleaning_enabled', 'true'::jsonb),
                                                    ('wallet_split_free_pct', '1'::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END $$;

-- P1 criar plano ------------------------------------------------------------
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); j jsonb; j2 jsonb; p cleaning_plans; v_err text;
        v_inicio date := (now() AT TIME ZONE 'Europe/Lisbon')::date + 2;
BEGIN
  PERFORM pg_temp.como(c1);
  j := public.cleaning_plan_create('casa', 'weekly', 3, ARRAY[extract(isodow FROM v_inicio)::int], '10:00', v_inicio,
         1, 'client', 't2', 'per_visit', 'Rua da Prova 1', 'Guarda', '6300-000', 40.5373, -7.2676, '',
         NULL, NULL, NULL, NULL, NULL, '{}', NULL, 'prova-chave-1');
  SELECT * INTO p FROM cleaning_plans WHERE id = (j->>'id')::uuid;
  PERFORM pg_temp.prova(p.status = 'pending_card', 'plano nasce pending_card');
  PERFORM pg_temp.prova(p.client_cents_per_hour = 1000 AND p.pro_cents_per_hour = 918, 'preço semanal congelado 10,00/9,18');
  PERFORM pg_temp.prova(p.total_per_visit_cents = 3000 + p.travel_fee_cents_per_pro, 'total por visita = 3 h × 10 € + deslocação');
  PERFORM pg_temp.prova(NOT EXISTS (SELECT 1 FROM cleaning_bookings WHERE plan_id = p.id), 'sem cartão não há visitas');
  PERFORM pg_temp.prova(NOT EXISTS (SELECT 1 FROM cleaning_plan_charges WHERE plan_id = p.id), 'criar não cobra nada');
  j2 := public.cleaning_plan_create('casa', 'weekly', 3, ARRAY[extract(isodow FROM v_inicio)::int], '10:00', v_inicio,
         1, 'client', 't2', 'per_visit', 'Rua da Prova 1', 'Guarda', '6300-000', 40.5373, -7.2676, '',
         NULL, NULL, NULL, NULL, NULL, '{}', NULL, 'prova-chave-1');
  PERFORM pg_temp.prova(j2->>'id' = j->>'id', 'mesma chave = mesmo plano');
  -- erros com as palavras que a app traduz
  BEGIN PERFORM public.cleaning_plan_create('casa','weekly',1,ARRAY[1],'10:00',v_inicio,1,'client','t2','per_visit','Rua','Guarda','6300',40.5373,-7.2676,'',NULL,NULL,NULL,NULL,NULL,'{}',NULL,NULL);
    RAISE EXCEPTION 'devia falhar'; EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%horas_minimas%', 'casa com 1 h → horas_minimas (' || v_err || ')');
  BEGIN PERFORM public.cleaning_plan_create('casa','weekly',3,ARRAY[1,3],'10:00',v_inicio,1,'client','t2','per_visit','Rua','Guarda','6300',40.5373,-7.2676,'',NULL,NULL,NULL,NULL,NULL,'{}',NULL,NULL);
    RAISE EXCEPTION 'devia falhar'; EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%dias_da_semana%', 'semanal com 2 dias → dias_da_semana');
  BEGIN PERFORM public.cleaning_plan_create('casa','weekly',3,ARRAY[1],'05:00',v_inicio,1,'client','t2','per_visit','Rua','Guarda','6300',40.5373,-7.2676,'',NULL,NULL,NULL,NULL,NULL,'{}',NULL,NULL);
    RAISE EXCEPTION 'devia falhar'; EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%hora_entre_6_e_23%', '05:00 → hora_entre_6_e_23');
  BEGIN PERFORM public.cleaning_plan_create('casa','weekly',3,ARRAY[1],'10:00',v_inicio,1,'client','t2','per_visit','',  'Guarda','6300',NULL,NULL,'',NULL,NULL,NULL,NULL,NULL,'{}',NULL,NULL);
    RAISE EXCEPTION 'devia falhar'; EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%morada_obrigatoria%', 'sem morada → morada_obrigatoria');
  BEGIN PERFORM public.cleaning_plan_create('empresa','weekly_1',1,ARRAY[1],'20:00',v_inicio,1,'cleaner',NULL,'per_visit','Rua','Guarda','6300',40.5373,-7.2676,'','Ótica Prova','12345',NULL,'otica',NULL,'{}',NULL,NULL);
    RAISE EXCEPTION 'devia falhar'; EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%nif_invalido%', 'NIF com 5 algarismos → nif_invalido');
  BEGIN PERFORM public.cleaning_plan_create('empresa','once',1,ARRAY[1],'20:00',v_inicio,1,'cleaner',NULL,'monthly','Rua','Guarda','6300',40.5373,-7.2676,'','Ótica Prova','123456789','a@b.pt','otica',NULL,'{}',NULL,NULL);
    RAISE EXCEPTION 'devia falhar'; EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%billing_mode%', 'uma vez + o mês de uma vez → recusado');
  INSERT INTO ids VALUES ('plano', p.id);
  RAISE NOTICE 'PROVA_OK P1 criar plano: % (30,00 € por visita, pending_card, chave repetida devolve o mesmo, 6 erros certos)', p.id;
END $$;

-- P2 ativar: o cartão fica guardado → ativo → visitas geradas ------------------
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); pid uuid := (SELECT v FROM ids WHERE k = 'plano'); r jsonb; n int; b cleaning_bookings;
BEGIN
  r := public.cleaning_plan_card_saved(pid, c1, 'cus_prova', 'pm_prova', 'visa', '4242', 12, 2030);
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plans WHERE id = pid) = 'active', 'plano ativo depois do cartão');
  SELECT count(*) INTO n FROM cleaning_bookings WHERE plan_id = pid;
  PERFORM pg_temp.prova(n BETWEEN 2 AND 3, 'semanal gera 2 a 3 visitas em 14 dias (gerou ' || n || ')');
  SELECT * INTO b FROM cleaning_bookings WHERE plan_id = pid ORDER BY scheduled_at LIMIT 1;
  PERFORM pg_temp.prova(b.payment_method = 'card' AND b.payment_status = 'unpaid' AND b.stripe_account = 'empresa'
                        AND b.recurrence = 'single' AND b.plan_visit_date IS NOT NULL, 'visita = reserva de cartão por pagar, conta empresa');
  PERFORM pg_temp.prova(b.scheduled_at >= now() + interval '36 hours', 'só a partir de 36 h');
  PERFORM pg_temp.prova(to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') = '10:00', 'hora de Lisboa');
  PERFORM pg_temp.prova(b.total_cents = 3000 + b.travel_fee_cents AND b.cleaner_earnings_cents = 2754 + b.travel_fee_cents
                        AND b.bora_fee_cents = 246, 'cliente 30 €, profissional 27,54 €, Bora 2,46 €');
  PERFORM pg_temp.prova(public._cleaning_plan_gerar_visitas(pid) = 0, 'gerar outra vez não duplica');
  PERFORM pg_temp.prova((public.cleaning_plan_card_saved(pid, c1, 'cus_prova', 'pm_prova', 'visa', '4242', 12, 2030))->>'already' = 'true',
                        'guardar o mesmo cartão outra vez = nada muda');
  RAISE NOTICE 'PROVA_OK P2 ativar: % visitas, primeira % (Lisboa), 30,00 / 27,54 / 2,46', n,
    to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI');
END $$;

-- P3 preço por vaga: casa T3, semanal 3 h, 2 profissionais, produtos da profissional ----
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); j jsonb; pid uuid; s1 cleaning_bookings; s2 cleaning_bookings; q jsonb;
        v_inicio date := (now() AT TIME ZONE 'Europe/Lisbon')::date + 3;
BEGIN
  PERFORM pg_temp.como(c1);
  j := public.cleaning_plan_create('casa', 'weekly', 3, ARRAY[extract(isodow FROM v_inicio)::int], '09:00', v_inicio,
         2, 'cleaner', 't3', 'per_visit', 'Rua da Prova 3', 'Guarda', '6300-000', 40.5373, -7.2676, '',
         NULL, NULL, NULL, NULL, NULL, '{}', NULL, 'prova-chave-equipa');
  pid := (j->>'id')::uuid;
  q := public.cleaning_plan_quote('casa', 'weekly', 3, 1, 2, 'cleaner', 40.5373, -7.2676);
  PERFORM public.cleaning_plan_card_saved(pid, c1, 'cus_prova', 'pm_prova2', 'visa', '4242', 12, 2030);
  SELECT * INTO s1 FROM cleaning_bookings WHERE plan_id = pid AND team_slot = 1 ORDER BY scheduled_at LIMIT 1;
  SELECT * INTO s2 FROM cleaning_bookings WHERE team_group_id = s1.team_group_id AND team_slot = 2;
  PERFORM pg_temp.prova(s1.team_size = 2 AND s2.id IS NOT NULL, 'equipa de 2 = duas reservas ligadas');
  PERFORM pg_temp.prova(s1.total_cents = (q->>'total_per_visit_cents')::int AND s2.total_cents = 0, 'vaga 1 leva o total da equipa (= cleaning_plan_quote)');
  PERFORM pg_temp.prova(s1.share_cents = 3000 + 300 + s1.travel_fee_cents AND s2.share_cents = 3000 + s2.travel_fee_cents, 'parte do cliente por vaga');
  PERFORM pg_temp.prova(s1.cleaner_earnings_cents = 2754 + 300 + s1.travel_fee_cents AND s2.cleaner_earnings_cents = 2754 + s2.travel_fee_cents,
                        'profissional: 27,54 € + deslocação (+ 3 € de produtos na vaga 1)');
  PERFORM pg_temp.prova(s1.bora_fee_cents = 246 AND s2.bora_fee_cents = 246, 'Bora fica com a diferença por hora (2,46 € por vaga)');
  PERFORM pg_temp.prova(s1.share_cents + s2.share_cents = s1.total_cents, 'as partes somam o total');
  INSERT INTO ids VALUES ('plano_equipa', pid);
  RAISE NOTICE 'PROVA_OK P3 preço por vaga: total %, vaga1 % / pro %, vaga2 % / pro %', s1.total_cents, s1.share_cents,
    s1.cleaner_earnings_cents, s2.share_cents, s2.cleaner_earnings_cents;
END $$;

-- P4 exceção da oferta: a visita de plano ativo toca antes de pagar; uma reserva de cartão normal não --
DO $$
DECLARE pid uuid := (SELECT v FROM ids WHERE k = 'plano'); c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); b cleaning_bookings; v_normal uuid;
BEGIN
  SELECT * INTO b FROM cleaning_bookings WHERE plan_id = pid ORDER BY scheduled_at LIMIT 1;
  PERFORM pg_temp.prova(b.offer_cleaner_id IS NOT NULL AND b.payment_status = 'unpaid', 'visita do plano já foi oferecida sem estar paga');
  INSERT INTO cleaning_bookings (client_user_id, recurrence, cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
     address_street, address_city, address_postal, lat, lng, notes, products_by, payment_method, payment_status,
     base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents, total_cents, cleaner_earnings_cents, bora_fee_cents)
  VALUES (c1, 'single', 'standard', 'hourly', 't2', 3, now() + interval '3 days', 180, 'Rua', 'Guarda', '6300', 40.5373, -7.2676, '',
          'client', 'card', 'unpaid', 3600, 0, 0, 0, 3600, 3060, 540) RETURNING id INTO v_normal;
  PERFORM public._cleaning_next_offer(v_normal);
  PERFORM pg_temp.prova((SELECT offer_cleaner_id FROM cleaning_bookings WHERE id = v_normal) IS NULL,
                        'reserva de cartão normal por pagar continua sem tocar (regra de 19/10)');
  UPDATE cleaning_bookings SET status = 'cancelled_client', cancelled_by = 'client' WHERE id = v_normal;
  RAISE NOTICE 'PROVA_OK P4 oferta antes de cobrar só nos planos';
END $$;

-- P5 saltar --------------------------------------------------------------------
DO $$
DECLARE pid uuid := (SELECT v FROM ids WHERE k = 'plano'); c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); b cleaning_bookings; v_err text; n int;
BEGIN
  PERFORM pg_temp.como(c1);
  SELECT * INTO b FROM cleaning_bookings WHERE plan_id = pid AND status NOT LIKE 'cancelled%' ORDER BY scheduled_at DESC LIMIT 1;
  PERFORM public.cleaning_plan_skip(pid, b.plan_visit_date);
  PERFORM pg_temp.prova((SELECT status FROM cleaning_bookings WHERE id = b.id) = 'cancelled_client', 'a visita saltada foi desmarcada');
  PERFORM pg_temp.prova(b.plan_visit_date = ANY ((SELECT skipped_dates FROM cleaning_plans WHERE id = pid)::date[]), 'o dia ficou em skipped_dates');
  PERFORM public._cleaning_plan_gerar_visitas(pid);
  SELECT count(*) INTO n FROM cleaning_bookings WHERE plan_id = pid AND plan_visit_date = b.plan_visit_date AND status NOT LIKE 'cancelled%';
  PERFORM pg_temp.prova(n = 0, 'dia saltado não volta a nascer');
  -- a menos de 24 h não se salta
  SELECT * INTO b FROM cleaning_bookings WHERE plan_id = pid AND status NOT LIKE 'cancelled%' ORDER BY scheduled_at LIMIT 1;
  UPDATE cleaning_bookings SET scheduled_at = now() + interval '10 hours' WHERE id = b.id;
  BEGIN PERFORM public.cleaning_plan_skip(pid, b.plan_visit_date); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%saltar_so_ate_24h%', 'a 10 h → saltar_so_ate_24h');
  UPDATE cleaning_bookings SET scheduled_at = now() + interval '30 hours' WHERE id = b.id;   -- volta para a P6
  INSERT INTO ids VALUES ('visita1', b.id);
  RAISE NOTICE 'PROVA_OK P5 saltar (grátis a mais de 24 h; recusado a 10 h)';
END $$;

-- P6 cobrança com profissional --------------------------------------------------
DO $$
DECLARE pid uuid := (SELECT v FROM ids WHERE k = 'plano'); v1 uuid := (SELECT v FROM ids WHERE k = 'visita1');
        k1 uuid := (SELECT v FROM ids WHERE k = 'k1'); r jsonb; ch cleaning_plan_charges; x jsonb;
BEGIN
  -- a profissional aceita (como cleaner_accept_booking faz)
  UPDATE cleaning_bookings SET status = 'accepted', cleaner_id = k1, accepted_at = now(), offer_cleaner_id = NULL, offer_expires_at = NULL
   WHERE id = v1;
  PERFORM pg_temp.prova((SELECT requested_cleaner_id FROM cleaning_plans WHERE id = pid) = k1, 'a primeira que aceita fica a profissional fixa');
  r := public.cleaning_plan_charges_due(25);                       -- 48 h antes: cria e avisa
  SELECT c.* INTO ch FROM cleaning_plan_charges c WHERE c.idempotency_key = 'visit-' || v1;
  PERFORM pg_temp.prova(ch.status = 'scheduled' AND ch.notice_sent_at IS NOT NULL, 'cobrança criada com aviso, à espera das 24 h');
  PERFORM pg_temp.prova(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'cobrar') e WHERE (e->>'charge_id')::uuid = ch.id),
                        'antes das 24 h não se cobra');
  UPDATE cleaning_plan_charges SET charge_after = now() - interval '1 minute' WHERE id = ch.id;  -- chegou a hora
  r := public.cleaning_plan_charges_due(25);
  SELECT e INTO x FROM jsonb_array_elements(r->'cobrar') e WHERE (e->>'charge_id')::uuid = ch.id;
  PERFORM pg_temp.prova(x IS NOT NULL, 'com a profissional confirmada vai a cobrar');
  PERFORM pg_temp.prova(x->>'stripe_idempotency_key' = 'cleaning-plan-visit-' || v1 || '-a1', 'chave da Stripe da 1.ª tentativa');
  PERFORM pg_temp.prova(x->>'payment_method_id' = 'pm_prova' AND (x->>'amount_cents')::int = ch.amount_cents, 'cartão guardado e valor certo');
  r := public.cleaning_plan_charge_result(ch.id, 1, 'succeeded', 'pi_prova_1', 'https://pay.stripe.com/receipts/prova', '4242');
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plan_charges WHERE id = ch.id) = 'succeeded', 'cobrança paga');
  PERFORM pg_temp.prova((SELECT payment_status FROM cleaning_bookings WHERE id = v1) = 'held', 'a visita ficou paga');
  INSERT INTO ids VALUES ('cobranca1', ch.id);
  RAISE NOTICE 'PROVA_OK P6 cobrança com profissional: % cobrados (24 h antes, chave -a1)', ch.amount_cents;
END $$;

-- P7 cobrança sem profissional (plano Bora Empresas): não cobra, avisa; cobra quando alguém aceita ---
DO $$
DECLARE c2 uuid := (SELECT v FROM ids WHERE k = 'c2'); k2 uuid := (SELECT v FROM ids WHERE k = 'k2'); u2 uuid := (SELECT v FROM ids WHERE k = 'u2');
        b cleaning_bookings; r jsonb; ch cleaning_plan_charges; j jsonb; pid uuid; info jsonb;
        v_inicio date := (now() AT TIME ZONE 'Europe/Lisbon')::date + 2;
BEGIN
  PERFORM pg_temp.como(c2);
  j := public.cleaning_plan_create('empresa', 'weekly_1', 1, ARRAY[extract(isodow FROM v_inicio)::int], '20:00', v_inicio,
         1, 'client', NULL, 'per_visit', 'Rua da Ótica 7', 'Guarda', '6300-000', 40.5373, -7.2676, 'tocar à campainha',
         'Ótica Prova', '123 456 789', 'Faturas@OticaProva.pt', 'otica', 40, ARRAY['varrer_aspirar','vidros_montra','x'],
         'chave no cofre 1234', 'prova-chave-empresa');
  pid := (j->>'id')::uuid;
  PERFORM pg_temp.prova((SELECT products_by = 'cleaner' AND billing_nif = '123456789' AND billing_email = 'faturas@oticaprova.pt'
                                AND tasks = ARRAY['varrer_aspirar','vidros_montra'] AND total_per_visit_cents = 1400 + travel_fee_cents_per_pro
                           FROM cleaning_plans WHERE id = pid), 'empresa: produtos incluídos, NIF/email limpos, 14 €/h');
  PERFORM public.cleaning_plan_card_saved(pid, c2, 'cus_prova_emp', 'pm_prova_emp', 'mastercard', '4444', 1, 2031);
  SELECT * INTO b FROM cleaning_bookings WHERE plan_id = pid ORDER BY scheduled_at LIMIT 1;
  PERFORM pg_temp.prova(b.notes LIKE 'Bora Empresas: Ótica Prova%' AND b.notes NOT LIKE '%1234%', 'notas com a empresa, nunca o acesso');
  PERFORM pg_temp.prova(to_char(b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') = '20:00', 'à hora da empresa (20:00)');
  -- a profissional a quem foi oferecida vê a empresa e as tarefas, mas não o acesso antes do dia
  PERFORM pg_temp.como((SELECT user_id FROM cleaners WHERE id = b.offer_cleaner_id));
  info := public.cleaning_plan_visit_info(b.id);
  PERFORM pg_temp.prova(info->>'company_name' = 'Ótica Prova' AND info->>'access_instructions' IS NULL
                        AND (info->>'access_available_on_the_day')::boolean, 'acesso escondido antes do dia');
  -- 20 h antes e ainda sem ninguém
  UPDATE cleaning_bookings SET scheduled_at = now() + interval '20 hours', offer_cleaner_id = NULL WHERE id = b.id;
  r := public.cleaning_plan_charges_due(25);
  SELECT * INTO ch FROM cleaning_plan_charges WHERE idempotency_key = 'visit-' || b.id;
  PERFORM pg_temp.prova(ch.status = 'waiting_cleaner' AND ch.no_cleaner_alerted_at IS NOT NULL, 'sem profissional: waiting_cleaner e alerta');
  PERFORM pg_temp.prova(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'cobrar') e WHERE (e->>'charge_id')::uuid = ch.id),
                        'sem profissional não se cobra');
  UPDATE cleaning_bookings SET status = 'accepted', cleaner_id = k2, accepted_at = now(),
         scheduled_at = date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon' + interval '23 hours 30 minutes'
   WHERE id = b.id;
  PERFORM pg_temp.como(u2);
  info := public.cleaning_plan_visit_info(b.id);
  PERFORM pg_temp.prova(info->>'access_instructions' = 'chave no cofre 1234', 'no dia, quem aceitou vê o acesso');
  UPDATE cleaning_bookings SET scheduled_at = now() + interval '20 hours' WHERE id = b.id;
  r := public.cleaning_plan_charges_due(25);
  PERFORM pg_temp.prova(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'cobrar') e WHERE (e->>'charge_id')::uuid = ch.id
                                   AND e->>'receipt_email' = 'faturas@oticaprova.pt' AND e->>'billing_nif' = '123456789'),
                        'logo que alguém aceita, vai a cobrar (recibo para o email de faturação, com NIF)');
  INSERT INTO ids VALUES ('visita2', b.id), ('cobranca2', ch.id);
  RAISE NOTICE 'PROVA_OK P7 Bora Empresas: sem profissional não cobra; cobra quando aceita; acesso só no dia';
END $$;


-- P8 nova tentativa: cartão recusado → +6 h com nova chave; rede → mesma chave ---------
DO $$
DECLARE ch uuid := (SELECT v FROM ids WHERE k = 'cobranca2'); v2 uuid := (SELECT v FROM ids WHERE k = 'visita2'); r jsonb; c cleaning_plan_charges; x jsonb;
BEGIN
  r := public.cleaning_plan_charge_result(ch, 1, 'card_error', 'pi_prova_falhou', NULL, NULL, 'Your card was declined.');
  SELECT * INTO c FROM cleaning_plan_charges WHERE id = ch;
  PERFORM pg_temp.prova(c.status = 'failed' AND c.attempts = 1 AND c.next_attempt_at > now(), 'recusado: failed, nova tentativa marcada');
  PERFORM pg_temp.prova(r #>> '{email,tipo}' = 'trocar_cartao', 'pede o email "troca o cartão"');
  PERFORM pg_temp.como((SELECT client_user_id FROM cleaning_plan_charges WHERE id = ch));
  PERFORM pg_temp.prova((public.cleaning_plan_mine() -> 0 ->> 'needs_action') = 'true', 'o plano mostra needs_action ao cliente');
  UPDATE cleaning_plan_charges SET next_attempt_at = now() - interval '1 minute' WHERE id = ch;
  r := public.cleaning_plan_charges_due(25);
  SELECT e INTO x FROM jsonb_array_elements(r->'cobrar') e WHERE (e->>'charge_id')::uuid = ch;
  PERFORM pg_temp.prova(x->>'stripe_idempotency_key' LIKE '%-a2', '2.ª tentativa com chave nova (-a2)');
  r := public.cleaning_plan_charge_result(ch, 2, 'transient', NULL, NULL, NULL, 'ECONNRESET');
  PERFORM pg_temp.prova((SELECT attempts FROM cleaning_plan_charges WHERE id = ch) = 2, 'erro de rede não conta como tentativa');
  r := public.cleaning_plan_charges_due(25);
  SELECT e INTO x FROM jsonb_array_elements(r->'cobrar') e WHERE (e->>'charge_id')::uuid = ch;
  PERFORM pg_temp.prova(x->>'stripe_idempotency_key' LIKE '%-a2' AND (x->>'repeat')::boolean, 'repete com a MESMA chave (-a2)');
  -- resultado velho de uma tentativa antiga não mexe em nada
  r := public.cleaning_plan_charge_result(ch, 1, 'card_error', NULL, NULL, NULL, 'velho');
  PERFORM pg_temp.prova((r->>'stale')::boolean, 'resultado da tentativa 1 ignorado');
  -- 3D Secure
  r := public.cleaning_plan_charge_result(ch, 2, 'requires_action', 'pi_prova_3ds', NULL, NULL, NULL);
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plan_charges WHERE id = ch) = 'requires_action', 'banco pede confirmação');
  PERFORM pg_temp.prova((public.cleaning_plan_action_charge(ch, (SELECT client_user_id FROM cleaning_plan_charges WHERE id = ch)))
                        ->>'payment_intent_id' = 'pi_prova_3ds', 'a app recebe o pagamento a confirmar');
  -- o webhook confirma o sucesso desse PaymentIntent
  r := public.cleaning_plan_webhook_payment(ch, 'succeeded', 'pi_prova_3ds', (SELECT amount_cents FROM cleaning_plan_charges WHERE id = ch), NULL, NULL);
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plan_charges WHERE id = ch) = 'succeeded'
                        AND (SELECT payment_status FROM cleaning_bookings WHERE id = v2) = 'held', 'webhook: paga e visita paga');
  RAISE NOTICE 'PROVA_OK P8 nova tentativa (-a1 recusado → -a2; rede repete -a2; 3D Secure; webhook)';
END $$;

-- P9 devoluções -----------------------------------------------------------------------
-- a) o cliente desmarca uma visita paga → Carteira Bora (o mesmo caminho do "Parar a série")
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); v1 uuid := (SELECT v FROM ids WHERE k = 'visita1');
        v_antes int; v_depois int; f cleaning_plan_refunds;
BEGIN
  PERFORM pg_temp.como(c1);
  v_antes := COALESCE((SELECT free_balance_cents FROM client_wallets WHERE user_id = c1), 0);
  PERFORM public.cancel_cleaning_booking(v1, 'prova', false);             -- cancelar só essa (a 30 h, sem taxa)
  SELECT * INTO f FROM cleaning_plan_refunds WHERE booking_id = v1;
  v_depois := COALESCE((SELECT free_balance_cents FROM client_wallets WHERE user_id = c1), 0);
  PERFORM pg_temp.prova(f.method = 'wallet' AND f.status = 'succeeded', 'devolução à carteira feita');
  PERFORM pg_temp.prova(v_depois - v_antes = f.amount_cents AND f.amount_cents = (SELECT total_cents FROM cleaning_bookings WHERE id = v1),
                        'a carteira subiu exatamente o que se pagou (' || f.amount_cents || ')');
  PERFORM pg_temp.prova(EXISTS (SELECT 1 FROM wallet_transactions WHERE idempotency_key LIKE '%limpeza_plano_' || v1),
                        'movimento da carteira com a chave da limpeza');
  RAISE NOTICE 'PROVA_OK P9a cliente desmarca visita paga → carteira +%', f.amount_cents;
END $$;

-- b) o admin pausa o plano → visita paga a mais de 24 h volta ao CARTÃO (robô devolve na Stripe)
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); pid uuid := (SELECT v FROM ids WHERE k = 'plano_equipa');
        b cleaning_bookings; ch uuid; r jsonb; f cleaning_plan_refunds; x jsonb; k1 uuid := (SELECT v FROM ids WHERE k = 'k1');
        k2 uuid := (SELECT v FROM ids WHERE k = 'k2');
BEGIN
  SELECT * INTO b FROM cleaning_bookings WHERE plan_id = pid AND team_slot = 1 ORDER BY scheduled_at LIMIT 1;
  -- a equipa toda confirmada e paga (como o robô faz), a 3 dias
  UPDATE cleaning_bookings SET status = 'accepted', cleaner_id = k1 WHERE id = b.id;
  UPDATE cleaning_bookings SET status = 'accepted', cleaner_id = k2 WHERE team_group_id = b.team_group_id AND team_slot = 2;
  INSERT INTO cleaning_plan_charges (plan_id, client_user_id, kind, idempotency_key, amount_cents, status, charge_after, attempts)
  VALUES (pid, c1, 'visit', 'visit-' || b.id, b.total_cents, 'processing', now(), 1) RETURNING id INTO ch;
  INSERT INTO cleaning_plan_charge_items (charge_id, booking_id, amount_cents) VALUES (ch, b.id, b.total_cents);
  PERFORM public.cleaning_plan_charge_result(ch, 1, 'succeeded', 'pi_prova_equipa', NULL, '4242');
  PERFORM pg_temp.prova((SELECT count(*) FROM cleaning_bookings WHERE team_group_id = b.team_group_id AND payment_status = 'held') = 2,
                        'a vaga 1 paga e a irmã fica paga (gatilho da equipa)');
  PERFORM pg_temp.como(c1, true);
  r := public.admin_cleaning_plan_set_status(pid, 'paused', 'prova de pausa');
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plans WHERE id = pid) = 'paused', 'plano em pausa');
  SELECT * INTO f FROM cleaning_plan_refunds WHERE booking_id = b.id;
  PERFORM pg_temp.prova(f.method = 'card' AND f.status = 'pending' AND f.amount_cents = b.total_cents, 'falha da Bora → devolução ao cartão, valor todo');
  PERFORM pg_temp.prova(EXISTS (SELECT 1 FROM admin_audit_log WHERE entity_type = 'cleaning_plans' AND entity_id = pid
                                   AND action = 'cleaning_plan_set_status'), 'ficou na auditoria');
  r := public.cleaning_plan_refunds_due(25);
  SELECT e INTO x FROM jsonb_array_elements(r) e WHERE (e->>'refund_id')::uuid = f.id;
  PERFORM pg_temp.prova(x->>'stripe_idempotency_key' = 'cleaning-plan-refund-' || f.id AND x->>'payment_intent_id' = 'pi_prova_equipa',
                        'robô devolve com a chave cleaning-plan-refund-<id>');
  PERFORM public.cleaning_plan_refund_result(f.id, true, 're_prova', NULL);
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plan_refunds WHERE id = f.id) = 'succeeded', 'devolução ao cartão feita');
  -- retomar volta a gerar
  r := public.admin_cleaning_plan_set_status(pid, 'active', 'prova de retomar');
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plans WHERE id = pid) = 'active', 'retomado');
  RAISE NOTICE 'PROVA_OK P9b pausa no painel → cartão % (auditado); retomar volta a gerar', f.amount_cents;
END $$;

-- P10 chamada repetida com a mesma chave: nada conta duas vezes ---------------------------
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); ch uuid := (SELECT v FROM ids WHERE k = 'cobranca1'); v1 uuid := (SELECT v FROM ids WHERE k = 'visita1');
        r jsonb; n int; v_saldo int;
BEGIN
  r := public.cleaning_plan_charge_result(ch, 1, 'succeeded', 'pi_prova_1', NULL, NULL);
  PERFORM pg_temp.prova((r->>'already')::boolean, 'sucesso repetido = já estava');
  r := public.cleaning_plan_charge_result(ch, 1, 'card_error', NULL, NULL, NULL, 'depois de pago');
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plan_charges WHERE id = ch) = 'succeeded', 'um succeeded nunca volta atrás');
  r := public.cleaning_plan_webhook_payment(ch, 'failed', 'pi_prova_1', NULL, NULL, 'tarde');
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plan_charges WHERE id = ch) = 'succeeded', 'evento de falha depois do sucesso não mexe');
  v_saldo := (SELECT free_balance_cents FROM client_wallets WHERE user_id = c1);
  PERFORM public._cleaning_plan_devolver(v1, 'wallet', 'repetida', 0);
  PERFORM pg_temp.prova((SELECT free_balance_cents FROM client_wallets WHERE user_id = c1) = v_saldo, 'a mesma devolução não credita duas vezes');
  SELECT count(*) INTO n FROM cleaning_plan_refunds WHERE booking_id = v1;
  PERFORM pg_temp.prova(n = 1, 'uma devolução por reserva');
  r := public.cleaning_plan_refunds_due(25);
  PERFORM pg_temp.prova(jsonb_array_length(r) = 0, 'devoluções feitas não voltam à fila');
  RAISE NOTICE 'PROVA_OK P10 repetido: sucesso, falha tardia, carteira e devolução — tudo contado uma vez';
END $$;

-- P11 cancelar o plano ---------------------------------------------------------------
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); pid uuid := (SELECT v FROM ids WHERE k = 'plano'); n_vivas int; v_err text;
BEGIN
  PERFORM pg_temp.como(c1);
  PERFORM public.cleaning_plan_cancel(pid, 'cliente');
  PERFORM pg_temp.prova((SELECT status FROM cleaning_plans WHERE id = pid) = 'cancelled', 'plano cancelado, sem taxa');
  SELECT count(*) INTO n_vivas FROM cleaning_bookings
   WHERE plan_id = pid AND status NOT LIKE 'cancelled%'
     AND (scheduled_at > now() + interval '24 hours' OR NOT public._cleaning_plan_visita_confirmada(id));
  PERFORM pg_temp.prova(n_vivas = 0, 'visitas a mais de 24 h e sem profissional desmarcadas');
  BEGIN PERFORM public.cleaning_plan_skip(pid, current_date + 10); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%plano_nao_ativo%', 'plano cancelado → plano_nao_ativo');
  PERFORM pg_temp.prova(public._cleaning_plan_gerar_visitas(pid) = 0, 'plano cancelado não gera mais');
  -- o que a app lê
  PERFORM pg_temp.prova(jsonb_typeof(public.cleaning_plan_mine()) = 'array', 'cleaning_plan_mine devolve lista');
  PERFORM pg_temp.prova(NOT (public.cleaning_plan_mine()::text LIKE '%pm_prova%' OR public.cleaning_plan_mine()::text LIKE '%cus_prova%'),
                        'nunca manda ao cliente os ids da Stripe');
  RAISE NOTICE 'PROVA_OK P11 cancelar o plano';
END $$;

-- P12 o painel lê; as reservas antigas não mudam -------------------------------------
DO $$
DECLARE c1 uuid := (SELECT v FROM ids WHERE k = 'c1'); s jsonb; l jsonb; d jsonb; v_err text;
BEGIN
  PERFORM pg_temp.como(c1, true);
  s := public.admin_cleaning_plans_summary();
  PERFORM pg_temp.prova((s->>'cobrado_mes_cents')::int > 0 AND (s->>'devolvido_mes_cents')::int > 0, 'resumo do mês com cobrado e devolvido');
  l := public.admin_list_cleaning_plans(NULL, NULL, 'prova-plano-casa');
  PERFORM pg_temp.prova(jsonb_array_length(l) >= 2 AND l->0 ? 'client_email' AND l->0 ? 'paid_cents', 'lista do painel com pesquisa por email');
  d := public.admin_cleaning_plan_detail((SELECT v FROM ids WHERE k = 'plano_equipa'));
  PERFORM pg_temp.prova(jsonb_array_length(d->'all_visits') > 0 AND jsonb_array_length(d->'all_refunds') > 0
                        AND jsonb_array_length(d->'audit') > 0, 'detalhe com visitas, devoluções e auditoria');
  PERFORM pg_temp.prova(jsonb_typeof(public.admin_list_cleaning_plan_charges(NULL)) = 'array', 'lista de cobranças');
  PERFORM pg_temp.como(c1, false);
  BEGIN PERFORM public.admin_cleaning_plans_summary(); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%admin_required%', 'cliente não entra no painel');
  PERFORM pg_temp.prova(NOT EXISTS (SELECT 1 FROM cleaning_bookings b WHERE b.plan_id IS NOT NULL AND b.client_user_id NOT IN
                          (SELECT v FROM ids WHERE k IN ('c1','c2'))), 'só as reservas da prova têm plan_id');
  PERFORM pg_temp.prova(NOT has_function_privilege('anon', 'public.cleaning_plan_create(text, text, integer, integer[], text, date, integer, text, text, text, text, text, text, double precision, double precision, text, text, text, text, text, integer, text[], text, text)', 'EXECUTE')
                        AND NOT has_function_privilege('anon', 'public.cleaning_plan_charges_due(integer)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.cleaning_plan_charges_due(integer)', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public.cleaning_plan_charge_result(uuid, integer, text, text, text, text, text)', 'EXECUTE'),
                        'funções novas fechadas a anon; as do robô só para o servidor');
  RAISE NOTICE 'PROVA_OK P12 painel (resumo, lista, detalhe, cobranças), guarda do admin e permissões';
END $$;

ROLLBACK;
