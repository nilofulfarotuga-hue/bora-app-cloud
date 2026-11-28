// ============================================================================
// cleaning-plan-charge — o robô que cobra os PLANOS de limpeza (casas e Bora Empresas)
// ----------------------------------------------------------------------------
// ⚠️ LISTA VERMELHA — PROPOSTA (missão limpeza-planos-fecho-2026-11-28, Bloco B). Não publicada
//    por esta sessão: a Claude.ai publica com o autorizo do Danilo de 28/11/2026.
//
// Quem chama: só o servidor (pg_cron 'cleaning-plan-charge', minutos 3 e 33, pela função
// _cleaning_plan_chamar_cobranca com a chave do cofre). Sem entrada. verify_jwt = true +
// exigirServidor (_shared/chaves.ts).
//
// O que faz, por esta ordem:
//   1. cleaning_plan_charges_due(): o banco arruma (cria as cobranças 48 h antes e avisa, passa a
//      'waiting_cleaner' o que não tem profissional, desmarca o que passou do prazo) e devolve o
//      que cobrar AGORA, já marcado 'processing', com a chave da Stripe desta tentativa
//      ('cleaning-plan-<idempotency_key>-a<tentativa>'). Uma tentativa presa repete com a mesma chave.
//   2. Cobra fora de sessão (off_session + confirm) no cartão guardado, na conta da EMPRESA,
//      com receipt_email e descrição "Bora · Limpeza plano/Bora Empresas · <mês> · <empresa> · NIF".
//   3. cleaning_plan_charge_result(): grava o resultado. Cartão recusado → email "troca o cartão".
//   4. cleaning_plan_refunds_due() → devoluções ao cartão (chave 'cleaning-plan-refund-<id>') →
//      cleaning_plan_refund_result().
// O valor vem SEMPRE do banco. A taxa da Stripe é da Bora. Erros ao chamador: genéricos.
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { chaveSecreta, exigirServidor } from '../_shared/chaves.ts';
import { STRIPE_MODE, stripePara } from '../_shared/stripe_contas.ts';
import { chaveValida, contar, descricao, emailTrocarCartao, resultadoDoErro, resultadoDoPi, resumoVazio, type Resultado } from './regras.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const EMAIL_FROM = 'Bora <recibos@boraguarda.com>';
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

// deno-lint-ignore no-explicit-any
type Cliente = any;

async function chaveResend(admin: Cliente): Promise<string | null> {
  const env = Deno.env.get('RESEND_API_KEY');
  if (env) return env;
  const { data } = await admin.rpc('get_resend_key');
  return data && String(data).trim() ? String(data).trim() : null;
}

async function mandarEmail(admin: Cliente, para: string, assunto: string, html: string): Promise<void> {
  try {
    const chave = await chaveResend(admin);
    if (!chave || !para) return;
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [para], subject: assunto, html }),
    });
    if (!r.ok) console.error('[cleaning-plan-charge] email falhou:', r.status);
  } catch (e) {
    console.error('[cleaning-plan-charge] email falhou:', e instanceof Error ? e.message : String(e));
  }
}

function urlRecibo(pi: Stripe.PaymentIntent): string | null {
  const ch = pi.latest_charge;
  return ch && typeof ch === 'object' ? (ch as Stripe.Charge).receipt_url ?? null : null;
}

