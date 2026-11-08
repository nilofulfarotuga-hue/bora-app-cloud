-- =============================================================================
-- M7 (08/11/2026) — Stripe Connect na conta da EMPRESA (acct_1UX67LGWwQxC9wR2).
-- PROPOSTA: não aplicada pela sessão do PC (modo automático seguro). Aplica a Claude.ai.
-- Idempotente: pode correr 2 vezes sem estragar nada. Não mexe em dinheiro, não apaga nada.
--
-- O que faz:
--   1) coluna stripe_account_owner ('pessoal' | 'empresa') nas 4 tabelas com conta Connect;
--      as contas que já existem ficam 'pessoal' (é onde foram criadas, na Stripe antiga).
--   2) tabela connect_convites: link de cadastro PERMANENTE por parceiro/estafeta
--      (o link da Stripe expira em minutos; o convite gera um novo cada vez que é aberto).
--   3) interruptor stripe_connect_conta_nova = 'pessoal' (NADA muda até alguém o pôr em 'empresa',
--      depois de ativar o Connect no painel da Stripe da empresa e criar o webhook).
--   4) admin_connect_convite(p_role, p_row_id, p_novo): o painel pede/renova o convite.
--   5) admin_list_connect_accounts: mesma assinatura, devolve também 'owner' e 'convite_url'.
-- Antes de aplicar: backup não é preciso (só acrescenta colunas/tabela/funções). Verificação no fim.
-- =============================================================================

begin;

-- 1) Conta dona ------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['restaurants','service_providers','drivers','cleaners'] loop
    execute format(
      'alter table public.%I add column if not exists stripe_account_owner text not null default %L',
      t, 'pessoal');
    if not exists (select 1 from pg_constraint where conname = t || '_stripe_account_owner_chk') then
      execute format(
        'alter table public.%I add constraint %I check (stripe_account_owner in (%L, %L))',
        t, t || '_stripe_account_owner_chk', 'pessoal', 'empresa');
    end if;
  end loop;
end $$;

-- 2) Convites permanentes ----------------------------------------------------------
create table if not exists public.connect_convites (
  token          text primary key check (length(token) >= 40),
  role           text not null check (role in ('partner','provider','driver','cleaner')),
  row_id         text not null,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  revogado_em    timestamptz,
  usos           integer not null default 0,
  ultimo_uso_em  timestamptz
);
create unique index if not exists connect_convites_um_ativo
  on public.connect_convites (role, row_id) where revogado_em is null;
alter table public.connect_convites enable row level security;
-- Sem políticas: só o servidor (service role) lê e escreve. O painel usa a função 4).
revoke all on public.connect_convites from public, anon, authenticated;

comment on table public.connect_convites is
  'M7 08/11/2026: link de cadastro Stripe Connect permanente por parceiro/estafeta. '
  'O token vai no link (connect-convite?t=...). Revogar = revogado_em. Só service role.';

-- 3) Interruptor ----------------------------------------------------------------
insert into public.platform_settings (key, value, description, category)
values ('stripe_connect_conta_nova', '"pessoal"'::jsonb,
        'Em que Stripe nascem as contas Connect novas (pessoal | empresa). '
        'Pôr em empresa só depois de: Connect ativo no painel da empresa + webhook de contas '
        'conectadas com o segredo STRIPE_CONNECT_WEBHOOK_SECRET_EMPRESA no servidor. '
        'Com empresa, quem ainda tem conta na pessoal recebe uma conta nova na empresa ao abrir o convite.',
        'stripe_connect')
on conflict (key) do nothing;

