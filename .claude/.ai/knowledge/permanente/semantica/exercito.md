---
tema: exercito · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# 🎖️ Exército — elenco de agentes (Fase 3)

> Os contratos vivem em `.claude/agents/*.md`. Regras partilhadas em `.claude/agents/agent-memory.md`.
> **CEO-AI é o dispatcher master.** Princípio: agentes **orquestram** skills (ferramentas), nunca
> duplicam a lógica delas. Proteção: 🟢 zona segura · 🟡 sensível · 🔴 dinheiro = **PROPOSE-ONLY**
> (a Trava bloqueia a edição; o agente lê e propõe, o Danilo aprova). Cada agente tem gaveta de
> memória própria no Cérebro: `escopo: agente:<nome>`. Regras de despacho no `CLAUDE.md`.

## Elenco canónico — 24 agentes

### Domínio (11)
- `cliente` 🟢 — ecrãs e fluxos do cliente.
- `estafeta-motorista` 🟡 — fluxo do estafeta / TVDE.
- `parceiro-restaurante` 🟡 — onboarding e operação de restaurantes.
- `parceiro-servicos` 🟢 — reservas/serviços (barbearias etc.).
- `mercados` 🟢 (ex-`crawler-mercados`) — sync mercados não-parceiro; só categorias estáveis; nunca markup na DB.
- `favores` 🟢 — favores/errands + talão.
- `pagamentos-wallet` 🔴 — dinheiro/wallet; **PROPOSE-ONLY**, espera "vai".
- `dispatch` 🔴 (ex-`dispatch-ops`) — motor de dispatch; **PROPOSE-ONLY**, nunca modifica o motor.
- `admin` 🟢 (ex-`admin-sync`) — guardião da paridade; toda feature nova → ecrã de gestão (PT-BR).
- `notificacoes` 🟢 (ex-`notifications-integrator`) — FCM/push + consent GDPR.
- `chat-suporte` 🟢 — suporte/FAQ (Robot A intocável).

### Ofício (10)
- `flutter-ui` 🟢 (ex-`design-system-applier`) — design system nos ecrãs Flutter.
- `backend-supabase` 🟡 (ex-`db-migrations`) — migrações seguras; bloqueia zonas $.
- `seguranca` 🟡 (ex-`seguranca-rls`) — RLS + storage buckets + hardening (nunca RLS financeira).
- `dados-sql` 🟢 (ex-`bi-analytics`) — dashboards read-only (só SELECT).
- `devops-ci` 🟡 (**NOVO**) — release/CI.
- `compliance-pt` 🟡 (**NOVO** — buraco da auditoria) — TVDE IMT/DL 45/2018, KYC, GDPR.
- `pesquisa-concorrencia` 🟢 (**NOVO**) — benchmark/paridade de UX.
- `catalogo-visual` 🟢 — catálogo de mercados (não-parceiro) + ícones/banners (nano-banana).
- `marketing-push` 🟢 — push segmentado + promo codes + banners.
- `obsidian-sync` 🟢 — sync unidirecional vault Obsidian → `knowledge/from-obsidian/` (SHA256).

### Cérebro (1)
- `bibliotecario-cerebro` 🟡 — o **único** que escreve no Cérebro. 8-checagens, dedup, marca
  `superado` (nunca apaga), parte ficheiros grandes, mantém o `INDEX.md`. Ver `PROTOCOLO.md`.

### Fase 4 — não tocar agora (2)
- `checkout-fixer`, `e2e-test-builder`.

## Regras obrigatórias
- **GATILHO DE PARIDADE:** toda feature nova de domínio → convocar também `admin` no fim
  (secção "Admin Panel Needed?" em cada agente).
- **Esquadrões pequenos:** líder + 2 a 4 agentes; fan-out só em varreduras grandes.
- Robot A (`support-chatbot`) e Robot B (`robot-b`) são **intocáveis**. CEO-AI = dispatcher master.

## História — superado pela Fase 3 (2026-07-01)
> Mantido para rasto; **estado: superado**. Não aplicar — o elenco atual é o de cima.
- **Lote 1 (2026-06-22):** `obsidian-sync`, `catalogo-visual`, `db-migrations`, `admin-sync`,
  `seguranca-rls`; migrados `checkout-fixer`, `design-system-applier`, `e2e-test-builder`,
  `notifications-integrator`.
- **Lote 2 (2026-06-23):** `bi-analytics`, `marketing-push`, `crawler-mercados`, `dispatch-ops`.
- Renomeados na Fase 3: admin-sync→`admin`, dispatch-ops→`dispatch`, db-migrations→`backend-supabase`,
  seguranca-rls→`seguranca`, design-system-applier→`flutter-ui`, bi-analytics→`dados-sql`,
  notifications-integrator→`notificacoes`, crawler-mercados→`mercados`. Novos: `cliente`,
  `estafeta-motorista`, `parceiro-restaurante`, `parceiro-servicos`, `favores`, `pagamentos-wallet`,
  `chat-suporte`, `devops-ci`, `compliance-pt`, `pesquisa-concorrencia`.
