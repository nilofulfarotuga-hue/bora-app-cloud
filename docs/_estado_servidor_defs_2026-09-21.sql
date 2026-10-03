-- Definições VIVAS lidas do servidor a 21/09/2026 (pg_get_functiondef, por REST/service_role). Só leitura.

-- ===== compute_driver_settlement(p_driver_id uuid, p_week_start timestamp with time zone, p_persist boolean) =====
CREATE OR REPLACE FUNCTION public.compute_driver_settlement(p_driver_id uuid, p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_persist boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_bounds RECORD;
  v_total_deliveries INT := 0;
  v_total_earnings NUMERIC := 0;
  v_total_cash_received NUMERIC := 0;
  v_total_card_orders NUMERIC := 0;
  v_cash_adjustments_due NUMERIC := 0;
  v_total_reimbursements NUMERIC := 0;
  v_tokens_converted_value NUMERIC := 0;
  v_tvde_rides INT := 0;
  v_tvde_earnings NUMERIC := 0;
  v_tvde_cash NUMERIC := 0;
  v_tvde_online NUMERIC := 0;
  v_tvde_sem_tarifa INT := 0;
  v_net_balance NUMERIC := 0;
  v_direction TEXT;
  v_settlement_id UUID;
BEGIN
  IF v_caller IS NOT NULL AND v_caller <> p_driver_id THEN
    IF NOT EXISTS (SELECT 1 FROM auth.users
                    WHERE id = v_caller
                      AND raw_app_meta_data->>'role' = 'admin') THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  SELECT
    COUNT(*),
    COALESCE(SUM(driver_earnings), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash' THEN COALESCE(final_total, price, 0) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method IN ('card','mbway') THEN COALESCE(final_total, price, 0) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash'
                  THEN public.order_driver_reimbursement(id) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN payment_method='cash'
                  THEN GREATEST(COALESCE(final_total, price, 0)
                                - COALESCE(driver_earnings, 0)
                                - public.order_driver_reimbursement(id), 0)
                  ELSE 0 END), 0)
  INTO v_total_deliveries, v_total_earnings, v_total_cash_received,
       v_total_card_orders, v_total_reimbursements, v_cash_adjustments_due
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id::text
    AND status = 'delivered'
    AND delivered_at >= v_bounds.week_start
    AND delivered_at <= v_bounds.week_end;

  -- CONTAS CLARAS: as corridas TVDE entram no acerto semanal.
  --
  -- CORRECAO 21/09 (substitui a regra "tarifa em falta = ganho + corte" que a Claude.ai
  -- aplicou a 20/09 e que estava ERRADA): tarifa a zero nem sempre e dado em falta.
  -- Nas VOLTAS de pacote e nas corridas de plano o zero e o valor certo — o passageiro
  -- ja pagou na ida ou no plano e na volta o motorista nao recebe nada. Deduzir ganho +
  -- corte cobrava dinheiro que nunca existiu (13 corridas erradas, 68,00 EUR a mais ao
  -- Danilo). O dinheiro em mao passa a vir de tvde_rides.cash_in_hand_cents, gravado por
  -- gatilho pela regra unica tvde_ride_cash_in_hand, que e a mesma regra do saldo.
  SELECT
    COUNT(*),
    COALESCE(SUM(COALESCE(driver_earn_cents, 0)), 0) / 100.0,
    COALESCE(SUM(COALESCE(cash_in_hand_cents, 0)), 0) / 100.0,
    COALESCE(SUM(CASE WHEN payment_method IN ('card','mbway')
                  THEN COALESCE(final_fare_cents, est_fare_cents, 0) ELSE 0 END), 0) / 100.0,
    COUNT(*) FILTER (WHERE cash_in_hand_cents IS NULL)
  INTO v_tvde_rides, v_tvde_earnings, v_tvde_cash, v_tvde_online, v_tvde_sem_tarifa
  FROM public.tvde_rides
  WHERE driver_id = p_driver_id
    AND status = 'finalizada'
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  v_total_earnings      := v_total_earnings + v_tvde_earnings;
  v_total_cash_received := v_total_cash_received + v_tvde_cash;
  v_total_card_orders   := v_total_card_orders + v_tvde_online;

  SELECT COALESCE(SUM(amount), 0) INTO v_tokens_converted_value
  FROM public.driver_transactions
  WHERE driver_id = p_driver_id
    AND type = 'token_conversion'
    AND status = 'completed'
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  -- FIX 2026-08-03: o que o estafeta adiantou nas compras volta para ele.
  v_net_balance := ROUND(v_total_earnings - v_total_cash_received
                       + v_total_reimbursements
                       + v_tokens_converted_value, 2);
  v_direction := CASE
    WHEN v_net_balance > 0 THEN 'bora_pays_driver'
    WHEN v_net_balance < 0 THEN 'driver_pays_bora'
    ELSE 'zero'
  END;

  IF p_persist THEN
    INSERT INTO public.driver_weekly_settlements (
      driver_id, week_start_at, week_end_at,
      total_deliveries, total_earnings, total_cash_received,
      total_card_orders, cash_adjustments_due, total_reimbursements,
      tokens_converted_value,
      tvde_rides_count, tvde_earnings, tvde_cash_received,
      net_balance, direction, status
    ) VALUES (
      p_driver_id, v_bounds.week_start, v_bounds.week_end,
      v_total_deliveries, v_total_earnings, v_total_cash_received,
      v_total_card_orders, v_cash_adjustments_due, v_total_reimbursements,
      v_tokens_converted_value,
      v_tvde_rides, v_tvde_earnings, v_tvde_cash,
      v_net_balance, v_direction, 'pending'
    )
    ON CONFLICT (driver_id, week_start_at) DO UPDATE SET
      total_deliveries       = EXCLUDED.total_deliveries,
      total_earnings         = EXCLUDED.total_earnings,
      total_cash_received    = EXCLUDED.total_cash_received,
      total_card_orders      = EXCLUDED.total_card_orders,
      cash_adjustments_due   = EXCLUDED.cash_adjustments_due,
      total_reimbursements   = EXCLUDED.total_reimbursements,
      tokens_converted_value = EXCLUDED.tokens_converted_value,
      tvde_rides_count       = EXCLUDED.tvde_rides_count,
      tvde_earnings          = EXCLUDED.tvde_earnings,
      tvde_cash_received     = EXCLUDED.tvde_cash_received,
      net_balance            = EXCLUDED.net_balance,
      direction              = EXCLUDED.direction
    WHERE public.driver_weekly_settlements.status NOT IN ('paid','received')
    RETURNING id INTO v_settlement_id;
  END IF;

  RETURN jsonb_build_object(
    'driver_id', p_driver_id,
    'week_start', v_bounds.week_start,
    'week_end', v_bounds.week_end,
    'total_deliveries', v_total_deliveries,
    'total_earnings', v_total_earnings,
    'total_cash_received', v_total_cash_received,
    'total_card_orders', v_total_card_orders,
    'cash_adjustments_due', v_cash_adjustments_due,
    'total_reimbursements', v_total_reimbursements,
    'tokens_converted_value', v_tokens_converted_value,
    'tvde_rides_count', v_tvde_rides,
    'tvde_earnings', v_tvde_earnings,
    'tvde_cash_received', v_tvde_cash,
    'tvde_sem_dinheiro_em_mao_gravado', v_tvde_sem_tarifa,
    'net_balance', v_net_balance,
    'direction', v_direction,
    'settlement_id', v_settlement_id,
    'persisted', p_persist
  );
