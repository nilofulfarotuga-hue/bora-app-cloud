# Sessão 3 — TODOs adiados

Branch origem: `autonomous-night-2026-04-29`
Relatório análise: `.claude/.ai/reports/20260502_megafinal/03_saco_mercado_analise.md`

---

## Sessão 3B — charge-extra off_session + retry queue

**Pré-requisito**: Sessão 3C (consent flow). Sem `setup_future_usage` activo, off_session falha SCA.

Tasks:
- [ ] **Rewrite `supabase/functions/charge-extra/index.ts`**
  - `off_session: true` + `confirm: true` + `payment_method: <id>` + `customer: <id>`
  - Header `Idempotency-Key: ${order_id}_${reason}`
  - Whitelist `reason: ['market_bags']`; validar `amount_cents BETWEEN 1 AND 50`
  - SCA recusa (`authentication_required`) → `pending_charges.status='requires_action'`
  - Sucesso → `pending_charges.status='succeeded'` + `stripe_payment_intent_id`
  - Falha → `pending_charges.status='failed'` + `error_code` + `retry_count++`
- [ ] **Webhook handler novo `stripe-webhook`**
  - Branch `payment_intent.succeeded` se `metadata.reason === 'market_bags'`:
    - `UPDATE pending_charges SET status='succeeded' WHERE idempotency_key = ...`
    - **NÃO tocar em `orders.payment_status`** (já está `paid` do checkout original)
  - Branch `payment_intent.payment_failed`/`canceled` análogo: `status='failed'`
- [ ] **RPC `finalize_storeshopping_purchase` — branch card/mbway**
  - `INSERT INTO pending_charges (status='pending', order_id, amount_cents, reason='market_bags', idempotency_key=order_id||'_bags') ON CONFLICT (idempotency_key) DO NOTHING`
  - Invocar Edge Function `charge-extra` via `pg_net.http_post` (assíncrono)
  - Se `pg_net` falhar: pending_charges fica em `pending` → cron drena
- [ ] **Cron drenagem** (`pg_cron` job a cada 5 min)
  - SELECT `pending_charges` WHERE `status='pending' AND created_at < now() - interval '2 minutes'` LIMIT 50
  - Invocar `charge-extra` para cada
- [ ] **Push cliente pós-charge** (B6 original)
  - Sucesso: "Sacos cobrados: €X.XX"
  - Falha: "Falha cobrança sacos, contactar suporte"
  - SCA required: "Confirma o pagamento dos sacos: <link>"
  - Depende de Sessão 1B push notifications estar deployado
- [ ] **Admin painel completo** (B7b)
  - Tela `admin_charges_screen.dart`
  - Lista `pending_charges` com filtros (status, últimas 24h falhados)
  - Acção retry manual: invoca `charge-extra` com mesma idempotency_key
  - Dashboard: charges falhados últimas 24h
- [ ] **Smoke tests**
  - storeShopping cartão 3 sacos → charge €0.30 auto + pending_charges='succeeded'
  - storeShopping mbway 5 sacos → análogo
  - Falha simulada (4000000000000341) → pending_charges='failed'
  - SCA recusa (4000000000003220) → pending_charges='requires_action'

---

## Sessão 3C — Consent flow checkout (setup_future_usage)

**Bloqueio actual**: `create-payment-intent` propositadamente OMITE `setup_future_usage` por decisão de produto documentada (cartão NUNCA gravado sem consent). Sem isto, Sessão 3B não pode funcionar.

Tasks:
- [ ] **Decisão de produto + legal**
  - Texto consent: "Autorizo cobranças até €0.50 por sacos de mercado pós-entrega"
  - Política de privacidade actualizada (storage payment_method)
  - Validar com legal antes de implementar
- [ ] **UI consent no checkout** (`lib/screens/checkout_screen.dart` ou similar)
  - Checkbox antes do pagamento: "Permitir cobranças automáticas de sacos pós-entrega"
  - Default: false (opt-in)
  - Se OFF: usuário paga sacos em cash mesmo se cartão (fallback "cobrar em mão")
- [ ] **Schema mudanças**
  - `ALTER TABLE orders ADD COLUMN allow_off_session_charge BOOLEAN NOT NULL DEFAULT false`
  - `ALTER TABLE orders ADD COLUMN stripe_customer_id TEXT NULL`
  - `ALTER TABLE orders ADD COLUMN stripe_payment_method_id TEXT NULL`
  - Considerar mover para tabela `users` ou `payment_methods` separada
- [ ] **`create-payment-intent` — modo consent**
  - Se cliente opt-in: criar/reusar Stripe `customer`
  - `setup_future_usage: 'off_session'` no PaymentIntent
  - Após `payment_intent.succeeded`, guardar `customer.id` + `payment_method.id` em `orders` ou `payment_methods`
- [ ] **Migrar create-mbway** análogo
- [ ] **Smoke tests**
  - Checkout com consent → cartão guardado, cobrança automática Sessão 3B funciona
  - Checkout sem consent → cartão NÃO guardado, fallback "cobrar em mão"

---

## Bugs colaterais (Sessão 6/7 housekeeping)

- [ ] **`confirm-mbway-payment` Edge Fn obsoleta** (v11 ACTIVE) — apagar após validar zero traffic
- [ ] **`create-mbway-payment-intent-debug` em prod** (v1 ACTIVE) — apagar; debug não deve estar em LIVE
- [ ] **Schema divergência `orders.final_total` (double precision) vs `orders.customer_total` (numeric)** — investigar dead code; consolidar num único tipo (recomendar `numeric(10,2)`)
- [ ] **`orders.extra_charge_amount` não nullify após charge succeeded** — actualmente fica preenchido para sempre; nullify quando `payment_status` volta a `paid`
- [ ] **`mbway_debug_errors` RLS check** — validar que tabela debug não está exposta a clientes

---

## Notas

- Cap actual `pending_charges.amount_cents BETWEEN 1 AND 50` reflecte política €0.50 max (5 sacos × €0.10).
- Idempotency key format: `${order_id}_bags` (singular `_bags` por order — só pode haver UM charge market_bags por order).
- Se no futuro houver mais `reason` types (ex.: `damaged_item`), key passa a `${order_id}_${reason}`.
- Cron drain só processa `status='pending'` com `created_at < now() - interval '2 minutes'` para dar tempo ao `pg_net` síncrono inicial completar.
