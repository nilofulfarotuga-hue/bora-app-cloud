// =============================================================================
// PROPOSTA — NÃO APLICADA — supabase/functions/cancel-order-with-choice/index.ts  (v19)
// Base: v18 no ar (lida com get_edge_function a 10/10/2026, 325 linhas, verify_jwt=true).
// ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
// Depende de: PROPOSTA_reembolso_ao_meio_de_pagamento.sql §3 (refund_choices), §4 (wallet_credit_refund_100),
//             §5 (devolver_tokens_do_pedido). Aplicar o SQL ANTES desta Edge.
//
// v19 (10/10/2026 — regra do Danilo "reembolso ao meio de pagamento"):
//   • MB Way → 100 % volta ao MB Way, sempre (ignora refund_method='wallet'). Sem tokens.
//   • Cartão → 100 % volta ao cartão por defeito. 'wallet' só com consentimento: grava-se
//     refund_choices (texto mostrado + versão da app) e credita-se 100 % saldo (sem tokens).
//   • Pagamento ainda não cobrado (requires_action / requires_payment_method / requires_capture /
//     requires_confirmation) → paymentIntents.cancel (o cliente não chega a pagar).
//   • Sem estafeta atribuído → taxa 0, SEMPRE (não depende do platform_settings nem do fallback 1,50 €).
//   • A parte paga com saldo volta ao saldo (100 %); os tokens usados voltam como TOKENS.
//   • Chave Stripe por pedido: `cowc-v19-${orderId}` (deixa de colidir com a Edge `refund`,
//     que usa `refund-${pi}-${cents}`).
//   • refund_status='pending' até o stripe-webhook confirmar (notificar_reembolso_confirmado).
//   • refund_method deixa de ser obrigatório (sem campo = meio original), para a app antiga não partir.
// =============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getCancelFees, computeCancelFeeEur } from '../_shared/platform_settings.ts';
import { corsHeaders } from '../_shared/cors.ts';
import { lerPagoDoPedido } from '../_shared/cobranca_stripe.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (body: unknown, status = 200) =>
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

// Estados da Stripe em que o dinheiro ainda NÃO saiu do cliente → cancela-se a reserva.
const PI_CANCELAVEL = new Set([
  'requires_payment_method', 'requires_confirmation', 'requires_action', 'requires_capture',
]);

