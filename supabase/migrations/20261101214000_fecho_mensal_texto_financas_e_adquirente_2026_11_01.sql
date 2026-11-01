-- 01/11/2026 (missão contabilista-2026-11-01, autorizado pelo Danilo 01/11: "ver tudinho o que está
-- faltando para o mês que vem não dar erro") — TEXTO DO FECHO PARA AS FINANÇAS E ADQUIRENTE DO RECIBO.
--
-- 1) admin_monthly_closeout(ano, mes):
--    • o TVDE de passageiros sai da "receita a declarar" e das faturas-recibo (regra do Danilo: fica fora
--      da declaração da Bora); continua a aparecer como informativo em tvde_outros_motoristas;
--    • entra a taxa da Bora nas limpezas (cleaning_bookings completed/done, sem testes) — era esquecida;
--    • a frase do IVA depende de platform_settings.fecho_entidade_tipo: 'individual' → isenção art. 53.º
--      (M10); 'sociedade' → regime normal, IVA 23% incluído. Já não diz "até outubro/a partir de novembro".
-- 2) driver_monthly_invoice_summary(ano, mes): o adquirente do recibo verde deixa de ser "Consumidor
--    final"/NIPC fixo. Até outubro/2026: o Danilo em nome individual (platform_settings fecho_entidade_*).
--    De novembro/2026 em diante: a sociedade Danilo Fulfaro da Silva - Unipessoal Lda (NIF 519686233),
--    porque a empresa começa a cobrar em novembro. Devolve também cliente_morada, cliente_tipo, retencao.
-- Só textos e composição do resumo: nenhum valor cobrado ou pago muda.

