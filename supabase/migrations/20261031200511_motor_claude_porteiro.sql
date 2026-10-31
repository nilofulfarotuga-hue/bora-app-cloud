-- 20261031_motor_claude_porteiro.sql
-- Missao motor-claude-2026-10-31 (Bloco 2 da retoma-geral-2026-10-31).
-- Ordem do Danilo 31/10 06:08: os robos usam PRIMEIRO o credito da API do Claude e, quando acaba,
-- a rotacao gratis. Este ficheiro NAO foi aplicado: vai para o passo PUBLICAR.
--
-- O que cria:
--   1. public.ia_gastos      - livro de gastos de IA (um registo por chamada ao Claude; VPS e Edge Functions)
--   2. public.licoes_robos   - licoes dos robos (o que errou, regra certa), lidas por todos os robos
--   3. platform_settings claude_*  - credito lido na Console a 31/10 10:45 UTC e interruptores por robo
--   4. public.ia_claude_pode(prioridade, robo) - a MESMA regra do porteiro da VPS, para as Edge Functions
--   5. assistant_tenants: cadeias com o porteiro (Claude) a frente e so motores gratis vivos atras
-- Nada aqui mexe em precos, comissoes, ganhos, Stripe, carteira, tokens, pedidos nem estafetas.


-- 1. Livro de gastos ----------------------------------------------------------------------------
create table if not exists public.ia_gastos (
  id                   bigserial primary key,
  quando               timestamptz not null default now(),
  maquina              text not null default 'vps',          -- vps | edge
  robo                 text,                                  -- quem pediu (origem / nome da funcao)
  perfil               text,                                  -- claude-cliente, claude-decisao, ...
  prioridade           smallint,                              -- 1 clientes, 2 Emerson e decisoes, 3 agentes e volume
  modelo               text not null,
  tokens_entrada       integer not null default 0,
  tokens_saida         integer not null default 0,
  tokens_cache_escrita integer not null default 0,
  tokens_cache_leitura integer not null default 0,
  custo_usd            numeric(12,6) not null default 0,      -- precos oficiais 31/10 (USD por milhao)
  ms                   integer,
  ok                   boolean not null default true,
  erro                 text,
  lote                 boolean not null default false         -- true = Batch API (metade do preco)
);
create index if not exists ia_gastos_quando_idx on public.ia_gastos (quando desc);
create index if not exists ia_gastos_robo_idx on public.ia_gastos (robo, quando desc);
alter table public.ia_gastos enable row level security;
drop policy if exists ia_gastos_admin on public.ia_gastos;
create policy ia_gastos_admin on public.ia_gastos for all using (is_admin()) with check (is_admin());
revoke all on public.ia_gastos from anon;
comment on table public.ia_gastos is 'Livro de gastos da API do Claude (porteiro do credito, missao motor-claude 31/10/2026). Escrito pelo Motor Bora (VPS) e pelas Edge Functions com a service role.';

-- 2. Licoes dos robos ---------------------------------------------------------------------------
create table if not exists public.licoes_robos (
  id            bigserial primary key,
  criada_em     timestamptz not null default now(),
  robo          text not null,                 -- whatsapp-bora, assistente-boom-burger, emerson, suporte-app, todos
  errou         text not null,                 -- o que o robo fez mal
  regra         text not null,                 -- a regra certa
  origem        text not null default 'escriba', -- danilo-telegram | danilo-assumiu-conversa | cliente-reclamou | juiz | critico | escriba | simulacao
  vezes         integer not null default 1,     -- o critico junta as repetidas e soma aqui
  ativa         boolean not null default true,
  arquivada_em  timestamptz,
  arquivada_por text,
  editada_em    timestamptz
);
create index if not exists licoes_robos_ativas_idx on public.licoes_robos (ativa, robo);
alter table public.licoes_robos enable row level security;
drop policy if exists licoes_robos_admin on public.licoes_robos;
create policy licoes_robos_admin on public.licoes_robos for all using (is_admin()) with check (is_admin());
revoke all on public.licoes_robos from anon;
comment on table public.licoes_robos is 'Caderno de erros dos robos (igual ao erros-aprendidos do Claude.ai). Todos os robos leem as ativas; o critico de noite junta repetidas e arquiva.';

