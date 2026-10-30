// supabase/functions/_shared/gorjeta_devolver.ts — missão gorjetas-taxa-2026-10-30 (Bloco B)
//
// Regra do Danilo (30/10/2026): pedido cancelado ou rejeitado antes da entrega → a gorjeta volta
// INTEIRA ao cliente, fora de qualquer taxa de cancelamento, pelo mesmo caminho e com a mesma
// escolha que o resto do reembolso (cartão/MB Way ou saldo Bora — regra de 29/10).
//
//   • Gorjeta do carrinho no MESMO pagamento (tips.cobrada_junto): reembolso do PI do pedido no valor
//     EXATO da gorjeta (o reembolso da compra já não a conta: _shared/cobranca_stripe.ts v3).
//   • Gorjeta à parte (apps antigas, pedidos pagos só com saldo, gorjeta depois): reembolso do PI dela.
//   • Destino 'carteira' (o cliente escolheu o saldo Bora): wallet_credit_refund_split com chave
//     própria 'gorjeta_<id>' (100% saldo, wallet_split_free_pct = 1; nunca credita duas vezes).
//   • Gorjeta ainda por pagar SEM pagamento criado → 'cancelled'. COM pagamento criado (MB Way à espera
//     do webhook, ou à parte): pergunta-se à Stripe — pago → marca-se paga e devolve-se (uma vez);
//     ainda à espera do cliente → fica (a conferência volta a perguntar); morto → 'cancelled'.
//
// Nunca devolve duas vezes: (1) cada gorjeta é RESERVADA (succeeded → refunded) antes de mexer no
// dinheiro; (2) antes de pedir um reembolso à Stripe, procura um reembolso desse PI com
// metadata.tip_id = esta gorjeta (uma falha de rede pode ter deixado um feito); (3) o valor é SEMPRE a
// gorjeta inteira — se a Stripe já não tem disponível para isso, não se devolve meia gorjeta: erro e
// aviso ao admin. Se falhar, volta a 'succeeded' e soma tips.devolucao_tentativas; à 2.ª falha avisa o
// admin UMA vez e a conferência de 15 em 15 min deixa de tentar (fica para o painel).

// deno-lint-ignore no-explicit-any
type Cliente = any;

export type DestinoGorjeta = 'meio' | 'carteira';

export interface GorjetaParaDevolver {
  id: string;
  order_id: string | null;
  tvde_ride_id: string | null;
  client_user_id: string;
  amount_cents: number;
  method: string;
  moment?: string;
  status: string;
  stripe_payment_intent_id: string | null;
  cobrada_junto: boolean | null;
  failure_reason: string | null;
  devolucao_tentativas?: number | null;
}

export interface GorjetaTratada {
  tipId: string;
  acao: string;
  cents: number;
  erro?: string;
}

export interface ResultadoGorjetas {
  devolvidaCents: number;
  meioCents: number;
  carteiraCents: number;
  itens: GorjetaTratada[];
  erros: number;
}

export const COLUNAS_GORJETA =
  'id, order_id, tvde_ride_id, client_user_id, amount_cents, method, moment, status, stripe_payment_intent_id, cobrada_junto, failure_reason, devolucao_tentativas';

/**
 * charge-tip `create` (moment checkout): a gorjeta do carrinho já foi no pagamento do cartão?
 * Pedido que EXISTE: só se o rascunho do PI DESTE pedido trouxer a gorjeta (ex.: "tentou cartão,
 * desistiu e pagou com saldo" → o pedido não tem esse PI → cobra-se à parte). Pedido que ainda NÃO
 * existe (o webhook ainda o está a criar): vale um rascunho recente do cliente com a gorjeta e ainda por usar.
 */
export function gorjetaJaVaiNoCartao(c: {
  pedidoExiste: boolean; rascunhoDoPiDoPedidoComGorjeta: boolean; rascunhoRecentePorUsarComGorjeta: boolean;
}): boolean {
  return c.pedidoExiste ? c.rascunhoDoPiDoPedidoComGorjeta : c.rascunhoRecentePorUsarComGorjeta;
}

// deno-lint-ignore no-explicit-any
async function stripe(key: string, metodo: 'GET' | 'POST', caminho: string, campos?: Record<string, string>, idem?: string): Promise<any> {
  const headers: Record<string, string> = { Authorization: `Bearer ${key}` };
  let body: string | undefined;
  if (metodo === 'POST') {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    if (idem) headers['Idempotency-Key'] = idem;
    body = new URLSearchParams(campos ?? {}).toString();
  }
  const res = await fetch(`https://api.stripe.com${caminho}`, { method: metodo, headers, body, signal: AbortSignal.timeout(15000) });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`stripe_${res.status}: ${String(j?.error?.message ?? '').slice(0, 200)}`);
  return j;
}

class DevolucaoImpossivel extends Error {}

