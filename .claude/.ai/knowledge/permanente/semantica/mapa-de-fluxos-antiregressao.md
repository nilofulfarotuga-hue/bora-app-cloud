---
id: mapa-de-fluxos-antiregressao
tipo: semantica
origem: [missão noturna 2026-07-09 Fase 1 — bugs-resolvidos.md (24 bugs) + backend-map]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado-no-codigo
---

# Mapa de Fluxos — CHECKS ANTI-REGRESSÃO + BACKEND POR FLUXO

> Cada bug `estado: atual` de `bugs-resolvidos.md` vira um check no fluxo correspondente.
> 🔴 = zona dinheiro: validar SÓ com leitura (SELECT/assert), nunca tocar.

## A) Checks anti-regressão (por bug)
| # | Bug | Fluxo | CHECK |
|---|---|---|---|
| 1 | vehicle_type hard-coded | candidatura | registar "carro" → `drivers.vehicle_type='car'` (nunca motorcycle) |
| 2 | card stretch Serviços | cliente/serviços | card prestador ~96px de altura (não 1910) |
| 3 | headers branco-no-branco | transversal | 0 `DecoratedBox` como header; tudo `BoraScreenAppBar` |
| 4 | chat_mark_read uuid=text | chat | marcar lido → `messages.read_at IS NOT NULL`, sem erro cast |
| 5 | IBAN PT+21 | aprovações | IBAN PT+21 díg aprova; PT+22 rejeita |
| 6 | nav race registo parceiro | parceiro | registo → pending estável, sem loop (sem setRole no ecrã) |
| 7 | só-serviços expulso | parceiro | login barbearia sem restaurante → PartnerServicesHubScreen |
| 8 | driver online bloqueado | estafeta | toggle online sem overlay/bateria → `is_online=true` |
| 9 | loop de dispatch | dispatch | SQL: 0 orders `calling_driver` com >5 min |
| 10 | oferta FG/BG/locked | estafeta | oferta → dialog fullscreen em FG; `pending_offer` rehydrata pós cold-start |
| 11 | FCM heads-up/token | push | token parceiro em `partner_push_tokens`; heads-up em BG |
| 12 | extras não cobrados 🔴 | checkout | SQL: pedido com option `price_add` → `total_amount` soma extras |
| 13 | bag_fee duplicado 🔴 | checkout | SQL: bag_fee conta 1× (rest €0,30 fixo / mercado €0,10/un) |
| 14 | chat 3 causas | chat | 0 mensagens `customer_name` null; senderType presente |
| 15 | PIN client-side (P0 ABERTO) | entrega | PIN validado server-side antes de delivered; `admin_approve_driver` sem duplicado |
| 16 | cadastro bloqueava | candidatura | Step0 avança sempre; RPC só overload 14-param (sem PGRST203) |
| 17 | storage 403 hero/logo | parceiro | upload grava `{restId}/{kind}.{ext}` sem 403 |
| 18 | dashboard em inglês | parceiro | 0 strings EN visíveis no dashboard |
| 19 | splash hang CI | build | CI injeta `DART_DEFINES_FILE_B64`; app passa do splash |
| 20 | scraper price=0 | mercados | SQL: 0 products `price<=0 AND is_available=true` |
| 21 | crawler Glovo −69% | mercados | contagens por loja ≈ real (Auchan ~6245) |
| 22 | tela branca Favores | favores | 2 formulários com corpo visível (bodyH>0); footer `mainAxisSize.min` |
| 23 | Central RPC errada | admin | aprovar evidência chama `robot_mark_suggestion_done`; sem mojibake |
| 24 | TVDE mudo (P0) | TVDE | elegibilidade `GREATEST(last_updated,last_heartbeat_at)`; `tvde_ride_events` regista `push_enviado/push_falhou` |

⚠️ Regra viva de tokens: cliente ganha **3 tokens/€** (não "3%"); driver +40 normal/+50 parceiro.

## B) Backend por fluxo (validação read-only no fim de cada teste)
| Fluxo | RPCs/EFs chave | Validar (SELECT) |
|---|---|---|
| Delivery parceiro | `create_order`🔴 · `partner_accept_order` · dispatch-engine🔴 · `apply_order_financial_split`🔴 | pós-delivered: 1 `order_financials`; split 10+5+5 em `order_financial_transactions`; tokens driver +40/+50; cliente 3/€ |
| storeShopping V2 | `finalize_storeshopping_purchase_v2`🔴 · `upload-receipt`/`ocr-receipt` · `charge-extra`🔴 | checklist reconcilia; talão em `order_receipts_v2`; finalize ANTES de pickup |
| Mercados | `bora_scraper_insert_batch` · `admin_update_product_price`🔴 | 0 price<=0 visível; sem duplicados `search_normalized` |
| Favores | `pricing_calculate_errand`🔴 · `errand_request_budget_increase` | orçamento acordado = total; catálogo gated em `errand_catalog_queue` |
| Reservas | `client_confirm_reservation_payment`🔴 · `partner_mark_arrival`🔴 | chegada → €2 `restaurant_menu_credits` + €2 `partner_reservation_payouts` |
| Limpeza | `cleaning_*` · `_cleaning_complete`🔴 · EF `cleaning-checkout`🔴 | split 85/15; tokens dentro de `_cleaning_complete` (⛔ não mexer); cash 15% `cash_pending` |
| TVDE corrida | `tvde_request_ride` · `tvde_accept_ride` · `tvde_finish_ride`🔴 (3 args) | oferta gera evento push; cash → `tvde_driver_balances`🔴 |
| TVDE planos | `tvde_consume_subscription_ride`🔴 · EF `tvde-plan-payment`🔴 | corrida consome 1 de `tvde_ride_counters`; sem stripe-webhook |
| Cancelamento | `compute_refund_split`🔴 · `wallet_credit_refund_split`🔴 · EFs cancel🔴 | fee por escalão E1–E4; split 80/20; cap refund respeitado |
| Wallet/Tokens 🔴 | `add_tokens`🔴 · `consume_tokens`🔴 · `recompute_user_balance`🔴 | saldo = soma ledger (append-only); 100 tokens=€0,50; ≤50% |
| Chat | `chat_mark_read` · EF `notify-chat-message` | read_at atualiza; RLS participantes-only |
| Push | `register_push_token` · EFs notify-* | token na tabela do papel; falha → `mark_token_failed` |

## 🔴 Blindadas (a Trava bloqueia; só ler)
EFs: `dispatch-engine` `create-payment-intent` `stripe-webhook` `refund` `finalize-order-from-intent` `charge-extra` `reprocess-refund` `create-mbway-payment-intent` · Ficheiros: `pricing_service.dart` `order_store.dart` `errand_execution_sheet.dart` · DDL: `pricing_*` `wallet_*` `*token*` `*settlement*` `*payout*` `refund*` `finalize_*` ledger
