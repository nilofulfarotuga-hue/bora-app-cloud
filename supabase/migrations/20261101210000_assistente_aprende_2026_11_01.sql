-- Bora Assistente — "aprende com os erros e com as perguntas dos clientes" (melhoria 3 de 10/10/2026,
-- feita a 01/11/2026, missão assistente-cliente-2026-11-01).
--
-- O que é: quando o assistente não sabe uma pergunta sobre a app, consulta o manual (RAG do suporte,
-- support_knowledge_chunks via match_knowledge) e guarda aqui a pergunta com a resposta encontrada;
-- da próxima vez a resposta já vai no prompt. Quando o cliente o corrige ("não era isso"), guarda uma
-- lição curta. Nada aqui é dinheiro: nunca guarda preços nem regras de preço (o prompt diz-o e o
-- servidor só aceita texto curto).
--
-- Paridade admin: o painel lê/edita/desliga pela RLS is_admin() (ecrã a fazer na app, ver relatório).

create table if not exists public.assistant_learned (
  id             uuid primary key default gen_random_uuid(),
  question_norm  text not null,
  question       text not null,
  answer         text not null,
  source         text not null default 'manual' check (source in ('manual', 'cliente', 'admin')),
  kind           text not null default 'resposta' check (kind in ('resposta', 'licao')),
  active         boolean not null default true,
  hits           integer not null default 1,
  user_id        uuid,
  conversation_id uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index if not exists assistant_learned_question_norm_uidx
  on public.assistant_learned (question_norm) where kind = 'resposta';
create index if not exists assistant_learned_active_idx
  on public.assistant_learned (active, kind, updated_at desc);

comment on table public.assistant_learned is
  'Bora Assistente: perguntas já respondidas pelo manual (kind=resposta) e lições vindas de correções do cliente (kind=licao). Escrito pela Edge Function client-assistant (service role). Admin pode ler/desligar.';

alter table public.assistant_learned enable row level security;

drop policy if exists assistant_learned_admin on public.assistant_learned;
create policy assistant_learned_admin on public.assistant_learned
  for all using (public.is_admin()) with check (public.is_admin());

revoke all on public.assistant_learned from anon;
grant select, update on public.assistant_learned to authenticated;

-- O robô novo entra no painel do Claude (platform_settings.claude_robos) como P1 Sonnet, igual ao
-- chat de ajuda. Não é definição financeira.
update public.platform_settings
   set value = jsonb_set(
         coalesce(value, '{}'::jsonb),
         '{edge-assistente}',
         coalesce(value -> 'edge-assistente',
                  '{"nome":"Bora Assistente (compras do cliente)","usar":true,"modelo":"claude-sonnet-5-5","prioridade":1}'::jsonb),
         true)
 where key = 'claude_robos';
