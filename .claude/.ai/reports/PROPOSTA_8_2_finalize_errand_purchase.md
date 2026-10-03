# PROPOSTA 8.2 — Consentimento do cliente para overage (errand) — PARA REVISÃO
> 2026-06-22 · NÃO aplicado. Claude.ai aplica o SQL via MCP após aprovação.
> Mini-plano aprovado: timing A · gate só-errand · threshold = buffer (×1.2) · recusa→disputa admin.

## Princípio (porque é cirúrgico)
`payment_buffer_total = fees + round(estimativa × 1.2)`. O `finalize_errand_purchase` já só
dispara `charge-extra` quando `final_total > payment_buffer_total`, ou seja **exatamente quando o
talão excede a estimativa em >20%**. Logo o "threshold ×1.2" já está implementado. O 8.2 só
acrescenta: **esse `charge-extra` passa a exigir consentimento do cliente**; sem consentimento →
**disputa admin** (não cobra nem absorve). Caminho 100% errand; `charge-extra` de outros fluxos
intocado.

---

## PARTE A — SQL (migration nova, NÃO aplicar localmente)
Nome sugerido quando aplicarem: `20260622090000_errand_budget_consent.sql`

```sql
-- 8.2 — Consentimento do cliente para compra acima do buffer (errand). ADITIVO.
-- NÃO toca pricing/create_order/dispatch/tokens. Só o caminho errand.

-- 1) Estado do pedido de aumento ------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS errand_budget_status        text,   -- null|pending|approved|rejected|disputed
  ADD COLUMN IF NOT EXISTS errand_budget_requested_cents integer;

-- 2) Estafeta pede aumento ANTES de comprar (timing A) --------------------
CREATE OR REPLACE FUNCTION public.errand_request_budget_increase(
  p_order_id text,
  p_new_total_cents integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'auth'
AS $$
DECLARE
  v_order RECORD;
  v_url text;
  v_key text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;
  IF p_new_total_cents IS NULL OR p_new_total_cents <= 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL: %', p_new_total_cents;
  END IF;

  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, service_type,
         status, errand_has_purchase, errand_estimated_purchase_cents
    INTO v_order FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;
  IF v_order.service_type IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'WRONG_SERVICE_TYPE'; END IF;
  IF NOT v_order.errand_has_purchase THEN RAISE EXCEPTION 'ERRAND_NO_PURCHASE'; END IF;
  IF v_order.status IN ('delivered','cancelled','rejected') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_TERMINAL'; END IF;
  IF v_order.assigned_driver_id IS DISTINCT FROM auth.uid()::text
     AND v_order.current_driver_offer_id IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;

  UPDATE public.orders
     SET errand_budget_status = 'pending',
         errand_budget_requested_cents = p_new_total_cents
   WHERE id = p_order_id;

  -- Push ao cliente (não fatal) — reusa notify-client (clientId obrigatório).
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object(
          'clientId', v_order.user_id,
          'orderId',  p_order_id,
          'status',   'errand_budget_request',
          'title',    'Autorizar compra maior?',
          'body',     'O estafeta precisa de ~€' || to_char(p_new_total_cents/100.0,'FM999990.00') ||
                      ' (orçaste €' || to_char(COALESCE(v_order.errand_estimated_purchase_cents,0)/100.0,'FM999990.00') ||
                      '). Abre a app para autorizar.'));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-client (budget) failed: %', SQLERRM; END;
  END IF;

  RETURN jsonb_build_object('success', true, 'status', 'pending',
                            'requested_cents', p_new_total_cents);
END;
$$;
GRANT EXECUTE ON FUNCTION public.errand_request_budget_increase(text, integer) TO authenticated;

-- 3) Cliente autoriza / recusa --------------------------------------------
CREATE OR REPLACE FUNCTION public.client_respond_budget_increase(
  p_order_id text,
  p_approve boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'auth'
AS $$
DECLARE
  v_order RECORD;
  v_new   text;
  v_url text; v_key text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  SELECT id, user_id, assigned_driver_id, service_type, status, errand_budget_status
    INTO v_order FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF v_order.user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'NOT_ORDER_OWNER'; END IF;
  IF v_order.service_type IS DISTINCT FROM 'errand' THEN RAISE EXCEPTION 'WRONG_SERVICE_TYPE'; END IF;
  IF v_order.errand_budget_status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'NO_PENDING_REQUEST'; END IF;

  v_new := CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
  UPDATE public.orders SET errand_budget_status = v_new WHERE id = p_order_id;

  -- Avisar o estafeta (não fatal) via notify-driver.
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-driver',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('driverId', v_order.assigned_driver_id, 'orderId', p_order_id,
                                   'title', CASE WHEN p_approve THEN 'Orçamento autorizado' ELSE 'Orçamento recusado' END,
                                   'body',  CASE WHEN p_approve THEN 'O cliente autorizou. Podes comprar e finalizar.'
                                                 ELSE 'O cliente recusou. Não compres — cancela o favor.' END));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-driver (budget) failed: %', SQLERRM; END;
  END IF;

  RETURN jsonb_build_object('success', true, 'status', v_new);
END;
$$;
GRANT EXECUTE ON FUNCTION public.client_respond_budget_increase(text, boolean) TO authenticated;

-- 4) finalize_errand_purchase — GATE do charge-extra por consentimento -----
--    (CREATE OR REPLACE completo; as ÚNICAS mudanças vs versão atual estão
--     marcadas com  -- [8.2] )
CREATE OR REPLACE FUNCTION public.finalize_errand_purchase(
  p_order_id text, p_driver_typed_total_cents integer, p_receipt_photo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'auth'
AS $function$
DECLARE
  v_order               RECORD;
  v_reimb_status        text;
  v_url                 text;
  v_key                 text;
  v_charge_extra_cents  integer := 0;
  v_final_total_eur     numeric;
  v_consent_ok          boolean := false;   -- [8.2]
  v_dispute             boolean := false;    -- [8.2]
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  SELECT id, user_id, assigned_driver_id, service_type, status,
         payment_method, delivery_fee, payment_buffer_total, errand_has_purchase,
         current_driver_offer_id,
         errand_budget_status, errand_budget_requested_cents          -- [8.2]
    INTO v_order FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;
  IF v_order.service_type IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'WRONG_SERVICE_TYPE: % (expected errand)', v_order.service_type;
  END IF;
  IF v_order.status IN ('delivered','cancelled','rejected') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_TERMINAL: %', v_order.status;
  END IF;
  IF v_order.assigned_driver_id IS DISTINCT FROM auth.uid()::text
     AND v_order.current_driver_offer_id IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER';
  END IF;
  IF NOT v_order.errand_has_purchase THEN
    RAISE EXCEPTION 'ERRAND_NO_PURCHASE: cannot finalize purchase on errand without has_purchase';
  END IF;
  IF p_driver_typed_total_cents IS NULL OR p_driver_typed_total_cents <= 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL: %', p_driver_typed_total_cents;
  END IF;
  IF p_receipt_photo_url IS NULL OR length(trim(p_receipt_photo_url)) = 0 THEN
    RAISE EXCEPTION 'RECEIPT_URL_REQUIRED';
  END IF;

  v_reimb_status := CASE WHEN v_order.payment_method = 'cash' THEN 'cash_settled' ELSE 'pending_admin' END;

  INSERT INTO public.order_receipts_v2 (
    order_id, photo_url, photo_taken_at, driver_typed_total_cents,
    reimbursement_status, reimbursement_amount_cents
  ) VALUES (
    p_order_id, p_receipt_photo_url, now(), p_driver_typed_total_cents,
    v_reimb_status, p_driver_typed_total_cents
  )
  ON CONFLICT (order_id) DO UPDATE
    SET photo_url = EXCLUDED.photo_url, photo_taken_at = EXCLUDED.photo_taken_at,
        driver_typed_total_cents = EXCLUDED.driver_typed_total_cents,
        reimbursement_status = EXCLUDED.reimbursement_status,
        reimbursement_amount_cents = EXCLUDED.reimbursement_amount_cents;

  v_final_total_eur := COALESCE(v_order.delivery_fee, 0) + (p_driver_typed_total_cents / 100.0);

  -- charge-extra previsto (cartão/MBWay) quando talão+fees > buffer (= >20%)
  IF v_order.payment_method IN ('card','stripe','mbway') AND v_order.payment_buffer_total IS NOT NULL THEN
    v_charge_extra_cents := GREATEST(0,
      ROUND((v_final_total_eur - v_order.payment_buffer_total) * 100)::int);
  END IF;

  -- [8.2] Consentimento: o cliente aprovou um total de compra ≥ ao talão real?
  v_consent_ok := (v_order.errand_budget_status = 'approved'
                   AND COALESCE(v_order.errand_budget_requested_cents, 0) >= p_driver_typed_total_cents);
  -- [8.2] Disputa: passou o buffer (precisa cobrar extra) mas sem consentimento.
  v_dispute := (v_charge_extra_cents > 0 AND NOT v_consent_ok);

  PERFORM set_config('app.financial_bypass', 'true', true);

  UPDATE public.orders SET
    final_total = v_final_total_eur,
    final_purchase_value = p_driver_typed_total_cents / 100.0,
    is_purchase_finalized = true,
    errand_budget_status = CASE WHEN v_dispute THEN 'disputed'      -- [8.2]
                                ELSE v_order.errand_budget_status END
  WHERE id = p_order_id;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
    IF v_order.payment_method IN ('card','stripe','mbway') THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-admin-reimbursement',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id',p_order_id,'driver_id',v_order.assigned_driver_id,'amount_cents',p_driver_typed_total_cents));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-admin-reimbursement (errand) failed: %', SQLERRM; END;
    END IF;
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/ocr-receipt',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('order_id', p_order_id));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ocr-receipt (errand) failed: %', SQLERRM; END;

    -- [8.2] charge-extra SÓ com consentimento do cliente.
    IF v_charge_extra_cents > 0 AND v_consent_ok THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/charge-extra',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id', p_order_id, 'amount_cents', v_charge_extra_cents, 'reason', 'errand_purchase_over_buffer'));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'charge-extra (errand) failed: %', SQLERRM; END;
    -- [8.2] Sem consentimento → disputa admin (não cobra cliente, não absorve).
    ELSIF v_dispute THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-admin-urgent',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id', p_order_id, 'driver_id', v_order.assigned_driver_id,
                   'reason', 'errand_overbudget_no_consent',
                   'over_buffer_cents', v_charge_extra_cents,
                   'typed_total_cents', p_driver_typed_total_cents));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-admin-urgent (errand dispute) failed: %', SQLERRM; END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'service_type', 'errand',
    'final_total_eur', v_final_total_eur,
    'final_purchase_value_cents', p_driver_typed_total_cents,
    'reimbursement_status', v_reimb_status,
    'charge_extra_cents', CASE WHEN v_consent_ok THEN v_charge_extra_cents ELSE 0 END,  -- [8.2]
    'budget_status', CASE WHEN v_dispute THEN 'disputed' ELSE v_order.errand_budget_status END,  -- [8.2]
    'dispute', v_dispute,                                                               -- [8.2]
    'payment_method', v_order.payment_method,
    'is_purchase_finalized', true
  );
END;
$function$;
```

