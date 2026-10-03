
-- Ponte de conhecimento Claude.ai -> ChatGPT / OpenCode / Claude Code.
-- A Claude.ai escreve aqui (regras do Danilo, estado, digests de sessão);
-- o ChatGPT (MCP Supabase) e o OpenCode lêem; o executor sincroniza para o Córtex.
create table if not exists public.claude_ai_memoria (
  pagina text primary key,
  titulo text not null,
  conteudo text not null,
  origem text not null default 'claude-ai',
  atualizado_em timestamptz not null default now()
);
comment on table public.claude_ai_memoria is
  'Memória viva da Claude.ai para os outros motores (ChatGPT, OpenCode, Claude Code). Ler ANTES de qualquer trabalho no Bora. pagina=regras-do-danilo manda em tudo.';
alter table public.claude_ai_memoria enable row level security;
revoke all on table public.claude_ai_memoria from public, anon, authenticated;
-- sem políticas: só service_role / acesso de servidor (MCP) lê e escreve
