// ============================================================================
// cobrar-diferenca-peso — PESO VARIÁVEL: cobrar no cartão a diferença a mais
// ----------------------------------------------------------------------------
// 🔴 LISTA VERMELHA (cartão). Regra do Danilo 26/10/2026 10:16 ("Autorizo."): o cliente paga o
// valor final dos produtos ao quilo; pagou com cartão e saiu mais caro → cobra-se a diferença no
// MESMO cartão. Missão fecho-pendentes-2026-10-31 (31/10 22:08): fica PRONTA mas DESLIGADA
// (platform_settings.weight_adjust_card_charge_enabled = false). business_rules §59.
//
// Quem chama: SÓ o servidor — finalizar_talao_nao_parceiro faz net.http_post com a chave de servidor
// quando o interruptor está ligado e o talão deu card_extra_cents > 0. Com o interruptor desligado
// esta função recusa sem cobrar nada, mesmo que alguém com a chave a chame.
//
// POST { order_id, amount_cents }   (ou { ping:true } do vigia das chaves → { pong:true })
// Só cobra quando TUDO bate:
//   - pedido pago com cartão ('card' | 'stripe'), compra fechada (is_purchase_finalized);
//   - amount_cents = ROUND(orders.extra_charge_amount × 100) (o que o talão gravou) e 1..5000;
//   - ainda não acertado (extra_charge_settled_at IS NULL).
// Cobra com o cartão e o Customer do pagamento original (payment_intent_id do pedido),
// off_session + confirm, idempotência "peso_<order_id>". Nunca marca nada como pago sem a Stripe
// dizer succeeded.
//   sucesso → orders.final_total += valor, extra_charge_settled_at, extra_charge_settled_via =
//             'cartao_peso'; order_weight_adjustments.settled_via = 'cartao_cobrado'; aviso no sino.
//   sem cartão reutilizável / o banco pede autenticação / recusado → settled_via = 'bora_assume'
//             e aviso URGENTE ao Danilo pelo porteiro (porteiro_entrada).
// Como ligar e vigiar: ver o relatório fecho-pendentes-2026-10-31 (secção ISTO MEXE EM DINHEIRO).
//
// 10/11/2026 (missão fechar-tudo-2026-11-10, Bloco C): a leitura do cartão e a cobrança passaram
// para _shared/peso_cartao.ts (o MESMO código serve o pedido real e o ensaio, e tem testes Deno).
// MODO ENSAIO: POST { ensaio:true, caso:'a_mais'|'a_menos'|'recusado'|'pede_autenticacao' } com a
// chave de servidor (RPC admin_ensaio_peso_cartao) → corre o caso na Stripe da EMPRESA em MODO DE
// TESTE (só STRIPE_TEST_SECRET_KEY_EMPRESA), grava em ensaio_peso_cartao, não toca em orders nem em
// dinheiro, e funciona com o interruptor desligado. Ver ensaio.ts e
// docs/propostas/fechar-tudo-2026-11-10/C_LEIA-ME.md.
// ============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { exigirServidor, respostaAoPing } from '../_shared/chaves.ts';
import { stripeDaLinha } from '../_shared/stripe_contas.ts';
import { cobrarDiferencaNoCartao, MAX_CENTS_PESO, type StripePeso } from '../_shared/peso_cartao.ts';
import {
  type CasoEnsaio,
  correrEnsaio,
  estadoChaveDeTeste,
  lerPedidoDeEnsaio,
  linhaDeErro,
  type LinhaEnsaio,
  MENSAGEM_FALTA_CHAVE,
  MENSAGEM_NAO_E_TESTE,
  NOME_CHAVE_TESTE,
  type StripeEnsaio,
} from './ensaio.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Duas contas Stripe (missão stripe-empresa-2026-11-01): a diferença de peso cobra-se na conta
// onde o pedido foi pago (orders.stripe_account) — o cartão guardado só existe lá.

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const MAX_CENTS = MAX_CENTS_PESO;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// deno-lint-ignore no-explicit-any
type Admin = any;

async function interruptorLigado(admin: Admin): Promise<boolean> {
  const { data } = await admin.from('platform_settings').select('value')
    .eq('key', 'weight_adjust_card_charge_enabled').maybeSingle();
  const v = data?.value;
  return v === true || v === 'true';
}

