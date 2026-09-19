# Sessão 7-UI-BUG004 — Implementation Report (2026-05-08)

## Ficheiros alterados

### Criados
- `lib/widgets/cancel_blocked_pickup_sheet.dart` (novo widget)
- `.claude/.ai/reports/2026-05-08_session_7_ui_bug004/00_overview.md`
- `.claude/.ai/reports/2026-05-08_session_7_ui_bug004/01_implementation.md`
- `.claude/.ai/reports/2026-05-08_session_7_ui_bug004/02_validation_manual.md`

### Modificados
- `lib/stores/order_store.dart` — refactor `driverCancelAcceptedOrder`
  (return type `Future<bool>` → `Future<Map<String,dynamic>>`).
- `lib/screens/driver_home_screen.dart` — handler
  `_handleCancelDelivery` lê `support_required`; novo método
  `_openSupportChatForBlockedCancel`; imports
  `cancel_blocked_pickup_sheet.dart` + `support_chat_screen.dart`.
- `lib/screens/support_chat_screen.dart` — parâmetro opcional
  `initialMessage`; pre-fill em `initState` via `TextEditingValue`
  com cursor no fim.
- `android/app/src/main/AndroidManifest.xml` — `<intent>` `tel`
  `DIAL` adicionado dentro do `<queries>` existente (não duplica bloco).
- `ios/Runner/Info.plist` — `LSApplicationQueriesSchemes` novo bloco
  com `tel`.
- `scripts/e2e/BUGS_FOUND.md` — BUG-004 → CLOSED + footer actualizado.
- `.obsidian-vault/sessoes/07e_b_bugs.md` — espelho actualizado.

## Decisões arquitecturais

### Tokens design system (A0.4)
Usados tokens nomeados — `AppTheme.primary` (#1B5E20 verde Bora) +
`AppTheme.secondary` (#E65100 laranja Bora). Centralizado em
[lib/config/app_theme.dart](../../../lib/config/app_theme.dart#L5).

### i18n (A0.5)
Sem `lib/l10n/`, sem `flutter_localizations` — projecto é PT-only por
agora. Strings hardcoded directamente em PT-PT no widget. TODO futuro:
extrair para arb files quando i18n for introduzido.

### Pre-fill chat (A0.2 → Cenário B)
`SupportChatScreen` extendido com parâmetro **opcional** `initialMessage`.
Init flow trivial (só adiciona greeting + nada de subscriptions ou
state machine), pre-fill via
`TextEditingValue` com `selection: TextSelection.collapsed(offset: pre.length)`
para cursor no fim — utilizador continua a escrever após o motivo.
Edge Fn `support-chatbot` v8 (PROTECTED) **não tocada**.

### Refactor obrigatório (Ajuste 1 do Danilo)
`driverCancelAcceptedOrder` original ignorava o response da RPC e
retornava sempre `true` excepto em catch. Refactor expõe o
`Map<String,dynamic>` completo para o caller, permitindo a UI ler
`support_required` directamente sem segunda chamada. Local state
update (`_orders.removeWhere`) só corre quando `result['ok']==true`.

### Permissions
- **Android**: `<queries>` JÁ EXISTIA (com `PROCESS_TEXT`). Append do
  `<intent>` `tel`/`DIAL` interno ao bloco existente — NÃO criou bloco
  novo (evita duplicação).
- **iOS**: `LSApplicationQueriesSchemes` NÃO existia. Adicionado bloco
  novo com `tel`. NB: `_callPhone()` em `driver_home_screen.dart:1490`
  já existe e funciona em produção via `launchUrl` directo, mas o
  `canLaunchUrl` requer o entry plist em iOS — bom higiene adicionar.

## Telefone hardcoded
`+351937501673` em `cancel_blocked_pickup_sheet.dart` como
`const String _supportPhone`. TODO marcado para mover para
configuração centralizada (env / remote config) em sessão futura.

## url_launcher (A0.3 → SKIP F2.4)
Já presente em `pubspec.yaml` (`^6.2.5`). Sem alteração à lockfile
necessária.

## Análise estática

`flutter analyze` baseline pré-sessão: 55 issues. Pós-refactor inicial
ficou 56 (`unnecessary_cast` em `order_store.dart:1151:39` —
`response as Map` redundante após `is Map` check). Removido cast.
Final: **55 issues**, baseline preservada.

## Não modificado (re-confirmação)

- `pricing_service.dart` ✅
- `dispatch-engine` ✅
- triggers `bora_tokens` ✅
- código Stripe (Edge Fn `stripe-webhook`) ✅
- `finalizePurchase` em `order_store.dart` ✅
- Edge Fns produção (`support-chatbot` v8 PROTECTED) ✅
- Cron jobs ✅
- Fixes BUG-005/007 ✅
- `admin_cancel_order` (RPC separada) ✅
- Sessão 6 ratings infra ✅
- Framework E2E 7E-A/7E-B ✅
- 21 skills active ✅
