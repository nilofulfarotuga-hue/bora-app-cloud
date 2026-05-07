# BUGs encontrados durante testes E2E

Política: tests legítimos que falham NÃO bloqueiam merge.
Cada FAIL → entrada aqui + fix em sessão dedicada futura.
CEO-AI orchestrator vê via sync Obsidian
(`.obsidian-vault/sessoes/07e_b_bugs.md`).

---

## Sessão 7E-B (2026-05-07) — 25/26 PASS + 5 BUGs

### Nota numeração

**BUG-7E-B-002 saltado** — entry intermédio reclassificado durante o run
(`assert_bag_fee_restaurant_fixed_30c`: bag fee restaurante €0.30 fixo
**não é bug** — é a regra documentada em
`platform_settings.bag_fee_restaurant_cents=30`. A interpretação inicial
"€0.30 × bag_count" do prompt original foi erro de leitura).

---

### BUG-7E-B-001 (LOW) — Cash limit DOCS_VS_CODE mismatch

- **Test:** T04 `test_t04_cash_at_limit_passes` / `test_t04_cash_above_limit_fails`
- **Esperado:** `business_rules.ts` declara `CASH_MAX_ORDER_VALUE_EUR=30.00`.
- **Real:** trigger SQL `enforce_cash_payment_limit` +
  `platform_settings.max_cash_amount_cents=4000` enforça **€40**.
- **RPC/Edge Fn:** trigger `enforce_cash_payment_limit` em `orders`.
- **Severidade:** LOW.
- **Acção sugerida:** confirmar valor real com Danilo e harmonizar — ou
  actualizar `business_rules.ts` (€30 → €40), ou alterar setting DB
  (€40 → €30).

---

### BUG-7E-B-003 (LOW) — `storeShopping` retorna `bag_fee=0`

- **Test:** T06 `test_t06_storeshopping_bag_fee_zero`
- **Esperado:** regra antiga em `business_rules.ts` dizia €0.10/saco
  para mercados.
- **Real:** `pricing_calculate` devolve `bag_fee=€0.00` sempre que
  `service_type='storeShopping'` (CASE só cobre `restaurant`).
- **RPC/Edge Fn:** `pricing_calculate` (linha
  `v_bag_fee := CASE WHEN p_service_type = 'restaurant' ... ELSE 0 END`).
- **Severidade:** LOW.
- **Acção sugerida:** decidir se a regra €0.10/saco em mercados
  permanece — actualizar `business_rules.md` para 0.00 ou implementar
  o cálculo no RPC.

---

### BUG-7E-B-004 (HIGH) — Estafeta consegue cancelar `pickedUp`

- **Test:** T37 `test_t37_driver_can_cancel_pickedup_bug_004`
- **Esperado:** decisão Danilo (2026-05-07) — bloquear `pickedUp` e
  redirigir o estafeta para suporte.
- **Real:** `business_rules.md §7.7` documenta explicitamente
  "Pode cancelar em `driverAccepted` ou `pickedUp`"; RPC
  `driver_cancel_order` aceita ambos os status.
- **Comportamento ACTUAL:** `ok=true` em `pickedUp` + status volta a
  `callingDriver`.
- **RPC/Edge Fn:** `driver_cancel_order`.
- **Severidade:** HIGH (impacto UX + regras de negócio).
- **Acção sugerida (3 fixes):**
  1. RPC `driver_cancel_order`: `WHERE status = 'driverAccepted'`
     (remover `pickedUp`).
  2. Actualizar `business_rules.md §7.7`.
  3. UI estafeta (Flutter): substituir botão "Cancelar" por
     "Contactar suporte" quando `status='pickedUp'`.

---

### BUG-7E-B-005 (HIGH) — Tokens conversion factor ×20 (deveria ×2)

- **Test:** T24 `test_t24_tokens_conversion_factor_20`
- **Esperado:** decisão Danilo (2026-05-07) — factor ×2
  (200c → 400 tokens, valor €2).
- **Real:** corpo da RPC `wallet_credit_refund_split`:
  `v_tokens_count := v_tokens_amount * 20`.
- **Implicação:** 200c → 4000 tokens (valor €20 = bonus 10×).
- **RPC/Edge Fn:** `wallet_credit_refund_split`.
- **Severidade:** HIGH (impacto financeiro directo).
- **Acção sugerida:**
  1. Fix RPC: `× 20` → `× 2`.
  2. Actualizar `business_rules.md §28.6` se a regra mudar.
  3. Considerar migração compensatória se algum utilizador real já
     recebeu refund com factor antigo.

---

### BUG-7E-B-006 (MEDIUM) — Stripe webhook fee mismatch

- **Esperado:** tabela `business_rules.md §8.3` diz fee
  `before_dispatch=€1.00`.
- **Real:** comentário em `stripe-webhook` Edge Fn diz
  `CANCEL_FEE_BEFORE_DISPATCH_EUR=1.50`. Ficheiro `_shared/business_rules.ts`
  declara `1.00`. Comentário isolado no webhook fica desalinhado.
- **RPC/Edge Fn:** `stripe-webhook` Edge Fn.
- **Severidade:** MEDIUM (comentário cosmético, não afecta valor real).
- **Acção sugerida:** corrigir o comentário ou clarificar contexto fora
  de 7E-B.

---

### BUG-7E-B-007 (HIGH) — `add_tokens` silent fail em `wallet_credit_refund_split`

- **Test:** T22 `test_t22_refund_split_zero_balance` (FAIL persistente
  após 4 runs).
- **Esperado:** refund €10 (1000c) → 4000 tokens criados em
  `bora_tokens` para o cliente.
- **Real (validado MCP isoladamente):**
  - RPC devolve `tokens_count=4000`, `success=true`.
  - `bora_tokens` fica VAZIA (0 rows após a chamada).
  - `get_user_tokens()` devolve 0.
  - `wallet_get_balance.tokens_balance` continua 0 → assert falha.
- **Hipótese causa:**
  - O bloco `BEGIN PERFORM public.add_tokens(...) EXCEPTION WHEN OTHERS THEN
    RAISE WARNING` no body de `wallet_credit_refund_split` está a engolir
    o erro real.
  - Possível RLS em `bora_tokens` rejeita INSERT (mesmo com
    SECURITY DEFINER) ou `add_tokens` tem `ON CONFLICT DO NOTHING` numa
    UNIQUE que está a matchar.
- **RPC/Edge Fn:** `wallet_credit_refund_split` + `add_tokens`.
- **Severidade:** HIGH (refund tokens reais não estão a ser creditados).
- **Acção sugerida:**
  1. Remover try/except no `PERFORM add_tokens` para expor o `SQLERRM`.
  2. Investigar causa (RLS `bora_tokens`? UNIQUE de
     `(source_order_id, role)` a matchar?).
  3. Validar fix end-to-end: refund €10 → 1 row em `bora_tokens` com
     `amount=4000` (ou `=400` após BUG-005 fix).

---

## Tests adiados — 7E-C

- `cancel-order-with-choice` + `execute-cancellation` (workflow
  cliente → admin via `cancellation_requests`).
- Refund completo split wallet 80/20 + cartão Stripe live.
- Promo balance non-cumulative / 60 d expiry — mover para tokens
  equivalente.

---

*Última actualização: 2026-05-07 — fim Sessão 7E-B*
