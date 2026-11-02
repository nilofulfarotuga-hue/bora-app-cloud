-- 02/11/2026 00:20 Claude.ai: RE-APLICADA por MCP. A RPC fecho_mensal_prestadores faltava em produção (a 20261101215000 ficou aplicada sem ela e sem registo; o reenvio de outubro falhou na limpeza, e2e 6092).
-- Texto igual ao da 20261101215000. Prova: fecho_mensal_prestadores(2026,10) -> Mayra 5 limpezas 167,79; reenvio sem force (pedido 93610) -> Mayra sent, os outros ja_enviado.
create or replace function public.fecho_mensal_prestadores(p_year integer, p_month integer)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_ini timestamptz; v_fim timestamptz; v_nome_mes text;
  v_adq jsonb; v_estafetas jsonb; v_limpeza jsonb; v_lavagem jsonb; v_tvde jsonb; v_lojas jsonb;
  v_excluir jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or current_user in ('postgres','service_role')) then
    raise exception 'admin_required';
  end if;
  if p_month not between 1 and 12 then raise exception 'mes_invalido'; end if;
  select ini, fim into v_ini, v_fim from public._fecho_limites(p_year, p_month);
  v_nome_mes := (array['janeiro','fevereiro','março','abril','maio','junho','julho',
                       'agosto','setembro','outubro','novembro','dezembro'])[p_month];

  -- adquirente dos recibos: até outubro/2026 o Danilo em nome individual (platform_settings
  -- fecho_entidade_*); de novembro/2026 em diante a sociedade (a empresa começa a cobrar em novembro).
  -- Mesma regra de driver_monthly_invoice_summary.
  if (p_year, p_month) >= (2026, 11) then
    v_adq := jsonb_build_object('tipo', 'sociedade', 'nome', 'Danilo Fulfaro da Silva - Unipessoal Lda',
      'nif', '519686233', 'morada', 'Rua do Torreão 14, 6300-610 Guarda',
      'retencao', 'Retenção na fonte de IRS (art. 101.º CIRS) se o prestador não estiver dispensado (art. 101.º-B: dispensa até 15.000 €/ano)');
  else
    v_adq := jsonb_build_object(
      'tipo',   coalesce((select value #>> '{}' from platform_settings where key='fecho_entidade_tipo'), 'individual'),
      'nome',   coalesce(nullif((select value #>> '{}' from platform_settings where key='fecho_entidade_nome'), ''), 'Danilo Fulfaro da Silva'),
      'nif',    coalesce(nullif((select value #>> '{}' from platform_settings where key='fecho_entidade_nif'), ''), '322151171'),
      'morada', coalesce(nullif((select value #>> '{}' from platform_settings where key='fecho_entidade_morada'), ''), 'Rua do Torreão 14, 6300-610 Guarda'),
      'retencao', 'Sem retenção: o adquirente é um particular sem contabilidade organizada');
  end if;
  v_adq := v_adq || jsonb_build_object(
    'iva_prestador', 'Isento art. 53.º CIVA quando o prestador está nesse regime; senão IVA 23%',
    'prazo', 'Fatura-recibo até ao 5.º dia útil seguinte ao recebimento (art. 36.º CIVA / art. 115.º CIRS)',
    'descricao_sugerida', 'Serviços prestados em ' || v_nome_mes || ' de ' || p_year || ' através da plataforma Bora');

  v_excluir := coalesce((select value from platform_settings where key = 'fecho_tvde_excluir_emails'), '[]'::jsonb);

  -- estafetas (entregas): o que a plataforma lhes pagou no mês (mesma conta do admin_monthly_closeout)
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

  -- limpeza
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

  -- lavagem
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

  -- TVDE de outros motoristas: SÓ INFORMATIVO (regra do Danilo: o TVDE de passageiros fica fora da
  -- declaração da Bora). As do próprio Danilo e as de teste ficam fora.
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_id, 'nome', coalesce(d.legal_name, d.name, u.email), 'nif', d.nif,
           'corridas', x.n, 'ganho_motorista', x.ganho, 'parte_bora', x.bora, 'em_dinheiro', x.cash,
           'nota', 'Fora da declaração da Bora (TVDE de passageiros).')
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

  -- lojas parceiras: a Bora fatura-lhes a comissão (não passam recibo à Bora)
  with fm as (select * from public._fecho_pedidos(v_ini, v_fim))
  select coalesce(jsonb_agg(jsonb_build_object(
           'partner_id', x.restaurant_id, 'nome', coalesce(r.name, x.nome), 'nif', r.nif, 'email', r.email,
           'pedidos', x.n, 'vendas', x.vendas, 'comissao_bora', x.comissao, 'parte_loja', x.parte,
           'fatura_bora', jsonb_build_object('valor', x.comissao, 'descricao', 'Comissão de intermediação — pedidos pela plataforma Bora (' || v_nome_mes || ' ' || p_year || ')'))
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
end $$;
revoke all on function public.fecho_mensal_prestadores(integer, integer) from public, anon;
