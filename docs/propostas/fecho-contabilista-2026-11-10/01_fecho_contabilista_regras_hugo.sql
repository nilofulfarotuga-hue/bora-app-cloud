-- PROPOSTA (missão fecho-contabilista-2026-11-10, Claude Code, 10/11/2026) — APLICA A CLAUDE.AI.
-- A bora-tranca desta sessão recusa migrations/DDL ("publicar → Claude.ai"; Write em supabase/migrations
-- recusado: "migration que toca tokens/wallet/pagamentos/ledger"). Este ficheiro é a migração inteira,
-- provada no PGlite com as definições reais e os dados reais de outubro e novembro de 2026
-- (prova em docs/propostas/fecho-contabilista-2026-11-10/prova_pglite.mjs e PROVA.md).
-- Ao aplicar: gravar também em supabase/migrations/20261110163000_fecho_contabilista_regras_hugo_2026_11_10.sql
-- (texto igual) e só DEPOIS publicar a Edge fecho-mensal-contabilista e a monthly-partner-statement deste ramo.
--
-- Ordem do Danilo (10/11/2026): "Eu quero que você arrume um sistema aí. O que vai pro estafeta, o que vai
-- pro parceiro, o que vai pro contabilista... O sistema tem que estar ótimo, sem erro."
--
-- Regras fiscais fechadas com o contabilista (Hugo Carvalho, DC Consultores) a 10/11/2026:
--  1) é o escritório do Hugo que emite as faturas da Bora (a Bora não emite faturas nem recibos);
--  2) a Bora fatura só o que ganha; estafeta, limpadora e profissional da Casa faturam a sua parte;
--     a parte da Bora nas lojas parceiras fatura-se aos CLIENTES, nunca às lojas;
--  3) sem NIF do cliente = consumidor final (o NIF da Bora nunca vai na caixa);
--  4) prestadores: uns isentos de IVA, outros não — nunca escrever que todos são isentos;
--  5) a sociedade (NIPC 519686233) cobra desde novembro/2026; outubro/2026 foi no nome individual;
--  6) o TVDE está fora da plataforma e não entra em fecho nenhum.
--
-- NÃO muda preços, comissões, ganhos nem cobra nada a ninguém: só leitura e textos do fecho.
--  a) backup das funções alteradas em public.bkp_funcoes_fecho_20261110;
--  b) admin_monthly_closeout: uma só linha "Consumidor final" com a parte da Bora toda; tokens descontados
--     numa rubrica própria; entidade pelo mês (sociedade desde 11/2026); texto sem TVDE e sem "fatura à loja";
--  c) fecho_mensal_prestadores e driver_monthly_invoice_summary: textos de IVA/retenção sem regra fixa;
--  d) promo_code_uses.tokens_origem: liga o uso de um código de tokens (BEMVINDO) aos tokens creditados;
--  e) funções novas: fecho_contabilista_extras, admin_prestadores_dados_fiscais (DAC7), admin_fecho_contabilista
--     (o que vai ao contabilista, com o texto para copiar), admin_fecho_contabilista_nota,
--     admin_fecho_contabilista_reenviar e admin_fecho_conferencia (só reporta diferenças, não corrige).

-- ── a) backup ────────────────────────────────────────────────────────────────
create table if not exists public.bkp_funcoes_fecho_20261110 (
  nome text primary key,
  definicao text not null,
  guardado_em timestamptz not null default now()
);
alter table public.bkp_funcoes_fecho_20261110 enable row level security;
revoke all on public.bkp_funcoes_fecho_20261110 from public, anon, authenticated;
insert into public.bkp_funcoes_fecho_20261110 (nome, definicao)
select p.oid::regprocedure::text, pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('admin_monthly_closeout', 'fecho_mensal_prestadores', 'driver_monthly_invoice_summary')
on conflict (nome) do nothing;

-- ── helper: euros em PT-PT ("12,34 €") ──────────────────────────────────────
create or replace function public._fecho_eur(p numeric)
returns text language sql immutable set search_path to 'public' as $$
  select replace(to_char(round(coalesce(p, 0), 2), 'FM9999990.00'), '.', ',') || ' €'
$$;

-- ── helper: tokens mesmo descontados num pedido ─────────────────────────────
-- Há pedidos em que o desconto dos tokens já vem dentro do total (ex.: Goola 10/2026: 11,55 + 3,74 − 2,51
-- = 12,78) e outros em que o "pago" do fecho o desconta (Auchan, Continente); há também pedidos com
-- tokens marcados que não chegaram a ser descontados (Burger King 10/2026: pagou 30,44 inteiros).
-- Regra: o que falta ao pago para chegar a produtos + taxas, até ao valor dos tokens marcados.
create or replace function public._fecho_tokens_descontados(p_tokens_cents integer, p_subtotal numeric,
                                                            p_taxas numeric, p_pago numeric)
returns numeric language sql immutable set search_path to 'public' as $$
  select case when coalesce(p_tokens_cents, 0) > 0
              then greatest(0, least(round(p_tokens_cents / 100.0, 2),
                                     round(coalesce(p_subtotal, 0) + coalesce(p_taxas, 0) - coalesce(p_pago, 0), 2)))
              else 0 end
$$;

-- ── d) promo_code_uses: ligação ao crédito de tokens ─────────────────────────
-- Um código do tipo tokens_grant (BEMVINDO) não é desconto num pedido: credita tokens na conta do cliente
-- (bora_tokens.source_order_id = 'promo-<CÓDIGO>-<user_id>', em client_redeem_promo_tokens). Por isso o uso
-- fica com order_id NULL. A coluna gerada guarda essa ligação em todas as linhas (passadas e futuras),
-- sem tocar na função que credita os tokens.
alter table public.promo_code_uses
  add column if not exists tokens_origem text
  generated always as (case when order_id is null then 'promo-' || code || '-' || user_id::text end) stored;
comment on column public.promo_code_uses.tokens_origem is
  'Uso de código de tokens (sem pedido): igual a bora_tokens.source_order_id do crédito. Missão fecho-contabilista 10/11/2026.';

-- ── b) admin_monthly_closeout ────────────────────────────────────────────────
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
  v_r_ent numeric; v_r_serv numeric; v_r_sacos numeric; v_r_peq numeric; v_r_parc numeric;
  v_r_np numeric; v_r_tok numeric; v_r_rec numeric; v_r_ajustes numeric; v_marc numeric;
