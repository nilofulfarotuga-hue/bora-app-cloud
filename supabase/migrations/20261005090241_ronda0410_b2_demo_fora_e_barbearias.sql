-- Ronda 04/10 Bloco B itens 2, 3 e 6.
-- 2) Dados de demonstracao fora de: Contas claras (admin_extrato_dono), Ganho do dia,
--    Acerto por pessoa, Vigia (vigia_dinheiro_diario + admin_vigia_achados) e KPIs.
--    Criterio = o que ja existe (is_demo_user/driver/restaurant/provider/order/subject,
--    padroes em platform_settings.admin_demo_email_patterns). '%@bora.app' NAO e demo.
-- 3) Contas claras passa a incluir as barbearias (appointment_payouts).
-- 6) Barbearias: "pago na app" so conta com pagamento real (full_payment_pi), nao so a marca.

-- Helper: um achado do vigia e de demonstracao?
CREATE OR REPLACE FUNCTION public._vigia_e_demo(p_entity_type text, p_entity_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_entity_id IS NULL THEN false
    WHEN p_entity_type IN ('wallet','client') THEN
      p_entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      AND public.is_demo_user(p_entity_id::uuid)
    WHEN p_entity_type = 'driver' THEN public.is_demo_driver(p_entity_id)
    WHEN p_entity_type = 'restaurant' THEN public.is_demo_restaurant(p_entity_id)
    WHEN p_entity_type = 'order' THEN
      COALESCE((SELECT public.is_demo_order(o) FROM public.orders o WHERE o.id = p_entity_id), false)
    WHEN p_entity_type = 'payout' THEN
      COALESCE((SELECT CASE p.user_type WHEN 'driver' THEN public.is_demo_driver(p.user_id)
                                        WHEN 'restaurant' THEN public.is_demo_restaurant(p.user_id)
                                        ELSE false END
                  FROM public.payouts p WHERE p.id::text = p_entity_id), false)
    ELSE false
  END
$function$;
REVOKE ALL ON FUNCTION public._vigia_e_demo(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._vigia_e_demo(text, text) TO service_role;

-- KPIs: sem pedidos de demonstracao.
CREATE OR REPLACE FUNCTION public.admin_kpi_avg_ticket(p_days_back integer DEFAULT 30)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_admin RECORD; v_avg_total NUMERIC; v_avg_partner NUMERIC; v_avg_market NUMERIC; v_count BIGINT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_days_back < 1 OR p_days_back > 365 THEN p_days_back := 30; END IF;
  SELECT count(*),
         ROUND(avg(o.price)::numeric, 2),
         ROUND(avg(o.price) FILTER (WHERE o.is_partner_store)::numeric, 2),
         ROUND(avg(o.price) FILTER (WHERE NOT o.is_partner_store)::numeric, 2)
    INTO v_count, v_avg_total, v_avg_partner, v_avg_market
    FROM public.orders o
   WHERE o.status = 'delivered' AND o.created_at >= now() - (p_days_back || ' days')::INTERVAL
     AND NOT public.is_demo_order(o);
  RETURN jsonb_build_object(
    'days_back', p_days_back, 'order_count', v_count,
    'avg_ticket_total', v_avg_total, 'avg_ticket_partner', v_avg_partner,
    'avg_ticket_market', v_avg_market
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_kpi_conversion(p_days_back integer DEFAULT 30)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_admin RECORD; v_created BIGINT; v_delivered BIGINT; v_cancelled BIGINT; v_rejected BIGINT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_days_back < 1 OR p_days_back > 365 THEN p_days_back := 30; END IF;
  SELECT count(*), count(*) FILTER (WHERE o.status = 'delivered'),
         count(*) FILTER (WHERE o.status = 'cancelled'),
         count(*) FILTER (WHERE o.status = 'rejected')
    INTO v_created, v_delivered, v_cancelled, v_rejected
    FROM public.orders o
   WHERE o.created_at >= now() - (p_days_back || ' days')::INTERVAL
     AND NOT public.is_demo_order(o);
  RETURN jsonb_build_object(
    'days_back', p_days_back,
    'orders_created', v_created, 'orders_delivered', v_delivered,
    'orders_cancelled', v_cancelled, 'orders_rejected', v_rejected,
    'conversion_rate', CASE WHEN v_created = 0 THEN 0 ELSE ROUND(((v_delivered::numeric / v_created) * 100), 2) END,
    'cancel_rate', CASE WHEN v_created = 0 THEN 0 ELSE ROUND(((v_cancelled::numeric / v_created) * 100), 2) END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_kpi_hot_zones(p_days_back integer DEFAULT 30, p_limit integer DEFAULT 20)
 RETURNS TABLE(cell_lat numeric, cell_lng numeric, order_count bigint, total_revenue numeric, avg_distance numeric)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_days_back < 1 OR p_days_back > 365 THEN p_days_back := 30; END IF;
  IF p_limit < 1 OR p_limit > 100 THEN p_limit := 20; END IF;
  RETURN QUERY
  SELECT
    ROUND(o.dropoff_lat::numeric, 2) AS cell_lat,
    ROUND(o.dropoff_lng::numeric, 2) AS cell_lng,
    count(*)::BIGINT AS order_count,
    ROUND(sum(o.price)::numeric, 2) AS total_revenue,
    ROUND(avg(o.distance_km)::numeric, 2) AS avg_distance
  FROM public.orders o
  WHERE o.status = 'delivered'
    AND o.created_at >= now() - (p_days_back || ' days')::INTERVAL
    AND o.dropoff_lat IS NOT NULL AND o.dropoff_lng IS NOT NULL
    AND NOT public.is_demo_order(o)
  GROUP BY 1, 2
  ORDER BY count(*) DESC
  LIMIT p_limit;
END;
$function$;

-- Ganho do dia: sem pessoas de demonstracao.
CREATE OR REPLACE FUNCTION public.admin_ganho_do_dia(p_dia date DEFAULT NULL::date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_dia date; v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_dia := COALESCE(p_dia, (now() AT TIME ZONE 'Europe/Lisbon')::date);
  WITH pessoa AS (
    SELECT v.user_id,
           sum(v.cents)::bigint  AS total_cents,
           sum(v.trabalhos)::int AS trabalhos_total,
           jsonb_agg(jsonb_build_object(
             'papel', v.papel,
             'titulo', CASE v.papel
                         WHEN 'driver'  THEN 'Entregas e corridas'
                         WHEN 'cleaner' THEN 'Limpeza'
                         WHEN 'washer'  THEN 'Lavagem de carros'
                         ELSE v.papel END,
             'cents', v.cents,
             'trabalhos', v.trabalhos) ORDER BY v.cents DESC) AS por_papel
    FROM public.v_ganho_diario_por_pessoa v
    WHERE v.dia = v_dia
      AND NOT public.is_demo_user(v.user_id)
      AND NOT public.is_demo_driver(v.user_id::text)
    GROUP BY v.user_id
  )
  SELECT jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'total_cents', COALESCE((SELECT sum(total_cents) FROM pessoa), 0),
    'pessoas', COALESCE((SELECT count(*) FROM pessoa), 0),
    'itens', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', p.user_id,
        'nome', COALESCE(
          (SELECT d.name FROM drivers  d WHERE d.user_id = p.user_id LIMIT 1),
          (SELECT c.name FROM cleaners c WHERE c.user_id = p.user_id LIMIT 1),
          (SELECT w.name FROM washers  w WHERE w.user_id = p.user_id LIMIT 1),
          (SELECT u.email FROM auth.users u WHERE u.id = p.user_id),
          '(sem nome)'),
        'email', COALESCE((SELECT u.email FROM auth.users u WHERE u.id = p.user_id), ''),
        'telefone', COALESCE(
          (SELECT d.phone FROM drivers  d WHERE d.user_id = p.user_id LIMIT 1),
          (SELECT c.phone FROM cleaners c WHERE c.user_id = p.user_id LIMIT 1),
          (SELECT w.phone FROM washers  w WHERE w.user_id = p.user_id LIMIT 1), ''),
        'total_cents', p.total_cents,
        'trabalhos_total', p.trabalhos_total,
        'por_papel', p.por_papel)
        ORDER BY p.total_cents DESC)
      FROM pessoa p), '[]'::jsonb)
  ) INTO v_out;
  RETURN v_out;
