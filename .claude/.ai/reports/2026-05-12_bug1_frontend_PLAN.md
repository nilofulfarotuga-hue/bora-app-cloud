# BUG #1 FRONTEND + COBRANÇA DA DÍVIDA — PLANO

**Data:** 2026-05-12
**Branch:** `autonomous-night-2026-04-29`
**Modelo:** Opus 4.7
**Status:** AGUARDA APROVAÇÃO DANILO

---

## A) PRÉ-REQUISITOS — 5/5 ✅

| # | Check | Resultado |
|---|-------|-----------|
| 1 | RPCs `wallet_debit_cancel_fee` + `wallet_debit_for_order` | ✅ ambos presentes |
| 2 | `client_wallets_free_balance_cents_check` >= `-4000` | ✅ confirmado |
| 3 | Kind `cancel_fee_debit` aceito em `wallet_transactions_kind_check` | ✅ |
| 4 | Edge Functions: `cancel-order-with-choice v11`, `client-cancel-order v19`, `upload-receipt v1`, `stripe-webhook v22` | ✅ |
| 5 | Setting `wallet_cancel_hard_floor_cents = -4000` | ✅ |

**flutter analyze baseline:** 85 issues, 0 errors (info/warning estáveis).

---

## B) SQL — 3 MIGRATIONS

### Migration 1 — `wallet_settle_debt` RPC (NOVA)

```sql
CREATE OR REPLACE FUNCTION public.wallet_settle_debt(
  p_user_id     uuid,
  p_amount_cents integer,
  p_source      text,
  p_idem_key    text
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_balance_after  INTEGER;
  v_was_debt       INTEGER;
  v_surplus        INTEGER;
  v_existing_id    UUID;
BEGIN
  IF p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'amount_must_be_positive';
  END IF;
  IF p_idem_key IS NULL OR length(trim(p_idem_key)) < 3 THEN
    RAISE EXCEPTION 'idem_key_required';
  END IF;

  -- Idempotência via SELECT prévio
  SELECT id INTO v_existing_id
    FROM public.wallet_transactions
    WHERE idempotency_key = p_idem_key
    LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    SELECT free_balance_cents INTO v_balance_after
      FROM public.client_wallets WHERE user_id = p_user_id;
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'settled_cents', p_amount_cents,
      'new_balance_cents', COALESCE(v_balance_after, 0),
      'was_debt_cents', 0,
      'surplus_cents', 0
    );
  END IF;

  -- Garantir wallet + lock
  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_balance_before IS NULL THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  v_was_debt := CASE WHEN v_balance_before < 0 THEN -v_balance_before ELSE 0 END;
  v_balance_after := v_balance_before + p_amount_cents;
  v_surplus := CASE WHEN v_balance_after > 0 AND v_was_debt > 0
                    THEN LEAST(v_balance_after, p_amount_cents - v_was_debt)
                    WHEN v_was_debt = 0 THEN p_amount_cents
                    ELSE 0 END;

  UPDATE public.client_wallets
    SET free_balance_cents = v_balance_after,
        updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.wallet_transactions
    (user_id, amount_cents, kind, reason, balance_after_cents, idempotency_key)
  VALUES
    (p_user_id, p_amount_cents, 'settlement',
     'Pagamento de dívida (' || p_source || ')',
     v_balance_after, p_idem_key);

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'settled_cents', p_amount_cents,
    'new_balance_cents', v_balance_after,
    'was_debt_cents', v_was_debt,
    'surplus_cents', v_surplus
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.wallet_settle_debt(uuid, integer, text, text) TO service_role;

COMMENT ON FUNCTION public.wallet_settle_debt IS
'Liquida dívida wallet (kind=settlement). Aceita amount > dívida (excedente = saldo positivo). Idempotente via idempotency_key. Service-role only (stripe-webhook + trigger apply_client_debt_settlement_on_cash_delivery).';
```

### Migration 2 — `quote_order_pricing` modificada (campo `include_debt`)

