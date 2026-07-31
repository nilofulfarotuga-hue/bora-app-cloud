// supabase/functions/create-reservation-payment-intent/index.ts — v10
//
// v10 (2026-07-31): guarda "Em breve" (STORE_COMING_SOON) antes do Stripe e
// antes de inserir a reserva. Nenhum valor cobrado foi alterado.
//
// PaymentIntent Stripe para PRÉ-PAGAMENTO de RESERVA (€3 default), via cartão.
//
// v9 (2026-05-15) — restringe métodos a `card`. Antes: automatic_payment_methods
// enabled mostrava Klarna/Revolut/Bancontact no PaymentSheet, fora do contexto
// PT/BORA. PaymentSheet com payment_method_types=['card'] ainda mostra Apple
// Pay e Google Pay (wallets de cartão), mantendo UX moderna.
//
// MBWay para reserva → função separada `create-mbway-reservation-payment-intent`
// (server-confirm via billing_details.phone, espelho do v21 dos orders).
//
// Webhook (stripe-webhook v25) trata payment_intent.succeeded /
// payment_intent.canceled via metadata.purpose='reservation_prepayment'.
//
// verify_jwt = true.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  COMING_SOON_RESERVATION_MSG,
  comingSoonResponseBody,
  isRestaurantComingSoon,
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

    const body = await req.json() as {
      restaurant_id?: string;
      people?: number;
      reserved_for?: string;
      client_name?: string;
      client_phone?: string;
      notes?: string;
      idempotency_key?: string;
    };

    if (!body.restaurant_id || !body.people || !body.reserved_for) {
      return new Response(JSON.stringify({ error: 'missing fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // 2026-07-31 — "Em breve": nunca criar PaymentIntent para loja fechada a
    // pedidos. Corre ANTES do Stripe e antes de inserir a reserva.
    if (await isRestaurantComingSoon(supabase, body.restaurant_id)) {
      return new Response(
        JSON.stringify(comingSoonResponseBody(COMING_SOON_RESERVATION_MSG)),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const { data: settingsRow } = await supabase
      .from('platform_settings').select('value')
      .eq('key', 'reservation_prepayment_cents').maybeSingle();
    const cents = parseInt(String((settingsRow?.value ?? 300)), 10);

    if (cents < 50) {
      return new Response(JSON.stringify({ error: 'prepayment too small (Stripe min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

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
      .select('id').single();

    if (rsvErr || !rsv) {
      return new Response(JSON.stringify({ error: 'failed to create reservation: ' + rsvErr?.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const idempotencyKey = body.idempotency_key ?? `rsv_${rsv.id}`;
    const intent = await stripe.paymentIntents.create({
      amount: cents,
      currency: 'eur',
      // v9: card-only. PaymentSheet ainda apresenta Apple Pay / Google Pay
      // como wallets de cartão (não são payment methods independentes).
      payment_method_types: ['card'],
      metadata: {
        reservation_id: rsv.id,
        restaurant_id: body.restaurant_id,
        purpose: 'reservation_prepayment',
      },
    }, { idempotencyKey });

    await supabase.from('reservations').update({ prepayment_pi: intent.id }).eq('id', rsv.id);

    return new Response(JSON.stringify({
      reservation_id: rsv.id,
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
