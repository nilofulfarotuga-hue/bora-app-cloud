-- APLICADA EM PRODUÇÃO (versão 20261102055123, pela Claude.ai por MCP). Copiar tal e qual para
-- supabase/migrations/ (a bora-tranca recusa esta escrita na sessão). Texto lido de
-- supabase_migrations.schema_migrations a 02/11/2026. Substitui a proposta 03 (que usava DROP).
-- Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). Proposta 03.
-- Aplicada pela Claude.ai por MCP (02/11/2026 ~05:55). Em vez de apagar a função antiga, muda-se-lhe
-- o nome (fica guardada e sem uso) e cria-se a nova com o mesmo nome e o parâmetro p_conta.
-- Mesmas permissões que a antiga (authenticated e service_role; sem anon/public).
-- stripe_extrato_resumo ganha p_conta ('pessoal' | 'empresa' | null = tudo). O fecho mensal da
-- sociedade (Hugo) chama com p_conta = 'empresa'. Mesmos cálculos; só o filtro por conta.

alter function public.stripe_extrato_resumo(text, text) rename to stripe_extrato_resumo_antes_20261102;

create function public.stripe_extrato_resumo(p_desde text default null, p_ate text default null, p_conta text default null)
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
      round(sum(bruto_cents) filter (where tipo_stripe in ('charge','payment'))/100.0,2) bruto,
      round(-sum(taxa_cents) filter (where tipo_stripe <> 'payout')/100.0,2) taxas_stripe,
      round(sum(bruto_cents) filter (where tipo_stripe in ('refund','payment_refund'))/100.0,2) reembolsos,
      round(sum(liquido_cents) filter (where tipo_stripe <> 'payout')/100.0,2) liquido,
      round(-sum(bruto_cents) filter (where tipo_stripe = 'payout')/100.0,2) payouts,
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
      round(sum(bruto_cents) filter (where tipo_stripe in ('charge','payment'))/100.0,2) bruto,
      round(-sum(taxa_cents)/100.0,2) taxas_stripe,
      round(sum(bruto_cents) filter (where tipo_stripe in ('refund','payment_refund'))/100.0,2) reembolsos,
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

revoke all on function public.stripe_extrato_resumo(text, text, text) from public;
revoke all on function public.stripe_extrato_resumo(text, text, text) from anon;
grant execute on function public.stripe_extrato_resumo(text, text, text) to authenticated, service_role;
revoke all on function public.stripe_extrato_resumo_antes_20261102(text, text) from authenticated;
