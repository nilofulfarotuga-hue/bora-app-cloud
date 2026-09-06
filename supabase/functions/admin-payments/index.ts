// supabase/functions/admin-payments/index.ts — v1 (2026-07-21)
//
// Carteira Única, Parte 6/6 — o que a aba admin "Pagamentos/Cartões" precisa e
// que NÃO se consegue tirar da base de dados:
//   • list_cards    — cartões guardados de UM cliente (só a Stripe os tem;
//                     list-saved-cards usa o JWT de quem chama, logo não serve
//                     para o admin ver os de outra pessoa).
//   • stuck_intents — PaymentIntents parados à espera de 3DS. O estado
//                     'requires_action' é transitório e NUNCA é gravado na
//                     nossa base de dados; só a Stripe o sabe.
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

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey = STRIPE_MODE === 'test'
  ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
  : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

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

    // ── cartões guardados de um cliente ─────────────────────────────────────
    if (action === 'list_cards') {
      const targetUserId = String(body?.user_id ?? '');
      if (!targetUserId) return json({ error: 'user_id_required' }, 400);

      const { data: row, error: selErr } = await admin
        .from('users').select('stripe_customer_id').eq('id', targetUserId).maybeSingle();
      if (selErr) return json({ error: 'db_error', details: selErr.message }, 500);

      const customerId = row?.stripe_customer_id as string | undefined;
      if (!customerId) return json({ cards: [] });

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

      // Só marca + últimos 4. O número completo nunca sai da Stripe.
      return json({
        cards: pmList.data.map((pm) => ({
          id: pm.id,
          brand: pm.card?.brand ?? 'card',
          last4: pm.card?.last4 ?? '••••',
          exp_month: pm.card?.exp_month ?? null,
          exp_year: pm.card?.exp_year ?? null,
          is_default: pm.id === defaultPmId,
        })),
      });
    }

    // ── PaymentIntents parados à espera de 3DS ──────────────────────────────
    if (action === 'stuck_intents') {
      const limit = Math.min(Number(body?.limit ?? 100), 100);
      // A API da Stripe não filtra por status na listagem — pedimos os mais
      // recentes e filtramos aqui.
      const list = await stripe.paymentIntents.list({ limit });
      const stuck = list.data.filter((pi) =>
        pi.status === 'requires_action' || pi.status === 'requires_confirmation'
      );
      return json({
        intents: stuck.map((pi) => ({
          id: pi.id,
          status: pi.status,
          amount_cents: pi.amount,
          currency: pi.currency,
          created: pi.created,
          customer: typeof pi.customer === 'string' ? pi.customer : pi.customer?.id ?? null,
          // metadata diz de que vertical veio (order_id / reservation_id / ...)
          metadata: pi.metadata ?? {},
        })),
        scanned: list.data.length,
      });
    }

    // ── estorno (delegado na EF blindada) ───────────────────────────────────
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
      // entity_id e UUID; o id do PaymentIntent ('pi_...') vai em entity_id_text.
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
