# Sessão 5A-2/7 — Agente IA Suporte: Frontend + Skills Seed

## Fase B — EXECUÇÃO FRONTEND (Relatório)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** claude-opus-4-7[1m]
**Modo:** PROTECÇÃO TOTAL — ambas fases aprovadas explicitamente
**Pré-requisito:** Sessão 5A-1 fechada (commit 5269dde push em prod)

---

## ✅ Migrations aplicadas (4)

| # | Migration | Estado |
|---|-----------|--------|
| B11.0 | `20260504080000_5a2_fix_agent_order_status_camelcase.sql` (BLOQUEADOR — fix bug 5A-1) | ✅ |
| B11.5 | `20260504080100_5a2_realtime_publish_chatbot_messages.sql` | ✅ |
| B16 | `20260504080200_5a2_admin_resolve_ticket.sql` | ✅ |
| B17 | `20260504080300_5a2_seed_skills.sql` (9 skills, ON CONFLICT idempotente) | ✅ |

---

## ✅ Ficheiros Flutter criados (7)

| # | Ficheiro | Estado |
|---|----------|--------|
| B11 | `lib/providers/support_settings_provider.dart` (3-state anti-flicker) | ✅ |
| B11 | `lib/widgets/bora_scaffold.dart` (wrapper minimal) | ✅ |
| B12 | `lib/widgets/bora_support_fab.dart` (FabPosition enum) | ✅ |
| B12 | `lib/widgets/bora_support_sheet.dart` (3 cards condicionais) | ✅ |
| B13 | `lib/screens/support_chat_screen.dart` (Gemini + Realtime) | ✅ |
| B14 | `lib/screens/support_email_form_screen.dart` | ✅ |
| B16 | `lib/screens/admin/admin_support_tickets_screen.dart` (lista + resolve) | ✅ |

## ✅ Ficheiros Flutter editados (2)

| # | Ficheiro | Mudança |
|---|----------|---------|
| B11 | `lib/main.dart` | import + Provider + `WidgetsBindingObserver` para refresh on resume |
| B15 | `lib/screens/client_favorites_screen.dart` | import + `floatingActionButton: const BoraSupportFab()` (PoC) |

---

## ⚠️ B15 — Split parcial reportado (5A-2-β)

Conforme acordado em **A8 audit** ("se contexto >85% durante B14→B15, parar e propor split β"), apliquei FAB em **1 screen prova-de-conceito** (`ClientFavoritesScreen`). As **22 screens restantes** ficam reportadas como **TODO 5A-2-β**:

### Screens cliente (~12) com posição recomendada

| Screen | Position |
|---|---|
| ClientHomeScreen | TR (já tem FAB próprio) |
| ClientMainScreen | BR |
| OrdersScreen | BR |
| OrderTrackingScreen | BR |
| OrderDetailsScreen | BR |
| ProfileScreen | BR |
| RestaurantsScreen | BR |
| StoresScreen | BR |
| RestaurantMenuScreen | BR |
| StoreProductsScreen | BR |
| ClientReservationsScreen | BR |
| WalletHistoryScreen | BR |
| NotificationsScreen | BR |
| ReferralScreen | BR |

### Screens estafeta (~3)

| Screen | Position |
|---|---|
| DriverMapScreen | BR (com SafeArea+padding 24dp por causa do bottomSheet) |
| DriverHomeScreen | BR |
| DriverEarningsScreen | BR |

### Screens parceiro (~5)

| Screen | Position |
|---|---|
| PartnerDashboardScreen | BR |
| RestaurantDashboardScreen | BR |
| PartnerProductsScreen | TR (já tem FAB próprio add product) |
| PartnerReservationsScreen | BR |
| PartnerEarningsScreen | BR |

**Padrão aplicado em β:** import `bora_support_fab.dart` + `floatingActionButton: const BoraSupportFab(orderId: <ctx>, position: <conforme tabela>)` no `Scaffold(...)`. Nenhuma alteração estrutural.

---

## ✅ Ajustes aplicados (3 — pré-aprovados Claude.ai)

