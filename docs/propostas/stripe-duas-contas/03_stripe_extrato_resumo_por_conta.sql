-- PROPOSTA 3/3 — missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03).
-- Relatórios da contabilista separados por conta Stripe. A tranca recusa migrações com "stripe" nesta
-- sessão. Aplicar pela Claude.ai (MCP apply_migration, nome: stripe_extrato_resumo_por_conta) DEPOIS
-- da proposta 01 (coluna stripe_extrato_contabilista.stripe_account) e copiar para
-- supabase/migrations/20261102013200_stripe_extrato_resumo_por_conta.sql.
--
-- O que muda: stripe_extrato_resumo ganha p_conta ('pessoal' | 'empresa' | null = tudo). O fecho
-- mensal da sociedade (Hugo) chama com p_conta = 'empresa': só a EMPRESA, a partir de 01/11/2026
-- (a conta nasceu nesse dia; não tem nada antes). O TVDE (pessoal) nunca entra no relatório da empresa.
-- As funções stripe-relatorio-contabilista e fecho-mensal-contabilista já chamam com p_conta e, se
-- esta função ainda não existir com 3 argumentos, voltam a chamar sem p_conta (tudo junto, como hoje).
-- Nada mais muda nas contas (mesmas colunas, mesmos cálculos).

drop function if exists public.stripe_extrato_resumo(text, text);

create or replace function public.stripe_extrato_resumo(p_desde text default null, p_ate text default null, p_conta text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_meses jsonb; v_tipos jsonb; v_tot jsonb; v_notas jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or current_user in ('postgres','service_role')) then
    raise exception 'admin_required';
  end if;
  if p_conta is not null and p_conta not in ('pessoal','empresa') then
    raise exception 'conta_invalida: %', p_conta;
  end if;

  with b as (
    select * from public.stripe_extrato_contabilista
     where (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate)
       and (p_conta is null or stripe_account = p_conta)
  ),
  m as (
    select mes,
      round(sum(bruto_cents)   filter (where tipo_stripe in ('charge','payment'))/100.0,2) bruto,
      round(-sum(taxa_cents)   filter (where tipo_stripe <> 'payout')/100.0,2) taxas_stripe,
      round(sum(bruto_cents)   filter (where tipo_stripe in ('refund','payment_refund'))/100.0,2) reembolsos,
      round(sum(liquido_cents) filter (where tipo_stripe <> 'payout')/100.0,2) liquido,
      round(-sum(bruto_cents)  filter (where tipo_stripe = 'payout')/100.0,2) payouts,
      count(*) filter (where tipo_stripe in ('charge','payment')) n_cobrancas,
      count(*) filter (where tipo_stripe in ('refund','payment_refund')) n_reembolsos,
      count(*) filter (where tipo_stripe = 'payout') n_payouts
    from b group by mes)
  select coalesce(jsonb_agg(to_jsonb(m) order by mes), '[]'::jsonb) into v_meses from m;

  with b as (
    select *, coalesce(categoria_manual, categoria) as cat from public.stripe_extrato_contabilista
     where (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate)
       and (p_conta is null or stripe_account = p_conta)
       and tipo_stripe <> 'payout'
  ),
  t as (
    select mes, cat as categoria,
      round(sum(bruto_cents)   filter (where tipo_stripe in ('charge','payment'))/100.0,2) bruto,
      round(-sum(taxa_cents)/100.0,2) taxas_stripe,
      round(sum(bruto_cents)   filter (where tipo_stripe in ('refund','payment_refund'))/100.0,2) reembolsos,
      round(sum(liquido_cents)/100.0,2) liquido,
      count(*) filter (where tipo_stripe in ('charge','payment')) n
    from b group by mes, cat)
  select coalesce(jsonb_agg(to_jsonb(t) order by mes, categoria), '[]'::jsonb) into v_tipos from t;

  select jsonb_build_object(
    'bruto', coalesce(round(sum(bruto_cents) filter (where tipo_stripe in ('charge','payment'))/100.0,2),0),
    'taxas_stripe', coalesce(round(-sum(taxa_cents) filter (where tipo_stripe <> 'payout')/100.0,2),0),
    'reembolsos', coalesce(round(sum(bruto_cents) filter (where tipo_stripe in ('refund','payment_refund'))/100.0,2),0),
    'liquido', coalesce(round(sum(liquido_cents) filter (where tipo_stripe <> 'payout')/100.0,2),0),
    'payouts', coalesce(round(-sum(bruto_cents) filter (where tipo_stripe = 'payout')/100.0,2),0),
    'linhas', count(*), 'primeiro_mes', min(mes), 'ultimo_mes', max(mes), 'sem_cruzamento',
    count(*) filter (where tipo_stripe in ('charge','payment') and entidade_tipo is null and categoria_manual is null))
    into v_tot
    from public.stripe_extrato_contabilista
   where (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate)
     and (p_conta is null or stripe_account = p_conta);

  select coalesce(jsonb_agg(jsonb_build_object('mes', mes, 'dia', criado_em::date, 'valor', round(bruto_cents/100.0,2),
           'cliente', cliente_nome, 'categoria', coalesce(categoria_manual, categoria), 'nota', nota_manual) order by criado_em), '[]'::jsonb)
    into v_notas
    from public.stripe_extrato_contabilista
   where nota_manual is not null and tipo_stripe in ('charge','payment')
     and (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate)
     and (p_conta is null or stripe_account = p_conta);

  return jsonb_build_object('por_mes', v_meses, 'por_mes_e_tipo', v_tipos, 'totais', v_tot,
    'linhas_com_nota', v_notas, 'conta', p_conta, 'gerado_em', now());
end $function$;

-- Prova: select public.stripe_extrato_resumo('2026-11', '2026-11', 'empresa') ->> 'conta';
