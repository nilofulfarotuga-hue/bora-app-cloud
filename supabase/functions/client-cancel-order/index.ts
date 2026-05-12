// supabase/functions/client-cancel-order/index.ts
// v19 (2026-05-12 — Bug #1): cancel CASH/MBWay-não-pago → débito wallet (dívida), não simples cancel.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return jsonResponse({ error: 'server_misconfigured' }, 500);

  let orderId: string | undefined;
  let reason: string | undefined;
  try {
    const body = await req.json();
    orderId = body?.order_id;
    reason = typeof body?.reason === 'string' ? body.reason : undefined;
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }

  if (!orderId || typeof orderId !== 'string') return jsonResponse({ error: 'order_id required' }, 400);

  // FIX 2026-05-12: aceitar qualquer texto livre (max 200 chars)
  if (reason !== undefined && reason !== null) {
    const trimmed = reason.trim();
    if (trimmed.length > 200) return jsonResponse({ error: 'reason_too_long', max: 200 }, 400);
    reason = trimmed;
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return jsonResponse({ error: 'unauthorized' }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select('id, user_id, status, payment_method, payment_intent_id, payment_status, total, estimated_total, final_total, customer_total, refund_amount, stripe_charge_cents, wallet_applied_cents, tokens_applied_value_cents')
    .eq('id', orderId)
    .maybeSingle();
  if (orderErr || !order) return jsonResponse({ error: 'order_not_found' }, 404);
  if (order.user_id !== user.id) return jsonResponse({ error: 'not_your_order' }, 403);

  const tier = resolveTier(order.status);
  if (tier === 'invalid') return jsonResponse({ error: 'cannot_cancel_at_status', status: order.status }, 409);

  const totalEur = Number(order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0);
  const fees = await getCancelFees();
  const feeEur = Number(computeCancelFeeEur(tier, totalEur, fees).toFixed(2));
  const refundEur = Math.max(0, Number((totalEur - feeEur).toFixed(2)));

  // FIX 2026-05-12: CASH antes de entrega → cliente nada pagou
  const paidCents = Number(order.stripe_charge_cents ?? 0) + Number(order.wallet_applied_cents ?? 0) + Number(order.tokens_applied_value_cents ?? 0);
  const nothingToRefund = paidCents === 0;

  let refundId: string | undefined;
  let refundExecuted = false;
  let chargeMissing = false;

  // v19: débito wallet para CASH/MBWay-não-pago
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
              order_id: orderId,
              user_id: user.id,
              fee_cents: Math.round(feeEur * 100),
              tier,
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
    let piStatus: string | undefined;
    let piLatestCharge: string | null | undefined;
    try {
      const pi = await stripe.paymentIntents.retrieve(order.payment_intent_id);
      piStatus = pi.status;
      piLatestCharge = (pi.latest_charge as string | null) ?? null;
    } catch (e) {
      return jsonResponse({ error: 'pi_retrieve_failed', details: String(e) }, 502);
    }
    if (piStatus !== 'succeeded' || !piLatestCharge) {
      chargeMissing = true;
    } else {
      try {
        const idempotencyKey = `refund-${order.payment_intent_id}-${Math.round(refundEur * 100)}`;
        const refund = await stripe.refunds.create(
          { payment_intent: order.payment_intent_id, amount: Math.round(refundEur * 100) },
          { idempotencyKey },
        );
        refundId = refund.id;
        refundExecuted = true;
      } catch (e) {
        return jsonResponse({ error: 'refund_failed', details: String(e) }, 502);
      }
    }
  }

  const now = new Date().toISOString();
  const newPaymentStatus = cancelFeeDebited
    ? 'cancelled_with_debt'
    : chargeMissing
      ? 'cancelled_no_charge'
      : refundEur <= 0
        ? 'refunded'
        : refundExecuted
          ? feeEur > 0 ? 'partial_refund' : 'refunded'
          : 'cancelled_no_charge';

  const updatePayload: Record<string, any> = {
    status: 'cancelled',
    cancel_reason: reason ?? null,
    cancel_fee: cancelFeeDebited ? feeEur : (nothingToRefund ? 0 : feeEur),
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
    .eq('user_id', user.id);

  if (updateErr) return jsonResponse({ error: 'db_update_failed', details: updateErr.message }, 500);

  return jsonResponse({
    ok: true,
    tier,
    fee_eur: cancelFeeDebited || !nothingToRefund ? feeEur : 0,
    refund_eur: refundExecuted ? refundEur : 0,
    refund_id: refundId ?? null,
    charge_missing: chargeMissing,
    nothing_to_refund: nothingToRefund,
    cancel_fee_debited: cancelFeeDebited,
    cancel_fee_debit: cancelFeeDebitResult,
  });
});
