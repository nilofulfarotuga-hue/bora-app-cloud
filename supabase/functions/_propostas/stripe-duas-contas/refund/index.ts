// PROPOSTA — supabase/functions/refund/index.ts — v29 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/refund/; este ficheiro é a versão
// completa pronta a copiar para lá e publicar (verify_jwt=true, como hoje).
// Base: v28 em produção (= repo).
//
// O que muda na v29 (e SÓ isto): o reembolso sai pela conta onde o dinheiro ENTROU.
//   • O corpo pode trazer `stripe_account` ('pessoal'|'empresa'); se não trouxer, procura-se o
//     PaymentIntent nas tabelas (orders, tips, reservations, appointments, limpeza, lavagem…) e
//     usa-se a conta gravada nessa linha; não encontrado = pessoal (tudo o que é antigo).
//   • Sem chave dessa conta → 500 stripe_key_missing (nunca se tenta a outra conta às cegas:
//     o PI não existe lá).
//   • Resposta: + stripe_account.
// v28 (autenticação pela regra da casa, ping do vigia, aviso ao cliente) fica intacto.
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { chamadaDoServidor, chamadaDeAdmin, respostaAoPing } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';
import { type ContaStripe, contaDoPaymentIntent, contaGravada, stripePara } from '../_shared/stripe_contas.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = secretKey() || (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');

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
    const { paymentIntentId, amount, userId, orderId, stripe_account } = await req.json() as {
      paymentIntentId?: string; amount?: number; userId?: string; orderId?: string;
      stripe_account?: string;
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

    // v29 — a conta onde o dinheiro entrou.
    const sb = (supabaseUrl && serviceKey) ? createClient(supabaseUrl, serviceKey) : null;
    const conta: ContaStripe = (stripe_account === 'pessoal' || stripe_account === 'empresa')
      ? contaGravada(stripe_account)
      : (sb ? await contaDoPaymentIntent(sb, paymentIntentId.trim()) : 'pessoal');
    let stripe: Stripe;
    try {
      stripe = stripePara(conta);
    } catch (e) {
      console.error('[refund] sem chave Stripe da conta', conta, String(e));
      return new Response(JSON.stringify({ error: 'stripe_key_missing', stripe_account: conta }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // BUG 3 (2026-04-30): retrieve PI + check status='succeeded' + has latest_charge
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId.trim());
    if (pi.status !== 'succeeded' || !pi.latest_charge) {
      console.log('[refund] PI without charge:', paymentIntentId, 'status=', pi.status, 'conta=', conta);
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
    console.log('[refund v29] issued:', refund.id, `pi=${paymentIntentId}`, `€${amount.toFixed(2)}`, `conta=${conta}`);

    if (userId && sb) {
      try {
        const message = `Reembolso de €${amount.toFixed(2)} processado. No MB Way chega normalmente na hora; no cartão pode demorar 5 a 10 dias úteis a aparecer no extrato.`;
        await sb.functions.invoke('notify-client', {
          body: { user_id: userId, title: 'Reembolso processado', body: message,
                  data: { order_id: orderId ?? null, refund_method: 'stripe', refund_id: refund.id } },
        });
      } catch (e) { console.warn('[refund] notify failed (non-fatal):', e); }
    }

    return new Response(JSON.stringify({ refundId: refund.id, stripe_account: conta }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[refund] error:', message);
    return new Response(JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
