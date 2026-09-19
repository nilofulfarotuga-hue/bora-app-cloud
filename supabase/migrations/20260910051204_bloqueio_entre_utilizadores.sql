-- Bloqueio entre utilizadores (2026-09-10).
-- Exigencia da directriz 1.2 da App Store: "The ability to block abusive
-- users from the service". A app ja tinha denuncia; faltava isto.
create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_ref text not null,
  blocked_label text,
  motivo text,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_ref)
);

create index if not exists blocked_users_blocker_idx
  on public.blocked_users (blocker_id);

alter table public.blocked_users enable row level security;

-- Cada pessoa so ve, cria e retira os seus proprios bloqueios.
create policy blocked_users_ve_os_seus on public.blocked_users
  for select using (auth.uid() = blocker_id);

create policy blocked_users_cria_os_seus on public.blocked_users
  for insert with check (auth.uid() = blocker_id);

create policy blocked_users_retira_os_seus on public.blocked_users
  for delete using (auth.uid() = blocker_id);