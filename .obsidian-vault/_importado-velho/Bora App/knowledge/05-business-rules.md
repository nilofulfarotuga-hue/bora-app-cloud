# 05 — Regras de Negócio

> Valores canónicos vivem em `platform_settings` (runtime, ver [09](09-platform-settings.md)).
> Cálculo no código passa SEMPRE por `PricingService.calculateBreakdown(...)`.
> **Nunca calcular fees à mão num ecrã.** Mercados são SEMPRE não-parceiros.

## Parceiro vs Não-parceiro
- **Restaurantes**: podem ser **parceiro** (modelo 10+5+5%) ou **não-parceiro** (preço base + 15% markup).
- **Mercados / Lojas / Farmácias scraped**: SEMPRE **não-parceiro** (`is_partner=false`, `user_=NULL`),
  markup 15% aplicado em runtime por `pricing_calculate`. Preço guardado é sempre **puro**.

## Comissão parceiro 10+5+5% (Batch D ✅)
- **10%** `partner_visible_commission_pct` (0.10) → `partner_commission_visible` — parceiro paga no settlement.
- **5%** `partner_hidden_markup_pct` (0.05) → `partner_markup_hidden` — embutido no preço (cliente não vê).
- **5%** `client_service_fee_pct` (0.05) → `partner_service_fee_client` / `service_fee` — taxa visível no recibo do cliente.
- Não-parceiro: `non_partner_markup_pct` = 0.15 (15%).

## Entrega (cliente paga)
- Base: `delivery_base_fee_cents` 250 (€2.50) até `delivery_base_distance_km` 4 km.
- Por km extra: `delivery_per_km_cents` 50 (€0.50/km).
- Apartamento: surcharge total 150c (€1.50) = 100c driver + 50c plataforma (`apartment_*`).

## Estafeta (driver earnings)
- Base: `driver_base_fee_cents` 380 (€3.80) + `driver_per_km_cents` 20 (€0.20/km).
- Bónus: `driver_surcharge_cents` 80 (€0.80) — storeShopping / carry / send.
- Stacking parceiro: `partner_driver_stacking_bonus_cents` 300 (+€3).
- Profit share: `driver_profit_share_pct` 0.30 (30% do lucro líquido Bora, não-parceiro).
- Logística (carry/send): base `logistics_driver_base_cents` 400 + `logistics_driver_per_km_cents` 50.
- Encomenda: `package_base_fee_cents` 600 (200c plataforma).

## Cash
- Limite: `max_cash_amount_cents` 4000 (**€40**) por entrega.

## Sacos (bag fee)
- Restaurante: `bag_fee_restaurant_cents` 30 (€0.30 fixo).
- Supermercado: `bag_fee_supermarket_per_bag_cents` 10 (€0.10 por saco × `bag_count`).

## Cancelamento (fees)
- Antes de dispatch: `cancel_fee_before_dispatch_cents` 100 (€1.00).
- Depois de aceite: `cancel_fee_after_accept_cents` 250 (€2.50).
- Depois de pickup: `cancel_fee_after_pickup_ratio` 1 (100% — cliente paga tudo).

## Reservas
- Prépagamento: `reservation_prepayment_cents` 300 (**€3**) · serviço Bora 100c · payout parceiro 200c.
- Janela de cancelamento: `reservation_cancel_window_hours` 2h · no-show grace 60 min.
- Crédito expira: `reservation_credit_expiry_days` 30.
- Antecedência: min 30 min · max 60 dias. Turn times: 90/120/150 min (2/4/6+ pax).

## Tokens (bora_tokens)
- Estafeta: +40 normal / +50 parceiro. Cliente: `client_token_award_pct` 3 (3% do valor).
- Valor: `token_value_cents_x100` 50 → 100 tokens = €0.50. Máx 50% desconto por pedido.
- Trigger: `trg_award_tokens_on_delivery`. Tabela: `bora_tokens` (ver [07](07-database-key-tables.md)).

## Wallet
- Hard floor: -2000c geral · -4000c cancelamentos. Uso máx 100% por pedido. Negativo habilitado.

## Referral
- Recompensa referrer/invited: 500c cada. Primeiro pedido mínimo: `referral_min_first_order_cents` 2000 (€20). Expira 30 dias.

## Fontes adicionais
- `.claude/.ai/knowledge/business-rules/` → `pricing.md`, `commission.md`, `tokens.md`,
  `delivery.md`, `dispatch.md`, `bags.md`, `cash.md` (detalhe + histórico).
- `bora_app/.claude/.ai/business_rules.md` (consulta obrigatória do prompt-blindado-validator).
- Código: `bora_app/lib/config/business_rules.dart`, `lib/services/pricing_service.dart`.
