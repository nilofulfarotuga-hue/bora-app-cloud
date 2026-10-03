-- Fecho mensal (missão fecho-mensal-2026-09, 29/09/2026).
--
-- B1 admin_monthly_closeout(ano, mes)   — o mês inteiro, só leitura, só admin.
-- B2 partner_monthly_statement(id, ano, mes) — extrato mensal de UMA loja parceira.
-- B3 monthly_statement_log + admin_resend_monthly_statement — registo do email mensal.
--
-- Nada aqui escreve em orders, ledger, wallets, tokens ou acertos: só lê.
-- TVDE fica de fora (só entregas + serviços), excepto a linha à parte "parte da Bora
-- nas corridas TVDE de outros motoristas" (acrescento do Danilo, 29/09 22:20).
--
-- Custo da mercadoria, por pedido (regra verificada contra os números de setembro):
--   loja parceira  -> ledger_entries user_type='restaurant' type='earning' (a parte da loja)
--   não-parceiro   -> order_receipts_v2.driver_typed_total_cents (o TALÃO)
--   sem talão      -> subtotal / 1,15 (preço de catálogo sem os 15%), marcado 'estimado'
-- orders.final_purchase_value NÃO é o talão (é o valor de venda com margem) — não se usa.
-- Pago pelo cliente = orders.final_total.

