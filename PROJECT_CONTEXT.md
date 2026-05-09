# BORA — Project Context (Auto-Generated)
## Data: 2026-04-13

---

### 1. Visão Geral

**Bora App** é uma plataforma de delivery e logística urbana (Portugal), com três perfis de utilizador (client, driver, partner) e quatro tipos de serviço. O backend é 100% Supabase (PostgreSQL + Edge Functions + Realtime). O frontend é Flutter (mobile + web). Os pagamentos são processados via Stripe (cartão) ou simulados localmente (MBWay, cash).

**Supabase Project:** `ojykpzwqrtusfeakzrna.supabase.co`

---

### 2. Estrutura do Projeto

```
bora_app/
├── lib/
│   ├── auth/                  # AuthStore
│   ├── config/                # business_rules.dart, maps_config.dart
│   ├── data/                  # fake_data.dart, postal_coordinates.dart
│   ├── dispatch/              # dispatch_engine.dart (noop), driver_capacity_service.dart
│   ├── models/                # order_model.dart, driver_model.dart, restaurant_model.dart, ...
│   ├── screens/               # todos os ecrãs por role
│   ├── services/              # payment_service.dart, pricing_service.dart, place_autocomplete_service.dart, ...
│   ├── stores/                # order_store, cart_store, driver_store, session_store, restaurant_store, ...
│   └── utils/                 # map_utils.dart
├── supabase/
│   ├── functions/             # Edge Functions (TS/Deno)
│   │   ├── dispatch-engine/
│   │   ├── create-payment-intent/
│   │   ├── stripe-webhook/
│   │   ├── confirm-mbway-payment/
│   │   └── _shared/           # business_rules.ts (fallback), cors.ts, platform_settings.ts (cancel fees @runtime)
│   └── migrations/            # 10+ migrations SQL
└── pubspec.yaml
```

**Stack:**
- Flutter (Dart) — mobile + web
- Supabase (PostgreSQL, Auth, Realtime, Edge Functions/Deno)
- Stripe (`flutter_stripe` + Supabase Edge Function)
- Google Maps (`google_maps_flutter` + `latlong2`)
- Provider (state management)
- SharedPreferences (sessão local)

---

### 3. Skills & Orquestrador

Não existem ficheiros `SKILL.md` no projeto. O conceito de "orquestrador" aplica-se ao **DispatchEngine** — ver secção 5 (Edge Functions) e secção 7 (Stores).

**Dispatch flow (backend-first):**
- A Flutter `DispatchEngine` está **desativada** (`// Todos os métodos estão desativados`).
- O dispatch real é feito pela Edge Function `dispatch-engine` (Supabase).
- O Flutter `DispatchEngine.attach()` é um no-op idempotente chamado pelo `ProxyProvider2`.

---

### 4. Business Rules

**Ficheiro principal:** `lib/config/business_rules.dart`

#### Tokens (Loyalty)
| Regra | Valor |
|---|---|
| Valor por token | €0.005 (100 tokens = €0.50) |
| Desconto máximo por pedido | 50% do total |
| Tokens por entrega — driver | 40 tokens (flat) |
| Tokens por entrega — client | ROUND(preço × 3%) mín. 1 |
| Award trigger | Server-side (PostgreSQL trigger `fn_award_tokens_on_delivery`) |
| Expiração | Configurável por linha na tabela `bora_tokens` |
| Idempotência | UNIQUE(source_order_id, role) |

#### Pricing (PricingService)
| Parâmetro | Valor |
|---|---|
| Delivery fee partner | €2.50 |
| Driver base pay (delivery) | €3.80/entrega |
| Driver rate per km | €0.20/km |
| Comissão platform (partner) | 20% do subtotal |
| Markup non-partner | 15% do subtotal |
| Taxa compra non-partner | €2.50 |
| Bónus shopping driver | €0.80 (store shopping: shopper+deliverer) |
| Package base fee | €6.00 (até 4 km) |
| Package extra per km | €0.50/km |
| Package platform share | €2.00 |
| Logistics driver base pay | €4.00 |
| Logistics rate per km | €0.50/km |
| Surcharge apartamento total | €1.50 (driver €1.00 + platform €0.50) |
| Plataform commission rate | 20% |
| Limite cash por pedido | €40 (server-enforced via trigger; source: `platform_settings.max_cash_amount_cents`) |

