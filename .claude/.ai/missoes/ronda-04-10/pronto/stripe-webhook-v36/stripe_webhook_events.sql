-- ronda 04/10 A.3 (proposta, 05/10/2026) — idempotência do stripe-webhook por event.id.
-- Aplicar ANTES de publicar o stripe-webhook v36 (o v36 também aguenta a tabela não
-- existir: processa como o v35, sem idempotência, e escreve o erro no log).
-- Nome sugerido no repo: supabase/migrations/20261005xxxxxx_stripe_webhook_events.sql

create table if not exists public.stripe_webhook_events (
  event_id     text primary key,
  type         text,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  last_error   text
);

comment on table public.stripe_webhook_events is
  'Eventos Stripe recebidos pelo stripe-webhook (v36+). processed_at preenchido = já tratado; '
  'repetição devolve 200 sem refazer. last_error = última falha real (o webhook devolveu 500).';

create index if not exists stripe_webhook_events_por_tratar
  on public.stripe_webhook_events (received_at)
  where processed_at is null;

-- Só a service_role (o próprio webhook) lê e escreve. RLS ligada e SEM políticas.
alter table public.stripe_webhook_events enable row level security;
revoke all on table public.stripe_webhook_events from public;
revoke all on table public.stripe_webhook_events from anon;
revoke all on table public.stripe_webhook_events from authenticated;
grant select, insert, update on table public.stripe_webhook_events to service_role;

-- Prova depois de aplicar (deve dar: rls=true, 0 políticas, anon/authenticated sem privilégios):
-- select c.relrowsecurity rls,
--        (select count(*) from pg_policies where tablename = 'stripe_webhook_events') politicas,
--        has_table_privilege('anon', 'public.stripe_webhook_events', 'select') anon_le,
--        has_table_privilege('authenticated', 'public.stripe_webhook_events', 'insert') auth_escreve
--   from pg_class c where c.oid = 'public.stripe_webhook_events'::regclass;

-- Voltar atrás (só depois de repor o stripe-webhook v35):
-- drop table if exists public.stripe_webhook_events;
