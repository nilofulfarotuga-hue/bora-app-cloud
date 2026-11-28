-- ============================================================================
-- PROVAS do Bloco A dos prémios do check-in — TUDO dentro de uma transação DESFEITA.
-- Correr DEPOIS de migracao.sql:  psql -v ON_ERROR_STOP=1 -f provas.sql
-- Cada prova é um bloco DO que levanta exceção se falhar e escreve "PROVA_OK Pn …" quando passa.
-- No fim: ROLLBACK — nada fica gravado. Pagamentos de teste: dinheiro, cartão sem Stripe (só o
-- servidor decide o que cobrar; nenhuma cobrança é feita).
--
-- P1 caso Divan: 4 h Standard em dinheiro com o prémio      P2 o mesmo vale não se usa duas vezes
-- P3 cancelar a tempo → o vale volta (pagamento em dinheiro)  P4 Profunda paga a diferença (cartão)
-- P5 2 h Standard no cartão → resto 0 → pago pelo prémio      P6 resto de 1 a 49 cêntimos só em dinheiro
-- P7 lavagem só por fora (cartão → prémio) e completa (paga a diferença)
-- P8 "Os meus prémios › Usar" passa pelo create            P9 série seguinte vai em dinheiro
-- P10 vale de outro cliente / expirado                       P11 banner: client_checkin_premio_servico_para_usar
-- P12 guarda de escrita direta e permissões                  P13 migração da reserva do Divan (cópia do bloco 8)
-- ============================================================================
BEGIN;