function ultimos4(pi: Stripe.PaymentIntent): string | null {
  const ch = pi.latest_charge;
  if (ch && typeof ch === 'object') return (ch as Stripe.Charge).payment_method_details?.card?.last4 ?? null;
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const negado = await exigirServidor(req, cors);
  if (negado) return negado;

  const admin = createClient(supabaseUrl, chaveSecreta());
  let stripe: Stripe;
  try {
    stripe = stripePara('empresa');
  } catch (e) {
    console.error('[cleaning-plan-charge] sem chave da Stripe da empresa:', e instanceof Error ? e.message : String(e));
    return json({ ok: false, error: 'stripe_indisponivel' }, 500);
  }

  let resumo = resumoVazio();

  // ── 1–3. Cobranças ─────────────────────────────────────────────────────────
  const { data: due, error: dueErr } = await admin.rpc('cleaning_plan_charges_due', { p_limit: 25 });
  if (dueErr) {
    console.error('[cleaning-plan-charge] charges_due falhou:', dueErr.message);
    return json({ ok: false, error: 'servidor' }, 500);
  }
  const lista: Record<string, unknown>[] = Array.isArray(due?.cobrar) ? due.cobrar : [];

  for (const c of lista) {
    const chargeId = String(c.charge_id ?? '');
    const tentativa = Number(c.attempt ?? 0);
    const chave = c.stripe_idempotency_key;
    if (!chargeId || !tentativa || !chaveValida(chave)) {
      console.error('[cleaning-plan-charge] cobrança mal formada, saltada:', chargeId);
      resumo.erros++;
      continue;
    }
    let resultado: Resultado;
    let piId: string | null = null;
    let recibo: string | null = null;
    let last4: string | null = null;
    let mensagem: string | null = null;
    try {
      const pi = await stripe.paymentIntents.create({
        amount: Number(c.amount_cents),
        currency: 'eur',
        customer: String(c.customer_id),
        payment_method: String(c.payment_method_id),
        off_session: true,
        confirm: true,
        payment_method_types: ['card'],
        receipt_email: typeof c.receipt_email === 'string' && c.receipt_email ? c.receipt_email : undefined,
        description: descricao({
          segment: c.segment as string, period_month: c.period_month as string,
          company_name: c.company_name as string, billing_nif: c.billing_nif as string,
        }),
        metadata: {
          kind: 'cleaning_plan', charge_id: chargeId, plan_id: String(c.plan_id), user_id: String(c.user_id),
          bora_conta: 'empresa', tentativa: String(tentativa),
        },
        expand: ['latest_charge'],
      }, { idempotencyKey: chave });
      resultado = resultadoDoPi(pi.status);
      piId = pi.id;
      recibo = urlRecibo(pi);
      last4 = ultimos4(pi) ?? (c.card_last4 as string ?? null);
    } catch (err) {
      const r = resultadoDoErro(err);
      resultado = r.resultado;
      piId = r.piId;
      mensagem = r.mensagem;
      console.warn('[cleaning-plan-charge]', chargeId, 'tentativa', tentativa, '→', resultado, mensagem);
    }

    const { data: res, error: resErr } = await admin.rpc('cleaning_plan_charge_result', {
      p_charge_id: chargeId, p_attempt: tentativa, p_outcome: resultado,
      p_payment_intent_id: piId, p_receipt_url: recibo, p_card_last4: last4, p_error: mensagem,
    });
    if (resErr) {
      // A cobrança fica 'processing'; daqui a 15 min repete com a MESMA chave (a Stripe devolve o mesmo).
      console.error('[cleaning-plan-charge] charge_result falhou:', chargeId, resErr.message);
      resumo.erros++;
      continue;
    }
    resumo = contar(resumo, resultado);
    const email = res?.email;
    if (resultado === 'card_error' && email?.to) {
      const m = emailTrocarCartao({ amountCents: Number(email.amount_cents ?? c.amount_cents), final: !!email.final, quando: String(email.quando ?? '') });
      await mandarEmail(admin, String(email.to), m.assunto, m.html);
    }
  }

  // ── 4. Devoluções ao cartão ─────────────────────────────────────────────────
  const { data: refunds, error: refErr } = await admin.rpc('cleaning_plan_refunds_due', { p_limit: 25 });
  if (refErr) console.error('[cleaning-plan-charge] refunds_due falhou:', refErr.message);
  for (const f of (Array.isArray(refunds) ? refunds : []) as Record<string, unknown>[]) {
    const refundId = String(f.refund_id ?? '');
    try {
      const r = await stripe.refunds.create({
        payment_intent: String(f.payment_intent_id),
        amount: Number(f.amount_cents),
        metadata: { kind: 'cleaning_plan_refund', refund_id: refundId, booking_id: String(f.booking_id ?? ''), bora_conta: 'empresa' },
      }, { idempotencyKey: `cleaning-plan-refund-${refundId}` });
      const ok = r.status !== 'failed' && r.status !== 'canceled';
      await admin.rpc('cleaning_plan_refund_result', { p_refund_id: refundId, p_ok: ok, p_stripe_refund_id: r.id, p_error: ok ? null : r.status });
      if (ok) resumo.devolvidas++;
    } catch (err) {
      const m = err instanceof Error ? err.message : String(err);
      console.error('[cleaning-plan-charge] devolução falhou:', refundId, m);
      await admin.rpc('cleaning_plan_refund_result', { p_refund_id: refundId, p_ok: false, p_stripe_refund_id: null, p_error: m.slice(0, 300) });
      resumo.erros++;
    }
  }

  console.log('[cleaning-plan-charge]', `mode=${STRIPE_MODE}`, JSON.stringify(resumo), JSON.stringify(due?.arrumacao ?? {}));
  return json({ ok: true, ...resumo, arrumacao: due?.arrumacao ?? null });
});
