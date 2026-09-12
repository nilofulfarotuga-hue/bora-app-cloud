-- F2 (2026-06-12): FECHO SEMANAL — parceiros + tokens no fecho estafeta + notificação admin
-- [APLICADA em prod via MCP em 3 migrations: f2_weekly_closeout_partners_tokens_notify,
--  f2_fix_weekly_closeout_severity, f2_admin_weekly_bora_totals — este ficheiro é o
--  espelho consolidado do estado final.]
-- Estende o sistema existente (driver_weekly_settlements/compute_driver_settlement)
-- sem duplicar lógica. Semana = driver_settlement_week_bounds (segunda 00:00 Lisboa).

-- ═══ 1. Tabela de fechos semanais por PARCEIRO (espelho da dos estafetas) ═══
CREATE TABLE IF NOT EXISTS public.partner_weekly_settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id text NOT NULL,
  week_start_at timestamptz NOT NULL,
  week_end_at timestamptz NOT NULL,
  total_orders int NOT NULL DEFAULT 0,
  gross_sales numeric NOT NULL DEFAULT 0,        -- Σ subtotal (preço de menu)
  commission_total numeric NOT NULL DEFAULT 0,   -- Σ (subtotal − partner_share) = comissão visível
  partner_share numeric NOT NULL DEFAULT 0,      -- Σ ledger partner_share (o que é do parceiro)
  cash_kept_by_partner numeric NOT NULL DEFAULT 0, -- takeaway pago em cash na loja
  net_balance numeric NOT NULL DEFAULT 0,        -- share − cash_retido (>0 Bora paga; <0 parceiro deve)
  direction text NOT NULL DEFAULT 'zero',
  status text NOT NULL DEFAULT 'pending',        -- pending(Aberto)|closed(Fechado)|paid|received|disputed
  payment_reference text,
  notes text,
  paid_at timestamptz,
  paid_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (partner_id, week_start_at)
);
ALTER TABLE public.partner_weekly_settlements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS partner_reads_own_settlement ON public.partner_weekly_settlements;
CREATE POLICY partner_reads_own_settlement ON public.partner_weekly_settlements
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.restaurants r
    WHERE r.id = partner_id AND COALESCE(r.user_id, r.user_) = auth.uid()
  ));

-- ═══ 2. FIX (auditoria F1, divergência E): tokens convertidos entram no fecho ═══
CREATE OR REPLACE FUNCTION public.compute_driver_settlement(
  p_driver_id uuid,
  p_week_start timestamp with time zone DEFAULT NULL,
  p_persist boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_bounds RECORD;
  v_total_deliveries INT := 0;
  v_total_earnings NUMERIC := 0;
  v_total_cash_received NUMERIC := 0;
  v_total_card_orders NUMERIC := 0;
  v_cash_adjustments_due NUMERIC := 0;
  v_tokens_converted_value NUMERIC := 0;
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
                  THEN GREATEST(COALESCE(final_total, price, 0) - COALESCE(driver_earnings, 0), 0)
                  ELSE 0 END), 0)
  INTO v_total_deliveries, v_total_earnings, v_total_cash_received,
       v_total_card_orders, v_cash_adjustments_due
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id::text
    AND status = 'delivered'
    AND delivered_at >= v_bounds.week_start
    AND delivered_at <= v_bounds.week_end;

  -- F2: conversões de tokens da semana — a Bora deve este valor ao estafeta
  -- (ou abate na dívida cash). driver_transactions é o registo canónico.
  SELECT COALESCE(SUM(amount), 0) INTO v_tokens_converted_value
  FROM public.driver_transactions
  WHERE driver_id = p_driver_id
    AND type = 'token_conversion'
    AND status = 'completed'
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  v_net_balance := ROUND(v_total_earnings - v_total_cash_received
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
      total_card_orders, cash_adjustments_due, tokens_converted_value,
      net_balance, direction, status
    ) VALUES (
      p_driver_id, v_bounds.week_start, v_bounds.week_end,
      v_total_deliveries, v_total_earnings, v_total_cash_received,
      v_total_card_orders, v_cash_adjustments_due, v_tokens_converted_value,
      v_net_balance, v_direction, 'pending'
    )
    ON CONFLICT (driver_id, week_start_at) DO UPDATE SET
      total_deliveries       = EXCLUDED.total_deliveries,
      total_earnings         = EXCLUDED.total_earnings,
      total_cash_received    = EXCLUDED.total_cash_received,
      total_card_orders      = EXCLUDED.total_card_orders,
      cash_adjustments_due   = EXCLUDED.cash_adjustments_due,
      tokens_converted_value = EXCLUDED.tokens_converted_value,
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
    'tokens_converted_value', v_tokens_converted_value,
    'net_balance', v_net_balance,
    'direction', v_direction,
    'settlement_id', v_settlement_id,
    'persisted', p_persist
  );
