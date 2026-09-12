# BUG #1 BACKEND — PLANO DE EXECUÇÃO (MODO PROTECÇÃO TOTAL)

**Data:** 2026-05-12
**Branch:** `autonomous-night-2026-04-29`
**Escopo:** Cancelamento CASH com débito wallet (dívida) em vez de reembolso
**Modelo:** Opus 4.7
**Status:** AGUARDA APROVAÇÃO DANILO — não executar nada antes.

---

## PRE-FLIGHT (executado)

- `git status -s` → modificações pequenas em .claude/settings.json + hooks + maestro/config.yaml + supabase/.temp + reports novos (esperado)
- `git branch --show-current` → `autonomous-night-2026-04-29` ✅
- `git log --oneline -5` → último commit `f574ab8 docs(session): exec upload-receipt …` ✅
- `flutter analyze` → 0 errors (info/warning baseline) ✅
- MCP read-only OK (5 queries)

---

## A) ANÁLISE DOS 17 TRIGGERS EM `orders` PARA TRANSIÇÃO → `cancelled`

UPDATE payload mínimo (apenas estes campos):
`status`, `cancel_reason`, `cancel_fee`, `cancelled_at`, `payment_status`, `cancellation_initiator`
(+ opcional: `refund_amount`, `refund_method`, `refund_status` — só no caminho Stripe/MBWay-PAGO, **não** no caminho CASH)

| # | Trigger | Quando dispara | Status='cancelled'? | Classificação | Notas |
|---|---|---|---|---|---|
| 1 | `orders_auto_confirm_cod` | BEFORE UPDATE OF status WHEN status='delivered' | NÃO | **SAFE** | Filtro WHEN exclui cancelled |
| 2 | `orders_cash_settlement` | AFTER UPDATE OF status WHEN status='delivered' AND payment=cash | NÃO | **SAFE** | Filtro WHEN exclui cancelled |
| 3 | `orders_enforce_cash_limit` | BEFORE INSERT/UPDATE OF payment_method,price,final_total | NÃO | **SAFE** | Não tocamos nesses 3 campos |
| 4 | `orders_enforce_payment_before_preparing` | BEFORE UPDATE (sempre) | DISPARA | **RELEVANTE-OK** | Inspeccionado: tem `IF NEW.status='cancelled' THEN RETURN NEW;` explícito ✅ |
| 5 | `orders_financial_lock` | BEFORE UPDATE (sempre) | DISPARA | **RELEVANTE-OK** | Função `enforce_financial_immutability`: 1º guard `auth.role()<>'service_role'`. Edge Function usa service_role → bypass total. cancel_fee NÃO na lista bloqueada de qualquer forma ✅ |
| 6 | `orders_financial_split` | AFTER UPDATE OF status WHEN delivered+paid+partner | NÃO | **SAFE** | Filtro WHEN exclui cancelled |
| 7 | `orders_post_to_ledger` | AFTER UPDATE OF status WHEN delivered+paid | NÃO | **SAFE** | Filtro WHEN exclui cancelled |
| 8 | `orders_set_delivered_at` | BEFORE UPDATE (sempre) | DISPARA | **RELEVANTE-OK** | Só seta `delivered_at` quando status muda para delivered; cancelled é no-op |
| 9 | `orders_storeshopping_pickup_guard` | BEFORE UPDATE (sempre) | DISPARA | **RELEVANTE-OK** | Função: só dispara WHEN `NEW.status IN ('pickedUp','onTheWay')`. cancelled passa ✅ |
| 10 | `trg_award_tokens_on_delivery` | AFTER UPDATE OF status | DISPARA | **RELEVANTE-OK** | Função filtra delivered internamente; cancelled é no-op |
| 11 | `trg_dispatch_on_calling_driver` | AFTER INSERT/UPDATE OF status | DISPARA | **RELEVANTE-OK** | Função filtra `status='callingDriver'`; cancelled é no-op |
| 12 | `trg_dispatch_on_rejection` | AFTER UPDATE WHEN current_driver_offer_id changes | NÃO | **SAFE** | Não tocamos nesse campo |
| 13 | `trg_enforce_refund_cap` | BEFORE UPDATE OF refund_amount | Apenas se refund_amount muda | **RELEVANTE-OK** | No caminho CASH `refund_amount` NÃO muda (não está no updatePayload). No caminho Stripe-pago já passa hoje |
| 14 | `trg_notify_on_order_cancel` | AFTER UPDATE OF status WHEN status='cancelled' AND old DISTINCT | DISPARA | **RELEVANTE-ESPERADO** | É exactamente o que queremos (push ao cliente). Já existe e funciona |
| 15 | `trg_referral_reward` | AFTER UPDATE OF status WHEN delivered | NÃO | **SAFE** | Filtro WHEN exclui cancelled |
| 16 | `trg_zz_set_purchase_flow_version` | BEFORE INSERT | NÃO | **SAFE** | INSERT-only |
| 17 | `trigger_credit_driver_on_delivery` | AFTER UPDATE OF status | DISPARA | **RELEVANTE-OK** | Função filtra delivered; cancelled é no-op |

