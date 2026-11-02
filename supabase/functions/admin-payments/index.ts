// supabase/functions/admin-payments/index.ts — v1 (2026-07-21)
//
// Carteira Única, Parte 6/6 — o que a aba admin "Pagamentos/Cartões" precisa e
// que NÃO se consegue tirar da base de dados:
//   • list_cards    — cartões guardados de UM cliente (só a Stripe os tem).
//   • stuck_intents — PaymentIntents parados à espera de 3DS (requires_action).
//   • refund        — estorno.
//
// SOBRE O ESTORNO: esta função NÃO reimplementa o refund. Verifica que quem
// chama é admin e delega na Edge Fn `refund` (blindada), que continua a ser a
// única implementação — mantém o cap contra o valor capturado, a idempotency
// key e o 409 charge_missing. A `refund` exige um JWT com role=service_role,
// que um admin autenticado na app não tem; é exactamente essa a ponte que
// falta e que esta função faz, sem afrouxar nada.
//
// Auth: verify_jwt=true. Além disso exige app_metadata.role='admin' no JWT do
// utilizador — a mesma guarda do resto do painel (AuthAdminService.isAdmin()).

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Duas contas Stripe (missão stripe-empresa-2026-11-01): o painel vê AS DUAS contas. Cada cartão e
// cada PaymentIntent sai marcado com `stripe_account`; o estorno passa a conta à função refund.
import { type ContaStripe, CONTAS_STRIPE, colunaClienteStripe, estadoChaves, temChaveSecreta, stripePara } from '../_shared/stripe_contas.ts';
import { chamadaDoServidor } from '../_shared/chaves.ts';
const contasComChave = (): ContaStripe[] => CONTAS_STRIPE.filter((c) => temChaveSecreta(c));

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SERVICE_KEY = secretKey() ?? '';

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// ── prova de uma conta (F6 das duas contas, 02/11/2026) ────────────────────────────────────
// Cria um PaymentIntent de 0,50 € SEM meio de pagamento e cancela-o logo: sem cartão não há
// cobrança. Prova que a chave da conta escreve PaymentIntents e faz a Stripe mandar o evento
// payment_intent.canceled ao webhook dessa conta (lá fica como "pagamento sem pedido", 200).
// deno-lint-ignore no-explicit-any
async function provaConta(admin: any, body: any, quem: string): Promise<Response> {
  const conta: ContaStripe = body?.conta === 'pessoal' ? 'pessoal' : 'empresa';
  if (!temChaveSecreta(conta)) return json({ ok: false, error: 'stripe_chave_em_falta', conta }, 409);
  let r: Record<string, unknown>;
  try {
    const stripe = stripePara(conta);
    const pi = await stripe.paymentIntents.create({
      amount: 50,
      currency: 'eur',
      payment_method_types: ['card'],
      description: 'Prova Bora duas contas (criado e cancelado logo, sem cobrança)',
      metadata: { kind: 'prova_conta', bora_conta: conta, origem: 'admin-payments', quem },
    });
    const cancelado = await stripe.paymentIntents.cancel(pi.id, { cancellation_reason: 'abandoned' });
    r = {
      ok: cancelado.status === 'canceled', conta, payment_intent_id: pi.id, valor_cents: pi.amount,
      estado_criado: pi.status, estado_final: cancelado.status, livemode: pi.livemode,
    };
  } catch (e) {
    r = { ok: false, conta, error: e instanceof Error ? e.message : String(e) };
  }
  try {
    await admin.from('e2e_log').insert({
      fluxo: 'stripe-duas-contas', passo: 'prova_conta', estado: r.ok ? 'ok' : 'falhou',
      detalhe: JSON.stringify({ ...r, quem }).slice(0, 2000), device: 'edge',
      run_id: new Date().toISOString().slice(0, 10),
    });
  } catch (_) { /* o registo é melhor-esforço */ }
  return json(r, r.ok ? 200 : 502);
}