-- 4) Convite pelo painel -----------------------------------------------------------
create or replace function public.admin_connect_convite(
  p_role text, p_row_id text, p_novo boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_existe boolean;
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;
  if p_role not in ('partner','provider','driver','cleaner') then
    raise exception 'invalid_role';
  end if;

  execute format('select exists(select 1 from public.%I where id::text = $1)',
                 case p_role when 'partner' then 'restaurants'
                             when 'provider' then 'service_providers'
                             when 'driver' then 'drivers'
                             else 'cleaners' end)
    into v_existe using p_row_id;
  if not v_existe then
    raise exception 'row_not_found';
  end if;

  if p_novo then
    update public.connect_convites
       set revogado_em = now()
     where role = p_role and row_id = p_row_id and revogado_em is null;
  end if;

  select token into v_token
    from public.connect_convites
   where role = p_role and row_id = p_row_id and revogado_em is null;

  if v_token is null then
    v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    insert into public.connect_convites (token, role, row_id, criado_por)
    values (v_token, p_role, p_row_id, auth.uid());
  end if;

  return jsonb_build_object(
    'token', v_token,
    'url', 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/connect-convite?t=' || v_token);
end;
$$;
revoke all on function public.admin_connect_convite(text, text, boolean) from public, anon;
grant execute on function public.admin_connect_convite(text, text, boolean) to authenticated;

-- 5) Lista do painel com a conta dona e o convite ----------------------------------
create or replace function public.admin_list_connect_accounts()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;
  return coalesce((
    select jsonb_agg(j order by j->>'role', j->>'name')
    from (
      select jsonb_build_object(
        'role', 'partner', 'row_id', r.id::text, 'name', r.name,
        'account_id', r.stripe_account_id, 'status', r.stripe_account_status,
        'owner', r.stripe_account_owner,
        'charges_enabled', r.stripe_charges_enabled, 'payouts_enabled', r.stripe_payouts_enabled,
        'requirements', r.stripe_requirements, 'onboarded_at', r.stripe_onboarded_at,
        'convite_url', (select 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/connect-convite?t=' || c.token
                          from connect_convites c
                         where c.role = 'partner' and c.row_id = r.id::text and c.revogado_em is null)) as j
      from restaurants r
      where r.user_ is not null or r.user_id is not null or r.stripe_account_id is not null
      union all
      select jsonb_build_object(
        'role', 'provider', 'row_id', sp.id::text, 'name', sp.name,
        'account_id', sp.stripe_account_id, 'status', sp.stripe_account_status,
        'owner', sp.stripe_account_owner,
        'charges_enabled', sp.stripe_charges_enabled, 'payouts_enabled', sp.stripe_payouts_enabled,
        'requirements', sp.stripe_requirements, 'onboarded_at', sp.stripe_onboarded_at,
        'convite_url', (select 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/connect-convite?t=' || c.token
                          from connect_convites c
                         where c.role = 'provider' and c.row_id = sp.id::text and c.revogado_em is null))
      from service_providers sp
      union all
      select jsonb_build_object(
        'role', 'driver', 'row_id', d.id::text, 'name', d.name,
        'account_id', d.stripe_account_id, 'status', d.stripe_account_status,
        'owner', d.stripe_account_owner,
        'charges_enabled', d.stripe_charges_enabled, 'payouts_enabled', d.stripe_payouts_enabled,
        'requirements', d.stripe_requirements, 'onboarded_at', d.stripe_onboarded_at,
        'convite_url', (select 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/connect-convite?t=' || c.token
                          from connect_convites c
                         where c.role = 'driver' and c.row_id = d.id::text and c.revogado_em is null))
      from drivers d
      union all
      select jsonb_build_object(
        'role', 'cleaner', 'row_id', cl.id::text, 'name', cl.name,
        'account_id', cl.stripe_account_id, 'status', cl.stripe_account_status,
        'owner', cl.stripe_account_owner,
        'charges_enabled', cl.stripe_charges_enabled, 'payouts_enabled', cl.stripe_payouts_enabled,
        'requirements', cl.stripe_requirements, 'onboarded_at', cl.stripe_onboarded_at,
        'convite_url', (select 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/connect-convite?t=' || c.token
                          from connect_convites c
                         where c.role = 'cleaner' and c.row_id = cl.id::text and c.revogado_em is null))
      from cleaners cl
    ) t
  ), '[]'::jsonb);
end;
$function$;

commit;

-- Verificação (ler de volta):
-- select table_name, column_default from information_schema.columns
--  where column_name = 'stripe_account_owner' order by 1;                       -- 4 linhas, 'pessoal'
-- select key, value from platform_settings where key = 'stripe_connect_conta_nova'; -- "pessoal"
-- select relrowsecurity from pg_class where relname = 'connect_convites';         -- true
-- select has_function_privilege('anon', 'public.admin_connect_convite(text,text,boolean)', 'execute'); -- false
