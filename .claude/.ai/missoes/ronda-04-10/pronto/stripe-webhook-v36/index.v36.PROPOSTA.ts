import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

// v36 (ronda 04/10 A.3) — falha REAL (RPC/UPDATE com erro): sobe até ao Deno.serve,
// que grava last_error em stripe_webhook_events e devolve 500 para a Stripe repetir.
// "metadata desconhecida" NÃO é falha: continua a ser só log + 200.
class FalhaWebhook extends Error {}
function falha(msg: string): never {
  throw new FalhaWebhook(msg);
}

// v36 (ronda 04/10 A.1) — grava em orders.stripe_charge_cents o que a Stripe cobrou mesmo.
// A função só escreve se o pedido tiver este PI e stripe_charge_cents ainda estiver a 0
// (idempotente; devolve false nos outros casos, o que não é erro).
async function registarCobranca(orderId: string, intent: Stripe.PaymentIntent) {
  const cents = Number(intent.amount_received ?? 0);
  if (!orderId || cents <= 0) return;
  const { data, error } = await supabase.rpc('registar_cobranca_stripe', {
    p_order_id: orderId,
    p_payment_intent_id: intent.id,
    p_cents: cents,
  });
  if (error) falha(`registar_cobranca_stripe: ${error.message} (${orderId})`);
  console.log('[stripe-webhook] cobranca registada:', orderId, cents, 'gravou:', data);
}

// v36 (ronda 04/10 A.7b) — mesmo parse do tvde-plan-payment (km pago vem dos METADATA do PI).
function parseKm(raw: unknown): number | null {
  const n = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(n) || n <= 0 || n > 500) return null;
  return Math.round(n * 100) / 100;
}

// v36 (ronda 04/10 A.7d) — gorjeta: grava o estado como o `confirm` do charge-tip
// (gravarEstado): mesmo mapeamento Stripe → tips.status, paid_at, taxa, failure_reason,
// e nunca volta atrás de succeeded/refunded.
async function tipGravarEstado(intent: Stripe.PaymentIntent) {
  const tipId = intent.metadata?.tip_id ?? '';
  if (!tipId) {
    console.error('[stripe-webhook] tip PI sem tip_id:', intent.id);
    return;
  }
  let status = 'pending';
  if (intent.status === 'succeeded') status = 'succeeded';
  else if (intent.status === 'requires_action' || intent.status === 'requires_payment_method'
    || intent.status === 'requires_confirmation') status = 'requires_action';
  else if (intent.status === 'canceled') status = 'failed';
  // deno-lint-ignore no-explicit-any
  const patch: Record<string, any> = { status, stripe_payment_intent_id: intent.id };
  if (status === 'succeeded') {
    patch.paid_at = new Date().toISOString();
    try {
      const full = await stripe.paymentIntents.retrieve(intent.id, {
        expand: ['latest_charge.balance_transaction'],
      });
      // deno-lint-ignore no-explicit-any
      const fee = (full.latest_charge as any)?.balance_transaction?.fee;
      if (typeof fee === 'number') patch.stripe_fee_cents = fee;
    } catch (_) { /* taxa é informativa */ }
  }
  if (intent.last_payment_error?.message) {
    patch.failure_reason = String(intent.last_payment_error.message).slice(0, 300);
  }
  const { error } = await supabase.from('tips').update(patch).eq('id', tipId)
    .not('status', 'in', '(succeeded,refunded)');
  if (error) falha(`tips update: ${error.message} (${tipId})`);
  console.log('[stripe-webhook] tip', tipId, '->', status, intent.id);
}

// v36 (ronda 04/10 A.7c) — lavagem: marca 'held' pela MESMA RPC do mark_held do
// carwash-checkout (valida o valor contra total_cents, idempotente, procura lavador).
async function carwashMarcarHeld(intent: Stripe.PaymentIntent) {
  const bookingId = intent.metadata?.booking_id ?? '';
  if (!bookingId) {
    console.error('[stripe-webhook] carwash PI sem booking_id:', intent.id);
    return;
  }
  const { data, error } = await supabase.rpc('confirm_carwash_payment_webhook', {
    p_booking_id: bookingId,
    p_payment_intent_id: intent.id,
    p_amount_cents: Number(intent.amount ?? 0),
  });
  if (error) falha(`confirm_carwash_payment_webhook: ${error.message} (${bookingId})`);
  // ok:false (booking_not_found / amount_mismatch) é recusa de negócio — repetir não muda nada.
  if (!(data as { ok?: boolean })?.ok) {
    console.error('[stripe-webhook] carwash recusado pela RPC:', JSON.stringify(data), intent.id);
    return;
  }
  console.log('[stripe-webhook] carwash held:', JSON.stringify(data), intent.id);
}

// ─────────────────────────────────────────────────────────────────────────────
// TVDE (2026-08-13) — corridas TVDE no webhook.
//
// Os PaymentIntents criados por `tvde-payment` / `tvde-plan-payment` levam
// metadata.kind = 'tvde_ride' | 'tvde_roundtrip' | 'tvde_stop'. Antes desta
// versao caiam TODOS no `else` do payment_intent.succeeded e so escreviam
// "missing metadata.draft_id and order_id" no log — o servidor NUNCA marcava a
// corrida como paga, logo o trigger `tr_tvde_dispatch_on_paid` ->
// `tvde_offer_to_next` -> `tr_notify_tvde_driver_on_offer` -> Edge Fn
// `notify-tvde-driver` nunca disparava e nenhum motorista era chamado.
// So o poll do cliente (`confirm_ride_payment`, 3s/120s) marcava pago — e o
// MB Way demora mais do que isso, por isso na pratica ficava por marcar.
//
// PROVA (logs de producao, 2026-08-13 19:01:45 UTC):
//   [stripe-webhook] payment_intent.succeeded missing metadata.draft_id and
//   order_id: pi_3U43sVGlT3R2jCYp0fulK3tK
// -> corrida 09c01c88-cc50-419d-951e-15c7abc033, tried_driver_ids = {}.
// ─────────────────────────────────────────────────────────────────────────────

