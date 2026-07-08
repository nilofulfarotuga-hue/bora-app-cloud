// =============================================================================
// tvde-payment — pagamento CARD + MB WAY nas corridas TVDE.
// =============================================================================
// PADRÃO ÚNICO (= delivery): cobra NA HORA o valor do plano e faz refund estilo
// `client-cancel-order` (capado ao pago, menos a taxa). SEM authorize/capture.
// Função NOVA e ISOLADA — NÃO toca no stripe-webhook.
//
// Triplo-gate: (1) kill switch server-side aqui, (2) a RPC tvde_request_ride
// rejeita card/mbway com o switch off, (3) a UI esconde card/mbway com off.
//
// Ações (body.action):
//   charge  → cria a corrida (JWT) — a RPC grava `est_fare_cents` JÁ com a regra
//             do plano — e cobra o valor de `tvde_ride_charge_cents(ride_id)`
//             (NÃO a tarifa cheia): coberta→só excesso, extra→€4,50+excesso,
//             normal→cheia. €0 (coberta ≤6km) → não cobra. CARTÃO devolve
//             clientSecret; MB WAY confirma server-side. Liga o payment_intent_id.
//   refund  → cancelamento: refund = max(0, min(pago − taxa, pago)).
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');

    // Gate #1 (server-side): kill switch. Falha fechada.
    if (!(await getSettingBool('tvde_card_payments_enabled'))) {
      return json({ error: 'card_payments_not_enabled' }, 403);
    }

    // Cliente autenticado (JWT) → cria a corrida como o próprio (auth.uid).
    const token = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim();
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'not_authenticated' }, 401);

    // ── CHARGE — cria a corrida e cobra o VALOR DO PLANO (não a tarifa cheia) ─
    if (action === 'charge') {
      const method = String(body.method ?? '');
      if (method !== 'card' && method !== 'mbway') {
        return json({ error: 'invalid_method' }, 400);
      }
      const distanceKm = Number(body.distance_km ?? 0);
      if (!(distanceKm > 0)) return json({ error: 'invalid_distance' }, 400);

      // 1) Cria a corrida COMO O CLIENTE. A RPC grava `est_fare_cents` JÁ com a
      //    regra do plano: coberta→só excesso, extra→€4,50+excesso, normal→cheia.
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

      // Cancela a corrida órfã se a cobrança falhar (nada foi cobrado ainda).
      const cancelRide = async () => {
        try {
          await userClient.rpc('tvde_cancel_ride', {
            p_ride_id: ride.id,
            p_actor: 'cliente',
            p_reason: 'payment_failed',
          });
        } catch (_) {/* best effort */}
      };

      // 2) Valor a cobrar = FONTE ÚNICA `tvde_ride_charge_cents` (NÃO recalcular).
      const { data: chargeData, error: chargeErr } = await admin.rpc(
        'tvde_ride_charge_cents',
        { p_ride_id: ride.id },
      );
      if (chargeErr) {
        await cancelRide();
        return json({ error: 'charge_calc_failed' }, 500);
      }
      const amountCents = Number(chargeData ?? 0);

      // 3) €0 → coberta ≤ base_km: não há cobrança online (a UI também não a
      //    envia neste caso). Devolve a corrida criada sem PaymentIntent.
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
      if (amountCents < 50) { // mínimo Stripe — não deve ocorrer (excesso mín = 50)
        await cancelRide();
        return json({ error: 'below_minimum' }, 400);
      }

      // 4) PaymentIntent DESSE valor (o do plano), não a tarifa cheia.
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

      // 5) Liga o PaymentIntent à corrida (service role — coluna sensível).
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

    // ── REFUND — cancelamento (padrão client-cancel-order) ──────────────────
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
      // Pago = o valor cobrado (final se existir, senão o estimado).
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
