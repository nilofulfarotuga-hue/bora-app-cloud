// supabase/functions/manage-saved-cards/index.ts — v1 (2026-07-21)
//
// Gestao dos cartoes guardados do user autenticado (Carteira Unica, Parte 1/6).
// Complementa list-saved-cards, que so LE. Esta funcao ESCREVE, mas nunca
// movimenta dinheiro:
//   - NAO cria PaymentIntent, NAO cobra, NAO reembolsa.
//   - NAO toca em precos, taxas, comissoes nem bora_tokens.
// As unicas chamadas Stripe sao paymentMethods.detach e customers.update
// (invoice_settings.default_payment_method).
//
// Auth: verify_jwt=true via config.toml. Authorization Bearer com user JWT.
// Service role usado APENAS para SELECT users.stripe_customer_id (RLS bloquearia
// o user de ler colunas administrativas como stripe_customer_id).
//
// Pedido:
//   { action: 'detach'      , payment_method_id: 'pm_xxx' }
//   { action: 'set_default' , payment_method_id: 'pm_xxx' }
//
// Resposta:
//   { ok: true, action, payment_method_id }
//
// Guarda-costas de posse: o payment method tem de pertencer ao Stripe Customer
// do proprio user. Sem isto, um user autenticado podia apagar o cartao de outro
// so por adivinhar o pm_id.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { type ContaStripe, CONTAS_STRIPE, colunaClienteStripe, temChaveSecreta, stripePara } from '../_shared/stripe_contas.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Duas contas Stripe (missão stripe-empresa-2026-11-01): o cartão pertence ao Customer de UMA
// conta. O corpo pode dizer qual (`stripe_account`); senão procura-se nas duas (só nas que o
// utilizador tem Customer e há chave).

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey     = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const serviceKey  = secretKey() ?? '';

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json({ error: 'missing_token' }, 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authErr } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authErr || !user) return json({ error: 'unauthorized', details: authErr?.message }, 401);

    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? '');
    const pmId = String(body?.payment_method_id ?? '');

    if (action !== 'detach' && action !== 'set_default') {
      return json({ error: 'invalid_action', details: 'use detach ou set_default' }, 400);
    }
    if (!pmId.startsWith('pm_')) {
      return json({ error: 'invalid_payment_method_id' }, 400);
    }

    // Service role: ler stripe_customer_id (admin-only column).
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: row, error: selErr } = await admin
      .from('users')
      .select('stripe_customer_id, stripe_customer_id_empresa')
      .eq('id', user.id)
      .maybeSingle();

    if (selErr) {
      console.error('[manage-saved-cards] users select failed:', selErr.message);
      return json({ error: 'db_error', details: selErr.message }, 500);
    }

    // duas contas: candidatas = a pedida, ou todas as que têm Customer deste utilizador e chave
    const pedida = body?.stripe_account;
    const candidatas: ContaStripe[] = (pedida === 'pessoal' || pedida === 'empresa')
      ? [pedida]
      : CONTAS_STRIPE.filter((c) => !!row?.[colunaClienteStripe(c)] && temChaveSecreta(c));
    let achada: { conta: ContaStripe; customerId: string } | null = null;
    for (const c of candidatas) {
      const customerId = row?.[colunaClienteStripe(c)] as string | undefined;
      if (!customerId) continue;
      try {
        const pm = await stripePara(c).paymentMethods.retrieve(pmId);
        const pmCustomer = typeof pm.customer === 'string' ? pm.customer : pm.customer?.id ?? null;
        if (pmCustomer === customerId) { achada = { conta: c, customerId }; break; }
      } catch (e) {
        // o cartão não existe nesta conta: tenta a próxima
        console.log('[manage-saved-cards] cartão não está na conta', c, String(e).slice(0, 120));
      }
    }
    if (!achada) {
      if (candidatas.length === 0) return json({ error: 'no_customer' }, 404);
      console.warn('[manage-saved-cards] ownership mismatch', { user: user.id, pmId });
      return json({ error: 'not_your_card' }, 403);
    }
    const { conta, customerId } = achada;
    const stripe = stripePara(conta);

    if (action === 'detach') {
      await stripe.paymentMethods.detach(pmId);
    } else {
      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: pmId },
      });
    }

    return json({ ok: true, action, payment_method_id: pmId, stripe_account: conta });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[manage-saved-cards] error:', msg);
    return json({ error: msg }, 500);
  }
});
