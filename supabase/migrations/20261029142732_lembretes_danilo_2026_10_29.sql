-- Lembretes diários para o dono (missão final-app-2026-10-29, passo 5.c).
-- Tabela de apoio, sem dinheiro. Só administradores e o service_role leem/escrevem; fechada a anon.
create table if not exists public.lembretes_danilo (
  id bigserial primary key,
  texto text not null,
  link text,
  quando timestamptz not null,
  enviado_em timestamptz,
  feito_em timestamptz,
  origem text not null default 'claude-code',
  urgente boolean not null default false,
  created_at timestamptz default now()
);

comment on table public.lembretes_danilo is 'Lembretes que a rotina das 09:30 manda pelo WhatsApp da Bora; urgentes saem de 10 em 10 minutos.';

create index if not exists lembretes_danilo_quando_idx on public.lembretes_danilo (quando);
create index if not exists lembretes_danilo_pendentes_idx on public.lembretes_danilo (enviado_em) where enviado_em is null;

alter table public.lembretes_danilo enable row level security;

revoke all on public.lembretes_danilo from public, anon;
revoke all on sequence public.lembretes_danilo_id_seq from public, anon;
grant select, insert, update on public.lembretes_danilo to authenticated;
grant usage, select on sequence public.lembretes_danilo_id_seq to authenticated;
grant all on public.lembretes_danilo to service_role;
grant all on sequence public.lembretes_danilo_id_seq to service_role;

drop policy if exists lembretes_danilo_admin_select on public.lembretes_danilo;
create policy lembretes_danilo_admin_select on public.lembretes_danilo
  for select to authenticated using (public.is_admin());

drop policy if exists lembretes_danilo_admin_insert on public.lembretes_danilo;
create policy lembretes_danilo_admin_insert on public.lembretes_danilo
  for insert to authenticated with check (public.is_admin());

drop policy if exists lembretes_danilo_admin_update on public.lembretes_danilo;
create policy lembretes_danilo_admin_update on public.lembretes_danilo
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists lembretes_danilo_service on public.lembretes_danilo;
create policy lembretes_danilo_service on public.lembretes_danilo
  for all to service_role using (true) with check (true);
