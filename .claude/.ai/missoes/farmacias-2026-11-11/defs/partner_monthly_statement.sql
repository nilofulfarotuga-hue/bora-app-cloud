CREATE OR REPLACE FUNCTION public.partner_monthly_statement(p_partner_id text, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini timestamptz; v_fim timestamptz; r record;
  v_linhas jsonb; v_tot jsonb; v_acertos jsonb; v_pago numeric; v_parte numeric;
BEGIN
  SELECT * INTO r FROM public.restaurants WHERE id = p_partner_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'parceiro_nao_encontrado'; END IF;
  IF NOT (public.is_admin()
          OR coalesce(auth.jwt()->>'role','') = 'service_role'
          OR (auth.uid() IS NOT NULL AND (r.user_id = auth.uid() OR r.user_::text = auth.uid()::text))) THEN
    RAISE EXCEPTION 'sem_permissao';
  END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);

  WITH f AS (
    SELECT x.*, CASE WHEN public.pedido_parceiro_chamou(o2.is_partner_store, o2.order_type, o2.user_id) THEN ROUND(x.custo + COALESCE(o2.partner_commission_visible, 0), 2) ELSE public._parceiro_vendas_loja(x.custo, p_partner_id) END AS vendas_loja
      FROM public._fecho_pedidos(v_ini, v_fim) x LEFT JOIN public.orders o2 ON o2.id = x.order_id
     WHERE x.restaurant_id = p_partner_id AND x.is_partner
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'order_id', f.order_id,
           'numero', upper(left(f.order_id, 8)),
           'data', to_char(f.delivered_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI'),
           'subtotal', f.vendas_loja,
           'comissao', ROUND(f.vendas_loja - f.custo, 2),
           'recebeu', f.custo,
           'pagamento', f.payment_method) ORDER BY f.delivered_at), '[]'::jsonb),
         jsonb_build_object('pedidos', count(*), 'vendas', coalesce(sum(f.vendas_loja),0),
                            'comissao', coalesce(sum(ROUND(f.vendas_loja - f.custo, 2)),0),
                            'parte_loja', coalesce(sum(f.custo),0))
    INTO v_linhas, v_tot
    FROM f;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'semana', to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '–' ||
                     to_char(s.week_end_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM'),
           'pedidos', s.total_orders, 'valor', s.partner_share, 'saldo', s.net_balance,
           'sentido', s.direction, 'estado', s.status,
           'pago_em', to_char(s.paid_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY'))
           ORDER BY s.week_start_at), '[]'::jsonb),
         coalesce(sum(s.partner_share) FILTER (WHERE s.status = 'paid'), 0)
    INTO v_acertos, v_pago
    FROM public.partner_weekly_settlements s
   WHERE s.partner_id = p_partner_id AND s.week_end_at >= v_ini AND s.week_end_at < v_fim;

  v_parte := (v_tot->>'parte_loja')::numeric;
  RETURN jsonb_build_object(
    'parceiro', jsonb_build_object('id', r.id, 'nome', r.name, 'nif', r.nif, 'email', r.email),
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month,
                                  'nome', (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                                                 'agosto','setembro','outubro','novembro','dezembro'])[p_month]),
    'pedidos', v_linhas,
    'totais', v_tot,
    'acertos_semanais', v_acertos,
    'total_pago_no_mes', v_pago,
    'saldo', v_parte - v_pago,
    'gerado_em', now());
END;
$function$
;