CREATE FUNCTION pg_temp.como(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_uid::text, ''), true),
         set_config('request.jwt.claim.role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;
CREATE FUNCTION pg_temp.prova(p_ok boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF NOT COALESCE(p_ok, false) THEN RAISE EXCEPTION 'PROVA_FALHOU: %', p_msg; END IF; END $$;
-- um vale do prémio dos 30 dias ("2 horas de limpeza ou uma lavagem exterior do carro")
CREATE FUNCTION pg_temp.vale(p_user uuid, p_valido interval DEFAULT interval '30 days') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO checkin_premios_vales (user_id, marco, marco_chave, tipo, estado, titulo, opcoes, valido_ate)
  VALUES (p_user, 30, 'mes', 'servico', 'por_usar', '2 horas de limpeza ou uma lavagem exterior do carro',
          ARRAY['limpeza','lavagem'], now() + p_valido)
  RETURNING id;
$$;
-- marcar uma limpeza pela marcação normal (como a app), com ou sem vale
CREATE FUNCTION pg_temp.limpeza(p_tipo text, p_horas int, p_metodo text, p_vale uuid, p_chave text,
                                p_recorrencia text DEFAULT 'single') RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.create_cleaning_booking(p_tipo, 'hourly', NULL, p_horas, now() + interval '3 days', p_recorrencia,
           'client', p_metodo, 'Rua da Prova 1', 'Guarda', '6300-000', 40.5373, -7.2676, '', NULL, p_chave, 1, p_vale);
$$;

CREATE TEMP TABLE ids (k text PRIMARY KEY, val uuid);

-- Cenário: 2 clientes com telemóvel (desde 28/11 10:19 não há marcação sem ele), 1 profissional e
-- 1 lavador aprovados e disponíveis. Interruptores como no ar (desfaz-se no ROLLBACK).
DO $$
DECLARE c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid();
        k1 uuid; w1 uuid; d int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (c1, 'prova-premio-1@exemplo.pt'), (c2, 'prova-premio-2@exemplo.pt'),
                                            (u1, 'prova-premio-pro@exemplo.pt'), (u2, 'prova-premio-lav@exemplo.pt');
  INSERT INTO public.users (id, phone) VALUES (c1, '+351912345670'), (c2, '+351912345671')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;
  INSERT INTO cleaners (user_id, name, approval_status, is_active, service_radius_km, rating_avg, cleanings_done)
  VALUES (u1, 'Prova Leonor', 'approved', true, 50, 5, 10) RETURNING id INTO k1;
  FOR d IN 0..6 LOOP
    INSERT INTO cleaner_availability (cleaner_id, weekday, start_time, end_time) VALUES (k1, d, '06:00', '23:59');
  END LOOP;
  INSERT INTO washers (user_id, name, approval_status, is_active, is_banned, service_radius_km)
  VALUES (u2, 'Prova Lavador', 'approved', true, false, 50) RETURNING id INTO w1;
  INSERT INTO ids VALUES ('c1', c1), ('c2', c2), ('k1', k1), ('w1', w1);
  INSERT INTO platform_settings (key, value) VALUES
    ('cleaning_enabled', 'true'::jsonb), ('cleaning_stripe_enabled', 'true'::jsonb),
    ('cleaning_hourly_cents', '1200'::jsonb), ('cleaning_bora_pct', '15'::jsonb), ('cleaning_min_lead_hours', '0'::jsonb),
    ('carwash_enabled', 'true'::jsonb), ('carwash_stripe_enabled', 'true'::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END $$;

-- P1 o caso Divan: 4 h Standard, dinheiro, com o prémio de 2 h ----------------------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid; q jsonb; b cleaning_bookings; vale checkin_premios_vales;
BEGIN
  PERFORM pg_temp.como(c1);
  v := pg_temp.vale(c1);
  q := public.cleaning_quote_team('standard', 'hourly', NULL, 4, 'single', 'client', 40.5373, -7.2676, 1);
  SELECT * INTO b FROM jsonb_populate_record(NULL::cleaning_bookings, pg_temp.limpeza('standard', 4, 'cash', v, 'prova-p1'));
  SELECT * INTO vale FROM checkin_premios_vales WHERE id = v;
  PERFORM pg_temp.prova(b.checkin_premio_cents = 2400 AND b.checkin_vale_id = v, 'prémio de 2 h × 12 € = 24 € na marcação');
  PERFORM pg_temp.prova(b.total_cents = (q->>'total_cents')::int - 2400, 'o cliente paga o total menos o prémio');
  PERFORM pg_temp.prova(b.cleaner_earnings_cents = (q->>'cleaner_earnings_cents')::int, 'a profissional ganha as 4 h todas');
  PERFORM pg_temp.prova(b.bora_fee_cents = (q->>'bora_fee_cents')::int - 2400, 'a Bora fica com a taxa normal menos o prémio');
  PERFORM pg_temp.prova(b.recurring_discount_cents = 0, 'o prémio já não usa recurring_discount_cents');
  PERFORM pg_temp.prova(b.payment_method = 'cash' AND b.payment_status = 'unpaid', 'em dinheiro a profissional cobra só o resto');
  PERFORM pg_temp.prova(b.offer_cleaner_id IS NOT NULL, 'em dinheiro a profissional é chamada logo');
  PERFORM pg_temp.prova(vale.estado = 'usado' AND vale.marcacao_id = b.id AND vale.marcacao_tipo = 'limpeza'
                        AND vale.valor_cents = 2400 AND vale.custo_cents = 2040, 'vale usado com o id da marcação (24 € / custo 20,40 €)');
  IF (q->>'total_cents')::int = 4800 THEN   -- com o preço do ar (12 €/h, 15 %): os números do Divan
    PERFORM pg_temp.prova(b.total_cents = 2400 AND b.cleaner_earnings_cents = 4080 AND b.bora_fee_cents = -1680,
                          'Divan: 24 € cliente, 40,80 € profissional, −16,80 € Bora (o acerto paga a diferença)');
  END IF;
  INSERT INTO ids VALUES ('v1', v), ('b1', b.id);
  RAISE NOTICE 'PROVA_OK P1 caso Divan: cliente % · profissional % · Bora % · prémio %', b.total_cents,
    b.cleaner_earnings_cents, b.bora_fee_cents, b.checkin_premio_cents;
END $$;

-- P2 o mesmo vale não se usa duas vezes; a mesma chave devolve a mesma marcação ---------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); v_err text; j jsonb;
BEGIN
  PERFORM pg_temp.como(c1);
  BEGIN PERFORM pg_temp.limpeza('standard', 3, 'cash', v, 'prova-p2'); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%checkin_premio_estado%usado%', 'vale usado → checkin_premio_estado: usado');
  j := pg_temp.limpeza('standard', 4, 'cash', v, 'prova-p1');
  PERFORM pg_temp.prova((j->>'id')::uuid = (SELECT val FROM ids WHERE k = 'b1'), 'toque duplo (mesma chave) = a mesma marcação');
  RAISE NOTICE 'PROVA_OK P2 um vale = um uso';
END $$;

-- P3 cancelar a tempo (sem taxa) → o vale volta, mesmo pago em dinheiro ---------------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); b uuid := (SELECT val FROM ids WHERE k = 'b1');
BEGIN
  PERFORM pg_temp.como(c1);
  PERFORM public.cancel_cleaning_booking(b, 'prova', false);
  PERFORM pg_temp.prova((SELECT estado = 'por_usar' AND marcacao_id IS NULL FROM checkin_premios_vales WHERE id = v),
                        'o vale voltou a por_usar (antes só voltava com pagamento premio)');
  RAISE NOTICE 'PROVA_OK P3 cancelar a tempo devolve o vale (dinheiro)';
END $$;

-- P4 Profunda: o prémio vale 2 h Standard e o cliente paga a diferença (cartão) --------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); q jsonb; b cleaning_bookings;
BEGIN
  PERFORM pg_temp.como(c1);
  q := public.cleaning_quote_team('deep', 'hourly', NULL, 2, 'single', 'client', 40.5373, -7.2676, 1);
  SELECT * INTO b FROM jsonb_populate_record(NULL::cleaning_bookings, pg_temp.limpeza('deep', 2, 'card', v, 'prova-p4'));
  PERFORM pg_temp.prova(b.checkin_premio_cents = 2400 AND b.total_cents = (q->>'total_cents')::int - 2400 AND b.total_cents > 0,
                        'Profunda 2 h: paga a diferença (' || b.total_cents || ')');
  PERFORM pg_temp.prova(b.payment_method = 'card' AND b.payment_status = 'unpaid' AND b.offer_cleaner_id IS NULL,
                        'com resto no cartão: cobra-se o resto e ninguém é chamado antes de pagar (regra 19/10)');
  PERFORM public.cancel_cleaning_booking(b.id, 'prova', false);
  PERFORM pg_temp.prova((SELECT estado FROM checkin_premios_vales WHERE id = v) = 'por_usar', 'cancelada → vale volta (cartão)');
  RAISE NOTICE 'PROVA_OK P4 Profunda paga a diferença: % de %', b.total_cents, q->>'total_cents';
