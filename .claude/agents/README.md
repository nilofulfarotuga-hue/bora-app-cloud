# Sistema de Agentes — Bora App

> Path: `bora_app/.claude/agents/` · Criado: Lote 1 (2026-06-22)

## SKILL vs AGENTE — a distinção

- **SKILL** = uma **ferramenta** especializada e determinística (ex.: `category-mapper-v2`,
  `backup-restore-table`). Faz uma coisa bem. Vive em `.claude/skills/`.
- **AGENTE** = um **orquestrador** com identidade, objetivo, limites e memória. **Chama skills**
  para executar; nunca duplica a lógica delas. Vive aqui em `.claude/agents/`.

> **Regra de ouro:** Agentes orquestram skills. O **CEO-AI é o dispatcher master** — escolhe que
> agente responde a cada tarefa. Todos os agentes leem `agent-memory.md` no arranque.

## Agentes disponíveis

| Agente | Propósito | Skills que usa | Robot B aware? |
|---|---|---|---|
| **obsidian-sync** | Sync unidirecional vault Obsidian → knowledge (SHA256, idempotente) | — (Bash/Read/Write) | Sim — escreve knowledge que o Robot B lê; respeita kill switches |
| **catalogo-visual** | Catálogo de mercados (não-parceiro) + imagens de categoria via nano-banana | category-mapper-v2, market-data-sync/cleaner, dedupe-market-products, weekly-market-prices, add-home-category, taxonomy-mapper, sync-market-photos | Não |
| **db-migrations** | Migrações Supabase seguras (dry-run, backup, rollback, bloqueio financeiro) | backup-restore-table | Não |
| **admin-sync** | Verifica cobertura no admin panel de toda feature nova (PT-BR) | — (Glob/Grep/Read) | Não |
| **seguranca-rls** | SEC-1 (RLS em falta) + SEC-2 (storage buckets) + hardening | storage-bucket-validator, audit-protected-zones | Não |
| **checkout-fixer** *(migrado)* | Diagnostica/corrige checkout flow | — | Não |
| **design-system-applier** *(migrado)* | Aplica design system nos ecrãs Flutter | — | Não |
| **e2e-test-builder** *(migrado)* | Testes E2E de fluxos críticos | — | Não |
| **notifications-integrator** *(migrado)* | FCM push live + consent GDPR | — | Não |

## Zonas protegidas (todos os agentes)
`dispatch_engine` · `pricing_service.dart` · triggers financeiros · Stripe webhook ·
RLS em `orders`/`wallets`/`ledger_entries`/`bora_tokens`. Robot A e Robot B são **intocáveis**.

## Como adicionar um novo agente
1. Copia `template.md` → `meu-agente.md`.
2. Preenche o contrato em 4 partes (Objetivo / Limites / Ferramentas / Protocolo) + as restantes
   secções (Identidade, Formato, Memória, **Admin Panel Check obrigatório**).
3. Adiciona uma linha à tabela acima **e** à secção "## Sistema de Agentes" do `CLAUDE.md`.
4. Frontmatter: `name` (== nome do ficheiro) e `description` obrigatórios. Omite `tools` se o
   agente precisar de MCP (herda tudo); declara `tools` explícitos se for só ficheiros/git.