BEGIN
  -- Guarda: admin, servidor (service_role) ou ligação direta à base (cron/CLI como postgres). NUNCA
  -- current_user: dentro de SECURITY DEFINER é sempre o dono (postgres) e deixava passar todos.
  IF NOT (public.is_admin() OR coalesce(auth.jwt()->>'role','') = 'service_role'
          OR session_user = 'postgres') THEN
    RAISE EXCEPTION 'admin_required';
  END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);
  v_nome_mes := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                       'agosto','setembro','outubro','novembro','dezembro'])[p_month];

  -- 10/11/2026 (regra 5): a sociedade cobra desde novembro/2026; antes, as settings fecho_entidade_*
  -- (Danilo em nome individual). Igual a driver_monthly_invoice_summary e fecho_mensal_prestadores.
  IF (p_year, p_month) >= (2026, 11) THEN
    v_ent_tipo := 'sociedade';
    v_ent_nome := 'Danilo Fulfaro da Silva - Unipessoal Lda';
    v_ent_nif  := '519686233';
  ELSE
    v_ent_tipo := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_tipo'), 'individual');
    v_ent_nome := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nome'), '');
    v_ent_nif  := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nif'), '');
  END IF;
  IF v_ent_tipo = 'sociedade' THEN
    v_regime := 'sociedade; IVA regime normal (trimestral), 23% incluído nas faturas da Bora';
    v_iva_txt := 'IVA da Bora: regime normal (trimestral), com IVA 23% incluído nas faturas da Bora.';
  ELSE
    v_regime := 'nome individual, regime simplificado; IVA isento art. 53.º CIVA (M10)';
    v_iva_txt := 'IVA da Bora: isenção do art. 53.º do CIVA (M10), enquanto a cobrança foi em nome individual.';
  END IF;

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
  v_marc := coalesce((v_serv_tot->>'bora_reteve')::numeric, 0);

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

  -- Rubricas (10/11/2026): os tokens descontados aos clientes passam a rubrica própria (antes estavam
  -- dentro da margem dos não-parceiros e dos ajustes). tok = _fecho_tokens_descontados (o que faltou
  -- pagar, até ao valor dos tokens marcados). A margem dos não-parceiros passa a ser a de antes dos tokens.
  -- A soma das rubricas é sempre a receita própria (os ajustes fecham a conta).
  SELECT coalesce(sum(f.delivery_fee),0), coalesce(sum(f.service_fee),0), coalesce(sum(f.bag_fee),0),
         coalesce(sum(f.small_order_fee),0),
         coalesce(sum(f.comissao_margem) FILTER (WHERE f.is_partner),0),
         coalesce(sum(f.comissao_margem + f.tok) FILTER (WHERE NOT f.is_partner),0),
         coalesce(sum(f.tok),0), coalesce(sum(f.receita),0)
    INTO v_r_ent, v_r_serv, v_r_sacos, v_r_peq, v_r_parc, v_r_np, v_r_tok, v_r_rec
    FROM (SELECT f.*, public._fecho_tokens_descontados(o.tokens_applied_value_cents, f.subtotal, f.taxas, f.pago) AS tok
            FROM public._fecho_pedidos(v_ini, v_fim) f
            JOIN public.orders o ON o.id = f.order_id) f;
  v_r_ajustes := round(v_r_rec - (v_r_ent + v_r_serv + v_r_sacos + v_r_peq + v_r_parc + v_r_np - v_r_tok), 2);
  v_rub := jsonb_build_object(
    'entrega', v_r_ent,
    'taxa_servico', v_r_serv,
    'sacos', v_r_sacos,
    'taxa_pedido_pequeno', v_r_peq,
    'comissao_lojas_parceiras', v_r_parc,
    'margem_nao_parceiros', v_r_np,
    'tokens_descontados', -v_r_tok,
    'ajustes_descontos', v_r_ajustes);
  v_fat_parc := v_r_parc;

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

  -- 10/11/2026 (regras 1 e 2): UMA linha "Consumidor final" com a parte da Bora toda. As faturas são
  -- emitidas pelo escritório do contabilista; a parte da Bora nas lojas parceiras fatura-se aos clientes,
  -- nunca às lojas (acabou a linha "Comissão de intermediação" por loja).
  v_fat := jsonb_build_array(jsonb_build_object(
    'destinatario', 'Consumidor final', 'nif', NULL, 'falta_nif', false,
    'valor', v_receita + v_limp_bora + v_marc,
    'entregas_e_mercados', v_receita, 'limpezas', v_limp_bora, 'marcacoes', v_marc,
    'inclui_lojas_parceiras', v_fat_parc,
    'descricao', 'Parte da Bora em ' || v_nome_mes || ' ' || p_year || ' — entregas e mercados'
                 || CASE WHEN v_limp_bora > 0 THEN ', taxa das limpezas' ELSE '' END
                 || CASE WHEN v_marc > 0 THEN ', marcações' ELSE '' END
                 || '. Faturada aos clientes pelo escritório do contabilista (consumidor final, ou o NIF do cliente quando o pediu), nunca às lojas.'));

  v_texto := format(
    'Receita própria da Bora em %s de %s: %s nas entregas e mercados, mais %s de taxa da Bora nas limpezas (%s serviços; clientes pagaram %s, prestadoras %s)%s. '
    'Entregas por rubrica: entrega %s, taxa de serviço %s, sacos %s, taxa de pedido pequeno %s, '
    'parte da Bora nos produtos das lojas parceiras %s, margem sobre compras em lojas não parceiras %s, tokens descontados %s, ajustes %s. '
    'Não inclui o valor da mercadoria (%s), que pertence às lojas. '
    'Faturação: as faturas da Bora são emitidas pelo escritório do contabilista; a parte da Bora (%s no total) fatura-se aos clientes — consumidor final, ou o NIF do cliente quando o pediu — e nunca às lojas. '
    'Cada prestador fatura a sua parte; o regime de IVA e a retenção de cada um são confirmados pelo contabilista. '
    'Entidade: %s (NIF %s). %s',
    v_nome_mes, p_year, public._fecho_eur(v_receita),
    public._fecho_eur(v_limp_bora), v_limp_n, public._fecho_eur(v_limp_pago), public._fecho_eur(v_limp_prest),
    CASE WHEN v_marc > 0 THEN format(', mais %s retidos em marcações', public._fecho_eur(v_marc)) ELSE '' END,
    public._fecho_eur(v_r_ent), public._fecho_eur(v_r_serv), public._fecho_eur(v_r_sacos), public._fecho_eur(v_r_peq),
    public._fecho_eur(v_r_parc), public._fecho_eur(v_r_np), public._fecho_eur(-v_r_tok), public._fecho_eur(v_r_ajustes),
    public._fecho_eur((v_tot->>'custo_mercadoria')::numeric),
    public._fecho_eur(v_receita + v_limp_bora + v_marc),
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
       'nota', 'Só informativo para o painel: o TVDE está fora da plataforma e não entra em fecho nenhum (regra de 10/11/2026).'),
    'entidade', jsonb_build_object('tipo', v_ent_tipo, 'nome', v_ent_nome, 'nif', v_ent_nif),
    'para_as_financas', jsonb_build_object(
       'regime', v_regime,
       'receita_propria', v_receita, 'rubricas', v_rub,
       'receita_limpeza', v_limp_bora,
       'receita_servicos', v_marc,
       'parte_bora_tvde_outros', v_tvde,
       'tvde_na_declaracao', false,
       'total_a_declarar', v_receita + v_limp_bora + v_marc,
       'faturas_recibo', v_fat,
       'texto', v_texto, 'nota_iva', v_iva_txt),
    'regra_custo', 'parceiro=ledger earning; não-parceiro=talão (order_receipts_v2); sem talão=subtotal/1,15',
    'gerado_em', now());
END;
$function$;