async function avisarAdmin(admin: Cliente, tip: GorjetaParaDevolver, msg: string): Promise<void> {
  try {
    await admin.rpc('notify_admin_event', {
      p_event_type: 'tip_refund_failed', p_severity: 'critical',
      p_summary: `Gorjeta de €${(tip.amount_cents / 100).toFixed(2)} do pedido #${String(tip.order_id ?? '').slice(0, 8)} não voltou ao cliente: ${msg}`.slice(0, 300),
      p_entity_type: 'order', p_entity_id: String(tip.order_id ?? ''), p_payload: { tip_id: tip.id },
      p_deep_link: '/admin/gorjetas',
    });
  } catch (_) { /* o aviso é extra */ }
}

/** Devolve UMA gorjeta paga (status succeeded), inteira. Reserva primeiro; desfaz a reserva se falhar. */
export async function devolverUmaGorjeta(
  admin: Cliente, stripeKey: string, tip: GorjetaParaDevolver, destino: DestinoGorjeta,
  motivo: string, quem: string | null = null,
): Promise<GorjetaTratada> {
  const onde = destino === 'carteira' ? 'para o saldo Bora' : 'ao cartão/MB Way';
  const { data: reservada, error: rErr } = await admin.from('tips').update({
    status: 'refunded', refunded_at: new Date().toISOString(), refunded_by: quem,
    refund_reason: `${motivo} (${onde})`.slice(0, 300), devolvida_para: destino,
  }).eq('id', tip.id).eq('status', 'succeeded').select('id');
  if (rErr) return { tipId: tip.id, acao: 'erro', cents: 0, erro: rErr.message };
  if (!reservada || reservada.length === 0) return { tipId: tip.id, acao: 'ja_tratada', cents: 0 };

  try {
    if (destino === 'carteira') {
      const { data: w, error } = await admin.rpc('wallet_credit_refund_split', {
        p_order_id: String(tip.order_id ?? tip.tvde_ride_id ?? tip.id),
        p_user_id: tip.client_user_id,
        p_total_cents: tip.amount_cents,
        p_reason: `Gorjeta devolvida: ${motivo}`.slice(0, 200),
        p_idempotency_key: `gorjeta_${tip.id}`,
      });
      if (error) throw new Error(`saldo: ${error.message}`);
      return { tipId: tip.id, acao: w?.already_applied ? 'carteira_ja_feita' : 'carteira', cents: w?.already_applied ? 0 : tip.amount_cents };
    }
    if (!tip.stripe_payment_intent_id) throw new DevolucaoImpossivel('gorjeta_sem_pagamento_na_stripe');
    if (!stripeKey) throw new Error('stripe_key_em_falta');
    const pi = encodeURIComponent(tip.stripe_payment_intent_id);
    // (2) Já há um reembolso desta gorjeta na Stripe (ex.: a resposta perdeu-se na rede)? Não se repete.
    const lista = await stripe(stripeKey, 'GET', `/v1/refunds?payment_intent=${pi}&limit=100`);
    // deno-lint-ignore no-explicit-any
    const feito = (lista?.data ?? []).find((r: any) => r?.metadata?.tip_id === tip.id && !['failed', 'canceled'].includes(String(r?.status)));
    if (feito) return { tipId: tip.id, acao: `meio_ja_feito:${feito.id}`, cents: 0 };
    // (3) Sempre a gorjeta inteira; sem disponível para isso → não se devolve meia gorjeta.
    const p = await stripe(stripeKey, 'GET', `/v1/payment_intents/${pi}?expand[]=latest_charge`);
    if (p.status !== 'succeeded') throw new Error(`pi_${p.status}`);
    const disponivel = Math.max(0, Number(p.amount_received ?? 0) - Number(p.latest_charge?.amount_refunded ?? 0));
    if (disponivel < tip.amount_cents) {
      throw new DevolucaoImpossivel(`a Stripe só tem ${disponivel} cêntimos por devolver neste pagamento (gorjeta ${tip.amount_cents})`);
    }
    const r = await stripe(stripeKey, 'POST', '/v1/refunds', {
      payment_intent: tip.stripe_payment_intent_id,
      amount: String(tip.amount_cents),
      'metadata[kind]': 'tip',
      'metadata[tip_id]': tip.id,
    }, `gorjeta-devolver-${tip.id}`);
    return { tipId: tip.id, acao: `meio:${r.id}`, cents: tip.amount_cents };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    // Repetir não resolve (sem pagamento / sem disponível) → pára já: conta como 2.ª tentativa.
    const anteriores = Math.max(0, Number(tip.devolucao_tentativas ?? 0));
    const n = e instanceof DevolucaoImpossivel ? Math.max(2, anteriores + 1) : anteriores + 1;
    await admin.from('tips').update({
      status: 'succeeded', refunded_at: null, refunded_by: null, refund_reason: null, devolvida_para: null,
      devolucao_tentativas: n,
      failure_reason: `devolução falhou (tentativa ${n}): ${msg}`.slice(0, 300),
    }).eq('id', tip.id).eq('status', 'refunded');
    // Avisa UMA vez: quando passa a 2 (a conferência deixa de tentar a partir daí).
    if (anteriores < 2 && n >= 2) await avisarAdmin(admin, tip, msg);
    return { tipId: tip.id, acao: 'erro', cents: 0, erro: msg };
  }
}

