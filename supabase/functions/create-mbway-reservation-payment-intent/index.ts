// supabase/functions/create-mbway-reservation-payment-intent/index.ts — v1
//
// MBWay payment intent para PRÉ-PAGAMENTO de RESERVA (€3 default).
// Espelha o padrão server-confirm de `create-mbway-payment-intent` v21
// (orders), adaptado para a tabela `reservations`.
//
// Fluxo:
//   1. INSERT reserva (status='pending_payment', prepayment_cents).
//   2. PaymentIntents.create({ payment_method_types:['mb_way'],
//      payment_method_data.billing_details.phone, confirm:true }).
//      → Stripe envia push para a app MBWay imediatamente.
//   3. UPDATE reservations.prepayment_pi.
//   4. Return { reservation_id, paymentIntentId, status }.
//
// Webhook (stripe-webhook v25) trata payment_intent.succeeded /
// payment_intent.canceled via metadata.purpose='reservation_prepayment'
// → confirm_reservation_payment_webhook RPC ou cancel_orphan_reservation RPC.
//
// verify_jwt = true (deploy) — mantém paridade com create-reservation-payment-intent v8.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Stripe mode toggle alinhado com create-mbway-payment-intent.
const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const auth = req.headers.get('Authorization') ?? '';
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { global: { headers: { Authorization: auth } } },
    );

    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) {
      return json({ error: 'auth required' }, 401);
    }

    const body = await req.json() as {
      restaurant_id?: string;
      people?: number;
      reserved_for?: string;
      client_name?: string;
      client_phone?: string;
      notes?: string;
      phone?: string;            // MBWay phone (PT 9 dígitos OU já em E.164)
      idempotency_key?: string;
    };

    if (!body.restaurant_id || !body.people || !body.reserved_for || !body.phone) {
      return json({ error: 'missing fields (restaurant_id, people, reserved_for, phone)' }, 400);
    }

    // Normaliza phone PT → E.164 (+351XXXXXXXXX). Idêntico a create-mbway-payment-intent.
    const e164 = body.phone.startsWith('+')
      ? body.phone
      : `+351${body.phone.replace(/^0/, '')}`;

    // Lê preço do prepagamento da plataforma (default 300 cents).
    const { data: settingsRow } = await supabase
      .from('platform_settings')
      .select('value')
      .eq('key', 'reservation_prepayment_cents')
      .maybeSingle();
    const cents = parseInt(String((settingsRow?.value ?? 300)), 10);

    if (cents < 50) {
      return json({ error: 'prepayment too small (Stripe min 0.50 EUR)' }, 400);
    }

    // INSERT reserva pending_payment.
    const { data: rsv, error: rsvErr } = await supabase
      .from('reservations')
      .insert({
        client_user_id: user.id,
        restaurant_id: body.restaurant_id,
        people: body.people,
        reserved_for: body.reserved_for,
        client_name: body.client_name,
        client_phone: body.client_phone,
        notes: body.notes,
        status: 'pending_payment',
        prepayment_cents: cents,
      })
      .select('id')
      .single();

    if (rsvErr || !rsv) {
      return json({ error: 'failed to create reservation: ' + rsvErr?.message }, 500);
    }

    const idempotencyKey = body.idempotency_key ?? `mbway_rsv_${rsv.id}`;

    // Server-side confirm com billing_details.phone (mesmo padrão que orders v21).
    let intent: Stripe.PaymentIntent;
    try {
      intent = await stripe.paymentIntents.create({
        amount: cents,
        currency: 'eur',
        payment_method_types: ['mb_way'],
        payment_method_data: {
          type: 'mb_way',
          billing_details: { phone: e164 },
        },
        confirm: true,
        metadata: {
          reservation_id: rsv.id,
          restaurant_id: body.restaurant_id,
          purpose: 'reservation_prepayment',
        },
      }, { idempotencyKey });
    } catch (stripeErr) {
      // Stripe falhou — limpar a reserva órfã para não deixar lixo.
      // RLS do user permite delete da própria reserva pending_payment, mas
      // usamos service-role (já no client) por garantia.
      await supabase.from('reservations').delete().eq('id', rsv.id);
      const msg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      console.error('[create-mbway-reservation-payment-intent] stripe failed:', msg);
      return json({ error: 'stripe_error: ' + msg }, 500);
    }

    console.log('[create-mbway-reservation-payment-intent] intent confirmed:',
      intent.id, `reservation=${rsv.id}`, `phone=${e164}`,
      `status=${intent.status}`, `mode=${STRIPE_MODE}`);

    // UPDATE prepayment_pi para auditoria/reconciliação.
    const { error: piUpdateErr } = await supabase
      .from('reservations')
      .update({ prepayment_pi: intent.id })
      .eq('id', rsv.id);

    if (piUpdateErr) {
      console.error('[create-mbway-reservation-payment-intent] save prepayment_pi failed:',
        piUpdateErr.message, intent.id);
      // Não bloquear — webhook ainda resolve via metadata.reservation_id.
    }

    return json({
      ok: true,
      reservation_id: rsv.id,
      paymentIntentId: intent.id,
      status: intent.status,
      amount_cents: cents,
      mode: STRIPE_MODE,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-mbway-reservation-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});
