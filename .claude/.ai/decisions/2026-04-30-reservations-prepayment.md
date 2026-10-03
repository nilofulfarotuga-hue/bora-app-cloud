# Reservations €3 prepayment — Decisão (T6.1)

> 2026-04-30 · Decisão: deferir charge real para pós-launch.

## Contexto
BR §14.5 prevê €3 prepayment em reserva de mesa para combater no-shows. O field `reservations.prepayment_cents` já existe e é populado pelo flow cliente em `reservation_flow_screen.dart`. **Mas nenhum Stripe charge dispara.** O valor é registado e ignorado.

## Opções avaliadas

### A) Implementar charge real agora
- Nova Edge Function `reservation-prepayment` (paymentIntent €3, confirm immediate)
- Refund automático se restaurante rejeita ou no-show negativo
- Webhook handling para captura/refund
- Risco: HIGH — Stripe LIVE, lógica nova, pouco coberta por smoke tests

### B) Remover field + texto UI
- Limpa expectativa errada
- Perde-se a infra preparada
- Cliente percebe reserva como gratuita; ao adicionar prepayment depois, alguns vão revoltar-se

### C) Deferir charge mas manter field (escolhida)
- Reservas continuam grátis até launch
- Field `prepayment_cents` mantém-se a 300 (já está em DB)
- Quando launchar charge, basta adicionar Edge Function + UI dialog
- Comentário em `reservation_flow_screen.dart:100` aponta para este doc

## Critério para wirear (pós-launch)
- ≥10 no-shows confirmados em prod
- Decisão Danilo de cobrar
- Sprint dedicada (mínimo 2h) para Edge Fn + smoke + UI

## Acção tomada nesta sessão
- TODO comment substituído por referência clara
- Decisão documentada
- Field continua populado (ledger ready)
