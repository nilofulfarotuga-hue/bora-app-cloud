# BORA — Project Context (Auto-Generated)
## Data: 2026-04-14

---

### 0. Identidade do Negócio

Nome do negócio: Bora App
Fundador: Danilo
Email: boraappbora@gmail.com
Telefone: +351 937 501 673
Domínio/Site: ainda não tem
Redes sociais: ainda não tem

Logo: Letra "B" estilizada em verde escuro com um motociclista de entregas em vermelho/laranja por cima. Ao lado, texto "BORA" com "BO" em verde e "RA" em laranja. Fundo branco circular.

Cores da marca:
- Verde escuro (primária): #2E7D32
- Laranja/Vermelho (secundária): #E65100
- Branco (fundo): #FFFFFF

Tipografia do logo: bold, sans-serif, moderna

Personalidade da marca: acessível, rápida, urbana, portuguesa

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
| `notify-driver` | Envia FCM push ao driver quando oferta é atribuída. Requer FIREBASE_PROJECT_ID + FIREBASE_SERVICE_ACCOUNT secrets. No-op se secrets não configurados. | **Criado / aguarda deploy** |

#### Shared
- `_shared/business_rules.ts` — constantes de negócio (sync com Dart)
- `_shared/cors.ts` — headers CORS

#### Config toml (todos presentes)
- `dispatch-engine/config.toml` — existente ✅
- `create-payment-intent/config.toml` — criado ✅
- `stripe-webhook/config.toml` — criado ✅
- `confirm-mbway-payment/config.toml` — criado ✅

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
| **Stripe** | Funcional | Mobile-only (kIsWeb guard). Usa Supabase SDK diretamente (sem BACKEND_BASE_URL). Edge Function `create-payment-intent` ativa. Webhook ativo. Erro de cartão exibe mensagem visível ao utilizador. |
| **MBWay** | Simulado | Edge Function `confirm-mbway-payment` — sem integração real com banco |
| **Cash** | Funcional | Server-side cap €40 (`platform_settings.max_cash_amount_cents`). Settlement automático via trigger. |
| **Google Maps** | Funcional | `google_maps_flutter` para widget + `latlong2` para cálculos. API key em `maps_config.dart` |
| **Google Places Autocomplete** | Funcional | Conditional imports (web/mobile/stub) |
| **Supabase Realtime** | Funcional | orders_channel (INSERT/UPDATE/DELETE) + public:drivers. Retry 5s. Fallback timer 3s. `_driverOfferNotifyChannel` + `_driverActiveNotifyChannel` — capturam transições NULL→driverId que `.stream().eq()` perde. |
| **Firebase / Push Notifications** | **Desativado** | `notification_service.dart` comentado. Requer `google-services.json`. HTTP notify-drivers/notify-client ainda funcionam. |
| **Supabase Auth** | Funcional | Anon key + signInWithPassword. Role via `user.userMetadata['bora_role']`. Driver email sintético: `{phone}@driver.bora.app` |

---

### 11. Problemas Conhecidos (TODOs/FIXMEs)

| Localização | Tipo | Descrição |
|---|---|---|
| `lib/screens/admin/admin_dashboard_screen.dart:12` | Temporary | Email allowlist para acesso admin — "intentionally temporary" |
| `supabase/functions/*/config.toml` | Resolvido | Todos os 4 config.toml criados (dispatch-engine, create-payment-intent, stripe-webhook, confirm-mbway-payment) |
| `lib/main.dart` | Disabled | Firebase.initializeApp() comentado — push notifications mobile não funcionam |
| `lib/dispatch/dispatch_engine.dart` | Design | Flutter DispatchEngine é singleton no-op — qualquer referência a métodos de dispatch no Flutter é inócua |
| `orders.assigned_driver_id` | Legacy | Coluna é TEXT (não UUID) — cast necessário nos triggers SQL |
| `lib/services/pricing_service.dart` | Comment | `_driverBasePay = 3.80 // was 4.0`, `_shoppingDriverBonus = 0.80 // was 1.0` — valores mudados sem registo formal |
| Realtime sync | Resolvido | `_driverActiveNotifyChannel` adicionado — captura transições NULL→driverId para active delivery stream |
| Driver flow | Resolvido | Fluxo completo verificado: aceitar oferta → pickedUp → onTheWay → delivered com código 4 dígitos |
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

