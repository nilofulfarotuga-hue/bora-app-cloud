-- PROPOSTA (loja-nichos-15-11, N1). Quem aplica: Claude.ai. Ordem do Danilo 15/11 18:52/18:56 (via
-- Claude.ai 19:00): a Loja Online passa a ser uma lista de NICHOS (Pets e o primeiro), cada nicho com
-- SUBCATEGORIAS, os MAIS VENDIDOS a frente e cada nicho novo ESCONDIDO ate o Danilo dizer "abrir".
-- Assenta no que ja esta no ar (20261115145547_loja_online_categoria + caixa 79). Nao mexe em precos,
-- pagamentos, comissoes nem no stripe-webhook.
--
-- Regra de visibilidade (depois disto):
--   admin ou conta da loja_online_lista_permissao -> ve todos os nichos ativos (para rever antes de abrir);
--   o publico -> so ve um nicho com ativo AND publico AND loja_online_ativa=true.
--   O ladrilho "Loja Online" aparece a quem tiver pelo menos um nicho visivel.
-- Ordem dos produtos (montra e cada subcategoria): ordem_manual (painel) primeiro, depois vendas_loja
-- (vendas reais pagas, contadas sozinhas), depois cj_listas (ranking de vendas da CJ), depois os mais novos.

-- 1. Nichos: interruptor proprio --------------------------------------------------------------------
alter table public.loja_online_nichos
  add column if not exists publico boolean not null default false;
comment on column public.loja_online_nichos.publico is
  'true = o nicho esta aberto a todos os clientes (com loja_online_ativa=true). Nasce false: so admin e lista de permissao o veem ate o Danilo dizer abrir.';

create or replace function public.loja_online_nicho_visivel(p_nicho_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.loja_online_nichos n
     where n.id = p_nicho_id and n.ativo
       and (
         (auth.uid() is not null and (
            public.is_admin()
            or exists (select 1 from public.loja_online_lista_permissao p where p.user_id = auth.uid())))
         or (n.publico and coalesce(public._setting_txt('loja_online_ativa', 'false') = 'true', false))
       ));
$$;
revoke all on function public.loja_online_nicho_visivel(uuid) from public;
grant execute on function public.loja_online_nicho_visivel(uuid) to anon, authenticated, service_role;

-- O ladrilho: ha pelo menos um nicho visivel para quem pergunta.
create or replace function public.loja_online_visivel_para_mim()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.loja_online_nichos n where public.loja_online_nicho_visivel(n.id));
$$;

-- 2. Subcategorias ------------------------------------------------------------------------------------
create table if not exists public.loja_online_subcategorias (
  id         uuid primary key default gen_random_uuid(),
  nicho_id   uuid not null references public.loja_online_nichos(id) on delete restrict,
  slug       text not null check (slug ~ '^[a-z0-9-]{2,40}$'),
  nome       text not null,
  ordem      integer not null default 100,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  unique (nicho_id, slug)
);
alter table public.loja_online_subcategorias enable row level security;
revoke all on public.loja_online_subcategorias from public, anon, authenticated;
grant select on public.loja_online_subcategorias to authenticated;
grant insert, update, delete on public.loja_online_subcategorias to authenticated;
drop policy if exists loja_online_subcategorias_leitura on public.loja_online_subcategorias;
create policy loja_online_subcategorias_leitura on public.loja_online_subcategorias
  for select to authenticated
  using ((ativo and public.loja_online_nicho_visivel(nicho_id)) or public.is_admin());
drop policy if exists loja_online_subcategorias_admin on public.loja_online_subcategorias;
create policy loja_online_subcategorias_admin on public.loja_online_subcategorias
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 3. Produtos: subcategoria e ordem por vendas --------------------------------------------------------
alter table public.loja_online_produtos
  add column if not exists subcategoria_id uuid references public.loja_online_subcategorias(id) on delete set null,
  add column if not exists cj_listas      integer not null default 0 check (cj_listas >= 0),
  add column if not exists vendas_loja    integer not null default 0 check (vendas_loja >= 0),
  add column if not exists ordem_manual   integer;
comment on column public.loja_online_produtos.cj_listas is 'Ranking de vendas do fornecedor (lojas que listam o produto na CJ). Serve so para ordenar enquanto ha poucas vendas nossas.';
comment on column public.loja_online_produtos.vendas_loja is 'Unidades vendidas e pagas na nossa loja (gatilho em loja_online_encomendas).';
comment on column public.loja_online_produtos.ordem_manual is 'Posicao fixada pelo admin (1 = primeiro). Vazio = ordem automatica por vendas.';
create index if not exists loja_online_produtos_ordem_idx
  on public.loja_online_produtos (nicho_id, subcategoria_id, ordem_manual, vendas_loja desc, cj_listas desc);

-- Leitura pelo nicho (substitui a regra "ativo e loja visivel").
drop policy if exists loja_online_produtos_leitura_ativos on public.loja_online_produtos;
create policy loja_online_produtos_leitura_ativos on public.loja_online_produtos
  for select to authenticated
  using ((ativo and public.loja_online_nicho_visivel(nicho_id)) or public.is_admin());
drop policy if exists loja_online_nichos_leitura_ativos on public.loja_online_nichos;
create policy loja_online_nichos_leitura_ativos on public.loja_online_nichos
  for select to authenticated
  using ((ativo and public.loja_online_nicho_visivel(id)) or public.is_admin());

