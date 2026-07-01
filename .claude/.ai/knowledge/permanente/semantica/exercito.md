---
tema: exercito · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# 🎖️ Exército — elenco de agentes

> Os contratos vivem em `.claude/agents/*.md`. Regras de comportamento partilhadas em
> `.claude/agents/agent-memory.md`. **CEO-AI é o dispatcher master.** Princípio: agentes
> **orquestram** skills (ferramentas), nunca duplicam a lógica delas.

## Guardião do Cérebro (Fase 2)
- **`bibliotecario-cerebro`** — o **único** que escreve no Cérebro. Verifica cada facto
  (8-checagens), faz dedup, marca `superado` (nunca apaga), parte ficheiros grandes, mantém o
  `INDEX.md`. Ver `.claude/agents/bibliotecario-cerebro.md` e `PROTOCOLO.md`.

## Lote 1 (2026-06-22)
- `obsidian-sync` — sync unidirecional vault Obsidian → `knowledge/from-obsidian/` (SHA256).
- `catalogo-visual` — catálogo de mercados (não-parceiro) + ícones/banners (nano-banana).
- `db-migrations` — migrações Supabase seguras (dry-run + backup + rollback; bloqueia zonas $).
- `admin-sync` — toda feature nova → verifica correspondência no admin panel (PT-BR).
- `seguranca-rls` — SEC-1 (RLS em falta) + SEC-2 (storage buckets) + hardening.
- Migrados: `checkout-fixer`, `design-system-applier`, `e2e-test-builder`, `notifications-integrator`.

## Lote 2 (2026-06-23)
- `bi-analytics` — dashboards read-only (só SELECT).
- `marketing-push` — push segmentado + promo codes + banners (aprovação > 50 utilizadores).
- `crawler-mercados` — sync mercados não-parceiro (só categorias estáveis; nunca markup na DB).
- `dispatch-ops` — monitor read-only do dispatch (nunca modifica o motor).

## Regra obrigatória
Toda feature nova → invocar `admin-sync` no fim (secção "Admin Panel Needed?" em cada agente).
Robot A (`support-chatbot`) e Robot B (`robot-b`) são **intocáveis**.
