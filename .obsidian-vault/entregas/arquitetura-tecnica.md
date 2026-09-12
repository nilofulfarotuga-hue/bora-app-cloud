# Arquitetura Técnica — Bora App

## Stack
- **Frontend:** Flutter (Dart) — mobile + web
- **Backend:** Supabase (PostgreSQL + Auth + Realtime + Edge Functions/Deno)
- **Pagamentos:** Stripe (`flutter_stripe`)
- **Mapas:** Google Maps (`google_maps_flutter` + `latlong2`)
- **State:** Provider
- **Sessão local:** SharedPreferences

## Estrutura de Pastas
```
bora_app/
├── lib/
│   ├── auth/          # AuthStore
│   ├── config/        # business_rules.dart, maps_config.dart
│   ├── dispatch/      # dispatch_engine.dart (noop), driver_capacity_service.dart
│   ├── models/        # OrderModel, DriverModel, RestaurantModel...
│   ├── screens/       # ecrãs por role
│   ├── services/      # payment_service, pricing_service, place_autocomplete...
│   ├── stores/        # order_store, cart_store, driver_store, session_store...
│   └── utils/         # map_utils.dart
├── supabase/
│   ├── functions/     # Edge Functions (TS/Deno)
│   └── migrations/    # 10+ migrations SQL
```

## Edge Functions Ativas

| Função | Estado |
|---|---|
| `dispatch-engine` | Ativo — seleciona driver, retry 42s, anti-duplicação |
| `create-payment-intent` | Ativo — cria Stripe PaymentIntent |
| `stripe-webhook` | Ativo — recebe eventos Stripe |
| `confirm-mbway-payment` | Ativo (simulado) |

## Fluxo de Pedido Completo

```
Cliente → seleciona loja → carrinho → morada → pagamento → pedido criado
Backend → dispatch engine → seleciona driver → oferta 10s
Driver → aceita → driverAccepted → pickedUp → onTheWay → delivered (código 4 dígitos)
Pós-entrega → tokens automáticos + cash settlement
```

## Status Flow
```
created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
       ↘ rejected
```

## Regra de Navegação
- Toda a navegação é `_RootNavigator` em `main.dart` (widget-rebuild)
- Sem `Navigator.push` para screens principais
- Trocar role ou auth = rebuild automático

## Contas Demo
- Cliente: `cliente@bora.app` / `123456`
- Driver: phone `910000000` / `123456`
- Parceiro: sem conta demo (requer registo)
