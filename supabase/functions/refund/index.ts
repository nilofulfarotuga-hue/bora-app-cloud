import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

// Admin-only: Supabase verifies JWT is valid (verify_jwt=true in config).
// Here we additionally check the JWT `role` claim is `service_role`.
function jwtRole(authHeader: string): string | null {
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const pad = parts[1] + '==='.slice((parts[1].length + 3) % 4);
    const json = atob(pad.replace(/-/g, '+').replace(/_/g, '/'));
    const claims = JSON.parse(json);
    return typeof claims.role === 'string' ? claims.role : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const role = jwtRole(req.headers.get('authorization') ?? '');
  if (role !== 'service_role') {
    return new Response(
      JSON.stringify({ error: 'unauthorized: admin only' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  try {
    const { paymentIntentId, amount, userId, orderId } = await req.json() as {
      paymentIntentId?: string;
      amount?: number;
      userId?: string;
      orderId?: string;
    };

    if (!paymentIntentId || typeof paymentIntentId !== 'string' || paymentIntentId.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'paymentIntentId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (typeof amount !== 'number' || !isFinite(amount) || amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'amount must be a positive number (euros)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const amountCents = Math.round(amount * 100);

    if (amountCents < 50) {
      return new Response(
        JSON.stringify({ error: 'Amount too small (min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // BUG 3 (2026-04-30): retrieve PI + check status='succeeded' + has latest_charge
    // antes de tentar refund. PIs órfãos (status=requires_payment_method, canceled,
    // etc.) não têm cobrança real → retornamos 409 charge_missing em vez de 502.
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId.trim());
    if (pi.status !== 'succeeded' || !pi.latest_charge) {
      console.log('[refund] PI without charge:', paymentIntentId, 'status=', pi.status);
      return new Response(
        JSON.stringify({
          error: 'charge_missing',
          details: `PaymentIntent ${paymentIntentId} has no successful charge (status=${pi.status}). Nothing to refund.`,
        }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    // Cap: refund cannot exceed amount actually received on the PaymentIntent.
    const receivedCents = pi.amount_received ?? 0;
    if (amountCents > receivedCents) {
      return new Response(
        JSON.stringify({
          error: `Refund amount (€${amount.toFixed(2)}) exceeds captured amount (€${(receivedCents / 100).toFixed(2)})`,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Idempotency key: same pi + same amount → same refund, never duplicated.
    const idempotencyKey = `refund-${paymentIntentId.trim()}-${amountCents}`;

    const refund = await stripe.refunds.create(
      {
        payment_intent: paymentIntentId.trim(),
        amount: amountCents,
      },
      { idempotencyKey },
    );

    console.log('[refund] issued:', refund.id, `pi=${paymentIntentId}`, `€${amount.toFixed(2)}`, `idempotencyKey=${idempotencyKey}`);

    // F2 (2026-04-30) — push client com clareza do prazo Stripe (best-effort)
    if (userId) {
      try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
        if (supabaseUrl && serviceKey) {
          const sb = createClient(supabaseUrl, serviceKey);
          const message = `Reembolso de €${amount.toFixed(2)} processado. Pode demorar 5-10 dias úteis a aparecer no cartão. Para crédito instantâneo, escolhe wallet da próxima vez.`;
          await sb.functions.invoke('notify-client', {
            body: {
              user_id: userId,
              title: 'Reembolso processado',
              body: message,
              data: { order_id: orderId ?? null, refund_method: 'stripe', refund_id: refund.id },
            },
          });
        }
      } catch (e) { console.warn('[refund] notify failed (non-fatal):', e); }
    }

    return new Response(
      JSON.stringify({ refundId: refund.id }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[refund] error:', message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
