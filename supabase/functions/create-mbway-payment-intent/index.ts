import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

// v30 (2026-10-04, ronda de correções · checkout M3)
//   1. Exige sessão: o pedido de pagamento MB Way só sai para o DONO do pedido.
//      Antes qualquer pessoa sem login, com um order_id, disparava um pedido de
//      pagamento MB Way (valor do pedido) para o telemóvel que escolhesse.
//      verify_jwt continua false (igual ao ar) — a verificação é feita aqui,
//      com o JWT do utilizador, para devolver erros JSON que a app entende.
//   2. Janela de 24 h presa ao 1.º pagamento: a chave de idempotência era só
//      `mbway_<order_id>`. Se o 1.º pedido MB Way falhasse/expirasse (ou o
//      cliente se enganasse no número), qualquer nova tentativa nas 24 h
//      seguintes devolvia o MESMO PaymentIntent morto. Agora a chave encadeia
//      o PaymentIntent anterior do pedido: toques duplos simultâneos continuam
//      a dar o mesmo PI; uma nova tentativa depois de falhar cria um PI novo.
//      Se o PI anterior ainda está vivo (à espera da app MB WAY), devolve-se
//      esse em vez de mandar um segundo pedido ao telemóvel.
//   Resposta igual à v29 ({ok, paymentIntentId, status, mode}) — compatível.

// BUG 13 — Stripe mode toggle. Default 'live'.
const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// Estados em que o PaymentIntent anterior ainda pode ser pago pelo cliente.
const PI_VIVO = new Set(['processing', 'requires_action', 'requires_confirmation']);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── 1. Sessão obrigatória ────────────────────────────────────────────
    const token = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '').trim();
    if (!token) return json({ error: 'missing_token' }, 401);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authError || !user) {
      return json({ error: 'unauthorized', details: authError?.message }, 401);
    }

    const { order_id, phone } = await req.json() as {
      order_id?: string;
      phone?: string;
    };

    if (!order_id || !phone) {
      return json({ error: 'order_id and phone are required' }, 400);
    }

    // Normalise PT phone → E.164 (+351XXXXXXXXX)
    const e164 = phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;

    const supabase = createClient(supabaseUrl, serviceKey);

    // v28 (2026-09-21) — INTERRUPTOR MB WAY (platform_settings.mbway_enabled).
    // Ordem do Danilo: MB Way temporariamente indisponível (limite atingido).
    // Enquanto a chave estiver false o servidor recusa criar o pagamento, mesmo
    // que a app instalada ainda mostre o botão. Religar = pôr a chave a true.
    const { data: mbwayFlag } = await supabase
      .from('platform_settings')
      .select('value')
      .eq('key', 'mbway_enabled')
      .maybeSingle();

    if (mbwayFlag && mbwayFlag.value === false) {
      const { data: msgRow } = await supabase
        .from('platform_settings')
        .select('value')
        .eq('key', 'mbway_disabled_message')
        .maybeSingle();
      const msg = (typeof msgRow?.value === 'string' && msgRow.value.length > 0)
        ? msgRow.value
        : 'MB Way temporariamente indisponível. Paga em dinheiro ou com cartão.';
      console.log('[create-mbway-payment-intent] bloqueado: mbway_enabled=false',
        `order=${order_id}`);
      return json({ error: 'mbway_disabled', message: msg }, 503);
    }

    const { data: order, error: dbErr } = await supabase
      .from('orders')
      .select('user_id, payment_buffer_total, payment_method, payment_status, payment_intent_id')
      .eq('id', order_id)
      .maybeSingle();

    if (dbErr || !order) {
      return json({ error: 'Order not found' }, 404);
    }

    // ── 1b. O pedido tem de ser de quem pede o pagamento ─────────────────
    // (404 e não 403: não se confirma a quem não é dono que o pedido existe.)
    if (String(order.user_id ?? '') !== user.id) {
      console.warn('[create-mbway-payment-intent] recusado: pedido de outro utilizador',
        `order=${order_id}`, `user=${user.id}`);
      return json({ error: 'Order not found' }, 404);
    }

    if (order.payment_method !== 'mbway') {
      return json({ error: 'Order is not an MBWay order' }, 400);
    }

    if (order.payment_status !== 'pending') {
      return json({ error: 'Order already processed' }, 409);
    }

    const amountCents = Math.round((order.payment_buffer_total as number) * 100);
    if (amountCents < 50) {
      return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);
    }

    // ── 2. Tentativa anterior ────────────────────────────────────────────
    const anterior = typeof order.payment_intent_id === 'string' &&
        order.payment_intent_id.startsWith('pi_')
      ? order.payment_intent_id as string
      : null;
    if (anterior) {
      try {
        const piAnterior = await stripe.paymentIntents.retrieve(anterior);
        if (piAnterior.status === 'succeeded') {
          return json({ error: 'Order already processed' }, 409);
        }
        if (PI_VIVO.has(piAnterior.status)) {
          console.log('[create-mbway-payment-intent] PI anterior ainda vivo, reutilizado:',
            anterior, `order=${order_id}`, `status=${piAnterior.status}`);
          return json({
            ok: true,
            paymentIntentId: piAnterior.id,
            status: piAnterior.status,
            mode: STRIPE_MODE,
          });
        }
      } catch (e) {
        // Não conseguir ler o anterior não impede uma tentativa nova.
        console.warn('[create-mbway-payment-intent] retrieve do PI anterior falhou:',
          anterior, String(e));
      }
    }

    // v21 (2026-05-15) — server-side confirmation com billing_details.phone.
    // Stripe confirma o PI, envia push MBWay imediatamente, devolve
    // paymentIntentId. Flutter mostra _MBWayWaitingDialog que faz poll a
    // payment_status até o webhook (payment_intent.succeeded) marcar 'paid'.
    const intent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      payment_method_types: ['mb_way'],
      payment_method_data: {
        type: 'mb_way',
        billing_details: { phone: e164 },
      },
      confirm: true,
      metadata: { order_id },
    }, { idempotencyKey: `mbway_${order_id}_${anterior ?? 'primeiro'}` });

    console.log('[create-mbway-payment-intent] intent confirmed (server-side):',
      intent.id, `order=${order_id}`, `phone=${e164}`, `status=${intent.status}`,
      `mode=${STRIPE_MODE}`, `anterior=${anterior ?? 'nenhum'}`);

    // Guardar payment_intent_id no pedido para auditoria e reconciliação.
    const { error: piUpdateErr } = await supabase
      .from('orders')
      .update({ payment_intent_id: intent.id })
      .eq('id', order_id);

    if (piUpdateErr) {
      console.error('[create-mbway-payment-intent] failed to save payment_intent_id:',
        piUpdateErr.message, intent.id);
      // não bloquear o fluxo — o webhook ainda consegue resolver via metadata.order_id
    }

    return json({
      ok: true,
      paymentIntentId: intent.id,
      status: intent.status,
      mode: STRIPE_MODE,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-mbway-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});
