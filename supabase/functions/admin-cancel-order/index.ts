// supabase/functions/admin-cancel-order/index.ts
// FASE 4 BUG 3 M3 — Admin order cancellation orchestrator.
// v14 (ronda 04/10 A.2, 05/10/2026): reembolsa o valor realmente cobrado pela Stripe e devolve
// à carteira a parte paga com carteira/tokens (_shared/cobranca_stripe.ts).

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { corsHeaders } from '../_shared/cors.ts';
import { lerPagoDoPedido, repartirReembolso, totalPago } from '../_shared/cobranca_stripe.ts';

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

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function refundClause(refundEur, status) {
  if (status === 'not_applicable') return '';
  if (refundEur && refundEur > 0) {
    return ` Reembolso de €${refundEur.toFixed(2)} em curso (3-5 dias úteis).`;
  }
  return '';
}

function mapClientMessage(code, refundEur, refundStatus, freeReason) {
  const r = refundClause(refundEur, refundStatus);
  switch (code) {
    case 'client_request':
      return { title: 'Pedido cancelado', body: `O teu pedido foi cancelado conforme pedido.${r}` };
    case 'partner_unable':
      return { title: 'Pedido cancelado', body: `O parceiro não conseguiu completar o teu pedido.${r} Pedimos desculpa.` };
    case 'driver_unavailable':
      return { title: 'Pedido cancelado', body: `Não foi possível atribuir um estafeta ao teu pedido.${r} Pedimos desculpa.` };
    case 'payment_failed':
      return { title: 'Pedido cancelado', body: 'Houve um problema com o pagamento e o pedido foi cancelado. Sem cobrança.' };
    case 'fraud_suspected':
      return { title: 'Pedido cancelado', body: 'O teu pedido foi cancelado por motivos de segurança. Contacta o suporte se tens dúvidas.' };
    case 'address_invalid':
      return { title: 'Pedido cancelado', body: `A morada de entrega não é válida.${r} Verifica a morada e tenta de novo.` };
    case 'food_quality_issue':
      return { title: 'Pedido cancelado', body: `O teu pedido foi cancelado por questão de qualidade.${r} Pedimos desculpa.` };
    case 'system_error':
      return { title: 'Pedido cancelado', body: `Erro técnico no sistema.${r} Pedimos desculpa.` };
    case 'other':
    default:
      return { title: 'Pedido cancelado', body: `O teu pedido foi cancelado pela administração.${r} Contacta o suporte para mais detalhes.` };
  }
}

