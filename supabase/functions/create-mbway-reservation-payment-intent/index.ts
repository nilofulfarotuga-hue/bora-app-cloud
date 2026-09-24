// supabase/functions/create-mbway-reservation-payment-intent/index.ts — v6
//
// MBWay payment intent para PRÉ-PAGAMENTO de RESERVA (€3 default).
// Server-confirm com billing_details.phone (mesmo padrão que orders v21).
//
// v6 (2026-07-31): guarda "Em breve" (STORE_COMING_SOON) antes do Stripe e
// antes de inserir a reserva. Nenhum valor cobrado foi alterado.
//
// verify_jwt = true — mantém paridade com create-reservation-payment-intent.

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
      phone?: string;
      idempotency_key?: string;
    };

    if (!body.restaurant_id || !body.people || !body.reserved_for || !body.phone) {
      return json({ error: 'missing fields (restaurant_id, people, reserved_for, phone)' }, 400);
    }

    // Normaliza phone PT → E.164 (+351XXXXXXXXX).
    const e164 = body.phone.startsWith('+')
      ? body.phone
      : `+351${body.phone.replace(/^0/, '')}`;

    // 2026-07-31 — "Em breve": nunca criar PaymentIntent (nem push MBWay) para
    // uma loja que ainda não aceita reservas. Corre ANTES do Stripe.
    if (await isRestaurantComingSoon(supabase, body.restaurant_id)) {
      return json(comingSoonResponseBody(COMING_SOON_RESERVATION_MSG), 409);
    }

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
      await supabase.from('reservations').delete().eq('id', rsv.id);
      const msg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      console.error('[create-mbway-reservation-payment-intent] stripe failed:', msg);
      return json({ error: 'stripe_error: ' + msg }, 500);
    }

    console.log('[create-mbway-reservation-payment-intent] intent confirmed:',
      intent.id, `reservation=${rsv.id}`, `phone=${e164}`,
      `status=${intent.status}`, `mode=${STRIPE_MODE}`);

    const { error: piUpdateErr } = await supabase
      .from('reservations')
      .update({ prepayment_pi: intent.id })
      .eq('id', rsv.id);

    if (piUpdateErr) {
      console.error('[create-mbway-reservation-payment-intent] save prepayment_pi failed:',
        piUpdateErr.message, intent.id);
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
