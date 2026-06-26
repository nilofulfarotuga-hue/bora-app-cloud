# Fix 3 bugs Flutter — sendPackage / carryGroceries / Favores estafeta
> 2026-06-26 · MODO PROTEÇÃO TOTAL · Opus

## Problema 3 — Estafeta não vê o LOCAL do Favor (errand) — ✅ CORRIGIDO

**Causa-raiz** (`lib/models/order_model.dart:411-417,468`):
`OrderModel.fromSupabase` derivava `pickupLocation` **apenas** de `pickup_lat/pickup_lng`
e `pickupAddress` de `pickup_address`. Para pedidos `errand`, o `create_order` grava o
local da tarefa em `errand_location_lat/lng` + `errand_location` — **nunca** em `pickup_*`.
Resultado: `pickupLocation == null` → sem pino de recolha no mapa, sem cartão "Recolha:",
sem alvo de navegação. O estafeta aceitava mas não via para onde ir.

**Fix** (cirúrgico, só leitura/desserialização — zero backend, zero RLS):
- `pickupLocation ??= errand_location_lat/lng` quando `serviceType == errand`.
- `pickupAddress ??= errand_location` quando `serviceType == errand`.

**Cascata automática** (todos leem pickup — paridade com storeShopping):
- `route_optimizer.dart:66` cria pickup stop → **pino laranja no mapa** ✓
- `driver_home_screen.dart:1317` `pickupTarget = pickupLocation ?? destination` → **botão navegação** ✓
- `driver_home_screen.dart:1443` "Recolha: {pickupAddress}" → mostra **"Calzedonia"** ✓
- `driver_map_screen.dart:1845` `_SingleOrderAddresses` linha de recolha ✓
- `ErrandExecutionSheet` (botão "Tratar do favor", `driver_home_screen.dart:1605`) já mostrava
  **tarefa (errandDescription)** + **paragem em casa (errandHomeStop)** + cash stop ✓

`flutter analyze lib/models/order_model.dart` → **No issues found**.

## Problema 1 (sendPackage) e Problema 2 (carryGroceries) — tela branca ao reentrar

**Investigação exaustiva (read-only)** de todo o caminho partilhado:
- `send_package_form_screen.dart`, `carry_groceries_form_screen.dart` (+ telas intermédias 28-linha)
- `address_autocomplete_field.dart`, `business_autocomplete_field.dart`
- `quote_price_footer.dart`, `mandatory_photo_picker.dart`
- `location_service.dart`, `place_autocomplete_service(_io).dart`

**Resultado: código limpo. `flutter analyze` → exit 0, zero erros.**
- Serviço de autocomplete é instância nova por uso (sem singleton/cliente partilhado).
- `LocationService.getCurrentLocation()` nunca lança (retorna null).
- Overlays dos campos são dropdowns pequenos (`CompositedTransformFollower`,
  `showWhenUnlinked:false`) — não barriers full-screen; leak não pinta branco.
- Bodies são `ListView` com filhos de altura limitada — **sem** o padrão `Row(stretch)`
  dentro de ListView que causou a "Serviços tela branca" anterior.

**Não há crash estático determinístico.** Não reescrevi telas de criação de pedido
(crítico p/ receita) por especulação. Hipóteses mais prováveis, por ordem:
1. **APK desatualizado no device** (padrão já visto neste projeto; CI auto-bumpa versionCode).
2. Exceção runtime específica do device — precisa de **logcat** para capturar.

**Próximo passo recomendado (Danilo):** instalar o build mais recente (Play Internal) e,
se persistir, capturar:
`adb logcat -c && adb logcat | grep -iE "EXCEPTION|FlutterError|sendPackage|carryGroceries|RenderBox|overflow"`
e reabrir a tela. Com o stack trace, o fix é cirúrgico.

## #5 — Foto de perfil (upload + aparecer) — ✅ código correto
`profile_screen.dart:283-337`: upload direto (`avatars` + `getPublicUrl` + cache-bust `?v=`)
→ fallback Edge Fn `upload-avatar` (service_role) → persiste via
`auth_store.updateCurrentUserPhoto` (users/drivers/restaurants). Robusto. Sem alteração.
