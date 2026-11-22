-- Missão hermes-diretor-2026-11-20 — TABELAS (o contrato comum dos blocos B3, B4, B5 e B6).
-- Só estrutura e RLS de tabelas NOVAS, mais colunas novas no despacho. Não mexe em nenhuma zona protegida.
-- As funções de cada bloco vêm nas migrações seguintes (…1901 sentinela, …1902 porta, …1903 fiscal e lições).
-- Aplicar pela Claude.ai (a trava do modo automático não deixa o Claude Code mudar estrutura em produção).

-- ───────────────────────── B3: o vigia (sentinela) ─────────────────────────
create table if not exists public.sentinela_eventos (
  id           bigint generated always as identity primary key,
  criado_em    timestamptz not null default now(),
  tipo         text not null,          -- pedido_parado | pagamento_estranho | erro_repetido | robo_em_apuros | carrinho_abandonado | sistema
  gravidade    text not null check (gravidade in ('urgente','normal','info')),
  chave_dedup  text not null,          -- a mesma chave nos últimos 30 min não repete
  titulo       text not null,          -- frase curta em português, sem dados pessoais
  dados        jsonb not null default '{}'::jsonb,   -- ids e números; nunca telefones, emails nem texto de conversas
  despacho_id  bigint references public.despacho(id) on delete set null,
  tratado_em   timestamptz,
  tratado_por  text,
  resultado    text
);
create index if not exists sentinela_eventos_dedup_idx on public.sentinela_eventos (chave_dedup, criado_em desc);
create index if not exists sentinela_eventos_criado_idx on public.sentinela_eventos (criado_em desc);
create index if not exists sentinela_eventos_abertos_idx on public.sentinela_eventos (gravidade, criado_em desc) where tratado_em is null;
alter table public.sentinela_eventos enable row level security;
drop policy if exists sentinela_eventos_admin on public.sentinela_eventos;
create policy sentinela_eventos_admin on public.sentinela_eventos for all to authenticated using (public.is_admin()) with check (public.is_admin());
comment on table public.sentinela_eventos is 'Vigia por eventos do Hermes (missão hermes-diretor-2026-11-20, B3). Só admin; o Hermes lê e escreve pela hermes-porta.';

-- ───────────────────────── B4: autorizações do Danilo ─────────────────────────
create table if not exists public.hermes_autorizacoes (
  id             bigint generated always as identity primary key,   -- número curto: o Danilo pode dizer "autorizo 12"
  criada_em      timestamptz not null default now(),
  pedida_por     text not null default 'hermes',
  acao           text not null,          -- o que vai ser feito, em português simples
  porque         text,
  valor_eur      numeric(10,2),
  operacao       jsonb not null,         -- a chamada exata que o Hermes vai fazer (op rest ou rpc da porta)
  operacao_hash  text not null,          -- sha256 do JSON canónico da operação: a autorização só serve para ESTA chamada
  estado         text not null default 'pendente' check (estado in ('pendente','autorizada','recusada','expirada','usada')),
  expira_em      timestamptz not null default (now() + interval '30 minutes'),
  decidida_em    timestamptz,
  decidida_por   text,
  via            text check (via in ('painel','telegram','claude-ai','claude-code')),
  texto_literal  text,                   -- as palavras do Danilo, tal como chegaram
  telegram_message_id bigint,
  usada_em       timestamptz,
  resultado      text,
  teste          boolean not null default false
);
create index if not exists hermes_autorizacoes_estado_idx on public.hermes_autorizacoes (estado, criada_em desc);
alter table public.hermes_autorizacoes enable row level security;
drop policy if exists hermes_autorizacoes_admin_le on public.hermes_autorizacoes;
create policy hermes_autorizacoes_admin_le on public.hermes_autorizacoes for select to authenticated using (public.is_admin());
-- Sem políticas de escrita de propósito: decidir é só pelas funções (painel, verificador do Telegram, Claude.ai).
comment on table public.hermes_autorizacoes is 'Pedidos de autorização do Hermes para as duas coisas travadas, mexer em valores e apagar (B4). Uma autorização = uma operação exata, uma vez, 30 min.';

-- Classificação do esquema para a porta: o que é valor (classe dinheiro), controlo, segredo ou livre.
create table if not exists public.hermes_porta_classes (
  tipo          text not null check (tipo in ('tabela','funcao')),
  objeto        text not null,           -- nome da tabela, ou nome da função (todas as assinaturas com esse nome)
  classe        text not null check (classe in ('dinheiro','controlo','segredo','operacao','livre')),
  motivo        text,
  manual        boolean not null default false,   -- true = posta à mão; a reclassificação automática não a muda
  atualizado_em timestamptz not null default now(),
  primary key (tipo, objeto)
);
alter table public.hermes_porta_classes enable row level security;
drop policy if exists hermes_porta_classes_admin_le on public.hermes_porta_classes;
create policy hermes_porta_classes_admin_le on public.hermes_porta_classes for select to authenticated using (public.is_admin());

