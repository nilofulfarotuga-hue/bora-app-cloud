---
prioridade: ALTA 🟠
ficheiro: lib/screens/rating_screen.dart, lib/models/rating_model.dart
bug_id: BUG-018
---

# BUG-018 — Sistema de ratings não persiste no Supabase

## Descrição
O `rating_screen.dart` e `rating_model.dart` existem mas as avaliações não são guardadas na base de dados Supabase. O modelo existe localmente mas sem serviço de persistência.

## Situação Actual
- `rating_model.dart`: ✅ Modelo definido
- `rating_screen.dart`: ✅ UI existe
- Serviço de gravação no Supabase: ❌ Não implementado
- Tabela `ratings` no Supabase: ❓ A verificar

## Impacto
- As avaliações dos clientes sobre restaurantes e drivers desaparecem
- O dashboard admin (`admin_ratings_screen.dart`) não tem dados para mostrar
- Parceiros não recebem feedback dos clientes
- Drivers não têm histórico de avaliações

## Solução Proposta
1. Criar/verificar tabela `ratings` no Supabase com colunas: `order_id`, `client_id`, `driver_id`, `partner_id`, `stars_driver`, `stars_partner`, `comment`, `tags`, `created_at`
2. Criar `rating_service.dart` com método `submitRating(RatingModel rating)`
3. Chamar o serviço no `rating_screen.dart` após o cliente submeter
4. Actualizar `admin_ratings_screen.dart` para ler da tabela real

## Acções Imediatas
- [ ] Verificar se a tabela `ratings` existe no Supabase
- [ ] Criar `lib/services/rating_service.dart`
- [ ] Ligar o botão "Submeter" do `rating_screen.dart` ao serviço
