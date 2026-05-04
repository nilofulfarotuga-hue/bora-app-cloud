---
prioridade: ALTA 🟠
ficheiro: lib/screens/order_details_screen.dart, supabase/functions/client-cancel-order/
bug_id: BUG-017
---

# BUG-017 — Cancelamento pelo cliente não implementado no UI (Edge Function existe)

## Descrição
A Edge Function `client-cancel-order` existe no Supabase mas o fluxo no UI do cliente não está implementado. Clientes não conseguem cancelar pedidos depois de submetidos.

## Situação Actual
- Edge Function: ✅ Existe (`supabase/functions/client-cancel-order/`)
- UI para cancelar: ❌ Não implementado
- Regras de cancelamento definidas: ❌ Não definidas no código

## Impacto para o Cliente
- Cliente fica preso num pedido que não quer
- Tem de contactar suporte manualmente
- Má experiência de utilizador, especialmente se o driver ainda não aceitou

## Regras de Negócio a Definir
1. Cancelamento **gratuito** → antes do restaurante confirmar (status: `created`)
2. Cancelamento **com taxa** → depois de confirmar, antes de pickup (status: `preparing`)
3. Cancelamento **não permitido** → depois do pickup (status: `pickedUp` ou além)

## Ficheiros a Criar/Editar
- `lib/screens/order_details_screen.dart` → adicionar botão "Cancelar Pedido"
- `lib/services/payment_service.dart` → lógica de reembolso parcial se taxa aplicável
- `supabase/functions/client-cancel-order/` → completar lógica de cancelamento

## Acções Imediatas
- [ ] Definir as regras exactas de cancelamento com Danilo
- [ ] Adicionar botão cancelar no `order_details_screen.dart` (só visível em `created` e `preparing`)
- [ ] Implementar lógica na Edge Function
