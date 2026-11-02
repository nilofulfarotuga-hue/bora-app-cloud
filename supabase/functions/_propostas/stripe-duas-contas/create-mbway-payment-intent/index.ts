// PROPOSTA — supabase/functions/create-mbway-payment-intent/index.ts — v32 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/create-mbway-payment-intent/; este ficheiro
// é a versão completa pronta a copiar para lá e publicar (verify_jwt=false, como hoje).
// Base: v31 EM PRODUÇÃO (o repo tinha um bloco "MB Way temporariamente indisponível" que não está
// no ar — não entra; a base é a produção, como manda a missão).
//
// O que muda na v32 (e SÓ isto):
//   • Conta Stripe por pagamento (_shared/stripe_contas.ts): pedido já com PI → a conta gravada
//     (orders.stripe_account); pedido sem PI → decide-se agora (app antiga ou interruptor em
//     'pessoal' → pessoal; app com `stripe_contas_v2: true` + interruptor 'empresa' + chave → empresa).
//   • orders.stripe_account gravado junto com o payment_intent_id.
//   • Resposta devolve `stripe_account` (o MB Way não usa chave publicável no app).
//   • Erro a construir o cliente da empresa → cai para a pessoal, regista e alerta.
// v30 (sessão + idempotência encadeada) e v31 (gorjeta do carrinho no mesmo PI) ficam intactos.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';
import {
  type ContaStripe,
  STRIPE_MODE,
  contaGravada,
  stripeDaLinha,
  stripeParaNovoPagamento,
} from '../_shared/stripe_contas.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = secretKey() ?? '';

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
    // ── 1. Sessão obrigatória ────────────────────────────────────
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

    const body = await req.json() as {
      order_id?: string;
      phone?: string;
      stripe_contas_v2?: boolean | string;
    };
    const { order_id, phone } = body;

    if (!order_id || !phone) {
      return json({ error: 'order_id and phone are required' }, 400);
    }

    // Normalise PT phone → E.164 (+351XXXXXXXXX)
    const e164 = phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;

    const supabase = createClient(supabaseUrl, serviceKey);

    // v28 (2026-09-21) — INTERRUPTOR MB WAY (platform_settings.mbway_enabled).
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
      .select('user_id, payment_buffer_total, payment_method, payment_status, payment_intent_id, stripe_account')
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

    // v31 (gorjetas 30/10): a gorjeta do carrinho deste pedido vai no mesmo pagamento.
    // Erro a ler (ex.: migração por aplicar) = sem gorjeta, como a v30.
    let gorjetaCents = 0;
    {
      const { data: g, error: gErr } = await supabase.rpc('gorjeta_checkout_mbway_valor', { p_order_id: order_id });
      if (gErr) console.error('[create-mbway-payment-intent] gorjeta não lida (segue sem gorjeta):', gErr.message);
      else gorjetaCents = Math.max(0, Math.round(Number(g ?? 0)));
    }
    const amountCents = Math.round((order.payment_buffer_total as number) * 100) + gorjetaCents;
    if (amountCents < 50) {
      return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);
    }

    // ── 2. Tentativa anterior ────────────────────────────────────────
    const anterior = typeof order.payment_intent_id === 'string' &&
        order.payment_intent_id.startsWith('pi_')
      ? order.payment_intent_id as string
      : null;

    // v32 — a conta: com PI anterior fica-se na conta onde ele foi criado (o PI só existe lá);
    // sem PI decide-se agora. Nunca se muda de conta a meio de um pedido.
    let stripe: Stripe;
    let conta: ContaStripe;
    if (anterior) {
      ({ stripe, conta } = stripeDaLinha(order));
    } else {
      ({ stripe, conta } = await stripeParaNovoPagamento(supabase, { body, origem: 'create-mbway-payment-intent' }));
    }

    if (anterior) {
      try {
        const piAnterior = await stripe.paymentIntents.retrieve(anterior);
        if (piAnterior.status === 'succeeded') {
          return json({ error: 'Order already processed' }, 409);
        }
        if (PI_VIVO.has(piAnterior.status)) {
          console.log('[create-mbway-payment-intent] PI anterior ainda vivo, reutilizado:',
            anterior, `order=${order_id}`, `status=${piAnterior.status}`, `conta=${conta}`);
          return json({
            ok: true,
            paymentIntentId: piAnterior.id,
            status: piAnterior.status,
            mode: STRIPE_MODE,
            stripe_account: conta,
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
      metadata: { order_id, bora_conta: conta, ...(gorjetaCents > 0 ? { gorjeta_cents: String(gorjetaCents) } : {}) },
    }, { idempotencyKey: `mbway_${order_id}_${anterior ?? 'primeiro'}` });

    // v31: a gorjeta fica a saber qual é o pagamento que a leva. Se falhar, o gatilho reconhece-a na
    // mesma quando o valor cobrado = buffer + gorjeta.
    if (gorjetaCents > 0) {
      const { error: gpErr } = await supabase.rpc('gorjeta_checkout_mbway_pi', {
        p_order_id: order_id, p_payment_intent: intent.id,
      });
      if (gpErr) console.error('[create-mbway-payment-intent] gorjeta sem PI gravado:', gpErr.message, intent.id);
    }

    console.log('[create-mbway-payment-intent v32] intent confirmed (server-side):',
      intent.id, `order=${order_id}`, `phone=${e164}`, `status=${intent.status}`,
      `mode=${STRIPE_MODE}`, `conta=${conta}`, `anterior=${anterior ?? 'nenhum'}`);

    // Guardar payment_intent_id (e a conta onde o dinheiro vai entrar) no pedido para auditoria,
    // reconciliação e reembolsos.
    const patch: Record<string, unknown> = { payment_intent_id: intent.id };
    if (contaGravada(order.stripe_account) !== conta) patch.stripe_account = conta;
    const { error: piUpdateErr } = await supabase
      .from('orders')
      .update(patch)
      .eq('id', order_id);

    if (piUpdateErr) {
      console.error('[create-mbway-payment-intent] failed to save payment_intent_id:',
        piUpdateErr.message, intent.id);
      // não bloquear o fluxo — o webhook ainda consegue resolver via metadata.order_id
      // (e o webhook da conta certa grava stripe_account ao marcar pago).
    }

    return json({
      ok: true,
      paymentIntentId: intent.id,
      status: intent.status,
      mode: STRIPE_MODE,
      amountCents,   // v31: compra + gorjeta do carrinho
      gorjetaCents,  // v31
      stripe_account: conta, // v32
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[create-mbway-payment-intent] error:', message);
    return json({ error: message }, 500);
  }
});