-- ── c) fecho_mensal_prestadores: textos de IVA/retenção e a "fatura" das lojas ──
CREATE OR REPLACE FUNCTION public.fecho_mensal_prestadores(p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ini timestamptz; v_fim timestamptz; v_nome_mes text;
  v_adq jsonb; v_estafetas jsonb; v_limpeza jsonb; v_lavagem jsonb; v_tvde jsonb; v_lojas jsonb;
  v_excluir jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or session_user = 'postgres') then
    raise exception 'admin_required';
  end if;
  if p_month not between 1 and 12 then raise exception 'mes_invalido'; end if;
  select ini, fim into v_ini, v_fim from public._fecho_limites(p_year, p_month);
  v_nome_mes := (array['janeiro','fevereiro','março','abril','maio','junho','julho',
                       'agosto','setembro','outubro','novembro','dezembro'])[p_month];

  -- 10/11/2026 (regra 4): nada de IVA ou retenção fixos — uns prestadores são isentos e outros não; o
  -- contabilista confirma o regime e a retenção de cada um.
  if (p_year, p_month) >= (2026, 11) then
    v_adq := jsonb_build_object('tipo', 'sociedade', 'nome', 'Danilo Fulfaro da Silva - Unipessoal Lda',
      'nif', '519686233', 'morada', 'Rua do Torreão 14, 6300-610 Guarda',
      'retencao', 'Retenção na fonte de IRS: confirmada pelo contabilista para cada prestador (há quem esteja dispensado, art. 101.º-B CIRS)');
  else
    v_adq := jsonb_build_object(
      'tipo',   coalesce((select value #>> '{}' from platform_settings where key='fecho_entidade_tipo'), 'individual'),
      'nome',   coalesce(nullif((select value #>> '{}' from platform_settings where key='fecho_entidade_nome'), ''), 'Danilo Fulfaro da Silva'),
      'nif',    coalesce(nullif((select value #>> '{}' from platform_settings where key='fecho_entidade_nif'), ''), '322151171'),
      'morada', coalesce(nullif((select value #>> '{}' from platform_settings where key='fecho_entidade_morada'), ''), 'Rua do Torreão 14, 6300-610 Guarda'),
      'retencao', 'Retenção na fonte de IRS: confirmada pelo contabilista (adquirente em nome individual)');
  end if;
  v_adq := v_adq || jsonb_build_object(
    'iva_prestador', 'Cada prestador fatura a sua parte; uns são isentos de IVA (art. 53.º CIVA) e outros não — o regime de cada um é confirmado pelo contabilista',
    'prazo', 'Fatura-recibo até ao 5.º dia útil seguinte ao recebimento (art. 36.º CIVA / art. 115.º CIRS)',
    'descricao_sugerida', 'Serviços prestados em ' || v_nome_mes || ' de ' || p_year || ' através da plataforma Bora');

  v_excluir := coalesce((select value from platform_settings where key = 'fecho_tvde_excluir_emails'), '[]'::jsonb);

  with fm as (select * from public._fecho_pedidos(v_ini, v_fim))
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_user_id, 'nome', coalesce(d.legal_name, d.name), 'email', d.email, 'nif', d.nif,
           'entregas', x.n, 'ganho', x.ganho, 'dinheiro_recebido_em_mao', x.cash, 'taloes_adiantados', x.taloes,
           'proprio_adquirente', lower(coalesce(nullif(trim(d.email),''), u.email, '')) = 'boraappbora@gmail.com',
           'recibo', jsonb_build_object('valor', x.ganho,
             'descricao', 'Serviços de entrega prestados em ' || v_nome_mes || ' de ' || p_year || ' através da plataforma Bora (' || x.n || ' entregas)'))
         order by x.ganho desc), '[]'::jsonb)
    into v_estafetas
    from (select driver_user_id, count(*) n, sum(estafeta) ganho, sum(cash_em_mao) cash, coalesce(sum(talao),0) taloes
            from fm group by driver_user_id) x
    left join public.drivers d on d.user_id::text = x.driver_user_id
    left join auth.users u on u.id::text = x.driver_user_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'cleaner_id', c.id, 'user_id', c.user_id, 'nome', coalesce(c.legal_name, c.name), 'email', c.email, 'nif', c.nif,
           'servicos', x.n, 'pago_pelos_clientes', x.total, 'ganho', x.ganho, 'taxa_bora', x.taxa,
           'em_dinheiro', x.cash_total, 'por_mbway_cartao', x.online_total,
           'acertos', (select coalesce(jsonb_agg(jsonb_build_object('semana', s.week_start_at::date, 'direcao', s.direction,
                          'valor', round(s.net_payout_cents/100.0,2), 'estado', s.status, 'pago_em', s.paid_at) order by s.week_start_at), '[]'::jsonb)
                        from public.cleaner_weekly_settlements s
                       where s.cleaner_id = c.id and s.week_end_at >= v_ini and s.week_end_at < v_fim + interval '7 days'),
           'recibo', jsonb_build_object('valor', x.ganho,
             'descricao', 'Serviços de limpeza prestados em ' || v_nome_mes || ' de ' || p_year || ' através da plataforma Bora (' || x.n || ' serviços)'))
         order by x.ganho desc), '[]'::jsonb)
    into v_limpeza
    from (select cleaner_id, count(*) n, round(sum(total_cents)/100.0,2) total, round(sum(cleaner_earnings_cents)/100.0,2) ganho,
                 round(sum(bora_fee_cents)/100.0,2) taxa,
                 round(sum(total_cents) filter (where payment_method = 'cash')/100.0,2) cash_total,
                 round(sum(total_cents) filter (where payment_method <> 'cash')/100.0,2) online_total
            from public.cleaning_bookings
           where status in ('completed','done') and coalesce(is_test_order,false) = false
             and scheduled_at >= v_ini and scheduled_at < v_fim
           group by cleaner_id) x
    join public.cleaners c on c.id = x.cleaner_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'washer_id', w.id, 'nome', coalesce(w.legal_name, w.name), 'email', w.email, 'nif', w.nif,
           'servicos', x.n, 'pago_pelos_clientes', x.total, 'ganho', x.ganho, 'taxa_bora', x.taxa,
           'recibo', jsonb_build_object('valor', x.ganho,
             'descricao', 'Serviços de lavagem automóvel prestados em ' || v_nome_mes || ' de ' || p_year || ' através da plataforma Bora (' || x.n || ' serviços)'))
         order by x.ganho desc), '[]'::jsonb)
    into v_lavagem
    from (select washer_id, count(*) n, round(sum(total_cents)/100.0,2) total, round(sum(washer_earnings_cents)/100.0,2) ganho,
                 round(sum(bora_fee_cents)/100.0,2) taxa
            from public.carwash_bookings
           where status in ('completed','done') and coalesce(is_test_order,false) = false
             and coalesce(completed_at, done_at, created_at) >= v_ini and coalesce(completed_at, done_at, created_at) < v_fim
           group by washer_id) x
    join public.washers w on w.id = x.washer_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_id, 'nome', coalesce(d.legal_name, d.name, u.email), 'nif', d.nif,
           'corridas', x.n, 'ganho_motorista', x.ganho, 'parte_bora', x.bora, 'em_dinheiro', x.cash,
           'nota', 'TVDE fora da plataforma: não entra em fecho nenhum (só informativo no painel).')
         order by x.ganho desc), '[]'::jsonb)
    into v_tvde
    from (select t.driver_id, count(*) n, round(sum(t.driver_earn_cents)/100.0,2) ganho, round(sum(t.bora_cut_cents)/100.0,2) bora,
                 round(sum(t.driver_earn_cents) filter (where t.payment_method = 'cash')/100.0,2) cash
            from public.tvde_rides t
           where t.status = 'finalizada' and t.created_at >= v_ini and t.created_at < v_fim and t.driver_id is not null
           group by t.driver_id) x
    left join auth.users u on u.id = x.driver_id
    left join public.drivers d on d.user_id = x.driver_id
   where lower(coalesce(u.email,'')) not in (select lower(e) from jsonb_array_elements_text(v_excluir) e)
     and coalesce(u.email,'') not ilike '%.test'
     and not coalesce(public.is_demo_email(u.email), false);

  -- 10/11/2026 (regra 2): a parte da Bora nos pedidos de cada loja parceira fatura-se aos clientes,
  -- nunca à loja. A chave 'fatura_bora' fica (compatibilidade), com o texto certo.
  with fm as (select * from public._fecho_pedidos(v_ini, v_fim))
  select coalesce(jsonb_agg(jsonb_build_object(
           'partner_id', x.restaurant_id, 'nome', coalesce(r.name, x.nome), 'nif', r.nif, 'email', r.email,
           'pedidos', x.n, 'vendas', x.vendas, 'comissao_bora', x.comissao, 'parte_bora', x.comissao, 'parte_loja', x.parte,
           'fatura_bora', jsonb_build_object('valor', x.comissao, 'faturada_a', 'clientes',
             'descricao', 'Parte da Bora nos pedidos desta loja (' || v_nome_mes || ' ' || p_year || ') — faturada aos clientes (consumidor final ou NIF do cliente), nunca à loja'))
         order by coalesce(r.name, x.nome)), '[]'::jsonb)
    into v_lojas
    from (select restaurant_id, max(vendor_name) nome, count(*) n, sum(subtotal) vendas, sum(comissao_margem) comissao, sum(custo) parte
            from fm where is_partner group by restaurant_id) x
    left join public.restaurants r on r.id = x.restaurant_id;

  return jsonb_build_object(
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month, 'nome', v_nome_mes, 'inicio', v_ini, 'fim', v_fim),
    'adquirente', v_adq,
    'estafetas', v_estafetas, 'limpeza', v_limpeza, 'lavagem', v_lavagem,
    'tvde_outros_motoristas', v_tvde, 'lojas_parceiras', v_lojas,
    'gerado_em', now());
end $function$;

-- ── c) driver_monthly_invoice_summary: IVA e retenção sem regra fixa ───────────
CREATE OR REPLACE FUNCTION public.driver_monthly_invoice_summary(p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ini timestamptz; v_fim timestamptz; v_admin boolean := public.is_admin(); v_out jsonb;
  v_nome_mes text := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                            'agosto','setembro','outubro','novembro','dezembro'])[p_month];
  v_sociedade boolean := (p_year, p_month) >= (2026, 11);
  v_cli_nome text; v_cli_nif text; v_cli_morada text; v_cli_tipo text; v_retencao text;
BEGIN
  IF auth.uid() IS NULL AND coalesce(auth.jwt()->>'role','') <> 'service_role' THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);

  -- 10/11/2026 (regra 4): a retenção e o IVA de cada prestador são confirmados pelo contabilista.
  IF v_sociedade THEN
    v_cli_tipo := 'sociedade';
    v_cli_nome := 'Danilo Fulfaro da Silva - Unipessoal Lda';
    v_cli_nif := '519686233';
    v_cli_morada := 'Rua do Torreão 14, 6300-610 Guarda';
    v_retencao := 'Retenção na fonte de IRS: o contabilista da Bora confirma o seu caso (há quem esteja dispensado, art. 101.º-B CIRS)';
  ELSE
    v_cli_tipo := coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_tipo'), 'individual');
    v_cli_nome := coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nome'), ''), 'Danilo Fulfaro da Silva');
    v_cli_nif := coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nif'), ''), '322151171');
    v_cli_morada := coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_morada'), ''), 'Rua do Torreão 14, 6300-610 Guarda');
    v_retencao := 'Retenção na fonte de IRS: o contabilista da Bora confirma o seu caso';
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
           'proprio_adquirente', lower(coalesce(d.email, '')) = 'boraappbora@gmail.com',
           'texto_recibo', format('Serviços prestados em %s de %s através da plataforma Bora (%s entregas)', v_nome_mes, p_year, x.n),
           'iva', 'IVA: depende do seu regime nas Finanças (isento pelo art. 53.º do CIVA, ou com IVA); o contabilista da Bora confirma',
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
    LEFT JOIN public.driver_fiscal_status fs ON fs.user_id::text = x.driver_user_id
    LEFT JOIN public.driver_monthly_invoices mi
           ON mi.user_id::text = x.driver_user_id AND mi.ano = p_year AND mi.mes = p_month;
  RETURN jsonb_build_object('ano', p_year, 'mes', p_month, 'nome_mes', v_nome_mes, 'estafetas', v_out,
                            'adquirente', jsonb_build_object('tipo', v_cli_tipo, 'nome', v_cli_nome, 'nif', v_cli_nif, 'morada', v_cli_morada, 'retencao', v_retencao));
END $function$;

