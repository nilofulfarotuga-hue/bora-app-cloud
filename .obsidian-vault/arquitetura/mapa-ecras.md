# Mapa de Ecrãs — Bora App

> 44 ecrãs organizados por fluxo. Útil para perceber o que existe e o que falta.

---

## Ecrãs de Entrada / Auth

| Ecrã | Ficheiro | Estado |
|------|---------|--------|
| Splash / Role selector | `role_screen.dart` | ✅ |
| Login Admin | `login_screen.dart` | ✅ |
| Login Cliente | `client_login_screen.dart` | ✅ |
| Registo Cliente | `register_client_screen.dart` | ✅ |
| Login Driver | `driver_login_screen.dart` | ✅ |
| Registo Driver | `driver_signup_screen.dart` | ✅ |
| Login Parceiro | `partner_login_screen.dart` | ✅ |
| Registo Parceiro | `register_partner_screen.dart` | ✅ |

---

## Ecrãs do Cliente

| Ecrã | Ficheiro | Estado | Notas |
|------|---------|--------|-------|
| Home principal | `client_home_screen.dart` | ✅ | Ver ideias de melhoria |
| Main (tabs) | `client_main_screen.dart` | ✅ | |
| Lista de restaurantes | `restaurants_screen.dart` | ✅ | |
| Lista de lojas | `stores_screen.dart` | ✅ | |
| Categorias | `store_categories_screen.dart` | ✅ | |
| Produtos da loja | `store_products_screen.dart` | ✅ | |
| Detalhe do produto | `product_detail_screen.dart` | ✅ | |
| Menu do restaurante | `restaurant_menu_screen.dart` | ✅ | |
| Carrinho | `cart_screen.dart` | ✅ | |
| Método de pagamento | `payment_method_screen.dart` | ✅ | MBWay stub |
| Os meus pedidos | `orders_screen.dart` | ✅ | |
| Detalhe do pedido | `order_details_screen.dart` | ✅ | ⚠️ Sem botão cancelar |
| Tracking do pedido | `order_tracking_screen.dart` | ✅ | |
| Avaliação | `rating_screen.dart` | ✅ | ⚠️ Sem persistência Supabase |
| Perfil | `profile_screen.dart` | ✅ | |
| Suporte | `support_screen.dart` | ✅ | |
| Chat | `chat_screen.dart` | ✅ | |
| Mapa | `map_screen.dart` | ✅ | |
| Enviar pacote | `send_package_screen.dart` + `send_package_form_screen.dart` | ✅ | |
| Carregar compras | `carry_groceries_screen.dart` + `carry_groceries_form_screen.dart` | ✅ | |
| Fluxo de reserva | `reservation_flow_screen.dart` | ✅ | |

---

## Ecrãs do Driver

| Ecrã | Ficheiro | Estado | Notas |
|------|---------|--------|-------|
| Home do driver | `driver_home_screen.dart` | ⚠️ | Fluxo incompleto (BUG-010) |
| Mapa do driver | `driver_map_screen.dart` | ✅ | |
| Driver pendente | `driver_pending_screen.dart` | ✅ | |
| Driver rejeitado | `driver_rejected_screen.dart` | ✅ | |
| Ganhos do driver | `driver_earnings_screen.dart` | ✅ | |

---

## Ecrãs do Parceiro

| Ecrã | Ficheiro | Estado | Notas |
|------|---------|--------|-------|
| Entrada parceiro | `partner_entry_screen.dart` | ✅ | |
| Dashboard parceiro | `partner_dashboard_screen.dart` | ✅ | |
| Produtos | `partner_products_screen.dart` | ✅ | |
| Adicionar produto | `add_product_screen.dart` | ✅ | |
| Reservas | `partner_reservations_screen.dart` | ✅ | |
| Chamar driver | `partner_call_driver_screen.dart` | ✅ | |
| Dashboard restaurante | `restaurant_dashboard_screen.dart` | ✅ | |

---

## Ecrãs Admin

| Ecrã | Ficheiro | Estado | Notas |
|------|---------|--------|-------|
| Dashboard admin | `admin_dashboard_screen.dart` | ✅ | |
| Gestão de drivers | `admin_drivers_screen.dart` | ✅ | |
| Aprovação de drivers | `admin_driver_approval_screen.dart` | ✅ | |
| Pagamentos drivers | `admin_driver_payments_screen.dart` | ✅ | |
| Gestão de pedidos | `admin_orders_screen.dart` | ✅ | |
| Gestão de parceiros | `admin_partners_screen.dart` | ✅ | |
| Ratings | `admin_ratings_screen.dart` | ✅ | ⚠️ Sem dados reais (BUG-018) |
| Reservas admin | `admin_reservations_screen.dart` | ✅ | |

---

## Ecrãs em Falta (a criar)

| Ecrã | Prioridade | Notas |
|------|-----------|-------|
| Histórico de pagamentos (cliente) | Média | Ver ideias/ux-cliente.md |
| Perfil completo do driver | Alta | Foto, documentos, estatísticas |
| Flash Deals / Promoções (parceiro) | Baixa | Feature futura |
| Configuração de horários (parceiro) | Média | Definir horas de funcionamento |
| Extracto financeiro (parceiro) | Média | Relatório mensal |
