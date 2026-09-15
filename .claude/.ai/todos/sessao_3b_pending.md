# Sessão 3B-NOVA — TODOs Pendentes (pós-deploy)

**Sessão fechada:** 2026-05-04
**Branch:** autonomous-night-2026-04-29
**Estado:** Wallet com saldo negativo deployada em prod (kill-switch `wallet_negative_enabled=true`).

---

## ⛔ ABANDONADO — Stripe off_session

Decisão Danilo 2026-05-04: solução escolhida foi **wallet com saldo negativo**.
NÃO trabalhar nisto:
- Rewrite `charge-extra` Edge Fn com off_session
- `setup_future_usage` em PaymentIntent inicial
- Webhook handler `market_bags`
- Coluna `stripe_customer_id` em `users`
- Termos legais para guardar método de pagamento

---

## 🔄 Próximas sessões podem decidir

### `pending_charges` table (Sessão 6/7)
- Criada na Sessão 3 (commit anterior), zero rows.
- Wallet negativa substituiu o caso de uso.
- Decidir: **manter inactiva** OU `DROP TABLE` se confirmadamente sem uso.

### Push templates (B13 — diferido)
- `notify-client` Edge Fn existe e está funcional.
- Templates desejados (cliente):
  - "Sacos extras: €X descontados. Carteira: −€Y (cobrado próxima compra)"
  - "Saldo regularizado. Obrigado!"
  - "A sua carteira tem dívida pendente há 90 dias"
- Pontos de invocação (server-side, dentro das RPCs Sessão 3B):
  - `wallet_apply_post_delivery_adjustment` quando `crossed_zero=true` → push 1
  - `create_order` settlement bem-sucedido → push 2
  - `pg_cron wallet_overdue_alerts` → push 3 (broadcast a admins)
- **Bloqueio actual:** Sessão 1B push (Firebase keys server-side) ainda não validado em prod.
  Quando confirmado, adicionar trigger `pg_net.http_post` ou usar `select net.http_post(...)`
  dentro das RPCs.

### Stripe Customer Portal (futuro)
- Cliente liquidar dívida via portal externo (sem usar app).
- Setup de Stripe Customer (vem por separado quando passar regime IVA normal).

### Refund parcial wallet (futuro)
- Refund actual abate dívida primeiro + split 80/20 do resto (já implementado).
- Cliente escolher refund parcial em vez de cancelamento total — fora escopo.

### Reset users.last_order_at (futuro performance)
- Actualmente pg_cron 09:00 UTC faz `MAX(orders.created_at)` por wallet negativa.
- Se base crescer (>10k clientes), considerar materializar `users.last_order_at`
  via trigger AFTER INSERT em `orders`.

### Regime IVA normal (futuro fiscal)
- Quando facturação anual ultrapassar **€15.000** (regime Art. 53.º expira), terá
  que emitir factura/nota débito para cada `wallet_transactions` com `kind='debit'`.
- Confirmar com contabilista pipeline:
  1. RPC `wallet_apply_post_delivery_adjustment` insere "nota interna"
  2. Próximo create_order → factura inclui "Liquidação dívida anterior" como linha
  3. Sistema gera nota crédito quando admin perdoa

---

## 🐛 Bugs colaterais reportados

### Da Sessão 3 (mantidos):
- `confirm-mbway-payment` Edge Fn obsoleta — apagar após confirmação prod
- `create-mbway-payment-intent-debug` em prod — apagar
- `final_total` (double) vs `customer_total` (numeric) — uniformizar tipo
- `extra_charge_amount` não nullify após charge bem-sucedido

### Novos (Sessão 3B):
- Memória CLAUDE auto: "5 pending non-partner restaurants" → real é 0 (todos aprovados).
  → Limpar memory `project_dual_driver_signup.md` se relevante.
- Memória CLAUDE auto: "7 reservation RPCs prod" → real é 6.
  Não bloqueia. Confirmar se nome 7º RPC mudou ou foi removido em sessão anterior.
