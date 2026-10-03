-- 2026-10-03 — Cartão no iPhone ficava só a rodar (Divan, 02/10).
--
-- Causa (app iOS): o plugin do Stripe procura a janela em AppDelegate.window,
-- que com UIScene fica vazia — a folha do cartão era apresentada a partir de
-- um ecrã solto, nunca aparecia e o pagamento ficava em
-- requires_payment_method. O conserto nativo está em ios/Runner/AppDelegate.swift.
--
-- Isto aqui é a rede de segurança para nunca mais falhar em silêncio:
--   1. payment_client_failures — cada vez que a folha do cartão não abre ou
--      falha, a app grava aqui (plataforma, fase, erro real).
--   2. log_payment_failure() — a porta única para gravar; avisa o Danilo no
--      Telegram (no máximo 1 aviso por cliente a cada 10 minutos).
--   3. platform_settings.payment_sheet_timeout_seconds = 20 — tempo máximo
--      para a folha do cartão aparecer.
--   4. admin_pagamentos_presos(p_dias) — lista para o painel admin: pagamentos
--      com cartão parados em requires_payment_method / requires_action, com a
--      plataforma do cliente e o último erro gravado.
--
-- Não mexe em valores cobrados nem em tabelas financeiras (só lê).

create table if not exists public.payment_client_failures (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid default auth.uid(),
  vertical text,
  referencia_id text,
  payment_intent_id text,
  platform text,
  app_version text,
  stage text,
  error_message text
);

create index if not exists payment_client_failures_created_idx
  on public.payment_client_failures (created_at desc);
create index if not exists payment_client_failures_pi_idx
  on public.payment_client_failures (payment_intent_id);

alter table public.payment_client_failures enable row level security;

create policy payment_client_failures_admin_read on public.payment_client_failures
  for select to authenticated using (public.is_admin());

revoke all on public.payment_client_failures from public, anon, authenticated;
grant select on public.payment_client_failures to authenticated;

create or replace function public.log_payment_failure(
  p_vertical text,
  p_referencia_id text,
  p_payment_intent_id text,
  p_platform text,
  p_app_version text,
  p_stage text,
  p_error_message text
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_recent int;
begin
  insert into public.payment_client_failures
    (user_id, vertical, referencia_id, payment_intent_id, platform, app_version, stage, error_message)
  values
    (v_uid, left(p_vertical, 60), left(p_referencia_id, 120), left(p_payment_intent_id, 120),
     left(p_platform, 30), left(p_app_version, 40), left(p_stage, 60), left(p_error_message, 2000));

  -- Telegram: 1 aviso por cliente (ou por anónimo) a cada 10 minutos.
  select count(*) into v_recent
    from public.payment_client_failures
   where user_id is not distinct from v_uid
     and created_at > now() - interval '10 minutes';
  if v_recent <= 1 then
    perform public._telegram_admin(
      'Pagamento com cartão falhou na app (' || coalesce(p_platform, '?') || ', ' ||
      coalesce(p_vertical, '?') || ', fase ' || coalesce(p_stage, '?') || '): ' ||
      left(coalesce(p_error_message, ''), 300) ||
      '. Ver no painel: Operação → Pagamentos presos.');
  end if;
exception when others then
  -- Gravar o erro nunca pode partir o fluxo do cliente.
  null;
end;
$$;

revoke all on function public.log_payment_failure(text, text, text, text, text, text, text) from public;
grant execute on function public.log_payment_failure(text, text, text, text, text, text, text) to anon, authenticated;

insert into public.platform_settings (key, value, description, category)
values ('payment_sheet_timeout_seconds', '20'::jsonb,
        'Segundos máximos para o ecrã do cartão (Stripe) aparecer. Passado isto a app mostra erro e oferece MB Way/dinheiro.',
        'pagamentos_app')
on conflict (key) do nothing;

create or replace function public.admin_pagamentos_presos(p_dias int default 14)
returns table (
  vertical text,
  referencia_id text,
  created_at timestamptz,
  status text,
  payment_status text,
  payment_intent_id text,
  valor_cents bigint,
  cliente_id text,
  cliente_nome text,
  cliente_contacto text,
  plataforma text,
  ultimo_erro text,
  ultimo_erro_em timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'apenas admin';
  end if;

  return query
  with base as (
    select 'tvde'::text v, r.id::text ref, r.created_at ca, r.status::text st, r.payment_status::text ps,
           r.payment_intent_id::text pi, coalesce(r.final_fare_cents, r.est_fare_cents)::bigint val,
           r.client_id::text cli
      from tvde_rides r
     where r.payment_method = 'card'
       and r.payment_status in ('requires_payment_method', 'requires_action', 'requires_confirmation')
       and r.created_at > now() - make_interval(days => p_dias)
    union all
    select 'entrega', o.id::text, o.created_at, o.status::text, o.payment_status::text,
           o.payment_intent_id::text, round(coalesce(o.customer_total, o.total, 0) * 100)::bigint, o.user_id::text
      from orders o
     where o.payment_method ilike '%card%'
       and o.payment_status in ('requires_payment_method', 'requires_action', 'requires_confirmation')
       and o.created_at > now() - make_interval(days => p_dias)
    union all
    select 'limpeza', c.id::text, c.created_at, c.status::text, c.payment_status::text,
           c.stripe_payment_intent_id::text, c.total_cents::bigint, c.client_user_id::text
      from cleaning_bookings c
     where c.payment_method ilike '%card%'
       and c.payment_status in ('requires_payment_method', 'requires_action', 'requires_confirmation')
       and c.created_at > now() - make_interval(days => p_dias)
    union all
    select 'lavagem', w.id::text, w.created_at, w.status::text, w.payment_status::text,
           w.stripe_payment_intent_id::text, w.total_cents::bigint, w.client_user_id::text
      from carwash_bookings w
     where w.payment_method ilike '%card%'
       and w.payment_status in ('requires_payment_method', 'requires_action', 'requires_confirmation')
       and w.created_at > now() - make_interval(days => p_dias)
  )
  select b.v, b.ref, b.ca, b.st, b.ps, b.pi, b.val, b.cli,
         u.name, coalesce(u.phone, u.email), u.platform,
         f.error_message, f.created_at
    from base b
    left join users u on u.id::text = b.cli
    left join lateral (
      select pf.error_message, pf.created_at
        from payment_client_failures pf
       where (pf.payment_intent_id is not null and pf.payment_intent_id = b.pi)
          or (pf.referencia_id is not null and pf.referencia_id = b.ref)
       order by pf.created_at desc
       limit 1
    ) f on true
  union all
  -- Falhas gravadas pela app que não casam com nenhum pedido (ex.: a folha
  -- nem chegou a abrir antes de haver pedido).
  select pf.vertical, pf.referencia_id, pf.created_at, null::text, 'falha_app'::text,
         pf.payment_intent_id, null::bigint, pf.user_id::text,
         u2.name, coalesce(u2.phone, u2.email), pf.platform,
         pf.error_message, pf.created_at
    from payment_client_failures pf
    left join users u2 on u2.id = pf.user_id
   where pf.created_at > now() - make_interval(days => p_dias)
     and not exists (select 1 from base b2
                      where (pf.payment_intent_id is not null and b2.pi = pf.payment_intent_id)
                         or (pf.referencia_id is not null and b2.ref = pf.referencia_id))
  order by 3 desc;
end;
$$;

revoke all on function public.admin_pagamentos_presos(int) from public, anon;
grant execute on function public.admin_pagamentos_presos(int) to authenticated;
