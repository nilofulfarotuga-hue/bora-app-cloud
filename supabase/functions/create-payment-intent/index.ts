import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { orderId, amount } = await req.json() as {
      orderId?: string;
      amount: number;
    };

    if (!amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Server-side amount validation: if a real orderId is provided,
    // re-read paymentBufferTotal from DB instead of trusting the client.
    let finalAmountEur = amount;

    const isRealOrder =
      orderId != null && orderId !== '' && !orderId.startsWith('direct-');

    if (isRealOrder) {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      );

      const { data: order, error } = await supabase
        .from('orders')
        .select('payment_buffer_total')
        .eq('id', orderId)
        .maybeSingle();

      if (error) {
        console.error('[create-payment-intent] DB error:', error.message);
      }

      if (order?.payment_buffer_total != null) {
        finalAmountEur = order.payment_buffer_total as number;
      }
    }

    // Stripe expects amounts in the smallest currency unit (cents for EUR).
    const amountCents = Math.round(finalAmountEur * 100);

    if (amountCents < 50) {
      return new Response(
        JSON.stringify({ error: 'Amount too small (min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      automatic_payment_methods: { enabled: true },
      metadata: { orderId: orderId ?? '' },
    });

    console.log('[create-payment-intent] created:', paymentIntent.id, `€${finalAmountEur.toFixed(2)}`);

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-payment-intent] error:', message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