Mudança mínima — apenas adiciona suporte ao flag opcional. RPC completa via `CREATE OR REPLACE FUNCTION` (não suporta ALTER granular):

```sql
CREATE OR REPLACE FUNCTION public.quote_order_pricing(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id            UUID := auth.uid();
  v_service_type       TEXT;
  v_distance_km        NUMERIC;
  v_is_partner_store   BOOLEAN;
  v_apartment_delivery BOOLEAN;
  v_subtotal_input     NUMERIC;
  v_subtotal_server    NUMERIC;
  v_pricing            RECORD;
  v_product_lines      JSONB;
  v_line               JSONB;
  v_wallet_cents       INTEGER;
  v_wallet_eur         NUMERIC;
  v_charge_total       NUMERIC;
  v_max_wallet_cents   INTEGER;
  v_balance_check      INTEGER;
  v_buffer_total       NUMERIC;
  v_include_debt       BOOLEAN;  -- NOVO 2026-05-12
  v_debt_cents         INTEGER := 0;  -- NOVO
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  v_service_type       := COALESCE(p_input->>'service_type', '');
  v_distance_km        := COALESCE((p_input->>'distance_km')::NUMERIC, 1);
  v_is_partner_store   := COALESCE((p_input->>'is_partner_store')::BOOLEAN, FALSE);
  v_apartment_delivery := COALESCE((p_input->>'apartment_delivery')::BOOLEAN, FALSE);
  v_subtotal_input     := COALESCE((p_input->>'subtotal')::NUMERIC, 0);
  v_product_lines      := p_input->'product_lines';
  v_wallet_cents       := COALESCE((p_input->>'wallet_applied_cents')::INTEGER, 0);
  v_include_debt       := COALESCE((p_input->>'include_debt')::BOOLEAN, FALSE);  -- NOVO

  IF v_service_type NOT IN ('restaurant','storeShopping','carryGroceries','sendPackage') THEN
    RAISE EXCEPTION 'INVALID_SERVICE_TYPE: %', v_service_type;
  END IF;

  IF v_wallet_cents > 0 THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id;
    IF v_balance_check IS NULL OR v_balance_check < v_wallet_cents THEN
      RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE: have=%, need=%',
        COALESCE(v_balance_check, 0), v_wallet_cents
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_service_type IN ('restaurant','storeShopping')
     AND v_product_lines IS NOT NULL
     AND jsonb_typeof(v_product_lines) = 'array'
     AND jsonb_array_length(v_product_lines) > 0
  THEN
    v_subtotal_server := 0;
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_product_lines)
    LOOP
      v_subtotal_server := v_subtotal_server + (
        COALESCE(
          (SELECT p.price FROM products p WHERE p.id = (v_line->>'product_id') LIMIT 1),
          (v_line->>'unit_price')::NUMERIC, 0
        ) * COALESCE((v_line->>'quantity')::NUMERIC, 1)
      );
    END LOOP;
    IF NOT v_is_partner_store THEN
      v_subtotal_server := v_subtotal_server * 1.15;
    END IF;
    v_subtotal_server := ROUND(v_subtotal_server::numeric, 2);
  ELSE
    v_subtotal_server := ROUND(v_subtotal_input::numeric, 2);
  END IF;

  SELECT * INTO v_pricing FROM pricing_calculate(
    v_service_type, v_subtotal_server, v_distance_km,
    v_is_partner_store, v_apartment_delivery, FALSE
  );

  v_max_wallet_cents := ROUND(v_pricing.customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN
    v_wallet_cents := v_max_wallet_cents;
  END IF;
  v_wallet_eur := v_wallet_cents / 100.0;

  v_charge_total := v_pricing.customer_total - v_wallet_eur;

  -- ⭐ NOVO 2026-05-12: incluir dívida wallet no charge_total + buffer
  IF v_include_debt THEN
    SELECT free_balance_cents INTO v_balance_check
      FROM client_wallets WHERE user_id = v_user_id;
    IF v_balance_check IS NOT NULL AND v_balance_check < 0 THEN
      v_debt_cents := -v_balance_check;
      v_charge_total := v_charge_total + (v_debt_cents::numeric / 100);
    END IF;
  END IF;

  IF (v_service_type IN ('restaurant','storeShopping')) AND NOT v_is_partner_store THEN
    v_buffer_total := ROUND((v_charge_total * 1.15)::numeric, 2);
  ELSE
    v_buffer_total := v_charge_total;
  END IF;

  RETURN jsonb_build_object(
    'price', v_pricing.customer_total,
    'subtotal', v_subtotal_server,
    'delivery_fee', v_pricing.delivery_fee,
    'service_fee', v_pricing.service_fee,
    'platform_commission', v_pricing.platform_commission,
    'driver_earnings', v_pricing.driver_earnings,
    'bag_fee', v_pricing.bag_fee,
    'apartment_surcharge', CASE WHEN v_apartment_delivery THEN 1.50 ELSE 0 END,
    'payment_buffer_total', v_buffer_total,
    'customer_total', v_pricing.customer_total,
    'wallet_applied_cents', v_wallet_cents,
    'charge_total', v_charge_total,
    'fully_paid_by_wallet', v_charge_total <= 0,
    'debt_settle_cents', v_debt_cents  -- ⭐ NOVO
  );
END;
$function$;
```