-- ── e) fecho_contabilista_extras: tokens, prémios, códigos, cancelamentos, Stripe, NIF do cliente ──
create or replace function public.fecho_contabilista_extras(p_year integer, p_month integer)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_ini timestamptz; v_fim timestamptz; v_mes text; v_eur_token numeric;
  v_tok jsonb; v_tok_desc jsonb; v_vales jsonb; v_promo jsonb; v_canc jsonb; v_reemb jsonb;
  v_stripe jsonb; v_stripe_est numeric; v_nif jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or session_user = 'postgres') then
    raise exception 'admin_required';
  end if;
  if p_month not between 1 and 12 then raise exception 'mes_invalido'; end if;
  select ini, fim into v_ini, v_fim from public._fecho_limites(p_year, p_month);
  v_mes := to_char(make_date(p_year, p_month, 1), 'YYYY-MM');
  -- Valor de cada token: definição token_value_cents_x100 (50 = 0,5 cêntimos = 0,005 €), a mesma fonte
  -- que client_redeem_promo_tokens usa.
  v_eur_token := coalesce((public.get_setting('token_value_cents_x100') #>> '{}')::numeric, 50) / 10000.0;

  -- Tokens oferecidos aos clientes no mês (só leitura de bora_tokens; nada se altera).
  with t as (
    select bt.amount,
           case when bt.source_order_id like 'promo-%' then 'codigos_promocionais'
                when bt.source_order_id like 'checkin-%' then 'checkin_diario'
                when bt.source_order_id like 'cleaning:%' then 'limpezas'
                when bt.source_order_id like 'devolucao%' then 'devolucoes'
                when bt.source_order_id is not null
                     and exists (select 1 from public.orders o where o.id = bt.source_order_id) then 'pedidos'
                else 'outros' end as origem
      from public.bora_tokens bt
     where bt.role = 'client' and bt.amount > 0
       and bt.created_at >= v_ini and bt.created_at < v_fim)
  select jsonb_build_object(
           'registos', count(*), 'tokens', coalesce(sum(amount), 0),
           'valor', round(coalesce(sum(amount), 0) * v_eur_token, 2), 'valor_por_token', v_eur_token,
           'por_origem', coalesce((select jsonb_agg(jsonb_build_object('origem', g.origem, 'registos', g.n, 'tokens', g.tk,
                                                                       'valor', round(g.tk * v_eur_token, 2)) order by g.tk desc)
                                     from (select origem, count(*) n, sum(amount) tk from t group by origem) g), '[]'::jsonb),
           'nota', 'Oferecer tokens não é custo: passa a custo só quando o cliente os usa num pedido.')
    into v_tok from t;

  -- Tokens descontados nos pedidos entregues do mês (mesma regra da rubrica de admin_monthly_closeout).
  -- Os pedidos com tokens marcados mas não descontados ficam à parte, para o contabilista saber.
  select jsonb_build_object('pedidos', count(*) filter (where x.d > 0), 'valor', coalesce(sum(x.d), 0),
                            'marcados_sem_desconto', count(*) filter (where x.marcado > 0 and x.d = 0))
    into v_tok_desc
    from (select public._fecho_tokens_descontados(o.tokens_applied_value_cents, f.subtotal, f.taxas, f.pago) d,
                 coalesce(o.tokens_applied_value_cents, 0) marcado
            from public._fecho_pedidos(v_ini, v_fim) f join public.orders o on o.id = f.order_id) x;

  -- Prémios do check-in (vales).
  select jsonb_build_object(
           'emitidos', count(*) filter (where v.emitido_em >= v_ini and v.emitido_em < v_fim),
           'emitidos_valor', round(coalesce(sum(v.valor_cents) filter (where v.emitido_em >= v_ini and v.emitido_em < v_fim), 0) / 100.0, 2),
           'emitidos_custo', round(coalesce(sum(v.custo_cents) filter (where v.emitido_em >= v_ini and v.emitido_em < v_fim), 0) / 100.0, 2),
           'usados', count(*) filter (where v.usado_em >= v_ini and v.usado_em < v_fim),
           'usados_custo', round(coalesce(sum(v.custo_cents) filter (where v.usado_em >= v_ini and v.usado_em < v_fim), 0) / 100.0, 2),
           'pagos_a_lojas', count(*) filter (where v.pago_loja_em >= v_ini and v.pago_loja_em < v_fim),
           'anulados', count(*) filter (where v.anulado_em >= v_ini and v.anulado_em < v_fim))
    into v_vales
    from public.checkin_premios_vales v;

  -- Códigos promocionais usados no mês. Os de tokens (BEMVINDO) ficam sem pedido: a ligação é
  -- promo_code_uses.tokens_origem = bora_tokens.source_order_id.
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', g.code, 'tipo', g.tipo, 'usos', g.n, 'valor', g.valor,
           'com_pedido', g.com_pedido, 'tokens_ja_usados', g.tokens_usados,
           'nota', case when g.tipo = 'tokens_grant'
                        then 'Oferta de tokens na conta do cliente (sem pedido ligado): só é custo quando os tokens são usados num pedido.'
                        else 'Desconto aplicado no pedido.' end) order by g.n desc), '[]'::jsonb)
    into v_promo
    from (select u.code, coalesce(pc.type, '?') tipo, count(*) n,
                 round(sum(u.applied_value_cents) / 100.0, 2) valor,
                 count(*) filter (where u.order_id is not null) com_pedido,
                 count(*) filter (where exists (select 1 from public.bora_tokens bt
                                                 where bt.source_order_id = u.tokens_origem and bt.is_used)) tokens_usados
            from public.promo_code_uses u
            left join public.promo_codes pc on pc.code = u.code
           where u.used_at >= v_ini and u.used_at < v_fim
           group by u.code, pc.type) g;

  -- Pedidos cancelados e reembolsados no mês (sem TVDE, sem pedidos de teste).
  select jsonb_build_object(
           'cancelados', count(*) filter (where o.status in ('cancelled','canceled')),
           'cancelados_valor', coalesce(sum(coalesce(o.final_total, o.customer_total, o.total, 0)) filter (where o.status in ('cancelled','canceled')), 0),
           'cancelados_com_cobranca', count(*) filter (where o.status in ('cancelled','canceled') and coalesce(o.stripe_charge_cents, 0) > 0),
           'taxas_de_cancelamento', coalesce(sum(o.cancel_fee) filter (where o.status in ('cancelled','canceled')), 0),
           'reembolsados', count(*) filter (where coalesce(o.refund_amount, 0) > 0),
           'reembolsado_valor', round(coalesce(sum(o.refund_amount) filter (where coalesce(o.refund_amount, 0) > 0), 0)::numeric, 2))
    into v_canc
    from public.orders o
   where coalesce(o.is_test_order, false) = false
     and coalesce(o.service_type, '') not ilike 'tvde%'
     and coalesce(o.cancelled_at, o.refunded_at, o.created_at) >= v_ini
     and coalesce(o.cancelled_at, o.refunded_at, o.created_at) < v_fim
     and (o.status in ('cancelled','canceled') or coalesce(o.refund_amount, 0) > 0);

  select coalesce(jsonb_agg(jsonb_build_object(
           'order_id', o.id, 'data', (coalesce(o.refunded_at, o.cancelled_at, o.created_at) at time zone 'Europe/Lisbon')::date,
           'loja', o.vendor_name, 'estado', o.status, 'valor', o.refund_amount, 'meio', coalesce(o.refund_method, o.payment_method))
         order by coalesce(o.refunded_at, o.cancelled_at, o.created_at)), '[]'::jsonb)
    into v_reemb
    from public.orders o
   where coalesce(o.is_test_order, false) = false
     and coalesce(o.service_type, '') not ilike 'tvde%'
     and coalesce(o.refund_amount, 0) > 0
     and coalesce(o.refunded_at, o.cancelled_at, o.created_at) >= v_ini
     and coalesce(o.refunded_at, o.cancelled_at, o.created_at) < v_fim;
  v_canc := v_canc || jsonb_build_object('lista_reembolsos', v_reemb);

  -- Stripe: só as cobranças da Bora (entregas, mercados, limpeza, lavagem, reservas, Casa). Fora: TVDE,
  -- gorjetas, serviços de sites, payouts e outros. Se o extrato do mês ainda não tem linhas, vale a
  -- estimativa pelos pedidos.
  select coalesce(sum(public._fecho_stripe_estimado(f.stripe_charge_cents)), 0)
    into v_stripe_est from public._fecho_pedidos(v_ini, v_fim) f;
  select jsonb_build_object(
           'cobrancas', count(*), 'bruto', round(coalesce(sum(s.bruto_cents), 0) / 100.0, 2),
           'taxas', round(coalesce(sum(s.taxa_cents), 0) / 100.0, 2),
           'por_categoria', coalesce((select jsonb_agg(jsonb_build_object('categoria', c.categoria, 'cobrancas', c.n,
                                                                          'bruto', c.bruto, 'taxas', c.taxas) order by c.categoria)
                                        from (select s2.categoria, count(*) n, round(sum(s2.bruto_cents) / 100.0, 2) bruto,
                                                     round(sum(s2.taxa_cents) / 100.0, 2) taxas
                                                from public.stripe_extrato_contabilista s2
                                               where s2.mes = v_mes
                                                 and s2.categoria in ('entregas_mercados','limpeza','lavagem','reservas','casa')
                                               group by s2.categoria) c), '[]'::jsonb))
    into v_stripe
    from public.stripe_extrato_contabilista s
   where s.mes = v_mes and s.categoria in ('entregas_mercados','limpeza','lavagem','reservas','casa');
  v_stripe := v_stripe || jsonb_build_object(
    'taxas_estimadas_pelos_pedidos', v_stripe_est,
    'fonte', case when (v_stripe->>'cobrancas')::int > 0 then 'extrato_stripe' else 'estimativa_pelos_pedidos' end,
    'taxas_a_considerar', case when (v_stripe->>'cobrancas')::int > 0 then (v_stripe->>'taxas')::numeric else v_stripe_est end,
    'nota', 'Só as taxas das cobranças da Bora. Fora: TVDE, gorjetas, serviços de sites e outros.');

  -- Pedidos em que o cliente pediu fatura com NIF (a parte da Bora fatura-se a esse NIF).
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_id', f.order_id, 'data', (f.delivered_at at time zone 'Europe/Lisbon')::date, 'loja', f.vendor_name,
           'nif_cliente', coalesce(nullif(btrim(i.nif), ''), nullif(btrim(b.nif), '')), 'nome', nullif(btrim(i.nome), ''),
           'parte_bora', f.receita) order by f.delivered_at), '[]'::jsonb)
    into v_nif
    from public._fecho_pedidos(v_ini, v_fim) f
    join public.orders o on o.id = f.order_id
    join public.order_invoice_requests i on i.order_id = f.order_id
    left join public.client_billing_profile b on b.user_id = o.user_id
   where coalesce(nullif(btrim(i.nif), ''), nullif(btrim(b.nif), '')) is not null;

  return jsonb_build_object(
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month),
    'tokens_oferecidos', v_tok,
    'tokens_descontados_em_pedidos', v_tok_desc,
    'premios_checkin', v_vales,
    'codigos_promocionais', v_promo,
    'cancelados_e_reembolsos', v_canc,
    'stripe_parte_bora', v_stripe,
    'pedidos_com_nif_do_cliente', v_nif,
    'gerado_em', now());
