# Takeaway — Investigação Read-Only (Flutter Impact Mapping)

**Data:** 2026-05-13
**Modelo:** Opus 4.7 (1M context)
**Modo:** READ-ONLY (zero escrita em DB/git/código)
**Output:** este relatório apenas

---

## 0. Pre-flight

| Campo | Valor |
|---|---|
| Working dir | `c:\Users\danil\Desktop\projetosflutter\bora_app` |
| Branch | `autonomous-night-2026-04-29` ✅ (esperado) |
| HEAD | `0b01bd7 feat(admin): nova tela Configuracoes de Despacho em PT-BR` |
| Últimos 5 commits | `0b01bd7` admin dispatch · `85e099e` modal dispatch decision 20min · `7e8eb6c` retry adaptativo 10s/42s · `f9f7d2e` BUG H6 oferta vencida · `2329df3` revert debug diag |
| git status -s | 5 modificados (settings/hooks/maestro/supabase temp), 18 untracked (todos relatórios e ficheiros `_analyze_*`); ZERO modificações em `lib/`, `supabase/functions/`, `supabase/migrations/` |

Conclusão: árvore limpa do lado do código produtivo. Investigação não toca em nada.

---

## I1 — Impacto do novo status `readyForPickup` (CRÍTICO)

### Enum actual ([lib/models/order_model.dart](bora_app/lib/models/order_model.dart))

```dart
enum OrderStatus {
  created, preparing, callingDriver, driverAccepted,
  pickedUp, onTheWay, delivered, rejected, cancelled,
}
```

**Strings `readyForPickup` já em uso:** ZERO (grep limpo em `lib/` e `supabase/`).

### Tabela de switches — 8 ficheiros, ~12 switches

