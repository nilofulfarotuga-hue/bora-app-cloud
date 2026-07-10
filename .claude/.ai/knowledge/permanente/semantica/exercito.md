---
tema: exercito · escopo: projeto · estado: atual · atualizado: 2026-07-10 (Fase Marketing+Evolução)
id: exercito
tipo: conceito
origem: [.claude/agents/*.md, .claude/agents/agent-memory.md, CLAUDE.md]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 🎖️ Exército — elenco de agentes (Fase 3 + Juiz Fase 4 + Maestro Fase 5)

> Os contratos vivem em `.claude/agents/*.md`. Regras partilhadas em `.claude/agents/agent-memory.md`.
> **CEO-AI é o dispatcher master.** Princípio: agentes **orquestram** skills (ferramentas), nunca
> duplicam a lógica delas. Proteção: 🟢 zona segura · 🟡 sensível · 🔴 dinheiro = **PROPOSE-ONLY**
> (a Trava bloqueia a edição; o agente lê e propõe, o Danilo aprova). Cada agente tem gaveta de
> memória própria no Cérebro: `escopo: agente:<nome>`. Regras de despacho no `CLAUDE.md`.

## Elenco canónico — 29 agentes

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

### Juiz (Fase 4, 2026-07-01) — 25.º agente
- `juiz-revisor` 🟡 (**NOVO** — O Juiz) — gate anti-trapaça **obrigatório**: nenhum trabalho é
  aceite sem passar **3 camadas**, com o chão **determinístico** `.claude/juiz/anti_trapaca.py`
  (via git diff) a correr **sempre primeiro**. Rejeição → lição → handoff ao Bibliotecário.
  Contrato em `.claude/agents/juiz-revisor.md`; scripts em `.claude/juiz/`.
- **Braços do Juiz** (`absorbed_by: juiz-revisor`, `absorbed_date: 2026-07-01`):
  - `e2e-test-builder` — geração de teste (Flutter integration_test).
  - `checkout-fixer` — fixer de regressão de checkout.

### Central de Autonomia (Fase 5, 2026-07-01) — 26.º agente
- `maestro-autonomia` 🟡 (**NOVO** — O Loop) — dono do ciclo autónomo apontado ao backlog de
  **paridade admin** (auditoria 360°). Pega item → classifica nível (N1🟢/N2🟡/N3🔴) × zonas
  protegidas → esquadrão pequeno → **Juiz obrigatório** → posta na Central. Evolui `robot-b`.
  Arquitetura **híbrida**: `robot_suggestions` = a fila; `autonomy_goals` + `autonomy_backlog_items`
  = camada de goals (o `/goal`, o placar, os tetos). Ecrã `AdminAutonomyCenterScreen`.
  **Dial COMEÇA cauteloso** (`robot_b_auto_level1_enabled=false`); **kill switch** `robot_b_enabled`.
  Envelope de 5 paredes: Trava · Juiz · Tetos · Humano-acima-do-L1 · Kill switch.
  Contrato em `.claude/agents/maestro-autonomia.md`; detalhe em `episodica/decisoes.md` (Fase 5).

### Marketing + Evolução (Fase Marketing+Evolução, 2026-07-10) — 27.º–29.º agentes
> Nascidos na missão noturna 2026-07-09/10 (Fase 5 do prompt "Olho do Bora + Cérebro de
> Marca + Evolução + Hermes em tudo").
- `diretor-criativo` 🟢 (**NOVO**) — dono do `brand-brain.md` e da skill homónima; campanhas
  completas com gate anti-slop. Fronteira: **catálogo=produto** (`catalogo-visual`),
  **diretor=marca**. Nunca publica.
- `social-media` 🟢 (**NOVO**) — dono de `social-publisher` + `marketing-loop` (Postiz).
  NUNCA cria contas; NUNCA publica sem Juiz + aprovação explícita do Danilo; sem Postiz/contas
  → dry-run.
- `evolution-engine` 🟡 (**NOVO** — meta-agente) — evolução governada de skills: deteta
  padrões / reescreve (falhas>30% ou 2 rejeições do Juiz) / arquiva (90d) / funde (>70%) /
  divide (>600 linhas). Verde = draft→Juiz; vermelho/dinheiro/auth = SÓ PROPOSTA. **Nunca se
  auto-modifica.** ADR: `wiki/decisoes/2026-07-10-evolution-engine-governado.md` (EvoSkill →
  opção (b), conceitos nativos).

### Fase 4 — não tocar agora (2)
> **estado: superado (pela Fase 4, 2026-07-01).** `checkout-fixer` e `e2e-test-builder` deixam de
> estar "não tocar" e passam a **braços do Juiz** (ver secção "Juiz" acima).
- ~~`checkout-fixer`, `e2e-test-builder`.~~

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
