-- 01/11/2026 (missão contabilista-2026-11-01) — EXTRATO DA STRIPE PARA O CONTABILISTA.
-- Porquê: o Danilo nunca declarou o que passou pela conta Stripe do Bora desde o início; o Hugo
-- (contabilista) precisa de um resumo por mês e por tipo. A Edge Function stripe-relatorio-contabilista
-- lê balance_transactions da Stripe e guarda aqui uma linha por movimento (idempotente por bt_id).
-- Só admins leem (is_admin()); anon e authenticated sem acesso. Escreve só o servidor (chave secreta).

create table if not exists public.stripe_extrato_contabilista (
  bt_id             text primary key,                 -- txn_… da Stripe (balance transaction)
  tipo_stripe       text not null,                    -- charge | payment | refund | payout | stripe_fee | adjustment | …
  objeto_id         text,                             -- ch_… / re_… / po_… / py_…
  payment_intent    text,                             -- pi_… quando existe
  criado_em         timestamptz not null,             -- created da balance transaction
  disponivel_em     timestamptz,                      -- available_on
  mes               text not null,                    -- 'YYYY-MM' em Europe/Lisbon
  categoria         text not null,                    -- entregas_mercados | tvde | limpeza | reservas | lavagem | gorjetas | servicos_site | outros | payout | taxa_stripe
  categoria_fonte   text,                             -- metadata.kind | order_id | descricao | cliente | sem_pista
  descricao         text,
  cliente_nome      text,
  cliente_email     text,
  moeda             text not null default 'eur',
  bruto_cents       bigint not null default 0,        -- amount (negativo em reembolsos/payouts)
  taxa_cents        bigint not null default 0,        -- fee
  liquido_cents     bigint not null default 0,        -- net
  estado            text,                             -- available | pending
  metadata          jsonb not null default '{}'::jsonb,
  entidade_tipo     text,                             -- order | tvde_ride | cleaning_booking | carwash_booking | appointment | tip | tvde_subscription
  entidade_id       text,
  cruzado_em        timestamptz,
  atualizado_em     timestamptz not null default now(),
  categoria_manual  text,                             -- fixada à mão pelo admin; a Edge Function nunca escreve aqui
  nota_manual       text
);

create index if not exists stripe_extrato_contabilista_mes_idx on public.stripe_extrato_contabilista (mes, categoria);
create index if not exists stripe_extrato_contabilista_pi_idx on public.stripe_extrato_contabilista (payment_intent);

alter table public.stripe_extrato_contabilista enable row level security;
revoke all on public.stripe_extrato_contabilista from public, anon, authenticated;

drop policy if exists stripe_extrato_contabilista_admin_le on public.stripe_extrato_contabilista;
create policy stripe_extrato_contabilista_admin_le on public.stripe_extrato_contabilista
  for select to authenticated using (public.is_admin());
-- (sem grant a authenticated: a política só vale para quem o painel admin deixar passar por RPC;
--  o painel lê pela função abaixo, security definer, que exige is_admin()).

comment on table public.stripe_extrato_contabilista is
  'Extrato da conta Stripe do Bora, uma linha por balance transaction, para o contabilista. Escrito pela Edge Function stripe-relatorio-contabilista. Só admins (is_admin()).';