function mapDriverMessage(code) {
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

const PARTNER_MESSAGE = 'Pedido cancelado pelo administrador.';

async function callNotifyClient(client, payload) {
  try {
    const { data, error } = await client.functions.invoke('notify-client', { body: payload });
    if (error) return { ok: false, reason: String(error?.message ?? error) };
    if (data?.ok === false) return { ok: false, reason: data.reason ?? 'unknown' };
    return { ok: true };
  } catch (e) { return { ok: false, reason: String(e) }; }
}
async function callNotifyDriver(client, payload) {
  try {
    const { data, error } = await client.functions.invoke('notify-driver', { body: payload });
    if (error) return { ok: false, reason: String(error?.message ?? error) };
    if (data?.ok === false) return { ok: false, reason: data.reason ?? 'unknown' };
    return { ok: true };
  } catch (e) { return { ok: false, reason: String(e) }; }
}
async function callNotifyPartner(client, payload) {
  try {
    const { data, error } = await client.functions.invoke('notify-partner', { body: payload });
    if (error) return { ok: false, reason: String(error?.message ?? error) };
    if (data?.ok === false) return { ok: false, reason: data.reason ?? 'unknown' };
    return { ok: true };
  } catch (e) { return { ok: false, reason: String(e) }; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST')   return jsonResponse({ error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey    = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const stripeKey  = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  let orderId = '';
  let reasonCode = '';
  let reason = '';
  try {
    const body = await req.json();
    orderId    = (body?.order_id    ?? '').toString().trim();
    reasonCode = (body?.reason_code ?? '').toString().trim();
    reason     = (body?.reason      ?? '').toString().trim();
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }
  if (!orderId || !UUID_RE.test(orderId)) return jsonResponse({ error: 'invalid_order_id' }, 400);
  if (!REASON_CODES.has(reasonCode))      return jsonResponse({ error: 'invalid_reason_code' }, 400);
  if (reason.length < 3)                  return jsonResponse({ error: 'reason_required', detail: 'min 3 chars' }, 400);

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const caller = userData?.user;
  if (authError || !caller) return jsonResponse({ error: 'unauthorized' }, 401);

  const callerRole = (caller.app_metadata)?.role;
  if (callerRole !== 'admin') return jsonResponse({ error: 'admin_required' }, 403);

  const adminId    = caller.id;
  const adminEmail = caller.email ?? null;
  const admin = createClient(supabaseUrl, serviceKey);

  const { data: rpcData, error: rpcError } = await userClient.rpc('admin_cancel_order', {
    p_order_id: orderId, p_reason_code: reasonCode, p_reason: reason,
  });

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

  const r = rpcData;
  if (!r || r.success !== true) return jsonResponse({ error: 'rpc_unexpected', detail: r }, 500);

  if (r.idempotent === true) {
    return jsonResponse({
      success: true, idempotent: true, order_id: orderId,
      message: 'already cancelled — no action taken',
      previous_status: r.previous_status, refund_status: r.refund_status,
    });
  }

  const totalNum   = Number(r.total ?? 0);
  const paymentPI  = r.payment_intent_id ?? null;
  const refundInit = r.refund_status ?? 'not_applicable';

  let refundResult = 'not_applicable';
  let stripeRefundId = null;
  let stripeError = null;
  let refundAmountEur = null;
  let carteiraCents = 0;
  let carteiraResult = 'not_applicable';

  // v14 (ronda 04/10 A.2, 05/10/2026): devolve o que foi REALMENTE pago, por fonte.
  // Antes mandava o total inteiro à Stripe: num pedido pago em parte com carteira/tokens
  // a Stripe recusava (mais do que o cobrado) e o reembolso ficava 'failed'; e um pedido
  // pago só com carteira/tokens (sem PI) nunca devolvia nada.
  let pago = null;
  try { pago = await lerPagoDoPedido(admin, stripeKey, orderId); }
  catch (e) { stripeError = `pago_nao_lido: ${String(e?.message ?? e)}`; }

  const { data: orderNow } = await admin.from('orders')
    .select('refund_status, refund_id, payment_method').eq('id', orderId).maybeSingle();

  if (orderNow?.refund_status === 'succeeded') {
    refundResult = 'skipped';
    stripeRefundId = orderNow.refund_id ?? null;
  } else if (pago) {
    // Tudo o que foi pago (nunca acima do preço), repartido: Stripe até ao que ainda se pode
    // devolver lá; o resto (carteira/tokens) volta à carteira.
    const parte = repartirReembolso(totalPago(pago), pago);
    let stripeCentsFeitos = 0;
    // 1) cartão / MB Way
    if (paymentPI && parte.stripeCents > 0) {
      try {
        const refund = await stripe.refunds.create(
          { payment_intent: paymentPI, amount: parte.stripeCents },
          { idempotencyKey: `admin-cancel-v14-${orderId}-${parte.stripeCents}` },
        );
        stripeRefundId = refund.id;
        refundResult   = 'succeeded';
        stripeCentsFeitos = parte.stripeCents;
        // grava já o id: se o resto falhar, o banco sabe que o dinheiro saiu
        await admin.from('orders').update({ refund_id: refund.id, payment_status: 'refunded' }).eq('id', orderId);
      } catch (e) {
        stripeError = String(e?.message ?? e);
        refundResult = 'failed';
        console.error('[admin-cancel-order] stripe refund failed:', stripeError);
      }
    }
    // 2) carteira + tokens: volta à carteira (80/20 como todos os reembolsos para a carteira).
    //    A chave é o id do pedido: se outro caminho já devolveu, não devolve outra vez.
    //    Independente da Stripe: se a Stripe falhar, a carteira devolve-se na mesma.
    if (parte.carteiraCents > 0 && r.user_id) {
      const { data: w, error: we } = await admin.rpc('wallet_credit_refund_split', {
        p_order_id: orderId, p_user_id: r.user_id, p_total_cents: parte.carteiraCents,
        p_reason: `admin_cancel: ${reasonCode}`, p_idempotency_key: orderId,
      });
      if (we) { carteiraResult = 'failed'; stripeError = (stripeError ? stripeError + ' | ' : '') + `carteira: ${we.message}`; }
      else { carteiraResult = w?.already_applied ? 'already_applied' : 'succeeded'; carteiraCents = w?.already_applied ? 0 : parte.carteiraCents; }
    }

    const devolvidoCents = stripeCentsFeitos + carteiraCents;
    if (refundResult === 'failed') {
      // nada saiu pela Stripe: 'failed' com o valor da parte da Stripe, para o Reprocessar
      // (reprocess-refund lê refund_amount/refund_method) devolver o certo e não 0.
      await admin.from('orders').update({
        refund_status: 'failed',
        refund_amount: parte.stripeCents / 100, refund_method: 'stripe',
      }).eq('id', orderId);
    } else if (carteiraResult === 'failed') {
      // a Stripe já devolveu (refund_id gravado) e a carteira falhou: 'needs_review' — o
      // Reprocessar só pega em 'failed', por isso não devolve a parte da Stripe outra vez.
      await admin.from('orders').update({ refund_status: 'needs_review' }).eq('id', orderId);
    } else if (devolvidoCents > 0) {
      refundAmountEur = devolvidoCents / 100;
      const upd = {
        refund_amount: refundAmountEur,
        refund_method: stripeCentsFeitos > 0 ? 'stripe' : 'wallet',
        refund_status: 'succeeded', refunded_at: new Date().toISOString(),
      };
      const { error: ue } = await admin.from('orders').update(upd).eq('id', orderId);
      if (ue) console.error('[admin-cancel-order] update refund falhou:', ue.message);
    }
  }

  const userId       = r.user_id ?? null;
  const driverId     = r.assigned_driver_id ?? null;
  const vendorName   = r.vendor_name ?? '';

  let resolvedRestaurantId = null;
  const { data: orderRow } = await admin.from('orders').select('restaurant_id').eq('id', orderId).maybeSingle();
  resolvedRestaurantId = orderRow?.restaurant_id ?? null;

  const clientMsg = mapClientMessage(reasonCode, refundAmountEur ?? 0, refundAmountEur ? 'pending' : refundInit, reason);
  const driverShort = mapDriverMessage(reasonCode);

  const notifyTasks = [];
  if (userId) {
    notifyTasks.push(
      callNotifyClient(admin, { clientId: userId, orderId, title: clientMsg.title, body: clientMsg.body })
        .then((res) => ({ key: 'client', ...res })),
    );
  }
  if (driverId) {
    notifyTasks.push(
      callNotifyDriver(admin, { driverId, orderId, vendorName: driverShort, total: totalNum })
        .then((res) => ({ key: 'driver', ...res })),
    );
  }
  if (resolvedRestaurantId) {
    notifyTasks.push(
      callNotifyPartner(admin, { restaurantId: resolvedRestaurantId, orderId, items: PARTNER_MESSAGE, total: totalNum })
        .then((res) => ({ key: 'partner', ...res })),
    );
  }

  const notifyResults = await Promise.allSettled(notifyTasks);
  const notifySummary = {};
  for (const x of notifyResults) {
    if (x.status === 'fulfilled') notifySummary[x.value.key] = { ok: x.value.ok, reason: x.value.reason };
    else notifySummary['error'] = { ok: false, reason: String(x.reason) };
  }

  try {
    await admin.from('admin_audit_log').insert({
      admin_id: adminId, admin_email: adminEmail,
      action: 'order_cancel_complete', entity_type: 'order', entity_id: orderId,
      details: {
        previous_status: r.previous_status, reason_code: reasonCode,
        refund_result: refundResult, refund_id: stripeRefundId,
        refund_amount: refundAmountEur, refund_status_initial: refundInit,
        stripe_error: stripeError, notifications: notifySummary,
        carteira_result: carteiraResult, carteira_cents: carteiraCents,
        pago: pago ? { stripe_cents: pago.stripeCents, stripe_disponivel_cents: pago.stripeDisponivelCents, wallet_cents: pago.walletCents, tokens_cents: pago.tokensCents, total_cents: pago.totalCents } : null,
        total: totalNum, payment_method: r.payment_method,
        payment_intent_id: paymentPI,
      },
    });
  } catch (e) { console.error('[admin-cancel-order] audit insert failed:', e); }

  return jsonResponse({
    success: true, idempotent: false, order_id: orderId,
    previous_status: r.previous_status,
    refund: { result: refundResult, stripe_id: stripeRefundId, amount: refundAmountEur, error: stripeError },
    notifications: notifySummary,
  });
});
