# Wallet 80/20 + Cashback + Referral (§17)
> Created 2026-04-30 — autonomous session · Branch `autonomous-night-2026-04-29`

## §17.1 — Saldo Bora (free)

- Tabela: `client_wallets (user_id PK, free_balance_cents, created_at, updated_at)`.
- **NUNCA expira.** Sem regras de uso. Cobre 100% de qualquer pedido.
- Crédito vem de:
  - Refund split 80% (cliente cancela e escolhe app)
  - Cashback automático (1% default)
  - Referral reward (€5 default)
  - Admin grant manual
- Compliance PT: "Saldo não reembolsável em dinheiro" — texto obrigatório.

## §17.2 — Tokens (Batch D — não duplicar)

- Tabela existente `bora_tokens`. RPCs existentes `add_tokens / consume_tokens / get_user_tokens`.
- 1 token = €0.0005 (= 0.05 cents = `token_value_cents_x100=5`).
- Refund split 20% → tokens (4000 tokens por €2 de refund).
- Cliente continua a ganhar `ROUND(price*3) min 1 token` ao entregar pedido (regra existente).
- Tokens dão até 50% desconto no checkout (regra existente).

## §17.3 — Refund split 80/20

- Setting `wallet_split_free_pct` (default 0.80, configurável em `platform_settings`).
- RPC `wallet_credit_refund_split(p_order_id, p_user_id, p_total_cents, p_reason)`:
  1. `free_amount = ROUND(total * 0.80)` → upsert `client_wallets`
  2. `tokens_amount = total - free_amount`
  3. `tokens_count = tokens_amount * 20` (porque token = 0.05 cents)
  4. Chama `add_tokens(user_id, 'client', tokens_count, order_id)`
  5. Audit log `wallet_refund_split`
- Edge Function `cancel-order-with-choice` chama esta RPC quando `refund_method='wallet'`.

## §17.4 — Refund choice dialog

- Padrão iFood (cliente escolhe a cada cancelamento)
- 2 opções:
  - **Cartão (5-10 dias úteis)** — chama Edge Fn `cancel-order-with-choice` com `refund_method='stripe'` → `stripe.refunds.create`
  - **App (instantâneo)** — `refund_method='wallet'` → split 80/20
- Default UI: `wallet` (mais valioso para retenção)
- `app_payment_method != 'card'` → força `wallet` (sem PaymentIntent)

## §17.5 — Cashback automático

- Setting `cashback_pct` (default 0.01 = 1%, range 0–5%)
- Trigger `trg_award_cashback` em `orders` quando `status→delivered`
- Crédito vai para saldo livre via `wallet_credit_generic(kind='cashback')`
- Idempotente: não credita se já houve cashback para a order

## §17.6 — Referral

- Setting `referral_referrer_reward_cents=500` / `referral_invited_reward_cents=500` / `referral_min_first_order_cents=1000` / `referral_invite_expires_days=30`
- Tabelas: `referral_codes (user_id PK, code UNIQUE, …)`, `referral_invites (status: pending/signed_up/first_order_done/expired)`
- Fluxo:
  1. User chama `client_get_or_create_referral_code()` → `BORA-DAN-A4F`
  2. Convidado faz signup e chama `client_register_with_referral(p_code)` → invite `signed_up`
  3. 1º pedido `delivered` ≥ €10 → trigger `trg_referral_reward` credita ambos em saldo livre
  4. Push para os dois (TODO Edge Fn `notify-client`)

## §17.7 — Promo codes

- Tabela `promo_codes (code PK, type, value_cents/value_pct, max_uses, max_uses_per_user, min_order_cents, valid_until, partner_ids[], is_active)`
- 3 tipos: `percent_off`, `fixed_off`, `free_delivery`
- 1 promo por pedido (regra Glovo)
- RPC `client_apply_promo_code(p_code, p_order_total_cents, p_partner_id)` → `{valid, discount_cents, reason}`
- RPC `client_record_promo_use(p_code, p_order_id, p_applied_value_cents)` chamada quando order é criada com promo

## §17.8 — Audit Log

- Todas as operações wallet/referral/promo/cancellation passam por `log_admin_action`
- RPC `admin_list_audit_log` paginada com filtros (search, action_type, admin_id, date range)
- UI: `admin_audit_log_screen.dart`

## §17.9 — Cancellation Requests

- Tabela `cancellation_requests (id, order_id, requester_role driver/partner/client, status pending/approved/rejected/withdrawn, refund_method)`
- Driver/partner/cliente pedem via `request_order_cancel(p_order_id, p_reason)` (1 pendente por order)
- Admin aprova com `admin_approve_cancellation(p_request_id, p_refund_method)` ou rejeita com `admin_reject_cancellation`
- ⚠️ TODO: Edge Fn dedicada para executar refund após `admin_approve_cancellation` (Stripe ou wallet RPC) — actualmente apenas marca aprovação

## §17.10 — Limitações conhecidas / TODOs pós-launch

- Saldo livre não top-uppable por cartão (só vem de refund/cashback/referral/admin)
- Sem transferência entre users
- Sem saque para conta bancária
- Compliance: validar com jurista se acima de €X obriga registo IM (instituição moeda electrónica)
- Free delivery promo type: aplicação ao `delivery_fee` no checkout precisa de wiring no `PricingService`