1. **B-FIX-1 (BLOQUEADOR):** RPC `agent_get_order_status` mapeava estados snake_case inexistentes → corrigido para camelCase real (`created/preparing/callingDriver/driverAccepted/pickedUp/onTheWay/delivered/cancelled/rejected`). `can_be_cancelled` agora reflecte flow real.
2. **B-FIX-2 (TOKENS_INFO):** playbook usa fórmula REAL do trigger `fn_award_tokens_on_delivery` — `GREATEST(1, ROUND(price × 3))` + expira 60 dias.
3. **B-FIX-3 (business_rules.md §32.4):** discrepância docs ("3% do valor") vs código (`ROUND(price × 3)`) reportada para resolver em sessão futura — não fixar agora.

---

## 📊 Smokes

### DB-side ✅

| Smoke | Resultado |
|-------|-----------|
| S1 — 9 skills active=true | ✅ 9/9 |
| S1b — total skills | ✅ 9 |
| S2 — `admin_resolve_ticket` exists | ✅ |
| S2b — non-admin → `NOT_ADMIN` | ✅ enforced |
| S3 — idempotência B17 (`ON CONFLICT DO UPDATE`) | ✅ migration usa pattern |
| S30 — RPC mapeia `callingDriver` → "À procura de estafeta" | ✅ |
| S31 — `can_be_cancelled` IN (`created`, `preparing`, `callingDriver`) | ✅ |
| S_realtime — `support_chatbot_messages` em `supabase_realtime` pub | ✅ |
| S_modes — 2 distinct modes (`read_only`, `escalate`) | ✅ |

### Regressão Sessões 1-4 + 5A-1 ✅

| Smoke | Resultado |
|-------|-----------|
| S20 coords NULL | 0 ✅ |
| S21 cap 5 sacos | ok ✅ |
| S24 settled_via | col existe ✅ |
| S25 dual_write trigger | enabled ✅ |
| S26 messages isolated | namespace separado ✅ |
| S29 5A-1 6 RPCs intactos | 6/6 ✅ |

### Diferidos para 5A-2-β / device manual

| Smoke | Razão |
|-------|-------|
| S4-S19 — UI manual (FAB visível, BottomSheet, ChatScreen, etc) | requer device emulador + JWT real |
| S22-S23 — wallet flows com `create_order` | requer pedido end-to-end |
| S27-S28 — BUG 35/38 UI Flutter | UI não tocada além do PoC |

---

## 📋 Análise transversal

| Camada | Impacto |
|--------|---------|
| Cliente (UI) | Provider + FAB (1 screen PoC). 13 screens em β |
| Estafeta (UI) | 3 screens em β |
| Parceiro (UI) | 5 screens em β |
| Admin | UI lista tickets + resolve + filtros (status/channel) ✅ |
| DB | 4 migrations aditivas; B11.0 corrige bug 5A-1 |
| Backend 5A-1 | NÃO TOCADO (excepto correcção bug `agent_get_order_status`) |
| Dispatch / Pricing / Stripe / Wallet RPCs / Reservation | NÃO TOCADO |

---

## 🛡️ Painel admin (5A-2 entregue)

- ✅ `AdminSupportTicketsScreen` lista com filtros status/channel
- ✅ Detalhe read-only com user/role/channel/order_id/session_id/admin_notes
- ✅ Acção "Marcar resolvido" → modal nota → RPC `admin_resolve_ticket(id, notas)` com audit timestamped
- ⏭ CRUD completo (responder cliente, atribuir, métricas, custo Gemini) → 5B

---

## 🐛 Bugs colaterais

- **BUG 39** §32.1 — UUID/TEXT mismatch (Sessão 7 dedicada)
- **§32.4 NOVO** — Tokens cliente discrepância docs (3%) vs código (`ROUND(price×3)`). 100x diferença. Confirmar com Danilo.
- **§32.5 NOVO** — Bug crítico 5A-1 corrigido em 5A-2 B-FIX-1 (estados camelCase).

---

## 🧠 Skills identificadas

**Nenhuma nova além das 9 aprovadas.** Registo em `.claude/skills/identified_during_5a2_NONE.md`.

---

## 📦 Sync Obsidian

