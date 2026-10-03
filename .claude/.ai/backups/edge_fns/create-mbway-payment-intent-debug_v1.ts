// BACKUP — create-mbway-payment-intent-debug v1 (Sessão 4 — A2)
// Snapshot date: 2026-05-04
// Status before delete: ACTIVE, verify_jwt=true, version=1
// Project: ojykpzwqrtusfeakzrna
// Reason for delete: variante debug deixada em prod — substituída por create-mbway-payment-intent LIVE.
// NOTA: usa payment_method_types: ['multibanco','card'] em vez de mb_way (não é fluxo MBWay real).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { order_id, phone } = await req.json() as {
      order_id?: string;
      phone?: string;
    };

    console.log('[mbway] request received', { order_id, phone });

    if (!order_id || !phone) {
      return new Response(
        JSON.stringify({ error: 'order_id and phone are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const e164 = phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;
    console.log('[mbway] normalised phone:', e164);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: order, error: dbErr } = await supabase
      .from('orders')
      .select('payment_buffer_total, payment_method, payment_status')
      .eq('id', order_id)
      .maybeSingle();

    if (dbErr || !order) {
      console.error('[mbway] order not found:', dbErr?.message);
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (order.payment_method !== 'mbway') {
      return new Response(
        JSON.stringify({ error: 'Order is not an MBWay order' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (order.payment_status !== 'pending') {
      return new Response(
        JSON.stringify({ error: 'Order already processed' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const amountCents = Math.round((order.payment_buffer_total as number) * 100);
    if (amountCents < 50) {
      return new Response(
        JSON.stringify({ error: 'Amount too small (min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const intent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      payment_method_types: ['multibanco', 'card'],
      payment_method_data: {
        type: 'multibanco',
      },
      confirm: false,
      metadata: { order_id, phone: e164, payment_method: 'mbway' },
    });

    await supabase
      .from('orders')
      .update({ payment_intent_id: intent.id })
      .eq('id', order_id);

    return new Response(
      JSON.stringify({
        ok: true,
        paymentIntentId: intent.id,
        clientSecret: intent.client_secret,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const stack = err instanceof Error ? err.stack : '';
    return new Response(
      JSON.stringify({ error: message, debug: stack }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