END $function$;

-- Acerto por pessoa: sem pessoas de demonstracao.
CREATE OR REPLACE FUNCTION public.admin_acerto_unificado(p_semana date DEFAULT NULL::date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_semana date; v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_semana := COALESCE(p_semana,
    (SELECT max(v.semana) FROM public.v_acerto_semanal_unificado v
      WHERE NOT public.is_demo_user(v.user_id) AND NOT public.is_demo_driver(v.user_id::text)));
  SELECT jsonb_build_object(
    'ok', true,
    'semana', v_semana,
    'semanas', COALESCE((SELECT jsonb_agg(DISTINCT x.semana ORDER BY x.semana DESC)
                         FROM public.v_acerto_semanal_unificado x
                        WHERE NOT public.is_demo_user(x.user_id) AND NOT public.is_demo_driver(x.user_id::text)), '[]'::jsonb),
    'itens', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', v.user_id,
        'email',   v.email,
        'nome', COALESCE(
          (SELECT d.name FROM drivers  d WHERE d.user_id = v.user_id LIMIT 1),
          (SELECT c.name FROM cleaners c WHERE c.user_id = v.user_id LIMIT 1),
          (SELECT w.name FROM washers  w WHERE w.user_id = v.user_id LIMIT 1),
          v.email, '(sem nome)'),
        'telefone', COALESCE(
          (SELECT d.phone FROM drivers  d WHERE d.user_id = v.user_id LIMIT 1),
          (SELECT c.phone FROM cleaners c WHERE c.user_id = v.user_id LIMIT 1),
          (SELECT w.phone FROM washers  w WHERE w.user_id = v.user_id LIMIT 1), ''),
        'detalhe', v.detalhe,
        'trabalhos_total', v.trabalhos_total,
        'a_receber_cents', v.a_receber_cents,
        'divida_cents', v.divida_cents,
        'divida_por_abater_cents', v.divida_por_abater_cents,
        'total_cents', v.total_cents,
        'sentido', v.sentido,
        'tudo_pago', v.tudo_pago)
        ORDER BY v.total_cents DESC)
      FROM public.v_acerto_semanal_unificado v
      WHERE v.semana = v_semana
        AND NOT public.is_demo_user(v.user_id) AND NOT public.is_demo_driver(v.user_id::text)), '[]'::jsonb)
  ) INTO v_out;
  RETURN v_out;
