// supabase/functions/client-cancel-order/index.ts
//
// Client-initiated order cancellation (BR §8.3).
//
// Fee tiers (source of truth: _shared/business_rules.ts):
//   • created / preparing / callingDriver → 1.00 EUR
//   • driverAccepted                       → 2.50 EUR
//   • pickedUp / onTheWay                  → 100% of total (no refund)
//
// Behaviour:
//   1. Authenticates the caller via JWT.
//   2. Looks up the order; rejects if the caller is not the owner.
//   3. Rejects if the order is already terminal (delivered/rejected/cancelled).
//   4. Computes the fee server-side from the current status.
//   5. If payment_method = 'card' and fee < total and payment_intent_id exists
//      → issues a Stripe refund for (total - fee).
//   6. For mbway/cash → updates refund_amount directly (no Stripe call).
//   7. Updates orders row: status='cancelled', cancel_fee, cancel_reason,
//      cancelled_at, payment_status.
//
// Never touches:
//   • driver_transactions, driver_balances, ledger_entries, order_financials,
//     payouts, bora_tokens. Fiscal trail preserved for 10 years (BR §20.2).
//   • finalizePurchase-related rows.
//
// Callers: Flutter client → OrderStore.clientCancelOrder().

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  CANCEL_FEE_BEFORE_DISPATCH_EUR,
  CANCEL_FEE_AFTER_ACCEPT_EUR,
  CANCEL_FEE_AFTER_PURCHASE_RATIO,
} from '../_shared/business_rules.ts';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

// deno-lint-ignore no-explicit-any
const jsonResponse = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

type CancelTier = 'before_dispatch' | 'after_accept' | 'after_pickup' | 'invalid';

function resolveTier(status: string): CancelTier {
  switch (status) {
    case 'created':
    case 'preparing':
    case 'callingDriver':
      return 'before_dispatch';
    case 'driverAccepted':
      return 'after_accept';
    case 'pickedUp':
    case 'onTheWay':
      return 'after_pickup';
    default:
      return 'invalid';
  }
}

