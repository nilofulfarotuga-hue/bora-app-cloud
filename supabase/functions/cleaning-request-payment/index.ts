// ============================================================================
// cleaning-request-payment — pede ao cliente o MB Way de uma limpeza sem ele abrir a app
// ----------------------------------------------------------------------------
// 19/10/2026 (missão limpeza-semanal-pagamento-19-10). Autorização do Danilo, literal:
//   "autorizo arrumar as limpezas semanais" + "Pode" + "o divã tem que fazer o pagamento
//   do MBA. E aí tem que chegar a notificação no telemóvel dele, no MBA dele, para ele
//   fazer o pagamento."
//
// Para quê: numa série semanal paga por MB Way, a reserva nova nasce por pagar e a
// profissional só é chamada depois de pago (_cleaning_next_offer). Esta função faz chegar
// o pedido de MB Way ao telemóvel do cliente. Quando ele aprova, o stripe-webhook
// (kind='cleaning') chama confirm_cleaning_payment_webhook → payment_status='held' →
// o gatilho trg_cleaning_paid_offer chama a profissional. Esta função NÃO mexe no estado.
//
// Quem chama: só o servidor — a função SQL public.cleaning_request_payment (pg_net, com
// a chave de servidor do cofre). verify_jwt = true + chamadaDoServidor (_shared/chaves.ts).
//
// Body: { bookingId, tentativa? }
// Valor: SEMPRE cleaning_bookings.total_cents (nunca vem do pedido). Nenhum preço muda.
// Telefone: o do último MB Way pago deste cliente na Stripe (metadata user_id); se não
//   houver, users.phone. O telefone nunca vai para os logs.
// Chave Stripe: mesmo padrão do cleaning-checkout (BORA_STRIPE_MODE=test → chave de teste).
// v2 (19/10/2026, revisor): não cria pedido novo se a reserva já tem um à espera do cliente
//   ou já pago na Stripe; telefone escolhido pelo tipo real do meio de pagamento (mb_way);
//   números de telefone nunca vão para os logs nem para a resposta.
// ============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { chaveSecreta, exigirServidor } from '../_shared/chaves.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecret = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecret, { apiVersion: '2023-10-16' });

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

// Igual ao cleaning-checkout.
function toE164(raw: string): string {
  const digits = raw.replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('351')) return '+' + digits;
  return '+351' + digits;
}

// As mensagens de erro da Stripe podem trazer o número de telefone: nunca vão inteiras
// para os logs nem para a resposta.
function semNumeros(m: string): string {
  return m.replace(/\+?\d[\d\s]{5,}\d/g, '***');
}

// O telefone do último MB Way que este cliente pagou (é o que ele usa de certeza).
async function telefoneDoUltimoMbWay(userId: string): Promise<string | null> {
  try {
    const r = await stripe.paymentIntents.search({
      query: `metadata['user_id']:'${userId}' AND status:'succeeded'`,
      limit: 20,
      expand: ['data.payment_method'],
    });
    const pagos = (r.data as Stripe.PaymentIntent[])
      .sort((a: Stripe.PaymentIntent, b: Stripe.PaymentIntent) => b.created - a.created);
    for (const pi of pagos) {
      let pm = pi.payment_method;
      if (typeof pm === 'string') pm = await stripe.paymentMethods.retrieve(pm);
      // O tipo do meio de pagamento usado, não os tipos que o pedido aceitava.
      if (!pm || pm.type !== 'mb_way') continue;
      const phone = pm.billing_details?.phone;
      if (phone) return phone;
    }
  } catch (e) {
    console.error('[cleaning-request-payment] pesquisa Stripe falhou:',
      semNumeros(e instanceof Error ? e.message : String(e)));
  }
  return null;
}

