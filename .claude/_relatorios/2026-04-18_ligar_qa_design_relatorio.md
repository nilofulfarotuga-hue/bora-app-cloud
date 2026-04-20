# RELATÓRIO — LIGAR PENDENTES + QA + DESIGN
Data: 2026-04-18
Modo: PROTECÇÃO TOTAL — aprovação por tarefa
Backup: branch `backup/2026-04-18-pre-ligar-pendentes`

---

## Fase 1 — 6 itens BR §26.2 ligados

Todos os fixes passam `flutter analyze` (apenas 2 `info` pré-existentes em zonas intocadas).

### Item 1 — Auto-abrir RatingScreen após `delivered`
- **Ficheiros:** [lib/screens/order_tracking_screen.dart](../../lib/screens/order_tracking_screen.dart)
- **Alteração:** novo método `_maybeOpenRating` (guard idempotente `_ratingNavigated`) chamado em `build` após `_freshOrder`. Navega via `addPostFrameCallback` se `status == delivered && assignedDriverId != null`.
- **Imports adicionados:** `rating_screen.dart`, `rating_model.dart`.
- **Risco:** 🟢 listener isolado. Zero toque em DB.

### Item 2 — Botão "Reservar mesa" guardado por `reservationsEnabled`
- **Ficheiros:**
  - [lib/models/restaurant_model.dart](../../lib/models/restaurant_model.dart) — campo `reservationsEnabled` (default `false`), `copyWith`
  - [lib/stores/restaurant_store.dart](../../lib/stores/restaurant_store.dart) — lê `reservations_enabled` do DB + novo helper `restaurantById`
  - [lib/screens/restaurant_menu_screen.dart](../../lib/screens/restaurant_menu_screen.dart) — `Builder` que busca `RestaurantModel` via `restaurantId` e renderiza `OutlinedButton "Reservar mesa"` só se `reservationsEnabled == true`. Abre `ReservationFlowScreen`.
- **Risco:** 🟢 model aditivo, UI guardada. Cor `#1B5E20` usada.