END $$;

-- P5 2 h Standard no cartão: resto 0 → pago pelo prémio, profissional chamada --------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); b cleaning_bookings; j jsonb;
BEGIN
  PERFORM pg_temp.como(c1);
  j := pg_temp.limpeza('standard', 2, 'card', v, 'prova-p5');
  SELECT * INTO b FROM cleaning_bookings WHERE id = (j->>'id')::uuid;
  PERFORM pg_temp.prova(b.total_cents = 0 AND b.checkin_premio_cents = 2400, 'resto 0');
  PERFORM pg_temp.prova(b.payment_method = 'premio' AND b.payment_status = 'held', 'cartão com resto 0 → método premio, pago');
  PERFORM pg_temp.prova(b.offer_cleaner_id IS NOT NULL, 'pago pelo prémio → a profissional é chamada (uma oferta)');
  PERFORM pg_temp.prova(b.cleaner_earnings_cents = 2040, 'a profissional ganha as 2 h (20,40 €)');
  PERFORM public.cancel_cleaning_booking(b.id, 'prova', false);
  PERFORM pg_temp.prova((SELECT estado FROM checkin_premios_vales WHERE id = v) = 'por_usar', 'cancelada → vale volta (premio)');
  RAISE NOTICE 'PROVA_OK P5 2 h no cartão pagas pelo prémio';
END $$;

-- P6 resto de 1 a 49 cêntimos no cartão/MB Way → recusa (só em dinheiro) -------------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); v_err text; q jsonb; b jsonb;
BEGIN
  PERFORM pg_temp.como(c1);
  -- preço/hora de ensaio para a Profunda de 2 h deixar 30 cêntimos de resto (desfaz-se no ROLLBACK)
  UPDATE platform_settings SET value = '38'::jsonb WHERE key = 'cleaning_hourly_cents';
  q := public.cleaning_quote_team('deep', 'hourly', NULL, 2, 'single', 'client', 40.5373, -7.2676, 1);
  PERFORM pg_temp.prova((q->>'total_cents')::int - 76 BETWEEN 1 AND 49, 'cenário: resto entre 1 e 49 (' || ((q->>'total_cents')::int - 76) || ')');
  BEGIN PERFORM pg_temp.limpeza('deep', 2, 'mbway', v, 'prova-p6'); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%checkin_premio_resto_so_dinheiro%', 'MB Way com resto abaixo de 50 cêntimos → recusado');
  PERFORM pg_temp.prova((SELECT estado FROM checkin_premios_vales WHERE id = v) = 'por_usar', 'o vale não foi gasto');
  b := pg_temp.limpeza('deep', 2, 'cash', v, 'prova-p6-dinheiro');
  PERFORM pg_temp.prova((b->>'total_cents')::int BETWEEN 1 AND 49, 'em dinheiro passa');
  PERFORM public.cancel_cleaning_booking((b->>'id')::uuid, 'prova', false);
  UPDATE platform_settings SET value = '1200'::jsonb WHERE key = 'cleaning_hourly_cents';
  RAISE NOTICE 'PROVA_OK P6 resto de 1 a 49 cêntimos só em dinheiro';
