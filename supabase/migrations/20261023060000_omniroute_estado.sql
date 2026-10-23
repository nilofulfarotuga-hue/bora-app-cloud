-- Missão omniroute-23-10 (23/10/2026) — bloco 7: estado do OmniRoute para o painel admin.
-- O roteador OmniRoute vive na VPS (contentor `omniroute`, porta só local/tailnet). De 10 em 10
-- minutos o script /opt/omniroute/or_estado.py escreve aqui UMA linha (id 'vps') com: fornecedores
-- vivos/mortos, combos e o nível que está a responder, e o consumo do dia. Nunca leva chaves.
-- Escreve com a chave de serviço (passa por cima da RLS); só admins leem, pelo is_admin().

create table if not exists public.omniroute_estado (
  id text primary key default 'vps',
  dados jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

comment on table public.omniroute_estado is
  'Estado do roteador OmniRoute da VPS (missao omniroute-23-10). Escrito de 10 em 10 min por /opt/omniroute/or_estado.py; lido pelo ecra /admin/motores. Sem chaves.';

alter table public.omniroute_estado enable row level security;

drop policy if exists omniroute_estado_admin on public.omniroute_estado;
create policy omniroute_estado_admin on public.omniroute_estado
  for all using (public.is_admin()) with check (public.is_admin());

revoke all on public.omniroute_estado from anon;
grant select on public.omniroute_estado to authenticated;
