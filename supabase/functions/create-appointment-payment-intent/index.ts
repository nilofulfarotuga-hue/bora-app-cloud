// supabase/functions/create-appointment-payment-intent/index.ts — v2
//
// v2 (2026-07-31): guarda "Em breve" (STORE_COMING_SOON) antes do Stripe.
// Nenhum valor cobrado foi alterado.
//
// PaymentIntent Stripe para o SINAL de uma MARCAÇÃO de barbearia (€3 default),
// via cartão. Clone de create-reservation-payment-intent (v9).
//
// Fluxo: a marcação já foi criada por `client_book_appointment` (RPC, que valida
// disponibilidade/colisão com auth.uid() do cliente). Esta função recebe o
// appointment_id, valida ownership + estado, e cria o PaymentIntent do sinal.
//
// Card-only (PaymentSheet ainda mostra Apple Pay / Google Pay como wallets de cartão).
// A confirmação client-side é feita por `client_confirm_appointment_payment` (RPC).
// verify_jwt = true.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  COMING_SOON_BOOKING_MSG,
  comingSoonResponseBody,
  isProviderComingSoon,
} from '../_shared/coming_soon.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
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
      return new Response(JSON.stringify({ error: 'auth required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const body = await req.json() as { appointment_id?: string; idempotency_key?: string };
    if (!body.appointment_id) {
      return new Response(JSON.stringify({ error: 'missing appointment_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const { data: appt, error: apptErr } = await supabase
      .from('appointments')
      .select('id, client_user_id, provider_id, deposit_cents, status, deposit_pi')
      .eq('id', body.appointment_id)
      .single();

    if (apptErr || !appt) {
      return new Response(JSON.stringify({ error: 'appointment not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (appt.client_user_id !== user.id) {
      return new Response(JSON.stringify({ error: 'not your appointment' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (appt.status !== 'pending_payment') {
      return new Response(JSON.stringify({ error: 'invalid status: ' + appt.status }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // 2026-07-31 — "Em breve": nunca criar PaymentIntent para um parceiro que
    // ainda não aceita marcações. Corre ANTES de tocar no Stripe.
    if (await isProviderComingSoon(supabase, appt.provider_id)) {
      return new Response(
        JSON.stringify(comingSoonResponseBody(COMING_SOON_BOOKING_MSG)),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const cents = parseInt(String(appt.deposit_cents ?? 300), 10);
    if (cents < 50) {
      return new Response(JSON.stringify({ error: 'deposit too small (Stripe min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const idempotencyKey = body.idempotency_key ?? `appt_${appt.id}`;
    const intent = await stripe.paymentIntents.create({
      amount: cents,
      currency: 'eur',
      payment_method_types: ['card'],
      metadata: {
        appointment_id: appt.id,
        provider_id: appt.provider_id,
        purpose: 'appointment_deposit',
      },
    }, { idempotencyKey });

    await supabase.from('appointments').update({ deposit_pi: intent.id }).eq('id', appt.id);

    return new Response(JSON.stringify({
      appointment_id: appt.id,
      paymentIntentId: intent.id,
      clientSecret: intent.client_secret,
      amount_cents: cents,
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: msg }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
