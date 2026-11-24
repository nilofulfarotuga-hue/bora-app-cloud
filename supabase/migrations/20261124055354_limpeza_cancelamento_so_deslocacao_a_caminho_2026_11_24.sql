-- 24/11/2026 (Claude.ai, decisão do Danilo 05:46, "eu autorizo" 05:52): "nós não pagamos nada [à profissional], só
-- pagamos se ela estiver a caminho e o cliente cancelar: aí pagamos a deslocação dela; e o cliente, se cancelar, paga
-- uma taxa de deslocação"; 05:52 "tenho que ficar com um euro".
-- Regra nova do cancelamento pelo CLIENTE:
--  * profissional atrasada (não começou 15 min depois da hora) -> cliente 0, profissional 0 (regra de 23/11, mantém-se);
--  * nenhuma profissional "a caminho" -> cancelamento grátis (acabam os 50%/100% que nunca eram cobrados nem pagos);
--  * profissional "a caminho" -> taxa de deslocação por cada profissional a caminho = o maior entre 5 EUR
--    (cleaning_cancel_travel_comp_cents) e a taxa de deslocação dessa vaga (moradas longe); o cliente paga-a;
--    a Bora fica com 1 EUR (cleaning_cancel_bora_cut_cents) e a profissional recebe o resto, no acerto semanal.
ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS cleaner_compensation_cents integer NOT NULL DEFAULT 0;
COMMENT ON COLUMN public.cleaning_bookings.cleaner_compensation_cents IS
  'Deslocação paga à profissional quando o cliente cancela com ela a caminho (taxa do cliente menos 1 EUR da Bora; regra do Danilo 24/11/2026). Entra no acerto semanal.';

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('cleaning_cancel_travel_comp_cents', '500'::jsonb,
        'Limpeza: taxa de deslocação mínima (cêntimos) que o cliente paga quando cancela com a profissional a caminho (a profissional recebe isto menos a parte da Bora). Moradas longe: vale a taxa de deslocação da limpeza, se for maior.',
        'limpeza')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('cleaning_cancel_bora_cut_cents', '100'::jsonb,
        'Limpeza: parte da Bora (cêntimos) em cada taxa de deslocação cobrada ao cliente que cancela com a profissional a caminho; a profissional recebe o resto.',
        'limpeza')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.cancel_cleaning_booking(p_booking_id uuid, p_reason text DEFAULT ''::text, p_no_show boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_b cleaning_bookings;
  v_me cleaners;
  v_is_client boolean;
  v_hours numeric;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_fee int := 0;
  v_late boolean := false;
  v_late_count int;
  v_limit int := public._cleaning_setting_int('cleaning_late_cancel_limit', 3);
  v_comp_min int := public._cleaning_setting_int('cleaning_cancel_travel_comp_cents', 500);
  v_bora_cut int := public._cleaning_setting_int('cleaning_cancel_bora_cut_cents', 100);
  v_taxa int := 0;
  v_pro_atrasada boolean := false;
  v_comp int := 0;
  v_irma record;
  v_principal uuid;
BEGIN
  -- 19/11/2026 equipa: o CLIENTE cancela sempre a equipa toda, pela vaga 1 (é lá que está o pagamento).
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NOT NULL AND v_b.team_group_id IS NOT NULL AND v_b.team_slot > 1
     AND v_b.client_user_id = v_uid THEN
    SELECT id INTO v_principal FROM cleaning_bookings
     WHERE team_group_id = v_b.team_group_id AND team_slot = 1;
    IF v_principal IS NOT NULL THEN
      RETURN public.cancel_cleaning_booking(v_principal, p_reason, p_no_show);
    END IF;
  END IF;

  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.status NOT IN ('scheduled','accepted','on_the_way') THEN
    RAISE EXCEPTION 'cannot_cancel_from_%', v_b.status;
  END IF;

  v_is_client := (v_b.client_user_id = v_uid);
  IF NOT v_is_client THEN
    v_me := public._cleaning_current_cleaner();
    IF v_b.cleaner_id IS DISTINCT FROM v_me.id
       AND v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
      RAISE EXCEPTION 'booking_not_yours';
    END IF;
  END IF;

  v_hours := EXTRACT(epoch FROM (v_b.scheduled_at - now())) / 3600.0;

  IF v_is_client THEN
    -- 23/11/2026 Danilo: profissional não apareceu = cliente não paga, profissional não recebe
    v_pro_atrasada := (v_b.started_at IS NULL AND now() > v_b.scheduled_at
                       + make_interval(mins => public._cleaning_setting_int('cleaning_pro_late_no_fee_minutes', 15)));

    -- 24/11/2026 Danilo: só há taxa (e compensação) se a profissional já estiver a caminho.
    v_taxa := CASE WHEN NOT v_pro_atrasada AND v_b.status = 'on_the_way' AND v_b.started_at IS NULL
                   THEN GREATEST(v_comp_min, COALESCE(v_b.travel_fee_cents, 0)) ELSE 0 END;
    v_comp := GREATEST(v_taxa - v_bora_cut, 0);   -- a profissional recebe a taxa menos a parte da Bora
    v_fee := v_taxa;
    -- Equipa: a taxa do cliente (na vaga 1, onde está o pagamento) soma a deslocação de cada profissional a caminho.
    IF v_b.team_group_id IS NOT NULL AND v_b.team_slot = 1 THEN
      v_fee := v_fee + COALESCE((
        SELECT SUM(CASE WHEN NOT v_pro_atrasada AND status = 'on_the_way' AND started_at IS NULL
                        THEN GREATEST(v_comp_min, COALESCE(travel_fee_cents, 0)) ELSE 0 END)
          FROM cleaning_bookings
         WHERE team_group_id = v_b.team_group_id AND team_slot > 1
           AND status IN ('scheduled','accepted','on_the_way')), 0);
    END IF;

    UPDATE cleaning_bookings
    SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
        cancel_reason = COALESCE(p_reason,''), cancel_fee_cents = v_fee, cleaner_compensation_cents = v_comp,
        payment_status = CASE
          WHEN payment_method = 'cash' AND v_fee > 0 THEN 'cash_pending'
          WHEN payment_status = 'held' THEN 'estornado'
          ELSE payment_status
        END,
        offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;

    IF v_b.cleaner_id IS NOT NULL THEN
      PERFORM public._cleaning_notify_user(
        (SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
        'cleaning_cancelled', 'Limpeza cancelada',
        'O cliente cancelou a limpeza de ' ||
        to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
        CASE WHEN v_comp > 0
             THEN '. Como já estavas a caminho, recebes ' || (v_comp / 100.0)::numeric(10,2) || ' EUR pela deslocação, no acerto da semana.'
             ELSE '.' END,
        p_booking_id::text);
    END IF;

    -- Equipa: as outras vagas caem com a principal; cada profissional que já ia a caminho recebe a sua deslocação.
    IF v_b.team_group_id IS NOT NULL AND v_b.team_slot = 1 THEN
      FOR v_irma IN
        SELECT id, cleaner_id, status, started_at, travel_fee_cents FROM cleaning_bookings
         WHERE team_group_id = v_b.team_group_id AND team_slot > 1
           AND status IN ('scheduled','accepted','on_the_way')
         FOR UPDATE
      LOOP
        v_comp := CASE WHEN NOT v_pro_atrasada AND v_irma.status = 'on_the_way' AND v_irma.started_at IS NULL
                       THEN GREATEST(GREATEST(v_comp_min, COALESCE(v_irma.travel_fee_cents, 0)) - v_bora_cut, 0) ELSE 0 END;
        UPDATE cleaning_bookings
        SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'client',
            cancel_reason = COALESCE(p_reason,''), cancel_fee_cents = 0, cleaner_compensation_cents = v_comp,
            payment_status = CASE WHEN payment_status = 'held' THEN 'estornado' ELSE payment_status END,
            offer_cleaner_id = NULL, offer_expires_at = NULL
        WHERE id = v_irma.id;
        IF v_irma.cleaner_id IS NOT NULL THEN
          PERFORM public._cleaning_notify_user(
            (SELECT user_id FROM cleaners WHERE id = v_irma.cleaner_id),
            'cleaning_cancelled', 'Limpeza cancelada',
            'O cliente cancelou a limpeza de ' ||
            to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
            CASE WHEN v_comp > 0
                 THEN '. Como já estavas a caminho, recebes ' || (v_comp / 100.0)::numeric(10,2) || ' EUR pela deslocação, no acerto da semana.'
                 ELSE '.' END,
            v_irma.id::text);
        END IF;
      END LOOP;
    END IF;

  ELSE
    IF p_no_show THEN
      IF now() < v_b.scheduled_at THEN
        RAISE EXCEPTION 'no_show_only_after_scheduled_time';
      END IF;
      v_fee := v_b.total_cents;
      UPDATE cleaning_bookings
      SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = 'cleaner',
          cancel_reason = COALESCE(NULLIF(p_reason,''), 'no_show_cliente'),
          cancel_fee_cents = v_fee, no_show_client = true,
          payment_status = CASE
            WHEN payment_method = 'cash' THEN 'cash_pending'
            WHEN payment_status = 'held' THEN 'released'
            ELSE payment_status END
      WHERE id = p_booking_id;
      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_no_show',
        'Limpeza marcada como não comparência',
        'A profissional não conseguiu aceder à morada à hora marcada. Foi aplicada a taxa prevista.',
        p_booking_id::text);
    ELSE
      v_late := (v_hours < v_free);
      UPDATE cleaning_bookings
      SET status = 'scheduled', cleaner_id = NULL, accepted_at = NULL,
          cancelled_late = v_late OR cancelled_late,
          offer_cleaner_id = NULL, offer_expires_at = NULL,
          offered_cleaner_ids = CASE WHEN v_me.id = ANY (offered_cleaner_ids)
                                     THEN offered_cleaner_ids
                                     ELSE offered_cleaner_ids || v_me.id END
      WHERE id = p_booking_id;

      IF v_late THEN
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, true);
        SELECT count(*) INTO v_late_count FROM cleaner_cancel_events
        WHERE cleaner_id = v_me.id AND was_late AND created_at > now() - interval '30 days';
        IF v_late_count >= v_limit THEN
          IF NOT EXISTS (SELECT 1 FROM public.prestador_suspensoes
                          WHERE entidade_tabela='cleaners' AND entidade_id = v_me.id::text
                            AND tipo='proposta_automatica' AND estado='pendente_decisao') THEN
            INSERT INTO public.prestador_suspensoes
              (user_id, tipo_conta, entidade_tabela, entidade_id, tipo, estado, motivo, motivo_codigo, origem, factos)
            VALUES (v_me.user_id, 'limpeza', 'cleaners', v_me.id::text, 'proposta_automatica', 'pendente_decisao',
                    'Proposta automática: ' || v_late_count || ' cancelamentos tardios em 30 dias (limite ' || v_limit || '). Uma pessoa decide.',
                    'cancelamentos_tardios', 'sistema',
                    jsonb_build_object('cancelamentos_tardios_30d', v_late_count, 'limite', v_limit, 'ultimo_booking', p_booking_id));
          END IF;
          PERFORM public._cleaning_notify_admin('Profissional precisa de decisão humana',
            v_me.name || ' atingiu ' || v_late_count || ' cancelamentos tardios em 30 dias. A app NÃO suspendeu: decide no painel > Revisões.');
          PERFORM public._cleaning_notify_user(v_me.user_id, 'cleaner_revisao',
            'A tua conta vai ser revista',
            'Atingiste o limite de cancelamentos tardios. Uma pessoa da equipa Bora vai rever a tua conta e falar contigo antes de qualquer decisão.',
            NULL);
        END IF;
      ELSE
        INSERT INTO cleaner_cancel_events (cleaner_id, booking_id, was_late)
        VALUES (v_me.id, p_booking_id, false);
      END IF;

      PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_reassigning',
        'A tua limpeza vai ser reatribuída',
        CASE WHEN v_b.team_size > 1
             THEN 'Uma profissional da tua equipa cancelou. Estamos a procurar outra para o mesmo horário; não perdes nada.'
             ELSE 'A profissional cancelou. Estamos a procurar outra profissional para o mesmo horário.' END,
        CASE WHEN v_b.team_group_id IS NOT NULL
             THEN COALESCE((SELECT id FROM cleaning_bookings WHERE team_group_id = v_b.team_group_id AND team_slot = 1), p_booking_id)::text
             ELSE p_booking_id::text END);
      PERFORM public._cleaning_next_offer(p_booking_id);
    END IF;
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $function$;