**Retro-compat:** input sem `include_debt` → `v_include_debt=FALSE` → `v_debt_cents=0` → comportamento idêntico ao actual + campo extra `debt_settle_cents:0` no return (additive, não-breaking).

### Migration 3 — Trigger `apply_client_debt_settlement_on_cash_delivery`

```sql
CREATE OR REPLACE FUNCTION public.fn_apply_client_debt_settlement_on_cash_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_balance INTEGER;
  v_debt    INTEGER;
BEGIN
  BEGIN
    SELECT free_balance_cents INTO v_balance
      FROM client_wallets WHERE user_id = NEW.user_id FOR UPDATE;

    IF v_balance IS NULL OR v_balance >= 0 THEN
      RETURN NEW;
    END IF;

    v_debt := -v_balance;

    PERFORM wallet_settle_debt(
      NEW.user_id, v_debt, 'cash_delivery',
      'settle_cash_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    -- Defensivo: NUNCA bloquear o UPDATE de status do pedido
    RAISE WARNING 'apply_client_debt_settlement_on_cash_delivery failed for order %: %',
      NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER apply_client_debt_settlement_on_cash_delivery
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered'
        AND OLD.status IS DISTINCT FROM 'delivered'
        AND NEW.payment_method = 'cash')
  EXECUTE FUNCTION fn_apply_client_debt_settlement_on_cash_delivery();
```

**Ordem alfabética:** `apply_client_*` (este) corre ANTES de `apply_driver_cash_settlement`. Tabelas independentes (`client_wallets` vs `driver_balances`) → **zero conflito**.

---

## C) EDGE FUNCTION NOVA — `pay-debt-standalone` v1