#### Batching (DriverCapacityService)
| Tipo de serviço | Regra |
|---|---|
| `carryGroceries`, `sendPackage` | Sem batching — driver tem de estar livre |
| Partner orders | Máx. 2 simultâneos; 2.º deve ser mesmo vendor OU ≤ 800m |
| Non-partner orders | Máx. 3 simultâneos; todos do mesmo vendor |

#### Outros
- `requiresCar`: orders com motas não podem ser servidas se `requiresCar=true`
- `VehicleType.car` serve tudo; `VehicleType.motorcycle` não serve `sendPackage` com `requiresCar`

---

### 5. Base de Dados (Supabase)

#### Migrations aplicadas
| Ficheiro | Conteúdo |
|---|---|
| `20260330155359_remote_schema.sql` | Schema base (orders, drivers, restaurants, products) |
| `20260404000000_bora_tokens.sql` | Sistema de tokens/loyalty |
| `20260404000001_bora_tokens_type_fix.sql` | Fix de tipo UUID |
| `20260404000002_consume_tokens.sql` | Função FIFO consume_tokens() |
| `20260409000000_driver_balance_cash_system.sql` | Saldo cash drivers + cap (actualmente €40 via `platform_settings`) |
| `20260409000001_order_financial_split.sql` | Campos financeiros por pedido |
| `20260409000002_financial_ledger.sql` | Ledger financeiro |
| `20260409000003_admin_dashboard_metrics.sql` | Métricas para dashboard admin |
| `20260409000004_auto_ledger_settlement.sql` | Settlement automático |
| `20260409000005_financial_hardening.sql` | Hardening financeiro |

#### Tabelas Principais

**`orders`**
- Campos principais: `id (UUID)`, `status (TEXT)`, `service_type`, `order_type`, `payment_method`, `payment_status`, `price`, `subtotal`, `delivery_fee`, `service_fee`, `platform_commission`, `driver_earnings`, `distance_km`, `is_partner_store`, `apartment_delivery`, `requires_car`, `vendor_name`, `pickup_address`, `pickup_lat/lng`, `delivery_lat/lng`, `assigned_driver_id (TEXT legacy)`, `current_driver_offer_id`, `driver_offer_expires_at`, `tried_driver_ids`, `payment_intent_id`, `estimated_total`, `final_purchase_value`, `final_total`, `payment_buffer_total`, `refund_amount`, `extra_charge`
- RLS: auth.uid() IS NOT NULL para SELECT (infere-se da RestaurantStore)

**`drivers`**
- Campos: `id (UUID)`, `name`, `phone`, `vehicle_type`, `is_online`, `lat`, `lng`, `status (pending/approved/rejected)`
- Realtime: canal `public:drivers`

**`bora_tokens`**
- Campos: `id (UUID)`, `user_id (UUID)`, `role (client/driver)`, `amount (INT)`, `is_used (BOOL)`, `used_at`, `created_at`, `expires_at`, `source_order_id (UUID nullable)`
- UNIQUE: `(source_order_id, role)` — idempotência
- Função: `get_user_tokens(p_user_id UUID)` → INTEGER

**`driver_balances`**
- Campos: `driver_id (UUID PK)`, `balance (NUMERIC 10,2)`, `updated_at`
- Atualizado apenas por trigger `apply_driver_cash_settlement`

**`driver_transactions`**
- Campos: `id (UUID PK)`, `driver_id (UUID)`, `order_id (UUID UNIQUE)`, `amount (NUMERIC 10,2)`, `type (cash_adjustment)`, `created_at`
- Índices: `driver_id`, `created_at DESC`