// ── destinos de webhook de cada conta (só leitura: URL, estado e eventos; nunca o segredo) ──
// A chave restrita da empresa pode não ter permissão de ler webhooks: aí vem o erro da Stripe.
async function webhooksDasContas(): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  for (const conta of contasComChave()) {
    try {
      const lista = await stripePara(conta).webhookEndpoints.list({ limit: 20 });
      out[conta] = lista.data.map((w: Stripe.WebhookEndpoint) => ({ id: w.id, url: w.url, status: w.status, versao_api: w.api_version ?? null, eventos: w.enabled_events }));
    } catch (e) {
      out[conta] = { erro: e instanceof Error ? e.message : String(e) };
    }
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // A prova também se pode pedir do próprio servidor (pg_net com a chave do cofre), sem sessão.
    const bodyCedo = await req.clone().json().catch(() => ({}));
    const acaoCedo = String(bodyCedo?.action ?? '');
    if ((acaoCedo === 'prova_conta' || acaoCedo === 'webhooks') && await chamadaDoServidor(req)) {
      if (acaoCedo === 'webhooks') return json({ webhooks: await webhooksDasContas() });
      return await provaConta(createClient(SUPABASE_URL, SERVICE_KEY), bodyCedo, 'servidor');
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json({ error: 'missing_token' }, 401);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData, error: authErr } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authErr || !user) return json({ error: 'unauthorized' }, 401);

    // Guarda de admin — app_metadata é imutável pelo cliente.
    // deno-lint-ignore no-explicit-any
    const role = (user.app_metadata as any)?.role;
    if (role !== 'admin') {
      console.warn('[admin-payments] nao-admin tentou aceder:', user.id);
      return json({ error: 'forbidden: admin only' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? '');
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    // ── cartões guardados de um cliente ───────────────────────────────
    if (action === 'list_cards') {
      const targetUserId = String(body?.user_id ?? '');
      if (!targetUserId) return json({ error: 'user_id_required' }, 400);

      const { data: row, error: selErr } = await admin
        .from('users').select('stripe_customer_id, stripe_customer_id_empresa').eq('id', targetUserId).maybeSingle();
      if (selErr) return json({ error: 'db_error', details: selErr.message }, 500);

      // duas contas: os cartões de cada conta, marcados com a conta
      // Só marca + últimos 4. O número completo nunca sai da Stripe.
      const cards: Record<string, unknown>[] = [];
      for (const conta of contasComChave()) {
        const customerId = (row as Record<string, unknown> | null)?.[colunaClienteStripe(conta)] as string | undefined;
        if (!customerId) continue;
        const stripe = stripePara(conta);
        const [pmList, customer] = await Promise.all([
          stripe.paymentMethods.list({ customer: customerId, type: 'card', limit: 20 }),
          stripe.customers.retrieve(customerId),
        ]);
        const defaultPm = (customer && !customer.deleted)
          ? ((customer as Stripe.Customer).invoice_settings?.default_payment_method ?? null)
          : null;
        const defaultPmId = typeof defaultPm === 'string'
          ? defaultPm
          : (defaultPm as Stripe.PaymentMethod | null)?.id ?? null;
        for (const pm of pmList.data) {
          cards.push({
            id: pm.id,
            brand: pm.card?.brand ?? 'card',
            last4: pm.card?.last4 ?? '••••',
            exp_month: pm.card?.exp_month ?? null,
            exp_year: pm.card?.exp_year ?? null,
            is_default: pm.id === defaultPmId,
            stripe_account: conta,
          });
        }
      }
      return json({ cards });
    }

    // ── PaymentIntents parados à espera de 3DS ────────────────────────
    if (action === 'stuck_intents') {
      const limit = Math.min(Number(body?.limit ?? 100), 100);
      // duas contas: lista das duas, cada PI marcado com a conta
      const intents: Record<string, unknown>[] = [];
      let scanned = 0;
      for (const conta of contasComChave()) {
        const list = await stripePara(conta).paymentIntents.list({ limit });
        scanned += list.data.length;
        for (const pi of list.data) {
          if (pi.status !== 'requires_action' && pi.status !== 'requires_confirmation') continue;
          intents.push({
            id: pi.id,
            status: pi.status,
            amount_cents: pi.amount,
            currency: pi.currency,
            created: pi.created,
            customer: typeof pi.customer === 'string' ? pi.customer : pi.customer?.id ?? null,
            metadata: pi.metadata ?? {},
            stripe_account: conta,
          });
        }
      }
      intents.sort((a, b) => Number(b.created) - Number(a.created));
      return json({ intents, scanned });
    }

    // ── estado das duas contas (só nomes/booleans, nunca valores) ────────
    if (action === 'contas') {
      return json({ contas: estadoChaves() });
    }

    // ── prova de uma conta: 0,50 € criado e cancelado logo (sem cobrança) ──
    if (action === 'prova_conta') {
      return await provaConta(admin, body, user.id);
    }

    // ── destinos de webhook das duas contas (só leitura) ──
    if (action === 'webhooks') {
      return json({ webhooks: await webhooksDasContas() });
    }

    // ── estorno (delegado na EF blindada) ──────────────────────────
    if (action === 'refund') {
      const paymentIntentId = String(body?.payment_intent_id ?? '');
      const amountCents = Number(body?.amount_cents ?? 0);
      if (!paymentIntentId) return json({ error: 'payment_intent_id_required' }, 400);
      if (!Number.isFinite(amountCents) || amountCents <= 0) {
        return json({ error: 'amount_cents_invalid' }, 400);
      }

      // A `refund` recebe o valor em EUROS e exige JWT service_role.
      const { data, error } = await admin.functions.invoke('refund', {
        body: {
          paymentIntentId,
          amount: amountCents / 100,
          userId: body?.user_id ?? null,
          orderId: body?.entity_id ?? null,
          stripe_account: body?.stripe_account ?? null, // duas contas: a função refund confirma pela linha se vier vazio
        },
      });
      if (error) {
        console.error('[admin-payments] refund falhou:', error.message);
        return json({ error: 'refund_failed', details: error.message }, 502);
      }
      // deno-lint-ignore no-explicit-any
      const d = data as any;
      if (d?.error) return json({ error: d.error, details: d.details ?? null }, 409);

      // Auditoria: quem estornou, o quê e quanto.
      await admin.from('admin_audit_log').insert({
        admin_id: user.id,
        admin_email: user.email ?? null,
        action: 'payment_refunded',
        entity_type: 'payment_intent',
        entity_id_text: paymentIntentId,
        details: {
          amount_cents: amountCents,
          refund_id: d?.refundId ?? null,
          reason: body?.reason ?? null,
          vertical: body?.vertical ?? null,
        },
      }).then(
        () => {},
        (e: unknown) => console.warn('[admin-payments] auditoria falhou:', e),
      );

      return json({ ok: true, refund_id: d?.refundId ?? null });
    }

    return json({ error: 'invalid_action' }, 400);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[admin-payments] error:', msg);
    return json({ error: msg }, 500);
  }
});
