---
tema: backend-map · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# Backend Map — Tabelas (schema public)

130 tabelas. RLS ativo em todas. 🔴 = zona de dinheiro. Índice: [backend-map.md](./backend-map.md).

## Pedidos / Financeiro 🔴

| Tabela | Propósito |
|---|---|
| `orders` | Pedido central (entrega/mercado/errand). Hub de todo o dispatch e financeiro. 🔴 |
| `order_financials` 🔴 | Ledger de split financeiro — 1 linha por pedido de parceiro, settle atómico na entrega. |
| `order_financial_transactions` 🔴 | Journal por-parte (2 linhas por pedido settled). |
| `ledger_entries` 🔴 | Ledger append-only — fonte única de verdade. Triggers no-update/no-delete. |
| `payouts` 🔴 | Pedidos de payout; par com ledger entry negativa. |
| `user_balance_snapshots` 🔴 | Saldo corrente cacheado por user (otimização; ledger é autoritativo). |
| `payment_drafts` | Rascunhos de pagamento (pré-intent). |
| `pending_charges` 🔴 | Fila de cobranças automáticas pós-entrega (sacos mercado, off_session). |
| `mbway_debug_errors` | Log de erros MB WAY. |

## Tokens / Wallet 🔴

| Tabela | Propósito |
|---|---|
| `bora_tokens` 🔴 | Saldo de tokens por user. |
| `token_config` 🔴 | Config de valor/regras de tokens. |
| `driver_token_transactions` 🔴 | Transações de tokens do estafeta. |
| `client_wallets` 🔴 | Carteira do cliente (saldo €). |
| `wallet_transactions` 🔴 | Movimentos da carteira (débitos/créditos/cashback). |
| `driver_balances` 🔴 | Saldo cash corrente por estafeta (dívida ao Bora). |
| `driver_transactions` 🔴 | Log de auditoria financeira do estafeta (UNIQUE order_id). |

## Dispatch / Estafetas

| Tabela | Propósito |
|---|---|
| `drivers` | Cadastro de estafetas (aprovação, online, docs). |
| `driver_locations` | Feed GPS realtime para admin live-ops (1 linha/driver). |
| `driver_weekly_settlements` 🔴 | Fecho semanal do estafeta. |

## Favores / Errand

| Tabela | Propósito |
|---|---|
| `errand_catalog_queue` | Fila de produtos extraídos de favores (Gemini) para aprovação admin (gated). |

## TVDE (isolada) 🔴

| Tabela | Propósito |
|---|---|
| `tvde_access_requests` | Pedidos de acesso à vertical TVDE. |
| `tvde_rides` | Corridas de passageiros (ISOLADA de orders/dispatch). |
| `tvde_ride_events` | Eventos de cada corrida. |
| `tvde_subscriptions` | Subscrições do motorista TVDE. |
| `tvde_ride_counters` | Contadores de corridas. |
| `tvde_driver_balances` 🔴 | Dívida do motorista ao Bora por corridas cash. |

## Serviços / Agendamentos (barbearia etc.)

| Tabela | Propósito |
|---|---|
| `service_providers` | Prestadores de serviço (barbearia, etc.). |
| `staff_members` | Funcionários do prestador. |
| `provider_services` | Serviços oferecidos (preço/duração). |
| `staff_availability` | Disponibilidade de staff. |
| `appointments` | Marcações de clientes. |
| `appointment_payouts` 🔴 | Payouts de marcações. |

## Reservas (Reservas Pro)

| Tabela | Propósito |
|---|---|
| `reservations` | Reservas de mesa (BR §14). |
| `restaurant_floor_plans` | Layouts do restaurante (Normal/Eventos). |
| `restaurant_tables` | Mesas físicas individuais. |
| `restaurant_pacing_rules` | Limites de capacidade por slot horário. |
| `restaurant_turn_times` | Tempo médio de ocupação por party size. |
| `reservation_table_assignments` | Liga reserva a mesa(s); combinação de mesas. |
| `reservation_waitlist` | Fila de espera quando cheio. |
| `reservation_notify_list` | "Avisar se vagar" (modelo OpenTable/Resy Notify). |
| `client_restaurant_profiles` | Perfil cliente↔restaurante (VIP, no-shows, notas). |
| `restaurant_menu_credits` 🔴 | Créditos de menu por chegada a reserva (auto-aplicado). |
| `partner_reservation_payouts` 🔴 | €2 devido ao parceiro por reserva com chegada. |