#### Triggers/Functions SQL
| Trigger/Function | O que faz |
|---|---|
| `fn_award_tokens_on_delivery()` | Atribui tokens ao driver (40) e client (3% preço) quando status → `delivered` |
| `apply_driver_cash_settlement` | Atualiza `driver_balances` quando pedido cash é entregue |
| `consume_tokens(p_user_id, p_amount, p_order_id, p_role)` | FIFO consume tokens, cria remainder row se necessário |
| `get_user_tokens(p_user_id)` | Retorna saldo de tokens ativo (não expirado, não usado) |

#### Order Status Flow
```
created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
       ↘ rejected
```
- Partner: `restaurantAcceptOrder → restaurantMarkReady → callingDriver`
- Non-partner: `preparing → callingDriver` (com delay simulado)

---

### 6. Edge Functions

| Função | O que faz | Estado |
|---|---|---|
| `dispatch-engine` | Encontra pedidos em `callingDriver`, seleciona driver disponível, persiste oferta, faz redispatch automático por timer (42s + retry) | **Ativo** |
| `create-payment-intent` | Cria Stripe PaymentIntent; re-valida amount contra DB; retorna `{clientSecret, paymentIntentId}` | **Ativo** |
| `stripe-webhook` | Recebe eventos Stripe (`payment_intent.succeeded`, etc.), atualiza `payment_status` em `orders` | **Ativo** |
| `confirm-mbway-payment` | Simula confirmação MBWay; atualiza payment_status | **Ativo (simulado)** |

#### Shared
- `_shared/business_rules.ts` — constantes de negócio (sync com Dart)
- `_shared/cors.ts` — headers CORS

#### Config toml
- `dispatch-engine/config.toml` — existente (rastreado)
- `create-payment-intent/config.toml` — novo não-commitado
- `stripe-webhook/config.toml` — novo não-commitado

---

### 7. Stores (State Management)

| Store | Responsabilidade | Estados geridos |
|---|---|---|
| `SessionStore` | Role do utilizador, persistência em SharedPreferences | `UserRole?`, `isLoaded` |
| `AuthStore` | Autenticação dual (in-memory + Supabase). Demo accounts hardcoded. | `currentClient`, `currentDriver`, `currentPartner`, `isLoggedIn` |
| `OrderStore` | Ciclo de vida dos pedidos, realtime `orders_channel`, _advanceStatus com ID comparison | `List<OrderModel>`, realtime channel, fallback timer 3s |
| `CartStore` | Carrinho, persistência SharedPreferences `bora_cart_v1`, cálculo de pricing | `List<CartItem>`, `OrderServiceType`, `isPartnerStore`, checkout |
| `DriverStore` | Estado dos drivers, realtime `public:drivers`, animação localização (12 steps × 80ms) | `List<DriverModel>`, token balance, syncDriverWithAuth |
| `RestaurantStore` | Restaurantes/lojas de Supabase, produtos por restaurante, realtime `_restaurantsChannel` + `_productsChannel` | `List<RestaurantModel>`, `Map<String, List<PartnerProduct>>` |
| `PartnerProductStore` | Proxy sobre RestaurantStore para produtos do parceiro | filtra por restaurantId do parceiro logado |
| `DispatchEngine` | **No-op** — só existe para compatibilidade com ProxyProvider2 | Singleton desativado |
| `ChatStore` | Mensagens de chat por pedido | (em desenvolvimento) |
| `FavoriteStore` | Favoritos do cliente | (em desenvolvimento) |

**Demo accounts (sempre disponíveis offline):**
- Client: `cliente@bora.app` / `123456`
- Driver: phone `910000000` / `123456`
- Partner: sem conta demo (requer registo)

---

### 8. Models