const TVDE_TERMINAL_STATUSES = ['cancelada_cliente', 'cancelada_motorista', 'no_show'];

/** Le a corrida ligada a um PI TVDE. Devolve null (e loga) se nao existir. */
async function tvdeFetchRide(rideId: string) {
  const { data, error } = await supabase
    .from('tvde_rides')
    .select('id, status, payment_status, est_fare_cents, final_fare_cents, cancel_fee_cents')
    .eq('id', rideId)
    .maybeSingle();
  if (error) {
    console.error('[stripe-webhook] tvde ride fetch failed:', error.message, rideId);
    return null;
  }
  if (!data) console.error('[stripe-webhook] tvde ride not found:', rideId);
  return data;
}

/**
 * `payment_intent.succeeded` de um PI TVDE.
 *
 * Caminho feliz: marca `payment_status='succeeded'` e DEIXA O TRIGGER despachar.
 * Nunca chamar `tvde_offer_to_next` a mao aqui — duplicaria a oferta.
 *
 * Dinheiro que entra DEPOIS da corrida morrer: refund automatico com o mesmo
 * calculo da accao `refund` do tvde-payment — refund = max(0, min(pago-taxa, pago)).
 * "pago" vem da Stripe (`amount_received`), a unica verdade do que foi mesmo
 * cobrado; `est_fare_cents` e so a estimativa gravada na corrida.
 */