END $function$;

-- Vigia: achados abertos sem demonstracao.
CREATE OR REPLACE FUNCTION public.admin_vigia_achados(p_so_abertos boolean DEFAULT true, p_limit integer DEFAULT 200)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN NOT public.is_admin() THEN jsonb_build_object('ok', false, 'error', 'NOT_ADMIN')
         ELSE jsonb_build_object('ok', true,
           'abertos', (SELECT COUNT(*) FROM public.payment_reconciliation_findings
                        WHERE resolved_at IS NULL AND NOT public._vigia_e_demo(entity_type, entity_id)),
           'lista', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                       'id', f.id, 'kind', f.kind, 'severity', f.severity, 'entity_type', f.entity_type, 'entity_id', f.entity_id,
                       'amount_cents', f.amount_cents, 'details', f.details, 'run_at', f.run_at, 'resolved_at', f.resolved_at)
                       ORDER BY f.resolved_at NULLS FIRST, f.run_at DESC)
                     FROM (SELECT * FROM public.payment_reconciliation_findings
                            WHERE ((NOT p_so_abertos) OR resolved_at IS NULL)
                              AND NOT public._vigia_e_demo(entity_type, entity_id)
                            ORDER BY resolved_at NULLS FIRST, run_at DESC LIMIT GREATEST(p_limit, 1)) f), '[]'::jsonb)) END;
$function$;

