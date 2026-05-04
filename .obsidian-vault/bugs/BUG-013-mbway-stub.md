---
prioridade: CRÍTICA 🔴
ficheiro: lib/services/payment_service.dart
bug_id: BUG-013
---

# BUG-013 — MBWay é um stub falso (não processa pagamentos reais)

## Descrição
O método `payWithMBWay()` no `payment_service.dart` não processa nenhum pagamento real. Simula sucesso após 300ms de delay artificial.

## Localização
**Ficheiro:** `bora_app/lib/services/payment_service.dart`

```dart
Future<bool> payWithMBWay() async {
  await Future.delayed(Duration(milliseconds: 300));
  return true; // Sempre devolve sucesso — STUB!
}
```

A Edge Function `confirm-mbway-payment` existe no Supabase mas também não está completamente implementada.

## Impacto
- Clientes que escolham MBWay como método de pagamento pensam que pagaram, mas não pagaram nada
- Pedidos ficam marcados como pagos sem pagamento real
- Risco financeiro grave em produção

## Solução Proposta
1. Implementar integração real com API MBWay (via SIBS ou EuPago)
2. Completar a Edge Function `confirm-mbway-payment`
3. Até estar implementado, **remover MBWay como opção de pagamento** no UI para clientes
4. Adicionar flag `MBWAY_ENABLED = false` nas business rules

## Acções Imediatas
- [ ] Esconder botão MBWay no `payment_method_screen.dart`
- [ ] Investigar qual provider usar: SIBS/Multibanco vs EuPago vs Ifthenpay
