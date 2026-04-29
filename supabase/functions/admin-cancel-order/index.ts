// supabase/functions/admin-cancel-order/index.ts
//
// FASE 4 · BUG 3 · M3 — Admin order cancellation orchestrator.
//
// Responsibilities:
//   1. Authenticate caller (anon client + JWT) and gate by app_metadata.role='admin'
//   2. Call public.admin_cancel_order RPC with caller JWT (preserves auth.uid()
//      for _admin_op_guard inside the RPC). RPC marks the order atomically.
//   3. If RPC returns idempotent=true → silent success (RPC already logged
//      order_cancel_idempotent; we don't re-do Stripe nor notifications).
//   4. If non-idempotent + refund_status='pending' + still pending in DB
//      (defensive read) → issue Stripe refund with idempotency key
//      `admin-cancel-{order_id}` for FULL `total` (Bora absorbs partial
//      losses per Q4). Update orders refund_* columns.
//   5. Fire-and-forget 3 notifications (Promise.allSettled):
//        notify-client  → custom title/body in PT (mapping per reason_code)
//        notify-driver  → if assigned_driver_id (best-fit; existing fn limits)
//        notify-partner → if restaurant_id (opaque message)
//   6. Audit row 'order_cancel_complete' with side-effect summary.
//
// Errors policy:
//   - Stripe failure → audit + ordem fica cancelled+refund_status='failed',
//     return 200 com warning (cancellation not blocked by refund).
//   - Notification failure → audit counts, return 200.
//   - RPC error / auth error → 4xx/5xx with clear message.
//
// Pattern reference:
//   - delete-account / admin-force-driver-logout (auth gate)
//   - client-cancel-order (Stripe refund inline)

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const REASON_CODES = new Set([
  'client_request', 'partner_unable', 'driver_unavailable',
  'payment_failed', 'fraud_suspected', 'address_invalid',
  'food_quality_issue', 'system_error', 'other',
]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ─── Reason → human messages ──────────────────────────────────────────────
// One source of truth, three audiences.

function refundClause(refundEur: number | null, status: string): string {
  if (status === 'not_applicable') return ''; // cash not paid → no refund mentioned
  if (refundEur && refundEur > 0) {
    return ` Reembolso de €${refundEur.toFixed(2)} em curso (3-5 dias úteis).`;
  }
  return '';
}

function mapClientMessage(
  code: string,
  refundEur: number | null,
  refundStatus: string,
  freeReason: string,
): { title: string; body: string } {
  const r = refundClause(refundEur, refundStatus);
  switch (code) {
    case 'client_request':
      return {
        title: 'Pedido cancelado',
        body: `O teu pedido foi cancelado conforme pedido.${r}`,
      };
    case 'partner_unable':
      return {
        title: 'Pedido cancelado',
        body: `O parceiro não conseguiu completar o teu pedido.${r} Pedimos desculpa.`,
      };
    case 'driver_unavailable':
      return {
        title: 'Pedido cancelado',
        body: `Não foi possível atribuir um estafeta ao teu pedido.${r} Pedimos desculpa.`,
      };
    case 'payment_failed':
      return {
        title: 'Pedido cancelado',
        body: 'Houve um problema com o pagamento e o pedido foi cancelado. Sem cobrança.',
      };
    case 'fraud_suspected':
      return {
        title: 'Pedido cancelado',
        body: 'O teu pedido foi cancelado por motivos de segurança. Contacta o suporte se tens dúvidas.',
      };
    case 'address_invalid':
      return {
        title: 'Pedido cancelado',
        body: `A morada de entrega não é válida.${r} Verifica a morada e tenta de novo.`,
      };
    case 'food_quality_issue':
      return {
        title: 'Pedido cancelado',
        body: `O teu pedido foi cancelado por questão de qualidade.${r} Pedimos desculpa.`,
      };
    case 'system_error':
      return {
        title: 'Pedido cancelado',
        body: `Erro técnico no sistema.${r} Pedimos desculpa.`,
      };
    case 'other':
    default:
      return {
        title: 'Pedido cancelado',
        body: `O teu pedido foi cancelado pela administração.${r} Contacta o suporte para mais detalhes.`,
      };
  }
}

function mapDriverMessage(code: string): string {
  // Short message for driver. Note: notify-driver currently hardcodes the
  // template; we pass this as `vendorName` which becomes the body. Tech-debt:
  // notify-driver should accept custom title/body (TODO).
  switch (code) {
    case 'partner_unable':       return 'Pedido cancelado: parceiro indisponível';
    case 'driver_unavailable':   return 'Pedido cancelado: reatribuição necessária';
    case 'payment_failed':       return 'Pedido cancelado: problema de pagamento';
    case 'fraud_suspected':      return 'Pedido cancelado pelo suporte';
    case 'address_invalid':      return 'Pedido cancelado: morada inválida';
    case 'food_quality_issue':   return 'Pedido cancelado pelo suporte';
    case 'system_error':         return 'Pedido cancelado: erro técnico';
    case 'client_request':       return 'Pedido cancelado pelo cliente';
    case 'other':
    default:                     return 'Pedido cancelado pelo suporte';
  }
}

// Partner sees opaque message — no reason_code exposed.
const PARTNER_MESSAGE = 'Pedido cancelado pelo administrador.';

// ─── Notification fire-and-forget helpers ─────────────────────────────────

async function callNotifyClient(
  client,
  payload: { clientId: string; orderId: string; title: string; body: string },
): Promise<{ ok: boolean; reason?: string }> {
  try {
    const { data, error } = await client.functions.invoke('notify-client', { body: payload });
    if (error) return { ok: false, reason: String(error?.message ?? error) };
    if (data?.ok === false) return { ok: false, reason: data.reason ?? 'unknown' };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: String(e) };
  }
}

