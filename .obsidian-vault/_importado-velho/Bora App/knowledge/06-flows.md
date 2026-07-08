# 06 — Fluxos

## Ciclo de vida do pedido (`OrderStatus`)
```
created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered
                ↘ rejected
```
- **NUNCA** usar String para status — sempre o enum `OrderStatus`.
- Toda a transição escreve **primeiro na DB** (`_updateOrderStatusInDatabase`) e só
  depois muta estado local. `_advanceStatus` compara por **ID** (não por referência),
  porque o Realtime substitui o objeto em `_orders` por uma nova instância.

## Dispatch (server-side — Edge Fn `dispatch-engine`)
- Fonte de verdade: `current_driver_offer_id` na `orders`.
- Stacking até 3 pedidos · FIFO ≤200 m · offer timeout `dispatch_offer_timeout_seconds` 40s.
- Total com drivers online: `dispatch_max_total_seconds_with_drivers_online` 1200s ·
  retry sem driver 10s · auto-cancel safety 1800s.
- `DriverCapacityService` decide elegibilidade: logística não pode stacked; parceiro máx 2
  (mesmo vendor ou ≤800m); não-parceiro máx 3 (mesmo vendor).
- O `DispatchEngine` Flutter é NO-OP (desativado) — ver [10](10-protected-zones.md).

## Parceiro aceitar/rejeitar
- Pedido parceiro: `restaurantAcceptOrder → restaurantMarkReady → callingDriver`.
- Não-parceiro: salta direto para `preparing → callingDriver` após delay simulado.
- Push ao parceiro via Edge Fn `notify-partner` (fire-and-forget após createOrder).
- CTA "Aceitar pedido" do parceiro = **verde** (confirmado Fase 4.3).

## Takeaway Pro
- `takeaway_enabled` no restaurante + `takeaway_default_prep_minutes` (default 20).
- Campos na order: `takeaway_ready_at`, `takeaway_prep_minutes`, `takeaway_pickup_code`,
  `takeaway_is_curbside` + `takeaway_curbside_info` (curbside opcional).

## Reservas
- `reservations_enabled` no restaurante. Prépagamento €3 via
  `create-reservation-payment-intent` (ou `create-mbway-reservation-payment-intent`).
- Estados em `reservations.status` (pending → ...). Lembretes 24h/2h. Walk-in suportado.

## storeShopping V2 (não-parceiro)
- `OrderServiceType.storeShopping` com `purchase_flow_version=2`.
- Estafeta compra fisicamente; tabelas auxiliares: `order_purchase_items_v2`,
  `order_receipts_v2`. Reconciliação via wallet + ledger.
- Debug: skill `storeshopping-v2-debugger` (cruza orders + items + receipts + wallet + audit).

## Pagamentos
- `card` → Stripe via Edge Fn `create-payment-intent` (verify_jwt=false, valida amount ±5% vs `payment_buffer_total`).
- `mbway` → `create-mbway-payment-intent` (LIVE) → push MB WAY → webhook `stripe-webhook` (payment_intent.succeeded) → paid + dispatch.
- `cash` → local, sem backend. Limite €40.

## Fontes adicionais
- `.claude/.ai/knowledge/architecture/dispatch-engine.md` + `from-obsidian/arquitetura/fluxo-pedido.md`.
- `bora_app/CLAUDE.md` (secções Order lifecycle, DispatchEngine, Payment, Batching).
