---
prioridade: MÉDIA 🟡
ficheiro: lib/services/payment_service.dart, supabase/functions/charge-extra/
bug_id: BUG-015
---

# BUG-015 — Sistema de buffer/reconciliação de pagamento não testado em produção

## Descrição
Para pedidos `nonPartnerPurchase`, o sistema pré-autoriza +15% do valor estimado e depois calcula a diferença (reembolso ou cobrança extra). Esta lógica é complexa e não há evidência de testes end-to-end.

## Fluxo Afectado
```
Cliente faz pedido → pré-autoriza valor_estimado × 1.15
Driver confirma valor_real_compra
Sistema calcula: diferença = valor_real - valor_estimado
  Se diferença < 0 → Edge Function `refund` (reembolso ao cliente)
  Se diferença > 0 → Edge Function `charge-extra` (cobrança extra)
```

## Casos de Risco
1. **Driver demora muito a confirmar** → PaymentIntent expira (Stripe tem limite de 7 dias para pre-auth)
2. **Cobrança extra falha** → Driver já entregou mas o cliente não é cobrado pelo excedente
3. **Reembolso falha** → Cliente foi cobrado a mais e não recebe de volta
4. **Valor real = 0** → Edge case não tratado (driver não encontrou os produtos)
5. **Cancelamento após confirmação do driver** → Estado de pagamento indeterminado

## Ficheiros Envolvidos
- `lib/services/payment_service.dart`
- `supabase/functions/charge-extra/`
- `supabase/functions/refund/`
- `lib/screens/driver_home_screen.dart` (onde driver confirma valor)

## Solução Proposta
1. Criar testes de integração para os 5 casos de risco acima
2. Adicionar logging detalhado nas Edge Functions para rastrear cada passo
3. Dashboard admin deve mostrar pedidos em estado `paymentPending` ou `extraRequired` > 1h (alerta)
4. Implementar timeout handler: se o driver não confirma em X horas → cancelar automaticamente

## Acções Imediatas
- [ ] Testar fluxo completo com cartão Stripe de teste em sandbox
- [ ] Verificar se a Edge Function `charge-extra` tem tratamento de erro adequado