**Conclusão:** 0 triggers em RISCO. Caminho CASH cancelado é seguro com payload proposto.

---

## B) SQL EXACTO DAS 4 MIGRATIONS

### Migration 1 — `20260512_001_wallet_cancel_hard_floor_setting.sql`

```sql
-- Hard floor wallet APENAS para cancelamento CASH after_pickup (até €40 negativo).
-- Ajustes/sacos continuam a usar wallet_hard_floor_cents (€20).
INSERT INTO public.platform_settings (key, value)
VALUES ('wallet_cancel_hard_floor_cents', '-4000'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

COMMENT ON TABLE public.platform_settings IS
'Settings runtime da plataforma. Hard floors wallet: wallet_hard_floor_cents=-2000 (ajustes/sacos), wallet_cancel_hard_floor_cents=-4000 (cancel CASH after_pickup, pior caso €40 limite CASH).';
```

### Migration 2 — `20260512_002_relax_client_wallets_check.sql`

```sql
-- Relaxar CHECK constraint da coluna free_balance_cents.
-- Pior caso absoluto = -4000 cents (€40, limite hardcoded enforce_cash_payment_limit).
-- Cada RPC valida o SEU limite via setting (wallet_debit_for_order vê -2000; wallet_debit_cancel_fee vê -4000).
ALTER TABLE public.client_wallets
  DROP CONSTRAINT IF EXISTS client_wallets_free_balance_cents_check;

ALTER TABLE public.client_wallets
  ADD CONSTRAINT client_wallets_free_balance_cents_check
  CHECK (free_balance_cents >= -4000);

COMMENT ON COLUMN public.client_wallets.free_balance_cents IS
'Saldo livre em cents. Pode ficar negativo (dívida). 2 hard floors via RPC: ajustes -2000 (wallet_debit_for_order), cancel CASH -4000 (wallet_debit_cancel_fee). CHECK relaxado para -4000 (pior caso).';
```

### Migration 3 — `20260512_003_wallet_tx_kind_cancel_fee_debit.sql`

```sql
-- Adicionar 'cancel_fee_debit' ao CHECK de wallet_transactions.kind.
-- Kinds actuais (11) + novo (1) = 12 total.
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_kind_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_kind_check
  CHECK (kind IN (
    'refund_credit_free',
    'refund_credit_tokens',
    'order_payment',
    'admin_grant',
    'admin_revoke',
    'cashback',
    'referral',
    'debit',
    'settlement',
    'adjustment',
    'forgive',
    'cancel_fee_debit'
  ));
```

### Migration 4 — `20260512_004_wallet_debit_cancel_fee_rpc.sql`