CREATE OR REPLACE FUNCTION public.admin_monthly_closeout(p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini timestamptz; v_fim timestamptz;
  v_tot jsonb; v_metodo jsonb; v_parc jsonb; v_serv jsonb; v_serv_tot jsonb;
  v_est jsonb; v_prej jsonb; v_rub jsonb; v_mand jsonb; v_texto text;
  v_receita numeric; v_nome_mes text;
  v_fat jsonb; v_fat_parc numeric; v_tvde numeric; v_tvde_n int;
  v_limp_n int; v_limp_pago numeric; v_limp_prest numeric; v_limp_bora numeric;
  v_ent_tipo text; v_ent_nome text; v_ent_nif text; v_iva_txt text; v_regime text;
BEGIN
  IF NOT (public.is_admin() OR coalesce(auth.jwt()->>'role','') = 'service_role') THEN
    RAISE EXCEPTION 'admin_required';
  END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);
  v_nome_mes := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                       'agosto','setembro','outubro','novembro','dezembro'])[p_month];

  v_ent_tipo := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_tipo'), 'individual');
  v_ent_nome := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nome'), '');
  v_ent_nif  := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nif'), '');
  IF v_ent_tipo = 'sociedade' THEN
    v_regime := 'sociedade; IVA regime normal (trimestral), 23% incluído nas faturas da Bora';
    v_iva_txt := 'IVA: regime normal (trimestral), com IVA 23% incluído nas faturas da Bora.';
  ELSE
    v_regime := 'nome individual, regime simplificado; IVA isento art. 53.º CIVA (M10)';
    v_iva_txt := 'IVA: isenção do art. 53.º do CIVA (M10), enquanto a cobrança for em nome individual.';
  END IF;

  -- (sem tabela temporária: _fecho_pedidos é chamada directamente em cada bloco; são poucas linhas por mês)

  SELECT jsonb_build_object(
    'pedidos_entregues', count(*),
    'pago_pelos_clientes', coalesce(sum(pago),0),
    'custo_mercadoria', coalesce(sum(custo),0),
    'receita_propria_bora', coalesce(sum(receita),0),
    'pago_a_estafetas', coalesce(sum(estafeta),0),
    'lucro', coalesce(sum(lucro),0),
    'pedidos_com_custo_estimado', count(*) FILTER (WHERE custo_fonte IN ('estimado','parceiro_estimado')),
    'stripe_estimado', coalesce(sum(public._fecho_stripe_estimado(stripe_charge_cents)),0))
    INTO v_tot FROM public._fecho_pedidos(v_ini, v_fim);
  v_receita := (v_tot->>'receita_propria_bora')::numeric;

  SELECT coalesce(jsonb_object_agg(payment_method, x), '{}'::jsonb) INTO v_metodo FROM (
    SELECT payment_method, jsonb_build_object(
             'pedidos', count(*), 'pago', sum(pago),
             'cobrado_pela_stripe', round(sum(stripe_charge_cents)/100.0, 2),
             'stripe_estimado', sum(public._fecho_stripe_estimado(stripe_charge_cents))) x
      FROM public._fecho_pedidos(v_ini, v_fim) GROUP BY payment_method) s;

  WITH p AS (
    SELECT restaurant_id, max(vendor_name) nome, count(*) n,
           sum(subtotal) vendas, sum(comissao_margem) comissao, sum(custo) parte
      FROM public._fecho_pedidos(v_ini, v_fim) WHERE is_partner GROUP BY restaurant_id),
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

  -- limpeza: taxa da Bora (receita própria) e o que os prestadores ganharam
  SELECT count(*), coalesce(round(sum(total_cents)/100.0,2),0), coalesce(round(sum(cleaner_earnings_cents)/100.0,2),0),
         coalesce(round(sum(bora_fee_cents)/100.0,2),0)
    INTO v_limp_n, v_limp_pago, v_limp_prest, v_limp_bora
    FROM public.cleaning_bookings
   WHERE status IN ('completed','done') AND coalesce(is_test_order,false) = false
     AND scheduled_at >= v_ini AND scheduled_at < v_fim;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_user_id, 'nome', d.name, 'entregas', x.n, 'ganho', x.ganho,
           'dinheiro_recebido_em_mao', x.cash, 'taloes_adiantados', x.taloes)
         ORDER BY x.ganho DESC), '[]'::jsonb)
    INTO v_est
    FROM (SELECT driver_user_id, count(*) n, sum(estafeta) ganho, sum(cash_em_mao) cash,
                 coalesce(sum(talao),0) taloes
            FROM public._fecho_pedidos(v_ini, v_fim) GROUP BY driver_user_id) x
    LEFT JOIN public.drivers d ON d.user_id::text = x.driver_user_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'order_id', order_id, 'loja', vendor_name,
           'data', (delivered_at AT TIME ZONE 'Europe/Lisbon')::date,
           'pago', pago, 'mercadoria', custo, 'estafeta', estafeta, 'resultado', lucro,
           'motivo', CASE
             WHEN custo_fonte = 'estimado' THEN 'sem talão (custo estimado = catálogo sem os 15%)'
             WHEN custo_fonte = 'talao' AND (talao > subtotal * 1.5 OR talao < subtotal * 0.5)
               THEN 'talão provavelmente mal escrito'
             WHEN custo_fonte = 'talao' AND talao > round(subtotal / public._mult_nao_parceiro(), 2)
               THEN 'talão acima do catálogo'
             ELSE 'taxas do pedido não cobrem o estafeta' END)
         ORDER BY lucro), '[]'::jsonb)
    INTO v_prej FROM public._fecho_pedidos(v_ini, v_fim) WHERE lucro <= 0;

  SELECT jsonb_build_object(
    'entrega', coalesce(sum(delivery_fee),0),
    'taxa_servico', coalesce(sum(service_fee),0),
    'sacos', coalesce(sum(bag_fee),0),
    'taxa_pedido_pequeno', coalesce(sum(small_order_fee),0),
    'comissao_lojas_parceiras', coalesce(sum(comissao_margem) FILTER (WHERE is_partner),0),
    'margem_nao_parceiros', coalesce(sum(comissao_margem) FILTER (WHERE NOT is_partner),0),
    'ajustes_descontos', coalesce(sum(receita) - sum(delivery_fee) - sum(service_fee) - sum(bag_fee)
                                  - sum(small_order_fee) - sum(comissao_margem),0))
    INTO v_rub FROM public._fecho_pedidos(v_ini, v_fim);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'destinatario', r.name, 'nif', r.nif, 'partner_id', x.restaurant_id,
           'valor', x.comissao, 'descricao', 'Comissão de intermediação — pedidos pela plataforma Bora',
           'falta_nif', r.nif IS NULL OR r.nif = '') ORDER BY r.name), '[]'::jsonb),
         coalesce(sum(x.comissao),0)
    INTO v_fat, v_fat_parc
    FROM (SELECT restaurant_id, sum(comissao_margem) comissao FROM public._fecho_pedidos(v_ini, v_fim) WHERE is_partner GROUP BY restaurant_id) x
    LEFT JOIN public.restaurants r ON r.id = x.restaurant_id;

  -- TVDE de outros motoristas: SÓ INFORMATIVO (fora da declaração da Bora)
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
    INTO v_mand FROM public._fecho_pedidos(v_ini, v_fim);

  v_fat := v_fat || jsonb_build_array(
    jsonb_build_object('destinatario', 'Consumidor final', 'nif', NULL,
                       'valor', v_receita - v_fat_parc,
                       'descricao', 'Serviços de entrega e intermediação — plataforma Bora (' || v_nome_mes || ' ' || p_year || ')'));
  IF v_limp_bora > 0 THEN
    v_fat := v_fat || jsonb_build_array(
      jsonb_build_object('destinatario', 'Consumidor final', 'nif', NULL, 'valor', v_limp_bora,
                         'descricao', 'Taxa de intermediação em serviços de limpeza — plataforma Bora (' || v_nome_mes || ' ' || p_year || ')'));
  END IF;

  v_texto := format(
    'Receita própria da Bora em %s de %s: %s € nas entregas e mercados, mais %s € de taxa da Bora nas limpezas (%s serviços; clientes pagaram %s €, prestadores %s €)%s. '
    'Entregas por rubrica: entrega %s €, taxa de serviço %s €, sacos %s €, taxa de pedido pequeno %s €, '
    'comissões de lojas parceiras %s €, margem sobre compras em lojas não parceiras %s €, ajustes e descontos %s €. '
    'Não inclui o valor da mercadoria (%s €), que pertence às lojas, nem o TVDE de passageiros (%s corridas de outros motoristas, parte Bora %s €), que por regra fica fora da declaração da Bora. '
    'Faturas-recibo a emitir: uma por loja parceira com a comissão (%s €) e o resto a consumidor final (%s € entregas%s). '
    'Entidade: %s (NIF %s). %s',
    v_nome_mes, p_year, to_char(v_receita, 'FM999990.00'),
    to_char(v_limp_bora, 'FM999990.00'), v_limp_n, to_char(v_limp_pago, 'FM999990.00'), to_char(v_limp_prest, 'FM999990.00'),
    CASE WHEN coalesce((v_serv_tot->>'bora_reteve')::numeric,0) > 0
         THEN format(', mais %s € retidos em marcações', to_char((v_serv_tot->>'bora_reteve')::numeric, 'FM999990.00')) ELSE '' END,
    to_char((v_rub->>'entrega')::numeric, 'FM999990.00'),
    to_char((v_rub->>'taxa_servico')::numeric, 'FM999990.00'),
    to_char((v_rub->>'sacos')::numeric, 'FM999990.00'),
    to_char((v_rub->>'taxa_pedido_pequeno')::numeric, 'FM999990.00'),
    to_char((v_rub->>'comissao_lojas_parceiras')::numeric, 'FM999990.00'),
    to_char((v_rub->>'margem_nao_parceiros')::numeric, 'FM999990.00'),
    to_char((v_rub->>'ajustes_descontos')::numeric, 'FM999990.00'),
    to_char((v_tot->>'custo_mercadoria')::numeric, 'FM999990.00'),
    v_tvde_n, to_char(v_tvde, 'FM999990.00'),
    to_char(v_fat_parc, 'FM999990.00'), to_char(v_receita - v_fat_parc, 'FM999990.00'),
    CASE WHEN v_limp_bora > 0 THEN format(' + %s € limpezas', to_char(v_limp_bora, 'FM999990.00')) ELSE '' END,
    v_ent_nome, v_ent_nif, v_iva_txt);

  RETURN jsonb_build_object(
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month, 'nome', v_nome_mes,
                                  'inicio', v_ini, 'fim', v_fim, 'fuso', 'Europe/Lisbon',
                                  'tvde', 'excluído'),
    'totais', v_tot || jsonb_build_object('por_metodo', v_metodo),
    'servicos_totais', v_serv_tot,
    'limpeza_totais', jsonb_build_object('servicos', v_limp_n, 'pago_pelos_clientes', v_limp_pago,
                                         'pago_prestadores', v_limp_prest, 'taxa_bora', v_limp_bora),
    'parceiros', v_parc,
    'servicos', v_serv,
    'estafetas', v_est,
    'pedidos_no_prejuizo', v_prej,
    'modelo_a_partir_de_2026_10', v_mand,
    'tvde_outros_motoristas', jsonb_build_object(
       'parte_bora', v_tvde, 'corridas', v_tvde_n,
       'nota', 'Soma de tvde_rides.bora_cut_cents (finalizada). Fora: corridas do próprio Danilo e contas de teste. Informativo: o TVDE de passageiros não entra na declaração da Bora.'),
    'entidade', jsonb_build_object('tipo', v_ent_tipo, 'nome', v_ent_nome, 'nif', v_ent_nif),
    'para_as_financas', jsonb_build_object(
       'regime', v_regime,
       'receita_propria', v_receita, 'rubricas', v_rub,
       'receita_limpeza', v_limp_bora,
       'receita_servicos', coalesce((v_serv_tot->>'bora_reteve')::numeric,0),
       'parte_bora_tvde_outros', v_tvde,
       'tvde_na_declaracao', false,
       'total_a_declarar', v_receita + v_limp_bora + coalesce((v_serv_tot->>'bora_reteve')::numeric,0),
       'faturas_recibo', v_fat,
       'texto', v_texto, 'nota_iva', v_iva_txt),
    'regra_custo', 'parceiro=ledger earning; não-parceiro=talão (order_receipts_v2); sem talão=subtotal/1,15',
    'gerado_em', now());