async function boraAssume(admin: Admin, orderId: string, motivo: string, amountCents: number) {
  await admin.from('order_weight_adjustments')
    .update({ settled_via: 'bora_assume', settled_at: new Date().toISOString() })
    .eq('order_id', orderId).eq('settled_via', 'cartao_pendente');
  const euros = (amountCents / 100).toFixed(2).replace('.', ',');
  await admin.from('porteiro_entrada').insert({
    origem: 'cobrar-diferenca-peso',
    nivel: 'URGENTE',
    texto: `Peso variável: não deu para cobrar ${euros} € no cartão do pedido ${orderId.slice(0, 8)} ` +
      `(${motivo}). A Bora assume a diferença. Ver Operação do dia → Ajustes de peso.`,
  });
  await admin.from('e2e_log').insert({
    fluxo: 'cobrar-diferenca-peso', passo: 'bora_assume', estado: 'aviso',
    detalhe: `pedido ${orderId} ${amountCents} cent: ${motivo}`, device: 'edge',
  });
}

/** Grava o resultado do ensaio (tabela própria, nunca orders) e o passo no e2e_log. */
async function gravarEnsaio(admin: Admin, linha: LinhaEnsaio, pedidoPor: string | null) {
  const { error } = await admin.from('ensaio_peso_cartao').insert({ ...linha, pedido_por: pedidoPor });
  if (error) console.error('[cobrar-diferenca-peso] ensaio_peso_cartao insert:', error.message);
  await admin.from('e2e_log').insert({
    fluxo: 'cobrar-diferenca-peso', passo: `ensaio_${linha.caso}`, estado: linha.estado,
    detalhe: `ensaio (modo de teste) ${linha.caso}: esperado ${linha.esperado}, deu ${linha.resultado ?? '—'}` +
      (linha.erro ? ` · ${linha.erro}` : '') + (error ? ` · NAO GRAVOU: ${error.message}` : ''),
    device: 'edge',
  });
}