```sql
-- RPC débito da taxa de cancelamento (CASH ou MBWay não-pago).
-- Espelha pattern wallet_debit_for_order. Hard floor próprio: wallet_cancel_hard_floor_cents (-4000).
-- Idempotência via idempotency_key = 'cancel_fee_<order_id>'.
CREATE OR REPLACE FUNCTION public.wallet_debit_cancel_fee(
  p_user_id   uuid,
  p_order_id  text,
  p_fee_cents integer,
  p_tier      text
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_balance_after  INTEGER;
  v_hard_floor     INTEGER;
  v_idem_key       TEXT;
  v_existing_id    UUID;
BEGIN
  -- Validações input
  IF p_fee_cents <= 0 THEN
    RAISE EXCEPTION 'fee_must_be_positive';
  END IF;
  IF p_tier NOT IN ('before_dispatch','after_accept','after_pickup') THEN
    RAISE EXCEPTION 'invalid_tier: %', p_tier;
  END IF;

  v_idem_key := 'cancel_fee_' || p_order_id;

  -- Idempotência: se já existe débito para este pedido → retornar sem duplicar
  SELECT id INTO v_existing_id
    FROM public.wallet_transactions
    WHERE idempotency_key = v_idem_key
    LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    SELECT free_balance_cents INTO v_balance_after
      FROM public.client_wallets WHERE user_id = p_user_id;
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'debited_cents', p_fee_cents,
      'new_balance_cents', COALESCE(v_balance_after, 0),
      'tier', p_tier
    );
  END IF;

  -- Ler hard floor específico de cancel (default -4000)
  SELECT COALESCE((value::text)::int, -4000) INTO v_hard_floor
    FROM public.platform_settings WHERE key='wallet_cancel_hard_floor_cents';
  v_hard_floor := COALESCE(v_hard_floor, -4000);

  -- Garantir wallet existe + lock
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_balance_after := COALESCE(v_balance_before, 0) - p_fee_cents;

  IF v_balance_after < v_hard_floor THEN
    RAISE EXCEPTION 'wallet_cancel_hard_floor_exceeded: have=% need=% floor=%',
      COALESCE(v_balance_before, 0), p_fee_cents, v_hard_floor
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.client_wallets
    SET free_balance_cents = v_balance_after,
        updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id,
     balance_after_cents, idempotency_key)
  VALUES
    (p_user_id, -p_fee_cents, 'cancel_fee_debit',
     'Taxa de cancelamento ' || p_tier || ' (pedido ' || p_order_id || ')',
     p_order_id, v_balance_after, v_idem_key);

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'debited_cents', p_fee_cents,
    'new_balance_cents', v_balance_after,
    'tier', p_tier
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_debit_cancel_fee(uuid, text, integer, text) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.wallet_debit_cancel_fee(uuid, text, integer, text) TO service_role;

COMMENT ON FUNCTION public.wallet_debit_cancel_fee IS
'Débito wallet para taxa de cancelamento CASH ou MBWay não-pago. Hard floor próprio: -4000 cents (€40, vs €20 wallet_debit_for_order). Idempotente por idempotency_key=cancel_fee_<order_id>. Service-role only (Edge Functions cancel-order-with-choice e client-cancel-order).';
```

---

## C) DIFF EXACTO — `cancel-order-with-choice` v10 → v11

**Ficheiro:** `supabase/functions/cancel-order-with-choice/index.ts`

**Mudança 1 — substituir bloco `if (nothingToRefund)` (linhas ~98-104 actual):**

ANTES (v10):
```ts
  if (nothingToRefund) {
    console.log('[cancel-with-choice] no payment to refund, simple cancel', {
      orderId, payment_method: order.payment_method, status: order.status,
    });
    chargeMissing = true;
  } else if (refundEur <= 0) {
```

DEPOIS (v11):
```ts
  let cancelFeeDebited = false;
  let cancelFeeDebitResult: any = null;

  if (nothingToRefund) {
    // CASH ou MBWay não-pago → débito wallet (dívida), sem reembolso
    const isUnpaid =
      order.payment_method === 'cash' ||
      (order.payment_method === 'mbway' && order.payment_status !== 'paid');

    if (fee > 0 && isUnpaid) {
      const { data: debitRpc, error: debitErr } = await admin.rpc(
        'wallet_debit_cancel_fee',
        {
          p_user_id: user.id,
          p_order_id: orderId,
          p_fee_cents: Math.round(fee * 100),
          p_tier: t,
        },
      );
      if (debitErr) {
        // Hard floor excedido → cancelar SEM débito + alertar (não bloquear cancelamento)
        console.error('[cancel-with-choice] wallet_debit_cancel_fee failed:', debitErr);
        try {
          await admin.functions.invoke('notify-admin-urgent', {
            body: {
              kind: 'wallet_cancel_floor_exceeded',
              order_id: orderId, user_id: user.id,
              fee_cents: Math.round(fee * 100), tier: t,
              error: debitErr.message,
            },
          });
        } catch (_) { /* fire-and-forget */ }
        chargeMissing = true; // mantém comportamento legado se débito falhar
      } else {
        cancelFeeDebited = true;
        cancelFeeDebitResult = debitRpc;
      }
    } else {
      // Caminho original: pedido sem fee (impossível com tabela actual mas defensivo)
      console.log('[cancel-with-choice] no payment + no fee, simple cancel', {
        orderId, payment_method: order.payment_method, status: order.status,
      });
      chargeMissing = true;
    }
  } else if (refundEur <= 0) {
```

