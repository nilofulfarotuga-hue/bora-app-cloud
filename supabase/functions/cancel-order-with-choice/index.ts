// supabase/functions/cancel-order-with-choice/index.ts
// FIX 2026-05-12: CASH antes de entrega não tem reembolso.
// v11 (2026-05-12 — Bug #1): cancel CASH/MBWay-não-pago → débito wallet (dívida), não simples cancel.
// v18 (2026-10-05 — ronda 04/10 A.1/A.2/A.6): trava atómica contra duplo toque; o que se pagou lê-se
//   da Stripe quando stripe_charge_cents está a 0; reembolso limitado ao pago e repartido por fonte
//   (MB Way também volta pela Stripe; carteira/tokens voltam à carteira).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { lerPagoDoPedido, repartirReembolso, totalPago } from '../_shared/cobranca_stripe.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

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
        'total, estimated_total, final_total, customer_total, refund_amount, ' +
        'stripe_charge_cents, wallet_applied_cents, tokens_applied_value_cents, refund_status',
    )
    .eq('id', orderId)
    .maybeSingle();
  if (orderErr || !order) return json({ error: 'order_not_found' }, 404);
  if (order.user_id !== user.id) return json({ error: 'not_your_order' }, 403);

  const t = tier(order.status);
  if (t === 'invalid') {
    return json({ error: 'cannot_cancel_at_status', status: order.status }, 409);
  }

  // v18 (ronda 04/10 A.6): trava contra duplo toque — reserva atómica do pedido
  // (refund_status -> 'processing' só se ainda não estiver). O segundo toque leva 409.
  const refundStatusAntes = order.refund_status ?? null;
  const { data: reservado, error: resErr } = await admin.from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).eq('user_id', user.id).neq('status', 'cancelled')
    .or('refund_status.is.null,refund_status.neq.processing')
    .select('id');
  if (resErr) return json({ error: 'db_reserve_failed', details: resErr.message }, 500);
  if (!reservado || reservado.length === 0) return json({ error: 'cancellation_in_progress' }, 409);
  const libertar = async () => {
    await admin.from('orders').update({ refund_status: refundStatusAntes })
      .eq('id', orderId).eq('refund_status', 'processing');
  };

  const totalEur = Number(
    order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0,
  );
  const fees = await getCancelFees();
  const fee = Number(computeCancelFeeEur(t, totalEur, fees).toFixed(2));

  // FIX 2026-05-12: Calcular quanto cliente REALMENTE pagou
  // v18 (ronda 04/10 A.1): stripe_charge_cents vem da Stripe quando está a 0 (lerPagoDoPedido).
  let pago;
  try { pago = await lerPagoDoPedido(admin, Deno.env.get('STRIPE_SECRET_KEY') ?? '', orderId); }
  catch (e) { await libertar(); return json({ error: 'paid_unknown', details: String(e) }, 502); }
  const paidCents = totalPago(pago);
  const nothingToRefund = paidCents === 0;
  // nunca devolve mais do que se pagou
  const refundCents = Math.min(Math.max(0, Math.round((totalEur - fee) * 100)), paidCents);
  const refundEur = refundCents / 100;

  let stripeRefundId: string | undefined;
  let devolvidoCents = 0;
  let walletResult: any = null;
  let refundExecuted = false;
  let chargeMissing = false;

  // v11: débito wallet para CASH/MBWay-não-pago
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
              order_id: orderId,
              user_id: user.id,
              fee_cents: Math.round(fee * 100),
              tier: t,
              error: debitErr.message,
            },
          });
        } catch (_) { /* fire-and-forget */ }
        chargeMissing = true; // fallback comportamento legado
      } else {
        cancelFeeDebited = true;
        cancelFeeDebitResult = debitRpc;
      }
    } else {
      // Sem fee ou pagamento já refundable noutro caminho — fallback simple cancel
      console.log('[cancel-with-choice] no payment + no fee, simple cancel', {
        orderId, payment_method: order.payment_method, status: order.status,
      });
      chargeMissing = true;
    }
  } else if (refundEur <= 0) {
    // 100% retido
  } else {
    // v18 (ronda 04/10 A.2): cada parte volta pela fonte. 'stripe' = até ao que a Stripe
    // cobrou (cartão OU MB Way) volta ao meio de pagamento; o que foi pago com carteira/
    // tokens volta à carteira. 'wallet' = tudo para a carteira.
    let carteiraCents = refundCents;
    if (refundMethod === 'stripe') {
      const parte = repartirReembolso(refundCents, pago);
      carteiraCents = parte.carteiraCents;
      if (parte.stripeCents > 0 && order.payment_intent_id) {
        try {
          const idempotencyKey = `refund-${order.payment_intent_id}-${parte.stripeCents}`;
          const refund = await stripe.refunds.create(
            { payment_intent: order.payment_intent_id, amount: parte.stripeCents },
            { idempotencyKey },
          );
          stripeRefundId = refund.id;
          refundExecuted = true;
          devolvidoCents += parte.stripeCents;
          // grava já o id: se o resto falhar, o banco sabe que o dinheiro saiu
          await admin.from('orders').update({ refund_id: refund.id }).eq('id', orderId);
        } catch (e) {
          console.error('[cancel-with-choice] stripe failed:', e);
          await libertar();
          return json({ error: 'refund_failed', details: String(e) }, 502);
        }
      } else if (carteiraCents <= 0) {
        chargeMissing = true;
      }
    }
    if (carteiraCents > 0) {
      const { data: walletRpc, error: walletErr } = await admin.rpc(
        'wallet_credit_refund_split',
        {
          p_order_id: orderId,
          p_user_id: user.id,
          p_total_cents: carteiraCents,
          p_reason: `Cancelamento pedido ${orderId}: ${reason}`,
        },
      );
      if (walletErr) {
        console.error('[cancel-with-choice] wallet RPC failed:', walletErr);
        if (!stripeRefundId) await libertar();
        // a Stripe já devolveu: 'needs_review' (o Reprocessar só pega em 'failed')
        else await admin.from('orders').update({ refund_status: 'needs_review' }).eq('id', orderId);
        return json({ error: 'wallet_credit_failed', details: walletErr.message, refund_id: stripeRefundId ?? null }, 500);
      }
      walletResult = walletRpc;
      refundExecuted = true;
      if (!walletRpc?.already_applied) devolvidoCents += carteiraCents;
    }
  }

  const now = new Date().toISOString();
  const newPaymentStatus = cancelFeeDebited
    ? 'cancelled_with_debt'
    : chargeMissing
      ? 'cancelled_no_charge'
      : refundEur <= 0
        ? 'refunded'
        : fee > 0
          ? 'partial_refund'
          : 'refunded';

  const updatePayload: Record<string, any> = {
    status: 'cancelled',
    cancel_reason: reason,
    cancel_fee: cancelFeeDebited ? fee : (nothingToRefund ? 0 : fee),
    cancelled_at: now,
    payment_status: newPaymentStatus,
    cancellation_initiator: 'client',
  };
  if (refundExecuted) {
    updatePayload.refund_amount = devolvidoCents / 100;
    updatePayload.refund_method = stripeRefundId ? 'stripe' : 'wallet';
    updatePayload.refund_status = stripeRefundId ? 'pending' : 'completed';
    if (stripeRefundId) updatePayload.refund_id = stripeRefundId;
  } else {
    // v18: tira a reserva da trava
    updatePayload.refund_status = refundStatusAntes;
  }

  const { error: updateErr } = await admin
    .from('orders')
    .update(updatePayload)
    .eq('id', orderId)
    .eq('user_id', user.id);

  if (updateErr) {
    console.error('[cancel-with-choice] update failed:', updateErr);
    if (refundExecuted) await admin.from('orders').update({ refund_status: 'needs_review' }).eq('id', orderId);
    else await libertar();
    return json({ error: 'db_update_failed', details: updateErr.message }, 500);
  }

  try {
    let title = 'Reembolso processado';
    let message: string;
    if (cancelFeeDebited) {
      title = 'Pedido cancelado';
      message =
        `Pedido cancelado. Taxa de cancelamento €${fee.toFixed(2)} foi adicionada como dívida na tua conta. ` +
        `Será cobrada no próximo pedido.`;
    } else if (nothingToRefund) {
      title = 'Pedido cancelado';
      message = 'O pedido foi cancelado. Como ainda não tinhas pago, não há reembolso a processar.';
    } else if (chargeMissing) {
      title = 'Pedido cancelado';
      message =
        'O pedido foi cancelado. Não houve cobrança no cartão, por isso não há reembolso a processar.';
    } else if (stripeRefundId) {
      message = `Reembolso de €${(devolvidoCents / 100).toFixed(2)} processado. Pode demorar 5-10 dias úteis a aparecer no cartão.`;
    } else if (walletResult) {
      message = `€${(walletResult.free_cents / 100).toFixed(2)} creditados em saldo livre + ${walletResult.tokens_count} tokens (≈€${(walletResult.tokens_value_cents / 100).toFixed(2)}). Disponível imediatamente.`;
    } else {
      message = 'Pedido cancelado.';
    }
    await admin.functions.invoke('notify-client', {
      body: { user_id: user.id, title, body: message,
              data: { order_id: orderId, refund_method: refundExecuted ? refundMethod : null,
                      charge_missing: chargeMissing,
                      cancel_fee_debited: cancelFeeDebited } },
    });
  } catch (e) {
    console.warn('[cancel-with-choice] notify failed (non-fatal):', e);
  }

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
});