/** Gorjeta por pagar: pergunta à Stripe pelo PI (se houver) e diz o que fazer. */
async function gorjetaPorPagar(
  admin: Cliente, stripeKey: string, t: GorjetaParaDevolver,
): Promise<'paga' | 'a_espera' | 'cancelada'> {
  if (t.stripe_payment_intent_id && stripeKey) {
    const pid = encodeURIComponent(t.stripe_payment_intent_id);
    const pi = await stripe(stripeKey, 'GET', `/v1/payment_intents/${pid}`);
    const st = String(pi.status);
    if (st === 'succeeded') {
      // O pagamento entrou (ex.: MB Way aprovado e o pedido cancelado antes do webhook): fica paga
      // para se devolver inteira, uma vez.
      await admin.from('tips').update({ status: 'succeeded', paid_at: new Date().toISOString(), failure_reason: null })
        .eq('id', t.id).in('status', ['pending', 'requires_action', 'cancelled', 'failed']);
      return 'paga';
    }
    if (st === 'processing') return 'a_espera'; // MB Way à espera da aprovação do cliente
    if (!t.cobrada_junto && ['requires_payment_method', 'requires_confirmation', 'requires_action'].includes(st)) {
      // À parte e à espera do cliente: cancela-se na Stripe para não cobrar depois.
      await stripe(stripeKey, 'POST', `/v1/payment_intents/${pid}/cancel`, {}, `gorjeta-cancelar-${t.id}`);
    } else if (t.cobrada_junto && st === 'requires_action') {
      return 'a_espera'; // pagamento do pedido ainda à espera do cliente
    }
  }
  await admin.from('tips').update({ status: 'cancelled', failure_reason: 'pedido cancelado antes de a gorjeta ser paga' })
    .eq('id', t.id).in('status', ['pending', 'requires_action']);
  return 'cancelada';
}

/**
 * Devolve todas as gorjetas de um pedido cancelado/rejeitado. Chamar DEPOIS do reembolso da compra.
 * Nunca lança: devolve o resumo (o cancelamento do pedido não pode falhar por causa da gorjeta).
 */
export async function devolverGorjetasDoPedido(
  admin: Cliente, stripeKey: string, orderId: string, destino: DestinoGorjeta,
  motivo: string, quem: string | null = null,
): Promise<ResultadoGorjetas> {
  const out: ResultadoGorjetas = { devolvidaCents: 0, meioCents: 0, carteiraCents: 0, itens: [], erros: 0 };
  try {
    const { data: tips, error } = await admin.from('tips').select(COLUNAS_GORJETA)
      .eq('order_id', orderId).in('status', ['pending', 'requires_action', 'succeeded']);
    if (error) { out.erros++; out.itens.push({ tipId: '', acao: 'erro', cents: 0, erro: error.message }); return out; }
    for (const t0 of (tips ?? []) as GorjetaParaDevolver[]) {
      let t = t0;
      if (t.method !== 'card' && t.method !== 'mbway') continue; // dinheiro: o gatilho do banco cancela-a
      if (t.status !== 'succeeded') {
        let estado: 'paga' | 'a_espera' | 'cancelada';
        try { estado = await gorjetaPorPagar(admin, stripeKey, t); } catch (e) {
          out.erros++;
          out.itens.push({ tipId: t.id, acao: 'erro', cents: 0, erro: e instanceof Error ? e.message : String(e) });
          continue;
        }
        if (estado !== 'paga') { out.itens.push({ tipId: t.id, acao: estado, cents: 0 }); continue; }
        t = { ...t, status: 'succeeded' };
      }
      const r = await devolverUmaGorjeta(admin, stripeKey, t, destino, motivo, quem);
      out.itens.push(r);
      if (r.acao === 'erro') out.erros++;
      if (r.cents > 0) {
        out.devolvidaCents += r.cents;
        if (r.acao.startsWith('carteira')) out.carteiraCents += r.cents; else out.meioCents += r.cents;
      }
    }
  } catch (e) {
    out.erros++;
    out.itens.push({ tipId: '', acao: 'erro', cents: 0, erro: e instanceof Error ? e.message : String(e) });
  }
  return out;
}

/**
 * auto-refund-order: o reembolso TOTAL do PI do pedido já levou a gorjeta do carrinho cobrada junto.
 * Marca-a 'refunded' (sem novo reembolso). Só depois de a Stripe confirmar o reembolso total.
 */
export async function marcarGorjetaJuntoNoReembolsoTotal(
  admin: Cliente, orderId: string, piId: string, motivo: string,
): Promise<number> {
  const agora = new Date().toISOString();
  const { data, error } = await admin.from('tips').update({
    status: 'refunded', refunded_at: agora, devolvida_para: 'meio',
    refund_reason: `${motivo} (devolvida no reembolso total do pedido)`.slice(0, 300),
  }).eq('order_id', orderId).eq('cobrada_junto', true).eq('stripe_payment_intent_id', piId)
    .in('status', ['succeeded', 'pending', 'requires_action']).select('id');
  if (error) { console.error('[gorjeta_devolver] marcar gorjeta junto devolvida falhou:', error.message, orderId); return 0; }
  return (data ?? []).length;
}