## Suporte / Robot / IA

| Tabela | Propósito |
|---|---|
| `support_tickets` | Tickets de suporte. |
| `support_settings` | Config do suporte. |
| `support_skills` | Playbooks do agente de suporte. |
| `support_chatbot_sessions` | Sessões do chatbot. |
| `support_chatbot_messages` | Mensagens do chatbot. |
| `support_chatbot_quota` | Quota por user. |
| `support_agent_actions` | Ações executadas pelo agente. |
| `support_knowledge_chunks` | RAG (embeddings Gemini 768-dim). |
| `support_embedding_cache` | Cache de embeddings de queries. |
| `support_pending_actions` | Ações pendentes de aprovação humana. |
| `skill_suggestions` | Sugestões automáticas de novas skills. |
| `robot_crosstalk` | Comunicação Robô A↔B (a_to_b/b_to_a). |
| `robot_runs` | Corridas do Robô B. |
| `robot_suggestions` | Sugestões geradas pelo Robô B. |
| `robot_audit_log` | Auditoria de ações do robô. |
| `complaints` | Reclamações. |
| `admin_ai_sessions` | Histórico admin↔assistente IA. |
| `debug_crash_logs` | Logs de crash do cliente. |

## Admin / Auditoria / Config

| Tabela | Propósito |
|---|---|
| `admin_audit_log` | Log append-only de ações admin (via `log_admin_action()`). |
| `admin_notifications` | Notificações internas de admin. |
| `cancellation_requests` | Pedidos de cancelamento. |
| `platform_settings` 🔴 | Settings runtime (inclui hard floors wallet, fees, pricing keys). |
| `partner_status_override` | Overrides admin de aberto/fechado do parceiro. |
| `category_mapping` | Mapeamento de categorias de catálogo. |
| `edge_function_invocations` | Log de invocações de edge fns. |
| `product_update_runs` | Observabilidade das corridas de update-products. |
| `market_update_schedule` | Agenda de update de mercados. |
| `guarda_businesses` | Diretório de negócios da Guarda. |
| `partner_weekly_settlements` 🔴 | Fecho semanal do parceiro. |

## Push / Notificações

| Tabela | Propósito |
|---|---|
| `client_push_tokens` | FCM tokens cliente (multi-device). |
| `driver_push_tokens` | FCM tokens estafeta (multi-device). |
| `partner_push_tokens` | FCM tokens parceiro. |
| `admin_push_tokens` | FCM tokens admin (multi-device). |
| `in_app_notifications` | Notificações in-app. |
| `push_broadcasts` | Broadcasts segmentados. |

## Cliente (perfil / social)

| Tabela | Propósito |
|---|---|
| `users` | Utilizadores (base). |
| `client_addresses` | Endereços do cliente. |
| `client_favorites` | Favoritos. |
| `client_search_history` | Histórico de pesquisa. |
| `referral_codes` 🔴 | Códigos de referral. |
| `referral_invites` 🔴 | Convites de referral. |
| `promo_codes` 🔴 | Códigos promocionais. |
| `promo_code_uses` 🔴 | Usos de promo. |
| `ratings` | Avaliações (estafeta/restaurante). |
| `messages` | Chat entre partes do pedido. |

## Catálogo / Mercados

| Tabela | Propósito |
|---|---|
| `products` | Catálogo de produtos (~46.7k linhas). |
| `product_variants` | Variantes de produto. |
| `product_option_groups` | Grupos de opções (~1.5k). |
| `product_option_items` | Itens de opção (~10.4k). |
| `restaurants` | Lojas/restaurantes/mercados. |
| `continente_price_staging` | Staging de preços Continente. |

## storeShopping v2 🔴

| Tabela | Propósito |
|---|---|
| `order_purchase_items_v2` | Checklist do estafeta (purchased/unavailable/replaced/added). 🔴 |
| `order_receipts_v2` 🔴 | Foto/OCR do talão; reembolso (Stripe/MBWay→pending_admin; CASH→auto). |

## Backup / Staging (67 tabelas)

Prefixos `_backup_*`, `_*_price_sources_*`, `_continente_price_sources_*`, `continente_price_staging`.
Snapshots de crawls (Continente, Auchan, Intermarché, Pingo Doce, Wells, Worten, Kiwoko, Zippy, Leroy, McDonald's, BK, KFC, Pizza Hut, Açaí). RLS on, 0 policies. Não tocar em runtime.