end $function$;

-- ── e) admin_prestadores_dados_fiscais (DAC7) ───────────────────────────────
-- Lista estafetas aprovados, limpadoras, profissionais da Casa, lavagem e lojas parceiras ativas com os
-- dados que a plataforma tem de comunicar (DAC7): nome legal, NIF, morada, data de nascimento (pessoas),
-- IBAN (só sim/não — nunca o número), comprovativo de atividade e o que falta. Só admin/servidor.
-- Regra única (interna, sem acesso de fora): uma linha por prestador/loja com o que falta. Usada pelo
-- painel (admin_prestadores_dados_fiscais) e pela app do próprio prestador (meus_dados_fiscais_em_falta).
create or replace function public._dados_fiscais_linhas()
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_linhas jsonb;
begin
  with base as (
    select 'estafeta'::text papel, d.user_id, d.id::text ref_id, d.name nome_app,
           nullif(btrim(d.legal_name), '') nome_legal,
           coalesce(nullif(btrim(d.nif), ''), nullif(btrim(fs.nif), '')) nif,
           nullif(btrim(d.address), '') morada, d.birth_date,
           nullif(btrim(d.iban), '') is not null tem_iban,
           pa.atividade_status, true pessoa,
           lower(coalesce(d.email, '')) = 'boraappbora@gmail.com' proprio
      from public.drivers d
      left join public.driver_fiscal_status fs on fs.user_id = d.user_id
      left join public.provider_atividade pa on pa.user_id = d.user_id
     where d.approval_status = 'approved' and coalesce(d.is_banned, false) = false
    union all
    select 'limpeza', c.user_id, c.id::text, c.name, nullif(btrim(c.legal_name), ''), nullif(btrim(c.nif), ''),
           nullif(btrim(c.address), ''), c.birth_date, nullif(btrim(c.iban), '') is not null,
           pa.atividade_status, true, false
      from public.cleaners c
      left join public.provider_atividade pa on pa.user_id = c.user_id
     where c.approval_status = 'approved' and coalesce(c.is_active, true)
    union all
    select 'casa', h.user_id, h.id::text, h.name, nullif(btrim(h.legal_name), ''), nullif(btrim(h.nif), ''),
           nullif(btrim(h.address), ''), h.birth_date, nullif(btrim(h.iban), '') is not null,
           pa.atividade_status, true, false
      from public.casa_profissionais h
      left join public.provider_atividade pa on pa.user_id = h.user_id
     where h.approval_status = 'approved' and coalesce(h.is_active, true)
    union all
    select 'lavagem', w.user_id, w.id::text, w.name, nullif(btrim(w.legal_name), ''), nullif(btrim(w.nif), ''),
           nullif(btrim(w.address), ''), w.birth_date, nullif(btrim(w.iban), '') is not null,
           pa.atividade_status, true, false
      from public.washers w
      left join public.provider_atividade pa on pa.user_id = w.user_id
     where w.approval_status = 'approved' and coalesce(w.is_active, true) and coalesce(w.is_banned, false) = false
    union all
    -- Lojas: NIF começado por 1, 2 ou 3 = pessoa singular (empresário em nome individual) → também
    -- precisa da data de nascimento; NIF de empresa (5…) não.
    select 'loja_parceira', r.user_id, r.id, r.name, nullif(btrim(r.legal_name), ''), nullif(btrim(r.nif), ''),
           nullif(btrim(r.address), ''), r.birth_date, nullif(btrim(r.iban), '') is not null,
           null, coalesce(btrim(r.nif) ~ '^[123]', false), false
      from public.restaurants r
     where r.is_partner and r.approval_status = 'approved'
       and coalesce(r.is_active_admin, true) and not coalesce(r.coming_soon, false)
  ),
  -- Fora do DAC7: as contas do próprio Danilo (dono da plataforma; os mesmos emails que is_admin() usa)
  -- e as contas de demonstração.
  g as (
    select b.papel, b.user_id, b.ref_id, b.nome_app, b.nome_legal, b.nif, b.morada, b.birth_date, b.tem_iban,
           b.atividade_status, b.pessoa,
           (b.proprio or lower(coalesce(u.email, '')) in ('boraappbora@gmail.com', 'nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')) proprio,
           (coalesce(public.is_demo_email(u.email), false) or coalesce(b.nome_app, '') ~* '(^|\s)demo') demo
      from base b left join auth.users u on u.id = b.user_id),
  f as (
    select b.*,
           case when b.proprio or b.demo then array[]::text[] else array_remove(array[
             -- Pessoa: serve o nome completo da app (nome e apelido). Loja: precisa sempre do nome da empresa.
             case when b.nome_legal is null
                       and (b.papel = 'loja_parceira'
                            or coalesce(array_length(regexp_split_to_array(btrim(coalesce(b.nome_app, '')), '\s+'), 1), 0) < 2)
                  then 'nome legal' end,
             case when b.nif is null then 'NIF'
                  when b.nif !~ '^[0-9]{9}$' then 'NIF inválido' end,
             case when b.morada is null then 'morada' end,
             case when b.pessoa and b.birth_date is null then 'data de nascimento' end,
             case when not b.tem_iban then 'IBAN' end,
             case when b.papel <> 'loja_parceira' and coalesce(b.atividade_status, '') <> 'aprovada'
                  then 'comprovativo de atividade' end
           ], null) end falta
      from g b)
  select coalesce(jsonb_agg(jsonb_build_object(
           'papel', f.papel, 'user_id', f.user_id, 'ref_id', f.ref_id,
           'nome', coalesce(f.nome_legal, f.nome_app), 'nome_app', f.nome_app, 'nome_legal', f.nome_legal,
           'nif', f.nif, 'morada', f.morada, 'data_nascimento', f.birth_date,
           'tem_iban', f.tem_iban,
           'atividade', case when f.papel = 'loja_parceira' then 'não se aplica' else coalesce(f.atividade_status, 'por_enviar') end,
           'proprio_danilo', f.proprio, 'demo', f.demo,
           'nota', case when f.proprio then 'Conta do próprio Danilo (dono da plataforma): fora do DAC7.'
                        when f.demo then 'Conta de demonstração: fora do DAC7.' end,
           'falta', to_jsonb(f.falta), 'em_falta', cardinality(f.falta) > 0)
         order by cardinality(f.falta) > 0 desc, f.papel, coalesce(f.nome_legal, f.nome_app)), '[]'::jsonb)
    into v_linhas
    from f;
  return v_linhas;
end $function$;

create or replace function public.admin_prestadores_dados_fiscais()
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_linhas jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or session_user = 'postgres') then
    raise exception 'admin_required';
  end if;
  v_linhas := public._dados_fiscais_linhas();
  return jsonb_build_object(
    'linhas', v_linhas,
    'total', jsonb_array_length(v_linhas),
    'com_falta', (select count(*) from jsonb_array_elements(v_linhas) e where (e->>'em_falta')::boolean),
    'nota', 'DAC7: a plataforma comunica nome, NIF, morada, data de nascimento, conta bancária, valor pago e taxas retidas de cada prestador. Aqui só se diz se há IBAN, nunca o número.',
    'gerado_em', now());
