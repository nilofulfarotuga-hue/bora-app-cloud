// =============================================================================
// tvde-payment — pagamento CARD + MB WAY nas corridas TVDE.
// =============================================================================
// PADRAO UNICO (= delivery): cobra NA HORA e faz refund estilo
// `client-cancel-order` (capado ao pago, menos a taxa). SEM authorize/capture.
//
// v10 (2026-08-19) — RESERVA AGENDADA em CARTAO e MB WAY:
//   charge_reservation -> cria a reserva (tvde_schedule_ride) e cobra o preco
//     fechado pelo servidor (est_fare_cents). A reserva nasce em
//     reservation_status='aguarda_pagamento' e NAO procura motorista.
//   confirm_reservation_payment -> PI succeeded? chama tvde_reservation_mark_paid,
//     que liberta a procura de motorista. Idempotente.
//   auto_refund_reservation -> SO com a service_role key (chamada do servidor,
//     pelo sweep/RPC): reembolso automatico quando a reserva e cancelada ou fica
//     sem motorista, sem depender de o cliente ter a app aberta.
//   ADITIVO: v9, v6 e v5 ficam INTACTAS.
//
// v9 (2026-08-13) — missao `tvde-pagamento-tokens-despacho`:
//   - `charge` passa `p_tokens_to_apply`.
//   - `confirm_ride_payment` aceita ADMIN.
//   - `refund` exige dono/admin, le a taxa da CORRIDA e nunca grava `refunded`
//     sem dinheiro de volta -> `kept_cancel_fee`.
//
// v6 (2026-08-01) — PACOTE IDA-E-VOLTA ONLINE (charge_roundtrip /
//   confirm_roundtrip_payment), sempre com o preco do servidor.
//
// v5 (2026-07-21) — Carteira Unica: `charge` guarda/reusa cartao.
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

async function getOrCreateCustomer(userId: string): Promise<string | null> {
  try {
    const { data: userRow } = await admin
      .from('users').select('stripe_customer_id, email, name')
      .eq('id', userId).maybeSingle();
    if (userRow?.stripe_customer_id) return userRow.stripe_customer_id as string;
    const customer = await stripe.customers.create({
      email: (userRow?.email as string | undefined) ?? undefined,
      name: (userRow?.name as string | undefined) ?? undefined,
      metadata: { supabase_uid: userId },
    });
    const { error: updErr } = await admin
      .from('users').update({ stripe_customer_id: customer.id })
      .eq('id', userId).is('stripe_customer_id', null);
    if (updErr) {
      const { data: refetch } = await admin
        .from('users').select('stripe_customer_id').eq('id', userId).maybeSingle();
      const winner = refetch?.stripe_customer_id as string | undefined;
      if (winner && winner !== customer.id) {
        try { await stripe.customers.del(customer.id); } catch (_) { /* swallow */ }
        return winner;
      }
    }
    return customer.id;
  } catch (err) {
    console.error('[tvde-payment] getOrCreateCustomer error:', err);
    return null;
  }
}

