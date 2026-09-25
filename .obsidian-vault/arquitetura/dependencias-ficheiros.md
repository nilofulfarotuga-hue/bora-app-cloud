# Dependências entre Ficheiros — Bora App

> Mapa de quem usa quem. Útil para perceber o impacto de mudanças.

---

## Camadas da Arquitectura

```
┌─────────────────────────────────────────┐
│              SCREENS (UI)               │  44 ecrãs
├─────────────────────────────────────────┤
│              STORES (State)             │  9 stores (Provider)
├─────────────────────────────────────────┤
│             SERVICES (Logic)            │  20 serviços
├─────────────────────────────────────────┤
│              MODELS (Data)              │  12 modelos
├─────────────────────────────────────────┤
│         SUPABASE / FIREBASE / STRIPE    │  Backend externo
└─────────────────────────────────────────┘
```

---

## Stores e quem as usa

### `cart_store.dart`
- Usado por: `cart_screen.dart`, `product_detail_screen.dart`, `store_products_screen.dart`
- Depende de: `cart_item.dart` (model), `partner_product.dart` (model)

### `order_store.dart`
- Usado por: `orders_screen.dart`, `order_details_screen.dart`, `order_tracking_screen.dart`, `admin_orders_screen.dart`
- Depende de: `order_model.dart`, `payment_service.dart`

### `driver_store.dart`
- Usado por: `driver_home_screen.dart`, `driver_map_screen.dart`, `admin_drivers_screen.dart`
- Depende de: `driver_model.dart`, `driver_location_service.dart`, `dispatch_engine.dart`

### `session_store.dart`
- Usado por: `main.dart` (root navigator)
- Depende de: `auth_store.dart`

### `auth_store.dart`
- Usado por: `session_store.dart`, praticamente todos os ecrãs que precisam de saber quem está logado
- Depende de: Supabase Auth SDK

### `restaurant_store.dart`
- Usado por: `restaurants_screen.dart`, `restaurant_menu_screen.dart`
- Depende de: `restaurant_model.dart`

### `partner_product_store.dart`
- Usado por: `partner_products_screen.dart`, `add_product_screen.dart`
- Depende de: `partner_product.dart` (model)

### `chat_store.dart`
- Usado por: `chat_screen.dart`
- Depende de: `chat_message.dart` (model), `message_model.dart`

### `favorite_store.dart`
- Usado por: (UI não totalmente ligado ainda — ver ideias/ux-cliente.md)
- Depende de: Supabase tabela `favorites`

### `consent_store.dart`
- Usado por: `main.dart` (ConsentBanner wrapper)
- Depende de: SharedPreferences

---

## Serviços e quem os usa

### `payment_service.dart` ← CENTRAL
- Usado por: `payment_method_screen.dart`, `order_store.dart`
- Chama: Edge Fn `create-payment-intent`, `charge-extra`, `refund`, `confirm-mbway-payment`
- Dependências externas: Stripe SDK, Supabase

### `dispatch_engine.dart` ← CENTRAL
- Usado por: `driver_assignment_service.dart`
- Chama: Edge Fn `dispatch-engine`, `notify-driver`
- Dependências: `driver_capacity_service.dart`, `driver_store.dart`

### `driver_location_service.dart`
- Usado por: `driver_store.dart`, `driver_map_screen.dart`
- ⚠️ Possível conflito com `driver_store.dart` (BUG-016)

### `pricing_service.dart`
- Usado por: `cart_screen.dart`, `send_package_form_screen.dart`
- Calcula: taxas de entrega baseadas em distância

### `directions_service.dart` (multi-plataforma)
- Versões: `directions_service_io.dart` (mobile), `directions_service_web.dart` (web), `directions_service_stub.dart`
- Usado por: `order_tracking_screen.dart`, `driver_map_screen.dart`
- Chama: Google Directions API

### `notification_service.dart`
- Usado por: `main.dart`, `driver_home_screen.dart`
- Chama: Firebase FCM
- ⚠️ BUG-003: notificações push desactivadas

### `auth_service.dart`
- Usado por: `auth_store.dart`
- Chama: Supabase Auth

---

## Ficheiros de Configuração (lib/config/)

| Ficheiro | Conteúdo | Usado por |
|----------|----------|-----------|
| `colors.dart` | Paleta de cores da Bora | Todos os ecrãs |
| `spacing.dart` | Constantes de espaçamento | Todos os ecrãs |
| `theme.dart` | ThemeData do Flutter | `main.dart` |
| `business_rules.dart` | Regras: raio, taxas, buffers | `pricing_service.dart`, `dispatch_engine.dart` |
| `maps_config.dart` | API keys Google Maps | `maps_service.dart`, `google_places_service.dart` |

---

## Ficheiros com Maior Impacto (mexer com cuidado)

1. **`main.dart`** — inicialização de tudo, mudanças aqui afectam toda a app
2. **`auth_store.dart`** — todos dependem desta store para saber o utilizador actual
3. **`order_model.dart`** — o modelo central; mudanças quebram muitos ecrãs
4. **`payment_service.dart`** — toca em dinheiro real; requer testes antes de mudar
5. **`dispatch_engine.dart`** — algoritmo central de atribuição; bugs aqui = drivers sem pedidos
6. **`business_rules.dart`** — altera taxas e comportamentos em toda a app (e deve estar em sync com `_shared/business_rules.ts`)
