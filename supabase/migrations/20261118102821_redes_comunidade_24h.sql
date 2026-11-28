-- Missão comunidade-24h-montagem (caixa_guardados 120, ponto 8 da caixa 119), 17/11/2026.
-- Registo do gestor de comunidade do Hermes: interações, números diários e experiências.
-- Escreve o Hermes (service_role, que passa a RLS); o painel admin lê e corrige.

create table if not exists public.redes_interacoes (
  id           bigint generated always as identity primary key,
  conta        text not null,                 -- vo-tonico, vo-celeste, malu, lucia, ines, em-dia, bora-guarda, mimo-patudo
  rede         text not null check (rede in ('youtube','instagram','facebook','tiktok')),
  tipo         text not null check (tipo in ('comentario','resposta','mensagem','fixar','coracao','gosto','ocultar')),
  id_externo   text,                          -- id do comentário/mensagem na plataforma
  id_video     text,                          -- vídeo/publicação onde aconteceu
  autor        text,                          -- nome público de quem escreveu (nunca contactos)
  recebido     text,                          -- o que a pessoa escreveu
  resposta     text,                          -- o que a personagem respondeu ou vai responder
  juiz         jsonb not null default '{}'::jsonb,  -- {veredito, motivo, motor}
  estado       text not null default 'novo'
               check (estado in ('novo','a-responder','pc-lote','publicado','lido-de-volta','chumbado','ignorado','erro')),
  canal        text not null default 'api' check (canal in ('api','pc-lote')),
  motor        text,
  erro         text,
  recebido_em  timestamptz,                   -- quando a pessoa comentou
  quando       timestamptz not null default now(),  -- quando o Hermes tratou
  unique (rede, tipo, id_externo)
);
create index if not exists redes_interacoes_fila_idx on public.redes_interacoes (canal, estado, quando);
create index if not exists redes_interacoes_conta_idx on public.redes_interacoes (conta, rede, quando desc);

create table if not exists public.redes_metricas (
  id         bigint generated always as identity primary key,
  conta      text not null,
  rede       text not null check (rede in ('youtube','instagram','facebook','tiktok','hotmart','etsy','shopify','meta-ads')),
  dia        date not null,
  id_video   text not null default '',        -- '' = número da conta inteira
  numeros    jsonb not null default '{}'::jsonb, -- visualizacoes, seguidores, retencao, cliques, vendas, gasto…
  fonte      text,                            -- API/endpoint de onde veio
  criado_em  timestamptz not null default now(),
  unique (conta, rede, dia, id_video)
);
create index if not exists redes_metricas_dia_idx on public.redes_metricas (dia desc, conta);

create table if not exists public.redes_experiencias (
  id             bigint generated always as identity primary key,
  conta          text not null,
  rede           text not null,
  semana_inicio  date not null,
  o_que_testou   text not null,               -- titulo, capa, hora, gancho, comentario fixado…
  antes          jsonb not null default '{}'::jsonb,
  depois         jsonb not null default '{}'::jsonb,
  decisao        text,                        -- manter, cortar, repetir
  estado         text not null default 'a-correr' check (estado in ('proposta','a-correr','medida','fechada')),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (conta, rede, semana_inicio)
);

alter table public.redes_interacoes   enable row level security;
alter table public.redes_metricas     enable row level security;
alter table public.redes_experiencias enable row level security;

-- Só admin pelo painel; o Hermes usa a chave de serviço (passa a RLS).
create policy redes_interacoes_admin   on public.redes_interacoes   for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy redes_metricas_admin     on public.redes_metricas     for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy redes_experiencias_admin on public.redes_experiencias for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.redes_interacoes, public.redes_metricas, public.redes_experiencias from anon;
