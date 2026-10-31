-- 31/10/2026 — vigia diário das chaves (missão chaves-varredura-2026-10-31, bloco D; autorizado pelo Danilo
-- 31/10 12:19 e no chat da Claude.ai 31/10 19:53, item 3). Parte 1: só a tabela dos pings.
create table if not exists public.saude_chaves_pings (
  id bigserial primary key,
  criado_em timestamptz not null default now(),
  ronda uuid not null,
  funcao text not null,
  modo text not null check (modo in ('legada_bearer', 'nova_apikey')),
  espera_pong boolean not null,
  request_id bigint not null,
  status_code int,
  corpo text,
  verificado_em timestamptz,
  resultado text,
  alertado boolean not null default false
);
create index if not exists saude_chaves_pings_ronda_idx on public.saude_chaves_pings (ronda);
create index if not exists saude_chaves_pings_pendentes_idx on public.saude_chaves_pings (criado_em) where verificado_em is null;
alter table public.saude_chaves_pings enable row level security;
