# Bora App — API Documentation (TestSprite)

> **Propósito:** referência técnica de Edge Functions, RPCs, schema Supabase, RLS e auth — para configuração de testes automáticos no TestSprite.
> **Data:** 2026-05-28
> **Project ref:** TODO: verificar (env var `SUPABASE_URL`).

---

## 0. Bases

- **Supabase URL:** `https://<project>.supabase.co` (env `SUPABASE_URL`).
- **Edge Function endpoint:** `https://<project>.supabase.co/functions/v1/<name>` — método **POST**, JSON body.
- **RPC endpoint:** chamado via `supabase.rpc('name', params)` ou `POST /rest/v1/rpc/<name>`.
- **Headers obrigatórios:**
  - `Content-Type: application/json`
  - `apikey: <anon_key>` (sempre)
  - `Authorization: Bearer <jwt>` (quando autenticado)
- **Encoding:** UTF-8.

---

## 1. Autenticação

### 1.1 Métodos de signup

| Método | Endpoint | Notas |
|---|---|---|
| Email + password | `auth.signInWithPassword` (SDK) | Cliente e Parceiro usam email real; Driver usa email sintético `{phone}@driver.bora.app`. |
| OAuth Google | `auth.signInWithOAuth({provider:'google'})` | Cliente apenas. |
| OAuth Apple | `auth.signInWithOAuth({provider:'apple'})` | iOS apenas; skeleton feature-flagged. TODO: verificar prod. |

### 1.2 JWT claims relevantes

```json
{
  "sub": "<user_uuid>",
  "email": "user@example.com",
  "user_metadata": {
    "bora_role": "client" | "driver" | "partner",
    "phone": "910000000",
    "full_name": "..."
  },
  "app_metadata": {
    "role": "admin"
  },
  "aud": "authenticated",
  "exp": 1735689600
}
```

- `user_metadata.bora_role` é **mutável** (set durante signup).
- `app_metadata.role='admin'` é **imutável** — protegido pelo trigger `protect_admin_app_role`.

### 1.3 Roles & storage

| Role | Storage | Notes |
|---|---|---|
| `client` | `user_metadata.bora_role='client'` | Email real. |
| `driver` | `user_metadata.bora_role='driver'` | Email sintético `{phone}@driver.bora.app`. |
| `partner` | `user_metadata.bora_role='partner'` | Approval workflow (`is_approved=false` até admin). |
| `admin` | `app_metadata.role='admin'` | Imutável. |

### 1.4 Aprovação

- Driver e Partner ficam `is_approved=false` até admin aprovar via:
  - `admin_approve_driver(driver_id)` RPC.
  - `admin_approve_partner(partner_id)` RPC (TODO: verificar nome exacto).

### 1.5 Demo accounts (sempre disponíveis offline)

- Cliente: `cliente@bora.app` / `123456`.
- Driver: phone `910000000` / `123456` → email sintético `910000000@driver.bora.app`.
- Não existe partner demo hardcoded.

### 1.6 Reset de password

- Edge Fn `support-password-reset` — POST `{email}` → envia link Supabase `resetPasswordForEmail`.
- Resposta neutra (anti-enumeration): `{success:true}` mesmo se email não existir.

---

## 2. Edge Functions (38 totais)

### 2.1 Modelos de auth Edge

- **JWT (anon)** `verify_jwt=false` — qualquer pode chamar (validações server-side).
- **JWT (user)** `verify_jwt=true` — requer Bearer JWT válido.
- **service_role** — exige JWT com `role=service_role` (admin/server-side apenas).

### 2.2 Pagamentos (Stripe)

