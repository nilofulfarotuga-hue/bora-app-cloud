// PROPOSTA — supabase/functions/charge-extra/index.ts — v22 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/charge-extra/; este ficheiro é a versão
// completa pronta a copiar para lá e publicar (verify_jwt=true, como hoje).
// Base: v21 em produção (= repo).
//
// O que muda na v22 (e SÓ isto): a conta Stripe do extra.
//   • `order_id` no corpo → a conta gravada nesse pedido (um extra a um pedido pago na pessoal
//     cobra-se na pessoal; o cartão guardado do cliente só existe lá).
//   • senão `stripe_account` no corpo (se a app já souber), senão a regra dos pagamentos novos
//     (app antiga → pessoal; `stripe_contas_v2: true` + interruptor 'empresa' + chave → empresa).
//   • `customerId` só se aplica se for o Stripe Customer dessa conta (users.stripe_customer_id ou
//     users.stripe_customer_id_empresa do utilizador com sessão); um id da outra conta é ignorado
//     em vez de rebentar na Stripe.
//   • Resposta: + stripe_account, publishable_key (a app abre a folha na conta certa).
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';
import {
  type ContaStripe,
  colunaClienteStripe,
  contaGravada,
  respostaConta,
  stripeDaLinha,
  stripeParaNovoPagamento,
} from '../_shared/stripe_contas.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey = secretKey() || (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

// Authenticated users: verify_jwt = true handles auth.
// Supabase rejects anonymous calls before this function runs.
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json() as {
      amount?: number;
      customerId?: string;
      order_id?: string;
      stripe_account?: string;
      stripe_contas_v2?: boolean | string;
    };
    const { amount, customerId, order_id, stripe_account } = body;

    if (typeof amount !== 'number' || !isFinite(amount) || amount <= 0) {
      return json({ error: 'amount must be a positive number (euros)' }, 400);
    }

    const amountCents = Math.round(amount * 100);

    if (amountCents < 50) {
      return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // v22 — a conta deste extra.
    let stripe: Stripe;
    let conta: ContaStripe;
    let orderMeta: Record<string, string> = {};
    if (typeof order_id === 'string' && order_id.trim()) {
      const { data: order, error: oErr } = await admin.from('orders')
        .select('id, stripe_account').eq('id', order_id.trim()).maybeSingle();
      if (oErr) console.warn('[charge-extra] pedido não lido (segue pela regra geral):', oErr.message);
      if (order) {
        ({ stripe, conta } = stripeDaLinha(order));
        orderMeta = { order_id: order.id as string };
      } else {
        ({ stripe, conta } = await stripeParaNovoPagamento(admin, { body, origem: 'charge-extra' }));
      }
    } else if (stripe_account === 'pessoal' || stripe_account === 'empresa') {
      conta = contaGravada(stripe_account);
      stripe = stripeDaLinha({ stripe_account: conta }).stripe;
    } else {
      ({ stripe, conta } = await stripeParaNovoPagamento(admin, { body, origem: 'charge-extra' }));
    }

    const intentParams: Stripe.PaymentIntentCreateParams = {
      amount: amountCents,
      currency: 'eur',
      metadata: { type: 'extra_charge', bora_conta: conta, ...orderMeta },
      automatic_payment_methods: { enabled: true },
    };

    // v22 — customerId só se for o Customer desta conta (o do utilizador com sessão).
    if (customerId && typeof customerId === 'string' && customerId.trim() !== '') {
      const pedido = customerId.trim();
      let aceite = false;
      try {
        const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
        if (token && anonKey) {
          const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
          const { data: ud } = await userClient.auth.getUser();
          const uid = ud?.user?.id;
          if (uid) {
            const coluna = colunaClienteStripe(conta);
            const { data: u } = await admin.from('users').select(coluna).eq('id', uid).maybeSingle();
            aceite = !!u && u[coluna] === pedido;
          }
        }
      } catch (e) {
        console.warn('[charge-extra] verificação do customer falhou (segue sem customer):', String(e));
      }
      if (aceite) intentParams.customer = pedido;
      else console.warn('[charge-extra] customerId ignorado: não é o Customer da conta', conta);
    }

    const intent = await stripe.paymentIntents.create(intentParams);

    console.log('[charge-extra v22] created:', intent.id, `€${amount.toFixed(2)}`, 'conta=', conta, orderMeta.order_id ?? '');

    return json({
      clientSecret: intent.client_secret,
      paymentIntentId: intent.id,
      ...respostaConta(conta),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[charge-extra] error:', message);
    return json({ error: message }, 500);
  }
});