async function tvdeHandleSucceeded(intent: Stripe.PaymentIntent, kind: string) {
  const rideId = intent.metadata?.ride_id ?? '';

  // `tvde_stop` ja e fechado por `confirm_stop_payment` (que ADICIONA a parada
  // via tvde_add_stop e faz refund se a adicao falhar). Duplicar aqui criaria
  // parada a dobrar — so log, como pedido.
  if (kind === 'tvde_stop') {
    console.log('[stripe-webhook] tvde stop paid (no-op — fechado por confirm_stop_payment):',
      intent.id, 'ride:', rideId || '(sem ride_id)');
    return;
  }

  // F3d (2026-08-16): pacote comprado via tvde-plan-payment (sem ride_id) —
  // o webhook agora CRIA o vale (antes: "nada a marcar"). RPC idempotente
  // por payment_intent_id; activate_roundtrip do cliente fica como acelerador.
  if (!rideId) {
    if (kind === 'tvde_roundtrip') {
      const buyerId = intent.metadata?.user_id ?? '';
      if (!buyerId) {
        console.error('[stripe-webhook] tvde_roundtrip sem user_id — vale nao criado:', intent.id);
        return;
      }
      const { error: creditErr } = await supabase.rpc('tvde_create_roundtrip_credit', {
        p_client_id: buyerId,
        p_outbound_ride_id: null,
        p_paid_cents: Number(intent.amount_received ?? intent.amount ?? 0),
        p_payment_intent_id: intent.id,
      });
      if (creditErr) {
        console.error('[stripe-webhook] roundtrip credit (sem ride) failed:',
          creditErr.message, intent.id);
        falha(`tvde_create_roundtrip_credit (sem ride): ${creditErr.message}`); // v36 (ronda 04/10 A.3)
      } else {
        console.log('[stripe-webhook] roundtrip credit garantido (sem ride):', intent.id);
      }
      return;
    }
    console.warn('[stripe-webhook] tvde PI succeeded sem metadata.ride_id — nada a marcar:',
      intent.id, 'kind:', kind);
    return;
  }

  const ride = await tvdeFetchRide(rideId);
  if (!ride) return;

  if (TVDE_TERMINAL_STATUSES.includes(String(ride.status))) {
    const paidCents = Number(intent.amount_received ?? 0);
    const feeCents = Math.max(0, Number(ride.cancel_fee_cents ?? 0));
    const refundCents = Math.max(0, Math.min(paidCents - feeCents, paidCents));
    if (refundCents >= 1) {
      try {
        await stripe.refunds.create(
          { payment_intent: intent.id, amount: refundCents },
          { idempotencyKey: `tvde-late-refund-${intent.id}-${refundCents}` },
        );
      } catch (e) {
        console.error('[stripe-webhook] tvde late refund failed:', e, intent.id);
        // v36 (ronda 04/10 A.3): 500 → a Stripe repete; o refund tem idempotencyKey.
        falha(`tvde late refund: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    // `refunded` SO quando dinheiro voltou mesmo. Zero devolvido = kept_cancel_fee.
    const newStatus = refundCents <= 0
      ? 'kept_cancel_fee'
      : (feeCents > 0 ? 'partial_refund' : 'refunded');
    const { error: lateErr } = await supabase.from('tvde_rides')
      .update({ payment_status: newStatus }).eq('id', rideId);
    if (lateErr) falha(`tvde late payment_status: ${lateErr.message}`); // v36 (ronda 04/10 A.3)
    console.warn('[stripe-webhook] tvde late payment on terminal ride:', rideId,
      'status:', ride.status, 'paid:', paidCents, 'fee:', feeCents,
      'refunded:', refundCents, '->', newStatus);
    return;
  }

  // v36 (ronda 04/10 A.7a) — RESERVA TVDE (agendada) paga por cartão/MB Way.
  // A reserva nasce em status='agendada' + reservation_status='aguarda_pagamento'
  // (tvde-payment charge_reservation / charge_roundtrip_reservation). Até à v35 o
  // webhook só punha payment_status='succeeded' (ramo genérico) e a reserva ficava
  // em 'aguarda_pagamento' até o cliente abrir a app (confirm_*_reservation_payment).
  // Agora chama as MESMAS funções desse confirm: passa a 'a_procurar', avisa o admin e
  // oferece ao 1.º motorista — com a app fechada. Ambas são idempotentes.
  // Corre DEPOIS do bloco terminal acima: reserva morta → refund, nunca activa.
  if (kind === 'tvde_reservation') {
    const { data, error } = await supabase.rpc('tvde_reservation_mark_paid', { p_ride_id: rideId });
    if (error) falha(`tvde_reservation_mark_paid: ${error.message} (${rideId})`);
    console.log('[stripe-webhook] tvde reserva paga:', rideId, 'activou:', data, intent.id);
    return;
  }
  if (kind === 'tvde_roundtrip_reservation') {
    const { data, error } = await supabase.rpc('tvde_roundtrip_reservation_mark_paid', {
      p_ride_id: rideId, p_payment_intent_id: intent.id, p_amount_cents: Number(intent.amount ?? 0),
    });
    if (error) falha(`tvde_roundtrip_reservation_mark_paid: ${error.message} (${rideId})`);
    console.log('[stripe-webhook] tvde reserva ida-e-volta paga:', rideId, 'activou:', data, intent.id);
    return;
  }

  // F3d (2026-08-16): pacote COM corrida de ida (tvde-payment charge_roundtrip)
  // — o webhook GARANTE o vale; confirm_roundtrip_payment fica como acelerador.
  // A RPC é idempotente por PI e ela própria marca a ida como paga + liga o
  // crédito (dispara o despacho via tr_tvde_dispatch_on_paid) — termina aqui.
  // Corre DEPOIS do bloco terminal acima: corrida morta → refund, nunca vale.
  if (kind === 'tvde_roundtrip') {
    const buyerId = intent.metadata?.user_id ?? '';
    if (!buyerId) {
      console.error('[stripe-webhook] tvde_roundtrip sem user_id — vale nao criado:',
        intent.id, rideId);
      return;
    }
    const { error: creditErr } = await supabase.rpc('tvde_create_roundtrip_credit', {
      p_client_id: buyerId,
      p_outbound_ride_id: rideId,
      p_paid_cents: Number(intent.amount_received ?? intent.amount ?? 0),
      p_payment_intent_id: intent.id,
    });
    if (creditErr) {
      console.error('[stripe-webhook] roundtrip credit failed:',
        creditErr.message, intent.id, rideId);
      falha(`tvde_create_roundtrip_credit: ${creditErr.message}`); // v36 (ronda 04/10 A.3)
    }
    console.log('[stripe-webhook] roundtrip credit garantido + ida paga:',
      intent.id, 'ride:', rideId);
    return;
  }

  if (ride.payment_status === 'succeeded') {
    console.log('[stripe-webhook] tvde ride ja estava paga (idempotente):', rideId, intent.id);
    return;
  }

  const { error } = await supabase
    .from('tvde_rides')
    .update({ payment_status: 'succeeded' })
    .eq('id', rideId);
  if (error) {
    console.error('[stripe-webhook] tvde ride paid UPDATE failed:', error.message, rideId);
    falha(`tvde ride paid UPDATE: ${error.message}`); // v36 (ronda 04/10 A.3)
  }
  console.log('[stripe-webhook] tvde ride paid:', rideId, 'kind:', kind, 'intent:', intent.id);
}

/** `payment_intent.processing` — MB Way empurrado, a aguardar o cliente. */
async function tvdeHandleProcessing(intent: Stripe.PaymentIntent, kind: string) {
  const rideId = intent.metadata?.ride_id ?? '';
  if (kind === 'tvde_stop' || !rideId) return;
  const { error } = await supabase
    .from('tvde_rides')
    .update({ payment_status: 'processing' })
    .eq('id', rideId)
    .neq('payment_status', 'succeeded');
  if (error) {
    console.error('[stripe-webhook] tvde ride processing UPDATE failed:', error.message, rideId);
    falha(`tvde ride processing UPDATE: ${error.message}`); // v36 (ronda 04/10 A.3)
  }
  console.log('[stripe-webhook] tvde ride processing:', rideId, 'intent:', intent.id);
}

/** `payment_intent.payment_failed` / `.canceled` — cancela a corrida. */
async function tvdeHandleFailed(intent: Stripe.PaymentIntent, kind: string, eventType: string) {
  const rideId = intent.metadata?.ride_id ?? '';
  if (kind === 'tvde_stop' || !rideId) {
    console.warn('[stripe-webhook] tvde PI', eventType, 'sem ride_id (ou stop) — ignorado:',
      intent.id, 'kind:', kind);
    return;
  }
  const failureMsg = intent.last_payment_error?.message ?? eventType;
  // `tvde_cancel_ride` e SECURITY DEFINER e aceita admin/dono. Aqui corre com
  // service_role (auth.uid() IS NULL -> is_admin() decide), actor 'cliente'.
  const { error } = await supabase.rpc('tvde_cancel_ride', {
    p_ride_id: rideId,
    p_actor: 'cliente',
    p_reason: 'payment_failed',
  });
  if (error) {
    // `ride_already_terminal` e esperado (o cliente ja tinha cancelado) — nao e erro.
    const msg = error.message ?? '';
    if (msg.includes('ride_already_terminal')) {
      console.log('[stripe-webhook] tvde ride ja terminal em', eventType, ':', rideId);
    } else {
      console.error('[stripe-webhook] tvde cancel on', eventType, 'failed:', msg, rideId);
      falha(`tvde_cancel_ride on ${eventType}: ${msg}`); // v36 (ronda 04/10 A.3)
    }
    return;
  }
  console.warn('[stripe-webhook] tvde ride canceled by', eventType, ':', rideId, failureMsg);
}

// ─────────────────────────────────────────────────────────────────────────────
// v35 (2026-10-02) — PEDIDO CANCELADO CEDO DEMAIS PELA APP + MB WAY PAGO DEPOIS.
//
// PROVA (produção, 02/10 12:25 UTC, pedido a78990d1, Favor do cliente Divan):
//   12:25:26 create-mbway-payment-intent → status=requires_action (push MB Way
//            enviado, à espera do cliente)
//   12:25:30 a app cliente (iOS) chamou client-cancel-order → status=cancelled,
//            cancel_reason=payment_failed, payment_status=cancelled_no_charge
//   12:26:01 Stripe: payment_intent.succeeded (o cliente confirmou no MB Way)
//   → o UPDATE abaixo filtrava payment_status='pending', afectou 0 linhas,
//     logou "order marked paid" na mesma, e o dispatch não correu:
//     DINHEIRO COBRADO, PEDIDO MORTO, NENHUM ESTAFETA CHAMADO.
//
// Regra do Danilo: dinheiro que entrou tem de virar pedido vivo. Se o pedido
// foi cancelado APENAS por "payment_failed" (nunca por decisão humana) e o
// pagamento depois entrou, o webhook REATIVA o pedido (status='created',
// payment_status='pending') e deixa o fluxo normal marcar pago + despachar.
// Cancelamentos humanos (cancelled_by / cancellation_initiator preenchidos,
// ou cancel_reason diferente) NÃO são reativados — nesse caso só se avisa o
// admin para reembolsar à mão.
// ─────────────────────────────────────────────────────────────────────────────
async function reviveOrderCancelledByPaymentFailed(orderId: string, intentId: string): Promise<boolean> {
  const { data: pre, error: preErr } = await supabase
    .from('orders')
    .select('status, payment_status, cancel_reason, cancelled_by, cancellation_initiator')
    .eq('id', orderId)
    .maybeSingle();
  if (preErr || !pre) {
    console.error('[stripe-webhook] revive: fetch failed:', preErr?.message, orderId);
    return false;
  }
  if (pre.status !== 'cancelled' || pre.payment_status === 'paid') return false;

  const autoCancel = pre.cancel_reason === 'payment_failed' &&
    !pre.cancelled_by && !pre.cancellation_initiator;

  if (!autoCancel) {
    console.error('[stripe-webhook] DINHEIRO ENTROU EM PEDIDO CANCELADO (humano) — reembolsar à mão:',
      orderId, intentId, 'cancel_reason:', pre.cancel_reason);
    await supabase.rpc('notify_admin_urgent_push', {
      p_event_type: 'pagamento_em_pedido_cancelado',
      p_summary: `Pagamento ${intentId} entrou no pedido ${orderId.slice(0, 8)} já cancelado (${pre.cancel_reason ?? '?'}). Reembolsar à mão.`,
      p_entity_type: 'order',
      p_entity_id: orderId,
      p_payload: { payment_intent_id: intentId, cancel_reason: pre.cancel_reason },
      p_deep_link: `/admin/orders/${orderId}`,
    }).then(({ error }) => { if (error) console.error('[stripe-webhook] notify_admin_urgent_push failed:', error.message); });
    return false;
  }

  const { error: upErr } = await supabase
    .from('orders')
    .update({
      status: 'created',
      payment_status: 'pending',
      cancel_reason: null,
      cancelled_at: null,
      cancel_fee: null,
      status_updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)
    .eq('status', 'cancelled');
  if (upErr) {
    console.error('[stripe-webhook] revive UPDATE failed:', upErr.message, orderId);
    return false;
  }
  console.warn('[stripe-webhook] PEDIDO REATIVADO (cancelado por payment_failed, MB Way pago depois):',
    orderId, intentId);
  await supabase.rpc('notify_admin_urgent_push', {
    p_event_type: 'pedido_reativado_pos_pagamento',
    p_summary: `Pedido ${orderId.slice(0, 8)} tinha sido cancelado pela app (payment_failed) mas o MB Way foi pago — reativado e a chamar estafeta.`,
    p_entity_type: 'order',
    p_entity_id: orderId,
    p_payload: { payment_intent_id: intentId },
    p_deep_link: `/admin/orders/${orderId}`,
  }).then(({ error }) => { if (error) console.error('[stripe-webhook] notify_admin_urgent_push failed:', error.message); });
  return true;
}

Deno.serve(async (req: Request) => {
  const signature = req.headers.get('stripe-signature');
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');

  if (!signature || !webhookSecret) {
    return new Response('Missing stripe-signature or webhook secret', { status: 400 });
  }

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[stripe-webhook] signature verification failed:', msg);
    return new Response(`Webhook signature error: ${msg}`, { status: 400 });
  }

  console.log('[stripe-webhook] event:', event.type);

  // v36 (ronda 04/10 A.3) — IDEMPOTÊNCIA por event.id. A Stripe entrega "pelo menos
  // uma vez": o mesmo evento pode chegar 2x. INSERT ... ON CONFLICT DO NOTHING; se o
  // evento já foi PROCESSADO (processed_at preenchido) → 200 sem refazer nada.
  // Se a tabela não responder, NÃO se bloqueia o dinheiro: processa-se como na v35.
  let registoOk = false;
  {
    const { error: insErr } = await supabase.from('stripe_webhook_events')
      .upsert({ event_id: event.id, type: event.type },
        { onConflict: 'event_id', ignoreDuplicates: true });
    if (insErr) {
      console.error('[stripe-webhook] stripe_webhook_events insert falhou (segue sem idempotência):',
        insErr.message, event.id);
    } else {
      const { data: reg, error: regErr } = await supabase.from('stripe_webhook_events')
        .select('processed_at').eq('event_id', event.id).maybeSingle();
      if (regErr) {
        console.error('[stripe-webhook] stripe_webhook_events read falhou (segue):', regErr.message, event.id);
      } else {
        registoOk = true;
        if (reg?.processed_at) {
          console.log('[stripe-webhook] evento repetido, já processado — nada a fazer:', event.id, event.type);
          return new Response(JSON.stringify({ received: true, duplicate: true }), {
            headers: { 'Content-Type': 'application/json' },
          });
        }
      }
    }
  }

  try { // v36 (ronda 04/10 A.3) — fecha no catch depois do switch
  switch (event.type) {
    // ── Payment succeeded ────────────────────────────────────────────────────
    // BUG 1 (Fase 2 / 2026-04-30): dual routing.
    //   - metadata.draft_id  → Mode B (NEW): chama finalize-order-from-intent
    //                          que cria order via create_order(payment_already_confirmed=true).
    //   - metadata.order_id  → Mode A (LEGACY): order já existe (mbway), apenas
    //                          marca paid + dispatch.
    case 'payment_intent.succeeded': {
      const intent = event.data.object as Stripe.PaymentIntent;

      // ⭐ NOVO v26 (2026-05-16) — reservation_prepayment
      // Confirma reserva pending_payment → pending via RPC idempotente.
      // Termina aqui (não processar como order). Lock + PI validation no RPC.
      // Notifica parceiro com FCM+som (mesmo padrão do MBWay de pedidos).
      if (intent.metadata?.purpose === 'reservation_prepayment') {
        const reservationId = intent.metadata?.reservation_id;
        if (reservationId) {
          const { data, error } = await supabase.rpc(
            'confirm_reservation_payment_webhook',
            { p_reservation_id: reservationId, p_payment_intent_id: intent.id },
          );
          if (error) {
            console.error('[stripe-webhook] reservation confirm failed:',
              error.message, intent.id);
            falha(`confirm_reservation_payment_webhook: ${error.message}`); // v36 (ronda 04/10 A.3)
          } else {
            console.log('[stripe-webhook] reservation confirmed:', data, intent.id);
            // Notify partner — fire-and-forget (same pattern as MBWay orders L164).
            const { data: resRow } = await supabase
              .from('reservations')
              .select('restaurant_id, guests')
              .eq('id', reservationId)
              .maybeSingle();
            if (resRow?.restaurant_id) {
              const notifyUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/notify-partner`;
              fetch(notifyUrl, {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
                },
                body: JSON.stringify({
                  orderId: reservationId,
                  restaurantId: resRow.restaurant_id,
                  customTitle: 'Nova reserva confirmada!',
                  customBody: `Reserva para ${resRow.guests ?? '?'} pessoas confirmada com pagamento.`,
                }),
              }).catch((e: unknown) =>
                console.error('[stripe-webhook] notify-partner reservation failed:', e),
              );
            }
          }
        } else {
          console.error('[stripe-webhook] reservation_prepayment missing reservation_id:',
            intent.id);
        }
        break;
      }

      // ⭐ F3a (2026-08-16) — MARCAÇÕES (appointments). O webhook passa a ser a
      // GARANTIA do pagamento; o poll do cliente (confirm-mbway-appointment-payment
      // → RPC client_confirm_appointment_payment) fica como ACELERADOR.
      // Router: kind='appointment' (PIs novos) OU purpose='appointment_deposit'
      // (PIs em voo criados antes desta versão). RPC idempotente + valida PI.
      if (intent.metadata?.kind === 'appointment' ||
          intent.metadata?.purpose === 'appointment_deposit') {
        const appointmentId = intent.metadata?.appointment_id;
        if (appointmentId) {
          const { data, error } = await supabase.rpc(
            'confirm_appointment_payment_webhook',
            { p_appointment_id: appointmentId, p_payment_intent_id: intent.id },
          );
          if (error) {
            console.error('[stripe-webhook] appointment confirm failed:',
              error.message, intent.id);
            falha(`confirm_appointment_payment_webhook: ${error.message}`); // v36 (ronda 04/10 A.3)
          } else {
            console.log('[stripe-webhook] appointment confirmed:', data, intent.id);
          }
        } else {
          console.error('[stripe-webhook] appointment PI missing appointment_id:',
            intent.id);
        }
        break;
      }

      // ⭐ F3b (2026-08-16) — LIMPEZA (cleaning). O webhook GARANTE o 'held';
      // o mark_held do cliente (cleaning-checkout) fica como acelerador.
      // RPC idempotente + valida o valor contra total_cents.
      if (intent.metadata?.kind === 'cleaning') {
        const bookingId = intent.metadata?.booking_id;
        if (bookingId) {
          const { data, error } = await supabase.rpc(
            'confirm_cleaning_payment_webhook',
            {
              p_booking_id: bookingId,
              p_payment_intent_id: intent.id,
              p_amount_cents: Number(intent.amount_received ?? intent.amount ?? 0),
            },
          );
          if (error) {
            console.error('[stripe-webhook] cleaning held failed:', error.message, intent.id);
            falha(`confirm_cleaning_payment_webhook: ${error.message}`); // v36 (ronda 04/10 A.3)
          } else {
            console.log('[stripe-webhook] cleaning held:', data, intent.id);
          }
        } else {
          console.error('[stripe-webhook] cleaning PI missing booking_id:', intent.id);
        }
        break;
      }

      // ⭐ F3c (2026-08-16) — PLANO TVDE (kind='tvde_plan'). O webhook GARANTE a
      // ativação da subscrição; o poll 'activate' do cliente (tvde-plan-payment)
      // fica como acelerador. RPC idempotente por payment_intent_id e valida
      // pago >= preço do plano. Tem de vir ANTES do ramo genérico tvde_*
      // (senão cai no aviso "sem ride_id, nada a marcar").
      if (intent.metadata?.kind === 'tvde_plan') {
        const planUserId = intent.metadata?.user_id;
        const plan = intent.metadata?.plan;
        if (planUserId && plan) {
          const { data, error } = await supabase.rpc('tvde_activate_paid_subscription', {
            p_client_id: planUserId,
            p_plan: plan,
            p_payment_intent_id: intent.id,
            p_paid_cents: Number(intent.amount_received ?? intent.amount ?? 0),
            // v36 (ronda 04/10 A.7b) — os km pagos (e a rota) vêm dos METADATA do PI, tal
            // como no 'activate' do tvde-plan-payment. Sem isto, se o webhook chegasse
            // primeiro, o plano nascia sem km e o 'activate' já não o corrigia
            // (a função devolve a subscrição existente pelo mesmo PI).
            p_km_included: parseKm(intent.metadata?.distance_km),
            p_origin_label: intent.metadata?.origin_label ?? null,
            p_dest_label: intent.metadata?.dest_label ?? null,
          });
          if (error) {
            console.error('[stripe-webhook] tvde plan activation failed:',
              error.message, intent.id);
            // v36 (ronda 04/10 A.3): pago abaixo do preço é recusa definitiva (repetir não
            // muda nada) → fica 200 e o admin vê no log; o resto é falha real → 500.
            if (!String(error.message ?? '').includes('paid_below_plan_price')) {
              falha(`tvde_activate_paid_subscription: ${error.message}`);
            }
          } else {
            console.log('[stripe-webhook] tvde plan activated:',
              (data as { id?: string })?.id ?? data, intent.id);
          }
        } else {
          console.error('[stripe-webhook] tvde_plan PI missing user_id/plan:', intent.id);
        }
        break;
      }

      // v36 (ronda 04/10 A.7c) — LAVAGEM (MB Way chega aqui como succeeded).
      if (intent.metadata?.kind === 'carwash') {
        await carwashMarcarHeld(intent);
        break;
      }

      // v36 (ronda 04/10 A.7d) — GORJETA: grava o estado como o confirm do charge-tip.
      if (intent.metadata?.kind === 'tip') {
        await tipGravarEstado(intent);
        break;
      }

      // ⭐ TVDE (2026-08-13) — corridas TVDE. Tem de vir ANTES dos ramos
      // draft_id / order_id (entregas): um PI TVDE nao tem nenhum dos dois e
      // caia no `else` a escrever "missing metadata" sem marcar nada.
      const tvdeKind = String(intent.metadata?.kind ?? '');
      if (tvdeKind.startsWith('tvde_')) {
        await tvdeHandleSucceeded(intent, tvdeKind);
        break;
      }

      // ⭐ NOVO v23 (2026-05-12 BUG #1 frontend) — debt settle via metadata
      const debtSettleCents = parseInt(intent.metadata?.debt_settle_cents ?? '0');
      const piUserId = intent.metadata?.user_id;
      if (debtSettleCents > 0 && piUserId) {
        const { error: settleErr } = await supabase.rpc('wallet_settle_debt', {
          p_user_id: piUserId,
          p_amount_cents: debtSettleCents,
          p_source: 'stripe_pi',
          p_idem_key: 'settle_pi_' + intent.id,
        });
        if (settleErr) {
          console.error('[stripe-webhook] wallet_settle_debt failed:', settleErr.message, intent.id);
          falha(`wallet_settle_debt: ${settleErr.message}`); // v36 (ronda 04/10 A.3) — idem_key protege a repetição
        } else {
          console.log('[stripe-webhook] debt settled:', piUserId, debtSettleCents, intent.id);
        }
      }
      // ⭐ NOVO v23 — standalone debt-only PI: parar aqui (não há pedido)
      if (intent.metadata?.standalone_debt_settle === 'true') {
        break;
      }

      const draft_id = intent.metadata?.draft_id;
      const order_id = intent.metadata?.order_id;

      // ── Mode B (NEW): draft → finalize ─────────────────────────────────
      if (draft_id) {
        try {
          const finalizeUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/finalize-order-from-intent`;
          const res = await fetch(finalizeUrl, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
            },
            body: JSON.stringify({ payment_intent_id: intent.id }),
          });
          const resBody = await res.text();
          console.log('[stripe-webhook] finalize invoked:', intent.id, 'draft=', draft_id,
            'status:', res.status, 'body:', resBody);
          // v36 (ronda 04/10 A.3) — finalize com 5xx = pedido NÃO criado com dinheiro cobrado:
          // 500 para a Stripe repetir (finalize é idempotente pelo draft).
          if (res.status >= 500) falha(`finalize-order-from-intent ${res.status}: ${resBody.slice(0, 300)}`);
          // v36 (ronda 04/10 A.1) — cobrança registada também aqui (redundante com o
          // finalize v14; cobre o caso de o finalize no ar ainda ser o v13).
          let finalOrderId = '';
          try { finalOrderId = String(JSON.parse(resBody)?.order_id ?? ''); } catch (_) { /* corpo não-JSON */ }
          if (res.ok && finalOrderId) await registarCobranca(finalOrderId, intent);
        } catch (e) {
          console.error('[stripe-webhook] finalize fetch failed:', e);
          throw e; // v36 (ronda 04/10 A.3) — sem resposta do finalize → 500, a Stripe repete
        }
        break;
      }

      // ── Mode A (LEGACY): existing order → mark paid + dispatch ─────────
      if (!order_id) {
        console.error('[stripe-webhook] payment_intent.succeeded missing metadata.draft_id and order_id:', intent.id);
        break;
      }

      // v35 (2026-10-02) — se a app cancelou o pedido cedo demais (payment_failed)
      // e o MB Way foi pago a seguir, reativa ANTES de marcar pago.
      await reviveOrderCancelledByPaymentFailed(order_id, intent.id);

      const { data: paidRows, error } = await supabase
        .from('orders')
        .update({ payment_status: 'paid', payment_intent_id: intent.id })
        .eq('id', order_id)
        .eq('payment_status', 'pending')
        .select('id');

      if (error) {
        console.error('[stripe-webhook] payment_intent.succeeded DB update error:', error.message);
        falha(`orders paid UPDATE: ${error.message}`); // v36 (ronda 04/10 A.3) — antes: 200 e pedido por marcar
      }
      if (!paidRows || paidRows.length === 0) {
        // v35: antes logava "order marked paid" mesmo com 0 linhas. Agora diz a verdade.
        console.error('[stripe-webhook] order NOT marked paid (payment_status não era pending — ver estado):',
          order_id, 'intent:', intent.id);
      } else {
        console.log('[stripe-webhook] order marked paid:', order_id, 'intent:', intent.id);
      }

      // v36 (ronda 04/10 A.1) — o que a Stripe cobrou fica gravado no pedido
      // (inclui o caminho do MB Way reativado acima).
      await registarCobranca(order_id, intent);

      const { data: orderRow, error: fetchErr } = await supabase
        .from('orders')
        .select('status, is_partner_store, service_type, payment_method, restaurant_id, customer_total, final_total, total, estimated_total')
        .eq('id', order_id)
        .single();

      if (fetchErr || !orderRow) {
        console.error('[stripe-webhook] failed to fetch order after payment:', fetchErr?.message);
        if (fetchErr) falha(`orders fetch after paid: ${fetchErr.message}`); // v36 (ronda 04/10 A.3)
        break;
      }

      const currentStatus = orderRow.status as string;
      const isPartnerRestaurant =
        orderRow.is_partner_store === true && orderRow.service_type === 'restaurant';

      // v25 (2026-05-15) — MBWay partner notification gating.
      // Flutter já NÃO notifica o parceiro para MBWay (order_store.dart). A
      // notificação só dispara aqui, após payment_intent.succeeded confirmar
      // o pagamento. Card/cash continuam a ser notificados pelo Flutter no
      // momento da criação do pedido (payment_status já é paid nesse caso).
      if (isPartnerRestaurant && orderRow.payment_method === 'mbway' && orderRow.restaurant_id) {
        const totalEur = Number(
          orderRow.customer_total ?? orderRow.final_total ?? orderRow.total ?? orderRow.estimated_total ?? 0,
        );
        const notifyUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/notify-partner`;
        fetch(notifyUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({
            orderId: order_id,
            restaurantId: orderRow.restaurant_id,
            total: totalEur,
          }),
        })
          .then((r) => console.log('[stripe-webhook] notify-partner (mbway) status:', r.status, 'order:', order_id))
          .catch((e) => console.error('[stripe-webhook] notify-partner (mbway) failed:', e));
      }

      if (!isPartnerRestaurant &&
          (currentStatus === 'created' || currentStatus === 'preparing')) {

        const { error: statusErr } = await supabase
          .from('orders')
          .update({ status: 'callingDriver' })
          .eq('id', order_id)
          .in('status', ['created', 'preparing']);

        if (statusErr) {
          console.error('[stripe-webhook] failed to advance to callingDriver:', statusErr.message);
          falha(`advance callingDriver: ${statusErr.message}`); // v36 (ronda 04/10 A.3)
        }
        console.log('[stripe-webhook] order advanced to callingDriver:', order_id);

        const dispatchUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/dispatch-engine`;
        const dispatchRes = await fetch(dispatchUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({ orderId: order_id }),
        });
        console.log('[stripe-webhook] dispatch-engine invoked for order:', order_id,
          'status:', dispatchRes.status);
      } else {
        console.log('[stripe-webhook] dispatch not triggered — status:', currentStatus,
          'isPartnerRestaurant:', isPartnerRestaurant);
      }
      break;
    }

    // ── MBWay: push sent, awaiting user confirmation (no DB action needed) ──
    case 'payment_intent.processing': {
      const intent = event.data.object as Stripe.PaymentIntent;
      console.log('[stripe-webhook] payment processing (MBWay awaiting confirm):', intent.id);
      const tvdeKind = String(intent.metadata?.kind ?? '');
      if (tvdeKind.startsWith('tvde_')) {
        await tvdeHandleProcessing(intent, tvdeKind);
      }
      break;
    }

    // ── Payment failed ───────────────────────────────────────────────────────
    // Tratamos draft_id (NEW) e order_id (LEGACY).
    case 'payment_intent.payment_failed':
    case 'payment_intent.canceled': {
      const intent = event.data.object as Stripe.PaymentIntent;

      // ⭐ TVDE (2026-08-13) — antes dos ramos de reserva/draft/order.
      const tvdeKindFail = String(intent.metadata?.kind ?? '');
      if (tvdeKindFail.startsWith('tvde_')) {
        await tvdeHandleFailed(intent, tvdeKindFail, event.type);
        break;
      }

      // v36 (ronda 04/10 A.7d) — GORJETA falhada/cancelada: mesmo estado que o confirm grava.
      if (intent.metadata?.kind === 'tip') {
        await tipGravarEstado(intent);
        break;
      }

      // ⭐ F3a (2026-08-16) — MARCAÇÕES: pagamento falhou/cancelado. A marcação
      // fica pending_payment DE PROPÓSITO — o cliente pode tentar outro método
      // (MB Way falhado é retentável por cartão e vice-versa). Só log.
      if (intent.metadata?.kind === 'appointment' ||
          intent.metadata?.purpose === 'appointment_deposit') {
        console.warn('[stripe-webhook] appointment PI', event.type,
          '— marcação fica pending_payment (retry possível):',
          intent.metadata?.appointment_id ?? '?', intent.id);
        break;
      }

      // ⭐ F3b (2026-08-16) — LIMPEZA: PI falhou/cancelado. Booking fica
      // 'unpaid' DE PROPÓSITO (o cliente pode tentar outro método). Só log.
      if (intent.metadata?.kind === 'cleaning') {
        console.warn('[stripe-webhook] cleaning PI', event.type,
          '— booking fica unpaid (retry possível):',
          intent.metadata?.booking_id ?? '?', intent.id);
        break;
      }

      // ⭐ NOVO v24 (2026-05-15 BUG 1+2 reservas) — reservation orphan cleanup
      // Apaga reserva pending_payment quando o utilizador cancela o
      // PaymentSheet ou a cobrança falha. Idempotente (DELETE).
      if (intent.metadata?.purpose === 'reservation_prepayment') {
        const reservationId = intent.metadata?.reservation_id;
        if (reservationId) {
          const reason = event.type === 'payment_intent.canceled'
            ? 'user_canceled' : 'payment_failed';
          const { data, error } = await supabase.rpc('cancel_orphan_reservation', {
            p_reservation_id: reservationId,
            p_payment_intent_id: intent.id,
            p_reason: reason,
          });
          if (error) {
            console.error('[stripe-webhook] reservation cancel failed:',
              error.message, intent.id);
            falha(`cancel_orphan_reservation: ${error.message}`); // v36 (ronda 04/10 A.3)
          } else {
            console.log('[stripe-webhook] reservation orphan cleanup:', data, intent.id);
          }
        }
        break;
      }

      const draft_id = intent.metadata?.draft_id;
      const order_id = intent.metadata?.order_id;
      const failureMsg = intent.last_payment_error?.message ?? event.type;

      if (draft_id) {
        // Mode B: draft sem order. Apaga draft (sem refund — não houve cobrança).
        const { error } = await supabase
          .from('payment_drafts')
          .delete()
          .eq('id', draft_id)
          .is('used_at', null);
        if (error) {
          console.error('[stripe-webhook] draft delete failed:', error.message);
          falha(`draft delete: ${error.message}`); // v36 (ronda 04/10 A.3)
        } else {
          console.warn('[stripe-webhook] draft deleted (PI failed/canceled):', draft_id, failureMsg);
        }
        break;
      }

      if (!order_id) {
        console.error('[stripe-webhook]', event.type, 'missing metadata.draft_id and order_id:', intent.id);
        break;
      }

      // Mode A LEGACY: marcar order failed.
      const { error } = await supabase
        .from('orders')
        .update({ payment_status: 'failed' })
        .eq('id', order_id);

      if (error) {
        console.error('[stripe-webhook]', event.type, 'DB update error:', error.message);
        falha(`orders failed UPDATE: ${error.message}`); // v36 (ronda 04/10 A.3)
      } else {
        console.warn('[stripe-webhook] order payment', event.type, ':', order_id, failureMsg);
      }
      break;
    }

    // ── Charge refunded (partial or full) ────────────────────────────────────
    case 'charge.refunded': {
      const charge = event.data.object as Stripe.Charge;
      console.log('[stripe-webhook] charge refunded:', charge.id, `amount_refunded=${charge.amount_refunded}`);
      // Status update (refunded/refundPending) is handled by the Flutter client
      // via PaymentService.refund() → OrderStore.finalizePurchase().
      break;
    }

    default:
      console.log('[stripe-webhook] unhandled event type:', event.type);
  }
  } catch (e) {
    // v36 (ronda 04/10 A.3) — falha real: regista e devolve 500 → a Stripe volta a enviar.
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[stripe-webhook] FALHA a processar', event.type, event.id, '—', msg);
    if (registoOk) {
      const { error: leErr } = await supabase.from('stripe_webhook_events')
        .update({ last_error: msg.slice(0, 1000) })
        .eq('event_id', event.id);
      if (leErr) console.error('[stripe-webhook] last_error não gravado:', leErr.message);
    }
    return new Response(JSON.stringify({ received: true, error: 'processing_failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // v36 (ronda 04/10 A.3) — processado (inclui "metadata desconhecida", que é só log).
  if (registoOk) {
    const { error: doneErr } = await supabase.from('stripe_webhook_events')
      .update({ processed_at: new Date().toISOString(), last_error: null })
      .eq('event_id', event.id);
    if (doneErr) console.error('[stripe-webhook] processed_at não gravado:', doneErr.message, event.id);
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