```ts
// supabase/functions/pay-debt-standalone/index.ts
// v1 (2026-05-12 — BUG #1 frontend): standalone PI para liquidar dívida wallet.
// Suporta card + MBWay. webhook.stripe-webhook detecta metadata e settle automaticamente.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: 'server_misconfigured' }, 500);

  let amountCents: number | undefined;
  let paymentMethod: 'card' | 'mbway' = 'card';
  let mbwayPhone: string | undefined;
  try {
    const body = await req.json();
    amountCents = Number(body?.amount_cents);
    if (body?.payment_method === 'mbway') paymentMethod = 'mbway';
    mbwayPhone = body?.mbway_phone;
  } catch (_) {
    return json({ error: 'invalid_body' }, 400);
  }
  if (!Number.isFinite(amountCents!) || amountCents! < 50) {
    return json({ error: 'amount_must_be_at_least_50_cents' }, 400);
  }
  if (paymentMethod === 'mbway' && (!mbwayPhone || !/^\+?351\d{9}$/.test(mbwayPhone))) {
    return json({ error: 'mbway_phone_required_e164_pt' }, 400);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized' }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: wallet, error: walletErr } = await admin
    .from('client_wallets')
    .select('free_balance_cents')
    .eq('user_id', user.id)
    .maybeSingle();
  if (walletErr) return json({ error: 'wallet_lookup_failed', details: walletErr.message }, 500);

  const balance = wallet?.free_balance_cents ?? 0;
  const debtAbs = balance < 0 ? -balance : 0;

  if (debtAbs === 0) return json({ error: 'no_debt_to_settle' }, 409);
  if (debtAbs < 50) return json({ error: 'debt_below_stripe_minimum', debt_cents: debtAbs }, 409);
  if (amountCents! < debtAbs) {
    return json({ error: 'amount_below_debt', debt_cents: debtAbs }, 409);
  }

  try {
    const piParams: Stripe.PaymentIntentCreateParams = {
      amount: amountCents!,
      currency: 'eur',
      payment_method_types: paymentMethod === 'mbway' ? ['multibanco'] : ['card'],
      metadata: {
        standalone_debt_settle: 'true',
        debt_settle_cents: String(amountCents),
        user_id: user.id,
        source: 'pay-debt-standalone',
      },
    };
    const pi = await stripe.paymentIntents.create(piParams, {
      idempotencyKey: `paydebt-${user.id}-${amountCents}-${Date.now()}`,
    });

    if (paymentMethod === 'mbway' && mbwayPhone) {
      // Espelho do pattern create-mbway-payment-intent: confirmar server-side
      await stripe.paymentIntents.confirm(pi.id, {
        payment_method_data: {
          type: 'multibanco',
          billing_details: { phone: mbwayPhone, email: user.email ?? undefined },
        },
      });
    }

    return json({
      clientSecret: pi.client_secret,
      paymentIntentId: pi.id,
      mode: paymentMethod,
      debt_cents: debtAbs,
      amount_cents: amountCents,
    });
  } catch (e: any) {
    console.error('[pay-debt-standalone] stripe failed:', e);
    return json({ error: 'stripe_pi_create_failed', details: String(e?.message ?? e) }, 502);
  }
});
```

**JWT verify:** ON. Aceita `payment_method: 'card'|'mbway'`. MBWay requer `mbway_phone` formato `+351XXXXXXXXX`.

---

## D) DIFF EXACTO `stripe-webhook` v22 → v23 (puramente aditivo)

**Mudanças:** 1 bloco aditivo (15 linhas) dentro de `case 'payment_intent.succeeded'`. **ZERO linhas removidas.**

```ts
case 'payment_intent.succeeded': {
  const intent = event.data.object as Stripe.PaymentIntent;
+
+ // ⭐ NOVO (2026-05-12 BUG #1 frontend) — debt settle via metadata.debt_settle_cents
+ const debtSettleCents = parseInt(intent.metadata?.debt_settle_cents ?? '0');
+ const piUserId = intent.metadata?.user_id;
+ if (debtSettleCents > 0 && piUserId) {
+   const { error: settleErr } = await supabase.rpc('wallet_settle_debt', {
+     p_user_id: piUserId,
+     p_amount_cents: debtSettleCents,
+     p_source: 'stripe_pi',
+     p_idem_key: 'settle_pi_' + intent.id,
+   });
+   if (settleErr) {
+     console.error('[stripe-webhook] wallet_settle_debt failed:', settleErr.message, intent.id);
+   } else {
+     console.log('[stripe-webhook] debt settled:', piUserId, debtSettleCents, intent.id);
+   }
+ }
+ // ⭐ NOVO — standalone debt-only PI: parar aqui (não há pedido)
+ if (intent.metadata?.standalone_debt_settle === 'true') {
+   break;
+ }
+
  const draft_id = intent.metadata?.draft_id;
  const order_id = intent.metadata?.order_id;
  // ... resto IDÊNTICO
}
```