-- 3. Credito e interruptores (lidos na Console a 31/10/2026 10:45 UTC) ---------------------------
insert into public.platform_settings (key, value, description, category, is_secret, updated_at) values
  ('claude_credito_atual_usd', '211.82'::jsonb,
   'Credito promocional da API do Claude que resta (USD). Lido na Console (Billing) a 31/10/2026 10:45 UTC: 100,00 + 111,82.', 'ia', true, now()),
  ('claude_credito_lido_em', '"2026-10-31T10:45:00Z"'::jsonb,
   'Quando o valor claude_credito_atual_usd foi lido. O gasto conta a partir daqui.', 'ia', true, now()),
  ('claude_credito_validade', '[{"usd": 100.00, "expira": "2026-11-28", "origem": "Max 25/10"}, {"usd": 111.82, "expira": "2026-12-02", "origem": "Ultra 29/10"}]'::jsonb,
   'Validade de cada credito promocional (Console > Billing > Creditos promocionais).', 'ia', true, now()),
  ('claude_proximo_credito', '"2026-11-30"'::jsonb,
   'Data do proximo credito mensal (claude.ai > Definicoes > Cobranca).', 'ia', true, now()),
  ('claude_credito_mensal_usd', '200'::jsonb,
   'Credito mensal da API incluido no plano Ultra (USD). Nao passa para o mes seguinte.', 'ia', true, now()),
  ('claude_robos', '{
      "ligado": true,
      "claude-cliente":     {"usar": true, "modelo": "claude-sonnet-5-5", "prioridade": 1, "nome": "Respostas a clientes (WhatsApp das lojas e da Bora, suporte)"},
      "claude-classificar": {"usar": true, "modelo": "claude-haiku-5-5",  "prioridade": 1, "nome": "Classificar mensagens de clientes"},
      "claude-decisao":     {"usar": true, "modelo": "claude-sonnet-5-5", "prioridade": 2, "nome": "Emerson e decisoes (decidir, despachante, torre, juiz)"},
      "claude-agente":      {"usar": true, "modelo": "claude-haiku-5-5",  "prioridade": 3, "nome": "Agentes do Hermes"},
      "claude-volume":      {"usar": true, "modelo": "claude-haiku-5-5",  "prioridade": 3, "nome": "Radares e volume"},
      "edge-decidir":       {"usar": true, "modelo": "claude-sonnet-5-5", "prioridade": 2, "nome": "Edge Function decidir"},
      "edge-suporte":       {"usar": true, "modelo": "claude-sonnet-5-5", "prioridade": 1, "nome": "Chat de ajuda na app"},
      "edge-admin":         {"usar": true, "modelo": "claude-sonnet-5-5", "prioridade": 2, "nome": "Assistente do painel admin"},
      "edge-robos":         {"usar": true, "modelo": "claude-haiku-5-5",  "prioridade": 3, "nome": "Robos da app com troca de modelo"}
   }'::jsonb,
   'Interruptor "usar Claude" e modelo por robo (Haiku ou Sonnet; Opus nunca automatico). Editavel no painel /admin/motores.', 'ia', true, now())
on conflict (key) do nothing;

