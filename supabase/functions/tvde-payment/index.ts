// =============================================================================
// tvde-payment — pagamento CARD + MB WAY nas corridas TVDE.
// =============================================================================
// PADRAO UNICO (= delivery): cobra NA HORA e faz refund estilo
// `client-cancel-order` (capado ao pago, menos a taxa). SEM authorize/capture.
//
// Acoes (body.action):
//   charge  -> cria a corrida (JWT) e cobra tvde_ride_charge_cents(ride_id).
//             CARTAO devolve clientSecret; MB WAY confirma server-side.
//   confirm_ride_payment -> le o estado REAL do PI no Stripe e grava-o em
//             tvde_rides.payment_status. A UI faz poll (3s/120s). Idempotente.
//   charge_stop -> v4: parada em corrida ONLINE. Cobra tvde_stop_fee_cents
//             (cartao: clientSecret; mbway: confirm server-side c/ phone).
//             A parada NAO e adicionada aqui — so no confirm_stop_payment.
//   confirm_stop_payment -> v4: se o PI da parada estiver succeeded, ADICIONA
//             a parada (tvde_add_stop c/ payment_intent_id, como o cliente).
//             Se a adicao falhar depois de pago (ex. max atingido, corrida
//             terminou) -> REFUND automatico. Idempotente (metadata.applied).
//   refund  -> cancelamento: refund = max(0, min(pago - taxa, pago)).
// =============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey =
  STRIPE_MODE === 'test'
    ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
    : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