- Audit Fase A → `Bora\entregas\05a2_agente_frontend_audit.md` (SHA256 idem) ✅
- Relatório Fase B → `Bora\entregas\05a2_agente_frontend_report.md` (este ficheiro)
- business_rules.md §31.9-§31.11 + §32.4-§32.5 → fonte única `.claude/.ai/business_rules.md`

---

## 📋 Lista [VERIFICAR] consolidada (Danilo preenche pós-sessão)

Skills com valores ambíguos (preencher em sessão futura):

| Skill | Item |
|---|---|
| ORDER_STATUS | ETA real (5C com `driver_locations`) |
| WALLET_INFO | "wallet promocional 80/20" não existe — confirmar (5B+) |
| WALLET_BLOCKED_HELP | prazo limite legal antes de cobrança forçada |
| TOKENS_INFO | conversão "100 tokens = €0,50" — confirmar se está em código activo |
| REFUND_STATUS | refund amount real (placeholder hoje) |
| GENERAL_FAQ | horário operacional Bora |
| GENERAL_FAQ | taxa entrega base (descreve, não calcula) |
| APP_TROUBLESHOOTING | versão mínima Android/iOS suportada |

---

## ⏭ TODOs adiados

### 5A-2-β (sub-sessão imediata)
- **Aplicar FAB nas 22 screens restantes** (cliente 13, estafeta 3, parceiro 5, +1 NotificationsScreen +1 ReferralScreen). Padrão: import + `floatingActionButton: const BoraSupportFab()`.
- Smokes UI manual S4-S19 com device/emulador real
- Validar visualmente positions TR em ClientHomeScreen + PartnerProductsScreen

### 5B
- Skills WRITE: UPDATE_DELIVERY_INSTRUCTIONS, UPDATE_DELIVERY_ADDRESS, ACCOUNT_UPDATE, PASSWORD_RESET, OTP_RESEND, FEEDBACK_SUGGESTION
- Skills CANCEL shadow: CANCEL_PRE_PURCHASE, CANCEL_DURING_PURCHASE, RESERVATION_CANCEL, PARTNER_REJECTED_ORDER
- Skills MARKET: MARKET_ITEM_UNAVAILABLE, MARKET_ITEM_ADDED, MARKET_PRICE_DIFFERENCE
- Shadow approval workflow admin (4 sem → auto)
- Resend/SMTP outbound email (channel='email' actualmente DB-only)
- Push cliente quando admin responde
- Admin support_skills CRUD (Danilo edita sem redeploy)
- Admin support_settings editor (kill switch UI, caps, model)
- Admin métricas dashboard (tickets, tempo médio, custo Gemini)
- `support_channel_taps` analytics tabela
- Refund detail real (`refunds` dedicada ou logs Stripe)
- Resolver §32.4 (tokens fórmula docs vs código)
- Deprecar `support_screen.dart` legacy
- Refactor progressivo scaffolds → BoraScaffold

### 5C
- pgvector + RAG embeddings
- Skills avançadas: MISSING_ITEM, WRONG_ITEM, DAMAGED_ITEM, CASH_CHANGE_ISSUE, TOKENS_NOT_CREDITED, PAYMENT_ISSUE_DIAGNOSE
- Learning loop

---

## ⚠️ Avisos prod

- **B11.0 fix RPC** já aplicado em prod via MCP — agente IA agora devolve textos PT corretos.
- **Realtime publication** activa — clientes em devices diferentes recebem mensagens em tempo real.
- **Kill switch operacional** (já existia 5A-1):
  ```sql
  UPDATE support_settings SET support_agent_enabled=false WHERE id=1;
  ```
  + Provider 3-state detecta no próximo `AppLifecycleState.resumed`.
- **Custo Gemini Flash** — monitorizar em 5B com métricas admin.

---

## ✅ Status final Fase B

🟢 **B11.0 + B11.5 + B11 + B12 + B13 + B14 + B15(PoC) + B16 + B17 todos completos.**
🟡 **B15 split parcial declarado** — 22 screens em β (lista + posições documentadas).
🟢 **Smokes DB-side todos passam.** UI manual diferido para β.
⏭ **Próxima sub-sessão:** 5A-2-β (aplicar FAB nas 22 screens restantes + smokes UI manual).
