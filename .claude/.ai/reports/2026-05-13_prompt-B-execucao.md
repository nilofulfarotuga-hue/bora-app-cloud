# PROMPT B — Relatório de Execução (Model + UI Cliente)

**Data:** 2026-05-14
**Modelo:** Opus 4.7 (1M context)
**Branch:** `autonomous-night-2026-04-29`
**Tag de segurança:** `pre-takeaway-flutter-2026-05-13` (criada antes da execução)
**Modo:** PROTECÇÃO TOTAL — zero alterações em DB / Edge Functions / scripts / migrations / backend

---

## 0. Auditorias prévias

### R1 — `status.index` hardcoded
9 call sites encontrados, todos usando símbolos `OrderStatus.X.index` (não números).
Reorder do enum com `readyForPickup` na posição 2 (entre `preparing` e `callingDriver`) mantém semântica correcta em todos os call sites:

| Call site | Comparação | Efeito p/ `readyForPickup` |
|---|---|---|
| `client_main_screen:42` | `>= driverAccepted.index` | **exclui** ✓ (sem driver) |
| `driver_home_screen:1200` | `>= pickedUp.index` | **exclui** ✓ |
| `order_details_screen:36` | `>= driverAccepted.index` | **exclui** ✓ |
| `order_tracking_screen:194` | `<= driverAccepted.index` | **inclui** ✓ (activo) |
| `order_tracking_screen:197` | `< delivered.index` | **inclui** ✓ |
| `order_tracking_screen:439` | `>= driverAccepted.index` | **exclui** ✓ |
| `driver_store:470` | `<= driverAccepted.index` | **inclui** ✓ |
| `driver_store:473` | `< delivered.index` | **inclui** ✓ |
| `restaurant_store:916` | `<= callingDriver.index` | **inclui** ✓ (parceiro vê) |

**Conclusão:** zero alterações necessárias por mudança de `.index`.

### R2 — `PricingService.calculateBreakdown`
Não foi tocado. `cart_screen.dart:30` já subtrai `deliveryFee` localmente via `cartStore.isTakeaway`. Com o novo getter compatível (`_serviceType == OrderServiceType.takeaway`), o padrão local funciona sem alterar PricingService. Server-side é authoritative (Claude.ai confirmou via MCP).

### Outros achados durante audit
- 3 switches `OrderServiceType` exhaustive (2 em `order_service_type.dart`, 1 em `order_store.dart:_resolveBagCount`) — todos receberam `case takeaway` ✅
- `order_store.dart:870` ainda escrevia `is_takeaway: true` no DB — **removido** (R6 confirmado: coluna apagada do servidor)

---

## 1. Ficheiros tocados

