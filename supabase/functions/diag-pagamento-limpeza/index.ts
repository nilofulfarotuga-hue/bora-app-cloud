// diag-pagamento-limpeza — SÓ LEITURA. Diz porque é que um pedido MB Way/cartão de uma
// limpeza falhou (o stripe-webhook só regista o tipo do evento, não o motivo).
// 19/10/2026 (missão limpeza-semanal-pagamento-19-10). Só o servidor chama
// (chamadaDoServidor). Não cria, não muda, não estorna nada na Stripe.
// Body: { paymentIntentIds: string[] } (máx. 5). Só devolve PaymentIntents com
// metadata.kind='cleaning'. Nunca devolve telefone nem dados do cartão.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { exigirServidor } from '../_shared/chaves.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecret = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecret, { apiVersion: '2023-10-16' });

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const negado = await exigirServidor(req, cors);
  if (negado) return negado;

  const body = await req.json().catch(() => ({}));
  const ids = (Array.isArray(body?.paymentIntentIds) ? body.paymentIntentIds : [])
    .filter((x: unknown): x is string => typeof x === 'string' && /^pi_[A-Za-z0-9]+$/.test(x))
    .slice(0, 5);
  if (ids.length === 0) return json({ ok: false, error: 'paymentIntentIds_required' }, 400);

  const out: unknown[] = [];
  for (const id of ids) {
    try {
      const pi = await stripe.paymentIntents.retrieve(id);
      if (pi.metadata?.kind !== 'cleaning') {
        out.push({ id, error: 'not_cleaning' });
        continue;
      }
      const e = pi.last_payment_error;
      out.push({
        id: pi.id,
        status: pi.status,
        amount: pi.amount,
        created: pi.created,
        canceled_at: pi.canceled_at,
        cancellation_reason: pi.cancellation_reason,
        metadata: {
          kind: pi.metadata?.kind, booking_id: pi.metadata?.booking_id,
          origem: pi.metadata?.origem ?? null,
        },
        last_payment_error: e
          ? { code: e.code ?? null, decline_code: e.decline_code ?? null, type: e.type, message: e.message ?? null }
          : null,
      });
    } catch (err) {
      out.push({ id, error: err instanceof Error ? err.message : String(err) });
    }
  }
  return json({ ok: true, mode: STRIPE_MODE, paymentIntents: out });
});
