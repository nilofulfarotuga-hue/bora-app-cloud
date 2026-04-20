---
skill: qa-engineer
mode: read-only (report) + auto-fix approved
date: 2026-04-18
scope: Fase 2 — 13 ecrãs (driver + partner)
files_analyzed:
  - lib/screens/driver_home_screen.dart (2392 linhas)
  - lib/screens/driver_login_screen.dart (360 linhas)
  - lib/screens/driver_map_screen.dart (2638 linhas)
  - lib/screens/driver_earnings_screen.dart (783 linhas)
  - lib/screens/driver_signup_screen.dart (647 linhas)
  - lib/screens/driver_pending_screen.dart (73 linhas)
  - lib/screens/driver_rejected_screen.dart (114 linhas)
  - lib/screens/partner_login_screen.dart (163 linhas)
  - lib/screens/partner_entry_screen.dart (46 linhas)
  - lib/screens/partner_dashboard_screen.dart (1018 linhas)
  - lib/screens/partner_products_screen.dart (252 linhas)
  - lib/screens/partner_reservations_screen.dart (215 linhas)
  - lib/screens/restaurant_dashboard_screen.dart (797 linhas)
---

# QA REPORT — Fase 2 (Driver + Partner)

## Resumo executivo

✅ **Nenhum bug crítico.** 3 APIs deprecated corrigidas, 5 AppBars standardizadas para identidade Bora. Zero `withOpacity`, zero `WillPopScope`, zero `RaisedButton/FlatButton`. `flutter analyze` restantes são apenas `info` de style lint (não-bloqueantes).

---

## 🔴 CRÍTICO

Nenhum.

---

## 🟡 ALTO

### ~~A1 — `setMapStyle` deprecated em google_maps_flutter 2.6~~ ✅ CORRIGIDO
- **Ficheiro:** [driver_map_screen.dart:695](lib/screens/driver_map_screen.dart#L695)
- **Antes:** `controller.setMapStyle(_mapStyle)` no `onMapCreated`
- **Depois:** `style: _mapStyle` como parâmetro directo de `GoogleMap()`

### ~~A2 — `BitmapDescriptor.fromBytes` deprecated~~ ✅ CORRIGIDO
- **Ficheiro:** [driver_map_screen.dart:138](lib/screens/driver_map_screen.dart#L138)
- **Antes:** `BitmapDescriptor.fromBytes(bytes)`
- **Depois:** `BitmapDescriptor.bytes(bytes)` (nova API Flutter 3.24+)

### ~~A3 — `DropdownButtonFormField(value:)` deprecated pós v3.33~~ ✅ CORRIGIDO
- **Ficheiro:** [driver_signup_screen.dart:409](lib/screens/driver_signup_screen.dart#L409)
- **Antes:** `value: _documentType`
- **Depois:** `initialValue: _documentType`

---

## 🟠 MÉDIO — AppBars inconsistentes ✅ 5/5 CORRIGIDAS

Padrão Bora = `backgroundColor: transparent + foregroundColor: white + headerGradient`.

| # | Ficheiro | Título | Estado |
|---|---|---|---|
| M1 | [driver_signup_screen.dart:264](lib/screens/driver_signup_screen.dart#L264) | Candidatura de Estafeta | ✅ corrigido |
| M2 | [driver_earnings_screen.dart:349](lib/screens/driver_earnings_screen.dart#L349) | Ganhos | ✅ corrigido |
| M3 | [partner_login_screen.dart:34](lib/screens/partner_login_screen.dart#L34) | Aceder como parceiro | ✅ corrigido (+ import AppTheme) |
| M4 | [partner_products_screen.dart:63](lib/screens/partner_products_screen.dart#L63) | Produtos de … | ✅ corrigido (+ import AppTheme) |
| M5 | [partner_reservations_screen.dart:55](lib/screens/partner_reservations_screen.dart#L55) | Reservas | ✅ corrigido (+ import AppTheme) |

**Benchmark:** Uber Partner / iFood Shop / Glovo Partner — todos mantêm header consistente em todos os sub-ecrãs do app.

---

## 📋 TODO (documentados, não corrigidos)

### T1 — Dead button intencional em partner_dashboard
- **Ficheiro:** [partner_dashboard_screen.dart:637](lib/screens/partner_dashboard_screen.dart#L637)
- **Análise:** `OutlinedButton.icon(onPressed: null, icon: timelapse_outlined, label: order.status.label)`
- **Veredicto:** **Não é bug.** É um indicador visual de estado (botão desactivado propositadamente para mostrar status intermédio quando `else` da condição `showCallDriver`). Padrão idêntico ao usado por iFood para status "Aguardando preparo".
- **Acção:** Nenhuma. Deixar como está. Sugestão estética futura: substituir por `Chip` com ícone para clarificar intenção.

### T2 — Lints `info` remanescentes (não bloqueantes)
6 hits em Fase 2, todos style/convention:
- `_kRequireDeliveryCode` underscore em var local (driver_home:1154, driver_map:1247)
- `BuildContext` across async gap (driver_home:1162)
- `prefer_const_declarations` + `prefer_const_constructors` (driver_home:1286, :1409)
- `curly_braces_in_flow_control_structures` (driver_map:392)

Todos pré-existentes, nenhum introduzido nesta Fase 2.

### T3 — `lib/utils/map_marker_helper.dart:126` usa `fromBytes` (fora de âmbito)
Mesmo API deprecated já corrigida em `driver_map_screen`. Fica para próxima fase (utils não eram âmbito desta Fase 2).

---

## ✅ Verificações OK (pós-fix)

| Critério | Resultado |
|---|---|
| `flutter analyze` nos 13 ecrãs | **0 erros, 0 warnings, 0 deprecated** (6 info-lint pré-existentes) |
| `withOpacity` deprecated | **0 ocorrências** em Fase 2 |
| `WillPopScope` | **0 ocorrências** |
| `RaisedButton / FlatButton / OutlineButton` | **0 ocorrências** |
| `onPressed: null` não-intencional | **0 ocorrências** (T1 é intencional) |
| AppBars padrão Bora | **13/13** ✓ |
| Navegação respeita `_RootNavigator` | **100%** — zero `pushReplacement` para root |
| Zonas protegidas BR §25.3 tocadas | **Nenhuma** (Stripe / pricing_service / driver_capacity_service / finalizePurchase intactos) |

---

## Diff resumo

| Ficheiro | Linhas +/- |
|---|---|
| driver_map_screen.dart | 2 linhas modificadas (1 API deprecated + setMapStyle→style) |
| driver_signup_screen.dart | 1 linha (value→initialValue) + 11 linhas AppBar |
| driver_earnings_screen.dart | 10 linhas AppBar |
| partner_login_screen.dart | 1 linha import + 10 linhas AppBar |
| partner_products_screen.dart | 1 linha import + 10 linhas AppBar |
| partner_reservations_screen.dart | 1 linha import + 10 linhas AppBar |

**Total:** 57 linhas modificadas em 6 ficheiros.
