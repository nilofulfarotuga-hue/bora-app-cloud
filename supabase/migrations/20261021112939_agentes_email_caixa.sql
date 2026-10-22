create table if not exists public.agentes_email (
  id uuid primary key default gen_random_uuid(),
  direcao text not null check (direcao in ('entrada','saida')),
  agente text not null,
  de text not null,
  para text not null,
  assunto text,
  texto text,
  html text,
  anexos jsonb not null default '[]'::jsonb,
  tamanho_bytes integer,
  message_id text,
  em_resposta_a text,
  estado text not null default 'novo' check (estado in ('novo','lido','tratado','arquivado','enviado','falhou')),
  erro text,
  criado_em timestamptz not null default now()
);
create index if not exists agentes_email_agente_idx on public.agentes_email (agente, criado_em desc);
create index if not exists agentes_email_estado_idx on public.agentes_email (estado) where estado = 'novo';
create unique index if not exists agentes_email_msgid_uq on public.agentes_email (direcao, message_id) where message_id is not null;
alter table public.agentes_email enable row level security;
drop policy if exists agentes_email_admin_all on public.agentes_email;
create policy agentes_email_admin_all on public.agentes_email for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.agentes_email from anon;
comment on table public.agentes_email is 'Caixa de e-mail dos agentes (agente@boraguarda.com).';