// supabase/functions/cancel-order-with-choice/index.ts
//
// Client-initiated cancellation with REFUND METHOD CHOICE (Feature 1, 2026-04-30).
//
// Body: { order_id: string, reason: string, refund_method: 'stripe' | 'wallet' }
//
// Flow:
//   1. Auth caller via JWT (must be order owner)
//   2. Validate order status (uses same tier logic as client-cancel-order)
//   3. Compute fee + refundable amount
//   4. If refund_method='stripe':
//        → stripe.refunds.create (5-10 dias úteis)
//        → push: "Reembolso de €X processado, demora 5-10 dias úteis."
//   5. If refund_method='wallet':
//        → RPC wallet_credit_refund_split (instant 80% free + 20% tokens)
//        → push: "€X creditados! €A em saldo livre + Y tokens (≈€B)"
//   6. UPDATE orders SET status='cancelled', cancel_*, refund_method, payment_status
//
// Source of truth split: platform_settings.wallet_split_free_pct (default 0.80)

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
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

type Tier = 'before_dispatch' | 'after_accept' | 'after_pickup' | 'invalid';
function tier(status: string): Tier {
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
function feeEur(t: Tier, total: number): number {
  switch (t) {
    case 'before_dispatch':
      return CANCEL_FEE_BEFORE_DISPATCH_EUR;
    case 'after_accept':
      return CANCEL_FEE_AFTER_ACCEPT_EUR;
    case 'after_pickup':
      return total * CANCEL_FEE_AFTER_PURCHASE_RATIO;
    default:
      return 0;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json({ error: 'server_misconfigured' }, 500);
  }

  let orderId: string | undefined;
  let reason: string | undefined;
  let refundMethod: 'stripe' | 'wallet' | undefined;
  try {
    const body = await req.json();
    orderId = body?.order_id;
    reason = typeof body?.reason === 'string' ? body.reason : undefined;
    refundMethod = body?.refund_method;
  } catch (_) {
    return json({ error: 'invalid_body' }, 400);
  }
  if (!orderId) return json({ error: 'order_id required' }, 400);
  if (!reason || reason.trim().length < 3) return json({ error: 'reason_required' }, 400);
  if (refundMethod !== 'stripe' && refundMethod !== 'wallet') {
    return json({ error: 'refund_method must be "stripe" or "wallet"' }, 400);
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

  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select(
      'id, user_id, status, payment_method, payment_intent_id, payment_status, ' +
        'total, estimated_total, final_total, customer_total, refund_amount',
    )
    .eq('id', orderId)
    .maybeSingle();
  if (orderErr || !order) return json({ error: 'order_not_found' }, 404);
  if (order.user_id !== user.id) return json({ error: 'not_your_order' }, 403);

  const t = tier(order.status);
  if (t === 'invalid') {
    return json({ error: 'cannot_cancel_at_status', status: order.status }, 409);
  }

  const totalEur = Number(
    order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0,
  );
  const fee = Number(feeEur(t, totalEur).toFixed(2));
  const refundEur = Math.max(0, Number((totalEur - fee).toFixed(2)));
  const refundCents = Math.round(refundEur * 100);

  let stripeRefundId: string | undefined;
  let walletResult: any = null;
  // refundExecuted=true ⇒ podemos escrever refund_amount/refund_method.
  // Se falso, deixamos esses campos a NULL (BUG-NEW-1: nunca escrever
  // refund_amount sem refund efectivo).
  let refundExecuted = false;
  // chargeMissing=true ⇒ PI nunca confirmou charge. Marcamos
  // payment_status='cancelled_no_charge' (BUG 3: PI órfão sem cobrança).
  let chargeMissing = false;

  // ── Branch by refund method ─────────────────────────────────────────────
  if (refundEur <= 0) {
    // 100% retido — não há refund a processar (after_pickup tier)
    // Continua para update da order, sem chamar Stripe nem wallet
  } else if (refundMethod === 'stripe') {
    if (order.payment_method !== 'card' || !order.payment_intent_id) {
      return json(
        { error: 'stripe_refund_unavailable',
          details: 'Order paid with non-card method or no payment_intent. Use wallet.' },
        409,
      );
    }
    // BUG 3 (2026-04-30): retrieve PI antes de refundar. Se status != succeeded
    // ou latest_charge=null, NÃO há cobrança real → skip Stripe sem 502.
    let piStatus: string | undefined;
    let piLatestCharge: string | null | undefined;
    try {
      const pi = await stripe.paymentIntents.retrieve(order.payment_intent_id);
      piStatus = pi.status;
      piLatestCharge = (pi.latest_charge as string | null) ?? null;
    } catch (e) {
      console.error('[cancel-with-choice] PI retrieve failed:', e);
      return json({ error: 'pi_retrieve_failed', details: String(e) }, 502);
    }
    if (piStatus !== 'succeeded' || !piLatestCharge) {
      console.log('[cancel-with-choice] PI without charge — skipping Stripe refund',
        { pi: order.payment_intent_id, piStatus, piLatestCharge });
      chargeMissing = true;
      // Sem cobrança a reembolsar — segue para update sem refund_amount.
    } else {
      try {
        // Idempotency key alinhada com Edge Fn `refund` (BUG-MN-004).
        const idempotencyKey = `refund-${order.payment_intent_id}-${refundCents}`;
        const refund = await stripe.refunds.create(
          { payment_intent: order.payment_intent_id, amount: refundCents },
          { idempotencyKey },
        );
        stripeRefundId = refund.id;
        refundExecuted = true;
      } catch (e) {
        console.error('[cancel-with-choice] stripe failed:', e);
        return json({ error: 'refund_failed', details: String(e) }, 502);
      }
    }
  } else {
    // refund_method === 'wallet' — sempre disponível independentemente do payment_method
    const { data: walletRpc, error: walletErr } = await admin.rpc(
      'wallet_credit_refund_split',
      {
        p_order_id: orderId,
        p_user_id: user.id,
        p_total_cents: refundCents,
        p_reason: `Cancelamento pedido ${orderId}: ${reason}`,
      },
    );
    if (walletErr) {
      console.error('[cancel-with-choice] wallet RPC failed:', walletErr);
      return json({ error: 'wallet_credit_failed', details: walletErr.message }, 500);
    }
    walletResult = walletRpc;
    refundExecuted = true;
  }

  // ── Update order ────────────────────────────────────────────────────────
  const now = new Date().toISOString();
  // BUG 3: PI órfão (sem cobrança) → payment_status='cancelled_no_charge'.
  // Não promovemos para 'refunded' porque nunca houve dinheiro.
  const newPaymentStatus = chargeMissing
    ? 'cancelled_no_charge'
    : refundEur <= 0
      ? 'refunded'
      : fee > 0
        ? 'partial_refund'
        : 'refunded';

  // BUG-NEW-1 + BUG-NEW-3: refund_amount/refund_method/refund_status só
  // quando refund_executed=true. Restantes ficam a NULL (constraint força).
  // deno-lint-ignore no-explicit-any
  const updatePayload: Record<string, any> = {
    status: 'cancelled',
    cancel_reason: reason,
    cancel_fee: fee,
    cancelled_at: now,
    payment_status: newPaymentStatus,
    cancellation_initiator: 'client',
  };
  if (refundExecuted) {
    updatePayload.refund_amount = refundEur;
    updatePayload.refund_method = refundMethod;
    updatePayload.refund_status =
      refundMethod === 'wallet' ? 'completed' : 'pending';
  }

  const { error: updateErr } = await admin
    .from('orders')
    .update(updatePayload)
    .eq('id', orderId)
    .eq('user_id', user.id);

  if (updateErr) {
    console.error('[cancel-with-choice] update failed:', updateErr);
    return json({ error: 'db_update_failed', details: updateErr.message }, 500);
  }

  // ── Notify (best-effort) ────────────────────────────────────────────────
  try {
    let title = 'Reembolso processado';
    let message: string;
    if (chargeMissing) {
      // BUG 3: pedido cancelado sem cobrança real — comunicar isto claramente.
      title = 'Pedido cancelado';
      message =
        'O pedido foi cancelado. Não houve cobrança no cartão, por isso não há reembolso a processar.';
    } else if (refundMethod === 'stripe') {
      message = `Reembolso de €${refundEur.toFixed(2)} processado. Pode demorar 5-10 dias úteis a aparecer no cartão. Para crédito instantâneo, escolhe wallet da próxima vez.`;
    } else if (walletResult) {
      message = `€${(walletResult.free_cents / 100).toFixed(2)} creditados em saldo livre + ${walletResult.tokens_count} tokens (≈€${(walletResult.tokens_value_cents / 100).toFixed(2)}). Disponível imediatamente.`;
    } else {
      message = 'Pedido cancelado.';
    }
    await admin.functions.invoke('notify-client', {
      body: { user_id: user.id, title, body: message,
              data: { order_id: orderId, refund_method: refundExecuted ? refundMethod : null,
                      charge_missing: chargeMissing } },
    });
  } catch (e) {
    console.warn('[cancel-with-choice] notify failed (non-fatal):', e);
  }

  return json({
    ok: true,
    tier: t,
    fee_eur: fee,
    refund_eur: refundExecuted ? refundEur : 0,
    refund_method: refundExecuted ? refundMethod : null,
    refund_id: stripeRefundId ?? null,
    charge_missing: chargeMissing,
    wallet: walletResult,
  });
});
