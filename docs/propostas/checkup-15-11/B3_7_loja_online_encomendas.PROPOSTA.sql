-- PROPOSTA (checkup-geral-15-11, B3.7 Loja online). Quem aplica: Claude.ai.
-- Ordem do Danilo 15/11 17:53 (via Claude.ai 17:59): a categoria das vendas da Shopify entra na app,
-- ligada primeiro SO para as contas do Danilo (como as farmacias), cartao e MB WAY pelo caminho
-- Stripe que ja existe, preco = 2 x custo do fornecedor (AUTORIZO do Danilo 14/11/2026 12:19).
-- Assenta na migracao 20261115145547_loja_online_categoria (ja no servidor).
--
-- O que cria:
--  1. loja_online_lista_permissao: quem ve a loja enquanto loja_online_ativa=false (as 2 contas do
--     Danilo, as mesmas da loja_lista_permissao das farmacias).
--  2. loja_online_visivel_para_mim(): true se loja_online_ativa=true OU admin OU na lista.
--  3. loja_online_encomendas: cada compra (snapshot do produto e do preco, morada de envio, estado,
--     pagamento). O cliente so LE as suas; quem escreve e a Edge loja-online-pagamento (service_role)
--     e o admin pelas funcoes abaixo. Nunca ha dinheiro (pagamento so cartao e MB WAY).
--  4. admin_loja_online_encomendas(p_estado) e admin_loja_online_encomenda_estado(...) com auditoria.
-- Nada aqui muda precos de pedidos, comissoes, tokens nem carteira.

-- 1. Lista de permissao -------------------------------------------------------------------------
create table if not exists public.loja_online_lista_permissao (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  motivo     text,
  criado_em  timestamptz not null default now()
);
alter table public.loja_online_lista_permissao enable row level security;
revoke all on public.loja_online_lista_permissao from public, anon, authenticated;
grant select, insert, delete on public.loja_online_lista_permissao to authenticated;
drop policy if exists loja_online_lista_permissao_admin on public.loja_online_lista_permissao;
create policy loja_online_lista_permissao_admin on public.loja_online_lista_permissao
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.loja_online_lista_permissao (user_id, motivo)
select distinct l.user_id, 'contas do Danilo: ver a loja antes de abrir (ordem 15/11 17:53)'
  from public.loja_lista_permissao l
 where l.user_id in ('c9fccf85-03ee-4efc-83bf-613f211a78ff', '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7')
on conflict (user_id) do nothing;

-- 2. Visibilidade -------------------------------------------------------------------------------
create or replace function public.loja_online_visivel_para_mim()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public._setting_txt('loja_online_ativa', 'false') = 'true', false)
      or (auth.uid() is not null and (
            public.is_admin()
            or exists (select 1 from public.loja_online_lista_permissao p where p.user_id = auth.uid())));
$$;
revoke all on function public.loja_online_visivel_para_mim() from public;
grant execute on function public.loja_online_visivel_para_mim() to anon, authenticated, service_role;

