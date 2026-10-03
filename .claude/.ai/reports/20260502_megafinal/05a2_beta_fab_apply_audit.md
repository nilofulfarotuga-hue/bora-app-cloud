# Sessão 5A-2-β/7 — Aplicar FAB suporte em 22 screens

## Fase A — AUDIT (read-only)

**Data:** 2026-05-04
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** claude-opus-4-7[1m]
**Pré-requisito:** Sessão 5A-2 fechada (commit bcde960 push)
**ClientFavoritesScreen** já tem FAB do PoC 5A-2 main → **não tocada**.

---

## A0 — Estado actual das 22 screens

**Audit via grep:** `floatingActionButton:` count + `bora_support_fab` import + linhas de `return Scaffold(`.

| # | Screen | FAB existente | import bora_support_fab | Scaffold top-level |
|---|--------|--------------|-------------------------|--------------------|
| 1 | client_home_screen | **1** | 0 | linha 134 |
| 2 | client_main_screen | 0 | 0 | linha 67 |
| 3 | orders_screen | 0 | 0 | linha 77 |
| 4 | order_tracking_screen | 0 | 0 | linha 235 |
| 5 | order_details_screen | 0 | 0 | linha 37 |
| 6 | profile_screen | 0 | 0 | linha 370 |
| 7 | restaurants_screen | 0 | 0 | linha 39 |
| 8 | stores_screen | 0 | 0 | linha 107 |
| 9 | restaurant_menu_screen | 0 | 0 | linha 96 (private @487 ignorado) |
| 10 | store_products_screen | 0 | 0 | linha 198 |
| 11 | client_reservations_screen | 0 | 0 | linha 127 |
| 12 | wallet_history_screen | 0 | 0 | linha 44 |
| 13 | notifications_screen | 0 | 0 | linha 64 |
| 14 | driver_map_screen | 0 | 0 | linha 687 |
| 15 | driver_home_screen | 0 | 0 | linha 495 (privates @697 @766 ignorados) |
| 16 | driver_earnings_screen | 0 | 0 | linha 313 |
| 17 | partner_dashboard_screen | 0 | 0 | linha 165 |
| 18 | restaurant_dashboard_screen | 0 | 0 | **2 Scaffolds top-level @58 (empty) + @119 (main)** |
| 19 | partner_products_screen | **1** | 0 | linha 67 |
| 20 | partner_reservations_screen | 0 | 0 | linha 81 |
| 21 | partner_earnings_screen | 0 | 0 | linha 85 |
| 22 | referral_screen | 0 | 0 | linha 87 |

