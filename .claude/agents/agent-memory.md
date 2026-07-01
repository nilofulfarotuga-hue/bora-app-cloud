---
name: agent-memory
description: Memória partilhada — regras globais lidas por TODOS os agentes no início de cada sessão.
version: 1.1.0
updated: 2026-06-23
---

# 🧠 Memória dos Agentes — Bora App

> **ESTE FICHEIRO É LIDO POR TODOS OS AGENTES NO INÍCIO DE CADA SESSÃO.**
> **Actualizado automaticamente quando o Danilo corrige uma regra.**
> Os números (pricing/tokens/comissões) vivem em `business_rules.md` — este ficheiro guarda
> as regras de *comportamento* dos agentes. Em conflito, `business_rules.md` vence nos números.

## Regras iniciais (v1.0 — 2026-06-22)

1. **Nunca gerar imagens sobre fotos reais de produtos ou restaurantes.**
2. **Admin panel em PT-BR sempre; app (cliente/estafeta/parceiro) em PT-PT sempre.**
3. **Todos os mercados são NÃO-PARCEIRO — nunca confundir** (pricing e markup diferem; consultar `business_rules.md`).
4. **Toda correcção do Danilo → adicionar como nova regra aqui, com data.**
5. **Toda migration destrutiva → backup obrigatório antes** (`backup-restore-table`).
6. **Toda feature nova → invocar o agente `admin-sync` no final.**

## Zonas protegidas (nunca tocar sem aprovação explícita do Danilo)
`dispatch_engine` · `pricing_service.dart` · triggers financeiros · Stripe webhook (v17) ·
RLS em `orders` / `wallets` / `ledger_entries` / `bora_tokens`.

## Robot A / Robot B
- **Robot A** = `support-chatbot` (Edge Function). **Robot B** = `robot-b` (Edge Function).
- **Intocáveis.** Nenhum agente cria loops autónomos paralelos ao Robot B nem desliga os seus
  kill switches. Crosstalk A↔B é tratado pela skill `ask-knowledge-base`, não por estes agentes.

## 🧠 Cérebro (Fase 2 — 2026-07-01)
- **Antes de trabalhar:** ler `.claude/.ai/knowledge/INDEX.md` e carregar só o teu tema.
- **Depois:** entregar um *handoff* ao agente `bibliotecario-cerebro` (o ÚNICO que escreve no
  Cérebro). Ver `.claude/.ai/knowledge/PROTOCOLO.md`. Aplicar só factos `estado: atual`.

## Agentes registados (25 — elenco canónico Fase 4, 2026-07-01)
**Domínio:** `cliente`🟢, `estafeta-motorista`🟡, `parceiro-restaurante`🟡, `parceiro-servicos`🟢,
`mercados`🟢, `favores`🟢, `pagamentos-wallet`🔴, `dispatch`🔴, `admin`🟢, `notificacoes`🟢, `chat-suporte`🟢.
**Ofício:** `flutter-ui`🟢, `backend-supabase`🟡, `seguranca`🟡, `dados-sql`🟢, `devops-ci`🟡,
`compliance-pt`🟡, `pesquisa-concorrencia`🟢, `catalogo-visual`🟢, `marketing-push`🟢, `obsidian-sync`🟢.
**Cérebro:** `bibliotecario-cerebro`🟡. **Juiz (Fase 4):** `juiz-revisor`🟡 — absorveu
`checkout-fixer` e `e2e-test-builder` como braços.

## 🧑‍⚖️ Gate do Juiz (Fase 4 — obrigatório para TODOS)
- Nenhum trabalho é ACEITE (commit/merge) sem o `juiz-revisor` passar as **3 camadas**, com o
  **chão determinístico** (`python .claude/juiz/anti_trapaca.py`, git diff) a correr **sempre primeiro**.