end $function$;

-- C3: o próprio prestador (estafeta, limpeza, Casa, lavagem, loja) vê na app o que lhe falta. Só a linha
-- dele e só a lista do que falta (sem NIF, morada nem IBAN de volta).
create or replace function public.meus_dados_fiscais_em_falta()
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_uid uuid := auth.uid(); v_minhas jsonb;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'motivo', 'sem_sessao', 'em_falta', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('papel', e->>'papel', 'falta', e->'falta')), '[]'::jsonb)
    into v_minhas
    from jsonb_array_elements(public._dados_fiscais_linhas()) e
   where e->>'user_id' = v_uid::text and (e->>'em_falta')::boolean;
  return jsonb_build_object('ok', true, 'em_falta', v_minhas);
end $function$;

-- ── e) nota do Danilo no fecho, reenvio e o conteúdo completo para o contabilista ──
alter table public.fecho_mensal_contabilista_log add column if not exists nota_admin text;
alter table public.fecho_mensal_contabilista_log add column if not exists nota_admin_em timestamptz;
alter table public.fecho_mensal_contabilista_log add column if not exists nota_admin_por uuid;

create or replace function public.admin_fecho_contabilista_nota(p_year integer, p_month integer, p_nota text)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  if p_month not between 1 and 12 then raise exception 'mes_invalido'; end if;
  if length(coalesce(v_nota, '')) > 2000 then raise exception 'nota_longa_demais'; end if;
  insert into public.fecho_mensal_contabilista_log (ano, mes, nota_admin, nota_admin_em, nota_admin_por, updated_at)
  values (p_year, p_month, v_nota, now(), auth.uid(), now())
  on conflict (ano, mes) do update
     set nota_admin = excluded.nota_admin, nota_admin_em = excluded.nota_admin_em,
         nota_admin_por = excluded.nota_admin_por, updated_at = now();
  perform public.log_admin_action('fecho_contabilista_nota', 'fecho_mensal_contabilista',
                                  p_year || '-' || lpad(p_month::text, 2, '0'),
                                  jsonb_build_object('nota', v_nota));
  return jsonb_build_object('ok', true, 'ano', p_year, 'mes', p_month, 'nota', v_nota);
end $function$;

-- Reenvio manual pelo painel (botão "Reenviar ao contabilista"): chama a Edge com force:true, pelo mesmo
-- caminho do cron 125 (chave sb_secret_backend do cofre). Só admin.
create or replace function public.admin_fecho_contabilista_reenviar(p_year integer, p_month integer)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare v_req bigint; v_chave text;
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  if p_month not between 1 and 12 then raise exception 'mes_invalido'; end if;
  select decrypted_secret into v_chave from vault.decrypted_secrets where name = 'sb_secret_backend';
  select net.http_post(
           url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/fecho-mensal-contabilista',
           headers := jsonb_build_object('apikey', v_chave, 'Authorization', 'Bearer ' || v_chave,
                                         'Content-Type', 'application/json'),
           body := jsonb_build_object('year', p_year, 'month', p_month, 'force', true),
           timeout_milliseconds := 90000)
    into v_req;
  perform public.log_admin_action('fecho_contabilista_reenviar', 'fecho_mensal_contabilista',
                                  p_year || '-' || lpad(p_month::text, 2, '0'),
                                  jsonb_build_object('request_id', v_req));
  return jsonb_build_object('ok', true, 'request_id', v_req, 'ano', p_year, 'mes', p_month);
end $function$;