| Model | Campos-chave |
|---|---|
| `OrderModel` | id, status (OrderStatus), serviceType, orderType, paymentMethod, paymentStatus, total, subtotal, deliveryFee, serviceFee, platformCommission, driverEarnings, distanceKm, isPartnerStore, apartmentDelivery, requiresCar, estimatedTotal, finalPurchaseValue, finalTotal, paymentBufferTotal, refundAmount, extraCharge, isPurchaseFinalized, vendorName, pickupAddress, deliveryAddress, assignedDriverId, clientPhone, paymentIntentId |
| `DriverModel` | id, name, location (LatLng), vehicleType (motorcycle/car), phone, licensePlate, isOnline, status (pending/approved/rejected), activeAssignments |
| `RestaurantModel` | id, name, isPartner, category (restaurant/supermarket/store/pharmacy), address, lat, lng |
| `PartnerProduct` | id, restaurantId, name, price, isAvailable |
| `CartItem` | productId, name, price, quantity |
| `OrderPricingBreakdown` | distanceKm, subtotal, deliveryFee, serviceFee, platformCommission, driverEarnings, apartmentSurcharge, customerTotal |

**Enums:**
- `OrderStatus`: created, preparing, callingDriver, driverAccepted, pickedUp, onTheWay, delivered, rejected
- `OrderServiceType`: restaurant, storeShopping, carryGroceries, sendPackage
- `OrderType`: partnerRestaurant, nonPartnerPurchase
- `PaymentMethod`: card, mbway, cash
- `PaymentStatus`: pending, authorized, captured, refunded, extraCharged, failed
- `VehicleType`: motorcycle, car
- `DriverStatus`: pending, approved, rejected
- `BusinessCategory`: restaurant, supermarket, store, pharmacy

---

### 9. Screens & Fluxos

#### Screens principais
| Screen | Role | O que faz |
|---|---|---|
| `role_screen.dart` | público | Escolha de role (client/driver/partner) |
| `login_screen.dart` | público | Login genérico |
| `client_login_screen.dart` | client | Login cliente (email+pass) |
| `driver_login_screen.dart` | driver | Login driver (phone+pass) |
| `partner_entry_screen.dart` | partner | Entry point parceiro |
| `client_main_screen.dart` | client | Home cliente — lista restaurantes/lojas |
| `cart_screen.dart` | client | Carrinho de compras |
| `payment_method_screen.dart` | client | Pagamento (Stripe/MBWay/Cash) + token discount |
| `map_screen.dart` | client | Mapa de acompanhamento de entrega |
| `order_details_screen.dart` | client | Detalhes do pedido |
| `carry_groceries_form_screen.dart` | client | Form para carryGroceries |
| `send_package_form_screen.dart` | client | Form para sendPackage |
| `driver_home_screen.dart` | driver | Home driver — lista ofertas e pedidos ativos |
| `driver_map_screen.dart` | driver | Mapa de navegação durante entrega |
| `admin_dashboard_screen.dart` | admin | Dashboard financeiro (email allowlist temporário) |

#### Navegação
Toda a navegação é gerida pelo `_RootNavigator` em `main.dart` — **widget-rebuild pattern**. Não existem `Navigator.push` para screens principais. Trocar role ou estado de auth faz rebuild automático.

#### Fluxo de Pedido Completo (client → driver)
```
[Client]
  1. Seleciona restaurante/loja (ClientMainScreen)
  2. Adiciona itens ao carrinho (CartStore)
  3. Escolhe morada de entrega
  4. Escolhe método de pagamento (PaymentMethodScreen)
     → Aplica token discount (máx 50%)
     → Stripe: cria PaymentIntent → confirma pagamento
     → MBWay/Cash: simulado
  5. Pedido criado em Supabase (status: created → preparing)

[Backend — DispatchEngine Edge Function]
  6. preparing → callingDriver (timer ou partner accept)
  7. Dispatch Engine seleciona driver disponível
  8. Oferta enviada ao driver (current_driver_offer_id + expires_at)
  9. Driver tem 10s para aceitar ou é passado ao próximo

[Driver]
  10. Recebe oferta (DriverHomeScreen)
  11. Aceita → status: driverAccepted
  12. Chega ao local → pickedUp
  13. A caminho → onTheWay
  14. Entrega confirmada (código 4 dígitos) → delivered

[Pós-entrega — automático]
  15. Trigger SQL: tokens atribuídos (client + driver)
  16. Cash settlement (se pagamento cash): driver_balances atualizado
```