END $$;

-- P7 lavagem: só por fora no cartão → pago pelo prémio; completa em dinheiro → paga a diferença --
DO $$
DECLARE c2 uuid := (SELECT val FROM ids WHERE k = 'c2'); v uuid; qe jsonb := public.carwash_quote('exterior');
        qf jsonb := public.carwash_quote('full'); w carwash_bookings; w2 carwash_bookings;
BEGIN
  PERFORM pg_temp.como(c2);
  v := pg_temp.vale(c2);
  SELECT * INTO w FROM jsonb_populate_record(NULL::carwash_bookings, public.create_carwash_booking(
    'exterior', 'AA-00-PR', '+351912345671', 'later', now() + interval '1 day', 'Rua da Prova 2', 'Guarda', '6300-000',
    40.5373, -7.2676, 'card', '', '', '', '', '[]'::jsonb, NULL, v));
  SELECT * INTO w FROM carwash_bookings WHERE id = w.id;
  PERFORM pg_temp.prova(w.total_cents = 0 AND w.checkin_premio_cents = (qe->>'total_cents')::int, 'só por fora: o prémio paga tudo');
  PERFORM pg_temp.prova(w.payment_method = 'premio' AND w.payment_status = 'held', 'cartão com resto 0 → premio');
  PERFORM pg_temp.prova(w.washer_earnings_cents = (qe->>'washer_earnings_cents')::int
                        AND w.bora_fee_cents = (qe->>'bora_fee_cents')::int - (qe->>'total_cents')::int, 'lavador ganha o mesmo; Bora = taxa − prémio');
  PERFORM pg_temp.prova((SELECT estado = 'usado' AND marcacao_tipo = 'lavagem' AND marcacao_id = w.id FROM checkin_premios_vales WHERE id = v),
                        'vale usado na lavagem');
  UPDATE carwash_bookings SET status = 'cancelled_client' WHERE id = w.id;
  PERFORM pg_temp.prova((SELECT estado FROM checkin_premios_vales WHERE id = v) = 'por_usar', 'lavagem cancelada → vale volta');
  SELECT * INTO w2 FROM jsonb_populate_record(NULL::carwash_bookings, public.create_carwash_booking(
    'full', 'AA-00-PR', '+351912345671', 'later', now() + interval '1 day', 'Rua da Prova 2', 'Guarda', '6300-000',
    40.5373, -7.2676, 'cash', '', '', '', '', '[]'::jsonb, NULL, v));
  PERFORM pg_temp.prova(w2.total_cents = (qf->>'total_cents')::int - (qe->>'total_cents')::int AND w2.payment_method = 'cash',
                        'completa: paga a diferença em dinheiro (' || w2.total_cents || ')');
  INSERT INTO ids VALUES ('v2', v), ('w2', w2.id);
  RAISE NOTICE 'PROVA_OK P7 lavagem: por fora % → 0; completa % → %', qe->>'total_cents', qf->>'total_cents', w2.total_cents;
END $$;

