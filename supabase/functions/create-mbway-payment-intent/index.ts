import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

// BUG 13 — Stripe mode toggle. Default 'live'.
const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
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

    if (!order_id || !phone) {
      return new Response(
        JSON.stringify({ error: 'order_id and phone are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Normalise PT phone → E.164 (+351XXXXXXXXX)
    const e164 = phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;

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

    // v20 (2026-05-15) — fix: PaymentSheet client-side. Server-confirm v19
    // tinha payment_method_data.mb_way.phone, parametro inexistente na API
    // Stripe → 500 garantido (parameter_unknown registado em mbway_debug_errors).
    // Agora cria PI + devolve client_secret. Flutter apresenta Stripe PaymentSheet
    // que recolhe MBWay phone nativamente e despoleta o push para a MBWay app.
    // phone continua recebido apenas para logging/auditoria.
    const intent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      payment_method_types: ['mb_way'],
      metadata: { order_id },
    }, { idempotencyKey: `mbway_${order_id}` });

    console.log('[create-mbway-payment-intent] intent created (PaymentSheet flow):',
      intent.id, `order=${order_id}`, `phone=${e164}`, `mode=${STRIPE_MODE}`);

    return new Response(
      JSON.stringify({
        ok: true,
        paymentIntentId: intent.id,
        clientSecret: intent.client_secret,
        mode: STRIPE_MODE,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-mbway-payment-intent] error:', message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