**Mudança 2 — newPaymentStatus (linhas ~134-141):**

ANTES (v10):
```ts
  const newPaymentStatus = chargeMissing
    ? 'cancelled_no_charge'
    : refundEur <= 0
      ? 'refunded'
      : fee > 0
        ? 'partial_refund'
        : 'refunded';
```

DEPOIS (v11):
```ts
  const newPaymentStatus = cancelFeeDebited
    ? 'cancelled_with_debt'
    : chargeMissing
      ? 'cancelled_no_charge'
      : refundEur <= 0
        ? 'refunded'
        : fee > 0
          ? 'partial_refund'
          : 'refunded';
```

**Mudança 3 — updatePayload.cancel_fee (linha ~146):**

ANTES (v10):
```ts
    cancel_fee: nothingToRefund ? 0 : fee,
```

DEPOIS (v11):
```ts
    cancel_fee: cancelFeeDebited ? fee : (nothingToRefund ? 0 : fee),
```

**Mudança 4 — notificação cliente (bloco ~158-180):**

ANTES (v10):
```ts
    if (nothingToRefund) {
      title = 'Pedido cancelado';
      message = 'O pedido foi cancelado. Como ainda não tinhas pago, não há reembolso a processar.';
    } else if (chargeMissing) {
```

DEPOIS (v11):
```ts
    if (cancelFeeDebited) {
      title = 'Pedido cancelado';
      message =
        `Pedido cancelado. Taxa de cancelamento €${fee.toFixed(2)} foi adicionada como dívida na tua conta. ` +
        `Será cobrada no próximo pedido.`;
    } else if (nothingToRefund) {
      title = 'Pedido cancelado';
      message = 'O pedido foi cancelado. Como ainda não tinhas pago, não há reembolso a processar.';
    } else if (chargeMissing) {
```

**Mudança 5 — response final:**

DEPOIS (v11), adicionar campos:
```ts
  return json({
    ok: true,
    tier: t,
    fee_eur: cancelFeeDebited || !nothingToRefund ? fee : 0,
    refund_eur: refundExecuted ? refundEur : 0,
    refund_method: refundExecuted ? refundMethod : null,
    refund_id: stripeRefundId ?? null,
    charge_missing: chargeMissing,
    nothing_to_refund: nothingToRefund,
    cancel_fee_debited: cancelFeeDebited,
    cancel_fee_debit: cancelFeeDebitResult,
    wallet: walletResult,
  });
```

**Mudança 6 — comentário topo do ficheiro:**
```ts
// supabase/functions/cancel-order-with-choice/index.ts
// FIX 2026-05-12: CASH antes de entrega não tem reembolso.
// v11 (2026-05-12 — Bug #1): cancel CASH/MBWay-não-pago → débito wallet (dívida), não simples cancel.
```

---

## D) DIFF EXACTO — `client-cancel-order` v18 → v19

**Ficheiro:** `supabase/functions/client-cancel-order/index.ts`

Mesmo pattern do bloco C aplicado ao `client-cancel-order`, mas mais simples (esta função só faz refund Stripe — não wallet refund). Resumido:

**Mudança 1 — substituir bloco `if (nothingToRefund)` (linhas ~97-99):**

ANTES (v18):
```ts
  if (nothingToRefund) {
    chargeMissing = true;
  } else if (order.payment_method === 'card' && order.payment_intent_id && refundEur > 0) {
```

DEPOIS (v19):
```ts
  let cancelFeeDebited = false;
  let cancelFeeDebitResult: any = null;

  if (nothingToRefund) {
    const isUnpaid =
      order.payment_method === 'cash' ||
      (order.payment_method === 'mbway' && order.payment_status !== 'paid');

    if (feeEur > 0 && isUnpaid) {
      const { data: debitRpc, error: debitErr } = await admin.rpc(
        'wallet_debit_cancel_fee',
        {
          p_user_id: user.id,
          p_order_id: orderId,
          p_fee_cents: Math.round(feeEur * 100),
          p_tier: tier,
        },
      );
      if (debitErr) {
        console.error('[client-cancel] wallet_debit_cancel_fee failed:', debitErr);
        try {
          await admin.functions.invoke('notify-admin-urgent', {
            body: {
              kind: 'wallet_cancel_floor_exceeded',
              order_id: orderId, user_id: user.id,
              fee_cents: Math.round(feeEur * 100), tier,
              error: debitErr.message,
            },
          });
        } catch (_) { /* fire-and-forget */ }
        chargeMissing = true;
      } else {
        cancelFeeDebited = true;
        cancelFeeDebitResult = debitRpc;
      }
    } else {
      chargeMissing = true;
    }
  } else if (order.payment_method === 'card' && order.payment_intent_id && refundEur > 0) {
```