// 19/10/2026 (revisor): não criar um segundo pedido enquanto o anterior desta reserva está
// à espera do cliente (o cron e o botão do painel podiam juntar dois no telemóvel dele), nem
// pedir de novo se a Stripe já tem um pagamento desta reserva (o webhook pode vir atrasado).
async function pedidoJaExistente(bookingId: string): Promise<{ estado: string; pi: string } | null> {
  try {
    const r = await stripe.paymentIntents.search({
      query: `metadata['booking_id']:'${bookingId}'`,
      limit: 20,
    });
    for (const pi of r.data as Stripe.PaymentIntent[]) {
      if (pi.metadata?.kind !== 'cleaning') continue;
      if (pi.status === 'succeeded' || pi.status === 'processing' || pi.status === 'requires_capture') {
        return { estado: 'ja_pago_na_stripe', pi: pi.id };
      }
      if (pi.status === 'requires_action') return { estado: 'pedido_pendente', pi: pi.id };
    }
  } catch (e) {
    // Se a pesquisa falhar, segue: a chave de idempotência ainda trava a repetição de rede.
    console.error('[cleaning-request-payment] pesquisa de pedidos falhou:',
      semNumeros(e instanceof Error ? e.message : String(e)));
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const negado = await exigirServidor(req, cors);
  if (negado) return negado;

  try {
    const body = await req.json().catch(() => ({}));
    const bookingId = typeof body?.bookingId === 'string' ? body.bookingId : '';
    if (!UUID.test(bookingId)) return json({ ok: false, error: 'bookingId_required' }, 400);

    const admin = createClient(supabaseUrl, chaveSecreta());
    const { data: b, error: bErr } = await admin
      .from('cleaning_bookings')
      .select('id, client_user_id, payment_method, payment_status, status, total_cents, payment_request_count')
      .eq('id', bookingId)
      .maybeSingle();
    if (bErr) return json({ ok: false, error: 'booking_read_failed', details: bErr.message }, 500);
    if (!b) return json({ ok: false, error: 'booking_not_found' }, 404);

    if (b.payment_method !== 'mbway') return json({ ok: false, error: 'not_mbway' });
    if (b.payment_status !== 'unpaid') {
      return json({ ok: false, error: 'not_unpaid', payment_status: b.payment_status });
    }
    if (String(b.status ?? '').startsWith('cancelled')) {
      return json({ ok: false, error: 'cancelled', status: b.status });
    }

    const amountCents = Number(b.total_cents ?? 0);
    if (!amountCents || amountCents < 50) return json({ ok: false, error: 'amount_below_minimum' });

    const tentativa = Number.isInteger(body?.tentativa) && body.tentativa > 0
      ? body.tentativa as number
      : Math.max(1, Number(b.payment_request_count ?? 0));

    const existente = await pedidoJaExistente(bookingId);
    if (existente) {
      console.log('[cleaning-request-payment]', bookingId, `tentativa=${tentativa}`,
        `nao_criado=${existente.estado}`, `pi=${existente.pi}`);
      return json({ ok: false, error: existente.estado, paymentIntentId: existente.pi, tentativa });
    }

    let phone = await telefoneDoUltimoMbWay(b.client_user_id);
    let origemTelefone = 'stripe';
    if (!phone) {
      const { data: u } = await admin.from('users').select('phone')
        .eq('id', b.client_user_id).maybeSingle();
      phone = (u?.phone as string | null | undefined) ?? null;
      origemTelefone = 'users';
    }
    if (!phone) {
      console.error('[cleaning-request-payment] sem telefone', bookingId);
      return json({ ok: false, error: 'phone_missing' });
    }

    let pi;
    try {
      pi = await stripe.paymentIntents.create({
        amount: amountCents,
        currency: 'eur',
        payment_method_types: ['mb_way'],
        payment_method_data: {
          type: 'mb_way',
          billing_details: { phone: toE164(phone) },
        },
        confirm: true,
        metadata: {
          kind: 'cleaning',
          booking_id: bookingId,
          user_id: b.client_user_id,
          origem: 'pedido_automatico',
        },
      }, { idempotencyKey: `cleaning-req-${bookingId}-${tentativa}` });
    } catch (e) {
      const m = semNumeros(e instanceof Error ? e.message : String(e));
      console.error('[cleaning-request-payment] stripe error:', bookingId, `tentativa=${tentativa}`, m);
      return json({ ok: false, error: 'mbway_create_failed', details: m }, 400);
    }

    console.log('[cleaning-request-payment]', bookingId, `tentativa=${tentativa}`,
      `amount=€${(amountCents / 100).toFixed(2)}`, `status=${pi.status}`, `pi=${pi.id}`,
      `telefone=${origemTelefone}`, `mode=${STRIPE_MODE}`);
    return json({
      ok: true, paymentIntentId: pi.id, status: pi.status, amountCents, tentativa,
      telefone: origemTelefone,
    });
  } catch (err) {
    const message = semNumeros(err instanceof Error ? err.message : String(err));
    console.error('[cleaning-request-payment] error:', message);
    return json({ ok: false, error: message }, 500);
  }
});