### Modificados (15)
| # | Caminho | Acção |
|---|---|---|
| 1 | [lib/models/order_service_type.dart](bora_app/lib/models/order_service_type.dart) | adicionado valor `takeaway` + 2 cases (label/description) |
| 2 | [lib/models/order_model.dart](bora_app/lib/models/order_model.dart) | enum reorder, 6 campos `takeaway_*`, removido `isTakeaway`, getter compat, label, remoção de `is_takeaway` em toSupabase |
| 3 | [lib/models/restaurant_model.dart](bora_app/lib/models/restaurant_model.dart) | 3 campos (`takeawayEnabled`, `curbsideEnabled`, `takeawayDefaultPrepMinutes`) + construtor + copyWith |
| 4 | [lib/stores/cart_store.dart](bora_app/lib/stores/cart_store.dart) | eliminado `_isTakeaway`, getter compat, `setServiceTypeFromOption`, curbside fields, flag `serviceTypeLockedByOptions` (R5) |
| 5 | [lib/stores/restaurant_store.dart](bora_app/lib/stores/restaurant_store.dart) | parsing 3 colunas + cache rebuild |
| 6 | [lib/stores/order_store.dart](bora_app/lib/stores/order_store.dart) | param `isTakeaway`→`takeawayIsCurbside`+`takeawayCurbsideInfo`, removido `is_takeaway` no UPDATE, guarda `_advanceStatus`, case takeaway em `_resolveBagCount` |
| 7 | [lib/screens/restaurants_screen.dart](bora_app/lib/screens/restaurants_screen.dart) | guard `showOptions` inclui `takeawayEnabled` |
| 8 | [lib/screens/restaurant_options_screen.dart](bora_app/lib/screens/restaurant_options_screen.dart) | cartões condicionais individuais (D1) + `setServiceTypeFromOption` |
| 9 | [lib/screens/cart_screen.dart](bora_app/lib/screens/cart_screen.dart) | switch só visível se `!serviceTypeLockedByOptions` (R5), invoca `setServiceTypeFromOption`, integra `_CurbsideForCart` |
| 10 | [lib/screens/order_tracking_screen.dart](bora_app/lib/screens/order_tracking_screen.dart) | banner `PickupCodeCard` quando `readyForPickup` + case em `_feeLabelForStatus` |
| 11 | [lib/screens/order_details_screen.dart](bora_app/lib/screens/order_details_screen.dart) | 3 cases em switches (`_isCancelable`, `_statusColor`, `_statusIcon`) |
| 12 | [lib/screens/orders_screen.dart](bora_app/lib/screens/orders_screen.dart) | case em `_StatusChip._color` |
| 13 | [lib/services/order_eta_service.dart](bora_app/lib/services/order_eta_service.dart) | case `readyForPickup` → null (sem driver, sem ETA) |
| 14 | [lib/screens/driver_map_screen.dart](bora_app/lib/screens/driver_map_screen.dart) | case defensivo (cinza) em `_StatusBadge._color` |
| 15 | [lib/screens/partner_dashboard_screen.dart](bora_app/lib/screens/partner_dashboard_screen.dart) | case mínimo "Pronto para levantar" (CTAs ficam para PROMPT C) |

### Novos (2)
| # | Caminho | Descrição |
|---|---|---|
| 16 | [lib/widgets/takeaway/curbside_inputs.dart](bora_app/lib/widgets/takeaway/curbside_inputs.dart) | Checkbox + textfield curbside com `isLocked` (D6) |
| 17 | [lib/widgets/takeaway/pickup_code_card.dart](bora_app/lib/widgets/takeaway/pickup_code_card.dart) | Cartão grande 6 chars + vendor + curbside info + ready_at |

**Nota:** o plano original previa 14+2 ficheiros; foi necessário tocar `partner_dashboard_screen.dart` (15º ficheiro) porque o switch `_buildBotaoEstafeta` é exhaustive sem default e a reorder do enum forçava adicionar `case readyForPickup` para o build passar. O case é mínimo (display "Pronto para levantar") — CTAs específicos (`partner_takeaway_mark_picked_up` etc.) vão no PROMPT C.

---

## 2. Decisões aplicadas

| # | Decisão Danilo | Implementação |
|---|---|---|
| D1 | Cartões condicionais individuais | `if (business.takeawayEnabled)` e `if (business.reservationsEnabled)` independentes em `restaurant_options_screen.dart` |
| D2 | Sem reservas + sem takeaway → menu directo | `showOptions = isPartner && (reservationsEnabled || takeawayEnabled)` em `restaurants_screen.dart:154` |
| D3 | `OrderServiceType.takeaway` | Adicionado ao enum + 4 switches actualizados |
| D4 | Eliminar `_isTakeaway` | Field removido; substituído por getter `isTakeaway => _serviceType == OrderServiceType.takeaway` em CartStore e em `OrderModelX` extension. `setServiceTypeFromOption(type)` é o único setter |
| D5 | notify-client com DB query | Deferido para PROMPT C (não tocado neste prompt) |
| D6 | Imutabilidade curbside UI-only | `CurbsideInputs` aceita `isLocked: bool`. Em `cart_screen.dart` é `false` (pré-paid); em `order_tracking_screen.dart` será `true` quando `paymentStatus==paid` (a usar no banner pós-paid, fora de scope do banner actual — Q: confirmar) |
| D7 | Pickup code 6 chars | `takeawayPickupCode` parseado como `String?` em `order_model.dart` — sem limite de tamanho; servidor é authoritative |
| D8 | `readyForPickup` entre `preparing` e `callingDriver` | Enum reorder na posição 2 (index 2). Comentário no enum explica o porquê semântico |
| D9 | Som parceiro separado | Não tocado |
| D10 | SQLs `partner_takeaway_*` em PROMPT C | Não tocado |
| R5 | Esconder switch quando veio de options | Flag `serviceTypeLockedByOptions` em CartStore, activada por `setServiceTypeFromOption`. Reset em `clearCart()`. UI: `if (cartStore.isPartnerStore && !cartStore.serviceTypeLockedByOptions)` |
| R6 | Remover `is_takeaway` writes | Removido de `toSupabase()` e de `order_store.dart` UPDATE block |