function computeFeeEur(tier: CancelTier, total: number): number {
  switch (tier) {
    case 'before_dispatch':
      return CANCEL_FEE_BEFORE_DISPATCH_EUR;
    case 'after_accept':
      return CANCEL_FEE_AFTER_ACCEPT_EUR;
    case 'after_pickup':
      return total * CANCEL_FEE_AFTER_PURCHASE_RATIO;
    case 'invalid':
      return 0;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseUrl || !serviceKey || !anonKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  // ── Parse body ───────────────────────────────────────────────────────────
  let orderId: string | undefined;
  let reason: string | undefined;
  try {
    const body = await req.json();
    orderId = body?.order_id;
    reason = typeof body?.reason === 'string' ? body.reason : undefined;
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }

  if (!orderId || typeof orderId !== 'string') {
    return jsonResponse({ error: 'order_id required' }, 400);
  }

  // BUG-NEW-2 (Fase 6 / 2026-04-30): validar reason contra enum + cap em 200 chars.
  const REASON_ENUM = new Set([
    'changed_mind',
    'wrong_address',
    'wrong_items',
    'too_long',
    'driver_unresponsive',
    'partner_unresponsive',
    'payment_failed',
    'payment_abandoned',
    'other',
  ]);
  if (reason !== undefined && reason !== null) {
    const trimmed = reason.trim();
    if (trimmed.length > 200) {
      return jsonResponse({ error: 'reason_too_long', max: 200 }, 400);
    }
    const head = trimmed.split(':', 1)[0].trim();
    if (!REASON_ENUM.has(head)) {
      return jsonResponse({
        error: 'invalid_reason',
        details: 'Use one of: ' + Array.from(REASON_ENUM).join(', ') + ' (or "other:<texto>")',
      }, 400);
    }
    reason = trimmed;
  }

  // ── Authenticate caller ──────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  const admin = createClient(supabaseUrl, serviceKey);

  // ── Load order ───────────────────────────────────────────────────────────
  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select(
      'id, user_id, status, payment_method, payment_intent_id, payment_status, ' +
        'total, estimated_total, final_total, customer_total, refund_amount',
    )
    .eq('id', orderId)
    .maybeSingle();

  if (orderErr || !order) {
    return jsonResponse({ error: 'order_not_found' }, 404);
  }
  if (order.user_id !== user.id) {
    return jsonResponse({ error: 'not_your_order' }, 403);
  }

  const tier = resolveTier(order.status);
  if (tier === 'invalid') {
    return jsonResponse(
      { error: 'cannot_cancel_at_status', status: order.status },
      409,
    );
  }

  // Use the best-available customer-facing total (may be estimated prior to
  // driver pickup for non-partner purchases).
  const totalEur = Number(
    order.customer_total ??
      order.final_total ??
      order.total ??
      order.estimated_total ??
      0,
  );

  const feeEur = Number(computeFeeEur(tier, totalEur).toFixed(2));
  const refundEur = Math.max(0, Number((totalEur - feeEur).toFixed(2)));

  // ── Stripe refund (card only, when there is something to refund) ─────────
  // BUG 3 + BUG-NEW-1 (2026-04-30):
  //   1. Retrieve PI antes de refund — se não houve charge, não chamamos Stripe.
  //   2. Só escrevemos refund_amount/refund_method se refund foi efectivamente
  //      executado. Caso contrário → payment_status='cancelled_no_charge'.
  let refundId: string | undefined;
  let refundExecuted = false;
  let chargeMissing = false;
  if (
    order.payment_method === 'card' &&
    order.payment_intent_id &&
    refundEur > 0
  ) {
    let piStatus: string | undefined;
    let piLatestCharge: string | null | undefined;
    try {
      const pi = await stripe.paymentIntents.retrieve(order.payment_intent_id);
      piStatus = pi.status;
      piLatestCharge = (pi.latest_charge as string | null) ?? null;
    } catch (e) {
      console.error('[client-cancel-order] PI retrieve failed:', e);
      return jsonResponse(
        { error: 'pi_retrieve_failed', details: String(e) },
        502,
      );
    }
    if (piStatus !== 'succeeded' || !piLatestCharge) {
      console.log('[client-cancel-order] PI without charge — skipping Stripe refund',
        { pi: order.payment_intent_id, piStatus, piLatestCharge });
      chargeMissing = true;
    } else {
      try {
        const idempotencyKey = `refund-${order.payment_intent_id}-${Math.round(refundEur * 100)}`;
        const refund = await stripe.refunds.create(
          {
            payment_intent: order.payment_intent_id,
            amount: Math.round(refundEur * 100),
          },
          { idempotencyKey },
        );
        refundId = refund.id;
        refundExecuted = true;
      } catch (e) {
        console.error('[client-cancel-order] stripe refund failed:', e);
        return jsonResponse(
          { error: 'refund_failed', details: String(e) },
          502,
        );
      }
    }
  } else if (refundEur === 0) {
    // 100% retido — sem refund a processar (refund_executed permanece false)
  } else {
    // mbway/cash sem PI — não escrevemos refund_amount aqui (BUG-NEW-1).
    // Refund mbway/cash é tratado por wallet credit em fluxo separado.
  }

  // ── Update orders row ────────────────────────────────────────────────────
  const now = new Date().toISOString();
  const newPaymentStatus = chargeMissing
    ? 'cancelled_no_charge'
    : refundEur <= 0
      ? 'refunded' // 100% retained — treat as closed (no money owed)
      : refundExecuted
        ? feeEur > 0 ? 'partial_refund' : 'refunded'
        : 'cancelled_no_charge'; // refund pendente/não-card sem fluxo aqui

  // deno-lint-ignore no-explicit-any
  const updatePayload: Record<string, any> = {
    status: 'cancelled',
    cancel_reason: reason ?? null,
    cancel_fee: feeEur,
    cancelled_at: now,
    payment_status: newPaymentStatus,
  };
  if (refundExecuted) {
    updatePayload.refund_amount = refundEur;
    updatePayload.refund_method = 'stripe';
    updatePayload.refund_status = 'pending';
  }

  const { error: updateErr } = await admin
    .from('orders')
    .update(updatePayload)
    .eq('id', orderId)
    .eq('user_id', user.id); // extra safety

  if (updateErr) {
    console.error('[client-cancel-order] update failed:', updateErr);
    return jsonResponse(
      { error: 'db_update_failed', details: updateErr.message },
      500,
    );
  }

  return jsonResponse({
    ok: true,
    tier,
    fee_eur: feeEur,
    refund_eur: refundExecuted ? refundEur : 0,
    refund_id: refundId ?? null,
    charge_missing: chargeMissing,
  });
});
