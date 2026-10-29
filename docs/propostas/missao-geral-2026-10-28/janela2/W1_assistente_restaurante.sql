-- Missao missao-geral-2026-10-28, Bloco 4 / W1 — assistente de WhatsApp para restaurantes (Boom! Burger, EM TESTE).
-- Para a JANELA 2 (o lider aplica). Nao toca em funcoes de dinheiro nem em dados de pedidos:
--   1) assistant_tenants ganha `tipo` (barbearia | restaurante) e `restaurant_id`;
--   2) assistant_tasks aceita o tipo 'pedido' (o robo acompanha cada encomenda numa tarefa);
--   3) tabela nova order_origem: de onde veio cada pedido (app | whatsapp) + telefone do cliente.
-- A linha do tenant da Boom (com os numeros) NAO esta aqui: vive num ficheiro fora do repositorio.
-- Idempotente: pode correr duas vezes.

begin;

-- 1) tenant: tipo e loja ------------------------------------------------------------------------
alter table public.assistant_tenants
  add column if not exists tipo text not null default 'barbearia',
  add column if not exists restaurant_id text references public.restaurants(id);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'assistant_tenants_tipo_check') then
    alter table public.assistant_tenants
      add constraint assistant_tenants_tipo_check check (tipo in ('barbearia', 'restaurante'));
  end if;
end $$;

comment on column public.assistant_tenants.tipo is
  'barbearia = marcacoes (provider_id); restaurante = encomendas da loja restaurant_id';
comment on column public.assistant_tenants.restaurant_id is
  'Loja (restaurants.id) quando tipo = restaurante';

-- 2) tarefas: o robo segue cada encomenda numa tarefa tipo 'pedido' ----------------------------
alter table public.assistant_tasks drop constraint if exists assistant_tasks_tipo_check;
alter table public.assistant_tasks add constraint assistant_tasks_tipo_check
  check (tipo in ('pergunta_dono', 'passar_dono', 'lembrete', 'avaliacao', 'reativacao',
                  'lista_espera', 'resumo_semanal', 'pedido'));

-- 3) origem do pedido ---------------------------------------------------------------------------
-- Sem chave estrangeira para a tabela de pedidos de proposito: esta tabela so acrescenta
-- informacao e nunca pode travar nem apagar nada do pedido.
create table if not exists public.order_origem (
  order_id     text primary key,
  origem       text not null check (origem in ('app', 'whatsapp')),
  client_phone text,
  tenant_slug  text,
  created_at   timestamptz not null default now()
);

create index if not exists order_origem_tenant_idx on public.order_origem (tenant_slug, created_at desc);
create index if not exists order_origem_origem_idx on public.order_origem (origem, created_at desc);

comment on table public.order_origem is
  'De onde veio o pedido (app | whatsapp). Escrita SO pela chave de servico (o assistente de WhatsApp). '
  'Leitura: admin e o parceiro dono da loja do pedido (etiqueta WhatsApp + telefone do cliente).';

alter table public.order_origem enable row level security;

-- leitura: admin
drop policy if exists order_origem_admin_le on public.order_origem;
create policy order_origem_admin_le on public.order_origem
  for select to authenticated
  using (public.is_admin());

-- leitura: o parceiro dono da loja do pedido (o mesmo criterio das politicas de leitura dos pedidos
-- para o parceiro: restaurant_id in parceiro_minhas_lojas())
drop policy if exists order_origem_parceiro_le on public.order_origem;
create policy order_origem_parceiro_le on public.order_origem
  for select to authenticated
  using (exists (
    select 1 from public.orders o
     where o.id = order_origem.order_id
       and o.restaurant_id in (select public.parceiro_minhas_lojas())
  ));

-- escrita: so a chave de servico (sem politicas de escrita; anon e authenticated sem privilegio)
revoke all on public.order_origem from anon;
revoke insert, update, delete, truncate on public.order_origem from authenticated;
grant select on public.order_origem to authenticated;
grant all on public.order_origem to service_role;

commit;

-- PROVA (depois de aplicar; tudo leitura):
-- select column_name, data_type, column_default from information_schema.columns
--  where table_schema='public' and table_name='assistant_tenants' and column_name in ('tipo','restaurant_id');
-- select pg_get_constraintdef(oid) from pg_constraint where conname in ('assistant_tenants_tipo_check','assistant_tasks_tipo_check');
-- select relrowsecurity from pg_class where oid = 'public.order_origem'::regclass;              -- true
-- select polname, polcmd from pg_policy where polrelid = 'public.order_origem'::regclass;       -- 2 de leitura
-- select has_table_privilege('anon','public.order_origem','select'),
--        has_table_privilege('authenticated','public.order_origem','insert');                  -- false, false
-- select slug, tipo from public.assistant_tenants order by slug;                                 -- os 2 antigos = barbearia
