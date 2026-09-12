# Bugs e Problemas Conhecidos — Bora App

## 🔴 Críticos (bloqueadores de lançamento)

### ~~BUG-001 — Stripe sem URL de produção~~ ✅ RESOLVIDO
- **Resolução (2026-04-24):** App usa Supabase Edge Functions directamente via `functions.invoke()` — `BACKEND_BASE_URL` é irrelevante. Node backend em Render é apenas redundância, não chamado pela app.
- ~~**Ficheiro:** `lib/services/payment_service.dart`~~
- ~~**Problema:** `BACKEND_BASE_URL` defaultValue `http://localhost:3000` — sem URL de produção, pagamentos por cartão falham silenciosamente~~

### ~~BUG-002 — Realtime sync entre dispositivos~~ ✅ RESOLVIDO
- **Resolução (2026-04-24) — commit `e4b3596`:**
  - Stream do cliente reiniciado com filtro `user_id` após auth (antes arrancava sem filtro)
  - Canal `_clientOrdersChannel` (onPostgresChanges UPDATE) adicionado como fallback — mesmo padrão dos canais de driver
- ~~**Ficheiro:** `lib/stores/order_store.dart`~~
- ~~**Status:** "Current Focus" no CLAUDE.md — não resolvido~~

### ~~BUG-003 — Push Notifications desativadas~~ ✅ RESOLVIDO
- **Resolução (2026-04-24):** Firebase push activo. Edge Functions `notify-partner` e `notify-driver` commitadas e funcionais.
- ~~**Ficheiro:** `lib/main.dart` (Firebase.initializeApp() comentado)~~
- ~~**Problema:** drivers com app em background não recebem ofertas de pedidos~~

---

## 🟡 Médios

### BUG-004 — Admin por email allowlist
- **Ficheiro:** `lib/screens/admin/admin_dashboard_screen.dart:12`
- **Problema:** acesso admin controlado por email allowlist hardcoded — "intentionally temporary"
- **Ação:** substituir por RLS/role real no Supabase

### ~~BUG-005 — `assigned_driver_id` é TEXT (não UUID)~~ ✅ FECHADO (workaround intencional)
- **Decisão (2026-04-24):** Coluna permanece TEXT por compatibilidade com dados históricos. Triggers fazem cast `::UUID` explicitamente — comportamento intencional, não legacy. Documentado em CLAUDE.md. Mudar para UUID nativo implicaria risco de migration falhar em produção sem benefício funcional.

### ~~BUG-006 — Config.toml de Edge Functions não commitados~~ ✅ RESOLVIDO
- **Resolução (2026-04-24) — commit `56fb788`:** 4 Edge Functions completas commitadas (`charge-extra`, `create-mbway-payment-intent`, `notify-partner`, `refund`) + `stripe-webhook/index.ts` actualizado. CLAUDE.md corrigido (MBWay deixou de ser "simulated locally").
- ~~**Ficheiros:** `supabase/functions/create-payment-intent/config.toml`, `supabase/functions/stripe-webhook/config.toml`~~

### ~~BUG-007 — Auth/session persistence com edge cases~~ ✅ RESOLVIDO
- **Resolução (2026-04-24):** Análise completa de `auth_store.dart` confirma que todos os edge cases críticos estão tratados: driver nunca usa guest UID, `_initFromPrefs` re-autentica via Supabase em cold start, `session == null` é protecção intencional contra token hiccups. Edge cases remanescentes (password vazia, non-demo client lookup) têm probabilidade nula em produção.
- ~~**Ficheiro:** `lib/auth/auth_store.dart`~~
- ~~**Status:** "Current Focus" no CLAUDE.md~~

---

## 🟠 Features Ausentes (impactam lançamento)

### ~~BUG-008 — GDPR não implementado~~ ✅ RESOLVIDO
- **Resolução (2026-04-24):** Tudo implementado — `ConsentBanner` wraps app, `ConsentStore` persistente, checkbox nos 3 flows de registo, botão "Apagar conta" em `profile_screen.dart`, Edge Function `delete-account` commitada (`17c49ce`), versioning de consentimento v1.0.

### ~~BUG-009 — Cancelamento pelo cliente não implementado~~ ✅ RESOLVIDO
- **Resolução (2026-04-24):** `OrderStatus.cancelled` existe, botão "Cancelar pedido" implementado em `order_tracking_screen.dart`, Edge Function `client-cancel-order` commitada e funcional. Ver BUG-017.

### BUG-010 — Driver flow UI incompleto
- **Status:** "Current Focus" no CLAUDE.md
- Sem botão "Preciso de Ajuda"
- Sem validação de foto antes de aceitar sendPackage/carryGroceries

### BUG-011 — Avaliações sem persistência em Supabase
- `rating_model.dart` existe mas sem tabela `ratings` em Supabase
- Sem ecrã de avaliação pós-entrega
- Sem etiquetas (simpático/rápido/limpo/denúncia)

---

## Valores Alterados sem Registo Formal
- `_driverBasePay = 3.80` (era 4.0)
- `_shoppingDriverBonus = 0.80` (era 1.0)
- **Ficheiro:** `lib/services/pricing_service.dart`

---

## Novos Bugs Descobertos — Análise Nocturna 24 Abril 2026

> Cada um tem ficheiro próprio com detalhe completo.

| ID | Prioridade | Resumo | Estado | Commit/Nota |
|----|-----------|--------|--------|-------------|
| ~~BUG-012~~ | ~~🔴 Crítico~~ | ~~Credenciais Supabase/Stripe hardcoded no source code~~ | ✅ RESOLVIDO | Migradas para `.dart_defines` (gitignored) — 2026-04-24 |
| ~~BUG-013~~ | ~~🔴 Crítico~~ | ~~MBWay é um stub — não processa pagamentos reais~~ | ✅ RESOLVIDO | Edge Fn `create-mbway-payment-intent` LIVE via Stripe — 2026-04-24 |
| ~~BUG-014~~ | ~~🔴 Crítico~~ | ~~Stripe em modo de teste (pk_test_) — não funciona em produção~~ | ✅ RESOLVIDO | `pk_live_` em `.dart_defines` para release — 2026-04-24 |
| BUG-015 | 🟡 Médio | Sistema de buffer/reconciliação de pagamento não testado | ⏳ Aberto | [[BUG-015-reconciliacao-buffer]] |
| ~~BUG-016~~ | ~~🟡 Médio~~ | ~~Dual GPS streams no driver causam localização divergente~~ | ✅ RESOLVIDO | `_navigateToMap()` pausa stream idle — commit `1a1f976` — 2026-04-24 |
| ~~BUG-017~~ | ~~🟠 Alta~~ | ~~Cancelamento pelo cliente sem UI~~ | ✅ RESOLVIDO | Flutter UI + Edge Fn completas (commit `17c49ce`). Botão visível em todos os estados não-terminais com taxa variável. |
| BUG-018 | 🟠 Alta | Ratings não persistem no Supabase (modelo existe, serviço não) | ⏳ Aberto | [[BUG-018-ratings-sem-persistencia]] |
