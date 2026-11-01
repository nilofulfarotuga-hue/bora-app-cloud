// supabase/functions/refund/index.ts — reembolso genérico na Stripe (painel admin + funções SQL).
//
// v28 (01/11/2026, missão zona-vermelha-2026-11-01, autorização do Danilo 01/11 19:56
//   "Acertar as três funções. As três você vai consertar e eu autorizo."):
//   Desde a chave nova (16/10) o admin-payments chama esta função com a sb_secret (secretKey()),
//   que NÃO é um JWT: o jwtRole(...) antigo lia o "role" de dentro do token e respondia
//   401 "admin only" → os reembolsos pedidos no painel davam refund_failed.
//   CORREÇÃO: autenticação pela regra da casa (_shared/chaves.ts):
//   chamadaDoServidor (sb_secret em apikey/Bearer, ou service_role legada confirmada no Auth)
//   OU admin com sessão válida. Cliente admin com secretKey(). Ping do vigia diário
//   ({"ping":true} → {"pong":true}). Nada mais mudou.
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { chamadaDoServidor, chamadaDeAdmin, respostaAoPing } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const autorizado = (await chamadaDoServidor(req)) || (await chamadaDeAdmin(req));
  if (!autorizado) {
    return new Response(JSON.stringify({ error: 'unauthorized: admin only' }),
      { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  const pong = await respostaAoPing(req, corsHeaders);
  if (pong) return pong;

  try {
    const { paymentIntentId, amount, userId, orderId } = await req.json() as {
      paymentIntentId?: string; amount?: number; userId?: string; orderId?: string;
    };

    if (!paymentIntentId || typeof paymentIntentId !== 'string' || paymentIntentId.trim() === '') {
      return new Response(JSON.stringify({ error: 'paymentIntentId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (typeof amount !== 'number' || !isFinite(amount) || amount <= 0) {
      return new Response(JSON.stringify({ error: 'amount must be a positive number (euros)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    const amountCents = Math.round(amount * 100);
    if (amountCents < 50) {
      return new Response(JSON.stringify({ error: 'Amount too small (min 0.50 EUR)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // BUG 3 (2026-04-30): retrieve PI + check status='succeeded' + has latest_charge
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId.trim());
    if (pi.status !== 'succeeded' || !pi.latest_charge) {
      console.log('[refund] PI without charge:', paymentIntentId, 'status=', pi.status);
      return new Response(JSON.stringify({
        error: 'charge_missing',
        details: `PaymentIntent ${paymentIntentId} has no successful charge (status=${pi.status}). Nothing to refund.`,
      }), { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    const receivedCents = pi.amount_received ?? 0;
    if (amountCents > receivedCents) {
      return new Response(JSON.stringify({
        error: `Refund amount (€${amount.toFixed(2)}) exceeds captured amount (€${(receivedCents / 100).toFixed(2)})`,
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const idempotencyKey = `refund-${paymentIntentId.trim()}-${amountCents}`;
    const refund = await stripe.refunds.create(
      { payment_intent: paymentIntentId.trim(), amount: amountCents },
      { idempotencyKey },
    );
    console.log('[refund] issued:', refund.id, `pi=${paymentIntentId}`, `€${amount.toFixed(2)}`);

    if (userId) {
      try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const serviceKey = secretKey() || (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
        if (supabaseUrl && serviceKey) {
          const sb = createClient(supabaseUrl, serviceKey);
          const message = `Reembolso de €${amount.toFixed(2)} processado. No MB Way chega normalmente na hora; no cartão pode demorar 5 a 10 dias úteis a aparecer no extrato.`;
          await sb.functions.invoke('notify-client', {
            body: { user_id: userId, title: 'Reembolso processado', body: message,
                    data: { order_id: orderId ?? null, refund_method: 'stripe', refund_id: refund.id } },
          });
        }
      } catch (e) { console.warn('[refund] notify failed (non-fatal):', e); }
    }

    return new Response(JSON.stringify({ refundId: refund.id }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[refund] error:', message);
    return new Response(JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
