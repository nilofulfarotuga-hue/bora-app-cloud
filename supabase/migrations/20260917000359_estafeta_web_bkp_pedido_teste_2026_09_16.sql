-- Missão estafeta-web-2026-09-16 · prova do bloco 3: backup (RLS ligada) do
-- pedido de TESTE criado por SQL para provar a oferta/viagem no navegador,
-- antes de o apagar. Guarda em jsonb as linhas de orders, order_status_events,
-- delivery_pin_attempts, order_driver_assignment_audit e bora_tokens.
-- Aplicada em produção a 2026-09-17 00:03:59 UTC (versão 20260917000359).
create table if not exists public.bkp_pedido_teste_estafeta_web_20260916 (
  id bigserial primary key, tabela text not null, linha jsonb not null, guardado_em timestamptz not null default now());
alter table public.bkp_pedido_teste_estafeta_web_20260916 enable row level security;
revoke all on public.bkp_pedido_teste_estafeta_web_20260916 from public;
revoke all on public.bkp_pedido_teste_estafeta_web_20260916 from anon;
revoke all on public.bkp_pedido_teste_estafeta_web_20260916 from authenticated;
insert into public.bkp_pedido_teste_estafeta_web_20260916 (tabela, linha)
select 'orders', to_jsonb(o) from public.orders o where o.id = 'e2e020916a5c4051891a6e2fd8280c84'
union all select 'order_status_events', to_jsonb(e) from public.order_status_events e where e.order_id = 'e2e020916a5c4051891a6e2fd8280c84'
union all select 'delivery_pin_attempts', to_jsonb(p) from public.delivery_pin_attempts p where p.order_id = 'e2e020916a5c4051891a6e2fd8280c84'
union all select 'order_driver_assignment_audit', to_jsonb(a) from public.order_driver_assignment_audit a where a.order_id = 'e2e020916a5c4051891a6e2fd8280c84'
union all select 'bora_tokens', to_jsonb(t) from public.bora_tokens t where t.source_order_id::text = 'e2e020916a5c4051891a6e2fd8280c84';