-- 4. A regra do porteiro, para as Edge Functions -------------------------------------------------
-- Igual a /opt/motor-bora/motor_bora/porteiro.py:
--   resta      = credito lido - gasto desde a leitura
--   parte/dia  = (resta + gasto de hoje) / dias ate ao proximo credito (minimo 1)
--   P1 usa enquanto houver credito; P2 ate a parte do dia; P3 ate metade da parte do dia.
create or replace function public.ia_claude_pode(p_prioridade int, p_robo text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_credito   numeric := coalesce((select (value #>> '{}')::numeric from platform_settings where key = 'claude_credito_atual_usd'), 0);
  v_lido      timestamptz := coalesce((select (value #>> '{}')::timestamptz from platform_settings where key = 'claude_credito_lido_em'), now());
  v_proximo   date := coalesce((select (value #>> '{}')::date from platform_settings where key = 'claude_proximo_credito'), (current_date + 30));
  v_robos     jsonb := coalesce((select value from platform_settings where key = 'claude_robos'), '{}'::jsonb);
  v_hoje_lx   date := (now() at time zone 'Europe/Lisbon')::date;
  v_gasto     numeric;
  v_gasto_dia numeric;
  v_resta     numeric;
  v_dias      int;
  v_parte     numeric;
  v_limite    numeric;
  v_pode      boolean;
  v_motivo    text;
  v_modelo    text;
begin
  select coalesce(sum(custo_usd), 0) into v_gasto from ia_gastos where quando >= v_lido;
  select coalesce(sum(custo_usd), 0) into v_gasto_dia from ia_gastos
   where (quando at time zone 'Europe/Lisbon')::date = v_hoje_lx;
  v_resta := v_credito - v_gasto;
  v_dias  := greatest(1, v_proximo - v_hoje_lx);
  v_parte := greatest(0, v_resta + v_gasto_dia) / v_dias;
  v_modelo := coalesce(v_robos -> p_robo ->> 'modelo', case when p_prioridade <= 2 then 'claude-sonnet-5-5' else 'claude-haiku-5-5' end);
  if v_modelo like 'claude-opus%' then v_modelo := 'claude-sonnet-5-5'; end if;   -- Opus nunca automatico

  if coalesce((v_robos ->> 'ligado')::boolean, true) = false then
    v_pode := false; v_motivo := 'Claude desligado no painel';
  elsif p_robo is not null and (v_robos -> p_robo) is not null and coalesce((v_robos -> p_robo ->> 'usar')::boolean, true) = false then
    v_pode := false; v_motivo := 'Claude desligado para este robo';
  elsif v_resta <= 0 then
    v_pode := false; v_motivo := 'credito do mes acabado';
  elsif p_prioridade <= 1 then
    v_pode := true; v_motivo := 'P1 usa enquanto houver credito';
  else
    v_limite := case when p_prioridade = 2 then v_parte else v_parte * 0.5 end;
    v_pode := v_gasto_dia < v_limite;
    v_motivo := case when v_pode then 'dentro da parte do dia' else 'parte do dia esgotada para P' || p_prioridade end;
  end if;

  return jsonb_build_object('pode', v_pode, 'motivo', v_motivo, 'modelo', v_modelo,
    'resta_usd', round(v_resta, 4), 'gasto_hoje_usd', round(v_gasto_dia, 4),
    'parte_do_dia_usd', round(v_parte, 4), 'dias_ate_proximo', v_dias);
end;
$$;
revoke all on function public.ia_claude_pode(int, text) from public, anon, authenticated;
grant execute on function public.ia_claude_pode(int, text) to service_role;

-- 5. Cadeias do WhatsApp das lojas: porteiro (Claude Sonnet 5.5) a frente, depois a rotacao gratis viva
--    (medida a 29/10). Sai o go:* e o gemini2:* (mortos: 401 e 402). O modo dos tenants NAO muda.
update public.assistant_tenants
   set motor = 'porteiro:perfil:claude-cliente',
       motores_reserva = array['groq:openai/gpt-oss-120b', 'gemini:gemini-3.1-flash-lite', 'groq:qwen/qwen3.8-27b',
                               'gemini:gemini-3.5-flash-lite', 'groq:openai/gpt-oss-20b', 'gemini:gemini-3-flash-preview']
 where slug in ('boom-burger', 'secretario-demo', 'mister-navalha');


-- Prova depois de aplicar (so leitura):
--   select public.ia_claude_pode(1, 'claude-cliente');   -- pode=true enquanto houver credito
--   select public.ia_claude_pode(3, 'claude-agente');    -- pode=false se o gasto de hoje passar metade da parte do dia
--   select slug, mode, motor, motores_reserva from public.assistant_tenants;  -- modos iguais (teste/teste/desligado)

-- =====================================================================