-- O conteúdo inteiro que vai ao contabilista (o mesmo do email e do painel), com o texto para copiar.
create or replace function public.admin_fecho_contabilista(p_year integer, p_month integer)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_f jsonb; v_p jsonb; v_x jsonb; v_falta jsonb; v_nota text; v_envio jsonb;
  v_l text[] := array[]::text[]; v_rub jsonb; v_tot jsonb; v_limp jsonb; v_fin jsonb; v_adq jsonb;
  v_total_bora numeric; v_lav numeric; v_marc numeric; r jsonb; v_nome_mes text;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or session_user = 'postgres') then
    raise exception 'admin_required';
  end if;
  v_f := public.admin_monthly_closeout(p_year, p_month);
  v_p := public.fecho_mensal_prestadores(p_year, p_month);
  v_x := public.fecho_contabilista_extras(p_year, p_month);
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_falta
    from jsonb_array_elements(public._dados_fiscais_linhas()) e where (e->>'em_falta')::boolean;
  select l.nota_admin,
         jsonb_build_object('estado', l.email_status, 'enviado_em', l.sent_at, 'erro', l.email_error, 'para', l.email_to)
    into v_nota, v_envio
    from public.fecho_mensal_contabilista_log l where l.ano = p_year and l.mes = p_month;

  v_nome_mes := v_f->'periodo'->>'nome';
  v_tot := v_f->'totais'; v_fin := v_f->'para_as_financas'; v_rub := v_fin->'rubricas';
  v_limp := v_f->'limpeza_totais'; v_adq := v_p->'adquirente';
  v_lav := coalesce((select sum((e->>'taxa_bora')::numeric) from jsonb_array_elements(v_p->'lavagem') e), 0);
  v_marc := coalesce((v_fin->>'receita_servicos')::numeric, 0);
  v_total_bora := (v_fin->>'total_a_declarar')::numeric + v_lav;

  v_l := v_l || format('Bora — fecho de %s de %s (para a contabilidade)', v_nome_mes, p_year);
  v_l := v_l || format('Entidade que recebeu e pagou neste mês: %s (NIF %s, %s).',
                       v_adq->>'nome', v_adq->>'nif', case when v_adq->>'tipo' = 'sociedade' then 'sociedade' else 'nome individual' end);
  v_l := v_l || ''::text;
  v_l := v_l || '1. RECEITA PRÓPRIA DA BORA (sem a mercadoria das lojas)'::text;
  v_l := v_l || ('- Taxa de entrega: ' || public._fecho_eur((v_rub->>'entrega')::numeric));
  v_l := v_l || ('- Taxa de serviço: ' || public._fecho_eur((v_rub->>'taxa_servico')::numeric));
  v_l := v_l || ('- Sacos: ' || public._fecho_eur((v_rub->>'sacos')::numeric));
  v_l := v_l || ('- Taxa de pedido pequeno: ' || public._fecho_eur((v_rub->>'taxa_pedido_pequeno')::numeric));
  v_l := v_l || ('- Parte da Bora nos produtos das lojas parceiras: ' || public._fecho_eur((v_rub->>'comissao_lojas_parceiras')::numeric));
  v_l := v_l || ('- Margem sobre compras em lojas não parceiras: ' || public._fecho_eur((v_rub->>'margem_nao_parceiros')::numeric));
  v_l := v_l || ('- Tokens descontados aos clientes nos pedidos: ' || public._fecho_eur((v_rub->>'tokens_descontados')::numeric));
  v_l := v_l || ('- Ajustes: ' || public._fecho_eur((v_rub->>'ajustes_descontos')::numeric));
  v_l := v_l || format('= Entregas e mercados (%s pedidos; clientes pagaram %s): %s',
                       v_tot->>'pedidos_entregues', public._fecho_eur((v_tot->>'pago_pelos_clientes')::numeric),
                       public._fecho_eur((v_fin->>'receita_propria')::numeric));
  v_l := v_l || format('- Limpeza — taxa da Bora (%s serviços; clientes pagaram %s): %s',
                       v_limp->>'servicos', public._fecho_eur((v_limp->>'pago_pelos_clientes')::numeric),
                       public._fecho_eur((v_limp->>'taxa_bora')::numeric));
  if v_lav > 0 then v_l := v_l || ('- Lavagem — taxa da Bora: ' || public._fecho_eur(v_lav)); end if;
  if v_marc > 0 then v_l := v_l || ('- Marcações — retido pela Bora: ' || public._fecho_eur(v_marc)); end if;
  v_l := v_l || ('= TOTAL RECEITA PRÓPRIA DA BORA: ' || public._fecho_eur(v_total_bora));
  v_l := v_l || format('Fora desta conta: mercadoria das lojas e mercados %s (pertence às lojas). Pago aos estafetas: %s. Sobra das entregas depois dos estafetas: %s.',
                       public._fecho_eur((v_tot->>'custo_mercadoria')::numeric), public._fecho_eur((v_tot->>'pago_a_estafetas')::numeric),
                       public._fecho_eur((v_tot->>'lucro')::numeric));
  v_l := v_l || ''::text;

  v_l := v_l || '2. FATURAÇÃO DA PARTE DA BORA (emitida pelo escritório do contabilista)'::text;
  v_l := v_l || format('- Consumidor final: %s (a parte da Bora toda; nas lojas parceiras fatura-se aos clientes, nunca às lojas).',
                       public._fecho_eur(v_total_bora));
  if jsonb_array_length(v_x->'pedidos_com_nif_do_cliente') > 0 then
    v_l := v_l || '- Destes, pedidos em que o cliente pediu fatura com NIF (a parte da Bora vai a esse NIF):'::text;
    for r in select * from jsonb_array_elements(v_x->'pedidos_com_nif_do_cliente') loop
      v_l := v_l || format('  · %s %s, NIF %s%s: parte da Bora %s (pedido %s)', r->>'data', r->>'loja', r->>'nif_cliente',
                           coalesce(' (' || (r->>'nome') || ')', ''), public._fecho_eur((r->>'parte_bora')::numeric), r->>'order_id');
    end loop;
  else
    v_l := v_l || '- Nenhum cliente pediu fatura com NIF neste mês.'::text;
  end if;
  v_l := v_l || ''::text;

  v_l := v_l || '3. PRESTADORES — cada um fatura a sua parte; o regime de IVA e a retenção de cada um são confirmados pelo contabilista'::text;
  v_l := v_l || ('Estafetas — total ' || public._fecho_eur((v_tot->>'pago_a_estafetas')::numeric));
  for r in select * from jsonb_array_elements(v_p->'estafetas') loop
    v_l := v_l || format('- %s%s: %s entregas, %s%s', r->>'nome', coalesce(' (NIF ' || (r->>'nif') || ')', ' (sem NIF)'),
                         r->>'entregas', public._fecho_eur((r->>'ganho')::numeric),
                         case when (r->>'proprio_adquirente')::boolean then ' — é o próprio Danilo' else '' end);
  end loop;
  if jsonb_array_length(v_p->'limpeza') > 0 then
    v_l := v_l || ('Limpeza — total ' || public._fecho_eur((v_limp->>'pago_prestadores')::numeric));
    for r in select * from jsonb_array_elements(v_p->'limpeza') loop
      v_l := v_l || format('- %s%s: %s serviços, %s (clientes pagaram %s: dinheiro %s, MB Way/cartão %s; taxa da Bora %s)',
                           r->>'nome', coalesce(' (NIF ' || (r->>'nif') || ')', ' (sem NIF)'), r->>'servicos',
                           public._fecho_eur((r->>'ganho')::numeric), public._fecho_eur((r->>'pago_pelos_clientes')::numeric),
                           public._fecho_eur((r->>'em_dinheiro')::numeric), public._fecho_eur((r->>'por_mbway_cartao')::numeric),
                           public._fecho_eur((r->>'taxa_bora')::numeric));
    end loop;
  end if;
  if jsonb_array_length(v_p->'lavagem') > 0 then
    v_l := v_l || 'Lavagem'::text;
    for r in select * from jsonb_array_elements(v_p->'lavagem') loop
      v_l := v_l || format('- %s%s: %s serviços, %s (taxa da Bora %s)', r->>'nome', coalesce(' (NIF ' || (r->>'nif') || ')', ' (sem NIF)'),
                           r->>'servicos', public._fecho_eur((r->>'ganho')::numeric), public._fecho_eur((r->>'taxa_bora')::numeric));
    end loop;
  end if;
  if jsonb_array_length(v_p->'lojas_parceiras') > 0 then
    v_l := v_l || 'Lojas parceiras — faturam o balcão aos clientes; não faturam à Bora nem recebem fatura da Bora'::text;
    for r in select * from jsonb_array_elements(v_p->'lojas_parceiras') loop
      v_l := v_l || format('- %s%s: %s pedido(s), vendas %s, parte da loja %s, parte da Bora %s (faturada aos clientes)',
                           r->>'nome', coalesce(' (NIF ' || (r->>'nif') || ')', ' (sem NIF)'), r->>'pedidos',
                           public._fecho_eur((r->>'vendas')::numeric), public._fecho_eur((r->>'parte_loja')::numeric),
                           public._fecho_eur((r->>'parte_bora')::numeric));
    end loop;
  end if;
  v_l := v_l || ''::text;

  v_l := v_l || '4. TOKENS, CÓDIGOS PROMOCIONAIS E PRÉMIOS'::text;
  v_l := v_l || format('- Tokens oferecidos aos clientes: %s tokens = %s (a %s cada). Oferecer não é custo: só passa a custo quando são usados.',
                       v_x->'tokens_oferecidos'->>'tokens', public._fecho_eur((v_x->'tokens_oferecidos'->>'valor')::numeric),
                       replace(rtrim(rtrim(v_x->'tokens_oferecidos'->>'valor_por_token', '0'), '.'), '.', ',') || ' €');
  for r in select * from jsonb_array_elements(v_x->'tokens_oferecidos'->'por_origem') loop
    v_l := v_l || format('  · %s: %s tokens (%s)', replace(r->>'origem', '_', ' '), r->>'tokens', public._fecho_eur((r->>'valor')::numeric));
  end loop;
  v_l := v_l || format('- Tokens descontados em pedidos: %s pedidos, %s (já estão na secção 1).',
                       v_x->'tokens_descontados_em_pedidos'->>'pedidos',
                       public._fecho_eur((v_x->'tokens_descontados_em_pedidos'->>'valor')::numeric));
  if jsonb_array_length(v_x->'codigos_promocionais') > 0 then
    for r in select * from jsonb_array_elements(v_x->'codigos_promocionais') loop
      v_l := v_l || format('- Código %s: %s usos, %s — %s', r->>'codigo', r->>'usos', public._fecho_eur((r->>'valor')::numeric), r->>'nota');
    end loop;
  else
    v_l := v_l || '- Nenhum código promocional usado.'::text;
  end if;
  v_l := v_l || format('- Prémios do check-in: %s emitidos (custo previsto %s), %s usados (custo %s).',
                       v_x->'premios_checkin'->>'emitidos', public._fecho_eur((v_x->'premios_checkin'->>'emitidos_custo')::numeric),
                       v_x->'premios_checkin'->>'usados', public._fecho_eur((v_x->'premios_checkin'->>'usados_custo')::numeric));
  v_l := v_l || ''::text;

  v_l := v_l || '5. CANCELAMENTOS E REEMBOLSOS'::text;
  v_l := v_l || format('- Pedidos cancelados: %s (valor %s; %s com cobrança feita; taxas de cancelamento %s).',
                       v_x->'cancelados_e_reembolsos'->>'cancelados',
                       public._fecho_eur((v_x->'cancelados_e_reembolsos'->>'cancelados_valor')::numeric),
                       v_x->'cancelados_e_reembolsos'->>'cancelados_com_cobranca',
                       public._fecho_eur((v_x->'cancelados_e_reembolsos'->>'taxas_de_cancelamento')::numeric));
  v_l := v_l || format('- Reembolsos: %s, total %s.', v_x->'cancelados_e_reembolsos'->>'reembolsados',
                       public._fecho_eur((v_x->'cancelados_e_reembolsos'->>'reembolsado_valor')::numeric));
  for r in select * from jsonb_array_elements(v_x->'cancelados_e_reembolsos'->'lista_reembolsos') loop
    v_l := v_l || format('  · %s %s: %s (%s, pedido %s)', r->>'data', coalesce(r->>'loja', ''), public._fecho_eur((r->>'valor')::numeric),
                         coalesce(r->>'meio', '?'), r->>'order_id');
  end loop;
  v_l := v_l || ''::text;

  v_l := v_l || '6. STRIPE — só a parte da Bora (sem TVDE, gorjetas nem serviços de sites)'::text;
  v_l := v_l || format('- Cobranças: %s, bruto %s, taxas da Stripe %s%s.',
                       v_x->'stripe_parte_bora'->>'cobrancas', public._fecho_eur((v_x->'stripe_parte_bora'->>'bruto')::numeric),
                       public._fecho_eur((v_x->'stripe_parte_bora'->>'taxas_a_considerar')::numeric),
                       case when v_x->'stripe_parte_bora'->>'fonte' = 'extrato_stripe' then ' (extrato da Stripe)'
                            else ' (estimativa pelos pedidos: o extrato da Stripe deste mês ainda não tem linhas)' end);
  v_l := v_l || ''::text;

  v_l := v_l || '7. PEDIDOS COM PREJUÍZO'::text;
  if jsonb_array_length(v_f->'pedidos_no_prejuizo') > 0 then
    for r in select * from jsonb_array_elements(v_f->'pedidos_no_prejuizo') loop
      v_l := v_l || format('- %s %s: resultado %s (pago %s, mercadoria %s, estafeta %s) — %s (pedido %s)',
                           r->>'data', r->>'loja', public._fecho_eur((r->>'resultado')::numeric), public._fecho_eur((r->>'pago')::numeric),
                           public._fecho_eur((r->>'mercadoria')::numeric), public._fecho_eur((r->>'estafeta')::numeric),
                           r->>'motivo', r->>'order_id');
    end loop;
  else
    v_l := v_l || '- Nenhum.'::text;
  end if;
  v_l := v_l || ''::text;

  v_l := v_l || '8. DADOS EM FALTA DE PRESTADORES E LOJAS (DAC7)'::text;
  if jsonb_array_length(v_falta) > 0 then
    for r in select * from jsonb_array_elements(v_falta) loop
      v_l := v_l || format('- %s (%s): falta %s', r->>'nome', replace(r->>'papel', '_', ' '),
                           (select string_agg(x, ', ') from jsonb_array_elements_text(r->'falta') x));
    end loop;
  else
    v_l := v_l || '- Nada em falta.'::text;
  end if;

  if v_nota is not null then
    v_l := v_l || ''::text;
    v_l := v_l || ('Nota do Danilo: ' || v_nota);
  end if;

  return jsonb_build_object(
    'periodo', v_f->'periodo',
    'entidade', v_adq,
    'receita', jsonb_build_object('rubricas', v_rub, 'entregas_e_mercados', v_fin->'receita_propria',
                                  'limpeza', v_limp, 'lavagem_taxa_bora', v_lav, 'marcacoes', v_marc,
                                  'total', v_total_bora, 'totais', v_tot - 'por_metodo'),
    'faturacao', v_fin->'faturas_recibo',
    'prestadores', jsonb_build_object('estafetas', v_p->'estafetas', 'limpeza', v_p->'limpeza',
                                      'lavagem', v_p->'lavagem', 'lojas_parceiras', v_p->'lojas_parceiras'),
    'extras', v_x,
    'pedidos_no_prejuizo', v_f->'pedidos_no_prejuizo',
    'dados_em_falta', v_falta,
    'nota_admin', v_nota,
    'envio', v_envio,
    'texto', array_to_string(v_l, E'\n'),
    'gerado_em', now());
