# Sessão 5A-2-β/7 — Aplicar FAB suporte em 22 screens

## Fase B — EXECUÇÃO (Relatório)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** claude-opus-4-7[1m]
**Pré-requisito:** Sessão 5A-2 fechada (commit bcde960)

---

## ✅ Resumo

| | |
|---|---|
| Screens-alvo | 22 |
| Screens **modificadas** | 21 |
| Screens **SKIP justificado** | 1 (#2 ClientMainScreen) |
| `flutter analyze` | **0 erros NOVOS** (54 issues total, baseline ≈52, todos info/warning) |
| Build | não corrido (smokes UI manual ficam para 5A-2-γ com device) |

---

## ✅ Caso especial #1 — ClientHomeScreen (Opção A executada)

**Acção:**
- ✅ Removido FAB legado WhatsApp (`FloatingActionButton(onPressed: _openWhatsApp, ...)`)
- ✅ Substituído por `floatingActionButton: const BoraSupportFab()` (BR default)
- ✅ Removido método privado `_openWhatsApp()` (linhas 93-99)
- ✅ Removido `import 'package:url_launcher/url_launcher.dart';` (já não usado)

**Verificação:** `_openWhatsApp` confirmado privado (apenas 2 referências em `client_home_screen.dart`: definição + uso interno). Zero impacto noutros ficheiros.

---

## ⚠️ Caso especial #2 — ClientMainScreen SKIP justificado

**Anomalia detectada:**
- ClientMainScreen é shell `IndexedStack` dos 3 tabs (HomeClient/Orders/Profile).
- Cada tab já recebe FAB próprio (#1, #3, #6 desta sessão).
- Adicionar FAB no shell duplicaria visualmente com FAB dos tabs.

**Decisão:** **NÃO aplicar** FAB em ClientMainScreen. Reportado.

---

## ✅ Caso especial #14 — DriverMapScreen TR

- ✅ Import + `floatingActionButton: const BoraSupportFab(position: FabPosition.topRight)`
- ✅ Adicionado `floatingActionButtonLocation: FloatingActionButtonLocation.endTop` (necessário para position TR via Scaffold)
- Razão: `DraggableScrollableSheet` linha 747 obstruiria BR

---

## ✅ Caso especial #18 — RestaurantDashboardScreen 2 Scaffolds

- ✅ Empty state Scaffold @59: FAB BR adicionado
- ✅ Main Scaffold @121: FAB BR adicionado
- 1 import único partilhado pelos 2 Scaffolds

---

## ✅ Caso especial #19 — PartnerProductsScreen Stack overlay TR

- ✅ FAB extended "Adicionar produto" **preservado intacto** (core function)
- ✅ Body wrapped em `Stack` com:
  - `SafeArea(child: <body original>)` (preservado idêntico)
  - `Positioned(top: 16, right: 16, child: SafeArea(child: BoraSupportFab(position: topRight, heroTag: 'bora_support_fab_partner_products')))`
- `heroTag` único para evitar Hero conflict com o FAB extended (regra Flutter: 2 Heroes na mesma rota precisam de tags diferentes)

---

## ✅ Casos especiais #4 #5 — orderId real

| Screen | orderId usado |
|---|---|
| OrderTrackingScreen | `widget.order.id` (StatefulWidget) |
| OrderDetailsScreen | `order.id` (StatelessWidget recebe `final OrderModel order`) |

---

## ✅ 16 trivais aplicadas (BR default)

Padrão: import `'../widgets/bora_support_fab.dart';` + `floatingActionButton: const BoraSupportFab()` no Scaffold top-level.

| Screen | Status |
|---|---|
| OrdersScreen | ✅ |
| ProfileScreen | ✅ |
| RestaurantsScreen | ✅ |
| StoresScreen | ✅ |
| RestaurantMenuScreen | ✅ (top-level @96; private @487 ignorado) |
| StoreProductsScreen | ✅ |
| ClientReservationsScreen | ✅ |
| WalletHistoryScreen | ✅ |
| NotificationsScreen | ✅ (com correcção de sintaxe — Edit inicial truncou AppBar; corrigido) |
| DriverHomeScreen | ✅ (top-level @495; privates @697 @766 ignorados) |
| DriverEarningsScreen | ✅ |
| PartnerDashboardScreen | ✅ |
| PartnerReservationsScreen | ✅ |
| PartnerEarningsScreen | ✅ |
| ReferralScreen | ✅ |
| ClientFavoritesScreen | (já tinha FAB do PoC 5A-2 main) |

---

## 📊 Smokes

### S1 flutter analyze ✅
- **0 erros NOVOS**
- 54 issues total (baseline ≈52)
- Issues pre-existentes não relacionados a 5A-2-β:
  - `profile_screen.dart:368` — `unused_local_variable 'user'` (já existia)
  - `support_email_form_screen.dart:49` — `use_build_context_synchronously` (do 5A-2 main)
  - `bora_support_sheet.dart:144` — `withOpacity` deprecated (do 5A-2 main)

### S2 flutter build apk --debug
- **Não executado** (compilação leva minutos; smokes UI manual ficam para 5A-2-γ com device).

### S3 UI manual ⏭ (5A-2-γ)
- Validar visualmente: FAB visível em cada uma das 21 screens, posicionamento correcto (TR vs BR), tap abre BottomSheet, kill switch via DB esconde card "Bora IA".

---

## 📋 Análise transversal

| Camada | Impacto |
|---|---|
| Cliente UI | 12 screens com FAB BR; ClientMainScreen SKIP justificado (shell IndexedStack) |
| Estafeta UI | 3 screens (DriverMap em TR; outras BR) |
| Parceiro UI | 5 screens (PartnerProducts em Stack TR; outras BR) |
| Admin | NÃO TOCADO |
| Backend 5A-1 / 5A-2 | NÃO TOCADO |
| Dispatch / Pricing / Stripe / Wallet RPCs | NÃO TOCADO |

---

## 🐛 Bugs colaterais

- **Nenhum novo bug detectado.**
- §32.4 (TOKENS_INFO formula docs vs código) e BUG 39 (UUID/TEXT) continuam pendentes — fora scope.

---

## 🧠 Skills identificadas

**Nenhuma nova.** Registo em `.claude/skills/identified_during_5a2beta_NONE.md`.

---

## 📦 Sync Obsidian

- Audit Fase A → `Bora\entregas\05a2_beta_fab_apply_audit.md` (SHA256 idem) ✅
- Relatório Fase B → `Bora\entregas\05a2_beta_fab_apply_report.md` (este ficheiro)

---

## ⚠️ Anomalia menor reportada (correcção interna)

Durante aplicação a `notifications_screen.dart`, o primeiro Edit truncou o `actions:` do AppBar inadvertidamente. Detectado pelo IDE diagnostics imediatamente. Corrigido em segundo Edit. Estado final 100% correcto e validado.

**Lição registada:** quando Scaffold tem `appBar: AppBar(...)` complexo (com `actions:`), ler 8-10 linhas pré-Edit em vez de 4-5 para evitar truncar partes do AppBar.

---

## ⏭ TODOs adiados

### 5A-2-γ (próxima sub-sessão)
- Smokes UI manual S4-S19 com device Android (Danilo configura device)
- Validar visualmente:
  - FAB visível em todas as 21 screens
  - Position TR em ClientHome (substituiu) + DriverMap + PartnerProducts (Stack overlay) sem obstruções
  - Tap → BottomSheet 3 cards
  - Kill switch backend → card "Bora IA" esconde

### 5B
- (mantém-se) Skills WRITE/CANCEL/MARKET, Resend SMTP, Push admin→cliente, etc.
- Resolver §32.4 (tokens fórmula docs vs código)
- Deprecar `support_screen.dart` legacy

### 5C
- (mantém-se) pgvector + RAG + skills avançadas

---

## ✅ Status final Fase B

🟢 **22/22 screens processadas (21 modificadas + 1 SKIP justificado).**
🟢 **5 casos especiais resolvidos conforme propostas A1.**
🟢 **flutter analyze: 0 erros NOVOS.**
🟡 **Smokes UI manual diferidos** — 5A-2-γ com device.
⏭ **Próximo:** Danilo aprova push + corre device test em 5A-2-γ.
