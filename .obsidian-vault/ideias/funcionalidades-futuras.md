# Funcionalidades Futuras — Bora App

## Serviços a Lançar

### Reservas em Restaurante (`restaurantReservation`)
- Status flow: `reservation_requested → restaurant_responding → (accepted | suggested_alternative | rejected) → confirmed → customer_arrived → completed / no_show`
- Pré-pagamento €3 no ato da reserva
- Timeline de reservas do dia no painel parceiro
- Gestão de menu em tempo real (disponibilidade por horário)

### Takeaway (`restaurantTakeaway`)
- Toggle "Ir buscar" no checkout
- Supressão da taxa de entrega €2,50
- Sem despacho de estafeta

### Limpeza Doméstica (`homeCleaning`)
- Novo tipo de prestador (empregada de limpeza)
- Agendamento de serviço com hora marcada

### Marketplace AliExpress
- Compra internacional (estilo AliExpress) com logística
- Secção separada no app

### Expansão para Outras Cidades
- Bora começa na Guarda — expansão nacional planeada pós-lançamento

### Chatbot de Suporte IA
- `ChatStore` já existe no código
- Chat por pedido entre cliente e estafeta
- Evolução para suporte automatizado com IA

---

## Features a Implementar (Backlog)

### GDPR (Bloqueador Legal — Lote 1)
- Checkbox de consentimento nos 3 ecrãs de registo
- Botão "Apagar conta" no perfil (mantém dados fiscais 10 anos)
- Banner de cookies na 1ª abertura (Aceitar / Rejeitar / Gerir)

### Cancelamento pelo Cliente (Lote 1)
- `OrderStatus.cancelled`
- Taxa: €1 antes de aceite / €2,50 a caminho / 100% após purchase
- Edge Function `client-cancel-order` com refund Stripe

### Avaliações com Etiquetas (Lote 2)
- 1-5 estrelas + chips (simpático, rápido, limpo, profissional, denúncia)
- Cliente → estafeta: pública | Estafeta → cliente: privada
- Tabela `ratings` em Supabase

### Gorjetas / Tips (Lote 2)
- UI: 1/2/3/5€ + valor personalizado
- Disponível no checkout e no ecrã de avaliação pós-entrega
- Split 80/20 (driver/Bora)
- Charge adicional Stripe se já pago por cartão

### Foto Obrigatória sendPackage / carryGroceries (Lote 2)
- `ImagePicker` nos 2 formulários
- Upload para bucket Supabase
- Coluna `package_photo_url` em `orders`
- Foto visível no card de oferta do driver

### Driver Help — "Preciso de Ajuda" (Lote 3)
- Botão no ecrã do driver durante entrega
- Custo: €4,00 (`DRIVER_HELP_COST_EUR`)
- Despacho de driver auxiliar
- Split €8/€4

### Push Notifications
- Ativar Firebase (requer `google-services.json`)
- Re-ativar `notification_service.dart`
- Crítico para drivers com app em background

### ChatStore / FavoriteStore
- Chat por pedido entre cliente e estafeta
- Favoritos do cliente
- Ambos em desenvolvimento
