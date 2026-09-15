# Pagamentos — Bora App

## Métodos Aceites
- **Cartão** (Stripe) — mobile only, requer `BACKEND_BASE_URL`
- **MBWay** — simulado (sem integração real com banco)
- **Dinheiro** — funcional, cap €40 server-enforced via trigger

## Stripe
- Edge Function `create-payment-intent` — cria PaymentIntent, re-valida contra DB
- Edge Function `stripe-webhook` — recebe eventos, atualiza `payment_status`
- **⚠️ Atenção:** `BACKEND_BASE_URL` defaultValue é `localhost:3000` — configurar em produção!
- Buffer de 15% pré-autorizado em pedidos não-parceiro

### Aviso obrigatório ao cliente (não-parceiro, cartão):
> "Reservámos no teu cartão 15% a mais do valor estimado, por segurança. Pagas apenas o valor real — o extra é libertado do teu cartão."

## MBWay
- Edge Function `confirm-mbway-payment` — simulada
- **Por implementar:** integração real com banco

## Dinheiro
- Cap €40/pedido (validação Flutter + trigger DB)
- Settlement automático via trigger `apply_driver_cash_settlement`
- `driver_balances` atualizado quando pedido cash é entregue

## Payout Drivers
- Automático toda segunda-feira às 3h (`bora_weekly_auto_payout`)
- Mínimo €10 para processar (abaixo acumula)

## Status de Pagamento (enum `PaymentStatus`)
`pending` → `authorized` → `captured` → `refunded` / `extraCharged` / `failed`
