-- Assistente de WhatsApp para restaurantes (Boom! Burger, em teste) - missao final-app-2026-10-29, bloco 2.
-- 1) assistant_tenants ganha tipo e restaurant_id; 2) assistant_tasks aceita o tipo 'pedido';
-- 3) tabela order_origem: de onde veio cada pedido (app | whatsapp) + telefone do cliente.
-- Idempotente.

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

alter table public.assistant_tasks drop constraint if exists assistant_tasks_tipo_check;
alter table public.assistant_tasks add constraint assistant_tasks_tipo_check
  check (tipo in ('pergunta_dono', 'passar_dono', 'lembrete', 'avaliacao', 'reativacao',
                  'lista_espera', 'resumo_semanal', 'pedido'));

-- Sem chave estrangeira para a tabela de pedidos de proposito: so acrescenta informacao e nunca trava o pedido.
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
  'De onde veio o pedido (app | whatsapp). Escrita so pela chave de servico (assistente de WhatsApp). Leitura: admin e parceiro dono da loja do pedido.';

alter table public.order_origem enable row level security;

drop policy if exists order_origem_admin_le on public.order_origem;
create policy order_origem_admin_le on public.order_origem
  for select to authenticated
  using (public.is_admin());

drop policy if exists order_origem_parceiro_le on public.order_origem;
create policy order_origem_parceiro_le on public.order_origem
  for select to authenticated
  using (exists (
    select 1 from public.orders o
     where o.id = order_origem.order_id
       and o.restaurant_id in (select public.parceiro_minhas_lojas())
  ));

revoke all on public.order_origem from anon;
revoke insert, update, delete, truncate on public.order_origem from authenticated;
grant select on public.order_origem to authenticated;
grant all on public.order_origem to service_role;