async function callNotifyDriver(
  client,
  payload: { driverId: string; orderId: string; vendorName: string; total: number },
): Promise<{ ok: boolean; reason?: string }> {
  try {
    const { data, error } = await client.functions.invoke('notify-driver', { body: payload });
    if (error) return { ok: false, reason: String(error?.message ?? error) };
    if (data?.ok === false) return { ok: false, reason: data.reason ?? 'unknown' };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: String(e) };
  }
}

async function callNotifyPartner(
  client,
  payload: { restaurantId: string; orderId: string; items: string; total: number },
): Promise<{ ok: boolean; reason?: string }> {
  try {
    const { data, error } = await client.functions.invoke('notify-partner', { body: payload });
    if (error) return { ok: false, reason: String(error?.message ?? error) };
    if (data?.ok === false) return { ok: false, reason: data.reason ?? 'unknown' };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: String(e) };
  }
}

// ─── Main ────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST')   return jsonResponse({ error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey    = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const stripeKey  = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  // ── Parse body ───────────────────────────────────────────────────────────
  let orderId: string = '';
  let reasonCode: string = '';
  let reason: string = '';
  try {
    const body = await req.json();
    orderId    = (body?.order_id    ?? '').toString().trim();
    reasonCode = (body?.reason_code ?? '').toString().trim();
    reason     = (body?.reason      ?? '').toString().trim();
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }
  if (!orderId || !UUID_RE.test(orderId)) {
    return jsonResponse({ error: 'invalid_order_id' }, 400);
  }
  if (!REASON_CODES.has(reasonCode)) {
    return jsonResponse({ error: 'invalid_reason_code' }, 400);
  }
  if (reason.length < 3) {
    return jsonResponse({ error: 'reason_required', detail: 'min 3 chars' }, 400);
  }

  // ── Authenticate caller ──────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: userData, error: authError } = await userClient.auth.getUser();
  const caller = userData?.user;
  if (authError || !caller) return jsonResponse({ error: 'unauthorized' }, 401);

  const callerRole = (caller.app_metadata as Record<string, unknown> | null)?.role;
  if (callerRole !== 'admin') return jsonResponse({ error: 'admin_required' }, 403);

  const adminId    = caller.id;
  const adminEmail = caller.email ?? null;

  // ── Service-role client for direct work + audit ──────────────────────────
  const admin = createClient(supabaseUrl, serviceKey);

  // ── Call RPC with USER client (preserves auth.uid for _admin_op_guard) ─
  const { data: rpcData, error: rpcError } = await userClient.rpc(
    'admin_cancel_order',
    { p_order_id: orderId, p_reason_code: reasonCode, p_reason: reason },
  );

  if (rpcError) {
    const msg = rpcError.message ?? 'rpc_failed';
    let httpStatus = 500;
    if (msg.startsWith('order_not_found')) httpStatus = 404;
    else if (msg.startsWith('order_already_delivered')) httpStatus = 409;
    else if (msg.startsWith('order_already_terminal'))  httpStatus = 409;
    else if (msg.startsWith('reason_required'))         httpStatus = 400;
    else if (msg.startsWith('reason_code_required'))    httpStatus = 400;
    else if (msg.startsWith('admin_required'))          httpStatus = 403;
    return jsonResponse({ error: 'rpc_error', detail: msg }, httpStatus);
  }

  const r = rpcData as Record<string, unknown>;
  if (!r || r.success !== true) {
    return jsonResponse({ error: 'rpc_unexpected', detail: r }, 500);
  }

  // ── Idempotent path: silent success ──────────────────────────────────────
  if (r.idempotent === true) {
    return jsonResponse({
      success: true,
      idempotent: true,
      order_id: orderId,
      message: 'already cancelled — no action taken',
      previous_status: r.previous_status,
      refund_status: r.refund_status,
    });
  }

  // ── Stripe refund (defensive) ───────────────────────────────────────────
  const totalNum   = Number(r.total ?? 0);
  const paymentPI  = (r.payment_intent_id as string | null) ?? null;
  const refundInit = (r.refund_status as string | null) ?? 'not_applicable';

  let refundResult: 'succeeded' | 'failed' | 'skipped' | 'not_applicable' = 'not_applicable';
  let stripeRefundId: string | null = null;
  let stripeError: string | null = null;
  let refundAmountEur: number | null = null;

  if (refundInit === 'pending' && paymentPI && totalNum > 0 && stripeKey) {
    // Defensive read: re-check the DB refund_status in case another caller
    // already issued the refund (race protection beyond idempotency key).
    const { data: orderNow } = await admin
      .from('orders')
      .select('refund_status, refund_id')
      .eq('id', orderId)
      .maybeSingle();

    if (orderNow?.refund_status === 'succeeded') {
      refundResult = 'skipped';
      stripeRefundId = orderNow.refund_id ?? null;
    } else {
      try {
        const refund = await stripe.refunds.create(
          {
            payment_intent: paymentPI,
            amount: Math.round(totalNum * 100), // FULL refund (Q4 — Bora absorbs)
          },
          { idempotencyKey: `admin-cancel-${orderId}` },
        );
        stripeRefundId  = refund.id;
        refundAmountEur = totalNum;
        refundResult    = 'succeeded';

        await admin
          .from('orders')
          .update({
            refund_id:     refund.id,
            refund_amount: refundAmountEur,
            refund_status: 'succeeded',
            refunded_at:   new Date().toISOString(),
            payment_status: 'refunded',
          })
          .eq('id', orderId);
      } catch (e) {
        stripeError = String((e as Error).message ?? e);
        refundResult = 'failed';
        await admin
          .from('orders')
          .update({ refund_status: 'failed' })
          .eq('id', orderId);
        console.error('[admin-cancel-order] stripe refund failed:', stripeError);
      }
    }
  } else {
    refundResult = 'not_applicable';
  }

  // ── Notifications fire-and-forget paralelo ────────────────────────────────
  const userId            = (r.user_id as string | null) ?? null;
  const driverId          = (r.assigned_driver_id as string | null) ?? null;
  const restaurantId      = (r.restaurant_id as string | null) ?? null; // not in RPC payload, lookup below
  const vendorName        = (r.vendor_name as string | null) ?? '';

  // Lookup restaurant_id from orders (RPC payload doesn't include it because
  // M2 was written before M2.5; cleaner to read it now than re-spin RPC).
  let resolvedRestaurantId: string | null = restaurantId;
  if (!resolvedRestaurantId) {
    const { data: orderRow } = await admin
      .from('orders')
      .select('restaurant_id')
      .eq('id', orderId)
      .maybeSingle();
    resolvedRestaurantId = orderRow?.restaurant_id ?? null;
  }

  const clientMsg = mapClientMessage(reasonCode, refundAmountEur ?? totalNum, refundInit, reason);
  const driverShort = mapDriverMessage(reasonCode);

  const notifyTasks: Array<Promise<{ key: string; ok: boolean; reason?: string }>> = [];

  if (userId) {
    notifyTasks.push(
      callNotifyClient(admin, {
        clientId: userId,
        orderId:  orderId,
        title:    clientMsg.title,
        body:     clientMsg.body,
      }).then((res) => ({ key: 'client', ...res })),
    );
  }
  if (driverId) {
    notifyTasks.push(
      callNotifyDriver(admin, {
        driverId: driverId,
        orderId:  orderId,
        vendorName: driverShort, // hack: notify-driver template puts vendorName in body
        total:    totalNum,
      }).then((res) => ({ key: 'driver', ...res })),
    );
  }
  if (resolvedRestaurantId) {
    notifyTasks.push(
      callNotifyPartner(admin, {
        restaurantId: resolvedRestaurantId,
        orderId:      orderId,
        items:        PARTNER_MESSAGE, // notify-partner template puts items in body
        total:        totalNum,
      }).then((res) => ({ key: 'partner', ...res })),
    );
  }

  const notifyResults = await Promise.allSettled(notifyTasks);
  const notifySummary: Record<string, { ok: boolean; reason?: string }> = {};
  for (const r of notifyResults) {
    if (r.status === 'fulfilled') {
      notifySummary[r.value.key] = { ok: r.value.ok, reason: r.value.reason };
    } else {
      notifySummary['error'] = { ok: false, reason: String(r.reason) };
    }
  }

  // ── Final audit row ──────────────────────────────────────────────────────
  try {
    await admin.from('admin_audit_log').insert({
      admin_id:    adminId,
      admin_email: adminEmail,
      action:      'order_cancel_complete',
      entity_type: 'order',
      entity_id:   orderId,
      details: {
        previous_status: r.previous_status,
        reason_code:     reasonCode,
        refund_result:   refundResult,
        refund_id:       stripeRefundId,
        refund_amount:   refundAmountEur,
        refund_status_initial: refundInit,
        stripe_error:    stripeError,
        notifications:   notifySummary,
        total:           totalNum,
        payment_method:  r.payment_method,
        payment_intent_id: paymentPI,
      },
    });
  } catch (e) {
    console.error('[admin-cancel-order] audit insert failed:', e);
  }

  return jsonResponse({
    success: true,
    idempotent: false,
    order_id: orderId,
    previous_status: r.previous_status,
    refund: {
      result:    refundResult,
      stripe_id: stripeRefundId,
      amount:    refundAmountEur,
      error:     stripeError,
    },
    notifications: notifySummary,
  });
});
