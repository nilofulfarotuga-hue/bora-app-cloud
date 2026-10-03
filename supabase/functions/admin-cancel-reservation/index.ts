// supabase/functions/admin-cancel-reservation/index.ts
// Sessao 5B-beta2a B0.2 — Admin reservation cancellation orchestrator.
// Espelha admin-cancel-order. Decisao D2 (Fase A audit).
//
// Fluxo:
//  1. Verifica admin JWT (app_metadata.role='admin')
//  2. Chama RPC admin_cancel_reservation_on_behalf_of(p_reservation_id, p_reason)
//  3. Se will_refund && prepayment_pi -> Stripe refund (idempotency key)
//  4. Audit log
//  5. Retorna { success, idempotent, refund }
//
// NB: notification ao cliente ja e feita pela RPC via _push_in_app_notification.
//     Push FCM externo nao e chamado aqui — RPC ja escreve in-app.

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST')   return jsonResponse({ error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey     = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const stripeKey   = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  let reservationId = '';
  let reason = '';
  try {
    const body = await req.json();
    reservationId = (body?.reservation_id ?? '').toString().trim();
    reason        = (body?.reason         ?? '').toString().trim();
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }
  if (!reservationId || !UUID_RE.test(reservationId)) {
    return jsonResponse({ error: 'invalid_reservation_id' }, 400);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const caller = userData?.user;
  if (authError || !caller) return jsonResponse({ error: 'unauthorized' }, 401);

  const callerRole = caller.app_metadata?.role;
  if (callerRole !== 'admin') return jsonResponse({ error: 'admin_required' }, 403);

  const adminId    = caller.id;
  const adminEmail = caller.email ?? null;
  const admin = createClient(supabaseUrl, serviceKey);

  // 1. Cancela via RPC SECURITY DEFINER (audit + push in-app + status update)
  const { data: rpcData, error: rpcError } = await userClient.rpc(
    'admin_cancel_reservation_on_behalf_of',
    { p_reservation_id: reservationId, p_reason: reason || null },
  );

  if (rpcError) {
    const msg = rpcError.message ?? 'rpc_failed';
    let httpStatus = 500;
    if (msg.startsWith('reservation_not_found')) httpStatus = 404;
    else if (msg.startsWith('cannot_cancel_status')) httpStatus = 409;
    else if (msg.startsWith('NOT_ADMIN')) httpStatus = 403;
    return jsonResponse({ error: 'rpc_error', detail: msg }, httpStatus);
  }
  const r = rpcData;
  if (!r || r.success !== true) {
    return jsonResponse({ error: 'rpc_unexpected', detail: r }, 500);
  }

  if (r.idempotent === true) {
    return jsonResponse({
      success: true, idempotent: true, reservation_id: reservationId,
      message: 'already cancelled — no action taken',
      previous_status: r.status,
    });
  }

  // 2. Stripe refund se aplicavel
  const willRefund      = r.will_refund === true;
  const prepaymentPi    = r.prepayment_pi ?? null;
  const prepaymentCents = Number(r.prepayment_cents ?? 0);

  let refundResult   = 'not_applicable';
  let stripeRefundId = null;
  let stripeError    = null;
  let refundAmountEur = null;

  if (willRefund && prepaymentPi && prepaymentCents > 0 && stripeKey) {
    try {
      const refund = await stripe.refunds.create(
        { payment_intent: prepaymentPi, amount: prepaymentCents },
        { idempotencyKey: `admin-cancel-rsv-${reservationId}` },
      );
      stripeRefundId  = refund.id;
      refundAmountEur = prepaymentCents / 100.0;
      refundResult    = 'succeeded';
    } catch (e) {
      stripeError  = String(e?.message ?? e);
      refundResult = 'failed';
      console.error('[admin-cancel-reservation] stripe refund failed:', stripeError);
    }
  } else if (willRefund && !prepaymentPi) {
    refundResult = 'no_payment_intent';
  } else if (!willRefund) {
    refundResult = 'forfeited_window'; // <2h, Bora retem
  }

  // 3. Audit
  try {
    await admin.from('admin_audit_log').insert({
      admin_id: adminId,
      admin_email: adminEmail,
      action: 'reservation_cancel_complete',
      entity_type: 'reservation',
      entity_id: reservationId,
      details: {
        new_status: r.status,
        will_refund: willRefund,
        refund_result: refundResult,
        refund_id: stripeRefundId,
        refund_amount: refundAmountEur,
        stripe_error: stripeError,
        prepayment_cents: prepaymentCents,
        hours_until: r.hours_until_reservation,
        reason: reason || null,
      },
    });
  } catch (e) {
    console.error('[admin-cancel-reservation] audit insert failed:', e);
  }

  return jsonResponse({
    success: true,
    idempotent: false,
    reservation_id: reservationId,
    new_status: r.status,
    refund: {
      result: refundResult,
      stripe_id: stripeRefundId,
      amount: refundAmountEur,
      error: stripeError,
    },
  });
});