**Resumo das mudanças no `finalize_errand_purchase` (linhas `-- [8.2]`):**
1. SELECT passa a ler `errand_budget_status`, `errand_budget_requested_cents`.
2. `v_consent_ok` = aprovado e o talão ≤ ao total que o cliente autorizou.
3. `v_dispute` = excede o buffer mas sem consentimento.
4. UPDATE marca `errand_budget_status='disputed'` quando disputa.
5. `charge-extra` só dispara com `v_consent_ok`; senão → `notify-admin-urgent` (disputa).
6. RETURN devolve `charge_extra_cents` real (0 se não cobrado), `budget_status`, `dispute`.

⚠️ Verificar no apply: existe Edge Function `notify-admin-urgent`? (a memória lista-a). Se o nome
real diferir, ajustar o URL. `charge-extra`/pricing/Stripe **inalterados** — só muda quem o chama.

---

## PARTE B — App do estafeta (`errand_execution_sheet.dart`) — proposta (NÃO aplicada)
Na fase "2. Compra na loja", acima do botão "Confirmar compra":
- Mostrar o limite autorizado: `~€(errandEstimatedPurchaseCents × 1.2)`.
- Botão **"Pedir aumento de orçamento"** → diálogo com o novo total previsto → chama a RPC:

```dart
Future<void> _requestBudgetIncrease() async {
  final ctrl = TextEditingController();
  final cents = await showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Pedir aumento de orçamento'),
      content: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Novo total previsto', prefixText: '€ '),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0;
            Navigator.pop(context, (v * 100).round());
          },
          child: const Text('Pedir'),
        ),
      ],
    ),
  );
  if (cents == null || cents <= 0) return;
  try {
    await Supabase.instance.client.rpc('errand_request_budget_increase',
        params: {'p_order_id': widget.order.id, 'p_new_total_cents': cents});
    if (mounted) setState(() => _error = null);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pedido enviado ao cliente. Aguarda a autorização antes de comprar.')));
  } catch (e) {
    if (mounted) setState(() => _error = 'Erro ao pedir aumento: $e');
  }
}
```