- Nunca apagar/enfraquecer/skipar um teste para fingir "verde" — o chão apanha mecanicamente
  (teste apagado, asserção enfraquecida, `expect(true)`, skip, valor esperado trocado, conserto-fantasma).
- Rejeição → gerar lição (`reflexao.py`) → handoff ao `bibliotecario-cerebro` → `procedural/licoes/`.

> Proteção: 🟢 zona segura · 🟡 sensível · 🔴 dinheiro = **PROPOSE-ONLY** (Trava bloqueia; lê+propõe).
> Gaveta de memória por agente no Cérebro: `escopo: agente:<nome>` (escrita só pelo Bibliotecário).
> **Renames Fase 3:** admin-sync→admin, dispatch-ops→dispatch, db-migrations→backend-supabase,
> seguranca-rls→seguranca, design-system-applier→flutter-ui, bi-analytics→dados-sql,
> notifications-integrator→notificacoes, crawler-mercados→mercados.

## Lições técnicas (Lote 1/2 — 2026-06-23)
> Aprendizagens de ambiente/processo. Não são regras de negócio.
- **MCP carrega pelo cwd de arranque.** `claude mcp list` e os tools MCP só funcionam quando a
  sessão arranca da pasta onde está o `.mcp.json` (= `bora_app/`).
- **nano-banana não carrega** se a sessão arrancar de `projetosflutter/` em vez de `bora_app/`.
  Sintoma: ToolSearch só devolve o Higgsfield (`mcp__e327f794…`) — **não substituir** por ele.
- **Agentes nativos (`.claude/agents/`) também só carregam com cwd=`bora_app/`.** Fora disso,
  executar o protocolo do agente inline (ler o `.md` e seguir os passos) com os MCP disponíveis.
- **`git push` pode falhar por commits remotos** (CI faz bump de versionCode no mesmo branch).
  Resolução: `git stash` do que estiver unstaged → `git pull --rebase` → `stash pop` → push.
- **44 Edge Functions locais** (não 43 — contagem corrigida em `3fe54b3`).
- **`design-system-applier` tinha hex stale** (`#2E7D32`/`#E65100`) — corrigido para
  `#16A34A`/`#F97316` em `fdcb8d0`.

## Histórico de correcções
<!-- Formato: - [YYYY-MM-DD] Regra: ... · Contexto: ... · Origem: Danilo -->
- [2026-06-22] Criação do sistema de agentes (Lote 1). Regras 1–6 estabelecidas.
- [2026-06-23] Lote 2: +4 agentes (bi-analytics, marketing-push, crawler-mercados, dispatch-ops).
  SEC-1/SEC-2 dry-run (read-only) feito — ver `sessions/2026-06-23-sec1-sec2-dryrun.md`.
  Lições técnicas de ambiente registadas acima. Origem: Danilo (prompts Lote 1/2).
- [2026-07-01] **Fase 3 (O Exército):** elenco canónico de 24 agentes. +10 novos (cliente,
  estafeta-motorista, parceiro-restaurante, parceiro-servicos, favores, chat-suporte,
  pagamentos-wallet🔴, dispatch🔴, devops-ci, compliance-pt, pesquisa-concorrencia) e 8 renames
  (ver acima). Níveis de proteção 🟢/🟡/🔴 + gaveta `agente:<nome>` + regras de despacho no CLAUDE.md
  (esquadrões pequenos + gatilho de paridade). Origem: Danilo (prompt Fase 3).
- [2026-07-01] **Fase 4 (O Juiz + Aprendizado):** +1 agente `juiz-revisor` (25 total). Gate
  anti-trapaça com chão determinístico (`.claude/juiz/*.py`, git diff — não é hook). Absorveu
  `checkout-fixer` e `e2e-test-builder` como braços. Ciclo de aprendizado: rejeição → lição →
  Bibliotecário → `procedural/licoes/`. Regra: NUNCA apagar/enfraquecer teste para fingir verde.
  Origem: Danilo (prompt Fase 4).