| Função | Auth | Body | Resposta | Notas |
|---|---|---|---|---|
| `create-payment-intent` | anon | `{order_id, amount, currency:'eur', payment_method_id?}` | `{client_secret, payment_intent_id}` | Valida amount ±5% `orders.payment_buffer_total`. Stripe min €0,50. |
| `create-mbway-payment-intent` | anon | `{order_id, amount, phone_e164}` | `{client_secret, payment_intent_id}` | Push automático para app MB Way. LIVE desde 2026-04-24. |
| `create-reservation-payment-intent` | JWT | `{reservation_id, amount}` | `{client_secret}` | Pré-pagamento reserva. |
| `confirm-mbway-payment` | service_role | `{payment_intent_id}` | `{status}` | Stub manual — obsoleto após webhook live. |
| `finalize-order-from-intent` | service_role | `{payment_intent_id}` | `{order:{}}` | Marca order paga após confirmação. |
| `refund` | service_role (JWT `role=service_role`) | `{order_id, amount?, reason}` | `{refund_id, status}` | Admin only. TODO: BUG-MN-004 cap + idempotency pendente. |
| `charge-extra` | JWT | `{order_id, amount, reason}` | `{charge_id}` | Tip, surcharge. |
| `list-saved-cards` | JWT | `{}` (user from JWT) | `{cards:[{id, brand, last4, exp}]}` | Stripe Customer payment methods. |
| `pay-debt-standalone` | JWT | `{amount}` | `{client_secret}` | Pagar dívida wallet. |
| `stripe-webhook` | service_role (Stripe sig) | Stripe event | `{received:true}` | Handler `payment_intent.succeeded` / `.payment_failed` / `charge.refunded`. |

### 2.3 Pedidos

| Função | Auth | Body | Resposta |
|---|---|---|---|
| `dispatch-engine` | JWT | `{order_id}` | `{driver_offered_id?, dispatched:true}` |
| `client-cancel-order` | JWT | `{order_id}` | `{cancelled:true, refund:{}}` |
| `cancel-order-with-choice` | JWT | `{order_id, reason_code, reason_text?}` | `{cancelled:true}` |
| `admin-cancel-order` | service_role | `{order_id, reason}` | `{cancelled:true}` |
| `execute-cancellation` | JWT | `{order_id}` | `{cancelled:true}` (workflow completo) |
| `update-products` | service_role | `{products:[...]}` | `{updated:N, errors:[]}` (bulk) |

### 2.4 Notificações

| Função | Auth | Body | Notas |
|---|---|---|---|
| `notify-client` | service_role | `{user_id, title, body, data?}` | FCM + email fallback. |
| `notify-driver` | service_role | `{driver_id, order_id, type}` | Data-only FCM + fullScreenIntent + canal `bora_alert`. Fallback `push_tokens`. |
| `notify-partner` | JWT | `{partner_id, order_id}` | Default `verify_jwt=true` (fire-and-forget após createOrder). |
| `notify-admin-urgent` | JWT | `{event_type, payload}` | Alerta admin. |
| `notify-admin-reimbursement` | service_role | `{order_id, reason}` | Flag reembolso pendente. |
| `notify-partner-low-rating` | JWT | `{partner_id, rating}` | Auto-trigger rating < 3. |
| `notify-chat-message` | service_role | `{conversation_id, sender_id, body}` | Push para outro lado. |
| `notify-purchase-finalized` | service_role | `{order_id}` | Push "encomenda entregue". |

### 2.5 AI / Suporte

| Função | Auth | Body | Notas |
|---|---|---|---|
| `admin-ai-assistant` | service_role | `{message, conversation_id}` | Gemini + SQL tools. Out of scope TestSprite. |
| `support-chatbot` | service_role | `{message, user_id, conversation_id?}` | Gemini + RAG (534 chunks). |
| `support-submit-ticket` | JWT | `{subject, body, attachments?}` | Cria ticket + email team. |
| `support-password-reset` | anon | `{email}` | Resposta neutra. |
| `reindex-knowledge` | JWT | `{}` | Rebuild vector index. Out of scope. |
| `analyze-conversations` | service_role | `{date_range}` | Out of scope. |

### 2.6 Utilizadores