-- O cliente le as colunas novas (nada de custo nem ligacoes ao fornecedor).
grant select (subcategoria_id, cj_listas, vendas_loja, ordem_manual)
  on public.loja_online_produtos to authenticated;

-- 4. Vendas reais: cada encomenda que passa a paga soma as unidades ao produto --------------------------
create or replace function public._loja_online_conta_venda()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.estado = 'paga' and old.estado is distinct from 'paga'
     and old.estado in ('aguarda_pagamento', 'falhou_pagamento') then
    update public.loja_online_produtos
       set vendas_loja = vendas_loja + greatest(new.quantidade, 0)
     where id = new.produto_id;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_loja_online_conta_venda on public.loja_online_encomendas;
create trigger trg_loja_online_conta_venda
  after update of estado on public.loja_online_encomendas
  for each row execute function public._loja_online_conta_venda();

-- 5. Painel: abrir/fechar um nicho e fixar a ordem de um produto ------------------------------------------
create or replace function public.admin_loja_online_nicho_publico(p_nicho_id uuid, p_publico boolean, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.loja_online_nichos%rowtype;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then raise exception 'reason_required' using errcode = '22023'; end if;
  if p_publico is null then raise exception 'nada_a_mudar' using errcode = '22023'; end if;
  update public.loja_online_nichos set publico = p_publico, atualizado_em = now()
   where id = p_nicho_id returning * into v;
  if not found then raise exception 'nicho_nao_encontrado' using errcode = 'P0002'; end if;
  perform public.log_admin_action('loja_online_nicho_publico'::text, 'loja_online_nicho'::text, p_nicho_id::text,
    jsonb_build_object('motivo', trim(p_motivo), 'nicho', v.slug, 'publico', p_publico));
  return jsonb_build_object('ok', true, 'id', v.id, 'publico', v.publico);
end;
$$;
revoke all on function public.admin_loja_online_nicho_publico(uuid, boolean, text) from public, anon;
grant execute on function public.admin_loja_online_nicho_publico(uuid, boolean, text) to authenticated;

create or replace function public.admin_loja_online_produto_ordem(p_id uuid, p_ordem_manual integer, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_antes integer; v_titulo text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then raise exception 'reason_required' using errcode = '22023'; end if;
  if p_ordem_manual is not null and p_ordem_manual < 1 then raise exception 'ordem_invalida' using errcode = '22023'; end if;
  select ordem_manual, titulo into v_antes, v_titulo from public.loja_online_produtos where id = p_id for update;
  if not found then raise exception 'produto_nao_encontrado' using errcode = 'P0002'; end if;
  update public.loja_online_produtos set ordem_manual = p_ordem_manual, atualizado_em = now() where id = p_id;
  perform public.log_admin_action('loja_online_produto_ordem'::text, 'loja_online_produto'::text, p_id::text,
    jsonb_build_object('motivo', trim(p_motivo), 'titulo', v_titulo, 'antes', v_antes, 'depois', p_ordem_manual));
  return jsonb_build_object('ok', true, 'id', p_id, 'ordem_manual', p_ordem_manual);
end;
$$;
revoke all on function public.admin_loja_online_produto_ordem(uuid, integer, text) from public, anon;
grant execute on function public.admin_loja_online_produto_ordem(uuid, integer, text) to authenticated;

-- 6. Pets: 5 subcategorias e os 11 produtos que ja estao no ar -----------------------------------------
insert into public.loja_online_subcategorias (nicho_id, slug, nome, ordem)
select n.id, s.slug, s.nome, s.ordem
  from public.loja_online_nichos n,
       (values ('cao', 'Cão', 10), ('gato', 'Gato', 20), ('peixe', 'Peixe e aquário', 30),
               ('passaro', 'Pássaro', 40), ('pequenos-animais', 'Pequenos animais', 50)) s(slug, nome, ordem)
 where n.slug = 'pets'
on conflict (nicho_id, slug) do nothing;

-- Os 11 de 15/11: o tunel e de gato, o resto de cao. cj_listas = "Lists" da ficha da CJ (pesquisa 15/11).
update public.loja_online_produtos p
   set subcategoria_id = s.id, cj_listas = v.listas
  from (values
    ('cj:6AEB0AAE-3E70-4EAE-857B-B83389786B3A:S', 'cao', 2673),
    ('cj:6AEB0AAE-3E70-4EAE-857B-B83389786B3A:L', 'cao', 2673),
    ('cj:C6DD91F5-4F23-4D6D-9EB4-0A5F88D484A1', 'cao', 1125),
    ('cj:2503191148021601200', 'cao', 6923),
    ('cj:1595721401296760832', 'cao', 6530),
    ('cj:1644945472383094784', 'gato', 1190),
    ('cj:1402533508353757184', 'cao', 330),
    ('cj:2E961E18-A6DD-44AC-A9B4-37795039890F', 'cao', 577),
    ('cj:1653041912300969984', 'cao', 3625),
    ('cj:1836302458034212864', 'cao', 202),
    ('cj:4D6E5E7A-85A5-4F26-955F-C91C69F19561', 'cao', 538)
  ) as v(spid, sub, listas)
  join public.loja_online_subcategorias s on s.slug = v.sub
  join public.loja_online_nichos n on n.id = s.nicho_id and n.slug = 'pets'
 where p.shopify_product_id = v.spid;

-- Prova sugerida (em rollback): ver o bloco de prova no fim do e2e_log (passo N1).
