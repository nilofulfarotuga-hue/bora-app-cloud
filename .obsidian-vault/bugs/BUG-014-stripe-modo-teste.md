---
prioridade: CRÍTICA 🔴
ficheiro: lib/main.dart
bug_id: BUG-014
---

# BUG-014 — Stripe em modo de teste (pk_test_) em produção

## Descrição
A chave publicável do Stripe usada é `pk_test_51T8MG0...` — modo de teste. Em produção, os clientes reais não conseguem pagar com cartões reais.

## Localização
**Ficheiro:** `bora_app/lib/main.dart`

```dart
Stripe.publishableKey = 'pk_test_51T8MG0GmiUUEIr722bf8...';
```

## Impacto
- Pagamentos com cartão real **falham silenciosamente** em produção
- Os clientes não conseguem completar pedidos pagos por cartão
- Risco de lançamento com zero pagamentos reais a funcionar

## Solução Proposta
1. Criar conta Stripe live (modo produção)
2. Obter `pk_live_` e `sk_live_` do dashboard Stripe
3. Usar `--dart-define=STRIPE_KEY=pk_live_xxx` no build de produção
4. Actualizar as Edge Functions `create-payment-intent` e `stripe-webhook` com a chave secreta live
5. Testar com um pagamento real de 0.50€ antes do lançamento

## Acções Imediatas
- [ ] Verificar no dashboard Stripe se existe conta live já activada
- [ ] Confirmar com Danilo se a conta Stripe está em "Live mode" ou ainda em "Test mode"
