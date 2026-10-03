-- ============================================================================
-- 2026-09-14 (missao painel-admin-limpo) — CARTOES DE CIMA DO PAINEL, VERSAO 2
--
-- Cicatriz: o RPC antigo (admin_dashboard_metrics) contava "hoje" em UTC
-- (entre a meia-noite e a uma da manha o painel mostrava o dia anterior),
-- somava pedidos de demonstracao, e "a pagar a estafetas" era a soma do livro
-- inteiro desde sempre (12,15 EUR) em vez do acerto da semana (7,04 EUR).
--
-- Regras desta versao:
--   · tudo em Europe/Lisbon: hoje = 00:00-23:59 de Lisboa; semana = segunda
--     00:00 a domingo 23:59:59 de Lisboa (driver_settlement_week_bounds).
--   · demo fora de tudo, salvo se admin_show_demo_data = true.
--   · uma linha por vertical, nunca um numero unico; zero e zero.
--   · dinheiro em 3 cartoes: receita hoje, receita da semana em curso, e o
--     acerto da semana fechada com "a pagar" e "a receber" separados, lidos
--     das tabelas de acerto (as mesmas do ecra "Acertos da semana").
--   · alertas com contagem para abrir o ecra certo.
-- O RPC antigo fica intacto (o ecra antigo em versoes instaladas ainda o chama).
-- ============================================================================

INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('admin_delivery_late_minutes', '60'::jsonb,
   'Painel admin: um pedido em curso ha mais de X minutos conta como atrasado.', 'admin'),
  ('admin_stuck_without_driver_minutes', '15'::jsonb,
   'Painel admin: pedido pronto/a chamar sem estafeta ha mais de X minutos conta como preso.', 'admin')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_dashboard_metrics_v2()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin      record;
  v_show_demo  boolean := public.admin_demo_visible();
  v_day_start  timestamptz := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
  v_day_end    timestamptz;
  v_ws         timestamptz;  -- semana em curso
  v_we         timestamptz;
  v_pws        timestamptz;  -- semana fechada (a ultima com acertos antes da em curso)
  v_pwe        timestamptz;
  v_late_min   int;
  v_stuck_min  int;
  v_fee        int;
  v_entregas   jsonb;
  v_tvde       jsonb;
  v_servicos   jsonb;
  v_limpeza    jsonb;
  v_lavagem    jsonb;
  v_reservas   jsonb;
  v_rec_hoje   jsonb;
  v_rec_sem    jsonb;
  v_acerto     jsonb;
  v_alertas    jsonb;
  v_daily      jsonb;
  v_avisos_24h int := 0;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  v_day_end := v_day_start + interval '1 day';
  SELECT b.week_start, b.week_end INTO v_ws, v_we FROM public.driver_settlement_week_bounds(now()) b;

  SELECT COALESCE((value::text)::int, 60) INTO v_late_min  FROM public.platform_settings WHERE key = 'admin_delivery_late_minutes';
  SELECT COALESCE((value::text)::int, 15) INTO v_stuck_min FROM public.platform_settings WHERE key = 'admin_stuck_without_driver_minutes';
  SELECT COALESCE((value::text)::int, 50) INTO v_fee       FROM public.platform_settings WHERE key = 'appointment_booking_fee_cents';
  v_late_min := COALESCE(v_late_min, 60); v_stuck_min := COALESCE(v_stuck_min, 15); v_fee := COALESCE(v_fee, 50);

  -- Semana fechada: a mais recente com linhas de acerto anteriores a semana em curso.
  SELECT max(ws) INTO v_pws FROM (
    SELECT week_start_at ws FROM public.driver_weekly_settlements  WHERE week_start_at < v_ws
    UNION ALL SELECT week_start_at FROM public.partner_weekly_settlements WHERE week_start_at < v_ws
    UNION ALL SELECT week_start_at FROM public.appointment_payouts        WHERE week_start_at < v_ws
    UNION ALL SELECT week_start_at FROM public.cleaner_weekly_settlements WHERE week_start_at < v_ws
    UNION ALL SELECT week_start_at FROM public.washer_weekly_settlements  WHERE week_start_at < v_ws
  ) x;
  IF v_pws IS NULL THEN v_pws := v_ws - interval '7 days'; END IF;
  v_pwe := v_pws + interval '7 days' - interval '1 second';

  -- ENTREGAS ------------------------------------------------------------------
  SELECT jsonb_build_object(
    'hoje',            count(*) FILTER (WHERE o.created_at >= v_day_start AND o.created_at < v_day_end),
    'entregues_hoje',  count(*) FILTER (WHERE o.status = 'delivered' AND o.delivered_at >= v_day_start AND o.delivered_at < v_day_end),
    'cancelados_hoje', count(*) FILTER (WHERE o.status IN ('cancelled','rejected') AND o.created_at >= v_day_start AND o.created_at < v_day_end),
    'em_curso',        count(*) FILTER (WHERE o.status IN ('preparing','readyForPickup','callingDriver','driverAccepted','pickedUp','onTheWay')
                                          OR (o.status = 'created' AND (o.payment_method = 'cash' OR o.payment_status = 'paid'))),
    'atrasados',       count(*) FILTER (WHERE o.status IN ('preparing','readyForPickup','callingDriver','driverAccepted','pickedUp','onTheWay')
                                          AND o.created_at < now() - make_interval(mins => v_late_min)),
    'presos_sem_estafeta', count(*) FILTER (WHERE o.status IN ('preparing','readyForPickup','callingDriver')
                                          AND o.assigned_driver_id IS NULL
                                          AND o.created_at < now() - make_interval(mins => v_stuck_min)),
    'semana',          count(*) FILTER (WHERE o.created_at >= v_ws AND o.created_at <= v_we),
    'entregues_semana',count(*) FILTER (WHERE o.status = 'delivered' AND o.delivered_at >= v_ws AND o.delivered_at <= v_we)
  ) INTO v_entregas
  FROM public.orders o
  WHERE (o.created_at >= v_ws OR o.status NOT IN ('delivered','cancelled','rejected'))
    AND (v_show_demo OR NOT public.is_demo_order(o));

  -- BORA MOTORISTA / TVDE ---------------------------------------------------------
  SELECT jsonb_build_object(
    'hoje',              count(*) FILTER (WHERE r.created_at >= v_day_start AND r.created_at < v_day_end),
    'finalizadas_hoje',  count(*) FILTER (WHERE r.status = 'finalizada' AND r.updated_at >= v_day_start AND r.updated_at < v_day_end),
    'em_curso',          count(*) FILTER (WHERE r.status IN ('pendente','motorista_a_caminho','motorista_chegou','em_andamento')),
    'agendadas',         count(*) FILTER (WHERE r.status = 'agendada'),
    'sem_motorista_hoje',count(*) FILTER (WHERE r.status = 'sem_motorista' AND r.created_at >= v_day_start AND r.created_at < v_day_end),
    'semana',            count(*) FILTER (WHERE r.created_at >= v_ws AND r.created_at <= v_we)
  ) INTO v_tvde
  FROM public.tvde_rides r
  WHERE (r.created_at >= v_ws OR r.status IN ('pendente','motorista_a_caminho','motorista_chegou','em_andamento','agendada'))
    AND (v_show_demo OR NOT (public.is_demo_user(r.client_id) OR public.is_demo_driver(r.driver_id::text)));

  -- SERVICOS / BARBEARIAS ----------------------------------------------------------
  SELECT jsonb_build_object(
    'hoje',          count(*) FILTER (WHERE a.scheduled_at >= v_day_start AND a.scheduled_at < v_day_end
                                        AND a.status IN ('confirmed','completed','awaiting_confirmation','no_show')),
    'por_concluir',  count(*) FILTER (WHERE a.status = 'confirmed'
                                        AND a.scheduled_at + make_interval(mins => COALESCE(a.duration_minutes, 30)) < now()),
    'por_confirmar', count(*) FILTER (WHERE a.status = 'awaiting_confirmation'),
    'retido_falta_n',     count(*) FILTER (WHERE a.status = 'no_show' AND a.deposit_status = 'retained'),
    'retido_falta_cents', COALESCE(sum(a.deposit_cents) FILTER (WHERE a.status = 'no_show' AND a.deposit_status = 'retained'), 0),
    'semana',        count(*) FILTER (WHERE a.scheduled_at >= v_ws AND a.scheduled_at <= v_we
                                        AND a.status IN ('confirmed','completed','awaiting_confirmation','no_show'))
  ) INTO v_servicos
  FROM public.appointments a
  WHERE a.status <> 'blocked'
    AND (v_show_demo OR NOT (public.is_demo_user(a.client_user_id) OR public.is_demo_provider(a.provider_id)));

  -- LIMPEZA -------------------------------------------------------------------------
  SELECT jsonb_build_object(
    'hoje',         count(*) FILTER (WHERE c.scheduled_at >= v_day_start AND c.scheduled_at < v_day_end AND c.status NOT LIKE 'cancelled%'),
    'em_curso',     count(*) FILTER (WHERE c.status IN ('accepted','on_the_way','in_progress','done')),
    'por_atribuir', count(*) FILTER (WHERE c.status = 'scheduled' AND c.cleaner_id IS NULL),
    'semana',       count(*) FILTER (WHERE c.scheduled_at >= v_ws AND c.scheduled_at <= v_we AND c.status NOT LIKE 'cancelled%')
  ) INTO v_limpeza
  FROM public.cleaning_bookings c
  WHERE (v_show_demo OR (COALESCE(c.is_test_order, false) = false AND NOT public.is_demo_user(c.client_user_id)));

  -- LAVAGEM AUTO --------------------------------------------------------------------
  SELECT jsonb_build_object(
    'hoje',         count(*) FILTER (WHERE w.scheduled_at >= v_day_start AND w.scheduled_at < v_day_end AND w.status NOT LIKE 'cancelled%'),
    'em_curso',     count(*) FILTER (WHERE w.status IN ('accepted','on_the_way','picked_up','in_progress','delivering','done')),
    'por_atribuir', count(*) FILTER (WHERE w.status = 'scheduled' AND w.washer_id IS NULL),
    'semana',       count(*) FILTER (WHERE w.scheduled_at >= v_ws AND w.scheduled_at <= v_we AND w.status NOT LIKE 'cancelled%')
  ) INTO v_lavagem
  FROM public.carwash_bookings w
  WHERE (v_show_demo OR (COALESCE(w.is_test_order, false) = false AND NOT public.is_demo_user(w.client_user_id)));

  -- RESERVAS DE MESA ----------------------------------------------------------------
  SELECT jsonb_build_object(
    'hoje',          count(*) FILTER (WHERE r.reserved_for >= v_day_start AND r.reserved_for < v_day_end
                                        AND r.status IN ('approved','confirmed','arrived','seated')),
    'por_confirmar', count(*) FILTER (WHERE r.status IN ('pending','pending_payment') AND r.reserved_for >= now() - interval '1 day'),
    'semana',        count(*) FILTER (WHERE r.reserved_for >= v_ws AND r.reserved_for <= v_we
                                        AND r.status IN ('approved','confirmed','arrived','seated'))
  ) INTO v_reservas
  FROM public.reservations r
  WHERE (v_show_demo OR NOT (public.is_demo_user(r.client_user_id) OR public.is_demo_restaurant(r.restaurant_id)));

  -- RECEITA DA BORA: hoje e semana em curso, por vertical ------------------------------
  v_rec_hoje := public._admin_receita_bora_cents(v_day_start, v_day_end, v_show_demo, v_fee);
  v_rec_sem  := public._admin_receita_bora_cents(v_ws, v_we + interval '1 second', v_show_demo, v_fee);

  -- ACERTO DA SEMANA FECHADA: o que esta nas tabelas de acerto ----------------------
  WITH linhas AS (
    SELECT 'driver' AS tipo, driver_id::text AS sid, ROUND(net_balance * 100)::bigint AS net_cents, status
      FROM public.driver_weekly_settlements WHERE week_start_at = v_pws
    UNION ALL
    SELECT 'partner', partner_id, ROUND(net_balance * 100)::bigint, status
      FROM public.partner_weekly_settlements WHERE week_start_at = v_pws
    UNION ALL
    SELECT 'provider', provider_id, net_payout_cents::bigint, status
      FROM public.appointment_payouts WHERE week_start_at = v_pws
    UNION ALL
    SELECT 'cleaner', cleaner_id::text, net_payout_cents::bigint, status
      FROM public.cleaner_weekly_settlements WHERE week_start_at = v_pws
    UNION ALL
    SELECT 'washer', washer_id::text, net_payout_cents::bigint, status
      FROM public.washer_weekly_settlements WHERE week_start_at = v_pws
  ), filtradas AS (
    SELECT * FROM linhas WHERE v_show_demo OR NOT public.is_demo_subject(tipo, sid)
  ), por_tipo AS (
    SELECT tipo,
           COALESCE(sum(net_cents) FILTER (WHERE net_cents > 0), 0) AS a_pagar_cents,
           COALESCE(sum(-net_cents) FILTER (WHERE net_cents < 0), 0) AS a_receber_cents,
           COALESCE(sum(net_cents) FILTER (WHERE net_cents > 0 AND status = 'pending'), 0) AS a_pagar_pendente_cents,
           COALESCE(sum(-net_cents) FILTER (WHERE net_cents < 0 AND status = 'pending'), 0) AS a_receber_pendente_cents,
           count(*) FILTER (WHERE status = 'pending' AND net_cents <> 0) AS pendentes,
           count(*) AS linhas
    FROM filtradas GROUP BY tipo
  )
  SELECT jsonb_build_object(
    'week_start', v_pws,
    'week_end', v_pwe,
    'label', to_char(v_pws AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || ' a ' || to_char(v_pwe AT TIME ZONE 'Europe/Lisbon', 'DD/MM'),
    'week_param', to_char(v_pws AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD'),
    'a_pagar_cents', COALESCE(sum(a_pagar_cents), 0),
    'a_receber_cents', COALESCE(sum(a_receber_cents), 0),
    'a_pagar_pendente_cents', COALESCE(sum(a_pagar_pendente_cents), 0),
    'a_receber_pendente_cents', COALESCE(sum(a_receber_pendente_cents), 0),
    'pendentes', COALESCE(sum(pendentes), 0),
    'por_tipo', COALESCE(jsonb_object_agg(tipo, jsonb_build_object(
        'a_pagar_cents', a_pagar_cents, 'a_receber_cents', a_receber_cents,
        'a_pagar_pendente_cents', a_pagar_pendente_cents, 'a_receber_pendente_cents', a_receber_pendente_cents,
        'pendentes', pendentes, 'linhas', linhas)), '{}'::jsonb)
  ) INTO v_acerto FROM por_tipo;

  -- GRAFICO: pedidos por dia, ultimos 7 dias em Lisboa ----------------------------
  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d.dia, 'count', COALESCE(c.n, 0)) ORDER BY d.dia), '[]'::jsonb)
  INTO v_daily
  FROM (SELECT (to_char((v_day_start AT TIME ZONE 'Europe/Lisbon')::date - g, 'YYYY-MM-DD')) AS dia FROM generate_series(6, 0, -1) g) d
  LEFT JOIN (
    SELECT to_char(o.created_at AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD') AS dia, count(*) AS n
    FROM public.orders o
    WHERE o.created_at >= v_day_start - interval '6 days'
      AND (v_show_demo OR NOT public.is_demo_order(o))
    GROUP BY 1
  ) c ON c.dia = d.dia;

  -- ALERTAS -------------------------------------------------------------------------
  BEGIN
    SELECT count(*) INTO v_avisos_24h FROM public.notification_failures WHERE created_at > now() - interval '24 hours';
  EXCEPTION WHEN undefined_table THEN v_avisos_24h := 0;
  END;

  v_alertas := jsonb_build_object(
    'pedidos_presos_sem_estafeta', v_entregas ->> 'presos_sem_estafeta',
    'pedidos_atrasados',           v_entregas ->> 'atrasados',
    'tvde_sem_motorista_hoje',     v_tvde ->> 'sem_motorista_hoje',
    'marcacoes_por_concluir',      v_servicos ->> 'por_concluir',
    'marcacoes_por_confirmar',     v_servicos ->> 'por_confirmar',
    'dinheiro_retido_falta_n',     v_servicos ->> 'retido_falta_n',
    'dinheiro_retido_falta_cents', v_servicos ->> 'retido_falta_cents',
    'limpezas_por_atribuir',       v_limpeza ->> 'por_atribuir',
    'lavagens_por_atribuir',       v_lavagem ->> 'por_atribuir',
    'reservas_por_confirmar',      v_reservas ->> 'por_confirmar',
    'avisos_falhados_24h',         v_avisos_24h,
    'acertos_pendentes',           v_acerto ->> 'pendentes',
    'avisos_por_ler', (SELECT count(*) FROM public.admin_notifications WHERE read_at IS NULL AND archived_at IS NULL)
  );

  RETURN jsonb_build_object(
    'versao', 2,
    'tz', 'Europe/Lisbon',
    'generated_at', now(),
    'demo_visivel', v_show_demo,
    'hoje', jsonb_build_object(
      'inicio', v_day_start, 'fim', v_day_end,
      'label', to_char(v_day_start AT TIME ZONE 'Europe/Lisbon', 'DD/MM')),
    'semana', jsonb_build_object(
      'inicio', v_ws, 'fim', v_we,
      'label', to_char(v_ws AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || ' a ' || to_char(v_we AT TIME ZONE 'Europe/Lisbon', 'DD/MM')),
    'entregas', v_entregas,
    'tvde', v_tvde,
    'servicos', v_servicos,
    'limpeza', v_limpeza,
    'lavagem', v_lavagem,
    'reservas', v_reservas,
    'dinheiro', jsonb_build_object(
      'receita_hoje', v_rec_hoje,
      'receita_semana', v_rec_sem,
      'acerto_semana_fechada', v_acerto),
    'alertas', v_alertas,
    'daily_orders', v_daily
  );
END;
$function$;

-- Receita da Bora num intervalo [p_from, p_to), por vertical, em centimos.
-- Entregas = livro (ledger_entries, user_type='platform') de pedidos nao-demo.
-- TVDE = bora_cut_cents das corridas finalizadas (pelo updated_at: a tabela
-- nao guarda a hora do fim). Servicos = taxa por marcacao concluida + retido.
-- Limpeza/Lavagem = bora_fee_cents dos trabalhos concluidos. Reservas = 1 EUR
-- por mesa com pre-pagamento que chegou; 3 EUR por falta.
CREATE OR REPLACE FUNCTION public._admin_receita_bora_cents(p_from timestamptz, p_to timestamptz, p_show_demo boolean, p_fee_cents int)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_entregas bigint := 0; v_tvde bigint := 0; v_servicos bigint := 0;
  v_limpeza bigint := 0; v_lavagem bigint := 0; v_reservas bigint := 0;
BEGIN
  SELECT COALESCE(ROUND(sum(le.amount) * 100), 0) INTO v_entregas
  FROM public.ledger_entries le
  LEFT JOIN public.orders o ON o.id = le.order_id::text
  WHERE le.user_type = 'platform'
    AND le.created_at >= p_from AND le.created_at < p_to
    AND (p_show_demo OR o.id IS NULL OR NOT public.is_demo_order(o));

  SELECT COALESCE(sum(r.bora_cut_cents), 0) INTO v_tvde
  FROM public.tvde_rides r
  WHERE r.status = 'finalizada'
    AND r.updated_at >= p_from AND r.updated_at < p_to
    AND (p_show_demo OR NOT (public.is_demo_user(r.client_id) OR public.is_demo_driver(r.driver_id::text)));

  SELECT COALESCE(count(*) FILTER (WHERE a.status = 'completed' AND a.completed_at >= p_from AND a.completed_at < p_to), 0) * p_fee_cents
       + COALESCE(sum(a.deposit_cents) FILTER (WHERE a.status = 'no_show' AND a.deposit_status = 'retained'
                                                 AND a.no_show_at >= p_from AND a.no_show_at < p_to), 0)
  INTO v_servicos
  FROM public.appointments a
  WHERE (p_show_demo OR NOT (public.is_demo_user(a.client_user_id) OR public.is_demo_provider(a.provider_id)));

  SELECT COALESCE(sum(c.bora_fee_cents), 0) INTO v_limpeza
  FROM public.cleaning_bookings c
  WHERE c.status = 'completed' AND c.completed_at >= p_from AND c.completed_at < p_to
    AND (p_show_demo OR (COALESCE(c.is_test_order, false) = false AND NOT public.is_demo_user(c.client_user_id)));

  SELECT COALESCE(sum(w.bora_fee_cents), 0) INTO v_lavagem
  FROM public.carwash_bookings w
  WHERE w.status = 'completed' AND w.completed_at >= p_from AND w.completed_at < p_to
    AND (p_show_demo OR (COALESCE(w.is_test_order, false) = false AND NOT public.is_demo_user(w.client_user_id)));

  SELECT COALESCE(count(*) FILTER (WHERE r.status IN ('arrived','seated') AND COALESCE(r.prepayment_cents, 0) > 0
                                     AND COALESCE(r.arrived_at, r.seated_at) >= p_from AND COALESCE(r.arrived_at, r.seated_at) < p_to), 0) * 100
       + COALESCE(sum(r.prepayment_cents) FILTER (WHERE r.status = 'no_show' AND r.decided_at >= p_from AND r.decided_at < p_to), 0)
  INTO v_reservas
  FROM public.reservations r
  WHERE (p_show_demo OR NOT (public.is_demo_user(r.client_user_id) OR public.is_demo_restaurant(r.restaurant_id)));

  RETURN jsonb_build_object(
    'total_cents', v_entregas + v_tvde + v_servicos + v_limpeza + v_lavagem + v_reservas,
    'entregas_cents', v_entregas, 'tvde_cents', v_tvde, 'servicos_cents', v_servicos,
    'limpeza_cents', v_limpeza, 'lavagem_cents', v_lavagem, 'reservas_cents', v_reservas);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_dashboard_metrics_v2() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._admin_receita_bora_cents(timestamptz, timestamptz, boolean, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_metrics_v2() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._admin_receita_bora_cents(timestamptz, timestamptz, boolean, int) TO authenticated, service_role;