Cases `processing`, `payment_failed`, `canceled`, `charge.refunded` **0% modificados**.

---

## E) FLUTTER — 7 ficheiros tocados

| # | Ficheiro | Tipo | Mudança |
|---|----------|------|---------|
| 1 | `lib/stores/cart_store.dart` | Edit | Linha ~190-201: adicionar `'include_debt': true` no `cartInput`. Adicionar `debt_settle_cents` ao return type cache. |
| 2 | `lib/services/wallet_service.dart` | Edit | (a) Adicionar método `payDebtStandalone({required int amountCents, required String paymentMethod, String? mbwayPhone})` → invoke `pay-debt-standalone`. (b) Adicionar case `'cancel_fee_debit'` no `WalletTx.kindLabel` → `'Taxa de cancelamento'`. (c) Actualizar comment `WalletConstants` (referenciar 2 hard floors). |
| 3 | `lib/services/payment_service.dart` | Edit | Adicionar método `payDebtViaSheet(int amountCents)` que chama `pay-debt-standalone` + `initPaymentSheet` + `presentPaymentSheet` (espelha pattern existente do checkout). |
| 4 | `lib/screens/payment_method_screen.dart` | Edit | (a) Mostrar linha "Dívida anterior: €X.XX" (vermelho) se `debt_settle_cents > 0`. (b) Calcular `total_cash_with_debt = customer_total + debt_settle_cents/100`. (c) Se `total_cash_with_debt > 40`: opção CASH disabled (Opacity 0.4 + tooltip PT-PT). Cartão/MBWay sempre activos. (d) Total final inclui dívida. |
| 5 | `lib/screens/wallet_history_screen.dart` | Edit | (a) Header: se `balance.isNegative` → mostrar valor em VERMELHO + texto `"⚠️ Dívida pendente €X.XX"`. (b) Botão "Pagar dívida agora" (visível só se `debtCents >= 50`). Se `debtCents < 50`: texto pequeno `"Dívida menor que €0.50 — será cobrada no próximo pedido."`. (c) Botão abre nova modal. |
| 6 | `lib/widgets/pay_debt_modal.dart` | **CREATE** | Novo widget StatefulWidget. Layout: opção `Pagar dívida (€X.XX)` (default) vs `Pagar mais [input] €`. Selector Cartão/MBWay (campo phone se MBWay). Valida input >= dívida + 1 cent. Confirmar → chama `WalletService.payDebtStandalone` + `PaymentService.payDebtViaSheet`. Após sucesso: refresh wallet + snackbar com surplus (se houve). |
| 7 | `lib/screens/cart_screen.dart` | Edit | (revisar) Se houver linha de total, garantir que mostra `debt_settle_cents`. Provavelmente não-tocado se total já lê de `quoteOrderPricing` cache. |

**Cores Bora:** texto dívida em `Colors.red.shade700`. Botões: verde `#1B5E20` (primary) / laranja `#E65100` (acção secundária).

---

## F) SYNC REPO

- 3 migrations: `supabase/migrations/20260512100001..03_*.sql`
- 1 nova Edge Function: `supabase/functions/pay-debt-standalone/index.ts` + `_shared/cors.ts` (já existe)
- 1 Edge Function modificada: `supabase/functions/stripe-webhook/index.ts` (v23)
- 6 Flutter Edit + 1 Flutter Create (7 ficheiros)

---

## G) `business_rules.md` — §54

Adicionar nova secção `## §54 — COBRANÇA DA DÍVIDA NO CHECKOUT (2026-05-12)`:

```
Dívida wallet (free_balance_cents < 0) é cobrada por 3 mecanismos:

1. **Próximo pedido CASH**:
   - Frontend: opção CASH desabilitada se total_pedido + dívida > €40 (limite hardcoded enforce_cash_payment_limit)
   - Backend: trigger apply_client_debt_settlement_on_cash_delivery dispara em status=delivered + payment_method=cash → chama wallet_settle_debt → wallet=0
   - Estafeta recebe TOTAL+dívida na entrega (em dinheiro)

2. **Próximo pedido Cartão/MBWay**:
   - Frontend envia include_debt:true no quote_order_pricing
   - quote_order_pricing soma debt_cents ao charge_total + payment_buffer_total
   - PI metadata.debt_settle_cents = abs(balance)
   - Webhook stripe-webhook v23 detecta metadata → chama wallet_settle_debt → wallet=0
   - Pedido prossegue normalmente (finalize via draft_id existente)

3. **Standalone "Pagar dívida agora"**:
   - Tela Saldo Bora → botão (visível se debt >= €0.50)
   - Modal PayDebtModal: cliente escolhe valor + método (card/MBWay)
   - Edge Function pay-debt-standalone v1 cria PI com metadata.standalone_debt_settle=true
   - Webhook detecta → settle → break (não há pedido)

**Guard Stripe min €0.50**:
- Se dívida < 50 cents: standalone NÃO disponível (UI esconde botão + texto "Dívida menor que €0.50 — será cobrada no próximo pedido"). Cobrança automática no próximo checkout (mecanismos 1 ou 2).

**Idempotência**:
- wallet_settle_debt usa idempotency_key construída pelo caller:
  - 'settle_cash_' || order_id (trigger CASH)
  - 'settle_pi_' || payment_intent.id (webhook)
- Reentregas Stripe não duplicam settle (SELECT prévio retorna idempotent:true).

**Surplus**:
- wallet_settle_debt aceita amount > debt. Excedente vira saldo positivo (100% para free_balance_cents — NÃO regra 80/20).
- UI modal mostra "Dívida paga! Tens €X em saldo." se houve surplus.

**12 kinds wallet_transactions** (§53):
- settlement (existia) — agora também usada por trigger CASH + webhook PI
- cancel_fee_debit (§53) — débito por cancelamento
- Resto inalterado.
```

---

## EXECUÇÃO (após aprovação)

1. Apply migration 1 (RPC settle)
2. Apply migration 2 (quote_order_pricing)
3. Apply migration 3 (trigger)
4. Validar 6 testes SQL (idempotência, surplus, retro-compat quote, trigger activo)
5. Deploy `pay-debt-standalone` v1
6. Deploy `stripe-webhook` v23
7. Write 3 migrations locais + 2 Edge Functions source
8. Edit 6 Flutter + Create 1 Flutter widget
9. `flutter analyze` — 0 novos errors (baseline 85 issues)
10. Edit `business_rules.md` §54
11. **11 commits granulares**
12. **NÃO push** — confirmar Danilo

---

## ⚠️ ÁREAS PROIBIDAS RESPEITADAS

- ✅ `dispatch-engine`, `create-payment-intent` v27, `create-mbway-payment-intent` v19, `finalize-order-from-intent` v7, `refund`, `cancel-order-with-choice` v11, `client-cancel-order` v19, `upload-receipt` v1, `upload-avatar` — **não tocados**
- ✅ 17 triggers em `orders` — só leitura; **novo trigger é adição paralela**
- ✅ `apply_driver_cash_settlement` — não tocado (paralelo)
- ✅ `wallet_debit_for_order`, `wallet_debit_cancel_fee`, `wallet_credit_refund_split`, `admin_forgive_wallet_debt` — não tocados
- ✅ Settings `wallet_hard_floor_cents` (-2000) e `wallet_cancel_hard_floor_cents` (-4000) — não tocados
- ✅ Fluxo parceiro — não tocado

**Única excepção aprovada:** `stripe-webhook` v22 → v23, modificação puramente aditiva (15 linhas dentro de `case 'payment_intent.succeeded'`).

---

**FIM DO PLANO — AGUARDA APROVAÇÃO**