-- P8 "Os meus prémios › Usar" (client_checkin_premio_marcar_limpeza) passa pelo create --------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); j jsonb; b cleaning_bookings;
BEGIN
  PERFORM pg_temp.como(c1);
  j := public.client_checkin_premio_marcar_limpeza(v, now() + interval '2 days', 'Rua da Prova 1', 'Guarda', '6300-000',
                                                   40.5373, -7.2676, '');
  SELECT * INTO b FROM cleaning_bookings WHERE id = (j #>> '{marcacao,id}')::uuid;
  PERFORM pg_temp.prova((j->>'ok')::boolean AND b.checkin_vale_id = v AND b.checkin_premio_cents = 2400 AND b.total_cents = 0,
                        'marcar pelo prémio usa os campos novos');
  PERFORM pg_temp.prova(b.payment_method = 'premio' AND b.payment_status = 'held' AND b.recurring_discount_cents = 0, 'pago pelo prémio');
  PERFORM pg_temp.prova((j #>> '{vale,estado}') = 'usado', 'a resposta traz o vale usado');
  PERFORM public.cancel_cleaning_booking(b.id, 'prova', false);
  RAISE NOTICE 'PROVA_OK P8 Os meus prémios › Usar pelo create';
END $$;

-- P9 série semanal paga pelo prémio: a seguinte nasce em dinheiro (o gerador não parte) --------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := (SELECT val FROM ids WHERE k = 'v1'); j jsonb; g uuid; n int; s cleaning_bookings;
BEGIN
  PERFORM pg_temp.como(c1);
  j := pg_temp.limpeza('standard', 2, 'card', v, 'prova-p9', 'weekly');
  g := (j->>'recurrence_group_id')::uuid;
  PERFORM pg_temp.prova((SELECT payment_method FROM cleaning_bookings WHERE id = (j->>'id')::uuid) = 'premio', 'a 1.ª da série foi paga pelo prémio');
  -- como se a 1.ª já tivesse passado, para a seguinte cair dentro dos 7 dias do gerador
  UPDATE cleaning_bookings SET scheduled_at = now() - interval '1 hour' WHERE id = (j->>'id')::uuid;
  PERFORM pg_temp.como(NULL);
  n := public.generate_recurring_bookings();
  SELECT * INTO s FROM cleaning_bookings WHERE recurrence_group_id = g AND id <> (j->>'id')::uuid ORDER BY scheduled_at LIMIT 1;
  PERFORM pg_temp.prova(s.id IS NOT NULL, 'o gerador criou a seguinte (não partiu na guarda)');
  PERFORM pg_temp.prova(s.payment_method = 'cash' AND s.checkin_vale_id IS NULL AND s.checkin_premio_cents = 0
                        AND s.total_cents = (public.cleaning_quote_team('standard', 'hourly', NULL, 2, 'weekly', 'client',
                                                                        40.5373, -7.2676, 1)->>'total_cents')::int,
                        'a seguinte vai em dinheiro, ao preço da série (com o desconto de sempre), sem prémio');
  RAISE NOTICE 'PROVA_OK P9 série: a seguinte em dinheiro (%)', s.total_cents;
END $$;

-- P10 vale de outro cliente e vale expirado ------------------------------------------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); c2 uuid := (SELECT val FROM ids WHERE k = 'c2'); v_err text; vx uuid;
BEGIN
  PERFORM pg_temp.como(c1);
  BEGIN PERFORM pg_temp.limpeza('standard', 2, 'cash', (SELECT val FROM ids WHERE k = 'v2'), 'prova-p10'); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%checkin_premio_nao_encontrado%', 'vale de outro cliente → não encontrado');
  vx := pg_temp.vale(c1, interval '-1 day');
  BEGIN PERFORM pg_temp.limpeza('standard', 2, 'cash', vx, 'prova-p10b'); RAISE EXCEPTION 'devia falhar';
  EXCEPTION WHEN others THEN v_err := sqlerrm; END;
  PERFORM pg_temp.prova(v_err LIKE '%checkin_premio_expirado%', 'vale expirado → recusado');
  RAISE NOTICE 'PROVA_OK P10 vale de outro cliente e expirado recusados';
END $$;

-- P11 banner da app ------------------------------------------------------------------------
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); c2 uuid := (SELECT val FROM ids WHERE k = 'c2'); r jsonb;
BEGIN
  PERFORM pg_temp.como(c2);
  PERFORM pg_temp.prova(public.client_checkin_premio_servico_para_usar('lavagem') IS NULL, 'vale usado → sem banner');
  PERFORM pg_temp.como(c1);
  UPDATE checkin_premios_vales SET estado = 'por_usar', marcacao_id = NULL, marcacao_tipo = NULL
   WHERE id = (SELECT val FROM ids WHERE k = 'v1');
  r := public.client_checkin_premio_servico_para_usar('limpeza');
  PERFORM pg_temp.prova((r->>'vale_id')::uuid = (SELECT val FROM ids WHERE k = 'v1') AND (r->>'horas')::int = 2
                        AND (r->>'valor_cents')::int = 2400, 'banner: 2 h, 24 €');
  r := public.client_checkin_premio_servico_para_usar('lavagem');
  PERFORM pg_temp.prova((r->>'valor_cents')::int = (public.carwash_quote('exterior')->>'total_cents')::int, 'banner da lavagem: preço só por fora');
  RAISE NOTICE 'PROVA_OK P11 banner (client_checkin_premio_servico_para_usar)';
END $$;

-- P12 guarda de escrita direta e permissões -------------------------------------------------
DO $$
DECLARE c2 uuid := (SELECT val FROM ids WHERE k = 'c2'); w uuid := (SELECT val FROM ids WHERE k = 'w2'); v_err text := ''; v_antes int; v_depois int;
BEGIN
  PERFORM pg_temp.como(c2);
  v_antes := (SELECT total_cents FROM carwash_bookings WHERE id = w);
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE carwash_bookings SET checkin_premio_cents = 0, total_cents = 2000 WHERE id = w;
    RESET ROLE;
  EXCEPTION WHEN others THEN v_err := sqlerrm; RESET ROLE; END;
  v_depois := (SELECT total_cents FROM carwash_bookings WHERE id = w);
  PERFORM pg_temp.prova(v_depois = v_antes, 'escrita direta não muda o prémio nem o total (' || COALESCE(NULLIF(v_err, ''), 'sem linhas') || ')');
  PERFORM pg_temp.prova(NOT has_function_privilege('authenticated', 'public._checkin_premio_guarda_campos()', 'EXECUTE')
                        AND NOT has_function_privilege('authenticated', 'public._trg_checkin_premio_serie_em_dinheiro()', 'EXECUTE')
                        AND NOT has_function_privilege('anon', 'public.client_checkin_premio_servico_para_usar(text)', 'EXECUTE')
                        AND has_function_privilege('authenticated', 'public.client_checkin_premio_servico_para_usar(text)', 'EXECUTE')
                        AND has_function_privilege('authenticated', 'public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer,uuid)', 'EXECUTE')
                        AND NOT has_function_privilege('anon', 'public.create_cleaning_booking(text,text,text,integer,timestamp with time zone,text,text,text,text,text,text,double precision,double precision,text,uuid,text,integer,uuid)', 'EXECUTE')
                        AND has_function_privilege('authenticated', 'public.create_carwash_booking(text,text,text,text,timestamptz,text,text,text,double precision,double precision,text,text,text,text,text,jsonb,uuid,uuid)', 'EXECUTE'),
                        'internas fechadas; as da app abertas a authenticated e fechadas a anon');
  PERFORM pg_temp.prova(NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'create_cleaning_booking' AND pronargs = 17)
                        AND NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'create_carwash_booking' AND pronargs = 17),
                        'sem versões antigas ambíguas');
  RAISE NOTICE 'PROVA_OK P12 guarda de escrita direta e permissões';