CREATE OR REPLACE FUNCTION public._fecho_pedidos(p_ini timestamptz, p_fim timestamptz)
RETURNS TABLE (
  order_id text, delivered_at timestamptz, restaurant_id text, vendor_name text,
  is_partner boolean, service_type text, payment_method text, driver_user_id text,
  pago numeric, subtotal numeric, taxas numeric, delivery_fee numeric, service_fee numeric,
  bag_fee numeric, small_order_fee numeric, custo numeric, custo_fonte text, talao numeric,
  estafeta numeric, receita numeric, lucro numeric, comissao_margem numeric,
  cash_em_mao numeric, stripe_charge_cents integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH o AS (
    SELECT o.*,
           (SELECT sum(l.amount) FROM public.ledger_entries l
             WHERE l.order_id::text = o.id AND l.user_type = 'restaurant' AND l.type = 'earning') AS parte_loja,
           (SELECT max(r.driver_typed_total_cents) FROM public.order_receipts_v2 r
             WHERE r.order_id = o.id)::numeric / 100 AS talao_eur
      FROM public.orders o
     WHERE o.status = 'delivered'
       AND coalesce(o.is_test_order, false) = false
       AND o.delivered_at >= p_ini AND o.delivered_at < p_fim
       AND coalesce(o.service_type, '') NOT ILIKE 'tvde%'),
  c AS (
    SELECT o.*,
           round(coalesce(o.final_total, o.customer_total, o.total, 0), 2) AS v_pago,
           round(coalesce(o.delivery_fee,0) + coalesce(o.service_fee,0)
                 + coalesce(o.bag_fee,0) + coalesce(o.small_order_fee,0), 2) AS v_taxas,
           CASE
             WHEN o.parte_loja IS NOT NULL THEN round(o.parte_loja, 2)
             WHEN coalesce(o.is_partner_store,false) THEN
               round(coalesce(o.subtotal,0) - coalesce(o.partner_commission_visible,0)
                     - coalesce(o.partner_markup_hidden,0), 2)
             WHEN o.talao_eur IS NOT NULL THEN round(o.talao_eur, 2)
             ELSE round(coalesce(o.subtotal,0) / 1.15, 2)
           END AS v_custo,
           CASE
             WHEN o.parte_loja IS NOT NULL THEN 'parceiro'
             WHEN coalesce(o.is_partner_store,false) THEN 'parceiro_estimado'
             WHEN o.talao_eur IS NOT NULL THEN 'talao'
             ELSE 'estimado'
           END AS v_fonte
      FROM o)
  SELECT c.id, c.delivered_at, c.restaurant_id, c.vendor_name,
         coalesce(c.is_partner_store,false), c.service_type, coalesce(c.payment_method,'cash'),
         c.assigned_driver_id,
         c.v_pago, round(coalesce(c.subtotal,0),2), c.v_taxas,
         round(coalesce(c.delivery_fee,0),2), round(coalesce(c.service_fee,0),2),
         round(coalesce(c.bag_fee,0),2), round(coalesce(c.small_order_fee,0),2),
         c.v_custo, c.v_fonte, round(c.talao_eur,2),
         round(coalesce(c.driver_earnings,0),2),
         c.v_pago - c.v_custo,
         c.v_pago - c.v_custo - round(coalesce(c.driver_earnings,0),2),
         -- Comissão da loja parceira = subtotal − parte da loja (é o que se fatura
         -- à loja: Goola 8,76 € e Sabores 5,05 € em setembro). Não-parceiro:
         -- margem = pago − taxas − custo.
         CASE WHEN coalesce(c.is_partner_store,false)
              THEN round(coalesce(c.subtotal,0),2) - c.v_custo
              ELSE c.v_pago - c.v_taxas - c.v_custo END,
         CASE WHEN coalesce(c.payment_method,'cash') = 'cash'
              THEN round(coalesce(c.cash_total_due, c.final_total, 0), 2) ELSE 0 END,
         coalesce(c.stripe_charge_cents, 0)
    FROM c;
$$;
REVOKE ALL ON FUNCTION public._fecho_pedidos(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

-- Limites do mês em hora de Lisboa.
CREATE OR REPLACE FUNCTION public._fecho_limites(p_ano int, p_mes int)
RETURNS TABLE (ini timestamptz, fim timestamptz)
LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $$
  SELECT make_timestamptz(p_ano, p_mes, 1, 0, 0, 0, 'Europe/Lisbon'),
         make_timestamptz(p_ano, p_mes, 1, 0, 0, 0, 'Europe/Lisbon') + interval '1 month';
$$;

-- Estimativa da Stripe (cartões EEE): 1,5% + 0,25 €. Bate com a taxa real
-- cobrada no corte da barbearia de setembro (12,00 € -> 0,43 €).
CREATE OR REPLACE FUNCTION public._fecho_stripe_estimado(p_cents integer)
RETURNS numeric LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN coalesce(p_cents,0) > 0
                  THEN round((p_cents * 0.015 + 25) / 100.0, 2) ELSE 0 END $$;

-- =====================================================================
-- B1 — admin_monthly_closeout
-- =====================================================================
CREATE OR REPLACE FUNCTION public.admin_monthly_closeout(p_year int, p_month int)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_ini timestamptz; v_fim timestamptz;
  v_tot jsonb; v_metodo jsonb; v_parc jsonb; v_serv jsonb; v_serv_tot jsonb;
  v_est jsonb; v_prej jsonb; v_rub jsonb; v_mand jsonb; v_texto text;
  v_receita numeric; v_nome_mes text;
  v_fat jsonb; v_fat_parc numeric; v_tvde numeric; v_tvde_n int;
BEGIN
  IF NOT (public.is_admin() OR coalesce(auth.jwt()->>'role','') = 'service_role') THEN
    RAISE EXCEPTION 'admin_required';
  END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);
  v_nome_mes := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                       'agosto','setembro','outubro','novembro','dezembro'])[p_month];

  CREATE TEMP TABLE IF NOT EXISTS _fm ON COMMIT DROP AS
    SELECT * FROM public._fecho_pedidos(v_ini, v_fim) WITH NO DATA;
  TRUNCATE _fm;
  INSERT INTO _fm SELECT * FROM public._fecho_pedidos(v_ini, v_fim);

  SELECT jsonb_build_object(
    'pedidos_entregues', count(*),
    'pago_pelos_clientes', coalesce(sum(pago),0),
    'custo_mercadoria', coalesce(sum(custo),0),
    'receita_propria_bora', coalesce(sum(receita),0),
    'pago_a_estafetas', coalesce(sum(estafeta),0),
    'lucro', coalesce(sum(lucro),0),
    'pedidos_com_custo_estimado', count(*) FILTER (WHERE custo_fonte IN ('estimado','parceiro_estimado')),
    'stripe_estimado', coalesce(sum(public._fecho_stripe_estimado(stripe_charge_cents)),0))
    INTO v_tot FROM _fm;
  v_receita := (v_tot->>'receita_propria_bora')::numeric;

  SELECT coalesce(jsonb_object_agg(payment_method, x), '{}'::jsonb) INTO v_metodo FROM (
    SELECT payment_method, jsonb_build_object(
             'pedidos', count(*), 'pago', sum(pago),
             'cobrado_pela_stripe', round(sum(stripe_charge_cents)/100.0, 2),
             'stripe_estimado', sum(public._fecho_stripe_estimado(stripe_charge_cents))) x
      FROM _fm GROUP BY payment_method) s;

  -- Lojas parceiras: vendas brutas = subtotal; comissão total = subtotal − parte da loja.
  WITH p AS (
    SELECT restaurant_id, max(vendor_name) nome, count(*) n,
           sum(subtotal) vendas, sum(comissao_margem) comissao, sum(custo) parte
      FROM _fm WHERE is_partner GROUP BY restaurant_id),
  s AS (
    SELECT s.partner_id,
           sum(s.partner_share) FILTER (WHERE s.status = 'paid') pago,
           jsonb_agg(jsonb_build_object('semana_inicio', (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date,
                                        'semana_fim', (s.week_end_at AT TIME ZONE 'Europe/Lisbon')::date,
                                        'parte_loja', s.partner_share, 'estado', s.status,
                                        'pago_em', s.paid_at) ORDER BY s.week_start_at) acertos
      FROM public.partner_weekly_settlements s
     WHERE s.week_end_at >= v_ini AND s.week_end_at < v_fim
     GROUP BY s.partner_id)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'partner_id', coalesce(p.restaurant_id, s.partner_id),
           'nome', coalesce(r.name, p.nome),
           'email', r.email,
           'pedidos', coalesce(p.n,0), 'vendas_brutas', coalesce(p.vendas,0),
           'comissao_total', coalesce(p.comissao,0), 'parte_loja', coalesce(p.parte,0),
           'pago_no_mes', coalesce(s.pago,0),
           'pendente', greatest(coalesce(p.parte,0) - coalesce(s.pago,0), 0),
           'acertos', coalesce(s.acertos,'[]'::jsonb),
           'extrato', (SELECT jsonb_build_object('estado', l.email_status, 'enviado_em', l.sent_at, 'erro', l.email_error)
                         FROM public.monthly_statement_log l
                        WHERE l.partner_id = coalesce(p.restaurant_id, s.partner_id)
                          AND l.ano = p_year AND l.mes = p_month))
         ORDER BY coalesce(r.name, p.nome)), '[]'::jsonb)
    INTO v_parc
    FROM p FULL JOIN s ON s.partner_id = p.restaurant_id
    LEFT JOIN public.restaurants r ON r.id = coalesce(p.restaurant_id, s.partner_id);

  -- Serviços (barbearias/salões): o acerto semanal já traz tudo.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'provider_id', a.provider_id, 'nome', sp.name,
           'marcacoes', a.total_appointments,
           'pago_pelos_clientes', round(a.total_service_revenue_cents/100.0,2),
           'taxa_stripe', round(a.bora_booking_fees_cents/100.0,2),
           'bora_reteve', round(a.bora_deposit_cut_cents/100.0,2),
           'liquido_prestador', round(a.net_payout_cents/100.0,2),
           'estado', a.status, 'pago_em', a.paid_at) ORDER BY a.week_start_at), '[]'::jsonb),
         jsonb_build_object(
           'marcacoes', coalesce(sum(a.total_appointments),0),
           'pago_pelos_clientes', coalesce(round(sum(a.total_service_revenue_cents)/100.0,2),0),
           'taxa_stripe', coalesce(round(sum(a.bora_booking_fees_cents)/100.0,2),0),
           'bora_reteve', coalesce(round(sum(a.bora_deposit_cut_cents)/100.0,2),0),
           'pago_prestadores', coalesce(round(sum(a.net_payout_cents) FILTER (WHERE a.status='paid')/100.0,2),0),
           'pendente_prestadores', coalesce(round(sum(a.net_payout_cents) FILTER (WHERE a.status<>'paid')/100.0,2),0))
    INTO v_serv, v_serv_tot
    FROM public.appointment_payouts a
    LEFT JOIN public.service_providers sp ON sp.id::text = a.provider_id
   WHERE a.week_end_at >= v_ini AND a.week_end_at < v_fim;

  -- Estafetas (identidade = user_id, a mesma que assigned_driver_id).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_user_id, 'nome', d.name, 'entregas', x.n, 'ganho', x.ganho,
           'dinheiro_recebido_em_mao', x.cash, 'taloes_adiantados', x.taloes)
         ORDER BY x.ganho DESC), '[]'::jsonb)
    INTO v_est
    FROM (SELECT driver_user_id, count(*) n, sum(estafeta) ganho, sum(cash_em_mao) cash,
                 coalesce(sum(talao),0) taloes
            FROM _fm GROUP BY driver_user_id) x
    LEFT JOIN public.drivers d ON d.user_id::text = x.driver_user_id;

  -- Pedidos no prejuízo (pago − mercadoria − estafeta ≤ 0).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'order_id', order_id, 'loja', vendor_name,
           'data', (delivered_at AT TIME ZONE 'Europe/Lisbon')::date,
           'pago', pago, 'mercadoria', custo, 'estafeta', estafeta, 'resultado', lucro,
           'motivo', CASE
             WHEN custo_fonte = 'estimado' THEN 'sem talão (custo estimado = catálogo sem os 15%)'
             WHEN custo_fonte = 'talao' AND (talao > subtotal * 1.5 OR talao < subtotal * 0.5)
               THEN 'talão provavelmente mal escrito'
             WHEN custo_fonte = 'talao' AND talao > round(subtotal / 1.15, 2)
               THEN 'talão acima do catálogo'
             ELSE 'taxas do pedido não cobrem o estafeta' END)
         ORDER BY lucro), '[]'::jsonb)
    INTO v_prej FROM _fm WHERE lucro <= 0;

  -- Receita própria por rubrica (para o recibo verde). A soma bate com a receita:
  -- o que sobra (descontos de tokens/carteira pagos pela Bora, acertos do talão
  -- em pedidos de loja parceira) vai para 'ajustes_descontos'.
  SELECT jsonb_build_object(
    'entrega', coalesce(sum(delivery_fee),0),
    'taxa_servico', coalesce(sum(service_fee),0),
    'sacos', coalesce(sum(bag_fee),0),
    'taxa_pedido_pequeno', coalesce(sum(small_order_fee),0),
    'comissao_lojas_parceiras', coalesce(sum(comissao_margem) FILTER (WHERE is_partner),0),
    'margem_nao_parceiros', coalesce(sum(comissao_margem) FILTER (WHERE NOT is_partner),0),
    'ajustes_descontos', coalesce(sum(receita) - sum(delivery_fee) - sum(service_fee) - sum(bag_fee)
                                  - sum(small_order_fee) - sum(comissao_margem),0))
    INTO v_rub FROM _fm;

  -- Faturas-recibo do mês (como as 4 de setembro): uma por loja parceira com a
  -- comissão (com NIF), uma a consumidor final com o resto da receita de entregas.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'destinatario', r.name, 'nif', r.nif, 'partner_id', x.restaurant_id,
           'valor', x.comissao, 'descricao', 'Comissão de intermediação — pedidos pela plataforma Bora',
           'falta_nif', r.nif IS NULL OR r.nif = '') ORDER BY r.name), '[]'::jsonb),
         coalesce(sum(x.comissao),0)
    INTO v_fat, v_fat_parc
    FROM (SELECT restaurant_id, sum(comissao_margem) comissao FROM _fm WHERE is_partner GROUP BY restaurant_id) x
    LEFT JOIN public.restaurants r ON r.id = x.restaurant_id;

  -- TVDE dos OUTROS motoristas: parte da Bora (bora_cut_cents) das corridas
  -- finalizadas no mês. Ficam fora as corridas do próprio Danilo
  -- (platform_settings.fecho_tvde_excluir_emails) e as contas de teste.
  SELECT coalesce(round(sum(t.bora_cut_cents)/100.0, 2), 0), count(*)
    INTO v_tvde, v_tvde_n
    FROM public.tvde_rides t
    LEFT JOIN auth.users u ON u.id = t.driver_id
   WHERE t.status = 'finalizada'
     AND t.created_at >= v_ini AND t.created_at < v_fim
     AND lower(coalesce(u.email,'')) NOT IN (
           SELECT lower(e) FROM jsonb_array_elements_text(coalesce(
             (SELECT value FROM public.platform_settings WHERE key = 'fecho_tvde_excluir_emails'),
             '[]'::jsonb)) e)
     AND coalesce(u.email,'') NOT ILIKE '%.test'
     AND NOT coalesce(public.is_demo_email(u.email), false);

  -- Modelo a partir de 01/10/2026: a entrega pertence ao estafeta, a Bora cobra
  -- por conta dele. Separa o que é receita Bora do que é cobrado por conta de terceiros.
  SELECT jsonb_build_object(
    'receita_bora', coalesce(sum(lucro),0),
    'receita_bora_rubricas', jsonb_build_object(
       'taxa_servico', coalesce(sum(service_fee),0), 'sacos', coalesce(sum(bag_fee),0),
       'taxa_pedido_pequeno', coalesce(sum(small_order_fee),0),
       'comissao_lojas_parceiras', coalesce(sum(comissao_margem) FILTER (WHERE is_partner),0),
       'margem_nao_parceiros', coalesce(sum(comissao_margem) FILTER (WHERE NOT is_partner),0),
       'entrega_menos_ganho_estafeta', coalesce(sum(delivery_fee - estafeta),0),
       'ajustes_descontos', coalesce((v_rub->>'ajustes_descontos')::numeric,0)),
    'cobrado_por_conta_de_terceiros', jsonb_build_object(
       'estafetas', coalesce(sum(estafeta),0),
       'lojas_parceiras', coalesce(sum(custo) FILTER (WHERE is_partner),0),
       'mercadoria_nao_parceiros', coalesce(sum(custo) FILTER (WHERE NOT is_partner),0)),
    'nota', 'Em vigor a partir de 01/10/2026. Até 30/09 a receita declarada é a receita_propria_bora.')
    INTO v_mand FROM _fm;

  v_fat := v_fat || jsonb_build_array(
    jsonb_build_object('destinatario', 'Consumidor final', 'nif', NULL,
                       'valor', v_receita - v_fat_parc,
                       'descricao', 'Serviços de entrega e intermediação — plataforma Bora (' || v_nome_mes || ' ' || p_year || ')'),
    jsonb_build_object('destinatario', 'Consumidor final', 'nif', NULL, 'valor', v_tvde,
                       'descricao', 'Parte da Bora nas corridas TVDE de outros motoristas (' || v_nome_mes || ' ' || p_year || ')'));

  v_texto := format(
    'Receita própria da Bora em %s de %s: %s € nas entregas, mais %s € de parte da Bora nas corridas '
    'TVDE de outros motoristas (%s corridas; as do próprio Danilo e as de teste ficam fora). '
    'Entregas por rubrica: entrega %s €, taxa de serviço %s €, sacos %s €, taxa de pedido pequeno %s €, '
    'comissões de lojas parceiras %s €, margem sobre compras em lojas não parceiras %s €, ajustes e descontos %s €. '
    'Não inclui o valor da mercadoria (%s €), que pertence às lojas. Serviços (marcações): a Bora reteve %s €. '
    'Faturas-recibo a emitir: uma por loja parceira com a comissão (%s €) e o resto a consumidor final (%s € entregas + %s € TVDE). '
    'Regime simplificado, IVA isento ao abrigo do art. 53.º do CIVA (M10).',
    v_nome_mes, p_year, to_char(v_receita, 'FM999990.00'), to_char(v_tvde, 'FM999990.00'), v_tvde_n,
    to_char((v_rub->>'entrega')::numeric, 'FM999990.00'),
    to_char((v_rub->>'taxa_servico')::numeric, 'FM999990.00'),
    to_char((v_rub->>'sacos')::numeric, 'FM999990.00'),
    to_char((v_rub->>'taxa_pedido_pequeno')::numeric, 'FM999990.00'),
    to_char((v_rub->>'comissao_lojas_parceiras')::numeric, 'FM999990.00'),
    to_char((v_rub->>'margem_nao_parceiros')::numeric, 'FM999990.00'),
    to_char((v_rub->>'ajustes_descontos')::numeric, 'FM999990.00'),
    to_char((v_tot->>'custo_mercadoria')::numeric, 'FM999990.00'),
    to_char(coalesce((v_serv_tot->>'bora_reteve')::numeric,0), 'FM999990.00'),
    to_char(v_fat_parc, 'FM999990.00'), to_char(v_receita - v_fat_parc, 'FM999990.00'),
    to_char(v_tvde, 'FM999990.00'));

  RETURN jsonb_build_object(
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month, 'nome', v_nome_mes,
                                  'inicio', v_ini, 'fim', v_fim, 'fuso', 'Europe/Lisbon',
                                  'tvde', 'excluído'),
    'totais', v_tot || jsonb_build_object('por_metodo', v_metodo),
    'servicos_totais', v_serv_tot,
    'parceiros', v_parc,
    'servicos', v_serv,
    'estafetas', v_est,
    'pedidos_no_prejuizo', v_prej,
    'modelo_a_partir_de_2026_10', v_mand,
    'tvde_outros_motoristas', jsonb_build_object(
       'parte_bora', v_tvde, 'corridas', v_tvde_n,
       'nota', 'Soma de tvde_rides.bora_cut_cents (finalizada). Fora: corridas do próprio Danilo e contas de teste.'),
    'para_as_financas', jsonb_build_object(
       'regime', 'simplificado; IVA isento art. 53.º CIVA (M10)',
       'receita_propria', v_receita, 'rubricas', v_rub,
       'receita_servicos', coalesce((v_serv_tot->>'bora_reteve')::numeric,0),
       'parte_bora_tvde_outros', v_tvde,
       'total_a_declarar', v_receita + v_tvde + coalesce((v_serv_tot->>'bora_reteve')::numeric,0),
       'faturas_recibo', v_fat,
       'texto', v_texto),
    'regra_custo', 'parceiro=ledger earning; não-parceiro=talão (order_receipts_v2); sem talão=subtotal/1,15',
    'gerado_em', now());