| Função | Auth | Body | Notas |
|---|---|---|---|
| `register-partner` | anon | `{email, password, restaurant_name, nif, iban, ...}` | Valida IBAN PT+21 dígitos. Logging detalhado. |
| `delete-account` | JWT | `{}` (user from JWT) | GDPR deletion. |
| `admin-force-driver-logout` | service_role | `{driver_id}` | Encerra sessão remota. |

### 2.7 Storage / Media

| Função | Auth | Body | Bucket |
|---|---|---|---|
| `upload-avatar` | JWT | multipart `{file}` | `avatars` |
| `upload-receipt` | JWT | multipart `{file, order_id}` | `receipts` |
| `upload-restaurant-asset` | service_role | multipart `{file, restaurant_id, kind}` | `restaurants/{id}/{kind}.{ext}` |
| `ocr-receipt` | service_role | `{image_url}` | Gemini Vision OCR → JSON. |

---

## 3. PostgreSQL RPCs (chamadas via `supabase.rpc()`)

### 3.1 Cliente / Carrinho

| RPC | Params | Resposta |
|---|---|---|
| `client_redeem_promo_tokens` | `{p_code, p_user_id}` | `{tokens_applied, discount_cents}` |
| `client_apply_promo_code` | `{p_code, p_order_id}` | Deprecated — usar redeem. |
| `wallet_get_balance` | `{p_user_id}` | `{free_cents, tokens_balance, last_transactions[]}` |
| `pricing_calculate` | `{p_subtotal, p_distance_km, p_is_partner, p_service_type}` | `{delivery_fee, service_fee, customer_total, driver_earnings, commission}` |

### 3.2 Driver

| RPC | Params | Resposta |
|---|---|---|
| `driver_heartbeat_by_id` | `{p_driver_id, p_lat, p_lng, p_battery?}` | `void` |
| `accept_offer` | `{p_order_id, p_driver_id}` | `{accepted:true}` ou erro `offer_unavailable` |
| `driver_reject_offer` | `{p_order_id, p_driver_id}` | `{rejected:true}` |
| `get_user_tokens` | `{p_user_id}` | `int` (sum active non-expired) |

### 3.3 Admin (20+)

```
admin_approve_action                — Approve pending admin action
admin_approve_cancellation          — Approve order cancellation request
admin_approve_skill_suggestion      — Approve support skill suggestion
admin_ban_client                    — Ban user (fraud/abuse)
admin_ban_driver(p_driver_id, p_reason_code, p_reason, p_banned_until)
admin_block_client                  — Soft-delete user
admin_broadcast_notification        — Send broadcast message
admin_bulk_reject_skill_suggestions
admin_category_mapping_stats
admin_dashboard_metrics
admin_finalize_action
admin_forgive_wallet_debt
admin_get_client_history
admin_list_audit_log
admin_list_complaints
admin_list_pending_actions
admin_list_products_by_partner
admin_list_wallets
admin_kpi_avg_ticket(p_days_back)
admin_kpi_conversion(p_days_back)
admin_kpi_hot_zones(p_days_back, p_limit)
admin_list_clients                  — Inclui photo_url (Sessão 2026-05-26)
```

### 3.4 Ledger / Payouts

| RPC | Params | Notas |
|---|---|---|
| `create_payout(user_id, user_type, amount)` | — | Atomic payout + ledger pair. SECURITY DEFINER. |
| `recompute_user_balance(user_id, user_type)` | — | Snapshot refresh from `ledger_entries` SUM. |
| `add_tokens(p_user_id, p_role, p_amount, p_source_order_id)` | — | Award token entry idempotente. |

---

## 4. Schema Supabase (tabelas principais)

### 4.1 `orders`
- **id:** TEXT (legado, não UUID).
- **user_id:** UUID → `auth.users`.
- **restaurant_id:** TEXT → `restaurants.id`.
- **assigned_driver_id:** TEXT (cast `::UUID` em triggers).
- **status:** ENUM `OrderStatus` (created/preparing/callingDriver/driverAccepted/pickedUp/onTheWay/delivered/cancelled/rejected).
- **payment_method:** ENUM (`card`/`mbway`/`cash`/`apple_pay`).
- **payment_buffer_total, customer_total, subtotal, delivery_fee, service_fee, partner_commission_visible, partner_markup_hidden, partner_service_fee_client.**
- **current_driver_offer_id:** TEXT (fonte de verdade dispatch).
- **created_at, accepted_at, picked_up_at, delivered_at.**

