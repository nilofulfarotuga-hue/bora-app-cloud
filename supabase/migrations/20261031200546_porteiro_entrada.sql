-- PORTEIRO DO TELEGRAM — fila de entrada da base (missao retoma-geral-2026-10-31, bloco 6; ordem do Danilo 31/10 10:07)
--
-- Porque: a Edge Function notify-admin-urgent (alertas da base: pedido novo, cadastro, marcacao, TVDE...) falava
-- direto com a API do bot e chegava ao Danilo SEM voz e sem triagem. Agora escreve aqui e o porteiro da VPS
-- (/opt/data/voz/porteiro.py, servico porteiro) le de 10 em 10 s e manda texto + voz pelo caminho unico.
-- Nao se abriu nenhuma porta da VPS a internet (a rota publica foi recusada a 31/10, ver docs/TRANCAS.md).
--
-- Seguranca: RLS ligada e SEM politicas => so service_role (Edge Functions e o porteiro) le e escreve.
-- anon/authenticated nao tocam na tabela (ninguem de fora consegue pôr mensagens no chat do Danilo).
-- Nao toca em dinheiro, pedidos, carteiras nem RLS de outras tabelas.

create table if not exists public.porteiro_entrada (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  origem      text        not null default 'notify-admin-urgent' check (length(origem) between 1 and 60),
  nivel       text        not null default 'URGENTE' check (nivel in ('URGENTE', 'RESULTADO', 'INFO')),
  texto       text        not null check (length(texto) between 1 and 4000),
  tratado_em  timestamptz,
  resultado   jsonb
);

comment on table public.porteiro_entrada is
  'Fila de avisos da base para o chat do Danilo no Telegram. Escreve: Edge notify-admin-urgent (service_role). '
  'Le e marca tratado_em: porteiro da VPS (/opt/data/voz/porteiro.py). Bloco 6 da retoma-geral-2026-10-31.';

alter table public.porteiro_entrada enable row level security;
revoke all on table public.porteiro_entrada from anon, authenticated;
revoke all on sequence public.porteiro_entrada_id_seq from anon, authenticated;

create index if not exists porteiro_entrada_por_tratar on public.porteiro_entrada (id) where tratado_em is null;

-- Prova depois de aplicar (so leitura):
--   select relrowsecurity from pg_class where oid = 'public.porteiro_entrada'::regclass;          -- true
--   select count(*) from pg_policies where tablename = 'porteiro_entrada';                         -- 0
--   select has_table_privilege('anon', 'public.porteiro_entrada', 'insert');                       -- false
-- e no servidor: ssh ... 'grep entrada /opt/data/voz/porteiro/porteiro.log.jsonl | tail -2'