END;
$function$
;

-- ===== close_previous_week_settlements() =====
CREATE OR REPLACE FUNCTION public.close_previous_week_settlements()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT := 0;
  v_anchor TIMESTAMPTZ := now() - interval '1 day';  -- domingo passado
  v_drv RECORD;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_calc JSONB;
  v_novo NUMERIC;
  v_velho NUMERIC;
  v_status TEXT;
  v_nome TEXT;
  v_travadas JSONB := '[]'::JSONB;
  v_texto TEXT;
BEGIN
  SELECT b.week_start, b.week_end INTO v_ws, v_we
  FROM public.driver_settlement_week_bounds(v_anchor) b;

  -- CONTAS CLARAS 2026-09-20: o fecho so percorria quem fez ENTREGAS, por isso
  -- quem trabalhou apenas em TVDE ficava de fora do acerto e nunca era pago.
  -- Passa a percorrer as duas origens.
  FOR v_drv IN
    SELECT DISTINCT id FROM (
      SELECT o.assigned_driver_id::uuid AS id
      FROM public.orders o, public.driver_settlement_week_bounds(v_anchor) b
      WHERE o.status = 'delivered'
        AND o.delivered_at >= b.week_start
        AND o.delivered_at <= b.week_end
        AND o.assigned_driver_id ~ '^[0-9a-f]{8}-'
      UNION
      SELECT r.driver_id AS id
      FROM public.tvde_rides r, public.driver_settlement_week_bounds(v_anchor) b
      WHERE r.status = 'finalizada'
        AND r.driver_id IS NOT NULL
        AND r.created_at >= b.week_start
        AND r.created_at <= b.week_end
    ) todos
  LOOP
    -- 1) a verdade, sem gravar nada
    v_calc := public.compute_driver_settlement(v_drv.id, v_anchor, false);
    v_novo := (v_calc ->> 'net_balance')::NUMERIC;

    -- 2) o que la esta, e se a trava vai impedir a reescrita
    SELECT s.status, s.net_balance INTO v_status, v_velho
    FROM public.driver_weekly_settlements s
    WHERE s.driver_id = v_drv.id AND s.week_start_at = v_ws;

    IF v_status IN ('paid','received')
       AND round(COALESCE(v_velho,0) * 100) <> round(COALESCE(v_novo,0) * 100) THEN
      SELECT COALESCE(u.name, v_drv.id::text) INTO v_nome
      FROM public.users u WHERE u.id = v_drv.id;

      v_travadas := v_travadas || jsonb_build_object(
        'driver_id', v_drv.id, 'nome', COALESCE(v_nome, v_drv.id::text),
        'estado', v_status, 'valor_na_linha', v_velho, 'valor_recalculado', v_novo,
        'diferenca', round(v_novo - COALESCE(v_velho,0), 2));

      INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
      VALUES ('fecho_linha_travada_valor_diferente', 'driver', v_drv.id::text,
              jsonb_build_object(
                'week_start', v_ws, 'week_end', v_we,
                'nome', COALESCE(v_nome, v_drv.id::text),
                'estado_da_linha', v_status,
                'valor_na_linha', v_velho,
                'valor_recalculado', v_novo,
                'diferenca', round(v_novo - COALESCE(v_velho,0), 2),
                'nota', 'A linha nao foi reescrita por estar paga. O recibo desta semana '
                     || 'leva o valor antigo. Verificar se o pagamento foi mesmo feito; '
                     || 'se nao foi, reabrir a linha e recalcular.'));
    END IF;

    -- 3) grava (nao faz nada se a linha estiver paga — e assim que deve ser)
    PERFORM public.compute_driver_settlement(v_drv.id, v_anchor, true);
    v_count := v_count + 1;
  END LOOP;

  -- 4) se alguma ficou travada com valor diferente, avisa. Nunca corrige.
  IF jsonb_array_length(v_travadas) > 0 THEN
    SELECT string_agg('• ' || (x ->> 'nome') || ': na linha ' || (x ->> 'valor_na_linha')
                      || ' EUR, recalculado ' || (x ->> 'valor_recalculado')
                      || ' EUR (' || (x ->> 'estado') || ')', chr(10))
      INTO v_texto
    FROM jsonb_array_elements(v_travadas) x;

    BEGIN
      PERFORM net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url')
               || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
          'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'kind', 'generic',
          'title', 'Fecho: ' || jsonb_array_length(v_travadas) || ' linha(s) por rever',
          'body', 'Estas linhas ja estavam pagas e por isso o fecho nao lhes pode tocar, '
                  || 'mas o valor recalculado e outro. O recibo saiu com o valor antigo:'
                  || chr(10) || v_texto,
          'route', '/admin/acertos-semana',
          'ref', 'fecho_travado_' || v_ws::date));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
      VALUES ('fecho_aviso_linha_travada_falhou', 'driver', NULL,
              jsonb_build_object('erro', SQLERRM, 'week_start', v_ws, 'travadas', v_travadas));
    END;
  END IF;

  RETURN v_count;
