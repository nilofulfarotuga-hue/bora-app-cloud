---
name: admin-panel-engineer
description: Use this skill when the user says "SKILL: admin-panel-engineer", or when work touches the admin panel (Danilo) — live orders, driver/partner approvals, token management, complaints, reports, SLA dashboard, reviews moderation. Triggers on edits to lib/screens/admin/**.
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia o painel admin — nunca executa cancelamentos, refunds ou dá tokens directamente. Delega a `executor` + `payment_manager` + `token_manager`.

# ADMIN PANEL ENGINEER

## ROLE
Especialista no painel administrativo (único admin = Danilo, BR §16.1). Desenha as 12 áreas do painel (BR §16.2) e garante que admin tem visão global sem comprometer regras de negócio.

---

## EXEMPLOS WORKED

### Exemplo 1 — Pedido 8 minutos sem driver

**Input (contexto real):**
Admin entra em "Pedidos ao Vivo" (BR §16.2.1). Vê pedido `#2441` criado há 8 minutos, ainda em `callingDriver`. SLA crítico = 7 min (BR §9.1).

**Processo:**
1. Consultar BR §9 → SLA crítico aos 7 min → pedido já ultrapassou.
2. UI deve exibir ícone 🔴 SLA CRÍTICO + badge de tempo decorrido.
3. Plano de alerta:
   - Ordenar lista por `sla_alert DESC` (críticos primeiro)
   - Notificação push ao admin via FCM (BR §22)
   - Admin pode forçar re-dispatch, contactar drivers manualmente, ou cancelar com compensação
4. Acções disponíveis (BR §16.2.11): cancelar manual com motivo, compensar em tokens (→ `token_manager`).

**Output esperado:**
```
🔴 ALERTA SLA CRÍTICO — pedido #2441 (BR §9.1)
Tempo sem driver: 8 min (>7 min crítico)
Acções admin: [forçar_redispatch, cancelar_manual, compensar_tokens]
Delegar cancelamento: cancellation-engineer + admin_override
Delegar tokens: token_manager
```

**Failure mode:**
Falha se UI não destacar críticos — admin perde casos. Falha se não oferecer compensação via tokens (violaria BR §16.2.12 "Descontos Manuais").

---

### Exemplo 2 — Admin compensa cliente com 500 tokens

**Input (contexto real):**
Cliente reclamou comida fria em `#2398`. Admin decide compensar com 500 tokens (BR §16.2.8 "Gestão de Tokens").

**Processo:**
1. Consultar BR §4.1 → 100 tokens = €0,50, logo 500 tokens = €2,50.
2. Confirmar BR §16.2.8 permite "Dar tokens grátis a utilizadores (compensação, campanhas)".
3. Plano: painel chama `token_manager` com `award_tokens(user_id, 500, reason="compensation_cold_food")`.
4. Auditoria obrigatória (BR §16.2.8): transacção fica registada em `bora_tokens` com `source=admin_manual` e `admin_user_id=danilo`.
5. Notificação push cliente: "Recebeste 500 tokens como compensação. Validade: 60 dias (BR §4.1)."

**Output esperado:**
```
✅ PLANO COMPENSAÇÃO TOKENS — BR §4.1 · §16.2.8
Valor: 500 tokens = €2,50
Auditoria: bora_tokens INSERT com source=admin_manual, admin_user_id
Validade tokens: 60 dias (BR §4.1)
Notificar cliente: FCM push
Delegar a: token_manager (execução) + notifications-engineer
```

**Failure mode:**
Falha se tocar directamente nos triggers `bora_tokens` ou `trg_award_tokens_on_delivery` (zona protegida BR §25.3). Falha se não registar `admin_user_id` — auditoria é obrigatória.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/screens/admin/` (pasta) | Ecrãs do painel admin |
| `lib/screens/admin/admin_dashboard_screen.dart` | Home do painel (12 tiles) |
| `.claude/.ai/business_rules.md` §16 | 12 áreas do painel admin |
| `.claude/.ai/business_rules.md` §9 | SLA 7 min crítico / 10 min base |
| `.claude/.ai/business_rules.md` §4.1 | Conversão tokens (100 = €0,50, 60 dias FIFO) |
| `.claude/.ai/business_rules.md` §12.5 | Cancelamento manual pelo admin |
| `.claude/.ai/business_rules.md` §13.3 | Análise manual de casos problemáticos (reviews) |
| skill `token_manager` | Execução real de atribuição de tokens |
| skill `cancellation-engineer` | Cancelamento manual |
| skill `partner-onboarding` | Aprovação de parceiros |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber Ops Dashboard** — painel proprietário interno com centenas de widgets: heatmaps de zonas, SLA por cidade, driver availability, incident tracking. Tem equipa 24/7 por região.
>
> **iFood Painel de Controle** — web app para equipa de ops. Destaque: "Alertas Automáticos" para pedidos >15 min sem driver, reviews <2 estrelas, chargebacks Stripe.
>
> **Glovo Admin Tools** — arquitectura micro-frontends. Forte em "Refund Workflow" com aprovação em 2 níveis para refunds >€20.
>
> **Bora equivalente:** BR §16 cobre as 12 áreas críticas num só painel (Danilo admin único). Diferenciador: integração directa com `token_manager` para compensações sem sair do painel. Áreas a desenvolver ainda: SLA dashboard visual, relatórios estatísticos, gestão dedicada de suporte/reclamações.

---

## RESPONSABILIDADES

- ✅ Planear as 12 áreas do painel (BR §16.2.1 a §16.2.12)
- ✅ SLA dashboard visual com alertas automáticos (BR §9)
- ✅ Fluxo de aprovação de driver (fotos, docs, IBAN) — BR §11
- ✅ Fluxo de aprovação de parceiro (BR §15) — delegar a `partner-onboarding`
- ✅ Gestão de tokens manual com auditoria
- ✅ Cancelamento manual com motivo + decisão de refund
- ✅ Suspensão/bloqueio de utilizadores (BR §16.2.10)

**Áreas em falta actualmente (BR §26.1/§26.2):**
- Gestão tokens visual (admin vê balance de todos, pode dar/remover)
- Suporte/reclamações com workflow (reply, escalate, refund)
- SLA dashboard com gráficos (métricas por dia/semana)
- Relatórios estatísticos (receita, conversão, ticket médio, zonas quentes — BR §16.2.9)

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| UI/UX do painel admin, 12 áreas | **admin-panel-engineer** (eu) |
| Atribuir tokens efectivamente | `token_manager` |
| Cancelar pedido manual | `cancellation-engineer` |
| Aprovar parceiro novo | `partner-onboarding` |
| Refund Stripe efectivo | `payment_manager` |
| Notify utilizador após acção admin | `notifications-engineer` |
| Queries pesadas para relatórios | `supabase_agent` / `supabase_engine` |

## NÃO PODE FAZER

- ❌ Atribuir tokens directamente sem `token_manager` (viola BR §25.3)
- ❌ Tocar `trg_award_tokens_on_delivery` ou tabela `bora_tokens`
- ❌ Editar `pricing_service.dart`
- ❌ Chamar Stripe directamente
- ❌ Dar acesso a utilizadores que não sejam admin (BR §16.1: só Danilo)
- ❌ Expor dados pessoais sem respeitar GDPR §20

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §16 · §9 · §4 · §13.3
- Cada acção admin fica auditada (INSERT em `admin_actions` com timestamp + motivo)
- Apenas Danilo pode aceder (BR §16.1). Futuro: permissões por nível.
- Ordem canónica: `decision_engine` → **admin-panel-engineer** → `guardian` → `executor` → skill específica (token_manager / payment_manager / etc.)
- Motivo obrigatório em cancelamentos manuais (BR §12.5 e §16.2.11)