-- Barbearias, metricas: "pago na app" so com pagamento real (full_payment_pi).
-- (compute_provider_weekly_payout tem a mesma regra mas e funcao protegida pela Trava:
--  fica proposta em .claude/.ai/missoes/ronda-04-10/feito/pc-B-PROPOSTA-barbearia-pago-na-app-real.sql)
CREATE OR REPLACE FUNCTION public.admin_appointments_metrics(p_provider_id text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_from timestamptz; v_to timestamptz; v_fee int; r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  v_from := COALESCE(p_from, now() - interval '30 days');
  v_to := COALESCE(p_to, now());
  SELECT COALESCE((value::text)::int,50) INTO v_fee FROM platform_settings WHERE key='appointment_booking_fee_cents';
  v_fee := COALESCE(v_fee,50);
  SELECT jsonb_build_object(
    'from', v_from, 'to', v_to,
    'total', count(*),
    'confirmed', count(*) FILTER (WHERE status='confirmed'),
    'completed', count(*) FILTER (WHERE status='completed'),
    'no_show',   count(*) FILTER (WHERE status='no_show'),
    'cancelled', count(*) FILTER (WHERE status='cancelled'),
    'walk_ins',  count(*) FILTER (WHERE is_walk_in),
    'no_show_rate_pct', CASE WHEN count(*) FILTER (WHERE status IN ('completed','no_show'))>0
        THEN ROUND(100.0*count(*) FILTER (WHERE status='no_show')/count(*) FILTER (WHERE status IN ('completed','no_show')),1) ELSE 0 END,
    'taxa_marcacoes_cents', COALESCE(SUM(CASE WHEN status='completed' THEN v_fee ELSE 0 END),0),
    'retido_no_show_cents', COALESCE(SUM(deposit_cents) FILTER (WHERE status IN ('no_show','cancelled') AND deposit_status='retained'),0),
    'bora_revenue_cents',
        COALESCE(SUM(CASE WHEN status='completed' THEN v_fee ELSE 0 END),0)
      + COALESCE(SUM(deposit_cents) FILTER (WHERE status IN ('no_show','cancelled') AND deposit_status='retained'),0),
    -- total cobrado ao cliente por marcacoes concluidas: o sinal pago + o valor cheio SO
    -- quando houve pagamento real na app (full_payment_pi), nao so a marca do parceiro.
    'recebido_cents',
        COALESCE(SUM(deposit_cents) FILTER (WHERE status='completed' AND deposit_status='paid'),0)
      + COALESCE(SUM(service_price_cents) FILTER (WHERE status='completed' AND full_payment_method='app'
                                                    AND full_payment_status='paid' AND full_payment_pi IS NOT NULL),0),
    'pago_na_app_sem_pagamento_real', count(*) FILTER (WHERE status='completed' AND full_payment_method='app'
                                                         AND full_payment_pi IS NULL)
  ) INTO r
  FROM appointments
  WHERE scheduled_at >= v_from AND scheduled_at <= v_to
    AND (p_provider_id IS NULL OR provider_id = p_provider_id)
    AND COALESCE(is_test, false) = false
    AND NOT public.is_demo_user(client_user_id)
    AND NOT public.is_demo_provider(provider_id);
  RETURN r;
END $function$;

-- O parceiro dizer "pagou na app" ja nao poe o valor como pago: so com pagamento real.
CREATE OR REPLACE FUNCTION public.partner_complete_appointment(p_appointment_id uuid, p_payment_method text DEFAULT 'on_site'::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_appt record;
BEGIN
  SELECT * INTO v_appt FROM appointments WHERE id=p_appointment_id;
  IF v_appt IS NULL THEN RAISE EXCEPTION 'appointment_not_found'; END IF;
  PERFORM public._appt_assert_provider_owner(v_appt.provider_id);
  IF v_appt.status NOT IN ('confirmed', 'awaiting_confirmation') THEN RAISE EXCEPTION 'invalid_status'; END IF;
  IF p_payment_method NOT IN ('on_site','app') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  UPDATE appointments SET status='completed', completed_at=now(), updated_at=now(),
         full_payment_method=p_payment_method,
         full_payment_status = CASE WHEN p_payment_method='app' AND v_appt.full_payment_pi IS NOT NULL
                                    THEN 'paid' ELSE 'pending' END
    WHERE id=p_appointment_id;
  IF v_appt.client_user_id IS NOT NULL THEN
    PERFORM public._appt_notify_client(v_appt.client_user_id, 'appointment_completed', 'Obrigado!',
            'A tua marcação foi concluída. Até à próxima!', p_appointment_id::text);
  END IF;
  RETURN jsonb_build_object('success', true, 'status','completed');
END $function$;

-- Vigia do dinheiro e Contas claras: remendo por ancora sobre a versao no ar
-- (funcoes grandes; cada ancora tem de aparecer exactamente 1 vez, senao aborta tudo).
CREATE OR REPLACE FUNCTION pg_temp._ancora(d text, a text, b text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE n int := (length(d) - length(replace(d, a, ''))) / NULLIF(length(a), 0);
BEGIN
  IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'ancora encontrada % vezes: %', n, left(a, 80); END IF;
  RETURN replace(d, a, b);
END $f$;

DO $patch$
DECLARE d text;
BEGIN
  -- Vigia: casos de contas de demonstracao nao entram (nem gritam).
  d := pg_get_functiondef('public.vigia_dinheiro_diario(boolean,boolean)'::regprocedure);
  d := pg_temp._ancora(d, E'  LOOP\n    v_casos := v_casos ||',
         E'  LOOP\n    CONTINUE WHEN public._vigia_e_demo(v_c.entity_type, v_c.entity_id);\n    v_casos := v_casos ||');
  EXECUTE d;

  -- Contas claras (admin_extrato_dono).
  d := pg_get_functiondef('public.admin_extrato_dono(date,date)'::regprocedure);
  -- entradas
  d := pg_temp._ancora(d, E'WHERE o.status = ''delivered'' AND COALESCE(o.is_test_order, false) = false',
         E'WHERE o.status = ''delivered'' AND COALESCE(o.is_test_order, false) = false AND NOT public.is_demo_order(o)');
  d := pg_temp._ancora(d, E'WHERE r.status = ''finalizada'' AND r.updated_at >= v_de AND r.updated_at < v_ate',
         E'WHERE r.status = ''finalizada'' AND r.updated_at >= v_de AND r.updated_at < v_ate\n       AND NOT public.is_demo_user(r.client_id) AND NOT public.is_demo_driver(r.driver_id::text)');
  d := pg_temp._ancora(d, E'FROM public.cleaning_bookings b\n     WHERE b.status = ''completed''',
         E'FROM public.cleaning_bookings b\n     WHERE COALESCE(b.is_test_order, false) = false AND NOT public.is_demo_user(b.client_user_id) AND b.status = ''completed''');
  d := pg_temp._ancora(d, E'FROM public.carwash_bookings b\n     WHERE b.status = ''completed''',
         E'FROM public.carwash_bookings b\n     WHERE COALESCE(b.is_test_order, false) = false AND NOT public.is_demo_user(b.client_user_id) AND b.status = ''completed''');
  -- saidas
  d := pg_temp._ancora(d, E'WHERE s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_driver''',
         E'WHERE NOT public.is_demo_driver(s.driver_id::text) AND s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_driver''');
  d := pg_temp._ancora(d, E'WHERE s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_partner''',
         E'WHERE NOT public.is_demo_restaurant(s.partner_id) AND s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_partner''');
  d := pg_temp._ancora(d, E'WHERE s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_cleaner''',
         E'WHERE NOT public.is_demo_subject(''cleaner'', s.cleaner_id::text) AND s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_cleaner''');
  d := pg_temp._ancora(d, E'WHERE s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_washer''',
         E'WHERE NOT public.is_demo_subject(''washer'', s.washer_id::text) AND s.status IN (''paid'',''received'') AND s.direction = ''bora_pays_washer''');
  d := pg_temp._ancora(d, E'WHERE o.refund_status = ''refunded''',
         E'WHERE NOT public.is_demo_order(o) AND o.refund_status = ''refunded''');
  d := pg_temp._ancora(d, E'WHERE rc.reimbursement_status = ''admin_paid''',
         E'WHERE NOT public.is_demo_order(o) AND rc.reimbursement_status = ''admin_paid''');
  d := pg_temp._ancora(d, E'WHERE wt.kind IN (''admin_grant'', ''cashback'', ''referral'', ''forgive'')',
         E'WHERE NOT public.is_demo_user(wt.user_id) AND wt.kind IN (''admin_grant'', ''cashback'', ''referral'', ''forgive'')');
  -- saidas: barbearias pagas (item 3)
  d := pg_temp._ancora(d, E'    UNION ALL\n    SELECT ''credito_carteira''',
         E'    UNION ALL\n    SELECT ''acerto_barbearia'', COALESCE(sp.name, s.provider_id), s.net_payout_cents, s.paid_at, s.payment_method, s.payment_reference\n'
      || E'      FROM public.appointment_payouts s LEFT JOIN public.service_providers sp ON sp.id = s.provider_id\n'
      || E'     WHERE NOT public.is_demo_provider(s.provider_id) AND s.status IN (''paid'',''received'') AND s.net_payout_cents > 0\n'
      || E'       AND s.paid_at >= v_de AND s.paid_at < v_ate\n'
      || E'    UNION ALL\n    SELECT ''credito_carteira''');
  -- a Bora deve: repasses de barbearia por pagar (item 3)
  d := pg_temp._ancora(d, E'    UNION ALL\n    SELECT ''tvde'', f.uid::text, d.name, f.fora,',
         E'    UNION ALL\n    SELECT ''acerto_barbearia'', s.provider_id, COALESCE(sp.name, s.provider_id), s.net_payout_cents,\n'
      || E'           ''Repasse da semana '' || to_char(s.week_start_at AT TIME ZONE ''Europe/Lisbon'', ''DD/MM''), s.id::text,\n'
      || E'           jsonb_build_object(''rpc'', ''admin_set_settlement_state'', ''p_subject_type'', ''provider'', ''p_subject_id'', s.provider_id,\n'
      || E'                              ''p_week_start'', (s.week_start_at AT TIME ZONE ''Europe/Lisbon'')::date)\n'
      || E'      FROM public.appointment_payouts s LEFT JOIN public.service_providers sp ON sp.id = s.provider_id\n'
      || E'     WHERE s.status = ''pending'' AND s.net_payout_cents > 0\n'
      || E'    UNION ALL\n    SELECT ''tvde'', f.uid::text, d.name, f.fora,');
  -- devem a Bora: barbearia com saldo negativo (item 3)
  d := pg_temp._ancora(d, E'    UNION ALL\n    SELECT ''tvde'', f.uid::text, d.name, -f.fora,',
         E'    UNION ALL\n    SELECT ''acerto_barbearia'', s.provider_id, COALESCE(sp.name, s.provider_id), -s.net_payout_cents,\n'
      || E'           ''Repasse da semana '' || to_char(s.week_start_at AT TIME ZONE ''Europe/Lisbon'', ''DD/MM'') || '' (deve a Bora)'', s.id::text,\n'
      || E'           jsonb_build_object(''rpc'', ''admin_set_settlement_state'', ''p_subject_type'', ''provider'', ''p_subject_id'', s.provider_id,\n'
      || E'                              ''p_week_start'', (s.week_start_at AT TIME ZONE ''Europe/Lisbon'')::date)\n'
      || E'      FROM public.appointment_payouts s LEFT JOIN public.service_providers sp ON sp.id = s.provider_id\n'
      || E'     WHERE s.status = ''pending'' AND s.net_payout_cents < 0\n'
      || E'    UNION ALL\n    SELECT ''tvde'', f.uid::text, d.name, -f.fora,');
  -- listas "deve"/"devem": linhas de demonstracao saltam
  d := pg_temp._ancora(d, E'  LOOP\n    v_deve := v_deve ||',
         E'  LOOP\n    CONTINUE WHEN CASE v_r.tipo WHEN ''acerto_parceiro'' THEN public.is_demo_restaurant(v_r.quem_id)\n'
      || E'                                WHEN ''acerto_barbearia'' THEN public.is_demo_provider(v_r.quem_id)\n'
      || E'                                WHEN ''carteira_cliente'' THEN public._vigia_e_demo(''wallet'', v_r.quem_id)\n'
      || E'                                ELSE public.is_demo_driver(v_r.quem_id) END;\n    v_deve := v_deve ||');
  d := pg_temp._ancora(d, E'  LOOP\n    v_devem := v_devem ||',
         E'  LOOP\n    CONTINUE WHEN CASE v_r.tipo WHEN ''acerto_parceiro'' THEN public.is_demo_restaurant(v_r.quem_id)\n'
      || E'                                WHEN ''acerto_barbearia'' THEN public.is_demo_provider(v_r.quem_id)\n'
      || E'                                WHEN ''carteira_cliente'' THEN public._vigia_e_demo(''wallet'', v_r.quem_id)\n'
      || E'                                ELSE public.is_demo_driver(v_r.quem_id) END;\n    v_devem := v_devem ||');
  -- arcas sem demonstracao
  d := pg_temp._ancora(d, E'(SELECT COALESCE(SUM(free_balance_cents), 0) FROM public.client_wallets)',
         E'(SELECT COALESCE(SUM(free_balance_cents), 0) FROM public.client_wallets WHERE NOT public.is_demo_user(user_id))');
  d := pg_temp._ancora(d, E'FROM public.wallet_transactions WHERE kind <> ALL',
         E'FROM public.wallet_transactions WHERE NOT public.is_demo_user(user_id) AND kind <> ALL');
  d := pg_temp._ancora(d, E'FROM public.driver_balances)',
         E'FROM public.driver_balances WHERE NOT public.is_demo_driver(driver_id::text))');
  d := pg_temp._ancora(d, E'FROM public.tvde_driver_balances)',
         E'FROM public.tvde_driver_balances WHERE NOT public.is_demo_driver(driver_id::text))');
  d := pg_temp._ancora(d, E'FROM public.payment_reconciliation_findings WHERE resolved_at IS NULL)',
         E'FROM public.payment_reconciliation_findings WHERE resolved_at IS NULL AND NOT public._vigia_e_demo(entity_type, entity_id))');
  EXECUTE d;
END $patch$;