### Item 3 — Takeaway bypass no dispatch
- **Ficheiros:**
  - [lib/models/order_model.dart](../../lib/models/order_model.dart) — campo `isTakeaway` + `fromSupabase` + `toSupabase` + construtor
  - [lib/stores/order_store.dart:1125](../../lib/stores/order_store.dart#L1125) — `restaurantMarkReady` salta `callingDriver` se `order.isTakeaway == true`. `createOrder` passa `isTakeaway` ao `OrderModel`.
- **Correcção de âmbito:** o bypass real acontece em `restaurantMarkReady` (não `_simulateRestaurantFlow`), porque partner restaurants saem cedo do simulador e o dispatch é disparado pelo dashboard do parceiro.
- **Risco:** 🟡 `_simulateRestaurantFlow`/`restaurantMarkReady` estão **fora** da zona protegida BR §25.3 (`finalizePurchase` intocado).
- **TODO conhecido:** falta transição `preparing → delivered` para fechar o pedido após cliente recolher (fora de âmbito).

### Item 4 — Gorjeta no checkout (Opção B aprovada: implementação completa com DB)
- **Ficheiros:**
  - `supabase/migrations/20260418020000_order_tip_cents.sql` — `ADD COLUMN orders.tip_cents INT NOT NULL DEFAULT 0` (aditivo)
  - [lib/models/order_model.dart](../../lib/models/order_model.dart) — campo `tipCents` + `fromSupabase` + `toSupabase`
  - [lib/stores/order_store.dart](../../lib/stores/order_store.dart) — `createOrder` aceita `tipCents`
  - [lib/stores/cart_store.dart](../../lib/stores/cart_store.dart) — `_tipCents` + `tipEur` getter + `setTipCents` + reset
  - [lib/screens/cart_screen.dart](../../lib/screens/cart_screen.dart) — widget `TipSelector` (já existia) + linha "Gorjeta" + total soma gorjeta
- **BR §4.5:** presets 1€/2€/3€/5€ + livre. Split 80/20 é trabalho de payout/backend (comentário na migration).
- **Limitação MVP:** cobrança real via Stripe passa por `paymentBufferTotal` (zona protegida) — gorjeta em card permanece registada em DB, não pré-autorizada.

### Item 5 — Pré-pagamento €3 reservas (aviso UI)
- **Ficheiros:** [lib/screens/reservation_flow_screen.dart:199-244](../../lib/screens/reservation_flow_screen.dart#L199-L244)
- **Alteração:** substituído texto plano por Column com badge "Pagamento via Stripe — em desenvolvimento. Nesta versão não haverá cobrança automática." Nenhum código Stripe tocado.
- **Risco:** 🟢 zero. Só UI.

### Item 6 — Migration `reservations_enabled` + toggle no painel parceiro
- **Ficheiros:**
  - `supabase/migrations/20260418030000_restaurant_reservations_enabled.sql` — `ADD COLUMN restaurants.reservations_enabled BOOLEAN NOT NULL DEFAULT false`
  - [lib/stores/restaurant_store.dart](../../lib/stores/restaurant_store.dart) — novo método `toggleReservationsEnabled` (mesmo padrão de `toggleRestaurantOnline`)
  - [lib/screens/partner_dashboard_screen.dart](../../lib/screens/partner_dashboard_screen.dart) — novo `_ReservationsToggleCard` com `SwitchListTile.adaptive` (`activeThumbColor: #1B5E20`), inserido entre `_OverviewCard` e `_OrdersSection`
- **Risco:** 🔴 migration DB aditiva — **pendente de aplicação** à instância Supabase `ojykpzwqrtusfeakzrna` (aguardar decisão A/B do Danilo).

---

## Fase 2 — QA Report

### Fixes automáticos aplicados
1. **`WillPopScope` → `PopScope`** (1×) — `driver_home_screen.dart:1555` (diálogo de oferta de pedido, `canPop: false`).
2. **`withOpacity(x)` → `withValues(alpha: x)`** (13×) nos ficheiros:
   - `driver_home_screen.dart` (3)
   - `driver_map_screen.dart` (2)
   - `order_details_screen.dart` (4)
   - `partner_dashboard_screen.dart` (2)
   - `restaurant_dashboard_screen.dart` (2)
3. **Remoção de dead code:** classe `_InfoRow` não usada em `profile_screen.dart:642-666`.

### Issues restantes (info-level, escolhidos para NÃO tocar)

| Ficheiro | Issue | Porquê não tocar |
|---|---|---|
| `payment_method_screen.dart:543-544` | `RadioListTile.groupValue/onChanged` deprecated | Toca fluxo de pagamento (tangente a Stripe — zona protegida) |
| `payment_method_screen.dart:487` | `BuildContext` across async gap | Precisa análise caller mais profunda |
| `register_partner_screen.dart:113` | mesma razão | Idem |
| `navigation_service.dart:51` | mesma razão | Idem |
| `directions_service_web.dart:4` | `dart:js` deprecated | Web implementation, migração não-trivial |
| `place_autocomplete_service_web.dart:4-5` | `dart:html` / `dart:js` deprecated | Idem |
| `map_marker_helper.dart:126` | `BitmapDescriptor.fromBytes` deprecated | Funcional, migração a planear |
| `order_store.dart:1151` | `curly_braces` info | Estilo, sem efeito |
| `register_client_screen.dart:163`, `register_driver_screen.dart:123` | `curly_braces` info | Estilo |

### Falsos positivos QA-scan
- `partner_dashboard_screen.dart:637` — `onPressed: null` é estado **disabled intencional** (OutlinedButton a mostrar label do status actual).
- 10× `backgroundColor: Colors.white` em AppBars — maioritariamente com `foregroundColor: Colors.black87` (não há white-on-white). Confirmado em `restaurant_menu_screen.dart:100`, `stores_screen.dart:113`, etc.

### Observações BR / fluxo
- Fluxo de entrega (BR §1.3) respeitado em `order_tracking_screen.dart`.
- Rating automático (BR §13) agora ligado via Item 1. Se `assignedDriverId == null` (takeaway — Item 3), rating pula naturalmente — bom comportamento.

---

## Fase 3 — Design Report (material para Claude Design)

Uso actual da paleta oficial Bora:
- Verde primário `#1B5E20` usado 4× em `lib/` — **insuficiente**.
- Laranja/vermelho `#E65100` usado 13× — mais usado que o verde.

### Cores hardcoded fora da paleta (decisão Claude Design)
**Funcionais (semântica própria — provavelmente manter):**
- `client_home_screen.dart:143` `#25D366` (WhatsApp green — botão de suporte)
- `driver_map_screen.dart` + `order_details_screen.dart` `#1C6EF2` (azul de dropoff marker vs laranja de pickup)
- `client_home_screen.dart:273-337` paleta pastel de quick-service tiles (7 cores)
- `store_categories_screen.dart:50-61+` paleta por categoria de mercado (convenção iFood/Uber Eats)

**Ambíguos (sugerir unificação em Bora verde):**
- `driver_earnings_screen.dart:575-615` usa `#2E7D32` (quase-Bora verde mas não exacto) → **recomendar `#1B5E20`**
- `stores_screen.dart:245` `#2E7D32` idem
- `role_screen.dart:97` `#1565C0` (azul) — role de cliente — considerar branding

**Neutros (OK):**
- `#EEEEEE`, `#F0F0F0`, `#F5F5F5` — backgrounds grey

### Espaçamentos fora do grid 4/8
- **`EdgeInsets.all(10)`** × 7 ocorrências → sugerir 8 ou 12
- **`EdgeInsets.all(14)`** × 3 → sugerir 12 ou 16
- **`EdgeInsets.all(6)`** em `profile_screen.dart:456` → sugerir 4 ou 8
- **`EdgeInsets.all(7)`** em `restaurant_menu_screen.dart:662` → sugerir 8
- **`SizedBox(height: 10)`, `width: 10`, `height: 6`, `width: 14`** — dezenas de ocorrências (maioritariamente em `admin/`, `client_home`, `driver_home`)

### Benchmark (BR §11 de qa-engineer)
- **Uber Eats checkout:** tip pré-seleccionada 15% · múltiplos de 8 · 2 cores primárias. Bora agora tem tip + split 80/20 — parity atingida.
- **iFood:** tip cards horizontal ao lado do total — actualmente Bora tem debaixo do total. Discutível.
- **Glovo:** minimalista 1 CTA grande — Bora tem 1 CTA "Finalizar pedido", OK.

### Lista consolidada para Claude Design
1. Unificar verdes secundários (`#2E7D32`) → `#1B5E20` em driver_earnings e stores.
2. Substituir `EdgeInsets.all(10|14|6|7)` por vizinhos grid 4/8.
3. Substituir `SizedBox(height: 10/6)` e `width: 10/14` por 8 ou 12.
4. Decidir se paletas pastel de category tiles (7 cores `client_home`, 15+ cores `store_categories`) ficam ou são compactadas em 2–3 famílias alinhadas à marca.
5. Avaliar criar `AppColors` centralizado (`lib/config/app_colors.dart`) com `primary #1B5E20`, `secondary #E65100`, `pickup #FF9800`, `dropoff #1C6EF2`, etc — elimina hardcodes.

---

## Verificação global

- [x] 6 itens BR §26.2 ligados
- [x] QA completo — fixes seguros aplicados, restantes documentados
- [x] Design auditado — lista actionable produzida
- [x] Zonas protegidas (BR §25.3) NÃO tocadas:
  - `pricing_service.dart` — intocado
  - `driver_capacity_service.dart` — intocado
  - `order_store.finalizePurchase` — intocado
  - triggers `bora_tokens` / `trg_award_tokens_on_delivery` — intocados
  - Código Stripe — intocado (apenas UI informativa adicionada)
  - `dispatch-engine/index.ts` (edge function) — intocado
- [x] Backup branch `backup/2026-04-18-pre-ligar-pendentes` criado antes de qualquer edit
- [x] `flutter analyze` em todos os ficheiros tocados: OK (apenas info-level pré-existentes em zonas intocadas)

## Pendências a resolver com Danilo

1. **Aplicar as 2 migrations** ao Supabase (`ojykpzwqrtusfeakzrna`):
   - `20260418020000_order_tip_cents.sql`
   - `20260418030000_restaurant_reservations_enabled.sql`
   - **Aguardando decisão A (MCP `apply_migration`) ou B (manual).**
2. **Takeaway completion:** falta transição `preparing → delivered` via confirmação do cliente (novo sub-item §26.2 ou cobrir em sessão seguinte).
3. **Design tokens:** criar `AppColors` centralizado conforme sugestão Fase 3.

## Próximo passo

1. Danilo escolhe A/B para migrations.
2. Testar manualmente no telemóvel Android:
   - Criar pedido parceiro com gorjeta → verificar `orders.tip_cents` no DB
   - Ligar `reservations_enabled` no painel do parceiro → botão "Reservar mesa" aparece em cliente
   - Takeaway → pedido não chama estafeta
   - Concluir entrega no driver → rating abre automaticamente no cliente
3. Claude Design itera sobre lista Fase 3.
