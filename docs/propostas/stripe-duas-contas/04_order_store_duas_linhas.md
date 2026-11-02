# PROPOSTA 4 — `lib/stores/order_store.dart` (zona vermelha: a tranca não deixa esta sessão editar)

Missão `stripe-empresa-2026-11-01` (autorização do Danilo 01/11/2026 22:03). São **duas linhas**,
nenhuma toca em preços, taxas ou no `finalizePurchase`. Aplicar na sessão com o Danilo (ou pela
Claude.ai) antes de publicar a app.

## 1. `startCardPaymentDraft` (~linha 659) — a app diz ao servidor que sabe lidar com duas contas

```dart
// antes
        body: {'cart_input': cartInput},
// depois
        body: {'cart_input': cartInput, 'stripe_contas_v2': true}, // duas contas Stripe (02/11/2026)
```

Sem isto, o `create-payment-intent` trata a app como antiga e cria o pagamento na conta PESSOAL
(continua a funcionar; só não muda de conta).

## 2. `processExtraCharge` (~linha 2012) — o extra sai na conta onde o pedido foi pago

```dart
// antes
      await _paymentService.chargeExtra(amount: amount);
// depois
      await _paymentService.chargeExtra(amount: amount, orderId: order.id); // duas contas
```

`PaymentService.chargeExtra` já aceita `orderId` (editado nesta missão) e o `charge-extra` v22
(proposta) usa a conta gravada no pedido.

## Prova depois de aplicar
`grep -n "stripe_contas_v2\|orderId: order.id" lib/stores/order_store.dart` → 2 linhas.
