// ============================================================================
// favor-cobrar-diferenca — pede ao cliente, por MB Way, a diferença da compra de um Favor
// ----------------------------------------------------------------------------
// 03/11/2026 13:22 — autorização do Danilo, literal: "Sim, eu autorizo. E já chega a notificação
// para ele lá ... fala que eu comprei 3 pellets e ele tem que fazer o pagamento".
// Caso: Favor b72c4f2c (Divan), compra 17,97 € acima do orçado; finalize_errand_purchase marcou
// 'disputed' e não cobrou nada (bug). Mesmo padrão provado do cleaning-request-payment:
// PaymentIntent MB Way confirmado no servidor → o pedido de pagamento chega ao telemóvel do
// cliente; só sai dinheiro se ele aprovar na app MB Way.
//
// 08/11/2026 (missão m1-dinheiro-favores, autorização do Danilo 08/11): o "quanto falta" vem da
// função SQL public._favor_diferenca_devida (fonte única, também antes da compra quando o cliente
// aprova um preço maior com MB Way). Sem a função no ar, usa a conta antiga (mesmo resultado
// depois da compra). Versão no ar até aqui: v1 de 03/11 (cópia trazida para o repo a 08/11; antes
// só existia no ramo favor-diferenca-mbway-2026-11-03).
//
// Quem chama: só o servidor (chave de servidor). POST { action:'request', order_id, amount_cents,
// tentativa? } ou { action:'status', payment_intent_id }.
// O valor tem de bater com a conta do pedido. Nenhum preço muda. Metadata SEM order_id de
// propósito: o webhook trataria um MB Way recusado como falha do pedido principal
// (payment_status='failed').
// Telefone: o do MB Way do pagamento original do pedido; senão users.phone. Nunca vai para logs.
// ============================================================================
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const url = Deno.env.get('SUPABASE_URL') ?? '';
const MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase() === 'test' ? 'test' : 'live';

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
}
function dict(nome: string): Record<string, string> {
  try { const o = JSON.parse(Deno.env.get(nome) ?? '{}'); return (o && typeof o === 'object') ? o : {}; } catch { return {}; }
}
function chavesSecretas(): string[] {
  const d = Object.values(dict('SUPABASE_SECRET_KEYS')).filter((v) => typeof v === 'string' && v);
  const s = [Deno.env.get('SUPABASE_SECRET_KEY'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')].filter((v): v is string => !!v && v.startsWith('sb_secret_'));
  return [...new Set([...d, ...s])];
}
function chaveAdmin(): string {
  const d = dict('SUPABASE_SECRET_KEYS');
  return d['backend-2026-10'] ?? d['default'] ?? Object.values(d)[0] ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}
function papel(t: string): string | null {
  const p = t.split('.'); if (p.length !== 3) return null;
  try { const b = p[1].replace(/-/g, '+').replace(/_/g, '/'); return JSON.parse(atob(b + '='.repeat((4 - b.length % 4) % 4)))?.role ?? null; } catch { return null; }
}
async function doServidor(req: Request): Promise<boolean> {
  const apikey = req.headers.get('apikey') ?? '';
  const h = req.headers.get('authorization') ?? '';
  const bearer = /^bearer\s+/i.test(h) ? h.replace(/^bearer\s+/i, '').trim() : '';
  const aceites = chavesSecretas();
  for (const c of [apikey, bearer]) if (c && aceites.includes(c)) return true;
  if (bearer && papel(bearer) === 'service_role') {
    try {
      const r = await fetch(`${url}/auth/v1/admin/users?per_page=1`, { headers: { apikey: bearer, Authorization: `Bearer ${bearer}` } });
      return r.ok;
    } catch { return false; }
  }
  return false;
}
function stripeDaConta(conta: string): Stripe {
  const suf = conta === 'empresa' ? '_EMPRESA' : '';
  const k = (MODE === 'test' ? Deno.env.get(`STRIPE_TEST_SECRET_KEY${suf}`) : Deno.env.get(`STRIPE_SECRET_KEY${suf}`)) ?? '';
  if (!k.trim()) throw new Error(`stripe_chave_em_falta:${conta}`);
  return new Stripe(k.trim(), { apiVersion: '2023-10-16', httpClient: Stripe.createFetchHttpClient() });
}
function toE164(raw: string): string {
  const d = raw.replace(/[^\d+]/g, '');
  if (d.startsWith('+')) return d;
  if (d.startsWith('351')) return '+' + d;
  return '+351' + d;
}
const semNumeros = (m: string) => m.replace(/\+?\d[\d\s]{5,}\d/g, '***');

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (!(await doServidor(req))) return json({ ok: false, error: 'forbidden' }, 403);
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* vazio */ }
  if (body?.ping === true) return json({ pong: true });
  const admin = createClient(url, chaveAdmin(), { auth: { persistSession: false } });

  try {
    if (body?.action === 'status') {
      const piId = String(body?.payment_intent_id ?? '');
      const conta = body?.stripe_account === 'pessoal' ? 'pessoal' : 'empresa';
      if (!piId.startsWith('pi_')) return json({ ok: false, error: 'pi_invalido' }, 400);
      const pi = await stripeDaConta(conta).paymentIntents.retrieve(piId);
      return json({ ok: true, status: pi.status, amount: pi.amount, amount_received: pi.amount_received,
        last_error: pi.last_payment_error?.message ? semNumeros(pi.last_payment_error.message) : null });
    }

    const orderId = String(body?.order_id ?? '');
    const amountCents = Number.isInteger(body?.amount_cents) ? body.amount_cents as number : -1;
    const tentativa = Number.isInteger(body?.tentativa) && body.tentativa > 0 ? body.tentativa as number : 1;
    if (!orderId || amountCents < 50 || amountCents > 10000) return json({ ok: false, error: 'pedido_invalido' }, 400);

    const { data: o, error } = await admin.from('orders').select('id, user_id, service_type, status, payment_method, payment_intent_id, stripe_account, final_total, stripe_charge_cents, wallet_applied_cents, tokens_applied_value_cents, menu_credit_applied_cents, extra_charge_settled_at').eq('id', orderId).maybeSingle();
    if (error || !o) return json({ ok: false, error: 'pedido_nao_encontrado' }, 404);
    if (o.service_type !== 'errand') return json({ ok: false, error: 'nao_e_favor' }, 400);
    if (o.payment_method !== 'mbway') return json({ ok: false, error: 'nao_e_mbway' }, 400);
    if (['cancelled', 'rejected'].includes(String(o.status))) return json({ ok: false, error: 'pedido_fechado' }, 400);
    if (o.extra_charge_settled_at) return json({ ok: false, error: 'ja_acertado' }, 400);

    // 08/11: fonte única do "quanto falta" (também antes da compra, com a aprovação do cliente).
    let devido: number;
    const { data: devidoSql, error: devErr } = await admin.rpc('_favor_diferenca_devida', { p_pedido: orderId });
    if (!devErr && typeof devidoSql === 'number') {
      devido = devidoSql;
    } else {
      const jaPago = Number(o.stripe_charge_cents ?? 0) + Number(o.wallet_applied_cents ?? 0) + Number(o.tokens_applied_value_cents ?? 0) + Number(o.menu_credit_applied_cents ?? 0);
      devido = Math.round(Number(o.final_total ?? 0) * 100) - jaPago;
    }
    if (devido !== amountCents) return json({ ok: false, error: 'valor_nao_bate', devido_cents: devido }, 400);

    const conta = o.stripe_account === 'empresa' ? 'empresa' : 'pessoal';
    const stripe = stripeDaConta(conta);

    let phone: string | null = null;
    let origemTelefone = 'pagamento_original';
    if (o.payment_intent_id) {
      try {
        const orig = await stripe.paymentIntents.retrieve(String(o.payment_intent_id), { expand: ['payment_method'] });
        const pm = orig.payment_method as Stripe.PaymentMethod | null;
        if (pm && typeof pm === 'object' && pm.type === 'mb_way' && pm.billing_details?.phone) phone = pm.billing_details.phone;
      } catch (e) { console.error('[favor-cobrar-diferenca] PI original ilegível:', semNumeros(String(e))); }
    }
    if (!phone) {
      const { data: u } = await admin.from('users').select('phone').eq('id', o.user_id).maybeSingle();
      phone = (u?.phone as string | null) ?? null;
      origemTelefone = 'users';
    }
    if (!phone) return json({ ok: false, error: 'sem_telefone' }, 400);

    const pi = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'eur',
      payment_method_types: ['mb_way'],
      payment_method_data: { type: 'mb_way', billing_details: { phone: toE164(phone) } },
      confirm: true,
      description: `Bora — diferença da compra do Favor ${orderId.slice(0, 8)}`,
      metadata: { kind: 'errand_extra', pedido_id: orderId, user_id: String(o.user_id), origem: 'diferenca_compra_favor' },
    }, { idempotencyKey: `errand-extra-${orderId}-${tentativa}` });

    // 08/11: o PaymentIntent fica já ligado à linha da tentativa (o webhook encontra-a pelo PI).
    try {
      await admin.from('favor_diferencas').update({ payment_intent_id: pi.id, atualizado_em: new Date().toISOString() })
        .eq('pedido_id', orderId).eq('tentativa', tentativa).is('payment_intent_id', null);
    } catch { /* melhor esforço: o webhook também liga pela última linha sem PI */ }

    console.log('[favor-cobrar-diferenca]', orderId, `amount=${amountCents}`, `status=${pi.status}`, `pi=${pi.id}`, `telefone=${origemTelefone}`, `conta=${conta}`);
    try {
      await admin.from('e2e_log').insert({ fluxo: 'favor-diferenca-mbway', passo: 'pedido_enviado', estado: pi.status,
        detalhe: `pedido ${orderId} ${amountCents} cent pi=${pi.id} conta=${conta} telefone=${origemTelefone}`, device: 'edge', run_id: '2026-11-08' });
    } catch { /* melhor esforço */ }
    return json({ ok: true, payment_intent_id: pi.id, status: pi.status, amount_cents: amountCents, conta, telefone: origemTelefone });
  } catch (e) {
    const m = semNumeros(e instanceof Error ? e.message : String(e));
    console.error('[favor-cobrar-diferenca] erro:', m);
    return json({ ok: false, error: m }, 500);
  }
});