**Triggers:**
- `orders_financial_lock` — imutabilidade financeira pós-criação.
- `orders_post_to_ledger` — AFTER UPDATE status='delivered' → entries earning + commission + share.
- `orders_cash_settlement` — AFTER UPDATE status='delivered' WHERE payment_method='cash'.

### 4.2 `profiles`
- **user_id:** UUID PK → `auth.users`.
- **full_name, photo_url, default_address_id, role (redundante com user_metadata).**

### 4.3 `restaurants` / `products`
- **restaurants.id:** TEXT.
- **business_category:** ENUM `restaurant/supermarket/store/pharmacy`.
- **is_active, is_partner, lat, lng, hero_url, logo_url.**
- **products.id:** TEXT. **products.restaurant_id:** TEXT FK.
- **products.price (cents), variants jsonb, is_available, taxonomy_section, needs_review.**

### 4.4 `drivers`
- **id:** UUID → `auth.users`.
- **phone, full_name, vehicle_type, iban, registration_selfie_url, is_approved, is_online, lat, lng, battery_percent.**
- **VehicleType:** ENUM (determina `supportsService()`).

### 4.5 `bora_tokens`
- **id PK, user_id, role (client/driver), amount (>0), expires_at (60d), source_order_id (UNIQUE WITH role — idempotência), is_used, used_at.**
- Trigger `fn_award_tokens_on_delivery`.

### 4.6 `ledger_entries`
- **id, user_id (TEXT), user_type (driver/restaurant/platform), order_id (nullable), amount NUMERIC (sign-convention), type (earning/cash_adjustment/commission/payout), reference (idempotency), created_at.**
- **Append-only** — UPDATE/DELETE bloqueado por trigger.

### 4.7 `driver_balances` / `driver_transactions`
- **driver_balances:** driver_id PK, balance NUMERIC, updated_at.
- **driver_transactions:** id, driver_id, order_id UNIQUE (idempotência), amount, type, created_at.
- Limite cash: €30 enforçado em INSERT (trigger `enforce_cash_payment_limit`).

### 4.8 `client_wallets` / `wallet_transactions`
- **client_wallets:** user_id PK, free_balance_cents (≥0).
- **wallet_transactions:** id, user_id, amount_cents (+/-), kind (refund_credit_free / order_payment / admin_grant / cashback / referral), reason.
- Refund logic: 80% saldo livre + 20% tokens (1 token = 0,05 cents).

### 4.9 Outras