- Regra UX (timing A): se o estafeta vê que vai passar o limite → **pedir aumento, esperar o
  estado `approved` (realtime/refetch da order) e só depois comprar + Confirmar compra**.
- (Opcional) ler `order.errand_budget_status` para mostrar "À espera do cliente…/Autorizado/
  Recusado" e desativar "Confirmar compra" enquanto `pending`.

## PARTE C — App do cliente (banner de autorização) — proposta (NÃO aplicada)
No ecrã de tracking/detalhe, quando `order.errand_budget_status == 'pending'`:

```dart
// _ErrandBudgetBanner — mostra pedido de aumento + Autorizar/Recusar
final requested = (order.errandBudgetRequestedCents ?? 0) / 100.0;
final estimated = order.errandEstimatedPurchaseCents / 100.0;
// "O estafeta precisa de ~€{requested} (orçaste €{estimated})."
// Autorizar  → rpc('client_respond_budget_increase', {p_order_id: id, p_approve: true})
// Recusar    → rpc(..., {p_approve: false})  // recusa = cancelar favor (§55.6, nada comprado)
```

## PARTE D — OrderModel (campos novos para a UI) — proposta
Adicionar (à imagem dos outros errand_*):
```dart
final String? errandBudgetStatus;          // data['errand_budget_status']
final int? errandBudgetRequestedCents;     // data['errand_budget_requested_cents']
```

## Rollout (ordem)
1. Claude.ai aplica o SQL (Parte A) via MCP.
2. Eu implemento Partes B/C/D no Flutter (após OK) + `flutter analyze`.
3. Teste: talão ≤ estimativa×1.2 → cobra auto; >1.2 sem pedido → disputa admin; com pedido
   aprovado → charge-extra; recusa → favor cancelado §55.6.