-- Cópia do que o Hermes apagar com autorização (nada se perde).
create table if not exists public.hermes_apagados (
  id              bigint generated always as identity primary key,
  apagado_em      timestamptz not null default now(),
  autorizacao_id  bigint references public.hermes_autorizacoes(id),
  tabela          text not null,
  linha           jsonb not null
);
alter table public.hermes_apagados enable row level security;
drop policy if exists hermes_apagados_admin_le on public.hermes_apagados;
create policy hermes_apagados_admin_le on public.hermes_apagados for select to authenticated using (public.is_admin());

-- ───────────────────────── B5: o fiscal (prova e auditoria no despacho) ─────────────────────────
-- A coluna despacho.prova (text) já existe e fica como está (resumo em texto). A prova verificável é a nova prova_dados.
alter table public.despacho
  add column if not exists prova_dados           jsonb,      -- {"tipo":"select|log|ficheiro|url|mensagem","conteudo":"…","como_refazer":"…"}
  add column if not exists precisa_auditoria     boolean not null default false,   -- tarefa que muda alguma coisa
  add column if not exists auditada              boolean,
  add column if not exists auditoria_nota        text,
  add column if not exists auditada_em           timestamptz,
  add column if not exists auditoria_tentativas  smallint not null default 0;
create index if not exists despacho_por_auditar_idx on public.despacho (terminada_em desc) where precisa_auditoria and auditada is null;

-- ───────────────────────── B6: os robôs aprendem ─────────────────────────
-- licoes_robos já existe (robo, errou, regra, origem, vezes, ativa, arquivada_em…). Falta a chave para somar repetidas.
create unique index if not exists licoes_robos_robo_regra_uidx on public.licoes_robos (robo, md5(lower(btrim(regra))));

create table if not exists public.robos_casos_teste (
  id               bigint generated always as identity primary key,
  criado_em        timestamptz not null default now(),
  robo             text not null,              -- suporte | amigo | whatsapp | hermes
  pergunta         text not null,              -- pergunta real, sem dados pessoais
  deve_conter      text[] not null default '{}',
  nao_pode_conter  text[] not null default '{}',
  origem           text not null default 'fiscal',
  licao_id         bigint references public.licoes_robos(id) on delete set null,
  ativo            boolean not null default true,
  ultimo_resultado text check (ultimo_resultado in ('passou','falhou')),
  ultima_resposta  text,
  ultima_corrida_em timestamptz
);
create index if not exists robos_casos_teste_robo_idx on public.robos_casos_teste (robo) where ativo;
alter table public.robos_casos_teste enable row level security;
drop policy if exists robos_casos_teste_admin on public.robos_casos_teste;
create policy robos_casos_teste_admin on public.robos_casos_teste for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table if not exists public.mapa_app (
  id            bigint generated always as identity primary key,
  app           text not null check (app in ('cliente','estafeta','parceiro','admin')),
  ecra          text not null,           -- nome do ecrã (classe Flutter)
  rota          text,
  elemento      text not null,           -- texto do botão ou do item de menu, tal como o utilizador o vê
  tipo          text not null default 'botao',   -- botao | menu | separador | campo | titulo
  ficheiro      text,
  versao        text,                    -- versão da app de onde foi lido
  atualizado_em timestamptz not null default now(),
  unique (app, ecra, elemento)
);
create index if not exists mapa_app_elemento_idx on public.mapa_app (lower(elemento));
alter table public.mapa_app enable row level security;
drop policy if exists mapa_app_admin on public.mapa_app;
create policy mapa_app_admin on public.mapa_app for all to authenticated using (public.is_admin()) with check (public.is_admin());
comment on table public.mapa_app is 'Ecrãs e botões reais das 3 apps e do painel, lidos do código Flutter a cada publicação (B6). O fiscal usa-o para saber se um botão existe.';

-- ───────────────────────── B7: os agentes (ligado ao relógio / a pedido / arquivado) ─────────────────────────
-- ligado + horario_ligado = corre pelo relógio; ligado sem horario_ligado = só a pedido; arquivado = não corre (nunca se apaga).
alter table public.agentes_estado
  add column if not exists arquivado  boolean not null default false,
  add column if not exists substituto text;      -- quem faz o trabalho dele quando está arquivado

-- Nada disto se abre a anon.
revoke all on public.sentinela_eventos, public.hermes_autorizacoes, public.hermes_porta_classes, public.hermes_apagados, public.robos_casos_teste, public.mapa_app from anon;