end $function$;

-- ── D1: conferência pedido a pedido (só reporta; não corrige nada) ──────────────
create or replace function public.admin_fecho_conferencia(p_year integer, p_month integer)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_ini timestamptz; v_fim timestamptz; v_ped jsonb; v_limp jsonb; v_rub jsonb; v_tot jsonb;
  v_soma numeric; v_f jsonb; v_sem_valor jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or session_user = 'postgres') then
    raise exception 'admin_required';
  end if;
  select ini, fim into v_ini, v_fim from public._fecho_limites(p_year, p_month);

  -- Por pedido: pago real (dinheiro + Stripe − reembolso + carteira) contra o "pago" do fecho; o ganho do
  -- estafeta e a parte da loja contra o razão (ledger).
  with p as (
    select f.order_id, f.vendor_name, f.is_partner, f.payment_method, f.pago, f.estafeta, f.custo, f.custo_fonte,
           (f.payment_method = 'cash' and o.cash_total_due is null) sem_valor_dinheiro,
           -- Dinheiro sem valor registado (cash_total_due vazio): não há como conferir; fica numa lista à parte.
           case when f.payment_method = 'cash' and o.cash_total_due is null then f.pago
                -- Stripe: tira a gorjeta cobrada junto com o pedido (tips.cobrada_junto), que é do estafeta.
                else round((case when f.payment_method = 'cash' then o.cash_total_due::numeric
                                 else coalesce(o.stripe_charge_cents, 0) / 100.0 - coalesce(o.refund_amount, 0)::numeric
                                      - coalesce((select sum(t.amount_cents) from public.tips t
                                                   where t.order_id = f.order_id and t.cobrada_junto and t.status = 'succeeded'), 0) / 100.0 end
                            + coalesce(o.wallet_applied_cents, 0) / 100.0)::numeric, 2) end pago_real,
           (select round(sum(l.amount)::numeric, 2) from public.ledger_entries l
             where l.order_id::text = f.order_id and l.user_type = 'driver' and l.type = 'earning') ledger_estafeta,
           (select round(sum(l.amount)::numeric, 2) from public.ledger_entries l
             where l.order_id::text = f.order_id and l.user_type = 'restaurant' and l.type = 'earning') ledger_loja
      from public._fecho_pedidos(v_ini, v_fim) f
      join public.orders o on o.id = f.order_id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_id', p.order_id, 'loja', p.vendor_name, 'meio', p.payment_method,
           'pago_fecho', p.pago, 'pago_real', p.pago_real, 'dif_pago', round(p.pago_real - p.pago, 2),
           'estafeta_pedido', p.estafeta, 'estafeta_ledger', p.ledger_estafeta,
           'dif_estafeta', round(coalesce(p.ledger_estafeta, 0) - p.estafeta, 2),
           'loja_fecho', case when p.is_partner then p.custo end, 'loja_ledger', p.ledger_loja,
           'dif_loja', case when p.is_partner then round(coalesce(p.ledger_loja, 0) - p.custo, 2) end)
         order by p.order_id) filter (where abs(p.pago_real - p.pago) >= 0.01
                                       or abs(coalesce(p.ledger_estafeta, 0) - p.estafeta) >= 0.01
                                       or (p.is_partner and abs(coalesce(p.ledger_loja, 0) - p.custo) >= 0.01)), '[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('order_id', p.order_id, 'loja', p.vendor_name, 'pago_fecho', p.pago)
                            order by p.order_id) filter (where p.sem_valor_dinheiro), '[]'::jsonb)
    into v_ped, v_sem_valor
    from p;

  select coalesce(jsonb_agg(jsonb_build_object(
           'booking_id', c.id, 'total', round(c.total_cents / 100.0, 2),
           'profissional', round(c.cleaner_earnings_cents / 100.0, 2), 'taxa_bora', round(c.bora_fee_cents / 100.0, 2),
           'dif', round((c.total_cents - c.cleaner_earnings_cents - c.bora_fee_cents) / 100.0, 2)) order by c.scheduled_at), '[]'::jsonb)
    into v_limp
    from public.cleaning_bookings c
   where c.status in ('completed','done') and coalesce(c.is_test_order, false) = false
     and c.scheduled_at >= v_ini and c.scheduled_at < v_fim
     and abs(coalesce(c.total_cents, 0) - coalesce(c.cleaner_earnings_cents, 0) - coalesce(c.bora_fee_cents, 0)) >= 1;

  v_f := public.admin_monthly_closeout(p_year, p_month);
  v_rub := v_f->'para_as_financas'->'rubricas'; v_tot := v_f->'totais';
  select coalesce(sum(value::numeric), 0) into v_soma from jsonb_each_text(v_rub);

  return jsonb_build_object(
    'periodo', jsonb_build_object('ano', p_year, 'mes', p_month),
    'pedidos_com_diferenca', v_ped,
    'dinheiro_sem_valor_registado', v_sem_valor,
    'limpezas_com_diferenca', v_limp,
    'soma_rubricas', v_soma, 'receita_propria', (v_tot->>'receita_propria_bora')::numeric,
    'rubricas_batem', abs(v_soma - (v_tot->>'receita_propria_bora')::numeric) < 0.01,
    'lucro_bate', abs((v_tot->>'pago_pelos_clientes')::numeric - (v_tot->>'custo_mercadoria')::numeric
                      - (v_tot->>'pago_a_estafetas')::numeric - (v_tot->>'lucro')::numeric) < 0.01,
    'nota', 'Só reporta. Nenhuma linha de dinheiro é corrigida por esta função.',
    'gerado_em', now());
end $function$;

-- ── permissões: fechadas a anon; admin entra pelo is_admin() de dentro ──────────
revoke all on function public._fecho_eur(numeric) from public, anon;
revoke all on function public._fecho_tokens_descontados(integer, numeric, numeric, numeric) from public, anon;
grant execute on function public._fecho_tokens_descontados(integer, numeric, numeric, numeric) to authenticated, service_role;
revoke all on function public._dados_fiscais_linhas() from public, anon, authenticated;
revoke all on function public.fecho_contabilista_extras(integer, integer) from public, anon;
revoke all on function public.admin_prestadores_dados_fiscais() from public, anon;
revoke all on function public.meus_dados_fiscais_em_falta() from public, anon;
revoke all on function public.admin_fecho_contabilista_nota(integer, integer, text) from public, anon;
revoke all on function public.admin_fecho_contabilista_reenviar(integer, integer) from public, anon;
revoke all on function public.admin_fecho_contabilista(integer, integer) from public, anon;
revoke all on function public.admin_fecho_conferencia(integer, integer) from public, anon;
grant execute on function public._fecho_eur(numeric) to authenticated, service_role;
grant execute on function public._dados_fiscais_linhas() to service_role;
grant execute on function public.fecho_contabilista_extras(integer, integer) to authenticated, service_role;
grant execute on function public.admin_prestadores_dados_fiscais() to authenticated, service_role;
grant execute on function public.meus_dados_fiscais_em_falta() to authenticated, service_role;
grant execute on function public.admin_fecho_contabilista_nota(integer, integer, text) to authenticated, service_role;
grant execute on function public.admin_fecho_contabilista_reenviar(integer, integer) to authenticated, service_role;
grant execute on function public.admin_fecho_contabilista(integer, integer) to authenticated, service_role;
grant execute on function public.admin_fecho_conferencia(integer, integer) to authenticated, service_role;