---

### 10. Integrações Externas

| Integração | Status | Notas |
|---|---|---|
| **Stripe** | Funcional | Mobile-only (kIsWeb guard). Backend via **Supabase Edge Functions** (`create-payment-intent`, `refund`, `charge-extra`) — não usa BACKEND_BASE_URL. Webhook ativo. Min 0.50 EUR enforced. |
| **MBWay** | Simulado | Edge Function `confirm-mbway-payment` — sem integração real com banco |
| **Cash** | Funcional | Server-side cap €40 (`platform_settings.max_cash_amount_cents`). Settlement automático via trigger. |
| **Google Maps** | Funcional | `google_maps_flutter` para widget + `latlong2` para cálculos. API key em `maps_config.dart` |
| **Google Places Autocomplete** | Funcional | Conditional imports (web/mobile/stub) |
| **Supabase Realtime** | Funcional | orders_channel (INSERT/UPDATE/DELETE) + public:drivers. Retry 5s. Fallback timer 3s. |
| **Firebase / Push Notifications** | **Desativado** | `notification_service.dart` comentado. Requer `google-services.json`. HTTP notify-drivers/notify-client ainda funcionam. |
| **Supabase Auth** | Funcional | Anon key + signInWithPassword. Role via `user.userMetadata['bora_role']`. Driver email sintético: `{phone}@driver.bora.app` |

---

### 11. Problemas Conhecidos (TODOs/FIXMEs)

| Localização | Tipo | Descrição |
|---|---|---|
| `lib/screens/admin/admin_dashboard_screen.dart:12` | Temporary | Email allowlist para acesso admin — "intentionally temporary" |
| `lib/services/payment_service.dart` | Funcional | Usa `Supabase.instance.client.functions.invoke(...)` directamente — sem dependência de `BACKEND_BASE_URL`. Edge Functions `create-payment-intent`, `refund` e `charge-extra` todas deployed. |
| `supabase/functions/create-payment-intent/config.toml` | Untracked | Ficheiro novo não commitado |
| `supabase/functions/stripe-webhook/config.toml` | Untracked | Ficheiro novo não commitado |
| `lib/main.dart` | Disabled | Firebase.initializeApp() comentado — push notifications mobile não funcionam |
| `lib/dispatch/dispatch_engine.dart` | Design | Flutter DispatchEngine é singleton no-op — qualquer referência a métodos de dispatch no Flutter é inócua |
| `orders.assigned_driver_id` | Legacy | Coluna é TEXT (não UUID) — cast necessário nos triggers SQL |
| `lib/services/pricing_service.dart` | Comment | `_driverBasePay = 3.80 // was 4.0`, `_shoppingDriverBonus = 0.80 // was 1.0` — valores mudados sem registo formal |
| Realtime sync | Open | CLAUDE.md marca como "Current Focus" — sincronização realtime entre dispositivos |
| Driver flow | Open | CLAUDE.md marca como "Current Focus" — fluxo driver incompleto |
| Auth/session persistence | Open | CLAUDE.md marca como "Current Focus" |

---

### 12. Resumo Executivo (para CEO AI)

#### ✅ PRONTO para produção
- **Order lifecycle completo** — criação, status flow, entrega, confirmação por código
- **Dispatch Engine server-side** — Edge Function robusta com retry, timeout, anti-duplicação
- **Sistema financeiro** — ledger, driver balances, cash cap €40, settlement automático
- **Tokens/Loyalty** — atribuição automática, FIFO consumption, token discount no checkout
- **Pricing engine** — todos os tipos de serviço com fee breakdown completo
- **Auth dual-layer** — in-memory + Supabase, demo accounts offline, SharedPreferences
- **Google Maps** — mapa cliente + driver, autocomplete de moradas
- **MBWay e Cash** — funcionais (simulado MBWay, real Cash com settlement)
- **Batching rules** — DriverCapacityService com regras por tipo de serviço
- **Admin dashboard** — métricas financeiras (acesso por allowlist)