| Tabela | Propósito |
|---|---|
| `addresses` | Moradas do cliente (FK user_id). |
| `messages` | Chat cliente↔driver↔partner. `senderType` em vez de `senderId`. |
| `partner_push_tokens` | FCM tokens parceiros (saveTokenForPartner). |
| `push_tokens` | FCM tokens drivers (fallback notify-driver). |
| `ratings` | Avaliações pós-entrega. TODO: verificar nome exacto. |
| `promo_codes` | code PK, type, discount_value, max_uses, expires_at. |
| `referral_codes` / `referral_invites` | Sistema viral (inviter bónus on invitee's 1st order). |
| `order_purchase_items_v2` / `order_receipts_v2` | StoreShopping V2 (Continente, Lidl). |
| `reservations` | Reservas de mesa. TODO: verificar schema. |
| `robot_crosstalk` | Comunicação Robô A↔B. Out of scope TestSprite. |
| `support_tickets` | Tickets suporte. |
| `audit_log` | Append-only audit (admin actions). |

---

## 5. RLS Policies (relevantes para testes de segurança)

### 5.1 `orders`
- **SELECT:** `auth.uid() = user_id` (cliente vê os seus) OR `auth.uid() = assigned_driver_id::UUID` (driver vê os atribuídos) OR `app_metadata.role='admin'`.
- **INSERT:** `auth.uid() = user_id` (cliente cria os seus).
- **UPDATE:** apenas via RPCs SECURITY DEFINER (status transitions) ou admin.
- **DELETE:** bloqueado (append-only — usa `cancelled` status).

### 5.2 `profiles`
- **SELECT:** `auth.uid() = user_id` + admin.
- **UPDATE:** `auth.uid() = user_id` (não pode mudar role).

### 5.3 `products`
- **SELECT:** `is_active=true` para qualquer auth.
- **INSERT/UPDATE/DELETE:** apenas owner do `restaurant_id` (partner) ou admin.

### 5.4 `restaurants`
- **SELECT:** `is_active=true` para qualquer (público).
- **UPDATE:** owner only — path canónico `{restId}/{kind}.{ext}` (storage fix Sessão 2026-05-21).

### 5.5 `bora_tokens`
- **SELECT:** `auth.uid() = user_id`.
- **INSERT:** apenas via RPC SECURITY DEFINER (`add_tokens` / trigger delivery).

### 5.6 `ledger_entries`
- **SELECT:** drivers vêem entries próprias (`user_id = auth.uid()::TEXT`).
- **INSERT/UPDATE/DELETE:** bloqueado para clientes — apenas SECURITY DEFINER.

### 5.7 `messages`
- **SELECT:** participantes da conversa (cliente, driver, partner do order).
- **INSERT:** auth_uid in participants.

### 5.8 `addresses`
- **SELECT/INSERT/UPDATE/DELETE:** `user_id = auth.uid()`.

### 5.9 `restaurants` (RLS hardening Sessão 2.4 — 2026-05-17)
- Restaurants + products + messages fechados em RLS hardening (3 migrations + helper function).

### 5.10 Storage buckets
- **avatars** — owner SELECT/UPDATE; público SELECT (TODO: verificar).
- **receipts** — owner only.
- **restaurants/** — path canónico `{restId}/{kind}.{ext}` (público SELECT, owner WRITE, admin WRITE).

---

## 6. Testes de segurança recomendados

| Cenário | Esperado |
|---|---|
| Cliente A tenta SELECT order de Cliente B | 0 rows. |
| Driver A tenta UPDATE order não atribuída | RLS bloqueia. |
| Cliente tenta INSERT em `bora_tokens` directamente | RLS bloqueia. |
| Cliente tenta UPDATE `profiles.role` | RLS bloqueia ou trigger reverte. |
| Cliente tenta UPDATE `app_metadata.role='admin'` | Trigger `protect_admin_app_role` reverte. |
| Driver tenta SELECT `ledger_entries` de outro driver | 0 rows. |
| anon (sem JWT) chama `create-payment-intent` | Aceita (verify_jwt=false), mas validações amount/buffer protegem. |
| anon chama `refund` | 401 (verify_jwt=true + role=service_role). |
| Partner tenta editar produtos de outro restaurante | RLS bloqueia (owner check). |
| Cliente força amount inflado em `create-payment-intent` | Edge Fn rejeita (>5% diff vs `payment_buffer_total`). |

---

## 7. Test environment

- **Cartões teste Stripe:**
  - Sucesso: `4242 4242 4242 4242` (CVC qualquer, exp futura).
  - Declined: `4000 0000 0000 0002`.
  - 3DS required: `4000 0025 0000 3155`.
- **MB Way teste:** ambiente sandbox Stripe — phone qualquer E.164 PT.
- **Demo accounts:** ver §1.5.
- **Realtime channels a subscrever em testes:**
  - `orders_channel` (orders INSERT/UPDATE/DELETE).
  - `public:drivers` (location updates).
  - `driver-offer:{id}` (oferta por driver).

---

**Fim.** Para descrição funcional + fluxos esperados ver `testsprite-prd.md`.