---

## 3. Verificação

### `flutter analyze`
- **Run 1** (pós-edição inicial): 97 issues, **1 erro** (`partner_dashboard_screen.dart:1050 non-exhaustive switch`)
- **Run 2** (após adicionar `case readyForPickup` em partner_dashboard): **96 issues, 0 errors** ✅
- Todas as 96 issues remanescentes são `info`/`warning` pré-existentes (deprecation, prefer_const, unused parameters/fields em ficheiros não tocados). Zero originadas pelo PROMPT B.

### `git status -s` em código produtivo
14 ficheiros `lib/` modificados + `lib/widgets/takeaway/` novo. **Zero alterações** em `supabase/functions/`, `supabase/migrations/`, `backend/`, `scripts/`.

---

## 4. Comportamento end-to-end (mental simulation)

### Fluxo cliente — restaurante com `takeawayEnabled=true && curbsideEnabled=true`
1. Cliente abre lista → vê restaurante normalmente.
2. Toca no card → `restaurants_screen.dart:154` activa `showOptions=true` (porque `takeawayEnabled || reservationsEnabled`).
3. **RestaurantOptionsScreen** mostra cartões: Entrega + Ir buscar (+ Reservar mesa se reservas activas).
4. Toca "Ir buscar" → `setServiceTypeFromOption(takeaway)` define `_serviceType=takeaway` + activa `_serviceTypeLockedByOptions=true`.
5. Menu carrega; cliente adiciona itens.
6. Cart screen:
   - Switch "Ir buscar" **escondido** (R5 — lockedByOptions).
   - `_CurbsideForCart` aparece (porque `isTakeaway==true && restaurant.curbsideEnabled`).
   - Cliente activa checkbox "Vou esperar no carro" + escreve matrícula.
   - Summary: `Entrega (takeaway) — €0,00` (subtraído localmente). Total = subtotal + tip.
7. Checkout → cria pedido. `OrderStore.createOrder` é invocado com `serviceType=takeaway` + `takeawayIsCurbside=true` + `takeawayCurbsideInfo='AA-12-BB cinza'`. Servidor (`create_order` RPC) calcula pricing authoritative (delivery_fee=0, service_fee=0, bag_fee=0, platform_commission=10% subtotal, partner_markup_hidden=5%, pickup_code 6 chars gerado).
8. Após sucesso → tracking screen abre.

### Fluxo cliente — restaurante com `takeawayEnabled=false`
1. `showOptions = isPartner && reservationsEnabled` (sem takeaway).
2. Se também `reservationsEnabled=false` → directo ao menu (D2).
3. No cart, `serviceTypeLockedByOptions=false` (cliente não passou por options). Switch "Ir buscar" aparece — mas cliente não consegue toggle se a backend rejeitar (servidor é authoritative). UX consistente com comportamento pré-existente.

### Tracking — status=readyForPickup
1. Realtime entrega update; `OrderModel` parseia `status='readyForPickup' takeawayPickupCode='AB47KM' takeawayReadyAt=…`.
2. `order_tracking_screen.dart` Stack overlay: banner `PickupCodeCard` aparece no topo (sobre o mapa) mostrando código + curbside info.
3. `_feeLabelForStatus(readyForPickup)` → `—` (não cancelável).
4. `OrderEtaService.minutesRemaining(readyForPickup)` → null (sem ETA de driver).

