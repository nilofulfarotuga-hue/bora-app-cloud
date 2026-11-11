CREATE OR REPLACE FUNCTION public.partner_my_weekly_closeout(p_restaurant_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_current jsonb;
  v_history jsonb;
  v_share numeric;
  v_vendas numeric;
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
  IF v_current ? 'partner_share' THEN
    v_share := COALESCE((v_current->>'partner_share')::numeric, 0);
    v_vendas := public._parceiro_vendas_semana(v_share, p_restaurant_id, (v_current->>'week_start')::timestamptz, (v_current->>'week_end')::timestamptz);
    v_current := v_current || jsonb_build_object('gross_sales', v_vendas,
                                                 'commission_total', ROUND(v_vendas - v_share, 2));
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'week_start', s.week_start_at,
    'week_end', s.week_end_at,
    'total_orders', s.total_orders,
    'gross_sales', public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at),
    'commission_total', ROUND(public._parceiro_vendas_semana(COALESCE(s.partner_share, 0), p_restaurant_id, s.week_start_at, s.week_end_at) - COALESCE(s.partner_share, 0), 2),
    'partner_share', s.partner_share,
    'cash_kept_by_partner', s.cash_kept_by_partner,
    'pago_em_mao_na_recolha', s.pago_em_mao_na_recolha,
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
$function$
;
