// =============================================================================
// tvde-payment — pagamento CARD + MB WAY nas corridas TVDE (Parte 5 aprovada).
// =============================================================================
// ⚠️  MEXE EM DINHEIRO. Função NOVA e ISOLADA — NÃO toca no stripe-webhook nem
//     em nenhuma function existente. Triplo-gate: (1) kill switch server-side
//     aqui, (2) a RPC tvde_request_ride rejeita card/mbway com o switch off,
//     (3) a UI esconde card/mbway com o switch off.
//
// NÃO DEPLOYADA NESTA SESSÃO (código só). Deploy é o passo final do Danilo,
// depois de rever, e ANTES de ligar `tvde_card_payments_enabled`.
//
// Ações (body.action):
//   authorize → CARTÃO: cria PaymentIntent capture_method=manual (hold =
//               estimado × (1 + margem%)), cria a corrida, devolve clientSecret
//               p/ o cliente confirmar o hold. Captura-se o valor FINAL no fim.
//   charge    → MB WAY: cria PaymentIntent mb_way confirm=true (push MB WAY),
//               cria a corrida (payment_status=processing).
//   capture   → no FIM: captura o final_fare_cents (<= autorizado) do cartão.
//   settle    → MB WAY no fim: se final < estimado → refund da diferença.
//   cancel    → antes de a caminho: void do hold. Tardio: captura só a taxa.
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