**Resumo:**
- ✅ Todas 22 screens existem
- ✅ Nenhuma tem `bora_support_fab` importado (0/22 — esperado)
- ⚠️ **2 screens já têm FAB próprio** (#1, #19) — casos especiais
- ⚠️ **#18 restaurant_dashboard_screen tem 2 Scaffolds top-level** — empty state + main (precisa FAB em AMBOS)
- ⚠️ **#14 driver_map_screen** tem `DraggableScrollableSheet` (linha 747)

---

## A1 — Casos especiais (5 com proposta explícita)

### #1 ClientHomeScreen — FAB existente

**Estado actual (linhas 136-141):**
```dart
floatingActionButton: FloatingActionButton(
  onPressed: _openWhatsApp,
  backgroundColor: const Color(0xFF25D366),
  tooltip: 'Suporte WhatsApp',
  child: const Icon(Icons.chat_rounded, color: Colors.white, size: 26),
),
```

**Análise:** o FAB existente é especificamente um botão WhatsApp (legado pré-5A). O nosso `BoraSupportFab` **substitui funcionalidade** — abre BottomSheet com 3 opções (Bora IA + WhatsApp + Email).

**Proposta:** **substituir** o FAB existente pelo `BoraSupportFab` em **BR** (default).
- Ganho: agrupa 3 canais num só sheet (UX consistente)
- Método `_openWhatsApp` privado fica obsoleto → recomendo **deixar para limpeza futura** (não remover nesta sessão; risco zero de quebrar — só fica unused).
- Position TR proposta no prompt fica desnecessária se substituirmos.

**Decisão Danilo necessária:**
- ✅ **Opção A (recomendada):** substituir FAB pelo `BoraSupportFab(position: BR)`. UX unificada.
- Opção B: manter FAB WhatsApp legado + adicionar `BoraSupportFab(position: TR)` via Stack overlay.

### #19 PartnerProductsScreen — FAB existente

**Estado actual (linha 81):**
```dart
floatingActionButton: FloatingActionButton.extended(
  onPressed: () => _openAddProduct(),
  icon: const Icon(Icons.add),
  label: const Text('Adicionar produto'),
),
```

**Análise:** FAB extended "Adicionar produto" é função core do parceiro. **NÃO substituir.**

**Proposta:** **Stack overlay** com `BoraSupportFab(position: TR)` — preservando FAB add product no BR. Implementação:
```dart
body: Stack(
  children: [
    Positioned.fill(child: <body original>),
    const Positioned(
      top: 16,
      right: 16,
      child: SafeArea(
        child: BoraSupportFab(position: FabPosition.topRight),
      ),
    ),
  ],
),
```
**Não tocar `floatingActionButton:` original.**

### #4 OrderTrackingScreen — orderId real

**Estado:** classe `StatefulWidget` que recebe `widget.order` (OrderModel). Não há `widget.orderId` directo — usa `widget.order.id`.

**Proposta:** `floatingActionButton: BoraSupportFab(orderId: widget.order.id)`.

### #5 OrderDetailsScreen — orderId real

**Estado:** `StatelessWidget` recebe `final OrderModel order` (campo directo).

**Proposta:** `floatingActionButton: BoraSupportFab(orderId: order.id)`.

### #14 DriverMapScreen — DraggableScrollableSheet

**Estado:** `Scaffold(body: Stack(...))` com `GoogleMap` full-screen + `DraggableScrollableSheet` (linha 747) na parte inferior.

**Análise:** colocar FAB em BR sobreporia o sheet draggable quando expandido. Risco UX.

**Proposta:** mudar para **TR** (top-right) — fora do raio do sheet. Posição não conflita com botão back já presente em `Positioned(top: topPadding+8, ...)` (back fica em TL via Positioned, FAB em TR).

**⚠️ Diferente do prompt original (que dizia BR para #14).** Documentar e pedir confirmação.

---

## A2 — Análise impacto + rollback

### Edits previstos (Fase B)
- **22 imports** (1 por screen): `import '../widgets/bora_support_fab.dart';`
- **23 inserções `floatingActionButton:`** ou Stack overlays:
  - 19 screens: `floatingActionButton: const BoraSupportFab()` em BR
  - 1 screen (#14): `floatingActionButton: const BoraSupportFab(position: FabPosition.topRight)` em TR (decisão alterada)
  - 1 screen (#1): substituir FAB existente (Opção A) → `floatingActionButton: const BoraSupportFab()` em BR
  - 1 screen (#19): Stack overlay TR (preserva FAB próprio)
  - 1 screen (#18): 2 inserções (empty + main Scaffold)
- 2 screens (#4, #5) com `orderId` no constructor

### Riscos: **zero crítico**
- Aditivo puro (excepto #1 substituição, com justificação clara)
- `flutter analyze` deve manter 0 erros NOVOS (baseline 52)
- Nenhum impacto em backend / dispatch / pricing / Stripe / wallet

### Plano rollback
1. **Kill switch backend (já existe):**
   ```sql
   UPDATE support_settings SET support_agent_enabled=false WHERE id=1;
   ```
   Provider 3-state esconde card "Bora IA"; FAB ainda renderiza com WhatsApp/Email.
2. **Rollback total UI:** `git revert <commit-5a2-beta>` — não-destrutivo.
3. **#1 ClientHomeScreen rollback:** se Danilo prefere Opção B depois, basta editar para Stack overlay.

---

## A3 — Decisões aguardadas Danilo + Claude.ai

| # | Item | Decisão necessária |
|---|------|--------------------|
| #1 | ClientHomeScreen | **Opção A** (substituir, recomendada) ou **B** (manter + Stack TR)? |
| #14 | DriverMapScreen | OK mudar de **BR → TR** por causa do `DraggableScrollableSheet`? |
| #18 | restaurant_dashboard_screen | OK aplicar FAB nos **2 Scaffolds top-level** (empty + main)? |
| #19 | PartnerProductsScreen | OK Stack overlay TR preservando FAB "add product"? |
| #4 #5 | order_tracking + order_details | OK usar `widget.order.id` / `order.id` para `BoraSupportFab(orderId:...)`? |

**Outras 17 screens:** trivial — `floatingActionButton: const BoraSupportFab()` em BR + 1 import. Sem decisões pendentes.

---

## 🧠 Skills identificadas

**Nenhuma nova.** Registo em `.claude/skills/identified_during_5a2beta_NONE.md`.

---

## 📦 Sync Obsidian

Audit Fase A → `Bora\entregas\05a2_beta_fab_apply_audit.md` (SHA256 idem após cópia).

---

⛔ **STOP — Aguardar luz verde Danilo + Claude.ai com respostas para os 5 itens decisão acima antes de iniciar Fase B.**