async function getSettingBool(key: string): Promise<boolean> {
  const { data } = await admin.rpc('get_setting', { p_key: key });
  return data === true || String(data).toLowerCase() === 'true';
}
async function getSettingInt(key: string, fallback: number): Promise<number> {
  const { data } = await admin.rpc('get_setting', { p_key: key });
  const v = Number(String(data ?? '').replace(/\"/g, ''));
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');

    // Gate #1 (server-side): kill switch. Falha fechada.
    if (!(await getSettingBool('tvde_card_payments_enabled'))) {
      return json({ error: 'card_payments_not_enabled' }, 403);
    }

    // Cliente autenticado (JWT).
    const token = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim();
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'not_authenticated' }, 401);

    // -- CHARGE — cria a corrida e cobra o VALOR DO PLANO (nao a tarifa cheia) --
    if (action === 'charge') {
      const method = String(body.method ?? '');
      if (method !== 'card' && method !== 'mbway') {
        return json({ error: 'invalid_method' }, 400);
      }
      const distanceKm = Number(body.distance_km ?? 0);
      if (!(distanceKm > 0)) return json({ error: 'invalid_distance' }, 400);

      const { data: rideRes, error: rideErr } = await userClient.rpc(
        'tvde_request_ride',
        {
          p_origin_lat: Number(body.origin_lat),
          p_origin_lng: Number(body.origin_lng),
          p_origin_label: body.origin_label ?? null,
          p_dest_lat: Number(body.dest_lat),
          p_dest_lng: Number(body.dest_lng),
          p_dest_label: body.dest_label ?? null,
          p_est_distance_km: distanceKm,
          p_payment_method: method,
        },
      );
      if (rideErr || !rideRes) {
        return json({ error: String(rideErr?.message ?? 'ride_create_failed') }, 400);
      }
      const ride = Array.isArray(rideRes) ? rideRes[0] : rideRes;

      const cancelRide = async () => {
        try {
          await userClient.rpc('tvde_cancel_ride', {
            p_ride_id: ride.id,
            p_actor: 'cliente',
            p_reason: 'payment_failed',
          });
        } catch (_) {/* best effort */}
      };

      const { data: chargeData, error: chargeErr } = await admin.rpc(
        'tvde_ride_charge_cents',
        { p_ride_id: ride.id },
      );
      if (chargeErr) {
        await cancelRide();
        return json({ error: 'charge_calc_failed' }, 500);
      }
      const amountCents = Number(chargeData ?? 0);

      if (amountCents <= 0) {
        await admin.from('tvde_rides')
          .update({ payment_status: 'not_charged' }).eq('id', ride.id);
        return json({
          ride: { ...ride, payment_status: 'not_charged' },
          paymentIntentId: null,
          clientSecret: null,
          status: 'not_charged',
        });
      }
      if (amountCents < 50) {
        await cancelRide();
        return json({ error: 'below_minimum' }, 400);
      }

      let pi: Stripe.PaymentIntent;
      try {
        if (method === 'card') {
          pi = await stripe.paymentIntents.create({
            amount: amountCents,
            currency: 'eur',
            automatic_payment_methods: { enabled: true },
            metadata: { kind: 'tvde_ride', method, ride_id: ride.id, user_id: user.id },
          });
        } else {
          const phone = String(body.phone ?? '');
          const e164 = phone.startsWith('+')
            ? phone
            : `+351${phone.replace(/\D/g, '').replace(/^0/, '')}`;
          pi = await stripe.paymentIntents.create(
            {
              amount: amountCents,
              currency: 'eur',
              payment_method_types: ['mb_way'],
              payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
              confirm: true,
              metadata: { kind: 'tvde_ride', method, ride_id: ride.id, user_id: user.id },
            },
            { idempotencyKey: `tvde_charge_${ride.id}` },
          );
        }
      } catch (err) {
        await cancelRide();
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }

      await admin
        .from('tvde_rides')
        .update({ payment_intent_id: pi.id, payment_status: pi.status })
        .eq('id', ride.id);

      return json({
        ride: { ...ride, payment_intent_id: pi.id, payment_status: pi.status },
        paymentIntentId: pi.id,
        clientSecret: method === 'card' ? pi.client_secret : null,
        status: pi.status,
      });
    }

    // -- CONFIRM_RIDE_PAYMENT — le o estado REAL do PI e grava na corrida --
    if (action === 'confirm_ride_payment') {
      const rideId = String(body.ride_id ?? '');
      if (!rideId) return json({ error: 'missing_ride_id' }, 400);

      const { data: ride } = await admin
        .from('tvde_rides')
        .select('id, client_id, payment_intent_id, payment_status')
        .eq('id', rideId)
        .maybeSingle();
      if (!ride) return json({ error: 'ride_not_found' }, 404);
      if (ride.client_id !== user.id) return json({ error: 'not_ride_owner' }, 403);

      if (!ride.payment_intent_id) {
        return json({
          ride_id: rideId,
          payment_status: ride.payment_status ?? 'not_charged',
          status: ride.payment_status ?? 'not_charged',
          succeeded: false,
          noop: true,
        });
      }

      if (ride.payment_status === 'succeeded') {
        return json({ ride_id: rideId, payment_status: 'succeeded', status: 'succeeded', succeeded: true });
      }

      let pi: Stripe.PaymentIntent;
      try {
        pi = await stripe.paymentIntents.retrieve(ride.payment_intent_id);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }

      await admin
        .from('tvde_rides')
        .update({ payment_status: pi.status })
        .eq('id', rideId);

      return json({
        ride_id: rideId,
        payment_status: pi.status,
        status: pi.status,
        succeeded: pi.status === 'succeeded',
      });
    }

    // -- CHARGE_STOP (v4) — cobra a parada (€2) numa corrida ONLINE ------------
    //    A parada so e ADICIONADA no confirm_stop_payment, quando o PI passar.
    if (action === 'charge_stop') {
      const rideId = String(body.ride_id ?? '');
      const method = String(body.method ?? '');
      if (!rideId) return json({ error: 'missing_ride_id' }, 400);
      if (method !== 'card' && method !== 'mbway') {
        return json({ error: 'invalid_method' }, 400);
      }
      const lat = Number(body.lat), lng = Number(body.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return json({ error: 'invalid_coords' }, 400);
      }

      const { data: ride } = await admin
        .from('tvde_rides')
        .select('id, client_id, status, payment_method, extra_stops_count')
        .eq('id', rideId)
        .maybeSingle();
      if (!ride) return json({ error: 'ride_not_found' }, 404);
      if (ride.client_id !== user.id) return json({ error: 'not_ride_owner' }, 403);
      if (!['motorista_a_caminho','motorista_chegou','em_andamento'].includes(ride.status)) {
        return json({ error: `invalid_ride_state_for_stop: ${ride.status}` }, 400);
      }
      if ((ride.payment_method ?? 'cash') === 'cash') {
        // Corrida em dinheiro: a parada e cobrada em mao no fim — usa tvde_add_stop direto.
        return json({ error: 'stop_cash_flow' }, 400);
      }
      const maxStops = await getSettingInt('tvde_max_stops', 2);
      if (Number(ride.extra_stops_count ?? 0) >= maxStops) {
        return json({ error: `max_stops_reached: ${maxStops}` }, 400);
      }
      const feeCents = await getSettingInt('tvde_stop_fee_cents', 200);

      let pi: Stripe.PaymentIntent;
      try {
        const meta = {
          kind: 'tvde_stop', ride_id: rideId, user_id: user.id,
          lat: String(lat), lng: String(lng),
          label: String(body.label ?? ''),
          segment_km: String(Number(body.segment_km ?? 0) || 0),
          applied: '0',
        };
        if (method === 'card') {
          pi = await stripe.paymentIntents.create({
            amount: feeCents,
            currency: 'eur',
            automatic_payment_methods: { enabled: true },
            metadata: meta,
          });
        } else {
          const phone = String(body.phone ?? '');
          const e164 = phone.startsWith('+')
            ? phone
            : `+351${phone.replace(/\D/g, '').replace(/^0/, '')}`;
          pi = await stripe.paymentIntents.create({
            amount: feeCents,
            currency: 'eur',
            payment_method_types: ['mb_way'],
            payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
            confirm: true,
            metadata: meta,
          });
        }
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }

      return json({
        paymentIntentId: pi.id,
        clientSecret: method === 'card' ? pi.client_secret : null,
        status: pi.status,
        amountCents: feeCents,
      });
    }

    // -- CONFIRM_STOP_PAYMENT (v4) — pagamento passou? adiciona a parada -------
    if (action === 'confirm_stop_payment') {
      const piId = String(body.payment_intent_id ?? '');
      if (!piId) return json({ error: 'missing_payment_intent_id' }, 400);

      let pi: Stripe.PaymentIntent;
      try {
        pi = await stripe.paymentIntents.retrieve(piId);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }
      if (pi.metadata?.kind !== 'tvde_stop') return json({ error: 'not_a_stop_pi' }, 400);
      if (pi.metadata?.user_id !== user.id) return json({ error: 'not_pi_owner' }, 403);
      const rideId = String(pi.metadata?.ride_id ?? '');

      // Idempotente: ja aplicado.
      if (pi.metadata?.applied === '1') {
        return json({ succeeded: true, already: true, ride_id: rideId, status: pi.status });
      }
      if (pi.status !== 'succeeded') {
        return json({ succeeded: false, ride_id: rideId, status: pi.status });
      }

      // Pagamento passou — adiciona a parada COMO O CLIENTE (revalida tudo na RPC).
      const { data: stopRes, error: stopErr } = await userClient.rpc('tvde_add_stop', {
        p_ride_id: rideId,
        p_lat: Number(pi.metadata.lat),
        p_lng: Number(pi.metadata.lng),
        p_label: pi.metadata.label || null,
        p_segment_km: Number(pi.metadata.segment_km ?? 0) || 0,
        p_payment_intent_id: pi.id,
      });

      if (stopErr) {
        // Pagou mas a parada nao entrou (max atingido / corrida terminou) -> refund.
        try {
          await stripe.refunds.create(
            { payment_intent: pi.id },
            { idempotencyKey: `stop-refund-${pi.id}` },
          );
        } catch (_) {/* best effort */}
        return json({
          succeeded: false,
          refunded: true,
          ride_id: rideId,
          error: String(stopErr.message ?? 'stop_add_failed'),
        });
      }

      try {
        await stripe.paymentIntents.update(pi.id, { metadata: { ...pi.metadata, applied: '1' } });
      } catch (_) {/* best effort */}

      return json({ succeeded: true, ride_id: rideId, stop: stopRes, status: 'succeeded' });
    }

    // -- REFUND — cancelamento (padrao client-cancel-order) --
    if (action === 'refund') {
      const rideId = String(body.ride_id ?? '');
      const feeCents = Math.max(0, Number(body.cancel_fee_cents ?? 0));
      const { data: ride } = await admin
        .from('tvde_rides')
        .select(
          'id, payment_intent_id, payment_status, est_fare_cents, final_fare_cents',
        )
        .eq('id', rideId)
        .maybeSingle();
      if (!ride?.payment_intent_id) return json({ ok: true, noop: true });
      if (ride.payment_status === 'refunded' || ride.payment_status === 'partial_refund') {
        return json({ ok: true, already: true });
      }
      const paidCents = Number(ride.final_fare_cents ?? ride.est_fare_cents ?? 0);
      const refundCents = Math.max(0, Math.min(paidCents - feeCents, paidCents));
      if (refundCents >= 1) {
        await stripe.refunds.create(
          { payment_intent: ride.payment_intent_id, amount: refundCents },
          { idempotencyKey: `refund-${ride.payment_intent_id}-${refundCents}` },
        );
      }
      await admin
        .from('tvde_rides')
        .update({
          payment_status: feeCents > 0 && refundCents > 0 ? 'partial_refund' : 'refunded',
        })
        .eq('id', ride.id);
      return json({ ok: true, refundCents });
    }

    return json({ error: 'unknown_action' }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return json({ error: message }, 500);
  }
});
