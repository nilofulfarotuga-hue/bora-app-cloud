---
skill: qa-engineer
mode: read-only
date: 2026-04-18
scope: Fase 1 — 8 ecrãs modificados (cliente)
files_analyzed:
  - lib/screens/client_home_screen.dart (486 linhas)
  - lib/screens/client_main_screen.dart (75 linhas)
  - lib/screens/restaurant_menu_screen.dart (832 linhas)
  - lib/screens/cart_screen.dart (364 linhas)
  - lib/screens/restaurants_screen.dart (349 linhas)
  - lib/screens/orders_screen.dart (305 linhas)
  - lib/screens/order_tracking_screen.dart (826 linhas)
  - lib/screens/profile_screen.dart (725 linhas)
---

# QA REPORT — Fase 1 (Cliente)

## Resumo executivo

✅ **Nenhum bug crítico.** `flutter analyze` limpo nestes 8 ecrãs. Zero APIs deprecated (`withOpacity`, `WillPopScope`, `RaisedButton`, `FlatButton`), zero `onPressed: null`, zero TODO/FIXME. Identidade visual consistente: todos os AppBars usam `Colors.transparent + foregroundColor: white + headerGradient` (contraste excelente).

---

## 🔴 CRÍTICO

Nenhum.

---

## 🟡 ALTO

Nenhum.

---

## 🟠 MÉDIO

### M1 — AppBar inconsistente no address picker
- **Ficheiro:** [client_home_screen.dart:435](lib/screens/client_home_screen.dart#L435)
- **Problema:** `_AddressPickerScreen` usa `AppBar(title: Text('Endereço de entrega'))` com tema default, enquanto todos os outros 14 ecrãs usam `backgroundColor: transparent + foregroundColor: white + headerGradient`.
- **Impacto:** Quebra identidade visual Bora no meio de um fluxo crítico (escolha de endereço antes de pedir).
- **Benchmark:** Uber Eats / iFood / Glovo mantêm header consistente em 100% dos sub-ecrãs.
- **Fix:** Substituir por `BoraAppBar(title: 'Endereço de entrega')` OU replicar padrão transparent+gradient.

### M2 — Sem pull-to-refresh em orders_screen
- **Ficheiro:** [orders_screen.dart:92-114](lib/screens/orders_screen.dart#L92-L114)
- **Problema:** `ListView.separated` sem `RefreshIndicator`. O `OrderStore` já tem `refresh()` público.
- **Impacto:** UX — user não tem forma manual de sincronizar pedidos se o realtime falhar (cenário comum em 3G). Força saída/entrada no tab.
- **Benchmark:** iFood + Glovo + Uber Eats todos têm pull-to-refresh na lista de pedidos.
- **Fix:** Envolver `ListView.separated` em `RefreshIndicator(onRefresh: () => orderStore.refresh())`.

---

## 📋 TODO (BR pendentes)

### T1 — Gorjeta no checkout (BR §4.5)
- **Ficheiro:** [cart_screen.dart](lib/screens/cart_screen.dart) — widget ausente
- **BR §4.5:** "Cliente pode dar gorjeta na altura de pagar **ou** depois da entrega".
- **Estado actual:** Só existe em `rating_screen.dart` (pós-entrega). Falta no checkout.
- **Sugestão BR:** Chips 1€ · 2€ · 3€ · 5€ + campo livre. Divisão 80% estafeta / 20% Bora.
- **Já listado em:** BR §26.2 (A desenvolver).

### T2 — Back button fullscreen map em order_tracking
- **Ficheiro:** [order_tracking_screen.dart:239](lib/screens/order_tracking_screen.dart#L239)
- **Observação:** `Navigator.maybePop(context)` — correcto quando aberto via `_ClientMainScreen` (push). Mas se futuramente este ecrã for entrada via deep-link/notificação, `maybePop` falha silenciosamente. Não é bug actual — é nota para quando BR §16.3 (push notifications) entrar.

---

## ✅ Verificações OK

| Critério | Resultado |
|---|---|
| `flutter analyze` nos 8 ecrãs | **0 erros, 0 warnings, 0 deprecated** |
| `withOpacity` deprecated | **0 ocorrências** (migração completa para `withValues`) |
| `WillPopScope` | **0 ocorrências** |
| `RaisedButton / FlatButton` | **0 ocorrências** |
| `onPressed: null` (dead buttons) | **0 ocorrências** — todos os disabled são condicionais (`empty ? null : callback`) |
| AppBars com contraste | **9/10** — só falha M1 |
| Navegação respeita `_RootNavigator` | **100%** — nenhum `pushReplacement` para root screens |
| Fluxo BR §1.3 (FSM delivery) | **OK** — transições via `OrderStore._advanceStatus` (DB-first) |
| Zonas protegidas BR §25.3 | **Não tocadas** |

---

## Plano de correcção (aguarda aprovação)

| # | Tarefa | Severidade | Ficheiro | Risco |
|---|---|---|---|---|
| 1 | Standardizar AppBar do `_AddressPickerScreen` para padrão Bora | 🟠 MÉDIO | client_home_screen.dart:435 | Baixo — só visual |
| 2 | Adicionar `RefreshIndicator` em `OrdersScreen` | 🟠 MÉDIO | orders_screen.dart:92 | Baixo — `orderStore.refresh()` já existe |
| 3 | Implementar widget de gorjeta em checkout (BR §4.5) | 📋 TODO | cart_screen.dart | Médio — toca em pricing |

**Modo PROTECÇÃO TOTAL activo:** aguardo aprovação individual por tarefa antes de delegar a `executor`.