-- 3. Encomendas ---------------------------------------------------------------------------------
create table if not exists public.loja_online_encomendas (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users(id) on delete restrict,
  produto_id           uuid not null references public.loja_online_produtos(id) on delete restrict,
  titulo               text not null,                 -- copia do titulo no momento da compra
  quantidade           integer not null default 1 check (quantidade between 1 and 5),
  preco_unit_cents     integer not null check (preco_unit_cents > 0),
  total_cents          integer not null check (total_cents = preco_unit_cents * quantidade),
  custo_unit_cents     integer not null default 0 check (custo_unit_cents >= 0),
  prazo_min_dias       integer not null default 0,
  prazo_max_dias       integer not null default 0,
  nome                 text not null check (length(trim(nome)) >= 3),
  telefone             text not null,
  email                text,
  morada               text not null check (length(trim(morada)) >= 5),
  codigo_postal        text not null check (codigo_postal ~ '^[0-9]{4}-[0-9]{3}$'),
  localidade           text not null,
  metodo               text not null check (metodo in ('card', 'mbway')),
  stripe_account       text not null default 'pessoal' check (stripe_account in ('pessoal', 'empresa')),
  payment_intent_id    text unique,
  estado               text not null default 'aguarda_pagamento' check (estado in (
                         'aguarda_pagamento', 'paga', 'encomendada_fornecedor', 'enviada',
                         'entregue', 'cancelada', 'falhou_pagamento')),
  fornecedor_ref       text,                           -- numero da encomenda na CJ / Shopify
  tracking             text,                           -- codigo de seguimento dos correios
  nota_admin           text,
  paga_em              timestamptz,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
comment on table public.loja_online_encomendas is
  'Loja Online (15/11/2026): compras dos clientes na app. Escrita so pela Edge loja-online-pagamento (service_role) e pelo admin. Pagamento so cartao/MB WAY.';
create index if not exists loja_online_encomendas_user_idx   on public.loja_online_encomendas (user_id, criado_em desc);
create index if not exists loja_online_encomendas_estado_idx on public.loja_online_encomendas (estado, criado_em);

alter table public.loja_online_encomendas enable row level security;
revoke all on public.loja_online_encomendas from public, anon, authenticated;
grant select on public.loja_online_encomendas to authenticated;
drop policy if exists loja_online_encomendas_minhas on public.loja_online_encomendas;
create policy loja_online_encomendas_minhas on public.loja_online_encomendas
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- 4. Painel admin -------------------------------------------------------------------------------
create or replace function public.admin_loja_online_encomendas(p_estado text default null)
returns setof public.loja_online_encomendas
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return query
    select * from public.loja_online_encomendas e
     where p_estado is null or e.estado = p_estado
     order by case e.estado when 'paga' then 0 when 'encomendada_fornecedor' then 1
                            when 'enviada' then 2 when 'aguarda_pagamento' then 3 else 4 end,
              e.criado_em desc
     limit 500;
end;
$$;
revoke all on function public.admin_loja_online_encomendas(text) from public, anon;
grant execute on function public.admin_loja_online_encomendas(text) to authenticated;

-- So os passos de logistica (o pagamento e a Edge que marca). Cancelar uma encomenda paga NAO
-- devolve dinheiro aqui: o reembolso e da zona do dinheiro e fica com o Danilo.
create or replace function public.admin_loja_online_encomenda_estado(
  p_id uuid, p_estado text, p_fornecedor_ref text, p_tracking text, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  public.loja_online_encomendas%rowtype;
  v_depois public.loja_online_encomendas%rowtype;
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  if p_estado is not null and p_estado not in ('encomendada_fornecedor', 'enviada', 'entregue', 'cancelada') then
    raise exception 'estado_invalido' using errcode = '22023';
  end if;
  select * into v_antes from public.loja_online_encomendas where id = p_id for update;
  if not found then
    raise exception 'encomenda_nao_encontrada' using errcode = 'P0002';
  end if;
  if p_estado in ('encomendada_fornecedor', 'enviada', 'entregue')
     and v_antes.estado in ('aguarda_pagamento', 'falhou_pagamento', 'cancelada') then
    raise exception 'encomenda_nao_paga' using errcode = '22023';
  end if;
  update public.loja_online_encomendas
     set estado         = coalesce(p_estado, estado),
         fornecedor_ref = coalesce(nullif(trim(p_fornecedor_ref), ''), fornecedor_ref),
         tracking       = coalesce(nullif(trim(p_tracking), ''), tracking),
         atualizado_em  = now()
   where id = p_id
   returning * into v_depois;
  perform public.log_admin_action(
    'loja_online_encomenda_estado'::text, 'loja_online_encomenda'::text, p_id::text,
    jsonb_build_object('motivo', trim(p_motivo),
      'antes',  jsonb_build_object('estado', v_antes.estado,  'fornecedor_ref', v_antes.fornecedor_ref,  'tracking', v_antes.tracking),
      'depois', jsonb_build_object('estado', v_depois.estado, 'fornecedor_ref', v_depois.fornecedor_ref, 'tracking', v_depois.tracking)));
  return jsonb_build_object('ok', true, 'id', v_depois.id, 'estado', v_depois.estado);
end;
$$;
revoke all on function public.admin_loja_online_encomenda_estado(uuid, text, text, text, text) from public, anon;
grant execute on function public.admin_loja_online_encomenda_estado(uuid, text, text, text, text) to authenticated;

-- Prova sugerida (em rollback):
-- select public.loja_online_visivel_para_mim();                       -- anon: false
-- select count(*) from public.loja_online_lista_permissao;            -- 2
-- set local role authenticated; select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
-- select public.loja_online_visivel_para_mim();                       -- false (nao esta na lista)
-- select public.admin_loja_online_encomendas(null);                   -- admin_required
