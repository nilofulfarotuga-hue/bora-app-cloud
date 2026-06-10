// supabase/functions/create-mbway-appointment-payment-intent/index.ts — v1
//
// MBWay payment intent para o SINAL de uma MARCAÇÃO (€3 default).
// Paridade M7 com reservas: espelha create-mbway-reservation-payment-intent v5,
// mas a marcação JÁ FOI criada por client_book_appointment (RPC com validação
// de colisão) — recebe appointment_id em vez de criar a row.
//
// Fluxo:
//   1. Valida ownership + status='pending_payment' da marcação.
//   2. PaymentIntents.create({ payment_method_types:['mb_way'],
//      payment_method_data.billing_details.phone, confirm:true })
//      → Stripe envia push para a app MBWay imediatamente.
//   3. UPDATE appointments.deposit_pi.
//   4. Return { appointment_id, paymentIntentId, status }.
//
// A confirmação é feita por polling do cliente à Edge Fn
// confirm-mbway-appointment-payment (verifica o PI no Stripe server-side) —
// o stripe-webhook NÃO trata appointment_deposit (zona protegida, não tocada).
// verify_jwt = true (paridade com create-appointment-payment-intent v1).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

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
    if (userErr || !user) return json({ error: 'auth required' }, 401);

    const body = await req.json() as {
      appointment_id?: string;
      phone?: string;            // MBWay phone (PT 9 dígitos OU já em E.164)
      idempotency_key?: string;
    };
    if (!body.appointment_id || !body.phone) {
      return json({ error: 'missing fields (appointment_id, phone)' }, 400);
    }

    const e164 = body.phone.startsWith('+')
      ? body.phone
      : `+351${body.phone.replace(/^0/, '')}`;

    const { data: appt, error: apptErr } = await supabase
      .from('appointments')
      .select('id, client_user_id, provider_id, deposit_cents, status, deposit_pi')
      .eq('id', body.appointment_id)
      .single();

    if (apptErr || !appt) return json({ error: 'appointment not found' }, 404);
    if (appt.client_user_id !== user.id) return json({ error: 'not your appointment' }, 403);
    if (appt.status !== 'pending_payment') {
      return json({ error: 'invalid status: ' + appt.status }, 409);
    }

    const cents = parseInt(String(appt.deposit_cents ?? 300), 10);
    if (cents < 50) {
      return json({ error: 'deposit too small (Stripe min 0.50 EUR)' }, 400);
    }

    const idempotencyKey = body.idempotency_key ?? `mbway_appt_${appt.id}`;

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
          appointment_id: appt.id,
          provider_id: appt.provider_id,
          purpose: 'appointment_deposit',
        },
      }, { idempotencyKey });
    } catch (stripeErr) {
      // Marcação fica pending_payment — o cliente pode tentar cartão a seguir.
      const msg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      console.error('[create-mbway-appointment-payment-intent] stripe failed:', msg);
      return json({ error: 'stripe_error: ' + msg }, 500);
    }

    console.log('[create-mbway-appointment-payment-intent] intent confirmed:',
      intent.id, `appointment=${appt.id}`, `phone=${e164}`,
      `status=${intent.status}`, `mode=${STRIPE_MODE}`);

    const { error: piUpdateErr } = await supabase
      .from('appointments')
      .update({ deposit_pi: intent.id })
      .eq('id', appt.id);
    if (piUpdateErr) {
      console.error('[create-mbway-appointment-payment-intent] save deposit_pi failed:',
        piUpdateErr.message, intent.id);
    }

    return json({
      ok: true,
      appointment_id: appt.id,
      paymentIntentId: intent.id,
      status: intent.status,
      amount_cents: cents,
      mode: STRIPE_MODE,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-mbway-appointment-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});
