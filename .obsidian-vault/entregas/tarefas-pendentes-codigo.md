# Tarefas Pendentes Descobertas no Código

> Lista de TODOs e features incompletas encontradas durante análise nocturna de 24 Abril 2026.

---

## 🔴 CRÍTICO — Bloqueia Lançamento

### 1. Stripe live mode
- **O quê:** Trocar `pk_test_` por `pk_live_` antes de lançar
- **Ficheiro:** `lib/main.dart` + Edge Fns `create-payment-intent`, `stripe-webhook`
- **Esforço:** 2-4 horas (obter chaves live do dashboard Stripe)
- **Detalhe:** BUG-014

### 2. MBWay — remover ou implementar
- **O quê:** O MBWay aparece no UI mas não processa pagamentos reais
- **Decisão:** Ou esconder o botão MBWay até implementar, ou implementar integração real
- **Ficheiro:** `lib/screens/payment_method_screen.dart`, `lib/services/payment_service.dart`
- **Esforço:** Esconder botão = 30 min | Implementar real = 2-3 semanas
- **Detalhe:** BUG-013

### 3. Push notifications em produção
- **O quê:** Notificações Firebase/FCM desactivadas ou com bug (BUG-003 já documentado)
- **Impacto:** Drivers e clientes não recebem alertas de novos pedidos
- **Ficheiro:** `lib/services/notification_service.dart`
- **Esforço:** 1-2 dias

---

## 🟠 ALTA PRIORIDADE — Deve estar no lançamento

### 4. Cancelamento de pedido pelo cliente
- **O quê:** UI para cancelar pedido não implementado (Edge Fn existe)
- **Ficheiro:** `lib/screens/order_details_screen.dart` + `supabase/functions/client-cancel-order/`
- **Esforço:** 1-2 dias (inclui definir regras de negócio de cancelamento)
- **Detalhe:** BUG-017

### 5. Ratings com persistência no Supabase
- **O quê:** Avaliações dos clientes não são guardadas na base de dados
- **Ficheiro:** criar `lib/services/rating_service.dart` + verificar/criar tabela no Supabase
- **Esforço:** 1 dia
- **Detalhe:** BUG-018

### 6. Fluxo de driver — completar
- **O quê:** `driver_home_screen.dart` tem o fluxo incompleto (BUG-010)
- **Esforço:** 2-3 dias (inclui testes com driver real)

### 7. Google Pay / Apple Pay
- **O quê:** Stripe suporta nativamente, reduz abandono no checkout
- **Ficheiro:** `lib/screens/payment_method_screen.dart`, `lib/services/payment_service.dart`
- **Esforço:** 1-2 dias
- **Detalhe:** ver ideias/ux-cliente.md

---

## 🟡 MÉDIA PRIORIDADE — Pós-lançamento imediato

### 8. Tags de avaliação
- **O quê:** Adicionar "Rápido", "Simpático", "Pontual" ao ecrã de rating
- **Ficheiro:** `lib/screens/rating_screen.dart`, `lib/models/rating_model.dart`
- **Esforço:** 4-6 horas

### 9. Foto do driver no tracking
- **O quê:** `driver_model.dart` já tem campo de foto, só falta ligar ao `order_tracking_screen.dart`
- **Esforço:** 2-4 horas

### 10. "Pedir de novo" na home do cliente
- **O quê:** Secção com os últimos restaurantes/lojas do utilizador
- **Ficheiro:** `lib/screens/client_home_screen.dart`
- **Esforço:** 1 dia

### 11. Tempo estimado de entrega na lista de restaurantes
- **O quê:** Mostrar "~20 min" antes de o cliente entrar no restaurante
- **Ficheiro:** `lib/screens/restaurants_screen.dart`
- **Esforço:** 4-6 horas (precisa de calcular distância cliente-restaurante)

### 12. Consolidar dual GPS stream do driver
- **O quê:** Dois streams de GPS a conflituar em `driver_location_service.dart`
- **Esforço:** 1 dia (análise + fix + testes)
- **Detalhe:** BUG-016

### 13. Logging nas Edge Functions de pagamento
- **O quê:** `charge-extra` e `refund` não têm logging adequado para debugging
- **Esforço:** 4 horas

---

## 🔵 BAIXA PRIORIDADE — Backlog

### 14. Toggle on/off por produto (parceiro)
- **O quê:** Activar/desactivar produto sem entrar no ecrã de edição
- **Ficheiro:** `lib/screens/partner_products_screen.dart`
- **Esforço:** 4 horas

### 15. Gráfico de pedidos por hora (parceiro dashboard)
- **O quê:** `fl_chart` já está na dependência, aproveitar
- **Ficheiro:** `lib/screens/partner_dashboard_screen.dart`
- **Esforço:** 1 dia

### 16. Dark mode
- **O quê:** Suporte ao dark mode do sistema operativo
- **Ficheiro:** `lib/config/theme.dart`
- **Esforço:** 1-2 dias (verificar contraste em todos os ecrãs)

### 17. Extracto financeiro mensal (parceiro)
- **O quê:** Listagem de pedidos com comissões deduzidas
- **Esforço:** 2-3 dias

### 18. Renomear firebase-service-account.json.json
- **O quê:** Ficheiro no backend tem dupla extensão `.json.json` — possível erro
- **Ficheiro:** `backend/firebase-service-account.json.json`
- **Esforço:** 10 minutos (verificar se está referenciado noutro lado antes de renomear)

---

## Resumo por Esforço

| Prioridade | Total | Estimativa |
|-----------|-------|-----------|
| 🔴 Crítico | 3 tarefas | ~1 semana |
| 🟠 Alta | 4 tarefas | ~1 semana |
| 🟡 Média | 6 tarefas | ~1,5 semanas |
| 🔵 Baixa | 5 tarefas | ~1 semana |
| **Total** | **18 tarefas** | **~4,5 semanas** |