async function getSettingBool(key: string): Promise<boolean> {
  const { data } = await admin.rpc('get_setting', { p_key: key });
  return data === true || String(data).toLowerCase() === 'true';
}
async function getSettingInt(key: string, fallback: number): Promise<number> {
  const { data } = await admin.rpc('get_setting', { p_key: key });
  const v = Number(String(data ?? '').replace(/\"/g, ''));
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

async function callerIsAdmin(
  userClient: ReturnType<typeof createClient>,
): Promise<boolean> {
  const { data, error } = await userClient.rpc('is_admin');
  if (error) return false;
  return data === true;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');

    const token = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim();

    // -- v10: AUTO_REFUND_RESERVATION — chamada do SERVIDOR (sweep/RPC) --------
    // Fica ANTES do kill switch de proposito: devolver dinheiro tem de funcionar
    // mesmo com os pagamentos online desligados.
    if (action === 'auto_refund_reservation') {
      if (!SERVICE_KEY || token !== SERVICE_KEY) {
        return json({ error: 'not_service_role' }, 403);
      }
      const rideId = String(body.ride_id ?? '');
      if (!rideId) return json({ error: 'missing_ride_id' }, 400);
      const { data: ride } = await admin
        .from('tvde_rides')
        .select('id, payment_intent_id, payment_status, est_fare_cents, final_fare_cents, cancel_fee_cents, scheduled_at')
        .eq('id', rideId)
        .maybeSingle();
      if (!ride) return json({ error: 'ride_not_found' }, 404);
      if (!ride.payment_intent_id) return json({ ok: true, noop: true });
      if (ride.payment_status === 'refunded' ||
          ride.payment_status === 'partial_refund' ||
          ride.payment_status === 'kept_cancel_fee') {
        return json({ ok: true, already: true });
      }
      const feeCents = Math.max(0, Number(ride.cancel_fee_cents ?? 0));
      const paidCents = Number(ride.final_fare_cents ?? ride.est_fare_cents ?? 0);
      const refundCents = Math.max(0, Math.min(paidCents - feeCents, paidCents));
      if (refundCents >= 1) {
        await stripe.refunds.create(
          { payment_intent: ride.payment_intent_id, amount: refundCents },
          { idempotencyKey: `resv-refund-${ride.payment_intent_id}-${refundCents}` },
        );
      }
      const newStatus = refundCents <= 0
        ? 'kept_cancel_fee'
        : (feeCents > 0 ? 'partial_refund' : 'refunded');
      await admin.from('tvde_rides')
        .update({ payment_status: newStatus }).eq('id', ride.id);
      console.log('[tvde-payment auto_refund_reservation]', ride.id,
        'paid:', paidCents, 'fee:', feeCents, 'refunded:', refundCents,
        'motivo:', String(body.motivo ?? ''), '->', newStatus);
      return json({ ok: true, refundCents, feeCents, paymentStatus: newStatus });
    }

    // Gate #1 (server-side): kill switch. Falha fechada.
    if (!(await getSettingBool('tvde_card_payments_enabled'))) {
      return json({ error: 'card_payments_not_enabled' }, 403);
    }

    // Cliente autenticado (JWT).
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
      const tokensUsed = Math.max(0, Math.trunc(Number(body.tokens_used ?? 0)) || 0);

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
          p_tokens_to_apply: tokensUsed,
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
          const customerId = await getOrCreateCustomer(user.id);
          const savedPmId = typeof body.saved_pm_id === 'string' ? body.saved_pm_id : null;
          const meta = { kind: 'tvde_ride', method, ride_id: ride.id, user_id: user.id };
          if (savedPmId && customerId) {
            pi = await stripe.paymentIntents.create({
              amount: amountCents,
              currency: 'eur',
              customer: customerId,
              payment_method: savedPmId,
              confirm: true,
              off_session: true,
              automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
              metadata: meta,
            });
          } else {
            pi = await stripe.paymentIntents.create({
              amount: amountCents,
              currency: 'eur',
              ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
              automatic_payment_methods: { enabled: true },
              metadata: meta,
            });
          }
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
        // deno-lint-ignore no-explicit-any
        const anyErr = err as any;
        const authPi = anyErr?.raw?.payment_intent ?? anyErr?.payment_intent;
        if (authPi?.id) {
          await admin
            .from('tvde_rides')
            .update({ payment_intent_id: authPi.id, payment_status: authPi.status })
            .eq('id', ride.id);
          return json({
            ride: { ...ride, payment_intent_id: authPi.id, payment_status: authPi.status },
            paymentIntentId: authPi.id,
            clientSecret: authPi.client_secret,
            status: authPi.status,
            requiresAction: true,
          });
        }
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
        requiresAction: pi.status === 'requires_action',
      });
    }

    // -- CHARGE_ROUNDTRIP (v6) — cria a corrida de IDA e cobra o PACOTE --------
    if (action === 'charge_roundtrip') {
      const method = String(body.method ?? '');
      if (method !== 'card' && method !== 'mbway') {
        return json({ error: 'invalid_method' }, 400);
      }
      const distanceKm = Number(body.distance_km ?? 0);
      if (!(distanceKm > 0)) return json({ error: 'invalid_distance' }, 400);

      const { data: priceData, error: priceErr } = await admin.rpc(
        'tvde_roundtrip_price_for_km',
        { p_distance_km: distanceKm },
      );
      const amountCents = Number(priceData ?? 0);
      if (priceErr || !(amountCents >= 50)) {
        return json({ error: 'roundtrip_price_failed' }, 500);
      }

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

      let pi: Stripe.PaymentIntent;
      const meta = {
        kind: 'tvde_roundtrip',
        method,
        ride_id: ride.id,
        user_id: user.id,
        distance_km: String(distanceKm),
        applied: '0',
      };
      try {
        if (method === 'card') {
          const customerId = await getOrCreateCustomer(user.id);
          const savedPmId = typeof body.saved_pm_id === 'string' ? body.saved_pm_id : null;
          if (savedPmId && customerId) {
            pi = await stripe.paymentIntents.create({
              amount: amountCents,
              currency: 'eur',
              customer: customerId,
              payment_method: savedPmId,
              confirm: true,
              off_session: true,
              automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
              metadata: meta,
            });
          } else {
            pi = await stripe.paymentIntents.create({
              amount: amountCents,
              currency: 'eur',
              ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
              automatic_payment_methods: { enabled: true },
              metadata: meta,
            });
          }
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
              metadata: meta,
            },
            { idempotencyKey: `tvde_roundtrip_${ride.id}` },
          );
        }
      } catch (err) {
        // deno-lint-ignore no-explicit-any
        const anyErr = err as any;
        const authPi = anyErr?.raw?.payment_intent ?? anyErr?.payment_intent;
        if (authPi?.id) {
          await admin
            .from('tvde_rides')
            .update({ payment_intent_id: authPi.id, payment_status: authPi.status })
            .eq('id', ride.id);
          return json({
            ride: { ...ride, payment_intent_id: authPi.id, payment_status: authPi.status },
            paymentIntentId: authPi.id,
            clientSecret: authPi.client_secret,
            status: authPi.status,
            amountCents,
            requiresAction: true,
          });
        }
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
        amountCents,
        requiresAction: pi.status === 'requires_action',
      });
    }

    // -- CONFIRM_ROUNDTRIP_PAYMENT (v6) — PI pago? cria o vale ----------------
    if (action === 'confirm_roundtrip_payment') {
      const piId = String(body.payment_intent_id ?? '');
      if (!piId) return json({ error: 'missing_payment_intent_id' }, 400);

      let pi: Stripe.PaymentIntent;
      try {
        pi = await stripe.paymentIntents.retrieve(piId);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }
      if (pi.metadata?.kind !== 'tvde_roundtrip') {
        return json({ error: 'not_a_roundtrip_pi' }, 400);
      }
      if (pi.metadata?.user_id !== user.id) return json({ error: 'not_pi_owner' }, 403);
      const rideId = String(pi.metadata?.ride_id ?? '');

      await admin
        .from('tvde_rides')
        .update({ payment_status: pi.status })
        .eq('id', rideId);

      if (pi.status !== 'succeeded') {
        return json({ succeeded: false, ride_id: rideId, status: pi.status });
      }

      const { data: creditRes, error: creditErr } = await admin.rpc(
        'tvde_create_roundtrip_credit',
        {
          p_client_id: user.id,
          p_outbound_ride_id: rideId,
          p_paid_cents: pi.amount,
          p_payment_intent_id: pi.id,
        },
      );
      if (creditErr) {
        console.error('[tvde-payment] roundtrip credit failed:', creditErr.message, pi.id);
        return json({
          succeeded: true,
          credit_created: false,
          ride_id: rideId,
          status: 'succeeded',
          error: String(creditErr.message ?? 'credit_create_failed'),
        }, 500);
      }

      return json({
        succeeded: true,
        credit_created: true,
        ride_id: rideId,
        status: 'succeeded',
        amountCents: pi.amount,
        credit: Array.isArray(creditRes) ? creditRes[0] : creditRes,
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
      if (ride.client_id !== user.id && !(await callerIsAdmin(userClient))) {
        return json({ error: 'not_ride_owner' }, 403);
      }

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

    // -- CHARGE_STOP (v4) — cobra a parada numa corrida ONLINE ------------
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

      if (pi.metadata?.applied === '1') {
        return json({ succeeded: true, already: true, ride_id: rideId, status: pi.status });
      }
      if (pi.status !== 'succeeded') {
        return json({ succeeded: false, ride_id: rideId, status: pi.status });
      }

      const { data: stopRes, error: stopErr } = await userClient.rpc('tvde_add_stop', {
        p_ride_id: rideId,
        p_lat: Number(pi.metadata.lat),
        p_lng: Number(pi.metadata.lng),
        p_label: pi.metadata.label || null,
        p_segment_km: Number(pi.metadata.segment_km ?? 0) || 0,
        p_payment_intent_id: pi.id,
      });

      if (stopErr) {
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

    // == v10 (2026-08-19) — RESERVA AGENDADA em CARTAO e MB WAY ==============
    if (action === 'charge_reservation') {
      const method = String(body.method ?? '');
      if (method !== 'card' && method !== 'mbway') return json({ error: 'invalid_method' }, 400);
      const distanceKm = Number(body.distance_km ?? 0);
      if (!(distanceKm > 0)) return json({ error: 'invalid_distance' }, 400);
      const scheduledAt = String(body.scheduled_at ?? '');
      if (!scheduledAt) return json({ error: 'missing_scheduled_at' }, 400);

      const { data: rideRes, error: rideErr } = await userClient.rpc('tvde_schedule_ride', {
        p_origin_lat: Number(body.origin_lat),
        p_origin_lng: Number(body.origin_lng),
        p_origin_label: body.origin_label ?? null,
        p_dest_lat: Number(body.dest_lat),
        p_dest_lng: Number(body.dest_lng),
        p_dest_label: body.dest_label ?? null,
        p_est_distance_km: distanceKm,
        p_scheduled_at: scheduledAt,
        p_payment_method: method,
        p_note: body.note ?? null,
      });
      if (rideErr || !rideRes) {
        return json({ error: String(rideErr?.message ?? 'reservation_create_failed') }, 400);
      }
      const ride = Array.isArray(rideRes) ? rideRes[0] : rideRes;

      const dropReservation = async () => {
        try {
          await userClient.rpc('tvde_cancel_reservation', {
            p_ride_id: ride.id, p_reason: 'payment_failed',
          });
        } catch (_) {/* best effort */}
      };

      const amountCents = Number(ride.est_fare_cents ?? 0);
      if (amountCents < 50) { await dropReservation(); return json({ error: 'below_minimum' }, 400); }

      let pi: Stripe.PaymentIntent;
      const meta = {
        kind: 'tvde_reservation', method, ride_id: ride.id, user_id: user.id,
        scheduled_at: scheduledAt,
      };
      try {
        if (method === 'card') {
          const customerId = await getOrCreateCustomer(user.id);
          const savedPmId = typeof body.saved_pm_id === 'string' ? body.saved_pm_id : null;
          if (savedPmId && customerId) {
            pi = await stripe.paymentIntents.create({
              amount: amountCents, currency: 'eur', customer: customerId,
              payment_method: savedPmId, confirm: true, off_session: true,
              automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
              metadata: meta,
            });
          } else {
            pi = await stripe.paymentIntents.create({
              amount: amountCents, currency: 'eur',
              ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
              automatic_payment_methods: { enabled: true },
              metadata: meta,
            });
          }
        } else {
          const phone = String(body.phone ?? '');
          const e164 = phone.startsWith('+')
            ? phone
            : `+351${phone.replace(/\D/g, '').replace(/^0/, '')}`;
          pi = await stripe.paymentIntents.create(
            {
              amount: amountCents, currency: 'eur',
              payment_method_types: ['mb_way'],
              payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
              confirm: true, metadata: meta,
            },
            { idempotencyKey: `tvde_reservation_${ride.id}` },
          );
        }
      } catch (err) {
        // deno-lint-ignore no-explicit-any
        const anyErr = err as any;
        const authPi = anyErr?.raw?.payment_intent ?? anyErr?.payment_intent;
        if (authPi?.id) {
          await admin.from('tvde_rides')
            .update({ payment_intent_id: authPi.id, payment_status: authPi.status })
            .eq('id', ride.id);
          return json({
            ride: { ...ride, payment_intent_id: authPi.id, payment_status: authPi.status },
            paymentIntentId: authPi.id, clientSecret: authPi.client_secret,
            status: authPi.status, amountCents, requiresAction: true,
          });
        }
        await dropReservation();
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }

      await admin.from('tvde_rides')
        .update({ payment_intent_id: pi.id, payment_status: pi.status })
        .eq('id', ride.id);

      return json({
        ride: { ...ride, payment_intent_id: pi.id, payment_status: pi.status },
        paymentIntentId: pi.id,
        clientSecret: method === 'card' ? pi.client_secret : null,
        status: pi.status, amountCents,
        requiresAction: pi.status === 'requires_action',
      });
    }

    if (action === 'confirm_reservation_payment') {
      const piId = String(body.payment_intent_id ?? '');
      if (!piId) return json({ error: 'missing_payment_intent_id' }, 400);
      let pi: Stripe.PaymentIntent;
      try {
        pi = await stripe.paymentIntents.retrieve(piId);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return json({ error: message }, 400);
      }
      if (pi.metadata?.kind !== 'tvde_reservation') return json({ error: 'not_a_reservation_pi' }, 400);
      if (pi.metadata?.user_id !== user.id) return json({ error: 'not_pi_owner' }, 403);
      const rideId = String(pi.metadata?.ride_id ?? '');

      await admin.from('tvde_rides').update({ payment_status: pi.status }).eq('id', rideId);
      if (pi.status !== 'succeeded') {
        return json({ succeeded: false, ride_id: rideId, status: pi.status });
      }
      const { error: paidErr } = await admin.rpc('tvde_reservation_mark_paid', { p_ride_id: rideId });
      if (paidErr) {
        console.error('[tvde-payment] reservation_mark_paid failed:', paidErr.message, pi.id);
        return json({ succeeded: true, activated: false, ride_id: rideId,
                      error: String(paidErr.message) }, 500);
      }
      return json({ succeeded: true, activated: true, ride_id: rideId,
                    status: 'succeeded', amountCents: pi.amount });
    }

    // -- REFUND — cancelamento (padrao client-cancel-order) --
    if (action === 'refund') {
      const rideId = String(body.ride_id ?? '');
      const { data: ride } = await admin
        .from('tvde_rides')
        .select(
          'id, client_id, payment_intent_id, payment_status, est_fare_cents, final_fare_cents, cancel_fee_cents',
        )
        .eq('id', rideId)
        .maybeSingle();
      if (!ride) return json({ error: 'ride_not_found' }, 404);
      if (ride.client_id !== user.id && !(await callerIsAdmin(userClient))) {
        return json({ error: 'not_ride_owner' }, 403);
      }
      if (!ride.payment_intent_id) return json({ ok: true, noop: true });
      if (ride.payment_status === 'refunded' ||
          ride.payment_status === 'partial_refund' ||
          ride.payment_status === 'kept_cancel_fee') {
        return json({ ok: true, already: true });
      }
      const feeCents = Math.max(0, Number(ride.cancel_fee_cents ?? 0));
      const paidCents = Number(ride.final_fare_cents ?? ride.est_fare_cents ?? 0);
      const refundCents = Math.max(0, Math.min(paidCents - feeCents, paidCents));
      if (refundCents >= 1) {
        await stripe.refunds.create(
          { payment_intent: ride.payment_intent_id, amount: refundCents },
          { idempotencyKey: `refund-${ride.payment_intent_id}-${refundCents}` },
        );
      }
      const newStatus = refundCents <= 0
        ? 'kept_cancel_fee'
        : (feeCents > 0 ? 'partial_refund' : 'refunded');
      await admin
        .from('tvde_rides')
        .update({ payment_status: newStatus })
        .eq('id', ride.id);
      console.log('[tvde-payment refund]', ride.id, 'paid:', paidCents,
        'fee:', feeCents, 'refunded:', refundCents, '->', newStatus);
      return json({ ok: true, refundCents, feeCents, paymentStatus: newStatus });
    }

    return json({ error: 'unknown_action' }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return json({ error: message }, 500);
  }
});
