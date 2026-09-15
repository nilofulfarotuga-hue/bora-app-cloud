import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  CANCEL_FEE_BEFORE_DISPATCH_EUR,
  CANCEL_FEE_AFTER_ACCEPT_EUR,
  CANCEL_FEE_AFTER_PURCHASE_RATIO,
} from '../_shared/business_rules.ts';

// Suppress unused-import warnings — these constants are referenced in comments
// and will be used by the refund logic when cancel flow is implemented.
void CANCEL_FEE_BEFORE_DISPATCH_EUR;
void CANCEL_FEE_AFTER_ACCEPT_EUR;
void CANCEL_FEE_AFTER_PURCHASE_RATIO;

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

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

  // `tvde_roundtrip` (pacote ida-e-volta) NAO leva ride_id na metadata: paga um
  // VALE, e a ligacao a corrida de ida so acontece em `activate_roundtrip`
  // (tvde-plan-payment), chamado pelo cliente. Sem ride_id nao ha nada a marcar
  // aqui — fica o log explicito para nao parecer silencio.
  if (!rideId) {
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
        return; // nao mentir no payment_status se o refund nao passou
      }
    }
    // `refunded` SO quando dinheiro voltou mesmo. Zero devolvido = kept_cancel_fee.
    const newStatus = refundCents <= 0
      ? 'kept_cancel_fee'
      : (feeCents > 0 ? 'partial_refund' : 'refunded');
    await supabase.from('tvde_rides')
      .update({ payment_status: newStatus }).eq('id', rideId);
    console.warn('[stripe-webhook] tvde late payment on terminal ride:', rideId,
      'status:', ride.status, 'paid:', paidCents, 'fee:', feeCents,
      'refunded:', refundCents, '->', newStatus);
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
    return;
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
    return;
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
    }
    return;
  }
  console.warn('[stripe-webhook] tvde ride canceled by', eventType, ':', rideId, failureMsg);
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
        } catch (e) {
          console.error('[stripe-webhook] finalize fetch failed:', e);
        }
        break;
      }

      // ── Mode A (LEGACY): existing order → mark paid + dispatch ─────────
      if (!order_id) {
        console.error('[stripe-webhook] payment_intent.succeeded missing metadata.draft_id and order_id:', intent.id);
        break;
      }

      const { error } = await supabase
        .from('orders')
        .update({ payment_status: 'paid' })
        .eq('id', order_id)
        .eq('payment_status', 'pending');

      if (error) {
        console.error('[stripe-webhook] payment_intent.succeeded DB update error:', error.message);
        break;
      }
      console.log('[stripe-webhook] order marked paid:', order_id, 'intent:', intent.id);

      const { data: orderRow, error: fetchErr } = await supabase
        .from('orders')
        .select('status, is_partner_store, service_type, payment_method, restaurant_id, customer_total, final_total, total, estimated_total')
        .eq('id', order_id)
        .single();

      if (fetchErr || !orderRow) {
        console.error('[stripe-webhook] failed to fetch order after payment:', fetchErr?.message);
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
          break;
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
      } else {
        console.warn('[stripe-webhook] order payment', event.type, ':', order_id, failureMsg);
      }
      break;
    }

    // ── Charge refunded (partial or full) ────────────────────────────────────
    // Triggered by cancel flows:
    //   - before dispatch   → 1.50 EUR retained  (CANCEL_FEE_BEFORE_DISPATCH_EUR)
    //   - after acceptance  → 50% retained        (CANCEL_FEE_AFTER_ACCEPT_RATIO)
    //   - after purchase    → 100% retained       (CANCEL_FEE_AFTER_PURCHASE_RATIO)
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

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
