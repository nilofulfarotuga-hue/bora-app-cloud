CREATE OR REPLACE FUNCTION public.admin_list_partner_settlements_for_week(p_week_start timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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

  -- Garante settlements atualizados para a semana pedida (idempotente;
  -- não toca em fechos já paid/received).
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
    'pago_em_mao_na_recolha', s.pago_em_mao_na_recolha, -- 10/11/2026 pagar-na-loja
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
$function$
