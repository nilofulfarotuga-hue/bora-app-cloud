import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { order_id, amount } = await req.json() as {
      order_id?: string;
      amount?: number;
    };

    // order_id is required — no anonymous or direct payments
    if (!order_id || order_id.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'order_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (!amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Always fetch order from DB — server is the source of truth for amount
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: order, error: dbError } = await supabase
      .from('orders')
      .select('price, payment_buffer_total')
      .eq('id', order_id)
      .maybeSingle();

    if (dbError) {
      console.error('[create-payment-intent] DB error:', dbError.message);
      return new Response(
        JSON.stringify({ error: 'Database error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (!order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // serverPrice  = customer-facing total, server-trusted after create_order RPC.
    // bufferAmount = Stripe pre-auth amount (buffer already applied, token discount
    //               already deducted server-side by the RPC).
    const serverPrice  = order.price as number;
    const bufferAmount = order.payment_buffer_total as number;

    if (!serverPrice || serverPrice <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid order amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (!bufferAmount || bufferAmount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid order buffer amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Zero-tolerance validation: client must send the exact server price.
    // Compare in integer cents to avoid IEEE-754 float rounding false-positives.
    // orders.price is immutable after RPC (enforced by orders_financial_lock trigger).
    const clientCents = Math.round(amount * 100);
    const serverCents = Math.round(serverPrice * 100);
    if (clientCents !== serverCents) {
      console.warn(
        `[create-payment-intent] amount mismatch — client: €${amount.toFixed(2)}, server: €${serverPrice.toFixed(2)} (${clientCents} vs ${serverCents} cents)`,
      );
      return new Response(
        JSON.stringify({ error: 'Amount does not match order total' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Charge payment_buffer_total — includes safety buffer for final price
    // adjustments (e.g. storeShopping weight variance). Token discount was
    // already deducted from this field server-side by the create_order RPC.
    const amountCents = Math.round(bufferAmount * 100);

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
      metadata: { order_id: order_id },
    });

    console.log('[create-payment-intent] created:', paymentIntent.id, `order_id=${order_id}`, `price=€${serverPrice.toFixed(2)}`, `charged=€${bufferAmount.toFixed(2)}`);

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
