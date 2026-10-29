-- Robo "fiscal de documentos" (missao final-app-2026-10-29, adendo 3, R1).
-- Tabela dos vereditos do robo + definicoes. O robo NUNCA aprova nada: a decisao final e humana.
-- NAO se guarda o nome nem o NIF lidos nos documentos: so se batem ou nao.

create table if not exists public.documentos_verificacoes (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  papel text not null,
  campo text,
  tipo_documento_esperado text not null,
  bucket text,
  path text,
  sha256 text,
  modelo text,
  tipo_detectado text,
  legivel boolean,
  nome_bate boolean,
  nif_bate boolean,
  validade date,
  confianca numeric(4,3),
  motivo_pt text,
  decisao text not null,
  acao text not null default 'nenhuma',
  modo text not null,
  created_at timestamptz not null default now(),
  revertido_por uuid,
  revertido_em timestamptz,
  constraint documentos_verificacoes_decisao_ck check (decisao in ('ok','errado','duvida')),
  constraint documentos_verificacoes_acao_ck check (acao in ('nenhuma','recusado','pedido')),
  constraint documentos_verificacoes_modo_ck check (modo in ('sombra','ativo','previa'))
);
create index if not exists documentos_verificacoes_user_idx on public.documentos_verificacoes (user_id, created_at desc);
create index if not exists documentos_verificacoes_path_idx on public.documentos_verificacoes (bucket, path);

alter table public.documentos_verificacoes enable row level security;
create policy documentos_verificacoes_admin_ler on public.documentos_verificacoes
  for select to authenticated using (public.is_admin());
revoke all on table public.documentos_verificacoes from public, anon, authenticated;
grant select on table public.documentos_verificacoes to authenticated;

-- Lembretes ja enviados pelo robo (dia 1, 3 e 7). So o admin le.
create table if not exists public.documentos_lembretes_enviados (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  dia integer not null,
  quem text not null default 'cron',
  faltas text[] not null default '{}',
  enviado_em timestamptz not null default now(),
  constraint documentos_lembretes_quem_ck check (quem in ('cron','painel'))
);
create index if not exists documentos_lembretes_user_idx on public.documentos_lembretes_enviados (user_id, enviado_em desc);
alter table public.documentos_lembretes_enviados enable row level security;
create policy documentos_lembretes_admin_ler on public.documentos_lembretes_enviados
  for select to authenticated using (public.is_admin());
revoke all on table public.documentos_lembretes_enviados from public, anon, authenticated;
grant select on table public.documentos_lembretes_enviados to authenticated;

-- Definicoes. ativo=false e modo sombra: o robo so olha e regista; nao fala com ninguem nem muda estados.
insert into public.platform_settings (key, value, description, category) values
  ('robo_documentos_ativo', 'false'::jsonb,
   'Robo de documentos: so age (recusa, avisa, lembra) quando isto e true E o modo e ativo. Com false so olha e regista.', 'documentos'),
  ('robo_documentos_modo', '"sombra"'::jsonb,
   'Robo de documentos: sombra = so olha e regista o veredito; ativo = age (so com robo_documentos_ativo=true).', 'documentos'),
  ('robo_documentos_confianca_min', '0.85'::jsonb,
   'Robo de documentos: confianca minima (0 a 1) para agir sobre um documento errado.', 'documentos'),
  ('robo_documentos_limite_dia', '200'::jsonb,
   'Robo de documentos: maximo de analises por dia (0 = pausa tudo, incluindo a IA).', 'documentos'),
  ('robo_documentos_lembretes_dias', '[1,3,7]'::jsonb,
   'Robo de documentos: dias depois da candidatura em que se lembra quem tem documentos em falta.', 'documentos'),
  ('robo_documentos_corte', 'null'::jsonb,
   'Robo de documentos: hora da ativacao. So recebem avisos automaticos candidatos registados ou com envio depois disto.', 'documentos')
on conflict (key) do nothing;