async function getSettingNum(key: string, fallback: number): Promise<number> {
  const { data } = await admin.rpc('get_setting', { p_key: key });
  const n = Number(data);
  return Number.isFinite(n) ? n : fallback;
}
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

    // Cliente autenticado (JWT) → para criar a corrida como o próprio (auth.uid).
    const token = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim();
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'not_authenticated' }, 401);

    // ── AUTHORIZE (cartão) / CHARGE (MB Way) — no pedido da corrida ──────────
    if (action === 'authorize' || action === 'charge') {
      const method = String(body.method ?? '');
      if (method !== 'card' && method !== 'mbway') {
        return json({ error: 'invalid_method' }, 400);
      }
      const distanceKm = Number(body.distance_km ?? 0);
      if (!(distanceKm > 0)) return json({ error: 'invalid_distance' }, 400);

      // Preço SEMPRE calculado no servidor (nunca confiar no cliente).
      const { data: fareData, error: fareErr } = await admin.rpc(
        'tvde_calculate_fare',
        { p_distance_km: distanceKm },
      );
      if (fareErr) return json({ error: 'fare_calc_failed' }, 500);
      const estCents = Number(fareData);
      if (!(estCents >= 50)) return json({ error: 'below_minimum' }, 400); // 0.50€

      let pi: Stripe.PaymentIntent;
      if (method === 'card') {
        const marginPct = await getSettingNum('tvde_auth_margin_pct', 20);
        const holdCents = Math.round(estCents * (1 + marginPct / 100));
        pi = await stripe.paymentIntents.create(
          {
            amount: holdCents,
            currency: 'eur',
            capture_method: 'manual', // autoriza agora, captura o final no fim
            automatic_payment_methods: { enabled: true },
            metadata: { kind: 'tvde_ride', method, user_id: user.id },
          },
          { idempotencyKey: `tvde_auth_${user.id}_${Math.round(distanceKm * 1000)}` },
        );
      } else {
        const phone = String(body.phone ?? '');
        const e164 = phone.startsWith('+')
          ? phone
          : `+351${phone.replace(/\D/g, '').replace(/^0/, '')}`;
        pi = await stripe.paymentIntents.create(
          {
            amount: estCents,
            currency: 'eur',
            payment_method_types: ['mb_way'],
            payment_method_data: { type: 'mb_way', billing_details: { phone: e164 } },
            confirm: true,
            metadata: { kind: 'tvde_ride', method, user_id: user.id },
          },
          { idempotencyKey: `tvde_mbway_${user.id}_${Math.round(distanceKm * 1000)}` },
        );
      }

      // Cria a corrida COMO O CLIENTE (auth.uid) — só depois de o pagamento
      // estar autorizado/iniciado. Se falhar, desfaz o hold (void).
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
        try {
          await stripe.paymentIntents.cancel(pi.id);
        } catch (_) {/* best effort */}
        return json({ error: String(rideErr?.message ?? 'ride_create_failed') }, 400);
      }
      const ride = Array.isArray(rideRes) ? rideRes[0] : rideRes;

      // Liga o PaymentIntent à corrida (service role — a coluna é sensível).
      await admin
        .from('tvde_rides')
        .update({
          payment_intent_id: pi.id,
          payment_status: pi.status,
        })
        .eq('id', ride.id);

      return json({
        ride: { ...ride, payment_intent_id: pi.id, payment_status: pi.status },
        paymentIntentId: pi.id,
        clientSecret: method === 'card' ? pi.client_secret : null,
        status: pi.status,
      });
    }

    // ── CAPTURE (cartão, no fim) — captura o valor FINAL (<= autorizado) ─────
    if (action === 'capture') {
      const rideId = String(body.ride_id ?? '');
      const { data: ride } = await admin
        .from('tvde_rides')
        .select('id, payment_intent_id, payment_method, final_fare_cents, payment_status')
        .eq('id', rideId)
        .maybeSingle();
      if (!ride?.payment_intent_id) return json({ error: 'no_payment' }, 404);
      if (ride.payment_status === 'succeeded') return json({ ok: true, already: true });
      const finalCents = Number(ride.final_fare_cents ?? 0);
      if (!(finalCents >= 50)) return json({ error: 'invalid_final' }, 400);
      const captured = await stripe.paymentIntents.capture(ride.payment_intent_id, {
        amount_to_capture: finalCents,
      });
      await admin
        .from('tvde_rides')
        .update({ payment_status: captured.status })
        .eq('id', ride.id);
      return json({ ok: true, status: captured.status });
    }

    // ── SETTLE (MB Way, no fim) — refund da diferença se final < estimado ────
    if (action === 'settle') {
      const rideId = String(body.ride_id ?? '');
      const { data: ride } = await admin
        .from('tvde_rides')
        .select('id, payment_intent_id, final_fare_cents, est_fare_cents, payment_status')
        .eq('id', rideId)
        .maybeSingle();
      if (!ride?.payment_intent_id) return json({ error: 'no_payment' }, 404);
      const paid = Number(ride.est_fare_cents ?? 0);
      const finalC = Number(ride.final_fare_cents ?? 0);
      // Política aprovada: final > estimado → Bora absorve (não cobra mais).
      if (finalC < paid && paid - finalC >= 1) {
        await stripe.refunds.create(
          { payment_intent: ride.payment_intent_id, amount: paid - finalC },
          { idempotencyKey: `tvde_settle_${ride.id}_${paid - finalC}` },
        );
        await admin
          .from('tvde_rides')
          .update({ payment_status: 'partial_refund' })
          .eq('id', ride.id);
      }
      return json({ ok: true });
    }

    // ── CANCEL — void (sem taxa) ou captura só a taxa de cancelamento ────────
    if (action === 'cancel') {
      const rideId = String(body.ride_id ?? '');
      const feeCents = Number(body.cancel_fee_cents ?? 0);
      const { data: ride } = await admin
        .from('tvde_rides')
        .select('id, payment_intent_id, payment_method')
        .eq('id', rideId)
        .maybeSingle();
      if (!ride?.payment_intent_id) return json({ ok: true, noop: true });
      if (ride.payment_method === 'card') {
        if (feeCents >= 50) {
          const cap = await stripe.paymentIntents.capture(ride.payment_intent_id, {
            amount_to_capture: feeCents,
          });
          await admin
            .from('tvde_rides')
            .update({ payment_status: cap.status })
            .eq('id', ride.id);
        } else {
          await stripe.paymentIntents.cancel(ride.payment_intent_id);
          await admin
            .from('tvde_rides')
            .update({ payment_status: 'canceled' })
            .eq('id', ride.id);
        }
      } else {
        // MB Way (já cobrado): refund total menos a taxa.
        const paid = Number(body.paid_cents ?? 0);
        const refund = Math.max(0, paid - feeCents);
        if (refund >= 1) {
          await stripe.refunds.create(
            { payment_intent: ride.payment_intent_id, amount: refund },
            { idempotencyKey: `tvde_cancel_${ride.id}_${refund}` },
          );
        }
        await admin
          .from('tvde_rides')
          .update({ payment_status: feeCents > 0 ? 'partial_refund' : 'refunded' })
          .eq('id', ride.id);
      }
      return json({ ok: true });
    }

    return json({ error: 'unknown_action' }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return json({ error: message }, 500);
  }
});