| # | Ficheiro:linha | Tipo | Exhaustive? | Para `readyForPickup` |
|---|---|---|---|---|
| 1 | [lib/models/order_model.dart:540-557](bora_app/lib/models/order_model.dart#L540-L557) | Model — `OrderStatusLabel.label` | SIM (sem default) | **OBRIGATÓRIO** — adicionar `'Pronto para levantar'` |
| 2 | [lib/screens/driver_map_screen.dart:1779-1791](bora_app/lib/screens/driver_map_screen.dart#L1779-L1791) | UI Estafeta — `_StatusBadge._color` | SIM (sem default) | **DEFENSIVO** — adicionar `case readyForPickup: return Colors.grey;` (driver nunca deveria receber, mas se Flutter desserializar order de outro tipo, não pode rebentar) |
| 3 | [lib/screens/driver_order_action_helper.dart:21-43](bora_app/lib/screens/driver_order_action_helper.dart#L21-L43) | UI Estafeta — `resolveDriverOrderAction` | NÃO (`default: return null`) | **OK sem alterações** — default cobre |
| 4 | [lib/screens/orders_screen.dart:394-408](bora_app/lib/screens/orders_screen.dart#L394-L408) | UI Cliente — `_statusColor` (histórico) | SIM (sem default) | **OBRIGATÓRIO** — `case readyForPickup: return AppColors.accent;` |
| 5 | [lib/screens/order_details_screen.dart:126-372](bora_app/lib/screens/order_details_screen.dart#L126) | UI Cliente — **4 switches** (label/icon/progress/actions, linhas 126/274/338/357) | SIM (todos sem default) | **OBRIGATÓRIO** — 4 cases novos |
| 6 | [lib/screens/order_tracking_screen.dart:883-911](bora_app/lib/screens/order_tracking_screen.dart#L883-L911) e seguintes (mais ~4 switches) | UI Cliente — `_statusColor` (com default), `_feeLabelForStatus`, etc. | mista (alguns com default, outros não) | **OBRIGATÓRIO** — auditar cada switch; o `_feeLabelForStatus` é exhaustive sem default e precisa `case readyForPickup: return '—'` (takeaway não pode ser cancelado depois de pronto) |
| 7 | [lib/screens/partner_dashboard_screen.dart:1051-1145](bora_app/lib/screens/partner_dashboard_screen.dart#L1051-L1145) | UI Parceiro — `_buildBotaoEstafeta` | SIM (sem default) | **OBRIGATÓRIO** — `case readyForPickup: return SizedBox.shrink();` (botão de chamar estafeta não se aplica a takeaway) |
| 8 | [lib/services/order_eta_service.dart:26-54](bora_app/lib/services/order_eta_service.dart#L26-L54) | Service — `etaForOrder` | SIM (sem default) | **OBRIGATÓRIO** — `case readyForPickup: return null;` (sem driver, sem ETA) |

### Resumo
- **6 switches obrigatórios** (modelo + cliente x3 + parceiro + service)
- **1 switch defensivo** (driver_map, baixa probabilidade mas evita crash)
- **1 switch OK** (driver_order_action_helper já tem default)

### Componentes partilhados (afectam ambos PROMPT B e C)
- `OrderStatusLabel.label` em `order_model.dart` é usado pelo cliente, parceiro e estafeta (`order.status.label` aparece em `partner_dashboard_screen.dart:1132`). **Alterar 1 vez serve todos.** → Pertence ao PROMPT que tocar primeiro no modelo (provável PROMPT B cliente).

---

## I2 — Restaurant Model (padrão para 3 campos novos)

### Estado actual

[lib/models/restaurant_model.dart:153,174](bora_app/lib/models/restaurant_model.dart) — `reservationsEnabled` é o padrão a replicar.

```dart
// Construtor (linha 153)
this.reservationsEnabled = false,

// Field (linha 174)
final bool reservationsEnabled;

// copyWith (linhas 228, 246)
bool? reservationsEnabled,
reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
```

Parsing em [lib/stores/restaurant_store.dart:903](bora_app/lib/stores/restaurant_store.dart#L903) (helper `_restaurantFromRecord`):

```dart
reservationsEnabled: data['reservations_enabled'] as bool? ?? false,
```

### Onde adicionar takeaway (5 sítios em 2 ficheiros)

**`lib/models/restaurant_model.dart`:**
1. Construtor named — 3 novos: `this.takeawayEnabled = false`, `this.curbsideEnabled = false`, `this.takeawayDefaultPrepMinutes = 15`
2. Campos final — 3 novos
3. `copyWith` — 3 novos parâmetros + 3 linhas no body

**`lib/stores/restaurant_store.dart` `_restaurantFromRecord`:**
4. 3 novas linhas de parsing:
   ```dart
   takeawayEnabled: data['takeaway_enabled'] as bool? ?? false,
   curbsideEnabled: data['curbside_enabled'] as bool? ?? false,
   takeawayDefaultPrepMinutes: (data['takeaway_default_prep_minutes'] as num?)?.toInt() ?? 15,
   ```

**Atenção:** existem outras invocações de `copyWith` em `restaurant_store.dart:680/807` — passam apenas `reservationsEnabled`. Os novos campos vão herdar via `??` (não exigem alteração nessas chamadas).

---

## I3 — Restaurant Options Screen

### Estado actual ([lib/screens/restaurant_options_screen.dart](bora_app/lib/screens/restaurant_options_screen.dart) — 107 linhas)

Já existe, criado em commit "BUG #9+10 (2026-05-13)". 3 cartões:

| Cartão | Tap → | Acção |
|---|---|---|
| **Entrega** | `_openMenu(takeaway: false)` | `cart.setTakeaway(false)` + push `RestaurantMenuScreen` |
| **Ir buscar** | `_openMenu(takeaway: true)` | `cart.setTakeaway(true)` + push `RestaurantMenuScreen` |
| **Reservar mesa** | `_openReservation()` | push `ReservationAvailabilityScreen` |

### Guard actual ([lib/screens/restaurants_screen.dart:154](bora_app/lib/screens/restaurants_screen.dart#L154))

```dart
final showOptions = business.isPartner && business.reservationsEnabled;
```

### ⚠️ PROBLEMA — a guard ignora `takeawayEnabled`

Hoje o cartão "Ir buscar" só aparece se o restaurante tem **reservas**. Restaurante com `takeaway_enabled=true && reservations_enabled=false` vai direto ao menu sem opção de takeaway.

**Correcção mínima (1 linha):**

```dart
final showOptions = business.isPartner &&
    (business.reservationsEnabled || business.takeawayEnabled);
```

**Decisão de UX a confirmar com Danilo:**
- (a) Se só `takeawayEnabled`, mostrar 2 cartões (Entrega/Ir buscar) — esconder Reservar mesa.
- (b) Se ambos, mostrar os 3 (estado actual).
- (c) Se só `reservationsEnabled`, esconder "Ir buscar" — actualmente está visível mesmo sem suporte de takeaway no servidor.

**Implementação sugerida:** condicionar cada cartão individualmente — `if (business.takeawayEnabled) BoraTileCard(label: 'Ir buscar', ...)` e idem para Reservar. Mais limpo que mostrar tudo sempre.

---

## I4 — Cart Store (`setServiceType` e `setTakeaway`)

### Enum actual ([lib/models/order_service_type.dart](bora_app/lib/models/order_service_type.dart))

```dart
enum OrderServiceType {
  restaurant,
  storeShopping,
  carryGroceries,
  sendPackage,
}
```

**❌ NÃO existe `OrderServiceType.takeaway`.**

### Estado actual do CartStore ([lib/stores/cart_store.dart](bora_app/lib/stores/cart_store.dart))

```dart
// linha 19
OrderServiceType _serviceType = OrderServiceType.restaurant;

// linha 224-229
bool _isTakeaway = false;
bool get isTakeaway => _isTakeaway;
void setTakeaway(bool v) {
  _isTakeaway = v;
  notifyListeners();
}

// linha 256-279 — setItemsAndServiceContext (único setter de _serviceType)
required OrderServiceType serviceType,
...
_serviceType = serviceType;
```

### ⚠️ DESCONEXÃO CRÍTICA

- `setTakeaway(true)` apenas seta `_isTakeaway` (bool) — **NÃO altera `_serviceType`**.
- O backend confirmado por Claude.ai espera `service_type='takeaway'` no `create_order` RPC.
- Hoje, mesmo clicando "Ir buscar", o serviceType continua `restaurant` quando o pedido é enviado → backend cria pedido com delivery_fee/service_fee, NÃO com a pricing especial de takeaway (subtotal puro + 10% commission visible + 5% markup hidden).

### Decisões a tomar (Danilo precisa decidir)

**Opção A — Adicionar `OrderServiceType.takeaway` ao enum** *(recomendada)*
- Vantagens: backend já espera; pricing engine fica consistente; aproveita a maquinaria existente do enum (label, switches).
- Custo: alteração em 1 ficheiro do modelo + ajustar `setTakeaway` para também setar `_serviceType = OrderServiceType.takeaway`; auditar uso de `_serviceType == OrderServiceType.restaurant` em `cart_store.dart:437/500` (sanity checks `isShoppingOrder`).
- Atenção: `OrderServiceTypeLabel` (extension) precisa do novo case "Para levantar".

**Opção B — Manter `_isTakeaway` bool + adicionar fork no payload do pedido**
- Em vez de mudar enum, no `createOrder` payload: se `_isTakeaway`, enviar `service_type: 'takeaway'` em vez de `_serviceType.name`.
- Vantagens: mínimo blast radius no Flutter.
- Desvantagens: ambiguidade — duas fontes de verdade (`serviceType` e `isTakeaway`) podem divergir; difícil de auditar.

**Recomendação:** Opção A. Razão: serviço de pricing, restaurant_store filters (`_isRestaurantPartnerOrder` em `restaurant_store.dart`), e order_model serializer já tratam serviceType como string única no DB.

### `clearCart()` ([lib/stores/cart_store.dart:407-420](bora_app/lib/stores/cart_store.dart#L407-L420))

Já reseta `_isTakeaway = false`. **Bom.** Se for Opção A, também precisa resetar `_serviceType = OrderServiceType.restaurant`.

---

## I5 — Edge Function de Push (`notify-client`)

### Função identificada

**`supabase/functions/notify-client/index.ts`** — linha 11:
```
// Called by Flutter NotificationService.notifyClientOrderStatus()
```

### Edge Functions disponíveis (lista deployed por nome)

```
admin-cancel-order            client-cancel-order        notify-admin-reimbursement
cancel-order-with-choice      finalize-order-from-intent notify-admin-urgent
notify-chat-message           notify-client              notify-driver
notify-partner                notify-partner-low-rating  notify-purchase-finalized
```

### Map actual de status → template

`statusMessage(status, vendorName, driverName, etaMinutes)` retorna `{title, body}`:

| Status | Title | Body |
|---|---|---|
| `preparing` | "Pedido aceite" | "👨‍🍳 ${vendor} está a preparar o seu pedido" |
| `callingDriver` | "À procura de estafeta" | "🛵 A procurar o melhor estafeta…" |
| `driverAccepted` | "Estafeta a caminho do restaurante" | "✅ ${driver} aceitou o seu pedido" |
| `pickedUp` | "Pedido recolhido" | "📦 O seu pedido foi recolhido e está a caminho" |
| `onTheWay` | "A caminho!" | "🛵 ~${etaMinutes} min" |
| `delivered` | "Entregue 🎉" | "Como foi a sua experiência?…" |
| _outro_ | `null` (devolve 400 se sem title/body) | |

### Onde adicionar takeaway

Não basta adicionar um único case `readyForPickup`. O fluxo takeaway pula `callingDriver/driverAccepted/pickedUp/onTheWay`. As mensagens existentes ficam **incorrectas** para takeaway:
- `preparing` para takeaway: deve dizer "fica pronto em ~X min", não "está a caminho".
- `delivered` para takeaway: deve dizer "Levantado ✓", não "Entregue 🎉".

**Estratégia recomendada** — adicionar parâmetro `serviceType` ao payload (caller envia `service_type`) e ramificar:

```ts
case 'preparing':
  return serviceType === 'takeaway'
    ? { title: 'Pedido aceite', body: `👨‍🍳 ${vendor} a preparar — pronto em ~${prepMinutes} min` }
    : { /* delivery actual */ };

case 'readyForPickup':
  return {
    title: 'Pronto para levantar 🎉',
    body: `Apresente o código ${pickupCode} no balcão${isCurbside ? ' ou aguarde no carro' : ''}.`,
  };

case 'delivered':
  return serviceType === 'takeaway'
    ? { title: 'Levantado ✓', body: 'Como foi? Avalie o pedido.' }
    : { /* delivery actual */ };
```

**Novos campos do payload necessários** (caller Flutter: `NotificationService.notifyClientOrderStatus`):
- `serviceType` (string)
- `prepMinutes` (int, opcional)
- `pickupCode` (string, opcional)
- `isCurbside` (bool, opcional)

**Versão actualmente deployed:** não acessível via grep local. Claude.ai deve confirmar via MCP `get_edge_function('notify-client')` antes do PROMPT C.

---

## I6 — Imutabilidade `takeaway_*` pós-paid

### Estado actual ([lib/stores/order_store.dart:1515](bora_app/lib/stores/order_store.dart#L1515))

Existe trigger server-side `enforce_financial_immutability` bloqueando UPDATE em colunas financeiras pós-criação. RPC `finalize_storeshopping_purchase` bypassa via session GUC + SECURITY DEFINER. Flutter **não** tem hoje guard explícito por `payment_status == 'paid'` para campos de não-financeiros — só verificação de fluxo (`isPaid` checks em [order_store.dart:2476](bora_app/lib/stores/order_store.dart#L2476)).

### Recomendação (a confirmar com Danilo)

| Campo | Imutável pós-paid? | Para quem? | Mecanismo |
|---|---|---|---|
| `takeaway_is_curbside` | **SIM** | Cliente | UI guard + (opcional) trigger SQL `enforce_takeaway_curbside_immutability` |
| `takeaway_curbside_info` (matrícula/cor) | **SIM** | Cliente | mesmo que acima |
| `takeaway_prep_minutes` | **NÃO para parceiro** (RPC `partner_takeaway_accept` define) | Cliente sempre bloqueado | RPC já é o único caminho oficial |
| `takeaway_pickup_code` | **SIM TOTAL** | Todos | gerado server-side, imutável (já é) |
| `takeaway_ready_at` | escrito por RPC `partner_takeaway_mark_ready` | imutável fora da RPC | RLS + RPC |
| `takeaway_picked_up_at` | idem `partner_takeaway_mark_picked_up` | imutável fora da RPC | RLS + RPC |

**Justificação:**
- Cliente alterar `is_curbside`/`curbside_info` **depois de pagar** abre race condition: parceiro pode já ter preparado para entrega no balcão e o cliente decide chegar de carro (ou vice-versa).
- Permitir antes do pagamento permite ainda iterar; bloquear após `paid` enquadra-se na semântica "contrato fechado".
- Implementação cliente-side mínima: em `order_details_screen.dart` (cliente), disable do checkbox curbside e do textfield matrícula `if (order.paymentStatus == 'paid')`.
- Implementação servidor (opcional, segurança em profundidade): trigger BEFORE UPDATE em `orders` que rejeita mudanças nestas 2 colunas quando `OLD.payment_status='paid'`.

**Edge case:** se cliente precisar mudar matrícula porque chegou no carro errado, suporte humano edita via admin RPC. Documentar.

---

## I7 — Uniqueness do `takeaway_pickup_code`

### Estado confirmado por grep

- ZERO referências a `pickup_code`, `pickupCode`, `partner_takeaway_*` em:
  - `lib/` (Flutter)
  - `supabase/migrations/` (locais)
  - `supabase/functions/`
  - `scripts/`
- Lógica de geração vive apenas em RPCs server-side (visível só via MCP).
- Claude.ai já confirmou: 4 chars uppercase, derivados de MD5(order_id), 26⁴ = ~456k combinações por restaurante (assumindo apenas A-Z) ou ~1.7M se [A-Z0-9].

### Risco actual

- Probabilidade de colisão simultânea **no mesmo restaurante** para 2 pedidos abertos: muito baixa (~1/450k).
- Em peak (10+ pedidos abertos simultâneos num restaurante grande): aproxima-se de 1/45k — ainda aceitável mas frágil.
- A UI mostra `restaurant_id + código` → mesmo com colisão entre restaurantes, parceiro não confunde.

### 3 opções (recomendação no fim)

| Opção | Custo | Benefício | Risco residual |
|---|---|---|---|
| (a) Aceitar risco actual | 0 | nenhum | baixo mas existe |
| (b) Adicionar UNIQUE(restaurant_id, takeaway_pickup_code) WHERE picked_up_at IS NULL e re-tentar geração | 1 migration + retry loop na RPC | colisão impossível por design | maior complexidade; retry pode falhar em deadlock raro |
| (c) Aumentar para 6 chars [A-Z0-9] | 1 linha SQL na geração | ~2 mil milhões de combinações; colisão estatisticamente nula | nenhum |

### Recomendação: **(c)**

Razão: 1 linha de código (mudar substring length 4→6, ou usar gen_random_uuid()::text + substring + upper), zero impacto operacional, elimina 99.999% do risco. O UX não sofre — 6 chars ainda cabem em qualquer ecrã e são fáceis de ditar oralmente ("A B 4 7 K M").

---

## 8. PLANO DE EXECUÇÃO (divisão sugerida para Danilo decidir)

**Nota:** não estou a propor próximo prompt. Apenas mapeio dependências para Danilo discutir com Claude.ai.

### PROMPT B — Cliente (Flutter, end-to-end takeaway client flow)

**Pré-requisitos:**
- Schema DB ok (confirmado por Claude.ai)
- 3 RPCs deployed (confirmado)
- Decisão I4: adicionar `OrderServiceType.takeaway` ✅ (recomendado)

**Escopo:**
- `OrderServiceType.takeaway` no enum (+label "Para levantar")
- `RestaurantModel` — 3 campos (`takeawayEnabled`, `curbsideEnabled`, `takeawayDefaultPrepMinutes`) + parsing
- `restaurants_screen.dart:154` — guard `(reservationsEnabled || takeawayEnabled)`
- `restaurant_options_screen.dart` — cartões condicionais; "Ir buscar" só se `takeawayEnabled`
- `cart_store.setTakeaway` — também setar `_serviceType`; reset em `clearCart`
- `cart_screen.dart` switch "Ir buscar" — auditar override (não vi código mas docs mencionam)
- Pricing UI no cart: zerar delivery_fee/service_fee/bag_fee visíveis quando takeaway
- `order_model.dart` — campo `takeaway*` para deserializar pedido (read-side)
- `OrderStatusLabel` — `'Pronto para levantar'`
- `OrderStatus.readyForPickup` no enum
- Switches cliente: `orders_screen.dart`, `order_details_screen.dart` (4), `order_tracking_screen.dart` (vários)
- `order_eta_service.dart` — case readyForPickup → null
- UI de checkout: checkbox curbside + textfield matrícula (se `curbsideEnabled`); disable se `payment_status='paid'`
- UI de tracking pós-paid: mostrar `pickup_code` grande, `ready_at` timer, `is_curbside` info

**Riscos:**
- 4 switches em `order_details_screen.dart` exhaustivos sem default — esquecer um quebra build.
- `cart_store` setters distribuídos — fácil deixar `_serviceType` divergir de `_isTakeaway` se não unificado.
- Pricing display do carrinho hoje calcula localmente — precisa branch para takeaway zerar campos.

### PROMPT C — Parceiro + Notifications + Admin

**Pré-requisitos:**
- PROMPT B fechado (componentes partilhados como `OrderStatusLabel` actualizados).

**Escopo:**
- `partner_dashboard_screen.dart` — case readyForPickup no switch; novo CTA "Marcar pronto" (chama `partner_takeaway_mark_ready`); CTA "Marcar levantado" (chama `partner_takeaway_mark_picked_up`); CTA "Aceitar com ETA" (chama `partner_takeaway_accept`) com selector 3/5/10/15/20/30/45/60 min, default = `restaurant.takeaway_default_prep_minutes`
- Toggle no painel parceiro para `takeaway_enabled` + `curbside_enabled` + `takeaway_default_prep_minutes`
- Som para parceiro em novo pedido takeaway (BUG-PT-006 paralelo)
- `notify-client` Edge Function — adicionar `serviceType/prepMinutes/pickupCode/isCurbside` no payload; ramificar `preparing`/`delivered` e adicionar `readyForPickup`
- `NotificationService.notifyClientOrderStatus` (Flutter) — passar os novos params
- Admin screen: filtro/coluna `service_type='takeaway'` em ordens
- `driver_map_screen.dart:1779-1791` — case defensivo `readyForPickup`

**Riscos:**
- Re-deploy de `notify-client` afecta TODO o cliente (não só takeaway) — testar regressão dos 6 status existentes.
- Som parceiro é blocker já existente — pode entrar em PROMPT separado.

---

## 9. Riscos identificados (gerais)

| # | Risco | Mitigação |
|---|---|---|
| R1 | 6+ switches exhaustivos sem default — esquecer 1 quebra build com warning vermelho do analisador Dart | Lista completa neste relatório (I1); usar `flutter analyze` antes de cada commit |
| R2 | `_serviceType` vs `_isTakeaway` divergência no CartStore | Adoptar Opção A em I4 (enum único como fonte de verdade) |
| R3 | Cliente abre order com `service_type='takeaway'` mas restaurante desliga `takeaway_enabled` entre o add-to-cart e o checkout | RPC `create_order` server-side já valida (confirmar com Claude.ai); UI fallback: ao falhar, mostrar erro "restaurante já não aceita takeaway" e voltar à home |
| R4 | `notify-client` re-deploy quebra status existentes | Smoke test com 1 pedido normal antes de prod |
| R5 | Cliente muda `curbside_info` depois de paid → race com parceiro a preparar | Imutabilidade post-paid (I6) |
| R6 | Colisão `pickup_code` em peak | Aumentar para 6 chars (I7 opção c) |
| R7 | Driver app pode receber order takeaway via realtime subscription mesmo sem necessitar | Driver app filtra por `service_type != 'takeaway'` no subscription, OU defensive `return null` no action helper (já existe) |

---

## 10. Perguntas pendentes para Danilo

1. **I3.a** — Confirmar UX: cartões condicionais individualmente ou sempre os 3 com mensagem "indisponível"?
2. **I3.b** — Quando `reservationsEnabled=false && takeawayEnabled=false`, ir direto ao menu (estado actual)?
3. **I4** — Aprovar **Opção A** (adicionar `OrderServiceType.takeaway` ao enum)? Confirmar que pricing engine server-side já trata correctamente este valor (Claude.ai confirmou via MCP, mas pedimos confirmação explícita).
4. **I4.b** — Manter `_isTakeaway` bool como mirror legado, ou eliminar completamente após adicionar enum? (eliminação é mais limpa; mirror é safer rollback).
5. **I5** — Estratégia de parametrização do `notify-client`: passar novos campos via payload (recomendado) OU deixar a Edge Function consultar a `orders` row via DB? (DB consulta é mais robusta mas adiciona latência).
6. **I6** — Aprovar imutabilidade pós-paid para `takeaway_is_curbside` + `takeaway_curbside_info`? Implementar UI-only inicialmente, trigger server-side em segunda fase?
7. **I7** — Aprovar opção (c) — aumentar `pickup_code` para 6 chars?
8. **Geral** — `OrderStatus.readyForPickup` deve ficar entre `pickedUp` e `delivered`, ou em fim do enum? (`.index` é usado em [restaurant_store.dart:_shouldKeepOrder](bora_app/lib/stores/restaurant_store.dart) para filtrar com `order.status.index <= OrderStatus.callingDriver.index` — adicionar `readyForPickup` no meio pode mudar ordering matemático).
9. **Geral** — Som parceiro novo pedido (BUG-PT-006) entra em PROMPT C ou fica separado? Bloqueador conhecido pré-takeaway.
10. **Migrations** — `partner_takeaway_*` RPCs e schema vivem só no projecto Supabase remoto (sem migration file local). Pedir a Claude.ai para extrair os SQLs e adicionar ao `supabase/migrations/` para versionamento?

---

## 11. Verificação final

| Item | Status |
|---|---|
| Zero INSERT/UPDATE/DELETE em DB | ✅ |
| Zero apply_migration / deploy_edge_function | ✅ |
| Zero git commit/push | ✅ |
| Zero modificações em ficheiros existentes | ✅ |
| Único output: este relatório | ✅ |
| `git status -s` em `lib/`, `supabase/functions/`, `supabase/migrations/` | ✅ vazio (sem alterações em código produtivo) |

---

**Fim do relatório.**