const TEXTO_CONSENTIMENTO_PADRAO = 'Quero já em saldo na carteira';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !serviceKey || !anonKey) return json({ error: 'server_misconfigured' }, 500);

  let orderId: string | undefined;
  let reason: string | undefined;
  let pedeCarteira = false;
  let textoConsentimento = TEXTO_CONSENTIMENTO_PADRAO;
  let appVersion: string | null = null;
  let plataforma: string | null = null;
  try {
    const body = await req.json();
    orderId = body?.order_id;
    reason = typeof body?.reason === 'string' ? body.reason : undefined;
    // v19: 'wallet' = o cliente carregou em "Quero já em saldo na carteira". Qualquer outro valor
    // (ou nenhum) = meio de pagamento original.
    pedeCarteira = body?.refund_method === 'wallet';
    if (typeof body?.consent_text === 'string' && body.consent_text.trim().length >= 3) {
      textoConsentimento = body.consent_text.trim().slice(0, 300);
    }
    appVersion = typeof body?.app_version === 'string' ? body.app_version.slice(0, 40) : null;
    plataforma = typeof body?.platform === 'string' ? body.platform.slice(0, 20) : null;
  } catch (_) {
    return json({ error: 'invalid_body' }, 400);
  }
  if (!orderId) return json({ error: 'order_id required' }, 400);
  if (!reason || reason.trim().length < 3) return json({ error: 'reason_required' }, 400);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return json({ error: 'missing_token' }, 401);
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) return json({ error: 'unauthorized' }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select(
      'id, user_id, status, payment_method, payment_intent_id, payment_status, ' +
        'total, estimated_total, final_total, customer_total, refund_amount, assigned_driver_id, ' +
        'stripe_charge_cents, wallet_applied_cents, tokens_applied_value_cents, refund_status',
    )
    .eq('id', orderId)
    .maybeSingle();
  if (orderErr || !order) return json({ error: 'order_not_found' }, 404);
  if (order.user_id !== user.id) return json({ error: 'not_your_order' }, 403);

  const t = tier(order.status);
  if (t === 'invalid') return json({ error: 'cannot_cancel_at_status', status: order.status }, 409);

  // Trava contra duplo toque (igual à v18).
  const refundStatusAntes = order.refund_status ?? null;
  const { data: reservado, error: resErr } = await admin.from('orders')
    .update({ refund_status: 'processing' })
    .eq('id', orderId).eq('user_id', user.id).neq('status', 'cancelled')
    .or('refund_status.is.null,refund_status.not.in.(processing,needs_review)')
    .select('id');
  if (resErr) return json({ error: 'db_reserve_failed', details: resErr.message }, 500);
  if (!reservado || reservado.length === 0) return json({ error: 'cancellation_in_progress' }, 409);
  const libertar = async () => {
    await admin.from('orders').update({ refund_status: refundStatusAntes })
      .eq('id', orderId).eq('refund_status', 'processing');
  };

  const semEstafeta = order.assigned_driver_id == null;
  const totalEur = Number(order.customer_total ?? order.final_total ?? order.total ?? order.estimated_total ?? 0);
  // v19: sem estafeta → taxa 0, sempre (regra do Danilo; não depende do fallback de 1,50 €).
  const fee = semEstafeta ? 0 : Number(computeCancelFeeEur(t, totalEur, await getCancelFees()).toFixed(2));
  const feeCents = Math.round(fee * 100);

  let pago;
  try { pago = await lerPagoDoPedido(admin, Deno.env.get('STRIPE_SECRET_KEY') ?? '', orderId); }
  catch (e) { await libertar(); return json({ error: 'paid_unknown', details: String(e) }, 502); }

  const meio = order.payment_method as 'card' | 'mbway' | 'cash' | string;
  const pagoOnline = meio === 'card' || meio === 'mbway';
  // MB Way volta sempre ao MB Way; cartão só vai para a carteira se o cliente o pediu.
  const destino: 'meio_original' | 'carteira' = (meio === 'card' && pedeCarteira) ? 'carteira' : 'meio_original';

  let stripeRefundId: string | undefined;
  let stripeCents = 0;          // devolvido ao cartão/MB Way
  let carteiraCents = 0;        // creditado em saldo (parte paga com saldo + consentimento)
  let tokensDevolvidos = 0;
  let piCancelado = false;
  let cancelFeeDebited = false;
  let cancelFeeDebitResult: unknown = null;

  // ---------------------------------------------------------------------------
  // 1) Pagamento online ainda não cobrado → cancela a reserva na Stripe.
  // ---------------------------------------------------------------------------
  if (pagoOnline && pago.piId && pago.piStatus && PI_CANCELAVEL.has(pago.piStatus)) {
    try {
      await stripe.paymentIntents.cancel(pago.piId,
        { cancellation_reason: 'requested_by_customer' },
        { idempotencyKey: `cowc-v19-cancel-${pago.piId}` });
      piCancelado = true;
    } catch (e) {
      // Se não deu para cancelar (ex.: o MB Way foi aprovado neste segundo), continua: o webhook
      // payment_intent.succeeded num pedido cancelado avisa o admin (v36 L373-382).
      console.error('[cancel-with-choice v19] paymentIntents.cancel falhou:', e);
    }
  }

  // ---------------------------------------------------------------------------
  // 2) Quanto se devolve: tudo o que foi pago, menos a taxa (só há taxa com estafeta).
  //    A taxa sai primeiro do que foi pago na Stripe; tokens nunca pagam taxa.
  // ---------------------------------------------------------------------------
  const stripeDisponivel = pago.stripeDisponivelCents;          // cobrado − já devolvido (lido na Stripe)
  const walletPago = pago.walletCents;                           // pago com saldo
  const stripeADevolver = Math.max(0, stripeDisponivel - feeCents);
  const feeRestante = Math.max(0, feeCents - stripeDisponivel);
  const walletADevolver = Math.max(0, walletPago - feeRestante);

  try {
    if (stripeADevolver > 0) {
      if (destino === 'meio_original') {
        const refund = await stripe.refunds.create(
          { payment_intent: pago.piId!, amount: stripeADevolver,
            metadata: { order_id: orderId, kind: 'order_cancel_client', origem: 'cancel-order-with-choice-v19' } },
          { idempotencyKey: `cowc-v19-${orderId}` },
        );
        stripeRefundId = refund.id;
        stripeCents = stripeADevolver;
        await admin.from('orders').update({ refund_id: refund.id }).eq('id', orderId);  // o banco sabe já
      } else {
        // cartão + "Quero já em saldo na carteira": consentimento primeiro, crédito depois (100 % saldo)
        const { error: cErr } = await admin.from('refund_choices').insert({
          vertical: 'order', referencia_id: orderId, user_id: user.id, escolha: 'carteira',
          meio_pagamento: meio, valor_cents: stripeADevolver, texto_mostrado: textoConsentimento,
          app_version: appVersion, plataforma,
        });
        // 23505 = já existia (2.º toque): segue, o crédito é idempotente
        if (cErr && (cErr as { code?: string }).code !== '23505') throw new Error(`consentimento_nao_gravado: ${cErr.message}`);
        const { data: w, error: wErr } = await admin.rpc('wallet_credit_refund_100', {
          p_order_id: orderId, p_user_id: user.id, p_cents: stripeADevolver,
          p_reason: `Cancelamento ${orderId.substring(0, 8)}: ${reason} — em saldo a pedido do cliente`,
          p_origem: 'consentimento_cliente',
        });
        if (wErr) throw new Error(`carteira_falhou: ${wErr.message}`);
        if (!(w as { already_applied?: boolean })?.already_applied) carteiraCents += stripeADevolver;
      }
    }

    if (walletADevolver > 0) {
      const { data: w2, error: w2Err } = await admin.rpc('wallet_credit_refund_100', {
        p_order_id: orderId, p_user_id: user.id, p_cents: walletADevolver,
        p_reason: `Cancelamento ${orderId.substring(0, 8)}: devolução da parte paga com saldo`,
        p_origem: 'parte_paga_com_carteira',
      });
      if (w2Err) throw new Error(`saldo_falhou: ${w2Err.message}`);
      if (!(w2 as { already_applied?: boolean })?.already_applied) carteiraCents += walletADevolver;
    }

    // tokens usados voltam como tokens (só se a taxa não os consumiu e se houver prova)
    if (feeRestante <= walletPago) {
      const { data: tk } = await admin.rpc('devolver_tokens_do_pedido', {
        p_order_id: orderId, p_motivo: `cancelamento_cliente: ${reason}`,
      });
      tokensDevolvidos = Number((tk as { tokens?: number })?.tokens ?? 0);
    }
  } catch (e) {
    console.error('[cancel-with-choice v19] dinheiro falhou:', e);
    if (stripeRefundId) {
      await admin.from('orders').update({ refund_status: 'needs_review' }).eq('id', orderId);
    } else {
      await libertar();
    }
    try {
      await admin.functions.invoke('notify-admin-urgent', {
        body: { kind: 'cancel_refund_failed', order_id: orderId, user_id: user.id, error: String(e) },
      });
    } catch (_) { /* fire-and-forget */ }
    return json({ error: 'refund_failed', details: String(e), refund_id: stripeRefundId ?? null }, 502);
  }

  // ---------------------------------------------------------------------------
  // 3) Dinheiro vivo / nada pago: só há taxa com estafeta (v11 mantém-se, mas sem estafeta fee=0).
  // ---------------------------------------------------------------------------
  const nadaPago = stripeDisponivel === 0 && walletPago === 0;
  if (nadaPago && feeCents > 0 && (meio === 'cash' || (meio === 'mbway' && order.payment_status !== 'paid'))) {
    const { data: debitRpc, error: debitErr } = await admin.rpc('wallet_debit_cancel_fee', {
      p_user_id: user.id, p_order_id: orderId, p_fee_cents: feeCents, p_tier: t,
    });
    if (debitErr) {
      console.error('[cancel-with-choice v19] wallet_debit_cancel_fee failed:', debitErr);
      try {
        await admin.functions.invoke('notify-admin-urgent', {
          body: { kind: 'wallet_cancel_floor_exceeded', order_id: orderId, user_id: user.id, fee_cents: feeCents, tier: t, error: debitErr.message },
        });
      } catch (_) { /* fire-and-forget */ }
    } else { cancelFeeDebited = true; cancelFeeDebitResult = debitRpc; }
  }

  // ---------------------------------------------------------------------------
  // 4) Estado final do pedido (um só UPDATE)
  // ---------------------------------------------------------------------------
  const devolvidoCents = stripeCents + carteiraCents;
  const houveDevolucao = devolvidoCents > 0;
  const now = new Date().toISOString();
  const updatePayload: Record<string, unknown> = {
    status: 'cancelled',
    cancel_reason: reason,
    cancelled_at: now,
    cancellation_initiator: 'client',
    cancel_fee: fee,
    payment_status: cancelFeeDebited ? 'cancelled_with_debt'
      : piCancelado ? 'cancelled_no_charge'
      : houveDevolucao ? (feeCents > 0 ? 'partial_refund' : 'refunded')
      : nadaPago ? 'cancelled_no_charge'
      : 'refunded',   // 100 % retido pela taxa
  };
  if (houveDevolucao) {
    updatePayload.refund_amount = devolvidoCents / 100;
    updatePayload.refund_method = stripeRefundId ? 'stripe' : 'wallet';
    updatePayload.refund_status = stripeRefundId ? 'pending' : 'completed';  // 'pending' → o webhook fecha
    if (stripeRefundId) updatePayload.refund_id = stripeRefundId;
  } else {
    updatePayload.refund_status = piCancelado ? 'not_applicable' : refundStatusAntes;
  }

  const { error: updateErr } = await admin.from('orders').update(updatePayload)
    .eq('id', orderId).eq('user_id', user.id);
  if (updateErr) {
    console.error('[cancel-with-choice v19] update failed:', updateErr);
    if (houveDevolucao) await admin.from('orders').update({ refund_status: 'needs_review' }).eq('id', orderId);
    else await libertar();
    return json({ error: 'db_update_failed', details: updateErr.message }, 500);
  }

  // ---------------------------------------------------------------------------
  // 5) Aviso ao cliente (PT-PT). O "reembolso confirmado" vem depois, pelo webhook.
  // ---------------------------------------------------------------------------
  try {
    const eur = (c: number) => (c / 100).toFixed(2).replace('.', ',');
    let title = 'Pedido cancelado';
    let message = 'O pedido foi cancelado.';
    if (piCancelado && !houveDevolucao) {
      message = 'O pedido foi cancelado. O pagamento não chegou a ser cobrado.';
    } else if (stripeRefundId && meio === 'mbway') {
      title = 'Reembolso a caminho';
      message = `Devolvemos ${eur(stripeCents)} € ao teu MB Way. Avisamos-te quando estiver confirmado.`;
    } else if (stripeRefundId) {
      title = 'Reembolso a caminho';
      message = `Devolvemos ${eur(stripeCents)} € ao teu cartão. Pode demorar 5 a 10 dias úteis a aparecer no extrato.`;
    } else if (carteiraCents > 0) {
      title = 'Saldo Bora';
      message = `${eur(carteiraCents)} € já estão no teu saldo Bora.`;
    } else if (cancelFeeDebited) {
      message = `Pedido cancelado. A taxa de cancelamento de ${eur(feeCents)} € fica para o próximo pedido.`;
    }
    if (stripeRefundId && carteiraCents > 0) {
      message += ` A parte paga com saldo (${eur(carteiraCents)} €) voltou ao teu saldo Bora.`;
    }
    if (tokensDevolvidos > 0) message += ` Os teus ${tokensDevolvidos} tokens voltaram à tua conta.`;
    await admin.functions.invoke('notify-client', {
      body: { user_id: user.id, title, body: message,
              data: { order_id: orderId, destino, refund_id: stripeRefundId ?? null, pi_cancelado: piCancelado } },
    });
  } catch (e) {
    console.warn('[cancel-with-choice v19] notify failed (non-fatal):', e);
  }

  return json({
    ok: true,
    tier: t,
    sem_estafeta: semEstafeta,
    fee_eur: fee,
    destino,
    refund_eur: devolvidoCents / 100,
    refund_stripe_eur: stripeCents / 100,
    refund_carteira_eur: carteiraCents / 100,
    refund_method: stripeRefundId ? 'stripe' : (carteiraCents > 0 ? 'wallet' : null),
    refund_id: stripeRefundId ?? null,
    pi_cancelado: piCancelado,
    tokens_devolvidos: tokensDevolvidos,
    cancel_fee_debited: cancelFeeDebited,
    cancel_fee_debit: cancelFeeDebitResult,
  });
});
