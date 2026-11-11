-- =============================================================================
-- farmacias-2026-11-11 · 01 · Lista de permissão por loja (lojas escondidas)
-- Ordem do Danilo (11/11/2026 15:18): as farmácias da Sé e Teixeira ficam ligadas SÓ nas contas dele;
-- para qualquer outra conta não aparece nada (categoria, pesquisa, faixas, link direto, Amigo, redes).
-- Mecanismo: restaurants.so_lista_permissao + tabela loja_lista_permissao + políticas RESTRICTIVE de
-- SELECT em restaurants e products + filtro nas funções SECURITY DEFINER que servem clientes.
-- Zero efeito em lojas com so_lista_permissao = false (todas as que existem hoje).
-- =============================================================================

alter table public.restaurants
  add column if not exists so_lista_permissao boolean not null default false;
comment on column public.restaurants.so_lista_permissao is
  'Loja escondida: só a veem admin, dono e quem está em loja_lista_permissao (farmacias-2026-11-11).';

create table if not exists public.loja_lista_permissao (
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  motivo text,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);
create index if not exists loja_lista_permissao_user_idx on public.loja_lista_permissao(user_id);
alter table public.loja_lista_permissao enable row level security;
revoke all on public.loja_lista_permissao from public, anon;
grant select on public.loja_lista_permissao to authenticated;
drop policy if exists loja_lista_permissao_admin on public.loja_lista_permissao;
create policy loja_lista_permissao_admin on public.loja_lista_permissao
  for select to authenticated using (public.is_admin() or user_id = auth.uid());

-- Ids das lojas escondidas que o utilizador atual NÃO pode ver (anon: todas as escondidas).
create or replace function public.lojas_escondidas_para_mim()
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(r.id), '{}'::text[])
    from public.restaurants r
   where r.so_lista_permissao
     and not (
       auth.uid() is not null and (
         public.is_admin()
         or r.user_id = auth.uid()
         or r.user_ = auth.uid()
         or exists (select 1 from public.loja_lista_permissao l
                     where l.restaurant_id = r.id and l.user_id = auth.uid())
       )
     );
$$;
revoke all on function public.lojas_escondidas_para_mim() from public;
grant execute on function public.lojas_escondidas_para_mim() to anon, authenticated;

create or replace function public.loja_visivel_para_mim(p_restaurant_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select not (coalesce(p_restaurant_id, '') = any (public.lojas_escondidas_para_mim()));
$$;
revoke all on function public.loja_visivel_para_mim(text) from public;
grant execute on function public.loja_visivel_para_mim(text) to anon, authenticated;

-- Políticas RESTRICTIVE: juntam-se (AND) às que já existem. O (select ...) corre uma vez por consulta.
drop policy if exists restaurants_lista_permissao on public.restaurants;
create policy restaurants_lista_permissao on public.restaurants
  as restrictive for select to public
  using (not (id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));

drop policy if exists products_lista_permissao on public.products;
create policy products_lista_permissao on public.products
  as restrictive for select to public
  using (not (restaurant_id = any (coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));

-- ----------------------------------------------------------------------------
-- Funções SECURITY DEFINER que servem clientes: o mesmo filtro (a RLS não as apanha).
-- ----------------------------------------------------------------------------