-- Cruzamento com a base: liga cada pagamento ao pedido/corrida/marcação de onde veio, para dizer
-- ao contabilista "o que cada mês foi". Só lê; nunca toca nas tabelas de produção.
create or replace function public.stripe_extrato_cruzar_base()
returns integer
language plpgsql security definer set search_path = public
as $$
declare n integer := 0;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or current_user in ('postgres','service_role')) then
    raise exception 'admin_required';
  end if;

  -- pedidos de entregas/mercados
  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'order', entidade_id = o.id::text,
         categoria = case when x.categoria in ('outros','entregas_mercados') then 'entregas_mercados' else x.categoria end,
         categoria_fonte = coalesce(x.categoria_fonte, 'base:orders'), cruzado_em = now()
    from public.orders o
   where x.payment_intent is not null and o.payment_intent_id = x.payment_intent and x.entidade_tipo is null;
  get diagnostics n = row_count;

  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'tvde_ride', entidade_id = t.id::text,
         categoria = 'tvde', categoria_fonte = coalesce(x.categoria_fonte, 'base:tvde_rides'), cruzado_em = now()
    from public.tvde_rides t
   where x.payment_intent is not null and t.payment_intent_id = x.payment_intent and x.entidade_tipo is null;

  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'tvde_subscription', entidade_id = s.id::text,
         categoria = 'tvde', categoria_fonte = coalesce(x.categoria_fonte, 'base:tvde_subscriptions'), cruzado_em = now()
    from public.tvde_subscriptions s
   where x.payment_intent is not null and s.stripe_payment_intent_id = x.payment_intent and x.entidade_tipo is null;

  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'cleaning_booking', entidade_id = c.id::text,
         categoria = 'limpeza', categoria_fonte = coalesce(x.categoria_fonte, 'base:cleaning_bookings'), cruzado_em = now()
    from public.cleaning_bookings c
   where x.payment_intent is not null and c.stripe_payment_intent_id = x.payment_intent and x.entidade_tipo is null;

  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'carwash_booking', entidade_id = w.id::text,
         categoria = 'lavagem', categoria_fonte = coalesce(x.categoria_fonte, 'base:carwash_bookings'), cruzado_em = now()
    from public.carwash_bookings w
   where x.payment_intent is not null and w.stripe_payment_intent_id = x.payment_intent and x.entidade_tipo is null;

  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'appointment', entidade_id = a.id::text,
         categoria = 'reservas', categoria_fonte = coalesce(x.categoria_fonte, 'base:appointments'), cruzado_em = now()
    from public.appointments a
   where x.payment_intent is not null and x.payment_intent in (a.deposit_pi, a.full_payment_pi) and x.entidade_tipo is null;

  update public.stripe_extrato_contabilista x
     set entidade_tipo = 'tip', entidade_id = tp.id::text,
         categoria = 'gorjetas', categoria_fonte = coalesce(x.categoria_fonte, 'base:tips'), cruzado_em = now()
    from public.tips tp
   where x.payment_intent is not null and tp.stripe_payment_intent_id = x.payment_intent and x.entidade_tipo is null;

  return n;
end $$;
revoke all on function public.stripe_extrato_cruzar_base() from public, anon;

-- Resumo por mês e tipo (o que o painel/contabilista lê). Exige admin. Usa coalesce(categoria_manual, categoria).
create or replace function public.stripe_extrato_resumo(p_desde text default null, p_ate text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_meses jsonb; v_tipos jsonb; v_tot jsonb; v_notas jsonb;
begin
  if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role'
          or current_user in ('postgres','service_role')) then
    raise exception 'admin_required';
  end if;

  with b as (
    select * from public.stripe_extrato_contabilista
     where (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate)
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
   where (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate);

  select coalesce(jsonb_agg(jsonb_build_object('mes', mes, 'dia', criado_em::date, 'valor', round(bruto_cents/100.0,2),
           'cliente', cliente_nome, 'categoria', coalesce(categoria_manual, categoria), 'nota', nota_manual) order by criado_em), '[]'::jsonb)
    into v_notas
    from public.stripe_extrato_contabilista
   where nota_manual is not null and tipo_stripe in ('charge','payment')
     and (p_desde is null or mes >= p_desde) and (p_ate is null or mes <= p_ate);

  return jsonb_build_object('por_mes', v_meses, 'por_mes_e_tipo', v_tipos, 'totais', v_tot, 'linhas_com_nota', v_notas, 'gerado_em', now());
end $$;
revoke all on function public.stripe_extrato_resumo(text, text) from public, anon;

-- Categorias fixadas à mão a 01/11/2026 depois da 1.ª leitura (294 linhas): pagamentos por link do Jai/Guarda FC
-- (site), contas semanais Jai/Vansh de 27/10 e sinais de reserva de mai/2026. Ver página do livro
-- stripe-declaracao-2026-11-01. (Aplicado em produção por UPDATE; aqui fica só o registo.)