/** MODO ENSAIO: só a chave de TESTE da empresa; nunca orders, nunca a chave real. */
async function ensaio(admin: Admin, caso: CasoEnsaio | null, pedidoPor: string | null): Promise<Response> {
  if (!caso) return json({ ok: false, error: 'caso_invalido' }, 400);
  const chave = (Deno.env.get(NOME_CHAVE_TESTE) ?? '').trim();
  const estado = estadoChaveDeTeste(chave);
  if (estado !== 'ok') {
    const erro = estado === 'falta' ? 'falta_chave_teste' : 'chave_nao_e_de_teste';
    const mensagem = estado === 'falta' ? MENSAGEM_FALTA_CHAVE : MENSAGEM_NAO_E_TESTE;
    await gravarEnsaio(admin, linhaDeErro(caso, erro, { mensagem }), pedidoPor);
    return json({ ok: false, error: erro, mensagem });
  }
  const stripeTeste = new Stripe(chave, { apiVersion: '2023-10-16', httpClient: Stripe.createFetchHttpClient() });
  const linha = await correrEnsaio(stripeTeste as unknown as StripeEnsaio, caso, crypto.randomUUID());
  await gravarEnsaio(admin, linha, pedidoPor);
  return json({ ok: linha.estado === 'ok', ...linha });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  const negado = await exigirServidor(req, corsHeaders);
  if (negado) return negado;
  const ping = await respostaAoPing(req, corsHeaders);
  if (ping) return ping;

  const admin = createClient(supabaseUrl, secretKey() ?? '', { auth: { persistSession: false } });

  // deno-lint-ignore no-explicit-any
  let body: any = null;
  try { body = await req.json(); } catch { /* corpo inválido */ }

  // MODO ENSAIO (10/11/2026): antes do interruptor — prova-se com ele desligado.
  const pedidoEnsaio = lerPedidoDeEnsaio(body);
  if (pedidoEnsaio.ensaio) return await ensaio(admin, pedidoEnsaio.caso, pedidoEnsaio.pedidoPor);

  const orderId = typeof body?.order_id === 'string' ? body.order_id : '';
  const amountCents = Number.isInteger(body?.amount_cents) ? body.amount_cents as number : -1;
  if (!orderId || amountCents < 1 || amountCents > MAX_CENTS) {
    return json({ ok: false, error: 'pedido_invalido' }, 400);
  }

  if (!(await interruptorLigado(admin))) {
    return json({ ok: false, error: 'desligado', note: 'weight_adjust_card_charge_enabled=false: nada cobrado' });
  }

  const { data: o, error: oe } = await admin.from('orders')
    .select('id, user_id, payment_method, payment_intent_id, is_purchase_finalized, extra_charge_amount, extra_charge_settled_at, final_total, status, stripe_account')
    .eq('id', orderId).maybeSingle();
  if (oe || !o) return json({ ok: false, error: 'pedido_nao_encontrado' }, 404);
  if (o.extra_charge_settled_at) return json({ ok: true, note: 'ja_acertado' });
  if (!['card', 'stripe'].includes(String(o.payment_method))) {
    return json({ ok: false, error: 'nao_e_cartao' }, 400);
  }
  if (o.is_purchase_finalized !== true) return json({ ok: false, error: 'compra_por_fechar' }, 400);
  if (['cancelled', 'rejected'].includes(String(o.status))) return json({ ok: false, error: 'pedido_fechado' }, 400);
  const gravado = Math.round(Number(o.extra_charge_amount ?? 0) * 100);
  if (gravado !== amountCents) {
    return json({ ok: false, error: 'valor_diferente_do_talao', gravado_cents: gravado }, 400);
  }

  // duas contas: a Stripe da conta onde o pedido foi pago (sem chave = a Bora assume, como sem cartão)
  let stripe: Stripe;
  let conta = 'pessoal';
  try {
    ({ stripe, conta } = stripeDaLinha(o));
  } catch (e) {
    await boraAssume(admin, orderId, `sem chave Stripe da conta ${o.stripe_account ?? 'pessoal'}: ${String(e)}`, amountCents);
    return json({ ok: false, error: 'sem_chave_stripe', settled_via: 'bora_assume' });
  }
  // Cartão e Customer do pagamento original + cobrança off_session: _shared/peso_cartao.ts
  // (o mesmo código que o ensaio prova). Sem cartão / não confirmado / recusado → a Bora assume.
  const r = await cobrarDiferencaNoCartao(stripe as unknown as StripePeso, {
    piOriginal: o.payment_intent_id ? String(o.payment_intent_id) : null,
    amountCents, orderId, conta,
  });
  if (!r.ok) {
    await boraAssume(admin, orderId, r.motivo, amountCents);
    return json({ ok: false, error: r.erro, ...(r.status ? { status: r.status } : {}), settled_via: 'bora_assume' });
  }

  // Cobrado (a Stripe disse succeeded). Daqui para baixo nada pode virar "a Bora assume": se o
  // banco falhar, fica registado para o admin acertar e a cobrança não se repete (idempotência).
  try {
    const pi = { id: r.piId };
    const novoTotal = Math.round((Number(o.final_total ?? 0) * 100) + amountCents) / 100;
    const agora = new Date().toISOString();
    const { error: ue } = await admin.from('orders').update({
      final_total: novoTotal,
      extra_charge_settled_at: agora,
      extra_charge_settled_via: 'cartao_peso',
    }).eq('id', orderId).is('extra_charge_settled_at', null);
    if (ue) {
      // Cobrado na Stripe mas o pedido não gravou: não se repete a cobrança (idempotência);
      // fica registado para o admin acertar.
      await admin.from('e2e_log').insert({
        fluxo: 'cobrar-diferenca-peso', passo: 'gravar_pedido', estado: 'erro',
        detalhe: `pedido ${orderId} cobrado ${pi.id} mas update falhou: ${ue.message}`, device: 'edge',
      });
    }
    await admin.from('order_weight_adjustments')
      .update({ settled_via: 'cartao_cobrado', settled_at: agora })
      .eq('order_id', orderId).eq('settled_via', 'cartao_pendente');
    if (o.user_id) {
      const euros = (amountCents / 100).toFixed(2).replace('.', ',');
      await admin.rpc('_push_in_app_notification', {
        p_user_id: o.user_id,
        p_kind: 'order_weight_adjusted',
        p_title: 'Diferença de peso cobrada',
        p_body: `Cobrámos ${euros} € no teu cartão: os produtos ao quilo pesaram mais do que o previsto.`,
        p_related_id: orderId,
      });
    }
    return json({ ok: true, payment_intent_id: pi.id, amount_cents: amountCents });
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    try {
      await admin.from('e2e_log').insert({
        fluxo: 'cobrar-diferenca-peso', passo: 'gravar_pedido', estado: 'erro',
        detalhe: `pedido ${orderId} cobrado ${r.piId} mas a gravação falhou: ${m.slice(0, 300)}`, device: 'edge',
      });
    } catch (_) { /* nada a fazer */ }
    return json({ ok: true, payment_intent_id: r.piId, amount_cents: amountCents, aviso: 'cobrado_mas_gravacao_falhou' });
  }
});