END $$;

-- P13 a migração da reserva do Divan (cópia do bloco 8 da migracao.sql, numa reserva de ensaio) ----
DO $$
DECLARE c1 uuid := (SELECT val FROM ids WHERE k = 'c1'); v uuid := pg_temp.vale(c1); id_b uuid; b cleaning_bookings; d cleaning_bookings;
BEGIN
  -- a reserva como a Claude.ai a deixou a 26/11 (prémio em recurring_discount_cents)
  INSERT INTO cleaning_bookings (client_user_id, recurrence, cleaning_type, pricing_mode, hours, scheduled_at, duration_min,
     address_street, address_city, address_postal, lat, lng, notes, products_by, payment_method, payment_status,
     base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents, total_cents, cleaner_earnings_cents, bora_fee_cents)
  VALUES (c1, 'single', 'standard', 'hourly', 4, now() + interval '1 day', 240, 'Rua', 'Guarda', '6300', 40.5373, -7.2676, '',
          'client', 'cash', 'unpaid', 4800, 0, 2400, 0, 2400, 4080, -1680) RETURNING id INTO id_b;
  UPDATE checkin_premios_vales SET estado = 'usado', marcacao_tipo = 'limpeza', marcacao_id = id_b WHERE id = v;
  SELECT * INTO b FROM cleaning_bookings WHERE id = id_b;
  UPDATE cleaning_bookings SET checkin_premio_cents = b.recurring_discount_cents, checkin_vale_id = v, recurring_discount_cents = 0
   WHERE id = id_b;
  SELECT * INTO d FROM cleaning_bookings WHERE id = id_b;
  PERFORM pg_temp.prova(d.checkin_premio_cents = 2400 AND d.checkin_vale_id = v AND d.recurring_discount_cents = 0, 'campos novos');
  PERFORM pg_temp.prova(d.total_cents = 2400 AND d.cleaner_earnings_cents = 4080 AND d.bora_fee_cents = -1680, 'nenhum valor mudou');
  RAISE NOTICE 'PROVA_OK P13 migração do Divan sem mudar valores';
END $$;

ROLLBACK;
