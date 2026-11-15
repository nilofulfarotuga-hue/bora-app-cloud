-- manha-15-11 (adendo Claude.ai 10:08, ordem do Danilo 10:06): fila dos roteiros dos 4
-- personagens de IA (Vo Tonico, Vo Celeste, Malu, Lucia). O Claude Code escreve os roteiros;
-- quem tem o Higgsfield ilimitado (Claude.ai) gera os videos a partir daqui e marca o estado.
-- Nada de dinheiro nem de clientes. Fechada ao publico: so service_role e admins.

create table if not exists public.conteudo_ia_fila (
  id                text primary key,                 -- ex.: vo-tonico-r001
  personagem        text not null check (personagem in ('vo-tonico','vo-celeste','malu','lucia')),
  tema              text,
  gancho            text not null,
  roteiro           text not null,
  palavras          integer,
  legenda           text,
  hashtags          text[],
  titulo_youtube    text,
  descricao_youtube text,
  texto_miniatura   text,
  versiculo         text,
  estado            text not null default 'roteiro'
                    check (estado in ('roteiro','a_gerar','gerado','aprovado','chumbado','agendado','publicado','descartado')),
  job_id            text,                             -- job do Higgsfield
  video_url         text,
  motivo            text,                             -- motivo do chumbo (Juiz/Refinador)
  agendado_para     timestamptz,
  publicado_em      jsonb not null default '{}'::jsonb, -- {"tiktok":"url","instagram":"url",...}
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);

create index if not exists conteudo_ia_fila_estado_idx on public.conteudo_ia_fila (personagem, estado);

alter table public.conteudo_ia_fila enable row level security;
revoke all on public.conteudo_ia_fila from anon, authenticated;

drop policy if exists conteudo_ia_fila_admin on public.conteudo_ia_fila;
create policy conteudo_ia_fila_admin on public.conteudo_ia_fila
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select, insert, update on public.conteudo_ia_fila to authenticated;

comment on table public.conteudo_ia_fila is
  'Fila de roteiros e videos dos personagens de IA (15/11/2026). Estados: roteiro > a_gerar > gerado > aprovado/chumbado > agendado > publicado.';
