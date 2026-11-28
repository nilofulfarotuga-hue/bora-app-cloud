// ============================================================================
// cleaning-plan — o cartão dos PLANOS de limpeza (casas e Bora Empresas)
// ----------------------------------------------------------------------------
// ⚠️ LISTA VERMELHA — PROPOSTA (missão limpeza-planos-fecho-2026-11-28, Bloco B). Não publicada
//    por esta sessão: a Claude.ai publica com o autorizo do Danilo de 28/11/2026.
//
// A app chama com a sessão do cliente (verify_jwt = true; a sessão confirma-se por dentro).
// Conta Stripe: SEMPRE a da EMPRESA (os planos nasceram depois da mudança de conta).
// Nada aqui cobra: 'setup' só GUARDA o cartão (SetupIntent, usage off_session = mandato para
// cobrar sem o cliente presente); quem cobra é o robô cleaning-plan-charge, 24 h antes.
//
// Ações (POST JSON):
//   { action:'setup',          planId }               → setupIntentClientSecret, setupIntentId,
//                                                        customerId, ephemeralKey|null, publishable_key, stripe_account
//   { action:'confirm_setup',  planId, setupIntentId } → grava o cartão (cleaning_plan_card_saved)
//   { action:'action_secret',  chargeId }             → clientSecret, paymentIntentId, amountCents, publishable_key
//   { action:'confirm_action', chargeId }             → { status: 'succeeded' | 'processing' | 'failed' }
// Erros: { error: 'stripe_indisponivel' | 'setup_not_completed' | 'nada_para_confirmar' | 'plan_closed' | … }
// (genéricos: o texto da Stripe nunca vai para a app).
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { secretKey } from '../_shared/keys.ts';
import { chavePublicavel, obterOuCriarClienteStripe, stripePara } from '../_shared/stripe_contas.ts';
import { acaoValida, depoisDoBanco, erroParaApp, motivoRecusaConfirmar, motivoRecusaSetup, uuidValido } from './regras.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const CONTA = 'empresa' as const;
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    if (!token) return json({ error: 'missing_token' }, 401);
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: userData, error: authError } = await userClient.auth.getUser();
    const user = userData?.user;
    if (authError || !user) return json({ error: 'unauthorized' }, 401);

    const body = await req.json().catch(() => ({}));
    const action = body?.action;
    if (!acaoValida(action)) return json({ error: 'invalid_action' }, 400);

    const admin = createClient(supabaseUrl, secretKey());
    let stripe: Stripe;
    try {
      stripe = stripePara(CONTA);
    } catch (e) {
      console.error('[cleaning-plan] sem chave da Stripe da empresa:', e instanceof Error ? e.message : String(e));
      return json({ error: 'stripe_indisponivel' }, 503);
    }

    // ── setup / confirm_setup: o cartão do plano ─────────────────────────────
    if (action === 'setup' || action === 'confirm_setup') {
      const planId = body?.planId;
      if (!uuidValido(planId)) return json({ error: 'planId_required' }, 400);
      const { data: plano } = await admin.from('cleaning_plans')
        .select('id, client_user_id, status').eq('id', planId).maybeSingle();
      const recusa = motivoRecusaSetup({ planoDoCliente: plano?.client_user_id === user.id, status: plano?.status });
      if (recusa) return json({ error: recusa }, recusa === 'plan_not_found' ? 404 : 409);

      if (action === 'setup') {
        const customerId = await obterOuCriarClienteStripe(admin, CONTA, user.id);
        if (!customerId) return json({ error: 'stripe_indisponivel' }, 503);
        const si = await stripe.setupIntents.create({
          customer: customerId,
          usage: 'off_session',
          payment_method_types: ['card'],
          metadata: { kind: 'cleaning_plan_setup', plan_id: planId, user_id: user.id, bora_conta: CONTA },
        });
        let ephemeralKey: string | null = null;
        try {
          const ek = await stripe.ephemeralKeys.create({ customer: customerId }, { apiVersion: '2023-10-16' });
          ephemeralKey = ek.secret ?? null;
        } catch (e) {
          console.warn('[cleaning-plan] sem chave efémera (a folha abre sem os cartões guardados):', e instanceof Error ? e.message : String(e));
        }
        return json({
          setupIntentClientSecret: si.client_secret, setupIntentId: si.id, customerId, ephemeralKey,
          publishable_key: chavePublicavel(CONTA), stripe_account: CONTA,
        });
      }

      // confirm_setup
      const setupIntentId = typeof body?.setupIntentId === 'string' ? body.setupIntentId : '';
      if (!setupIntentId.startsWith('seti_')) return json({ error: 'setup_not_completed' }, 400);
      let si: Stripe.SetupIntent;
      try {
        si = await stripe.setupIntents.retrieve(setupIntentId, { expand: ['payment_method'] });
      } catch (_) {
        return json({ error: 'setup_not_completed' }, 404);
      }
      const pm = si.payment_method && typeof si.payment_method === 'object' ? si.payment_method as Stripe.PaymentMethod : null;
      const motivo = motivoRecusaConfirmar({
        status: si.status, metaPlanId: si.metadata?.plan_id, metaUserId: si.metadata?.user_id, metaKind: si.metadata?.kind,
        planId, userId: user.id, temCartao: !!pm?.id,
      });
      if (motivo) return json({ error: motivo }, 409);
      const { data: r, error } = await admin.rpc('cleaning_plan_card_saved', {
        p_plan_id: planId, p_user_id: user.id,
        p_customer_id: typeof si.customer === 'string' ? si.customer : si.customer?.id ?? null,
        p_payment_method_id: pm!.id, p_brand: pm?.card?.brand ?? null, p_last4: pm?.card?.last4 ?? null,
        p_exp_month: pm?.card?.exp_month ?? null, p_exp_year: pm?.card?.exp_year ?? null,
      });
      if (error) {
        console.error('[cleaning-plan] card_saved falhou:', planId, error.message);
        return json({ error: erroParaApp(error.message) }, 409);
      }
      return json({ ok: true, status: r?.status ?? null });
    }

    // ── action_secret / confirm_action: o 3D Secure de uma cobrança ───────────
    const chargeId = body?.chargeId;
    if (!uuidValido(chargeId)) return json({ error: 'chargeId_required' }, 400);
    const { data: ch, error: chErr } = await admin.rpc('cleaning_plan_action_charge', { p_charge_id: chargeId, p_user_id: user.id });
    if (chErr || !ch || !ch.payment_intent_id) return json({ error: 'nada_para_confirmar' }, 404);

    let pi: Stripe.PaymentIntent;
    try {
      pi = await stripe.paymentIntents.retrieve(String(ch.payment_intent_id), { expand: ['latest_charge'] });
    } catch (_) {
      return json({ error: 'nada_para_confirmar' }, 404);
    }
    if (pi.metadata?.kind !== 'cleaning_plan' || pi.metadata?.charge_id !== chargeId || pi.metadata?.user_id !== user.id) {
      return json({ error: 'nada_para_confirmar' }, 403);
    }

    if (action === 'action_secret') {
      const piPorConfirmar = ['requires_action', 'requires_payment_method', 'requires_confirmation'].includes(pi.status);
      if (ch.status !== 'requires_action' || !piPorConfirmar) {
        return json({ error: 'nada_para_confirmar' }, 409);
      }
      return json({ clientSecret: pi.client_secret, paymentIntentId: pi.id, amountCents: pi.amount, publishable_key: chavePublicavel(CONTA), stripe_account: CONTA });
    }

    // confirm_action
    const d = depoisDoBanco(pi.status);
    if (d.resultado) {
      const recibo = pi.latest_charge && typeof pi.latest_charge === 'object' ? (pi.latest_charge as Stripe.Charge).receipt_url ?? null : null;
      const { error } = await admin.rpc('cleaning_plan_charge_result', {
        p_charge_id: chargeId, p_attempt: Number(ch.attempt ?? 0), p_outcome: d.resultado, p_payment_intent_id: pi.id,
        p_receipt_url: recibo, p_card_last4: null, p_error: d.resultado === 'card_error' ? 'o banco não confirmou' : null,
      });
      if (error) console.error('[cleaning-plan] charge_result falhou:', chargeId, error.message);
    }
    return json({ status: d.app });
  } catch (err) {
    console.error('[cleaning-plan] erro:', err instanceof Error ? err.message : String(err));
    return json({ error: erroParaApp(err) }, 500);
  }
});