**Mudança 2 — newPaymentStatus (linhas ~131-138):**

ANTES (v18):
```ts
  const newPaymentStatus = chargeMissing
    ? 'cancelled_no_charge'
    : refundEur <= 0
      ? 'refunded'
      : refundExecuted
        ? feeEur > 0 ? 'partial_refund' : 'refunded'
        : 'cancelled_no_charge';
```

DEPOIS (v19):
```ts
  const newPaymentStatus = cancelFeeDebited
    ? 'cancelled_with_debt'
    : chargeMissing
      ? 'cancelled_no_charge'
      : refundEur <= 0
        ? 'refunded'
        : refundExecuted
          ? feeEur > 0 ? 'partial_refund' : 'refunded'
          : 'cancelled_no_charge';
```

**Mudança 3 — updatePayload.cancel_fee:**

ANTES (v18):
```ts
    cancel_fee: nothingToRefund ? 0 : feeEur,
```

DEPOIS (v19):
```ts
    cancel_fee: cancelFeeDebited ? feeEur : (nothingToRefund ? 0 : feeEur),
```

**Mudança 4 — response final (adicionar 2 campos):**
```ts
    cancel_fee_debited: cancelFeeDebited,
    cancel_fee_debit: cancelFeeDebitResult,
```

**Nota:** não vou criar `_shared/cancel_debit.ts` nesta iteração para minimizar superfície de mudança. Duplicar a lógica é aceitável (8 linhas, 2 ficheiros).

---

## E) PLANO SYNC REPO

Após deploys via MCP, sincronizar source local:

1. `supabase/functions/cancel-order-with-choice/index.ts` → conteúdo v11 (overwrite via Write)
2. `supabase/functions/client-cancel-order/index.ts` → conteúdo v19 (overwrite via Write)
3. `supabase/functions/upload-receipt/index.ts` → confirmar igual ao deploy actual (já em sync pelo commit `f574ab8`)
4. `supabase/migrations/20260512_001_*.sql` ... `20260512_004_*.sql` (Write 4 ficheiros)

---

## F) ACTUALIZAÇÃO `business_rules.md`

Adicionar nova secção `## §53 — CANCEL FEE CASH/MBWAY-NÃO-PAGO = DÍVIDA WALLET NEGATIVA (2026-05-12)` no final do ficheiro, com o texto canónico que está no prompt do Danilo.

---

## EXECUÇÃO (após aprovação)

1. `apply_migration` × 4 (na ordem 001 → 002 → 003 → 004)
2. `deploy_edge_function('cancel-order-with-choice', v11)`
3. `deploy_edge_function('client-cancel-order', v19)`
4. `Write` source local 2 Edge Functions + 4 migrations
5. `Edit` business_rules.md §53
6. Validação pós-execução (8 checks SQL no prompt)
7. **7 commits granulares**:
   1. `feat(wallet): add wallet_cancel_hard_floor_cents setting (-4000/€40)`
   2. `fix(wallet): relax client_wallets check constraint to -4000`
   3. `fix(wallet): add cancel_fee_debit kind to wallet_transactions`
   4. `feat(wallet): wallet_debit_cancel_fee RPC (idempotent debit on CASH cancel)`
   5. `fix(edge): cancel-order-with-choice v11 - debit wallet on nothingToRefund (CASH)`
   6. `fix(edge): client-cancel-order v19 - debit wallet on nothingToRefund (CASH)`
   7. `chore(sync): edge functions source from MCP deploys + business_rules §53`
8. **NÃO push automaticamente** — confirmar com Danilo antes

---

## ANOMALIAS / OBSERVAÇÕES FORA DE ESCOPO

Nenhuma divergência encontrada vs achados MCP pré-validados. Tudo coerente.

Observação menor (não-blocking, não-acção): `_shared/platform_settings.ts` tem 2 cópias divergentes entre `cancel-order-with-choice` e `client-cancel-order` (diferença trivial em logging). Já era assim antes — fora de escopo desta sessão.

---

**FIM DO PLANO — AGUARDA APROVAÇÃO DO DANILO**