#### ⚠️ PARCIAL (funciona mas precisa de trabalho)
- **Stripe** — integrado via Supabase Edge Functions (`create-payment-intent`, `refund`, `charge-extra`, `stripe-webhook`). Mobile-only. Sem necessidade de `BACKEND_BASE_URL`. **LIVE activo desde 2026-04-24**: `pk_live_` via `--dart-define=STRIPE_PUBLISHABLE_KEY` no build, `sk_live_` + `whsec_` nos secrets Supabase. Node backend em `backend/server.js` existe como referência no repo mas o serviço Render (bora-backend-2dp0) está **suspenso** — a app nunca o chamou.
- **Realtime sync** — subscriptions ativas mas CLAUDE.md indica bugs de sincronização entre dispositivos
- **Driver flow UI** — store e lógica presentes mas CLAUDE.md marca como incompleto
- **Auth/session persistence** — funcional mas com edge cases não resolvidos
- **Push Notifications** — código HTTP existe mas Firebase desativado; mobile sem push

#### ❌ POR FAZER
- **Firebase / Push Notifications** — requer `google-services.json` e re-ativar `notification_service.dart`
- **MBWay real** — integração com banco real (atual é simulada)
- **Partner demo account** — sem conta demo para role partner
- **Admin access control** — email allowlist deve ser substituído por RLS/role real
- **ChatStore / FavoriteStore** — stores existem mas em desenvolvimento

#### 🔴 3 Maiores Riscos para Lançamento

1. **Stripe em modo LIVE sem testes end-to-end** — backend via Supabase Edge Functions (`create-payment-intent`, `refund`, `charge-extra`) está deployed e a responder. Key Stripe em uso é `rk_live_` (restricted, não test). **Ação:** testar fluxo completo de pagamento real com pequeno valor antes do lançamento público + confirmar que o restricted key tem permissões `payment_intents:write` e `refunds:write`.

2. **Realtime sync entre dispositivos** — identificado como "Current Focus" no CLAUDE.md. Se o driver e o cliente não verem o mesmo estado de um pedido em tempo real, o fluxo de entrega quebra. **Ação:** resolver antes do lançamento.

3. **Push Notifications desativadas** — sem Firebase ativo, os drivers não recebem notificações de novas ofertas. Dependem exclusivamente do polling/realtime enquanto a app estiver aberta. Em produção, drivers com app em background não recebem ofertas. **Ação:** activar Firebase com google-services.json antes do lançamento.

---

### 13. Reservas PRO

Sistema de reservas mesa BEST-IN-CLASS aplicado 2026-05-08/09.

**Estado:** F1 SCHEMA + F2 BACKEND CORE aplicados. F3 UI CLIENTE pendente.

**F1 SCHEMA (2026-05-08):** 8 tabelas + 10 cols `reservations` + 13 settings novos.

**Tabelas:** `restaurant_floor_plans`, `restaurant_tables`, `restaurant_pacing_rules`, `restaurant_turn_times`, `reservation_table_assignments`, `reservation_waitlist`, `reservation_notify_list`, `client_restaurant_profiles`.

**F2 BACKEND CORE (2026-05-09):**
- 4 RPCs cliente (`client_search_availability`, `client_join_waitlist`, `client_join_notify`, `client_arrived`)
- 6 RPCs parceiro (`partner_create_floor_plan`, `partner_add_table`, `partner_combine_tables`, `partner_seat_walk_in`, `partner_mark_seated`, `partner_mark_finished`)
- 5 triggers (4 reservations + 1 waitlist)
- 5 CRON jobs pg_cron (reminders 24h/2h, pending alert, morning summary, expire lists)
- 9 notificações parceiro + 7 cliente automáticas
- Auto-logic: auto-VIP após 5 visits, auto-block após 3 no-shows / 5 late cancels

**Detalhes:** ver `.claude/.ai/business_rules.md` §50 (schema) + §51 (backend).

**Roadmap:** F3 UI CLIENTE → F4 UI PARCEIRO + ADMIN.