### Tracking — status=delivered (após parceiro marcar levantado)
- Banner `PickupCodeCard` desaparece (condicional ao status).
- Rating flow normal aparece (`_ratingNavigated`).

---

## 5. Riscos e mitigações aplicadas

| # | Risco previsto | Mitigação aplicada |
|---|---|---|
| R1 | Reorder enum quebra `.index` | Audit confirmou todos os call sites usam símbolos; semantics intactos |
| R2 | PricingService não trata takeaway | Display local em cart_screen continua a tratar; PricingService NÃO foi tocado |
| R3 | Switch `OrderServiceType` exhaustive sem default | 3 cases adicionados (`label`, `description`, `_resolveBagCount`) |
| R4 | `_advanceStatus` aceita transições para takeaway | Guarda explícita adicionada — só permite cancel/reject |
| R5 | Cart_screen switch redundante | Flag `serviceTypeLockedByOptions` esconde |
| R6 | Coluna `is_takeaway` removida | toSupabase + UPDATE block limpos |
| R7 | `notify-client` mensagem errada para takeaway | PROMPT C |
| R8 | DispatchEngine tenta dispatch para takeaway | Guarda em `_advanceStatus` + servidor não muda para callingDriver |
| R9 | Imports widgets — `app_colors.success`, `Spacing.xs`/`xl` | `flutter analyze` confirma OK (todos os símbolos existem) |
| R10 | Realtime getter dinâmico | OK por desenho |

### Risco emergente durante execução
- **R11 (novo):** `partner_dashboard_screen.dart` switch exhaustive sem default forçou inclusão. Tratado com case mínimo display-only. CTAs específicos (`partner_takeaway_accept`, `partner_takeaway_mark_ready`, `partner_takeaway_mark_picked_up`) e som novo pedido ficam para PROMPT C.

---

## 6. Sequência de commit

Tag pré-execução já criada:
```
pre-takeaway-flutter-2026-05-13
```

Commit único a fazer:
```
feat(takeaway): client flow + model + readyForPickup status (PROMPT B)
```

Ficheiros a stage:
- 15 modificados em `lib/`
- 1 directório novo `lib/widgets/takeaway/` (2 ficheiros)
- 2 novos relatórios em `.claude/.ai/reports/` (plano + execução)

**NÃO** stage: `.claude/settings.json`, `.github/hooks/*`, `.maestro/config.yaml`, `supabase/.temp/*`, ficheiros `_analyze_*.txt` em `.claude/.ai/` (não relacionados com o PROMPT B). 

**NÃO** push.

---

## 7. Pendente para Danilo

1. **Testar manualmente** (`flutter run`):
   - (a) Restaurante com `takeawayEnabled=true && curbsideEnabled=true` → 2 cartões em options → cart com curbside → checkout
   - (b) Restaurante com `takeawayEnabled=false && reservationsEnabled=true` → 2 cartões (Entrega + Reservar mesa, sem Ir buscar)
   - (c) Restaurante sem opções → menu directo
   - (d) Mock de order com `status=readyForPickup` → banner aparece sobre o mapa
2. **Validar pricing** com Claude.ai: confirmar que `create_order` RPC zera delivery/service/bag fees para takeaway.
3. **Após aprovação** → push manual da branch `autonomous-night-2026-04-29`.
4. **Próximo:** PROMPT C — parceiro + notifications + migrations.

---

## 8. Métricas

- **Ficheiros tocados:** 15 modificados + 2 novos = 17
- **Linhas afectadas:** ~280 added / ~50 removed (estimativa)
- **Erros analyze:** 0
- **Issues analyze remanescentes:** 96 (todos pré-existentes, fora de scope)
- **Backups:** tag `pre-takeaway-flutter-2026-05-13` (local-only)
- **Tempo de execução:** ~70 min (estimativa do plano: 2-3h)

---

**FIM DA EXECUÇÃO. Aguarda teste manual + aprovação do Danilo para push.**
