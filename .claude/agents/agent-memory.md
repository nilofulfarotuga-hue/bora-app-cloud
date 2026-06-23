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

## Agentes registados (13)
**Lote 1:** `obsidian-sync`, `catalogo-visual`, `db-migrations`, `admin-sync`, `seguranca-rls`
+ migrados `checkout-fixer`, `design-system-applier`, `e2e-test-builder`, `notifications-integrator`.
**Lote 2 (2026-06-23):** `bi-analytics`, `marketing-push`, `crawler-mercados`, `dispatch-ops`.

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