END;
$function$
;

-- ===== weekly_closeout_compile(p_week_start date) =====
CREATE OR REPLACE FUNCTION public.weekly_closeout_compile(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ws date;
  v_total int := 0;
  v_summary jsonb;
BEGIN
  v_ws := COALESCE(p_week_start, (
    SELECT max(w) FROM (
      SELECT week_start_at::date w FROM driver_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM cleaner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM appointment_payouts
      UNION ALL SELECT week_start_at::date FROM partner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM washer_weekly_settlements
    ) x WHERE w < (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date));
  IF v_ws IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'week_start', null, 'total', 0,
      'to_pay', '[]'::jsonb, 'to_receive', '[]'::jsonb, 'zero_count', 0,
      'note', 'sem settlements para compilar');
  END IF;

  -- DRIVERS (euros; net_balance ja vem SIGNED, negativo = deve a Bora)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'driver', s.driver_id::text,
         COALESCE(d.name, 'Estafeta'),
         COALESCE(NULLIF(d.email,''), u.email),
         COALESCE(NULLIF(d.mbway_phone,''), d.phone),
         round(s.net_balance * 100)::int,
         CASE WHEN s.net_balance < 0 THEN 'owes_bora'
              WHEN s.net_balance > 0 THEN 'bora_pays' ELSE 'zero' END,
         -- As parcelas, pela ordem por que se leem: o que ganhou, o que
         -- adiantou e lhe volta, e por fim o que tem em mao e devolve.
         (CASE WHEN COALESCE(s.total_deliveries,0) <> 0
                 OR round((COALESCE(s.total_earnings,0) - COALESCE(s.tvde_earnings,0)) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Entregas',
                      'qty', COALESCE(s.total_deliveries,0),
                      'value_cents', round((COALESCE(s.total_earnings,0) - COALESCE(s.tvde_earnings,0)) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN COALESCE(s.tvde_rides_count,0) <> 0
                 OR round(COALESCE(s.tvde_earnings,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Corridas',
                      'qty', COALESCE(s.tvde_rides_count,0),
                      'value_cents', round(COALESCE(s.tvde_earnings,0) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN round(COALESCE(s.total_reimbursements,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Compras que adiantou do bolso',
                      'value_cents', round(COALESCE(s.total_reimbursements,0) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN round(COALESCE(s.tokens_converted_value,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Tokens convertidos',
                      'value_cents', round(COALESCE(s.tokens_converted_value,0) * 100)::int))
               ELSE '[]'::jsonb END)
      || (CASE WHEN round(COALESCE(s.total_cash_received,0) * 100)::int <> 0
               THEN jsonb_build_array(jsonb_build_object(
                      'label','Dinheiro que recebeu em mão (devolve à Bora)',
                      'value_cents', -round(COALESCE(s.total_cash_received,0) * 100)::int))
               ELSE '[]'::jsonb END),
         'pending'
  FROM driver_weekly_settlements s
  LEFT JOIN drivers d ON d.id::text = s.driver_id::text OR d.user_id::text = s.driver_id::text
  LEFT JOIN auth.users u ON u.id = d.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- CLEANERS (cents; net_payout_cents, direcao pelo texto ou sinal)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'cleaner', s.cleaner_id::text,
         COALESCE(c.name,'Profissional de limpeza'),
         COALESCE(NULLIF(c.email,''), u.email),
         COALESCE(NULLIF(c.mbway_phone,''), c.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Limpezas','qty',COALESCE(s.total_jobs,0),'value_cents',COALESCE(s.total_earnings_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.total_bora_fee_cents,0))
         ),
         'pending'
  FROM cleaner_weekly_settlements s
  LEFT JOIN cleaners c ON c.id::text = s.cleaner_id::text OR c.user_id::text = s.cleaner_id::text
  LEFT JOIN auth.users u ON u.id = c.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- PROVIDERS / servicos (cents; net_payout_cents)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'provider', s.provider_id::text,
         COALESCE(sp.name,'Parceiro de servicos'),
         u.email,
         COALESCE(NULLIF(sp.mbway_phone,''), sp.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Marcacoes','qty',COALESCE(s.total_appointments,0),'value_cents',COALESCE(s.total_service_revenue_cents,0)),
           jsonb_build_object('label','Sinais retidos','value_cents',COALESCE(s.total_deposits_retained_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.bora_booking_fees_cents,0))
         ),
         'pending'
  FROM appointment_payouts s
  LEFT JOIN service_providers sp ON sp.id::text = s.provider_id::text OR sp.user_id::text = s.provider_id::text
  LEFT JOIN auth.users u ON u.id = sp.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- PARTNERS / restaurantes (euros; net_balance SIGNED)
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'partner', s.partner_id::text,
         COALESCE(r.name,'Parceiro'),
         COALESCE(NULLIF(r.email,''), u.email),
         COALESCE(NULLIF(r.mbway_phone,''), r.phone),
         round(COALESCE(s.net_balance,0) * 100)::int,
         CASE WHEN COALESCE(s.net_balance,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_balance,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Pedidos','qty',COALESCE(s.total_orders,0),'value_cents',round(COALESCE(s.gross_sales,0)*100)::int),
           jsonb_build_object('label','Comissao Bora','value_cents',-round(COALESCE(s.commission_total,0)*100)::int),
           jsonb_build_object('label','Cash retido pelo parceiro','value_cents',round(COALESCE(s.cash_kept_by_partner,0)*100)::int)
         ),
         'pending'
  FROM partner_weekly_settlements s
  LEFT JOIN restaurants r ON r.id::text = s.partner_id::text OR r.user_id::text = s.partner_id::text
  LEFT JOIN auth.users u ON u.id = r.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  -- WASHERS / lavagem auto (cents; net_payout_cents) — ACRESCENTADO 2026-09-07.
  INSERT INTO weekly_digest_log AS w
    (week_start_at, week_end_at, subject_type, subject_id, subject_name,
     subject_email, subject_phone, net_cents, direction, breakdown, email_status)
  SELECT s.week_start_at, s.week_end_at, 'washer', s.washer_id::text,
         COALESCE(wa.name,'Profissional de lavagem'),
         COALESCE(NULLIF(wa.email,''), u.email),
         COALESCE(NULLIF(wa.mbway_phone,''), wa.phone),
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%'
              THEN -abs(COALESCE(s.net_payout_cents,0)) ELSE COALESCE(s.net_payout_cents,0) END,
         CASE WHEN s.direction ILIKE '%pays_bora%' OR s.direction ILIKE '%to_bora%' OR COALESCE(s.net_payout_cents,0) < 0 THEN 'owes_bora'
              WHEN COALESCE(s.net_payout_cents,0) > 0 THEN 'bora_pays' ELSE 'zero' END,
         jsonb_build_array(
           jsonb_build_object('label','Lavagens','qty',COALESCE(s.total_jobs,0),'value_cents',COALESCE(s.total_earnings_cents,0)),
           jsonb_build_object('label','Taxa Bora','value_cents',-COALESCE(s.total_bora_fee_cents,0))
         ),
         'pending'
  FROM washer_weekly_settlements s
  LEFT JOIN washers wa ON wa.id::text = s.washer_id::text OR wa.user_id::text = s.washer_id::text
  LEFT JOIN auth.users u ON u.id = wa.user_id
  WHERE s.week_start_at::date = v_ws
  ON CONFLICT (week_start_at, subject_type, subject_id) DO UPDATE SET
    net_cents=EXCLUDED.net_cents, direction=EXCLUDED.direction, breakdown=EXCLUDED.breakdown,
    subject_name=EXCLUDED.subject_name, subject_email=EXCLUDED.subject_email,
    subject_phone=EXCLUDED.subject_phone
  WHERE w.email_status IN ('pending','failed','aguarda_dominio');

  SELECT count(*)::int INTO v_total FROM weekly_digest_log WHERE week_start_at::date = v_ws;

  SELECT jsonb_build_object(
    'ok', true, 'week_start', v_ws,
    'week_end', (SELECT max(week_end_at)::date FROM weekly_digest_log WHERE week_start_at::date = v_ws),
    'total', v_total,
    'to_pay', COALESCE((SELECT jsonb_agg(jsonb_build_object('name',subject_name,'amount_cents',abs(net_cents),'mbway',subject_phone,'type',subject_type) ORDER BY abs(net_cents) DESC)
                        FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='bora_pays'), '[]'::jsonb),
    'to_receive', COALESCE((SELECT jsonb_agg(jsonb_build_object('name',subject_name,'amount_cents',abs(net_cents),'mbway',subject_phone,'type',subject_type) ORDER BY abs(net_cents) DESC)
                        FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='owes_bora'), '[]'::jsonb),
    'zero_count', (SELECT count(*)::int FROM weekly_digest_log WHERE week_start_at::date=v_ws AND direction='zero')
  ) INTO v_summary;

  RETURN v_summary;
END $function$
;

-- ===== finalize_storeshopping_purchase(p_order_id text, p_items_status jsonb, p_items_added jsonb, p_bag_count integer) =====
CREATE OR REPLACE FUNCTION public.finalize_storeshopping_purchase(p_order_id text, p_items_status jsonb, p_items_added jsonb DEFAULT '[]'::jsonb, p_bag_count integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_uid              UUID;
  v_order                   RECORD;
  v_markup_pct              NUMERIC;
  v_max_extra_pct           NUMERIC;
  v_per_bag_cents           INT;
  v_bought_total_cents      INT := 0;
  v_unavailable_total_cents INT := 0;
  v_added_total_cents       INT := 0;
  v_bag_fee_cents           INT;
  v_delivery_fee_cents      INT;
  v_service_fee_cents       INT;
  v_small_order_fee_cents   INT;
  v_final_total_cents       INT;
  v_orig_total_cents        INT;
  v_paid_cents              INT;
  v_refund_cents            INT;
  v_extra_charge_cents      INT;
  v_refund_method           TEXT := NULL;
  v_new_payment_status      TEXT;
  v_warning                 TEXT := NULL;
  v_items_added_resolved    JSONB := '[]'::jsonb;
  v_payload_entry           JSONB;
  v_canonical_item          JSONB;
  v_added_item              JSONB;
  v_payload_id              TEXT;
  v_payload_status          TEXT;
  v_canon_price_cents       INT;
  v_canon_qty               INT;
  v_base_cents              INT;
  v_qty                     INT;
  v_final_cents             INT;
  v_status_by_id            JSONB := '{}'::jsonb;
  v_merged_items            JSONB := '[]'::jsonb;
  v_canon_id                TEXT;
  v_canon_status            TEXT;
  v_canon_default_status    TEXT;
  v_is_card                 BOOLEAN;
  v_is_restaurant           BOOLEAN;
  v_cash_extra_cents        INT := 0;
  v_wallet_neg_enabled      BOOLEAN;
  v_adjust_result           JSONB;
  v_adjust_reason           TEXT;
  v_wallet_debit_applied    INT := 0;
  v_wallet_balance_after    INT := NULL;
BEGIN
  v_caller_uid := auth.uid();
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;

  IF v_order.assigned_driver_id IS DISTINCT FROM v_caller_uid::text THEN
    RAISE EXCEPTION 'forbidden_not_assigned_driver: caller=% driver=%',
      v_caller_uid, v_order.assigned_driver_id
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_order.is_purchase_finalized, false) = true THEN
    RAISE EXCEPTION 'already_finalized' USING ERRCODE = '23514';
  END IF;

  IF v_order.service_type NOT IN ('storeShopping','restaurant') THEN
    RAISE EXCEPTION 'wrong_service_type: % (expected storeShopping or restaurant)', v_order.service_type
      USING ERRCODE = '23514';
  END IF;

  v_is_restaurant := v_order.service_type = 'restaurant';
  v_canon_default_status := CASE WHEN v_is_restaurant THEN 'bought' ELSE 'pending' END;

  SELECT COALESCE((value::text)::numeric, 0.15) INTO v_markup_pct
    FROM public.platform_settings WHERE key = 'non_partner_markup_pct';
  v_markup_pct := COALESCE(v_markup_pct, 0.15);

  SELECT COALESCE((value::text)::numeric, 0.30) INTO v_max_extra_pct
    FROM public.platform_settings WHERE key = 'max_extra_charge_pct';
  v_max_extra_pct := COALESCE(v_max_extra_pct, 0.30);

  SELECT COALESCE((value::text)::int, 10) INTO v_per_bag_cents
    FROM public.platform_settings WHERE key = 'bag_fee_supermarket_per_bag_cents';
  v_per_bag_cents := COALESCE(v_per_bag_cents, 10);

  SELECT COALESCE((value::text)::boolean, true) INTO v_wallet_neg_enabled
    FROM public.platform_settings WHERE key='wallet_negative_enabled';
  v_wallet_neg_enabled := COALESCE(v_wallet_neg_enabled, true);

  IF v_is_restaurant THEN
    IF COALESCE(v_order.is_partner_store, false) THEN
      v_bag_fee_cents := 0;
    ELSE
      v_bag_fee_cents := 30;
    END IF;
  ELSE
    IF p_bag_count IS NOT NULL THEN
      IF p_bag_count < 0 OR p_bag_count > 5 THEN
        RAISE EXCEPTION 'invalid_bag_count: % (must be 0-5)', p_bag_count
          USING ERRCODE = '23514';
      END IF;
      v_bag_fee_cents := p_bag_count * v_per_bag_cents;
    ELSE
      v_bag_fee_cents := ROUND(COALESCE(v_order.bag_fee, 0) * 100)::int;
    END IF;
  END IF;

  v_delivery_fee_cents := ROUND(COALESCE(v_order.delivery_fee, 0) * 100)::int;
  v_service_fee_cents  := ROUND(COALESCE(v_order.service_fee, 0) * 100)::int;
  -- CONTAS CLARAS 21/09: a taxa de pedido pequeno ja foi orcamentada ao
  -- cliente e gravada pelo gatilho; volta a entrar no total em vez de
  -- desaparecer no fecho da compra.
  v_small_order_fee_cents := ROUND(COALESCE(v_order.small_order_fee, 0) * 100)::int;

  IF p_items_status IS NOT NULL AND jsonb_typeof(p_items_status) = 'array' THEN
    FOR v_payload_entry IN SELECT jsonb_array_elements(p_items_status)
    LOOP
      v_payload_id := COALESCE(
        v_payload_entry->>'id',
        v_payload_entry->>'productId',
        v_payload_entry->>'product_id'
      );
      v_payload_status := COALESCE(
        v_payload_entry->>'purchase_status',
        v_payload_entry->>'purchaseStatus'
      );
      IF v_payload_id IS NULL OR v_payload_id = '' THEN
        RAISE EXCEPTION 'missing_item_id_in_payload: %', v_payload_entry::text
          USING ERRCODE = '23514';
      END IF;
      v_status_by_id := v_status_by_id || jsonb_build_object(
        v_payload_id, COALESCE(v_payload_status, v_canon_default_status)
      );
    END LOOP;
  END IF;

  IF v_order.items IS NOT NULL AND jsonb_typeof(v_order.items) = 'array' THEN
    FOR v_canonical_item IN SELECT jsonb_array_elements(v_order.items)
    LOOP
      v_canon_id := COALESCE(
        v_canonical_item->>'productId',
        v_canonical_item->>'product_id',
        v_canonical_item->>'id'
      );
      v_canon_price_cents := ROUND(
        COALESCE((v_canonical_item->>'price')::numeric, 0) * 100
      )::int;
      v_canon_qty := COALESCE(
        NULLIF(v_canonical_item->>'quantity','')::int,
        NULLIF(v_canonical_item->>'qty','')::int,
        1
      );
      v_canon_status := COALESCE(
        v_status_by_id->>v_canon_id,
        v_canonical_item->>'purchaseStatus',
        v_canonical_item->>'purchase_status',
        v_canon_default_status
      );
      IF v_canon_status = 'bought' THEN
        v_bought_total_cents := v_bought_total_cents + (v_canon_price_cents * v_canon_qty);
      ELSIF v_canon_status = 'unavailable' THEN
        v_unavailable_total_cents := v_unavailable_total_cents + (v_canon_price_cents * v_canon_qty);
      END IF;
      v_merged_items := v_merged_items || jsonb_build_array(
        v_canonical_item || jsonb_build_object('purchaseStatus', v_canon_status)
      );
      v_status_by_id := v_status_by_id - v_canon_id;
    END LOOP;
  END IF;

  IF jsonb_typeof(v_status_by_id) = 'object' AND v_status_by_id <> '{}'::jsonb THEN
    RAISE EXCEPTION 'unknown_item_id: %s not in orders.items',
      (SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_status_by_id) k)
      USING ERRCODE = '23514';
  END IF;

  IF p_items_added IS NOT NULL AND jsonb_typeof(p_items_added) = 'array' THEN
    FOR v_added_item IN SELECT jsonb_array_elements(p_items_added)
    LOOP
      v_base_cents := COALESCE((v_added_item->>'price_base_cents')::int, 0);
      v_qty := COALESCE(
        NULLIF(v_added_item->>'qty','')::int,
        NULLIF(v_added_item->>'quantity','')::int,
        1
      );
      v_final_cents := ROUND(v_base_cents * (1 + v_markup_pct))::int;
      IF v_base_cents <= 0 THEN
        RAISE EXCEPTION 'invalid_added_item_price: name=%', v_added_item->>'name'
          USING ERRCODE = '23514';
      END IF;
      v_added_total_cents := v_added_total_cents + (v_final_cents * v_qty);
      v_items_added_resolved := v_items_added_resolved || jsonb_build_array(
        jsonb_build_object(
          'name',              v_added_item->>'name',
          'price_base_cents',  v_base_cents,
          'price_final_cents', v_final_cents,
          'qty',               v_qty,
          'reason',            COALESCE(v_added_item->>'reason', 'driver_substitution'),
          'added_at',          to_jsonb(now()),
          'added_by',          to_jsonb(v_caller_uid)
        )
      );
    END LOOP;
  END IF;

  v_orig_total_cents := ROUND(
    COALESCE(v_order.payment_buffer_total, v_order.final_total, 0) * 100
  )::int;
  v_paid_cents := COALESCE(v_order.stripe_charge_cents, 0)
                + COALESCE(v_order.wallet_applied_cents, 0)
                + COALESCE(v_order.tokens_applied_value_cents, 0);
  v_final_total_cents := v_bought_total_cents
                       + v_added_total_cents
                       + v_bag_fee_cents
                       + v_delivery_fee_cents
                       + v_service_fee_cents
                       + v_small_order_fee_cents;
  v_is_card := v_order.payment_method IN ('card', 'mbway');

  IF v_final_total_cents < v_orig_total_cents THEN
    v_refund_cents := LEAST(v_orig_total_cents - v_final_total_cents, v_paid_cents);
    IF v_refund_cents > 0 THEN
      v_refund_method := CASE WHEN v_is_card THEN 'stripe' ELSE 'wallet' END;
      v_new_payment_status := 'refundPending';
    ELSE
      v_new_payment_status := v_order.payment_status;
    END IF;
    v_extra_charge_cents := 0;
  ELSIF v_final_total_cents > v_orig_total_cents THEN
    IF v_is_card THEN
      v_extra_charge_cents := v_final_total_cents - v_orig_total_cents;
      IF v_wallet_neg_enabled THEN
        v_adjust_reason := CASE
          WHEN p_bag_count IS NOT NULL AND v_added_total_cents > 0 THEN 'market_bags_and_substitutions'
          WHEN p_bag_count IS NOT NULL THEN 'market_bags_extra'
          WHEN v_added_total_cents > 0 THEN 'driver_substitutions'
          ELSE 'post_delivery_extra'
        END;
        BEGIN
          v_adjust_result := public.wallet_apply_post_delivery_adjustment(
            p_order_id      => p_order_id,
            p_user_id       => v_order.user_id,
            p_amount_cents  => v_extra_charge_cents,
            p_reason        => v_adjust_reason,
            p_kind          => 'debit'
          );
          v_wallet_debit_applied := v_extra_charge_cents;
          v_wallet_balance_after := (v_adjust_result->>'new_balance_cents')::int;
          v_extra_charge_cents := 0;
          v_new_payment_status := v_order.payment_status;
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'wallet_apply_post_delivery_adjustment failed: % — fallback to extraRequired', SQLERRM;
          v_warning := 'wallet_debit_failed:' || SQLERRM;
          v_new_payment_status := 'extraRequired';
        END;
      ELSE
        v_new_payment_status := 'extraRequired';
      END IF;
    ELSE
      -- Cash com extra: o estafeta cobrou mais
      v_cash_extra_cents := v_final_total_cents - v_orig_total_cents;
      v_extra_charge_cents := 0;
      v_new_payment_status := v_order.payment_status;
    END IF;
    v_refund_cents := 0;
  ELSE
    v_refund_cents := 0;
    v_extra_charge_cents := 0;
    v_new_payment_status := v_order.payment_status;
  END IF;

  IF v_orig_total_cents > 0
     AND (v_extra_charge_cents > ROUND(v_orig_total_cents * v_max_extra_pct)::int
          OR v_wallet_debit_applied > ROUND(v_orig_total_cents * v_max_extra_pct)::int)
  THEN
    v_warning := COALESCE(v_warning || '; ', '') || format(
      'extra_charge exceeds %s%% limit: extra=%s wallet_debit=%s orig=%s',
      ROUND(v_max_extra_pct * 100)::int,
      v_extra_charge_cents, v_wallet_debit_applied, v_orig_total_cents
    );
  END IF;

  PERFORM set_config('app.financial_bypass', 'true', true);

  UPDATE public.orders SET
    items                    = v_merged_items,
    items_added              = v_items_added_resolved,
    bag_count                = CASE WHEN v_is_restaurant THEN 1 ELSE COALESCE(p_bag_count, bag_count) END,
    bag_fee                  = v_bag_fee_cents::numeric / 100.0,
    final_total              = v_final_total_cents::numeric / 100.0,
    refund_amount            = CASE WHEN v_refund_cents > 0
                                    THEN v_refund_cents::numeric / 100.0
                                    ELSE NULL END,
    refund_method            = v_refund_method,
    extra_charge_amount      = CASE WHEN v_extra_charge_cents > 0
                                    THEN v_extra_charge_cents::numeric / 100.0
                                    ELSE NULL END,
    extra_charge_settled_at  = CASE WHEN v_wallet_debit_applied > 0 AND extra_charge_settled_at IS NULL
                                    THEN now()
                                    ELSE extra_charge_settled_at END,
    extra_charge_settled_via = CASE WHEN v_wallet_debit_applied > 0 AND extra_charge_settled_via IS NULL
                                    THEN 'wallet'
                                    ELSE extra_charge_settled_via END,
    -- FIX 2026-05-21: cash_total_due deve ser SEMPRE o final_total para
    -- pagamentos em dinheiro — independentemente de haver extra ou não.
    -- Antes só actualizava quando v_cash_extra_cents > 0, o que deixava
    -- o valor antigo (NET) quando o estafeta comprava menos do estimado.
    cash_total_due           = CASE
                                 WHEN NOT v_is_card
                                   THEN v_final_total_cents::numeric / 100.0
                                 ELSE cash_total_due
                               END,
    is_purchase_finalized    = true,
    payment_status           = v_new_payment_status
  WHERE id = p_order_id;

  BEGIN
    INSERT INTO public.admin_audit_log (
      admin_id, admin_email, action, entity_type, entity_id_text, details
    ) VALUES (
      v_caller_uid,
      (SELECT email FROM auth.users WHERE id = v_caller_uid),
      'storeshopping_finalize',
      'order',
      p_order_id,
      jsonb_build_object(
        'driver_id',                v_caller_uid,
        'service_type',             v_order.service_type,
        'is_partner_store',         COALESCE(v_order.is_partner_store, false),
        'bought_total_cents',       v_bought_total_cents,
        'unavailable_total_cents',  v_unavailable_total_cents,
        'added_total_cents',        v_added_total_cents,
        'bag_count_input',          p_bag_count,
        'bag_fee_per_bag_cents',    v_per_bag_cents,
        'bag_fee_cents',            v_bag_fee_cents,
        'delivery_fee_cents',       v_delivery_fee_cents,
        'service_fee_cents',        v_service_fee_cents,
        'small_order_fee_cents',    v_small_order_fee_cents,
        'final_total_cents',        v_final_total_cents,
        'orig_total_cents',         v_orig_total_cents,
        'paid_cents',               v_paid_cents,
        'refund_cents',             v_refund_cents,
        'refund_method',            v_refund_method,
        'extra_charge_cents',       v_extra_charge_cents,
        'cash_extra_cents',         v_cash_extra_cents,
        'wallet_debit_cents',       v_wallet_debit_applied,
        'wallet_balance_after',     v_wallet_balance_after,
        'wallet_negative_enabled',  v_wallet_neg_enabled,
        'payment_status_before',    v_order.payment_status,
        'payment_status_after',     v_new_payment_status,
        'items_added_count',        jsonb_array_length(v_items_added_resolved),
        'markup_pct',               v_markup_pct,
        'max_extra_pct',            v_max_extra_pct,
        'warning',                  v_warning,
        'payment_method',           v_order.payment_method,
        'item_price_source',        'orders.items_canonical'
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'finalize_storeshopping_purchase: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',              true,
    'order_id',             p_order_id,
    'service_type',         v_order.service_type,
    'is_partner_store',     COALESCE(v_order.is_partner_store, false),
    'final_total_cents',    v_final_total_cents,
    'orig_total_cents',     v_orig_total_cents,
    'paid_cents',           v_paid_cents,
    'refund_cents',         v_refund_cents,
    'refund_method',        v_refund_method,
    'extra_charge_cents',   v_extra_charge_cents,
    'cash_extra_cents',     v_cash_extra_cents,
    'wallet_debit_cents',   v_wallet_debit_applied,
    'wallet_balance_after', v_wallet_balance_after,
    'bag_fee_cents',        v_bag_fee_cents,
    'bag_count',            CASE WHEN v_is_restaurant THEN 1 ELSE COALESCE(p_bag_count, v_order.bag_count) END,
    'delivery_fee_cents',   v_delivery_fee_cents,
    'service_fee_cents',    v_service_fee_cents,
    'small_order_fee_cents', v_small_order_fee_cents,
    'payment_status',       v_new_payment_status,
    'items_added_count',    jsonb_array_length(v_items_added_resolved),
    'items_added',          v_items_added_resolved,
    'markup_pct',           v_markup_pct,
    'warning',              v_warning,
    'item_price_source',    'orders.items_canonical'
  );
END;
$function$
;

-- ===== _trg_alerta_pedido_no_vermelho_fn() =====
CREATE OR REPLACE FUNCTION public._trg_alerta_pedido_no_vermelho_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente   numeric;
  v_mercado   numeric;
  v_estafeta  numeric;
  v_bora      numeric;
BEGIN
  IF COALESCE(NEW.is_partner_store, false) THEN RETURN NEW; END IF;

  v_cliente  := COALESCE(NEW.final_total, NEW.price, 0);
  IF v_cliente <= 0 THEN RETURN NEW; END IF;

  v_mercado  := COALESCE(public.order_driver_reimbursement(NEW.id), 0);
  v_estafeta := COALESCE(NEW.driver_earnings, 0);
  v_bora     := ROUND(v_cliente - v_mercado - v_estafeta, 2);

  IF v_bora > 0 THEN RETURN NEW; END IF;

  PERFORM public.notify_admin_event(
    'pedido_no_vermelho',
    CASE WHEN v_bora < 0 THEN 'high' ELSE 'medium' END,
    'Pedido em ' || COALESCE(NEW.vendor_name, 'loja nao-parceira') ||
      ' fechou sem lucro para a Bora: sobraram ' ||
      to_char(v_bora, 'FM990.00') || ' EUR. Cliente pagou ' ||
      to_char(v_cliente, 'FM990.00') || ', a mercadoria custou ' ||
      to_char(v_mercado, 'FM990.00') || ' e o estafeta levou ' ||
      to_char(v_estafeta, 'FM990.00') ||
      '. Ver se o preco do catalogo desta loja esta desatualizado.',
    'order',
    NEW.id,
    jsonb_build_object(
      'order_id', NEW.id,
      'vendor_name', NEW.vendor_name,
      'cliente_pagou', v_cliente,
      'mercadoria', v_mercado,
      'estafeta', v_estafeta,
      'sobrou_para_a_bora', v_bora,
      'catalog_price_gap_cents', NEW.catalog_price_gap_cents,
      'small_order_fee', NEW.small_order_fee),
    '/admin/orders/' || NEW.id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$
;

-- ===== tvde_ride_cash_in_hand(p_ride_id uuid) =====
CREATE OR REPLACE FUNCTION public.tvde_ride_cash_in_hand(p_ride_id uuid)
 RETURNS TABLE(cash_in_hand_cents integer, deduced boolean, regra text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r        public.tvde_rides%ROWTYPE;
  v_meta   jsonb;
  v_pm     text;
  v_stops  integer := 0;
  v_extra  integer := 0;
  v_credit record;
BEGIN
  SELECT * INTO r FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_pm := COALESCE(r.payment_method, 'cash');
  SELECT e.meta INTO v_meta FROM public.tvde_ride_events e
   WHERE e.ride_id = p_ride_id AND e.status = 'finalizada' ORDER BY e.at DESC LIMIT 1;
  v_stops := COALESCE((v_meta->>'stops_cash_cents')::int, 0);
  v_extra := COALESCE((v_meta->>'return_extra_fare_cents')::int, 0);

  IF r.roundtrip_credit_id IS NOT NULL THEN
    SELECT c.paid_cents, (c.payment_intent_id IS NULL) AS pago_a_dinheiro INTO v_credit
      FROM public.tvde_roundtrip_credits c WHERE c.id = r.roundtrip_credit_id;
    IF COALESCE(r.is_return_leg, false) THEN
      RETURN QUERY SELECT (CASE WHEN v_pm = 'cash' THEN v_stops + v_extra ELSE v_stops END), false, 'pacote_volta';
    ELSE
      RETURN QUERY SELECT (CASE WHEN COALESCE(v_credit.pago_a_dinheiro, v_pm = 'cash') THEN COALESCE(v_credit.paid_cents, 0) ELSE 0 END) + v_stops, false, 'pacote_ida';
    END IF;
    RETURN;
  END IF;

  IF COALESCE(r.used_subscription_ride, false) THEN
    RETURN QUERY SELECT v_stops, false, 'plano';
    RETURN;
  END IF;

  IF v_pm = 'cash' THEN
    IF COALESCE(r.final_fare_cents, 0) > 0 THEN
      RETURN QUERY SELECT r.final_fare_cents, false, 'normal_dinheiro';
    ELSE
      RETURN QUERY SELECT COALESCE(r.driver_earn_cents, 0) + COALESCE(r.bora_cut_cents, 0), true, 'normal_dinheiro_sem_tarifa_deduzida';
    END IF;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_stops, false, 'paga_na_app';
END;
$function$
;

-- ===== admin_resend_weekly_digest(p_week_start date) =====
CREATE OR REPLACE FUNCTION public.admin_resend_weekly_digest(p_week_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_req bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url') || '/functions/v1/weekly-closeout-digest',
    headers := jsonb_build_object('Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'), 'Content-Type', 'application/json'),
    body := jsonb_build_object('week_start', p_week_start, 'force', true)
  ) INTO v_req;
  PERFORM public.log_admin_action('resend_weekly_digest', 'weekly_digest', COALESCE(p_week_start::text,'ultima'), jsonb_build_object('request_id', v_req, 'force', true));
  RETURN jsonb_build_object('ok', true, 'request_id', v_req);
END $function$
;