END;
$function$;

CREATE OR REPLACE FUNCTION public.driver_monthly_invoice_summary(p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ini timestamptz; v_fim timestamptz; v_admin boolean := public.is_admin(); v_out jsonb;
  v_nome_mes text := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                            'agosto','setembro','outubro','novembro','dezembro'])[p_month];
  -- A partir de novembro/2026 a cobrança é da sociedade; até outubro é o Danilo em nome individual.
  v_sociedade boolean := (p_year, p_month) >= (2026, 11);
  v_cli_nome text; v_cli_nif text; v_cli_morada text; v_cli_tipo text; v_retencao text;
BEGIN
  IF auth.uid() IS NULL AND coalesce(auth.jwt()->>'role','') <> 'service_role' THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);

  IF v_sociedade THEN
    v_cli_tipo := 'sociedade';
    v_cli_nome := 'Danilo Fulfaro da Silva - Unipessoal Lda';
    v_cli_nif := '519686233';
    v_cli_morada := 'Rua do Torreão 14, 6300-610 Guarda';
    v_retencao := 'Retenção na fonte de IRS (art. 101.º CIRS), salvo dispensa do prestador (art. 101.º-B, até 15.000 €/ano)';
  ELSE
    v_cli_tipo := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_tipo'), 'individual');
    v_cli_nome := coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nome'), ''), 'Danilo Fulfaro da Silva');
    v_cli_nif := coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nif'), ''), '322151171');
    v_cli_morada := coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_morada'), ''), 'Rua do Torreão 14, 6300-610 Guarda');
    v_retencao := 'Sem retenção de IRS: o adquirente é um particular sem contabilidade organizada';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_user_id, 'nome', d.name,
           'nif', coalesce(fs.nif, d.nif),
           'atividade_aberta', coalesce(fs.atividade_aberta, false),
           'ano', p_year, 'mes', p_month,
           'entregas', x.n, 'total_a_faturar', x.total,
           'cliente', v_cli_nome,
           'cliente_nif', v_cli_nif,
           'cliente_morada', v_cli_morada,
           'cliente_tipo', v_cli_tipo,
           'proprio_adquirente', lower(coalesce(nullif(trim(d.email), ''), u.email, '')) = 'boraappbora@gmail.com',
           'texto_recibo', format('Serviços prestados em %s de %s através da plataforma Bora (%s entregas)', v_nome_mes, p_year, x.n),
           'iva', 'IVA — regime de isenção (art. 53.º CIVA), se o prestador estiver nesse regime; senão IVA 23%',
           'retencao', v_retencao,
           'prazo', 'Fatura-recibo até ao 5.º dia útil seguinte ao recebimento',
           'recibo_numero', mi.recibo_numero, 'recibo_data', mi.recibo_data, 'marcado_em', mi.marcado_em,
           'recibo_passado', mi.marcado_em IS NOT NULL)
         ORDER BY d.name), '[]'::jsonb)
    INTO v_out
    FROM (SELECT driver_user_id, count(*) n, sum(estafeta) total
            FROM public._fecho_pedidos(v_ini, v_fim)
           WHERE driver_user_id IS NOT NULL
             AND (v_admin OR coalesce(auth.jwt()->>'role','') = 'service_role'
                  OR driver_user_id = auth.uid()::text)
           GROUP BY driver_user_id) x
    LEFT JOIN public.drivers d ON d.user_id::text = x.driver_user_id
    LEFT JOIN auth.users u ON u.id::text = x.driver_user_id
    LEFT JOIN public.driver_fiscal_status fs ON fs.user_id::text = x.driver_user_id
    LEFT JOIN public.driver_monthly_invoices mi
           ON mi.user_id::text = x.driver_user_id AND mi.ano = p_year AND mi.mes = p_month;
  RETURN jsonb_build_object('ano', p_year, 'mes', p_month, 'nome_mes', v_nome_mes, 'estafetas', v_out,
                            'adquirente', jsonb_build_object('tipo', v_cli_tipo, 'nome', v_cli_nome, 'nif', v_cli_nif, 'morada', v_cli_morada, 'retencao', v_retencao));
END $function$;