#### ✅ RESOLVIDO NESTA SESSÃO (2026-04-14 → 2026-04-15) — FASE 4 DADOS REAIS + SACO

- **Logos reais** — `restaurants` table: `photo_url` atualizado com Clearbit CDN para todos (McDonald's, KFC, BK, Pizza Hut, Continente, Lidl, Auchan, Pingo Doce, Intermarché, Mercadona)
- **Imagens produtos restaurantes** — todos os 179 produtos (McDonald's 52, KFC 41, BK 46, Pizza Hut 40) têm `photo_url` por categoria via Unsplash
- **Imagens produtos mercados** — todos os 17942 produtos sem foto receberam `photo_url` por categoria (Auchan 3003, Lidl 3002, Intermarché 3004, Pingo Doce 3101 - 59, Continente 590): 0 sem foto em todos os mercados
- **RestaurantMenuScreen reescrito** — mostra secções por categoria com emoji (🍔 Burgers, 🍗 Chicken, 🍕 Pizzas, etc.) + imagem 64×64 por produto + fallback. Carrega directamente do `RestaurantStore`. Ficheiro: `lib/screens/restaurant_menu_screen.dart`
- **Saco para viagem €0.30** — automático em pedidos de restaurante. `PricingService._restaurantBagFee = 0.30`. `OrderPricingBreakdown.bagFee` adicionado. `customerTotal` inclui `bagFee`. CartScreen mostra linha "Saco para viagem: €0.30"
- **Sacolas mercados €0.10×N** — driver escolhe número de sacolas ao confirmar entrega em pedidos `storeShopping`. Diálogo `_showBagCountDialog` em `driver_home_screen.dart` aparece antes do código 4 dígitos. `bag_count` guardado em `orders` via `OrderStore.updateBagCount()`. Migração `add_bag_count_to_orders` aplicada.

#### ✅ RESOLVIDO NESTA SESSÃO (2026-04-14 → 2026-04-15) — FASE 3 UI + DADOS

- **BUG 1 — Paginação produtos** — `loadProductsFromSupabase()` agora usa loop `.range(offset, offset+999)` para carregar >1000 produtos (Continente 4832, Auchan 3003, etc.)
- **BUG 2 — Preço em falta (Bebé)** — `_ProductCard` mostra preço base `product.price` quando não há variantes; "Preço indisponível" se price=0
- **BUG 3 — Mensagem laranja McDonald's** — Removida de `RestaurantMenuScreen` (exclusivo para restaurantes que preparam comida, não compras)
- **BUG 4 — Logos restaurantes/lojas** — `restaurants_screen.dart` e `stores_screen.dart` mostram `photoUrl` via `Image.network` com fallback de inicial em círculo
- **BUG 5 — Home UI** — Greeting "Olá [nome]!", categorias em `GridView` 3 colunas com cards brancos com sombra e ícone em caixa colorida
- **BUG 6 — Perfil cliente** — `profile_screen.dart` redesenhado: avatar circular, header verde, cards/sections, links para Pedidos e Suporte, botão logout estilizado
- **BUG 7 — Levar Compras** — Renomeado de "Fazer Compras" em UI; `OrderServiceType.carryGroceries.label` → "Levar Compras"; descrição atualizada
- **BUG 8 — Suporte chatbot** — `support_screen.dart` criado: chat com bolhas, 6 FAQs automáticas, fallback para email/telefone, acessível do perfil
- **BUG 9 — Imagens produtos** — `_ProductThumbnail` widget em `store_products_screen.dart`: 60×60 `Image.network(product.photoUrl)` com fallback por categoria

#### ✅ RESOLVIDO NESTA SESSÃO (2026-04-14 → 2026-04-15) — FASE 2 CARROÇARIA
- **Stripe** — usa Supabase SDK diretamente (sem BACKEND_BASE_URL). Erro de cartão mostra mensagem visível.
- **Realtime sync** — `_driverActiveNotifyChannel` resolve transições NULL→driverId perdidas por `.stream().eq()`
- **Driver flow UI** — verificado completo (aceitar → pickedUp → onTheWay → delivered + código 4 dígitos)
- **config.toml** — todos os 4 Edge Functions têm config.toml
- **Firebase/Push Notifications** — código completo activado. **Aguarda apenas:** `google-services.json` + `GoogleService-Info.plist` + secrets Supabase. Ver `README_FIREBASE_SETUP.md`.
- **UI Polish (Fase 2)** — `lib/config/app_theme.dart` criado com ThemeData centralizado (#2E7D32 primária, #E65100 secundária). Aplicado em `main.dart`. Screens polidas: role_screen, client_login, driver_login, client_main, cart_screen, payment_method, driver_home, order_details.
- **Painel Admin completo** — `admin_dashboard_screen.dart` expandido com nav cards. Novos: `admin_orders_screen.dart` (filtros + cancelar), `admin_drivers_screen.dart` (aprovar/rejeitar + saldo), `admin_partners_screen.dart` (activar/desactivar).
- **Gestão produtos parceiro** — `partner_products_screen.dart` + `add_product_screen.dart` já existiam e funcionais.
- **Seed data** — `20260415000000_seed_restaurants.sql`: 5 restaurantes PT (Tasca do Zé, Pingo Doce Express, Farmácia Saúde, Burger Palace, Mini Mercado Silva) com 20+ produtos realistas em €.

#### ⚠️ PARCIAL (funciona mas precisa de trabalho antes do lançamento)
- **Auth/session persistence** — funcional mas com edge cases não resolvidos
- **Push Notifications** — código 100% pronto; aguarda ficheiros de configuração Firebase (google-services.json + GoogleService-Info.plist + Supabase secrets). Ver `README_FIREBASE_SETUP.md`.

#### ❌ POR FAZER
- **Firebase config files** — adicionar `google-services.json` → `android/app/` e `GoogleService-Info.plist` → `ios/Runner/`
- **Supabase secrets Firebase** — `FIREBASE_PROJECT_ID` + `FIREBASE_SERVICE_ACCOUNT` para Edge Function notify-driver
- **Deploy notify-driver** — `supabase functions deploy notify-driver`
- **saveTokenForDriver call** — chamar após login do driver (ex: DriverStore)
- **MBWay real** — integração com banco real (atual é simulada)
- **Partner demo account** — sem conta demo para role partner
- **Admin access control** — email allowlist deve ser substituído por RLS/role real
- **ChatStore / FavoriteStore** — stores existem mas em desenvolvimento

#### 🔴 Maiores Riscos para Lançamento (atualizado 2026-04-15)

1. **Auth/session persistence** — edge cases de sessão não totalmente resolvidos. **Ação:** testar fluxo completo com dados reais antes do lançamento.
2. **Push Notifications** — código pronto, aguarda `google-services.json` + `GoogleService-Info.plist` + secrets Firebase no Supabase.

#### 🆕 Ficheiros adicionados nesta sessão (Fase 2 — Carroçaria)
- `lib/config/app_theme.dart` — ThemeData centralizado com marca Bora
- `lib/screens/admin/admin_orders_screen.dart`
- `lib/screens/admin/admin_drivers_screen.dart`
- `lib/screens/admin/admin_partners_screen.dart`
- `supabase/migrations/20260415000000_seed_restaurants.sql`

#### 🆕 Alterações desta sessão (Fase 4 — Dados Reais + Saco)
- `lib/screens/restaurant_menu_screen.dart` — reescrito com secções por categoria + imagens
- `lib/services/pricing_service.dart` — `bagFee` em `OrderPricingBreakdown`, `_restaurantBagFee = 0.30`
- `lib/screens/cart_screen.dart` — linha "Saco para viagem" quando `bagFee > 0`
- `lib/models/order_model.dart` — campo `bagCount` (mutable int, default 0)
- `lib/stores/order_store.dart` — método público `updateBagCount(orderId, count)`
- `lib/screens/driver_home_screen.dart` — `_showBagCountDialog` para pedidos storeShopping
- `supabase/migrations/add_bag_count_to_orders` — `bag_count INTEGER DEFAULT 0` em orders

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
