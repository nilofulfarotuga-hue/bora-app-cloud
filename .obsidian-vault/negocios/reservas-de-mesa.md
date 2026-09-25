# Reservas de Mesa — Bora App

## Modelo de Negócio
- Pré-pagamento: **€3,00** no ato da reserva
  - €1,00 → Bora
  - €2,00 → Restaurante
- Cancelamento com reembolso total até **4h antes** da reserva

## Status Flow
```
reservation_requested
  → restaurant_responding
    → accepted
    → suggested_alternative
    → rejected
      → confirmed
        → customer_arrived
          → completed
          → no_show
```

## Regras Operacionais
- Só disponível em restaurantes parceiros
- Restaurante pode sugerir alternativa (horário/mesa diferente)
- `no_show` → sem reembolso (cliente não apareceu)
- Timeline de reservas do dia visível no painel do parceiro

## Estado Atual
- ❌ Não implementado — zero migrations `reservations` no código
- `restaurant_menu_screen.dart` existe mas renderiza produtos estáticos
- Sem fluxo de reserva, sem pré-pagamento €3, sem status `customer_arrived`
- Previsto para **Lote 3** do plano de lançamento
