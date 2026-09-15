// supabase/functions/execute-cancellation/index.ts
//
// Executes a cancellation_request that was previously approved by admin.
// Body: { request_id: string }
// Auth: caller must be admin (bora_role='admin' in JWT).
//
// Flow:
//   1. Auth admin via JWT
//   2. Load cancellation_request, validate status='approved' and refund_method set
//   3. Load order (must not be already cancelled)
//   4. Compute fee + refundable amount via tier (same as client-cancel-order)
//   5. Branch by request.refund_method:
//        - 'stripe' → stripe.refunds.create
//        - 'wallet' → RPC wallet_credit_refund_split
//        - 'none'   → skip
//   6. Update orders SET status='cancelled', refund_*, cancelled_at, cancellation_initiator
//   7. Notify client via notify-client
//   8. Audit log

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';
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
    case 'created': case 'preparing': case 'callingDriver': return 'before_dispatch';
    case 'driverAccepted': return 'after_accept';
    case 'pickedUp': case 'onTheWay': return 'after_pickup';
    default: return 'invalid';
  }
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: 'server_misconfigured' }, 500);

  let requestId: string | undefined;
  try {
    const body = await req.json();
    requestId = body?.request_id;
  } catch (_) { return json({ error: 'invalid_body' }, 400); }
  if (!requestId) return json({ error: 'request_id required' }, 400);

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized' }, 401);

  const role = (user.user_metadata as Record<string, unknown> | undefined)?.['bora_role']
            ?? (user.app_metadata as Record<string, unknown> | undefined)?.['role'];
  if (role !== 'admin') return json({ error: 'admin_required' }, 403);

  const admin = createClient(supabaseUrl, serviceKey);

  // Load cancellation_request
  const { data: cReq, error: cErr } = await admin
    .from('cancellation_requests')
    .select('id, order_id, status, refund_method, requester_role, requester_id, reviewed_by_admin')
    .eq('id', requestId)
    .maybeSingle();
  if (cErr || !cReq) return json({ error: 'cancellation_request_not_found' }, 404);
  if (cReq.status !== 'approved') return json({ error: 'request_not_approved', status: cReq.status }, 409);
  if (!cReq.refund_method) return json({ error: 'no_refund_method_set' }, 409);

  // Load order
  const { data: order, error: oErr } = await admin
    .from('orders')
    .select('id, user_id, status, payment_method, payment_intent_id, payment_status, total, estimated_total, final_total, customer_total, refund_amount, refund_method, cancelled_at')
    .eq('id', cReq.order_id)
    .maybeSingle();
  if (oErr || !order) return json({ error: 'order_not_found' }, 404);

  if (order.status === 'cancelled' && order.cancelled_at) {
    return json({ ok: true, idempotent: true, message: 'order_already_cancelled' });
  }

  const t = tier(order.status);
  if (t === 'invalid') return json({ error: 'cannot_cancel_at_status', status: order.status }, 409);

  const totalEur = Number(order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0);
  const fees = await getCancelFees();
  const fee = Number(computeCancelFeeEur(t, totalEur, fees).toFixed(2));
  const refundEur = Math.max(0, Number((totalEur - fee).toFixed(2)));
  const refundCents = Math.round(refundEur * 100);

  const method = cReq.refund_method as 'stripe' | 'wallet' | 'none';
  let stripeRefundId: string | undefined;
  // deno-lint-ignore no-explicit-any
  let walletResult: any = null;

  if (method !== 'none' && refundEur > 0) {
    if (method === 'stripe') {
      if (order.payment_method !== 'card' || !order.payment_intent_id) {
        return json({ error: 'stripe_refund_unavailable',
          details: 'Order not paid with card. Re-approve with wallet method.' }, 409);
      }
      try {
        const refund = await stripe.refunds.create({
          payment_intent: order.payment_intent_id, amount: refundCents,
        });
        stripeRefundId = refund.id;
      } catch (e) {
        console.error('[execute-cancellation] stripe failed:', e);
        return json({ error: 'refund_failed', details: String(e) }, 502);
      }
    } else {
      const { data: walletRpc, error: walletErr } = await admin.rpc('wallet_credit_refund_split', {
        p_order_id: order.id, p_user_id: order.user_id, p_total_cents: refundCents,
        p_reason: `Aprovado por admin (req ${cReq.id}, ${cReq.requester_role})`,
      });
      if (walletErr) {
        console.error('[execute-cancellation] wallet RPC failed:', walletErr);
        return json({ error: 'wallet_credit_failed', details: walletErr.message }, 500);
      }
      walletResult = walletRpc;
    }
  }

  // Update order
  const now = new Date().toISOString();
  const newPaymentStatus = refundEur <= 0 ? 'refunded' : fee > 0 ? 'partial_refund' : 'refunded';
  const { error: updateErr } = await admin.from('orders').update({
    status: 'cancelled',
    cancel_reason: `Cancelamento aprovado pelo admin (pedido por ${cReq.requester_role})`,
    cancel_fee: fee, cancelled_at: now,
    refund_amount: refundEur, refund_method: method,
    refund_status: method === 'wallet' ? 'completed' : (method === 'none' ? 'completed' : 'pending'),
    payment_status: newPaymentStatus,
    cancellation_initiator: cReq.requester_role,
  }).eq('id', order.id);
  if (updateErr) {
    console.error('[execute-cancellation] update failed:', updateErr);
    return json({ error: 'db_update_failed', details: updateErr.message }, 500);
  }

  // Audit (admin context — RPC fails silent if guard rejects, so use direct insert via service)
  try {
    await admin.from('admin_audit_log').insert({
      admin_id: cReq.reviewed_by_admin,
      action: 'cancellation_executed',
      entity_type: 'cancellation_request',
      entity_id: cReq.id,
      details: {
        order_id: order.id,
        refund_method: method,
        refund_eur: refundEur,
        fee_eur: fee,
        stripe_refund_id: stripeRefundId ?? null,
      },
    });
  } catch (e) { console.warn('[execute-cancellation] audit failed (non-fatal):', e); }

  // Notify client
  try {
    const message = method === 'stripe'
      ? `Cancelamento aprovado. Reembolso de €${refundEur.toFixed(2)} processado. Pode demorar 5-10 dias úteis a aparecer no cartão.`
      : method === 'wallet' && walletResult
      ? `Cancelamento aprovado. €${(walletResult.free_cents / 100).toFixed(2)} em saldo livre + ${walletResult.tokens_count} tokens (≈€${(walletResult.tokens_value_cents / 100).toFixed(2)}) — disponíveis imediatamente.`
      : `Cancelamento aprovado.`;
    await admin.functions.invoke('notify-client', {
      body: { user_id: order.user_id, title: 'Cancelamento aprovado', body: message,
              data: { order_id: order.id, refund_method: method } },
    });
  } catch (e) { console.warn('[execute-cancellation] notify failed (non-fatal):', e); }

  return json({ ok: true,
    request_id: cReq.id, order_id: order.id, refund_method: method,
    fee_eur: fee, refund_eur: refundEur,
    stripe_refund_id: stripeRefundId ?? null, wallet: walletResult,
  });
});
