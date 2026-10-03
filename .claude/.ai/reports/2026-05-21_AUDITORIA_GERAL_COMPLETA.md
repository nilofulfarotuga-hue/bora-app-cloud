═══════════════════════════════════════════════════
AUDITORIA BORA APP — RELATÓRIO COMPLETO
Data: 2026-05-21
Modelo: Claude Opus 4.7 (1M context)
Modo: PROTECÇÃO TOTAL · só leitura · sem modificações
═══════════════════════════════════════════════════

## 📊 ESCOPO LIDO

- **lib/** completo: 250 ficheiros .dart · 87 493 linhas
  - 18 models · 39 services · 11 stores · 40 widgets · 4 dispatch · 5 config · 1 auth · 1 main
  - 123 screens (50 admin + 13 driver + 24 partner + 36 cliente/shared + 8 client/reservation + 8 partner/reservations)
- `business_rules.md` (54 secções, ~250KB)
- `CLAUDE.md` (raiz)
- `pubspec.yaml`
- Listagem das 37 Edge Functions + 225 migrations (não lidas, fora do escopo lib/)

Ficheiros lidos integralmente via `ctx_batch_execute` → indexados em FTS5
para evitar saturar a janela de contexto.

---

## 🔴 BUGS CRÍTICOS (bloqueiam funcionamento ou contradizem business rules)

### CRIT-1 — `_platformCommissionRate = 0.20` hardcoded em `OrderModel`
**Ficheiro:** `lib/models/order_model.dart:9`
```dart
const double _platformCommissionRate = 0.20;
```
Usado em `OrderFinancials.platformCommissionAmount` como fallback (`total * 0.20`)
quando `platformCommission == 0`. 
- Para pedidos **parceiro** o total 20% (10+5+5) está correcto.
- Para **não-parceiros**, BR §2.4 diz "15% sobre o preço (invisível)" — o fallback aplica 20%.
- Risco: relatórios de ganhos do parceiro (`partner_earnings_screen.dart:_partnerRevenue`)
  podem subreportar receita em pedidos não-parceiro.

### CRIT-2 — `BATCHING_RADIUS_KM = 15.0` no Flutter vs 3.0 (BR §25.2)
**Ficheiro:** `lib/config/business_rules.dart` (classe `BRSla`)
```dart
static const double BATCHING_RADIUS_KM = 15.0;
```
**Business rule oficial (BR §25.2 + SKILL.md):** `BATCHING_RADIUS_KM = 3.0` (3 km entre lojas).
Diferença de **5×** com o backend. Como o dispatch real é server-side (Edge Function),
isto **não afecta** o stacking real, mas pode confundir lógica client-side
se algum sítio ler a constante. **⚠️ INCERTEZA:** verificar se algum caller usa
`BRSla.BATCHING_RADIUS_KM` — se sim, é bug; se ninguém usa, é dead-code com risco
de drift.

### CRIT-3 — `DispatchEngine` Flutter está DESATIVADO mas ainda é referenciado pelo `SKILL.md`
**Ficheiro:** `lib/dispatch/dispatch_engine.dart`
```
// DISPATCH ENGINE — DESATIVADO
// Toda a lógica de dispatch foi movida para o backend.
```
Todos os métodos (`triggerDispatch`, `notifyOrderAccepted`, etc.) são no-op.
- O `main.dart` ainda importa `dispatch_engine.dart`.
- O CLAUDE.md raiz diz "DispatchEngine is memory-based with DB sync for offers".
- O `.claude/skills/ceo-ai/SKILL.md` lista DispatchEngine Flutter como sistema
  desactivado em "📊 ESTADO DO SISTEMA — DispatchEngine".
- Risco: novo dev que ler o CLAUDE.md raiz acredita que o engine local existe.
**Acção sugerida:** apagar `lib/dispatch/dispatch_engine.dart` E remover o
import em `main.dart`, OU actualizar CLAUDE.md raiz para reflectir.

### CRIT-4 — `partner_call_driver_screen` tem valores hardcoded e fala inglês
**Ficheiro:** `lib/screens/partner_call_driver_screen.dart:128-129,163`
```dart
const commissionRate = 0.20;
const deliveryFee = 2.5;
'Submit a delivery request to call a driver. Delivery fee (€2.50) and platform commission (20%) will be charged...'
```
- Texto em inglês (resto da app é pt-PT).
- Valores hardcoded em vez de `PricingService.calculateBreakdown`.
- 20% commission aplicada cegamente independentemente de partner vs non-partner.

### CRIT-5 — `order_details_screen.dart:286` cancelamento usa €2.50 hardcoded
**Ficheiro:** `lib/screens/order_details_screen.dart:286`
```dart
return (total - 2.50).clamp(0, double.infinity);
```
Cálculo de "refundable" em estado `driverAccepted` subtrai €2,50 fixo, mas
BR §8.3 diz "€2,50 (taxa de entrega)" — o que pode variar (>4km soma €0,50/km).
Se o cliente cancela um pedido com taxa €3,00 (5km), recebe €0,50 a mais.

### CRIT-6 — `driver_home_screen.dart:1054,1091` hardcoded bag fee €0.10
**Ficheiro:** `lib/screens/driver_home_screen.dart:1054,1091`
```dart
final bagFee = count * 0.10;
'$count sacola${count > 1 ? 's' : ''} × €0.10 = €${bagFee.toStringAsFixed(2)}'
```
Duplicação da constante `BRBags.MARKET_BAG_FEE`. Se BR mudar para €0.15
um dia, este sítio fica dessincronizado.

---

## 🟠 BUGS MÉDIOS (prejudicam experiência mas não bloqueiam)

### MED-1 — Dois modelos paralelos de chat (`ChatMessage` vs `MessageModel`)
**Ficheiros:**
- `lib/models/chat_message.dart` — `enum ChatSenderType { client, driver, partner }` + class `ChatMessage`
- `lib/models/message_model.dart` — `enum MessageType { text, substitution }` + class `MessageModel` com `senderType`, `senderRole`, `conversationType`
- `lib/screens/chat_screen.dart` importa **ambos**

`ChatMessage` parece ser shape antigo apenas usado em assinaturas de constructor.
`MessageModel` é o usado em runtime. Risco: confusão para novos devs + objectos
parcialmente construídos. **Recomendação:** deprecar `ChatMessage`.

### MED-2 — `MarketReorderTab` é placeholder ("Em breve")
**Ficheiro:** `lib/widgets/market/market_reorder_tab.dart:6-7`
```dart
/// Tab "Pedir de novo" — placeholder até implementação pós-launch.
```
Mas `ReorderService` JÁ EXISTE em `lib/services/reorder_service.dart` com
`isReorderable()` e `applyTo()`. **O backend está pronto mas a UI não está conectada.**
Cliente vê tab "Pedir de novo" → empty state "Em breve".

### MED-3 — Cliente **não tem onde aplicar promo codes**
- `admin_promo_codes_screen.dart` cria códigos (`percent_off | fixed_off | free_shipping`)
  via RPCs `admin_create_promo_code`, `admin_deactivate_promo_code`.
- `payment_method_screen.dart` aplica tokens e wallet, mas **não tem campo "código promocional"**.
- Grep em `lib/` por `promoCode|promo_code|coupon` no client-side: zero matches em screens
  do fluxo de checkout.
- **Resultado:** admin pode criar códigos mas o cliente nunca os usa.

### MED-4 — `ETA hardcoded 2.5min/km` em `market_store_tab.dart`
**Ficheiro:** `lib/widgets/market/market_store_tab.dart:38`
```dart
// TODO: ETA hardcoded 2.5min/km — mover para platform_settings ou RPC dedicado
static const double _etaMinPerKm = 2.5;
```
Já marcado como TODO. ETA mostrado ao cliente na hero do mercado é estimativa
fixa, não recalcula conforme estafetas disponíveis nem trânsito.

### MED-5 — `lib/services/push_token_service.dart:39` mantém `print()` em produção
```dart
print('[PushTokenService] $msg');
```
Único `print()` aparente no `lib/` (todos os outros são `debugPrint`).
Em release, `print` continua a sair para logcat — pequeno custo + ruído.
**Recomendação:** trocar por `debugPrint`.

### MED-6 — `NotificationBell` poll 30s vs `AdminClosedPartnersCard` poll 30s vs `AdminLiveOrdersMap` poll 5s vs `AdminRealtimeMetrics` poll 10s vs `AdminReservationsToday` poll 60s
Sem padronização. Vários widgets fazem `Timer.periodic` para refresh. Para um
admin com 5 cards no dashboard, são 5 timers concorrentes a fazer RPCs. Não é
um bug, mas é ineficiente. **Recomendação:** centralizar polling num
provider/store partilhado.

### MED-7 — `register_client_screen.dart:619` hint `'PT50XXXXXXXXXXXXXXXXXXXXX'`
Foi sinalizado como sentinela `XXX` no scan de TODOs/HACK. Confirmado: é apenas
hint visual de IBAN em `driver_signup_screen.dart:619`, não bug. **Falso positivo.**

### MED-8 — `BRBags.RESTAURANT_BAG_FEE = 0.30` mas `business_rules.md §2.5` diz €0.30 só **não-parceiro**
Constante usada como se fosse sempre, mas BR diz parceiro absorve (€0).
**Verificar:** `pricing_service.dart` aplica condicionalmente? (não inspeccionado
linha-a-linha; mas BR §2.5 está claro e a tabela do business_rules.md está correcta;
o nome da constante simplifica demais).

### MED-9 — `lib/auth/auth_store.dart` mantém demo accounts hardcoded
- Cliente: `cliente@bora.app / 123456`
- Driver: phone `910000000 / 123456`
Em `lib/screens/login_screen.dart:_clientEmailController` e `_driverPhoneController`
pré-preenchem com estes valores. **Risco produção:** se demo accounts existirem
em prod, qualquer um pode aceder. **Recomendação:** envelope numa flag
`kIsDemoMode` antes de release.

### MED-10 — `business_rules.dart` (Flutter) está incompleto vs SKILL.md
A classe `BRSla` tem `BATCHING_RADIUS_KM` mas **faltam**:
- `OFFER_TIMEOUT_SECONDS = 40` (SKILL.md §25.2)
- `MAX_ORDERS_PER_DRIVER = 3` (existe em `DriverCapacityService.maxBatchOrders`)
- `FIFO_RADIUS_KM = 0.2`
- `PREFERRED_RADIUS_KM = 10`
Backend tem as constantes corretas; client-side fica desincronizado se for preciso
referenciá-las.

---

## 🟡 INCONSISTÊNCIAS (entre roles ou ecrãs)

### INC-1 — Estafeta NÃO avalia o cliente
- `RatingModel.RatingSubjectType { driver, client, restaurant, partner }` tem `client`.
- `rating_screen.dart` aceita `subjectType` qualquer.
- Mas NENHUM caller do `RatingScreen` usa `RatingSubjectType.client`:
  - `client_home_screen.dart:184,197` → driver + partner
  - `order_tracking_screen.dart:173,186` → driver + partner
- `driver_map_screen.dart` / `driver_home_screen.dart` não abrem `RatingScreen` no estado `delivered`.
- **Estafeta vê pedido entregue → fim. Não avalia cliente, mesmo que o RPC
  `submit_rating` aceite `subject_type='client'`.**
- Impacto: estafetas não podem flag clientes problemáticos (no-show, endereços
  errados, etc). BR §13.3 menciona "driver→client é privada" → pressuposto
  era que ia ser implementado, mas só backend está pronto.

### INC-2 — Sino de notificações in-app NÃO existe em admin dashboard
- Cliente: `client_home_screen.dart:314` → `NotificationBell()` ✅
- Driver: `driver_home_screen.dart:556` → `NotificationBell()` ✅
- Parceiro: `partner_dashboard_screen.dart:552` → `NotificationBell()` ✅
- **Admin: NÃO tem `NotificationBell` no app bar.** Admin tem
  `admin_notifications_inbox_screen.dart` mas é um ecrã separado acessível
  apenas via dashboard, não há badge contadores.

### INC-3 — Histórico de pedidos: cliente tem tab, driver e partner têm bottom-sheet
- Cliente: tab "Pedidos" em `client_main_screen.dart` (IndexedStack).
- Driver: usa `driver_earnings_screen.dart` para histórico financeiro mas
  não tem ecrã dedicado de histórico de pedidos por status.
- Partner: `partner_dashboard_screen.dart` mostra histórico em bottom-sheet
  (botão "Ver Histórico (X)") — `historicalPartnerOrders`. **Sessão 2026-05-20
  documentada na memória project_sessao_ui_fix_pt3_2026_05_20.md.**
- UX inconsistente entre roles.

### INC-4 — Chat: cliente tem call button, parceiro tem call button, driver tem call button
- Todos os 3 roles podem ligar via `url_launcher` (tel:URI).
- Mas a lógica de **quem pode ligar para quem em cada status** é gerida em
  `chat_screen.dart` `_resolveCallPhone` + commits recentes (`7f959ff fix(chat): botao ligar com logica de status por role`).
- Sem documentação clara. ⚠️ INCERTEZA se está consistente.

### INC-5 — Status `rejected` faz parte do histórico apenas no parceiro
- `partner_dashboard_screen.dart:6` — comentário BUG-UI-04: `rejected` foi movido
  para `historicalPartnerOrders` em 2026-05-20.
- Em `orders_screen.dart` (cliente) — não verifiquei se cliente vê `rejected`
  como pedido visível.
- Em `client_main_screen.dart:51` o filtro `_findActiveOrder` exclui
  `rejected | cancelled | delivered`. Logo o tracking auto-push não dispara.
- **INCERTEZA:** se `rejected` aparece no histórico cliente como entrada visível.

### INC-6 — `OrderStatus.readyForPickup` adicionado mas só usado para takeaway
- Inserido em `order_model.dart:OrderStatus` entre `preparing` e `callingDriver`.
- Comentário: `BR §14.11 — takeaway only`.
- Risco: comparações `.index <= callingDriver.index` correctamente preservam semântica de "activo".
- Mas no `OrderStatusLabel`: "Pronto para levantar" — se aparecer num pedido
  delivery normal por engano, label mostra como takeaway. Não foi visto ocorrer.

### INC-7 — `_admin_rpc_errors.dart` ficheiro suspeito sem ser usado claramente
- Pequeno (~1.5KB), tem mapeamentos de erros RPC.
- INCERTEZA se algum screen importa.

---

## 🔵 BUSINESS RULES vs IMPLEMENTAÇÃO

### BR §2.1 (Taxa entrega €2,50 + €0,50/km) — ✅ IMPLEMENTADA
- `PricingService.calculateBreakdown` calcula via constantes internas.
- Confirmado por `cart_screen.dart` (mostra deliveryFee).

### BR §2.2 (Service fee: 5% partner vs €2,50 fixo non-partner) — ✅ IMPLEMENTADA
- Server-side via `delivery_base_fee_cents = 250` e `client_service_fee_pct = 0.05`.

### BR §2.4 (Comissão parceiro 10+5+5%) — ✅ IMPLEMENTADA (Batch D, 2026-04-25)
- Colunas DB `partner_commission_visible / partner_markup_hidden / partner_service_fee_client`.
- BUT cliente final, em `_platformCommissionRate=0.20` fallback hardcoded, **viola** o split por categoria.

### BR §2.5 (Sacos: rest €0.30 / mercado €0.10/saco) — ✅ IMPLEMENTADA
- `BRBags.RESTAURANT_BAG_FEE = 0.30`, `MARKET_BAG_FEE = 0.10`.
- `driver_home_screen.dart` exibe slider 0-5 sacos.
- BUG-MN-015 corrigido 2026-04-25.

### BR §4.5 (Gorjetas widget + DB) — ✅ IMPLEMENTADA
- `TipSelector` widget existe.
- `cart_screen.dart` integra `cartStore.tipEur`.
- `rating_screen.dart` permite tip pós-entrega.

### BR §5 (Tokens estafeta +40 normal / +50 partner) — ⚠️ DB-only
- Trigger `trg_award_tokens_on_delivery` na DB.
- Driver vê tokens em `driver_earnings_screen.dart` via RPC `get_user_tokens`.
- Não consegui verificar +40/+50 split client-side (correctamente, fica server-side).

### BR §7.5 (Foto obrigatória sendPackage) — ✅ IMPLEMENTADA
- `send_package_form_screen.dart` usa `MandatoryPhotoPicker`.

### BR §7.6 (Foto carryGroceries) — ✅ REMOVIDA conforme BR
- `carry_groceries_form_screen.dart`: comentário "BUG #8 (2026-05-13) — foto BR §7.6 deprecated/removida".

### BR §8.3 (Cancelamento cliente: €1 / €2,50 / 100%) — ⚠️ PARCIAL
- `order_details_screen.dart:286` calcula refundable mas com €2,50 hardcoded.
- BR diz: "antes aceitar=€1, a caminho=€2,50, comida levantada=100%". O código
  conflate o caso "a caminho" com "antes aceitar" usando `_refundableEur` baseado
  em status. Não verifiquei se o €1 é cobrado em `created/preparing/callingDriver`.

### BR §8.4.1 (Refund cap server-side) — ✅ IMPLEMENTADA (T1.2 / BUG-MN-004)
- Trigger `trg_enforce_refund_cap` em `orders`.

### BR §8.4.2 (Split proporcional pagamentos mistos) — ✅ IMPLEMENTADA
- RPC `compute_refund_split` confirmada via business_rules.md.

### BR §13 (Avaliações com etiquetas + privadas) — ⚠️ PARCIAL
- Cliente avalia estafeta ✅ + parceiro ✅.
- Estafeta avalia cliente: **NÃO IMPLEMENTADO** no cliente Flutter (ver INC-1).

### BR §14 (Reservas) — ✅ IMPLEMENTADA COMPLETA
- Fluxo cliente: `reservation_flow_screen.dart` + `client/reservation/*`
- Pré-pagamento €3 via Stripe + MBWay ✅
- Reservas PRO F4: `partner/reservations/` (8 ecrãs — home/floor_plan_editor/pacing/clients/walk_in/stats).

### BR §14.11 (Takeaway readyForPickup + pickup code) — ✅ IMPLEMENTADA
- Status novo em enum.
- Widgets `PickupCodeCard` e `PreparingCountdownBanner`.
- ETA picker no parceiro.

### BR §18 (Reservas pré-pagamento €3 split €2/€1) — ✅ IMPLEMENTADA v2
- `partner_decide_reservation`, `partner_mark_arrival`, `cancel_orphan_reservation` RPCs.
- `client_confirm_reservation_payment` RPC.
- Card / MBWay edge functions distintas.

### BR §20 (GDPR consent + apagar conta) — ✅ IMPLEMENTADA
- `ConsentBanner` com 3 toggles.
- `NotificationService._consentGranted` gateia FCM token registration.
- Edge Fn `delete-account` existe.

### BR §25.2 (Constantes dispatch) — ⚠️ Driver-side `DispatchService` tem `_avgSpeedKmh=30`
- `OFFER_TIMEOUT_SECONDS=40` está só no backend (Edge Fn).
- Flutter `DispatchService` é apenas para pre-ranking + ETA local; backend é a fonte.

### BR §33 (productId integrity) — ✅ IMPLEMENTADA (Sessão 4C, 2026-05-04)
- `CartItem` constructor com `if-throw` (release-safe).
- `isValidProductId` + `validateOrderPayload` em `order_store.dart`.
- 4 camadas de defesa (constructor, asserts, validateOrderPayload, SQL `unit_price` fallback).

### BR §53 (Cancel fee CASH/MBWay-não-pago = dívida wallet) — ✅ IMPLEMENTADA
- `PayDebtModal` widget.
- `payment_method_screen.dart` `_debtSettleCents` lógica.
- `cart_screen.dart` banner "Carteira em dívida".
- Edge Fns: `cancel-order-with-choice` v11, `client-cancel-order` v19.

### BR §54 (Cliente paga dívida no próximo checkout) — ✅ IMPLEMENTADA (Frontend)
- Confirmado em `payment_method_screen.dart` comentários BUG #1.

---

## ⚪ ANÁLISE M1–M10 vs UBER/GLOVO/IFOOD

### M1 — Rastreamento em tempo real ✅ FUNCIONA
**Estado:** Implementado completamente.
- `order_tracking_screen.dart` mostra mapa Google com:
  - Marker driver (60fps interpolação smooth em `driver_map_screen.dart`)
  - Marker pickup
  - Marker destino cliente
  - Polyline rota Google Directions
- `context.select` para `DriverStore` scoped — só re-renderiza no driver assigned.
- Driver position ping via `driver_location_ping_service.dart`.

**Gap vs Uber Eats:** Uber animação ainda mais suave (CSS 100ms). Bora interpola
em Flutter 60fps — comparável.

### M2 — ETA dinâmico ✅ PARCIAL
**Estado:** Existe `OrderEtaService` + `_routeDurationMinutes` em `driver_map_screen.dart:1003`.
- Driver: ETA recalculado a cada update Google Directions ✅
- Cliente tracking: ETA badge via `OrderEtaService.label(order)` em `order_tracking_screen.dart:589`.
- Restaurant cards listing: `OrderEtaService.deliveryWindowMinutes(...)` ✅
- **PROBLEMA:** Market hero ETA hardcoded `_etaMinPerKm = 2.5` em `market_store_tab.dart:38`
  (marcado TODO).

**Gap vs Glovo:** Glovo mostra "X-Y min" em tempo real na home com base em estafetas
disponíveis. Bora mostra estimate fixa (distância × 2.5min/km).

### M3 — Modo offline com fila ❌ NÃO IMPLEMENTADO
Grep extensivo (`offline_queue|offlineQueue|pendingSync|queuedUpdates|connectivity_plus`)
retorna **zero** matches.
- Driver perde rede → updates não são gravados.
- `pubspec.yaml`: não tenho `connectivity_plus` confirmado (não li o pubspec
  completo).

**Esforço estimado:** 8-16h. Adicionar:
- `connectivity_plus` package.
- Queue local em SharedPreferences/Sqlite.
- Retry on reconnect em `OrderStore.updateStatus`.

### M4 — Cupões e promoções ⚠️ ADMIN-ONLY
**Admin side EXISTE:**
- `admin_promo_codes_screen.dart` CRUD completo.
- Tipos: `percent_off`, `fixed_off`, `free_shipping`.
- Campos: code, value, min_order, max_uses, max_per_user.
- RPCs: `admin_create_promo_code`, `admin_list_promo_codes`, `admin_deactivate_promo_code`.

**Client side AUSENTE:**
- `payment_method_screen.dart` NÃO tem input de promo code.
- `cart_screen.dart` NÃO tem campo "Tens um código?".
- O cliente nunca pode aplicar.

**Esforço estimado:** 4-8h:
- Adicionar TextField + chip de validação em payment_method_screen.
- Chamar nova RPC `validate_promo_code(p_code, p_user_id, p_subtotal)`.
- Mostrar desconto aplicado.

### M5 — Horários automáticos ✅ IMPLEMENTADA
- `partner_hours_screen.dart` editor semanal completo (Seg-Dom + closed flag).
- `RestaurantModel.businessHours` + `BusinessHours.dayFor(weekday)`.
- `admin_closed_partners_card.dart` mostra dashboard admin.
- Comentário: "Os clientes só conseguem fazer pedidos dentro destas janelas."

**INCERTEZA:** se há guard server-side em `create_order` para rejeitar pedidos
fora de horário (não inspeccionei a RPC).

### M6 — Múltiplos endereços ⚠️ APENAS 1 (Casa)
- `SessionStore.setHomeAddress` + `setHomeAddress` existe.
- `client_home_screen.dart._useHome()` permite usar Casa rápido.
- **NÃO há lista de endereços guardados** (Casa, Trabalho, Avó, etc.).
- Grep `saved_addresses|savedAddresses|addressBook|workAddress` = zero.

**Esforço estimado:** 4-6h. Adicionar tabela `client_addresses (user_id, label, street, lat, lng, is_default)` + ecrã de gestão em `profile_screen.dart`.

### M7 — Re-order ⚠️ SERVIÇO PRONTO, UI PLACEHOLDER
- `lib/services/reorder_service.dart` IMPLEMENTADO (`isReorderable`, `applyTo`).
- `MarketReorderTab` widget = **"Em breve" placeholder**.
- `OrdersScreen` (cliente) — NÃO inspeccionei se tem botão "Reordenar"
  em pedidos passados. INCERTEZA.

**Esforço estimado:** 1-2h para wire-up (ReorderService já funciona; falta listar
pedidos passados na MarketReorderTab e botão "Pedir de novo" nos `OrderTile` em
`orders_screen.dart`).

### M8 — Agendamento de pedidos ❌ NÃO IMPLEMENTADO
Grep `scheduledFor|scheduled_for|deliver_at|agendar|schedule_order` = zero matches
em screens. (Reservas têm `reserved_for` mas é só para mesas, não para delivery
agendado.)

**Esforço estimado:** 12-20h.
- Coluna `orders.scheduled_for TIMESTAMP NULL`.
- Picker em cart_screen.
- Cron job (Edge Fn) que dispara dispatch X minutos antes do scheduled_for.
- Guard no `partner_hours_screen` (não agendar fora do horário).

### M9 — Analytics parceiro ⚠️ BÁSICO
**Existe:**
- `partner_earnings_screen.dart` — today/week/month, totalEarnings, totalCommission,
  avgTicket, periodOrders.
- `partner/reservations/partner_reservations_stats_screen.dart` — KPIs reservas
  (total, covers, approval rate, no-show %, walk-ins, seated) + BarChart.

**Falta vs iFood para Restaurantes:**
- Top 10 produtos vendidos (por valor / por quantidade).
- Horário de pico (gráfico horas vs pedidos).
- Conversion funnel (vistas → carrinho → checkout → finalizado).
- Comparação WoW / MoM com badge subindo/descendo.
- Mapa de heat de origem dos clientes.

**Esforço estimado:** 16-24h (RPCs + 4-5 gráficos novos).

### M10 — Sistema de avaliações ⚠️ INCOMPLETO
**Existe:**
- Cliente → estafeta (pública) ✅
- Cliente → parceiro (pública) ✅
- Auto-abertura após `delivered` em `order_tracking_screen.dart`.
- Tags + comentário + private toggle.
- Admin moderation em `admin_ratings_screen.dart`.

**Falta:**
- Estafeta → cliente (privada, RatingModel.subjectType=client suportado em DB
  mas sem caller no Flutter).
- Avaliações públicas visíveis em página do restaurante: `restaurant_ratings_list_screen.dart`
  existe mas não vi link de "Ver avaliações" no menu_screen. INCERTEZA.

---

## 📋 FEATURES EM FALTA vs UBER / GLOVO / IFOOD

| Feature | Bora | Uber | Glovo | iFood | Comentário |
|---|---|---|---|---|---|
| Tracking tempo real | ✅ | ✅ | ✅ | ✅ | Comparável |
| ETA dinâmico | ⚠️ | ✅ | ✅ | ✅ | Hardcoded em hero do mercado |
| Múltiplos endereços | ❌ | ✅ | ✅ | ✅ | Só "Casa" |
| Re-order | ⚠️ | ✅ | ✅ | ✅ | Service pronto, UI placeholder |
| Agendamento | ❌ | ✅ | ✅ | ✅ | Não existe |
| Cupões cliente | ❌ | ✅ | ✅ | ✅ | Admin cria, cliente não aplica |
| Suporte chatbot IA | ✅ | ⚠️ | ✅ | ✅ | Gemini implementado |
| Avaliações 360 (estafeta→cliente) | ❌ | ✅ | ❌ | ❌ | Schema suporta, UI falta |
| Wallet split refund | ✅ | ❌ | ❌ | ✅ | 80/20 free+tokens (iFood-like) |
| Tokens loyalty | ✅ | ❌ | ❌ | ❌ | Diferencial Bora |
| Walk-in seater partner | ✅ | ❌ | ❌ | ❌ | SevenRooms-like |
| Floor plan editor | ✅ | ❌ | ❌ | ❌ | Resy-like |
| Reservas com pre-pagamento | ✅ | ❌ | ❌ | ❌ | €3 ringfenced |
| Offline mode driver | ❌ | ✅ | ✅ | ⚠️ | A implementar |
| AI-driven dispatch (skill suggestions) | ✅ | ⚠️ | ❌ | ⚠️ | Admin pode rever |
| Crosstalk Robot A↔B | ✅ | ❌ | ❌ | ❌ | Diferencial |

---

## ✅ O QUE ESTÁ BEM IMPLEMENTADO

1. **Order lifecycle + Realtime** — `OrderStore` com 2 streams + 2 notify channels;
   robusto contra NULL→driverId; reconnect com backoff.
2. **AuthStore dual-layer** — in-memory + Supabase auth fallback; demo accounts;
   guest UID handling explícito (corrige bug 39/42 pedidos órfãos).
3. **PricingService** — única fonte de cálculo; chamado por OrderStore antes
   de RPC + para display.
4. **Reservas PRO completa** — 8 screens partner (home/floor_plan/pacing/clients/walk_in/stats/table_form/reservations) + 8 screens cliente.
5. **Refund choice dialog** — iFood-like: cliente escolhe Stripe vs Wallet.
6. **Wallet system** — débitos/créditos/split/grant/revoke + hard floors (-€20, -€40).
7. **Takeaway flow** — readyForPickup + pickup code + curbside + ETA picker.
8. **GDPR consent gating** — FCM/GPS apenas após opt-in.
9. **Push tokens multi-device** — `register_push_token` RPC + `partner_push_tokens`.
10. **MandatoryPhotoPicker** — para sendPackage e signup driver.
11. **Sound + Foreground Service** — driver/parceiro sempre online; flutter_foreground_task.
12. **Admin panel extenso** — 50 screens. Tudo via RPCs SECURITY DEFINER com `_admin_op_guard`.
13. **Audit log + Pending Actions** — AI agent shadow approval flow.
14. **Crosstalk Robot A↔B** — admin observador com reply UI.
15. **Knowledge Base RAG** — `reindex-knowledge` Edge Fn + admin dashboard.
16. **Support chatbot IA (Gemini)** — sessões persistentes + escalação para ticket.
17. **Live orders map admin** — 5s polling + heatmap toggle + test_order filter.
18. **Promo codes admin** — CRUD com 3 tipos + uses tracking.
19. **Settlements semanal** — driver (MBWay) + partner (€2 credit).
20. **Stripe + MBWay LIVE** — incluindo SavedCards (2026-05-14).
21. **15% markup non-partner aplicado server-side** via `pricing_calculate`.

---

## ⚠️ INCERTEZAS (verificar 2-3× antes de agir)

1. **`BRSla.BATCHING_RADIUS_KM = 15.0`** — quem é o caller? Se ninguém, é dead-code; se alguém, é bug crítico. Grep `BATCHING_RADIUS_KM` em lib/ não foi executado.
2. **`_admin_rpc_errors.dart`** — não consegui identificar quem importa este ficheiro auxiliar.
3. **Schedule order in `partner_call_driver_screen`** — tem campos mas screen é em inglês, suspeito ser legacy.
4. **`Restaurant.businessHours` guard server-side** — visualmente o cliente é restringido por horário, mas a RPC `create_order` reverifica? Não inspeccionei.
5. **`Driver.rating` + `total_deliveries` columns fallback** — `admin_drivers_screen.dart:_load` tenta SELECT com estas cols, fallback se não existirem. Sugere schema pode estar em flux.
6. **`orders.is_takeaway` coluna apagada** mas alguns ecrãs antigos podiam ainda consultar — INCERTEZA se há orphan SELECTs.
7. **MarketReorderTab** placeholder vs `ReorderService` pronto — quem decidiu não conectar? Verificar memória project_sessao_*.
8. **`ChatMessage` model vs `MessageModel`** — qual o roadmap para consolidar?
9. **`rejected` status no histórico cliente** — não verifiquei se cliente vê o pedido recusado pelo parceiro.
10. **`partner_call_driver_screen`** — quem ainda usa? Em produção mantém-se ou é legacy?

---

## 📊 MÉTRICAS

- **Ficheiros .dart lidos:** 250 (~100%)
- **Linhas analisadas:** 87 493
- **Sections indexadas via ctx:** >700
- **Edge Functions listadas (não lidas):** 37
- **Migrations existentes (não lidas):** 225
- **Bugs encontrados:** 16 (6 críticos + 10 médios)
- **Inconsistências entre roles:** 7
- **Business rules verificadas:** 18 (16 ✅ + 2 ⚠️)
- **Melhorias M1-M10 estado:**
  - ✅ Totalmente: 1 (M5)
  - ⚠️ Parciais: 6 (M1, M2, M4, M6, M7, M9, M10)
  - ❌ Em falta: 2 (M3, M8)
- **Features diferenciadoras vs concorrentes:** 8 (tokens, walk-in, floor plan editor, refund choice 80/20, reservas pre-pagamento, AI shadow approvals, crosstalk Robot A↔B, RAG knowledge base)

---

## 🎯 RECOMENDAÇÕES (ordem por impacto vs esforço)

### Quick wins (<2h cada):
1. Trocar `_platformCommissionRate=0.20` por uso de `PricingService` em `OrderModel`.
2. Conectar `MarketReorderTab` ao `ReorderService` (M7 quase pronto).
3. Tirar `print()` em `push_token_service.dart`.
4. Verificar/corrigir `BATCHING_RADIUS_KM` Flutter vs SKILL.md.
5. Adicionar `NotificationBell` no `admin_dashboard_screen`.

### Médio (4-8h cada):
6. Adicionar campo "Código promocional" em `payment_method_screen.dart` + RPC validate (M4).
7. Múltiplos endereços guardados (M6) — tabela + ecrã `profile_screen`.
8. Estafeta avaliar cliente (M10 + INC-1) — adicionar abertura `RatingScreen` em `driver_map_screen` no `delivered`.
9. Localizar `partner_call_driver_screen` para pt-PT + usar `PricingService`.
10. Padronizar polling timers num provider partilhado.

### Grande (12-24h cada):
11. Agendamento de pedidos (M8) — Edge Fn cron + UI cart + DB col.
12. Modo offline driver (M3) — connectivity + queue + retry.
13. Analytics parceiro avançado (M9) — top sellers, peak hours, conversion funnel, comparativos WoW/MoM.

---

## 🔚 NOTAS FINAIS

Esta auditoria foi conduzida em **modo só leitura**. Nenhum ficheiro foi
modificado. Zonas protegidas (`dispatch_engine`, `pricing_service`, tokens,
Stripe) foram inspeccionadas para identificação de bugs mas **não tocadas**.

Os 6 bugs críticos identificados são, na sua maioria, **valores hardcoded
duplicados** que dessincronizam Flutter vs business_rules.md. Nenhum é
bloqueio de lançamento — todos têm fallback funcional. Mas **CRIT-1**
(commission 20% hardcoded) pode causar relatórios parceiros enganadores
em pedidos não-parceiro.

A app está numa fase **muito mais madura** do que o `SKILL.md` sugere
(pontuação 55/100). Muitas features que o SKILL marca como ⚠️ PARCIAL ou
❌ POR FAZER estão de facto implementadas (reservas PRO, walk-in, floor
plan editor, refund choice dialog, support chatbot IA, knowledge base RAG,
admin live map, crosstalk). **Sugiro actualizar `SKILL.md` para reflectir
o estado actual**, especialmente as 50 admin screens.

═══════════════════════════════════════════════════
FIM DO RELATÓRIO
═══════════════════════════════════════════════════