END;
$function$;

-- ═══ 3. Cálculo do fecho semanal de UM parceiro ═══
-- Fonte da verdade: ledger_entries (partner_share por pedido) + orders (bruto/cash).
-- Pedido cash-takeaway (parceiro recebeu o dinheiro na loja) entra AO CONTRÁRIO:
-- o share desse pedido anula-se e o parceiro fica a dever o resto (comissões+fees).
CREATE OR REPLACE FUNCTION public.compute_partner_weekly_settlement(
  p_partner_id text,
  p_week_start timestamptz DEFAULT NULL,
  p_persist boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_bounds record;
  v_total_orders int := 0;
  v_gross numeric := 0;
  v_share numeric := 0;
  v_cash_partner numeric := 0;
  v_commission numeric := 0;
  v_net numeric := 0;
  v_direction text;
  v_id uuid;
BEGIN
  IF v_caller IS NOT NULL AND NOT public._is_admin(v_caller) THEN
    IF NOT EXISTS (SELECT 1 FROM public.restaurants r
                    WHERE r.id = p_partner_id
                      AND COALESCE(r.user_id, r.user_) = v_caller) THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  SELECT
    COUNT(*),
    COALESCE(SUM(o.subtotal), 0),
    COALESCE(SUM(ls.share), 0),
    COALESCE(SUM(CASE WHEN o.payment_method = 'cash'
                       AND o.takeaway_picked_up_at IS NOT NULL
                  THEN COALESCE(o.final_total, o.total, o.price, 0)
                  ELSE 0 END), 0)
  INTO v_total_orders, v_gross, v_share, v_cash_partner
  FROM public.orders o
  LEFT JOIN LATERAL (
    SELECT SUM(le.amount) AS share
    FROM public.ledger_entries le
    WHERE le.order_id::text = o.id
      AND le.user_type = 'restaurant'
      AND le.type = 'earning'
  ) ls ON true
  WHERE o.restaurant_id = p_partner_id
    AND o.status = 'delivered'
    AND o.delivered_at >= v_bounds.week_start
    AND o.delivered_at <= v_bounds.week_end;

  v_commission := ROUND(v_gross - v_share, 2);
  v_net := ROUND(v_share - v_cash_partner, 2);
  v_direction := CASE
    WHEN v_net > 0 THEN 'bora_pays_partner'
    WHEN v_net < 0 THEN 'partner_pays_bora'
    ELSE 'zero'
  END;

  IF p_persist THEN
    INSERT INTO public.partner_weekly_settlements (
      partner_id, week_start_at, week_end_at,
      total_orders, gross_sales, commission_total, partner_share,
      cash_kept_by_partner, net_balance, direction, status
    ) VALUES (
      p_partner_id, v_bounds.week_start, v_bounds.week_end,
      v_total_orders, v_gross, v_commission, v_share,
      v_cash_partner, v_net, v_direction, 'pending'
    )
    ON CONFLICT (partner_id, week_start_at) DO UPDATE SET
      total_orders         = EXCLUDED.total_orders,
      gross_sales          = EXCLUDED.gross_sales,
      commission_total     = EXCLUDED.commission_total,
      partner_share        = EXCLUDED.partner_share,
      cash_kept_by_partner = EXCLUDED.cash_kept_by_partner,
      net_balance          = EXCLUDED.net_balance,
      direction            = EXCLUDED.direction
    WHERE public.partner_weekly_settlements.status NOT IN ('paid','received')
    RETURNING id INTO v_id;
  END IF;

  RETURN jsonb_build_object(
    'partner_id', p_partner_id,
    'week_start', v_bounds.week_start,
    'week_end', v_bounds.week_end,
    'total_orders', v_total_orders,
    'gross_sales', v_gross,
    'commission_total', v_commission,
    'partner_share', v_share,
    'cash_kept_by_partner', v_cash_partner,
    'net_balance', v_net,
    'direction', v_direction,
    'settlement_id', v_id,
    'persisted', p_persist
  );
END;
$function$;

-- ═══ 4. Fecho de TODOS os parceiros da semana ═══
CREATE OR REPLACE FUNCTION public.close_partner_week_settlements(
  p_anchor timestamptz DEFAULT now() - interval '1 day'
) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_count int := 0;
  v_p RECORD;
BEGIN
  FOR v_p IN
    SELECT DISTINCT o.restaurant_id AS id
    FROM public.orders o, public.driver_settlement_week_bounds(p_anchor) b
    WHERE o.status = 'delivered'
      AND o.is_partner_store = true
      AND o.restaurant_id IS NOT NULL
      AND o.delivered_at >= b.week_start
      AND o.delivered_at <= b.week_end
  LOOP
    PERFORM public.compute_partner_weekly_settlement(v_p.id, p_anchor, true);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

-- ═══ 5. Lista admin (espelho de admin_list_settlements_for_week) ═══
CREATE OR REPLACE FUNCTION public.admin_list_partner_settlements_for_week(
  p_week_start timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_bounds RECORD;
  v_rows JSONB;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  PERFORM public.close_partner_week_settlements(v_bounds.week_start + interval '1 hour');

  SELECT jsonb_agg(jsonb_build_object(
    'settlement_id',        s.id,
    'partner_id',           s.partner_id,
    'partner_name',         COALESCE(r.name, s.partner_id),
    'total_orders',         s.total_orders,
    'gross_sales',          s.gross_sales,
    'commission_total',     s.commission_total,
    'partner_share',        s.partner_share,
    'cash_kept_by_partner', s.cash_kept_by_partner,
    'net_balance',          s.net_balance,
    'direction',            s.direction,
    'status',               s.status,
    'paid_at',              s.paid_at,
    'payment_reference',    s.payment_reference,
    'notes',                s.notes
  ) ORDER BY ABS(s.net_balance) DESC)
  INTO v_rows
  FROM public.partner_weekly_settlements s
  LEFT JOIN public.restaurants r ON r.id = s.partner_id
  WHERE s.week_start_at = v_bounds.week_start;

  RETURN jsonb_build_object(
    'week_start', v_bounds.week_start,
    'week_end',   v_bounds.week_end,
    'settlements', COALESCE(v_rows, '[]'::jsonb)
  );
END;
$function$;

-- ═══ 6. Mudança de estado pelo admin (com auditoria — regra absoluta) ═══
CREATE OR REPLACE FUNCTION public.admin_set_partner_settlement_status(
  p_settlement_id uuid,
  p_new_status text,
  p_payment_reference text DEFAULT NULL,
  p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_uid UUID := auth.uid();
  v_settlement RECORD;
BEGIN
  IF NOT public._is_admin(v_admin_uid) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  IF p_new_status NOT IN ('pending', 'closed', 'paid', 'received', 'disputed') THEN
    RAISE EXCEPTION 'invalid_status: %', p_new_status USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_settlement FROM public.partner_weekly_settlements
   WHERE id = p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'settlement_not_found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.partner_weekly_settlements SET
    status            = p_new_status,
    payment_reference = COALESCE(p_payment_reference, payment_reference),
    notes             = COALESCE(p_notes, notes),
    paid_at           = CASE WHEN p_new_status IN ('paid','received')
                             THEN now() ELSE paid_at END,
    paid_by           = CASE WHEN p_new_status IN ('paid','received')
                             THEN v_admin_uid ELSE paid_by END
  WHERE id = p_settlement_id;

  PERFORM public.log_admin_action(
    'partner_settlement_status'::text,
    'partner_weekly_settlement'::text,
    p_settlement_id::text,
    jsonb_build_object(
      'partner_id', v_settlement.partner_id,
      'week_start', v_settlement.week_start_at,
      'old_status', v_settlement.status,
      'new_status', p_new_status,
      'net_balance', v_settlement.net_balance,
      'payment_reference', p_payment_reference
    )
  );

  RETURN jsonb_build_object('ok', true, 'settlement_id', p_settlement_id,
                            'new_status', p_new_status);
END;
$function$;

-- ═══ 7. Vista do PARCEIRO (read-only): semana atual ao vivo + histórico ═══
CREATE OR REPLACE FUNCTION public.partner_my_weekly_closeout(
  p_restaurant_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_current jsonb;
  v_history jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF NOT public._is_admin(v_caller) AND NOT EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = p_restaurant_id
        AND COALESCE(r.user_id, r.user_) = v_caller) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  v_current := public.compute_partner_weekly_settlement(p_restaurant_id, now(), false);

  SELECT jsonb_agg(jsonb_build_object(
    'week_start', s.week_start_at,
    'week_end', s.week_end_at,
    'total_orders', s.total_orders,
    'gross_sales', s.gross_sales,
    'commission_total', s.commission_total,
    'partner_share', s.partner_share,
    'cash_kept_by_partner', s.cash_kept_by_partner,
    'net_balance', s.net_balance,
    'direction', s.direction,
    'status', s.status,
    'paid_at', s.paid_at
  ) ORDER BY s.week_start_at DESC)
  INTO v_history
  FROM (SELECT * FROM public.partner_weekly_settlements
        WHERE partner_id = p_restaurant_id
        ORDER BY week_start_at DESC LIMIT 8) s;

  RETURN jsonb_build_object(
    'current_week', v_current,
    'history', COALESCE(v_history, '[]'::jsonb)
  );
END;
$function$;

-- ═══ 8. Fecho semanal COMPLETO (estafetas + parceiros) + notificação admin ═══
-- severity: admin_notifications só aceita low|medium|high|critical.
CREATE OR REPLACE FUNCTION public.run_weekly_closeout()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_drivers int := 0;
  v_partners int := 0;
  v_url text;
  v_key text;
  v_summary text;
BEGIN
  v_drivers  := public.close_previous_week_settlements();
  v_partners := public.close_partner_week_settlements();

  v_summary := format('📊 Fecho da semana pronto — %s estafeta(s) · %s parceiro(s). Abrir "Fechos semanais" para rever e pagar.',
                      v_drivers, v_partners);

  INSERT INTO public.admin_notifications (event_type, severity, entity_type, summary, deep_link, payload)
  VALUES ('weekly_closeout', 'medium', 'settlement', v_summary, '/admin/settlements',
          jsonb_build_object('drivers', v_drivers, 'partners', v_partners, 'ran_at', now()));

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
    IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type', 'application/json'),
        body    := jsonb_build_object(
          'kind', 'generic',
          'title', '📊 Fecho semanal pronto',
          'body', format('%s estafeta(s) · %s parceiro(s) — rever e pagar no painel.', v_drivers, v_partners),
          'route', '/admin/settlements',
          'ref', 'weekly_closeout')
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'run_weekly_closeout push error: %', SQLERRM;
  END;

  RETURN jsonb_build_object('drivers', v_drivers, 'partners', v_partners);
END;
$function$;

-- ═══ 9. Totais da Bora na semana (ecrã admin "Fechos semanais") ═══
CREATE OR REPLACE FUNCTION public.admin_weekly_bora_totals(
  p_week_start timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_bounds RECORD;
  v_orders_count int := 0;
  v_orders_revenue numeric := 0;
  v_platform_commissions numeric := 0;
  v_service_fees numeric := 0;
  v_delivery_fees numeric := 0;
  v_bag_fees numeric := 0;
  v_appt_deposits numeric := 0;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_bounds FROM public.driver_settlement_week_bounds(
    COALESCE(p_week_start, now())
  );

  SELECT COUNT(*),
         COALESCE(SUM(COALESCE(final_total, total, price, 0)), 0),
         COALESCE(SUM(COALESCE(service_fee, 0)), 0),
         COALESCE(SUM(COALESCE(delivery_fee, 0)), 0),
         COALESCE(SUM(COALESCE(bag_fee, 0)), 0)
  INTO v_orders_count, v_orders_revenue, v_service_fees, v_delivery_fees, v_bag_fees
  FROM public.orders
  WHERE status = 'delivered'
    AND delivered_at >= v_bounds.week_start
    AND delivered_at <= v_bounds.week_end;

  SELECT COALESCE(SUM(amount), 0) INTO v_platform_commissions
  FROM public.ledger_entries
  WHERE user_type = 'platform' AND type = 'commission'
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  SELECT COALESCE(SUM(deposit_cents), 0) / 100.0 INTO v_appt_deposits
  FROM public.appointments
  WHERE deposit_status IN ('paid', 'retained')
    AND created_at >= v_bounds.week_start
    AND created_at <= v_bounds.week_end;

  RETURN jsonb_build_object(
    'week_start', v_bounds.week_start,
    'week_end', v_bounds.week_end,
    'orders_count', v_orders_count,
    'orders_revenue', v_orders_revenue,
    'platform_commissions', v_platform_commissions,
    'service_fees', v_service_fees,
    'delivery_fees', v_delivery_fees,
    'bag_fees', v_bag_fees,
    'appointment_deposits', v_appt_deposits
  );
END;
$function$;

-- ═══ 10. Grants (REVOKE PUBLIC + explícitos — padrão DNA) ═══
REVOKE ALL ON FUNCTION public.compute_partner_weekly_settlement(text, timestamptz, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_partner_weekly_settlement(text, timestamptz, boolean) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.close_partner_week_settlements(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_partner_week_settlements(timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.admin_list_partner_settlements_for_week(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_partner_settlements_for_week(timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_partner_settlement_status(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_partner_settlement_status(uuid, text, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.partner_my_weekly_closeout(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.partner_my_weekly_closeout(text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.run_weekly_closeout() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.run_weekly_closeout() TO service_role;
REVOKE ALL ON FUNCTION public.admin_weekly_bora_totals(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_weekly_bora_totals(timestamptz) TO authenticated, service_role;

-- ═══ 11. Cron: o fecho de segunda 00:05 passa a fechar TUDO + notificar ═══
SELECT cron.schedule('close-weekly-settlements', '5 0 * * 1',
                     'SELECT public.run_weekly_closeout();');