END;
$$;
REVOKE ALL ON FUNCTION public.admin_monthly_closeout(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_monthly_closeout(int, int) TO authenticated, service_role;

-- =====================================================================
-- B3 — registo do email mensal (idempotência)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.monthly_statement_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id text NOT NULL,
  ano int NOT NULL,
  mes int NOT NULL CHECK (mes BETWEEN 1 AND 12),
  email_to text,
  email_status text NOT NULL DEFAULT 'pending',
  email_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (partner_id, ano, mes));
ALTER TABLE public.monthly_statement_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS monthly_statement_log_admin_read ON public.monthly_statement_log;
CREATE POLICY monthly_statement_log_admin_read ON public.monthly_statement_log
  FOR SELECT TO authenticated USING (public.is_admin());

-- =====================================================================
-- B2 — partner_monthly_statement
-- =====================================================================
CREATE OR REPLACE FUNCTION public.partner_monthly_statement(p_partner_id text, p_year int, p_month int)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
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

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'order_id', f.order_id,
           'numero', upper(left(f.order_id, 8)),
           'data', to_char(f.delivered_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI'),
           'subtotal', f.subtotal,
           'comissao', f.comissao_margem,
           'recebeu', f.custo,
           'pagamento', f.payment_method) ORDER BY f.delivered_at), '[]'::jsonb),
         jsonb_build_object('pedidos', count(*), 'vendas', coalesce(sum(f.subtotal),0),
                            'comissao', coalesce(sum(f.comissao_margem),0),
                            'parte_loja', coalesce(sum(f.custo),0))
    INTO v_linhas, v_tot
    FROM public._fecho_pedidos(v_ini, v_fim) f
   WHERE f.restaurant_id = p_partner_id AND f.is_partner;

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
$$;
REVOKE ALL ON FUNCTION public.partner_monthly_statement(text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_monthly_statement(text, int, int) TO authenticated, service_role;

-- Lista de parceiros com pedidos no mês (a Edge Function usa-a para saber a quem mandar).
CREATE OR REPLACE FUNCTION public.monthly_statement_recipients(p_year int, p_month int)
RETURNS TABLE (partner_id text, nome text, email text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT DISTINCT f.restaurant_id, r.name, r.email
    FROM public._fecho_limites(p_year, p_month) l,
         LATERAL public._fecho_pedidos(l.ini, l.fim) f
    JOIN public.restaurants r ON r.id = f.restaurant_id
   WHERE f.is_partner;
$$;
REVOKE ALL ON FUNCTION public.monthly_statement_recipients(int, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.monthly_statement_recipients(int, int) TO service_role;

-- Botão "Reenviar extrato do mês" do painel (force:true), igual ao do fecho semanal.
CREATE OR REPLACE FUNCTION public.admin_resend_monthly_statement(p_year int, p_month int, p_partner_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_req bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url') || '/functions/v1/monthly-partner-statement',
    headers := jsonb_build_object('Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
                                  'Content-Type', 'application/json'),
    body := jsonb_build_object('year', p_year, 'month', p_month, 'partner_id', p_partner_id,
                               'force', true, 'admin_summary', p_partner_id IS NULL)
  ) INTO v_req;
  PERFORM public.log_admin_action('resend_monthly_statement', 'monthly_statement',
                                  p_year || '-' || p_month || coalesce(':' || p_partner_id, ''),
                                  jsonb_build_object('request_id', v_req, 'force', true));
  RETURN jsonb_build_object('ok', true, 'request_id', v_req);
END $$;
REVOKE ALL ON FUNCTION public.admin_resend_monthly_statement(int, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_resend_monthly_statement(int, int, text) TO authenticated;

-- Quem fica fora da linha "TVDE de outros motoristas": as corridas do próprio Danilo.
INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('fecho_tvde_excluir_emails', '["boraappbora@gmail.com"]'::jsonb,
        'Fecho mensal: emails de motorista cujas corridas TVDE NÃO entram na parte da Bora (o próprio Danilo).',
        'fecho')
ON CONFLICT (key) DO NOTHING;