-- Acerto semanal: a deslocação dos cancelamentos com a profissional a caminho entra no que a Bora lhe paga.
CREATE OR REPLACE FUNCTION public.compute_cleaner_weekly_settlement(p_cleaner_id uuid, p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_persist boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_bounds        RECORD;
  v_anchor        TIMESTAMPTZ := COALESCE(p_week_start, now());
  v_total_jobs    INT := 0;
  v_total_earn    INT := 0;
  v_total_fee     INT := 0;
  v_earn_a_pagar  INT := 0;   -- ganho dos trabalhos que a Bora ainda deve
  v_fee_em_divida INT := 0;   -- taxa da Bora que ficou na mao do prestador
  v_comp          INT := 0;   -- 24/11/2026: deslocacoes pagas quando o cliente cancelou com ela a caminho
  v_net           INT := 0;
  v_id            UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds
  FROM public.driver_settlement_week_bounds(v_anchor);

  SELECT
    COUNT(*),
    COALESCE(SUM(cleaner_earnings_cents), 0),
    COALESCE(SUM(bora_fee_cents), 0),
    COALESCE(SUM(cleaner_earnings_cents)
             FILTER (WHERE payment_method IS DISTINCT FROM 'cash'), 0),
    COALESCE(SUM(bora_fee_cents)
             FILTER (WHERE payment_method = 'cash'), 0)
  INTO v_total_jobs, v_total_earn, v_total_fee, v_earn_a_pagar, v_fee_em_divida
  FROM public.cleaning_bookings
  WHERE cleaner_id = p_cleaner_id
    AND status = 'completed'
    AND COALESCE(is_test_order, false) = false
    AND COALESCE(completed_at, scheduled_at) >= v_bounds.week_start
    AND COALESCE(completed_at, scheduled_at) <= v_bounds.week_end;

  SELECT COALESCE(SUM(cleaner_compensation_cents), 0) INTO v_comp
  FROM public.cleaning_bookings
  WHERE cleaner_id = p_cleaner_id
    AND status = 'cancelled_client'
    AND cleaner_compensation_cents > 0
    AND COALESCE(is_test_order, false) = false
    AND cancelled_at >= v_bounds.week_start
    AND cancelled_at <= v_bounds.week_end;

  v_total_earn   := v_total_earn + v_comp;
  v_earn_a_pagar := v_earn_a_pagar + v_comp;

  -- Era `v_net := v_total_earn`. Pagava as limpezas de dinheiro outra vez.
  v_net := v_earn_a_pagar - v_fee_em_divida;

  IF p_persist THEN
    INSERT INTO public.cleaner_weekly_settlements (
      cleaner_id, week_start_at, week_end_at,
      total_jobs, total_earnings_cents, total_bora_fee_cents,
      net_payout_cents, direction, status
    ) VALUES (
      p_cleaner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_jobs, v_total_earn, v_total_fee,
      v_net,
      CASE WHEN v_net < 0 THEN 'cleaner_to_bora' ELSE 'bora_to_cleaner' END,
      'pending'
    )
    ON CONFLICT (cleaner_id, week_start_at) DO UPDATE SET
      week_end_at          = EXCLUDED.week_end_at,
      total_jobs           = EXCLUDED.total_jobs,
      total_earnings_cents = EXCLUDED.total_earnings_cents,
      total_bora_fee_cents = EXCLUDED.total_bora_fee_cents,
      net_payout_cents     = EXCLUDED.net_payout_cents,
      direction            = EXCLUDED.direction
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'cleaner_id',            p_cleaner_id,
    'week_start',            v_bounds.week_start,
    'week_end',              v_bounds.week_end,
    'total_jobs',            v_total_jobs,
    'total_earnings_cents',  v_total_earn,
    'total_bora_fee_cents',  v_total_fee,
    'earnings_a_pagar_cents', v_earn_a_pagar,
    'fee_em_divida_cents',   v_fee_em_divida,
    'compensacoes_deslocacao_cents', v_comp,
    'net_payout_cents',      v_net,
    'settlement_id',         v_id,
    'persisted',             p_persist
  );
END;
$function$;