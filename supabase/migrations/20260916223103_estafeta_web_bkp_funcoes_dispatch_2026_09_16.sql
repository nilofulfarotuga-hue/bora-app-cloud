-- ============================================================================
-- Missão estafeta-web-2026-09-16 · BLOCO 0/2 — backup das funções de dispatch
-- que esta missão vai alterar. Regra da casa: antes de tocar numa zona
-- protegida guarda-se a definição exacta (bkp_<nome>_AAAAMMDD, com RLS ligada).
--
-- Para repor uma função: copiar `def` desta tabela e executá-la tal e qual.
-- ============================================================================

create table if not exists public.bkp_fn_dispatch_20260916 (
  fn          text primary key,
  def         text not null,
  guardado_em timestamptz not null default now()
);

alter table public.bkp_fn_dispatch_20260916 enable row level security;
revoke all on public.bkp_fn_dispatch_20260916 from public;
revoke all on public.bkp_fn_dispatch_20260916 from anon;
revoke all on public.bkp_fn_dispatch_20260916 from authenticated;

-- Funções (pg_get_functiondef devolve o CREATE OR REPLACE completo)
insert into public.bkp_fn_dispatch_20260916 (fn, def)
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'fn_dispatch_on_calling_driver',
    'bora_dispatch_maintenance',
    'admin_reassign_order',
    'ops_reassign_order',
    'expire_stale_driver_presence',
    'driver_heartbeat'
  )
on conflict (fn) do nothing;

-- Triggers de orders que a missão toca (definição literal)
insert into public.bkp_fn_dispatch_20260916 (fn, def)
select 'TRIGGER ' || t.tgname || ' ON orders', pg_get_triggerdef(t.oid)
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'orders' and not t.tgisinternal
  and t.tgname in ('trg_dispatch_on_calling_driver', 'tr_notify_driver_on_offer')
on conflict (fn) do nothing;
