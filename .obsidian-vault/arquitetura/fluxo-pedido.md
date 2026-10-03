# Fluxo de Pedido — Bora App

> Mapeamento completo do ciclo de vida de um pedido, do cliente ao driver.

---

## Estados de um Pedido (OrderStatus)

```
created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
                                                                            ↘ cancelled
                                                                            ↘ rejected
```

### Descrição de cada estado

| Estado | Quem actua | O que acontece |
|--------|-----------|----------------|
| `created` | Cliente | Pedido submetido, aguarda confirmação do parceiro |
| `preparing` | Parceiro | Restaurante/loja aceita e começa a preparar |
| `callingDriver` | Sistema | Dispatch Engine começa a procurar driver disponível |
| `driverAccepted` | Driver | Driver aceitou a entrega, a caminho do parceiro |
| `pickedUp` | Driver | Driver recolheu o pedido |
| `onTheWay` | Driver | Driver a caminho do cliente |
| `delivered` | Driver | Entrega concluída, trigger para avaliação |
| `cancelled` | Cliente/Admin | Pedido cancelado (lógica de reembolso activada) |
| `rejected` | Parceiro | Parceiro recusou o pedido |

---

## Tipos de Pedido (OrderType)

### 1. `partnerRestaurant` — Restaurante parceiro
```
Cliente escolhe restaurante → adiciona produtos ao carrinho → checkout
→ Pagamento processado (Stripe/MBWay/Cash)
→ Notificação ao parceiro
→ Parceiro confirma (status: preparing)
→ Dispatch Engine procura driver
→ Driver entrega
→ Valor fixo, sem reconciliação
```

### 2. `nonPartnerPurchase` — Compra em loja não-parceira
```
Cliente descreve o que quer + valor estimado
→ Pré-autorização: valor_estimado × 1.15 (buffer 15%)
→ Driver aceita e vai às compras
→ Driver confirma o valor_real_compra
→ Sistema calcula diferença:
   - valor_real < valor_estimado → Edge Fn `refund` (reembolso)
   - valor_real > valor_estimado → Edge Fn `charge-extra` (cobrança)
→ Driver entrega
```

### 3. `sendPackage` — Envio de pacote
```
Cliente especifica origem + destino + descrição
→ Preço calculado por distância (pricing_service.dart)
→ Driver aceita → recolhe → entrega
→ Sem parceiro envolvido
```

### 4. `carryGroceries` — Carregar compras
```
Cliente escolhe supermercado + hora desejada
→ Driver encontra-se com cliente no supermercado
→ Ajuda a carregar + leva até casa
→ Preço por hora/serviço
```

---

## Fluxo de Pagamento Detalhado

```
CLIENTE
  │
  ├─ Stripe Card ──→ create-payment-intent (Edge Fn)
  │                  → Stripe confirma
  │                  → stripe-webhook (Edge Fn) actualiza DB
  │
  ├─ MBWay ────────→ confirm-mbway-payment (Edge Fn) ⚠️ STUB
  │
  └─ Cash ─────────→ Sem processamento online; driver marca como pago

RECONCILIAÇÃO (só nonPartnerPurchase)
  │
  ├─ Reembolso ────→ refund (Edge Fn) → Stripe refund API
  └─ Extra ────────→ charge-extra (Edge Fn) → Stripe charge API
```

---

## Fluxo do Dispatch Engine

```
Estado muda para `callingDriver`
  │
  ↓
dispatch-engine (Edge Fn / lib/dispatch/)
  │
  ├─ Filtra drivers: disponíveis + dentro do raio
  ├─ Ordena por: distância + capacidade + rating
  ├─ Envia notificação ao 1º driver (notify-driver Edge Fn)
  │
  ├─ Driver aceita → status: driverAccepted, atribui driver_id
  └─ Driver recusa/timeout → tenta próximo driver
                           → max 3 tentativas → alerta admin
```

---

## Ficheiros Principais por Fase

| Fase | Ficheiros Flutter | Edge Functions |
|------|------------------|----------------|
| Checkout | `cart_screen.dart`, `payment_method_screen.dart` | `create-payment-intent` |
| Confirmação | `partner_dashboard_screen.dart` | — |
| Dispatch | `dispatch_engine.dart`, `driver_assignment_service.dart` | `dispatch-engine`, `notify-driver` |
| Tracking | `order_tracking_screen.dart`, `driver_store.dart` | — |
| Entrega | `driver_home_screen.dart` | `refund`, `charge-extra` |
| Avaliação | `rating_screen.dart` | — |
