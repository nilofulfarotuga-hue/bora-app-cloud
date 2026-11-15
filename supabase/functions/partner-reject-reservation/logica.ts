// supabase/functions/partner-reject-reservation/logica.ts
//
// fechar-tudo-15-11 (15/11/2026; "Autorizo tudo" do Danilo às 15:15, passado pela Claude.ai às
// 15:21). O PARCEIRO rejeita uma reserva que o cliente JÁ PAGOU (pré-pagamento de 3 €) e a Bora
// devolve o dinheiro. Até aqui a RPC partner_decide_reservation punha a reserva em
// 'rejected_refunded' e avisava o cliente "Reembolso em curso", mas nada era devolvido na Stripe.
//
// Espelha admin-cancel-reservation: RPC primeiro (muda o estado e avisa o cliente), depois
// stripe.refunds.create com chave de idempotência, depois admin_audit_log. Diferenças, de propósito:
//  1. Quem chama tem de ser o dono do restaurante (restaurants.user_, a mesma regra da RPC),
//     verificado aqui no servidor antes de tudo — também numa nova tentativa.
//  2. Novas tentativas são seguras. Reserva já 'rejected_refunded' (a 1.ª chamada rejeitou mas a
//     resposta perdeu-se, ou a devolução falhou): a RPC não se chama outra vez e só se devolve o
//     que ainda faltar. A chave reserva-recusa-<id> impede a Stripe de devolver duas vezes.
//  3. O pagamento e o valor vêm da Stripe, não das colunas da reserva: a RLS
//     reservations_client_owner deixa o CLIENTE alterar prepayment_pi e prepayment_cents da
//     própria reserva. Só conta o pagamento com metadata.purpose='reservation_prepayment' e
//     metadata.reservation_id = esta reserva (gravados pelo servidor ao criar o pagamento), e
//     devolve-se no máximo o que esse pagamento recebeu, menos o que já foi devolvido.
//  4. Se a devolução não sair, a equipa é avisada no painel (notify_admin_event): o parceiro
//     não tem como a refazer.
//
// Sem rede: o index.ts liga isto ao Supabase e à Stripe; o logica_test.ts usa falsos.

export const ESTADO_PENDENTE = 'pending';
export const ESTADO_REJEITADA = 'rejected_refunded';
/** "Já rejeitada": o estado de hoje e o antigo (o admin também trata 'rejected' como final). */
export const ESTADOS_JA_REJEITADA: readonly string[] = [ESTADO_REJEITADA, 'rejected'];
export const PROPOSITO_PREPAGAMENTO = 'reservation_prepayment';
export const MOTIVO_MAX = 500;
export const ACAO_REGISTO = 'reservation_partner_reject_complete';
export const TIPO_AVISO = 'reservation_refund_failed';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Devoluções que contam como feitas ou a caminho ('failed' e 'canceled' não contam). */
const DEVOLUCAO_CONTA = new Set(['succeeded', 'pending', 'requires_action']);

export type ResultadoDevolucao =
  | 'succeeded' // devolução pedida agora à Stripe
  | 'already_refunded' // já não havia nada por devolver (nova tentativa)
  | 'not_applicable' // reserva sem pré-pagamento
  | 'not_paid' // o pagamento nunca foi cobrado: nada a devolver
  | 'failed'; // não saiu: a equipa é avisada e trata

export interface Reserva {
  id: string;
  restaurant_id: string;
  status: string;
  prepayment_pi: string | null;
  prepayment_cents: number | null;
  stripe_account?: string | null;
}

export interface PagamentoStripe {
  id: string;
  status: string;
  amount_received?: number | null;
  metadata?: Record<string, string> | null;
}

export interface DevolucaoStripe {
  id: string;
  amount: number;
  status?: string | null;
}

/** A conta Stripe onde a reserva foi paga (reservations.stripe_account). */
export interface StripeDaReserva {
  conta: string;
  lerPagamento(pi: string): Promise<PagamentoStripe>;
  listarDevolucoes(pi: string): Promise<DevolucaoStripe[]>;
  devolver(
    pi: string,
    cents: number,
    chaveIdempotencia: string,
    metadata: Record<string, string>,
  ): Promise<DevolucaoStripe>;
}

export interface AvisoEquipa {
  reservaId: string;
  resumo: string;
  detalhes: Record<string, unknown>;
}

export type FimDaRpc = { ok: true; status: string } | { ok: false; mensagem: string };

export interface Dependencias {
  /** Utilizador do token, confirmado no Auth; null = sem sessão válida. */
  utilizador(): Promise<{ id: string } | null>;
  /** Linha da reserva, lida com a chave do servidor. */
  lerReserva(id: string): Promise<Reserva | null>;
  /** O utilizador é o dono do restaurante (restaurants.user_)? */
  eDono(restaurantId: string, userId: string): Promise<boolean>;
  /** partner_decide_reservation(p_accept=false) com o token de quem chama. */
  rejeitarPelaRpc(id: string, motivo: string | null): Promise<FimDaRpc>;
  /** Cliente Stripe da conta onde a reserva foi paga (pode lançar: chave em falta). */
  stripe(reserva: Reserva): StripeDaReserva;
  registar(linha: Record<string, unknown>): Promise<void>;
  avisarEquipa(aviso: AvisoEquipa): Promise<void>;
}

export interface Resposta {
  status: number;
  body: Record<string, unknown>;
}

export interface Devolucao {
  resultado: ResultadoDevolucao;
  /** Devolvido agora (succeeded) ou já devolvido antes (already_refunded); senão 0. */
  cents: number;
  conta: string | null;
  refundId: string | null;
  /** Porquê, para o registo: no_payment_intent, pi_mismatch, payment_processing, stripe_error… */
  motivo: string | null;
  /** Mensagem da Stripe, só para o registo (nunca vai para a app do parceiro). */
  erro: string | null;
}

function inteiro(v: unknown): number {
  return Math.trunc(Number(v ?? 0)) || 0;
}

/** Corpo do pedido: { reservation_id: uuid, reason?: texto }. */
export function lerPedido(
  body: unknown,
): { reservationId: string; motivo: string | null } | { erro: string } {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return { erro: 'invalid_body' };
  const b = body as Record<string, unknown>;
  const id = typeof b.reservation_id === 'string' ? b.reservation_id.trim() : '';
  if (!UUID_RE.test(id)) return { erro: 'invalid_reservation_id' };
  const motivo = typeof b.reason === 'string' ? b.reason.trim().slice(0, MOTIVO_MAX).trim() : '';
  return { reservationId: id.toLowerCase(), motivo: motivo || null };
}

/** A chave pedida pela Claude.ai: a mesma reserva nunca gera duas devoluções na Stripe. */
export function chaveIdempotencia(reservaId: string): string {
  return `reserva-recusa-${reservaId}`;
}

/** Erro da RPC partner_decide_reservation → código HTTP e código para a app. */
export function erroDaRpc(mensagem: string): { http: number; error: string } {
  const m = String(mensagem ?? '');
  if (m.startsWith('reservation_not_pending')) return { http: 409, error: 'reservation_not_pending' };
  if (m.startsWith('reservation_not_found')) return { http: 404, error: 'reservation_not_found' };
  if (m.startsWith('not_your_restaurant')) return { http: 403, error: 'not_your_restaurant' };
  if (m.startsWith('auth_required')) return { http: 401, error: 'auth_required' };
  if (m.includes('convidado_sem_conta')) return { http: 403, error: 'convidado_sem_conta' };
  return { http: 500, error: 'rpc_error' };
}

/** O pagamento é mesmo o pré-pagamento DESTA reserva, e foi cobrado? */
export function validarPagamento(
  reservaId: string,
  pi: PagamentoStripe,
): 'ok' | 'pi_mismatch' | 'payment_processing' | 'not_paid' {
  const md = pi.metadata ?? {};
  if (md.purpose !== PROPOSITO_PREPAGAMENTO || md.reservation_id !== reservaId) return 'pi_mismatch';
  if (pi.status === 'processing') return 'payment_processing';
  if (pi.status !== 'succeeded' || inteiro(pi.amount_received) <= 0) return 'not_paid';
  return 'ok';
}

/** Quanto falta devolver: o que o pagamento recebeu menos as devoluções feitas ou a caminho. */
export function centsPorDevolver(
  pi: PagamentoStripe,
  devolucoes: DevolucaoStripe[],
): { recebido: number; jaDevolvido: number; falta: number } {
  const recebido = Math.max(0, inteiro(pi.amount_received));
  const jaDevolvido = devolucoes
    .filter((d) => DEVOLUCAO_CONTA.has(String(d.status ?? '')))
    .reduce((soma, d) => soma + Math.max(0, inteiro(d.amount)), 0);
  return { recebido, jaDevolvido, falta: Math.max(0, recebido - jaDevolvido) };
}

/** Devolve o pré-pagamento da reserva. Nunca lança: o que falhar volta em `resultado`. */
export async function devolverPrePagamento(
  reserva: Reserva,
  deps: Pick<Dependencias, 'stripe'>,
): Promise<Devolucao> {
  const base: Devolucao = {
    resultado: 'not_applicable',
    cents: 0,
    conta: null,
    refundId: null,
    motivo: null,
    erro: null,
  };
  const pi = String(reserva.prepayment_pi ?? '').trim();
  if (!pi) {
    // Como no admin ('no_payment_intent'): sem pagamento na Stripe não há o que devolver aqui.
    // Se a reserva diz que houve pré-pagamento, a equipa tem de ver.
    return inteiro(reserva.prepayment_cents) > 0
      ? { ...base, resultado: 'failed', motivo: 'no_payment_intent' }
      : base;
  }
  let conta: string | null = null;
  try {
    const s = deps.stripe(reserva);
    conta = s.conta;
    const pagamento = await s.lerPagamento(pi);
    const valido = validarPagamento(reserva.id, pagamento);
    if (valido === 'pi_mismatch' || valido === 'payment_processing') {
      return { ...base, conta, resultado: 'failed', motivo: valido };
    }
    if (valido === 'not_paid') {
      return { ...base, conta, resultado: 'not_paid', motivo: `pi_${pagamento.status}` };
    }
    const { jaDevolvido, falta } = centsPorDevolver(pagamento, await s.listarDevolucoes(pi));
    if (falta <= 0) {
      return { ...base, conta, resultado: 'already_refunded', cents: jaDevolvido };
    }
    const refund = await s.devolver(pi, falta, chaveIdempotencia(reserva.id), {
      purpose: 'reservation_partner_reject',
      reservation_id: reserva.id,
    });
    if (refund.status === 'failed' || refund.status === 'canceled') {
      return { ...base, conta, resultado: 'failed', motivo: `refund_${refund.status}`, refundId: refund.id };
    }
    return { ...base, conta, resultado: 'succeeded', cents: falta, refundId: refund.id };
  } catch (e) {
    return {
      ...base,
      conta,
      resultado: 'failed',
      motivo: 'stripe_error',
      erro: e instanceof Error ? e.message : String(e),
    };
  }
}

/** Linha do admin_audit_log, com os mesmos campos do admin-cancel-reservation e os do parceiro. */
export function linhaDeRegisto(a: {
  reserva: Reserva;
  parceiroId: string;
  idempotente: boolean;
  motivo: string | null;
  novoEstado: string;
  devolucao: Devolucao;
}): Record<string, unknown> {
  const d = a.devolucao;
  return {
    admin_id: null, // quem decidiu foi o parceiro, não um admin (como o 'sistema:' do delete-account)
    admin_email: 'parceiro:partner-reject-reservation',
    action: ACAO_REGISTO,
    entity_type: 'reservation',
    entity_id: a.reserva.id,
    details: {
      partner_user_id: a.parceiroId,
      restaurant_id: a.reserva.restaurant_id,
      new_status: a.novoEstado,
      idempotent: a.idempotente,
      refund_result: d.resultado,
      refund_reason: d.motivo,
      stripe_account: d.conta,
      refund_id: d.refundId,
      refund_amount: d.cents / 100,
      stripe_error: d.erro,
      prepayment_cents: inteiro(a.reserva.prepayment_cents),
      prepayment_pi: a.reserva.prepayment_pi,
      reason: a.motivo,
    },
  };
}

export function euros(cents: number): string {
  return `${(cents / 100).toFixed(2).replace('.', ',')} €`;
}

/** O que o admin precisa de fazer, em PT-BR, conforme o motivo. */
const PISTA_PARA_A_EQUIPA: Record<string, string> = {
  pi_mismatch:
    'o pagamento gravado na reserva não é o desta reserva (pode ter sido alterado); conferir antes de reembolsar',
  no_payment_intent: 'a reserva não tem pagamento gravado; conferir se o cliente pagou',
  payment_processing: 'o pagamento ainda está em processamento; reembolsar quando concluir',
};

/** Aviso no painel quando a devolução não saiu: o parceiro não a consegue refazer. */
export function avisoDeFalha(reserva: Reserva, d: Devolucao): AvisoEquipa {
  const cents = d.cents > 0 ? d.cents : inteiro(reserva.prepayment_cents);
  const pista = PISTA_PARA_A_EQUIPA[d.motivo ?? ''] ?? 'reembolsar pelo painel de pagamentos';
  return {
    reservaId: reserva.id,
    resumo: `Reserva #${reserva.id.slice(0, 8)}: o parceiro recusou e o reembolso de ${euros(cents)} ` +
      `ao cliente não foi feito — ${pista}.`,
    detalhes: {
      restaurant_id: reserva.restaurant_id,
      motivo: d.motivo,
      stripe_account: d.conta,
      stripe_error: d.erro,
      prepayment_pi: reserva.prepayment_pi,
      prepayment_cents: inteiro(reserva.prepayment_cents),
    },
  };
}

/** O pedido inteiro, do corpo à resposta. */
export async function tratar(body: unknown, deps: Dependencias): Promise<Resposta> {
  const pedido = lerPedido(body);
  if ('erro' in pedido) return { status: 400, body: { error: pedido.erro } };

  const quem = await deps.utilizador();
  if (!quem) return { status: 401, body: { error: 'unauthorized' } };

  let reserva = await deps.lerReserva(pedido.reservationId);
  if (!reserva) return { status: 404, body: { error: 'reservation_not_found' } };

  // 1. Só o dono do restaurante (a regra da RPC), verificado aqui antes de tudo.
  if (!(await deps.eDono(reserva.restaurant_id, quem.id))) {
    return { status: 403, body: { error: 'not_your_restaurant' } };
  }

  // 2. Estado: a RPC de sempre rejeita e avisa o cliente; numa nova tentativa não se repete.
  let idempotente = false;
  let novoEstado = reserva.status;
  if (reserva.status === ESTADO_PENDENTE) {
    const fim = await deps.rejeitarPelaRpc(reserva.id, pedido.motivo);
    if (fim.ok) {
      novoEstado = fim.status || ESTADO_REJEITADA;
    } else {
      const e = erroDaRpc(fim.mensagem);
      if (e.error !== 'reservation_not_pending') {
        return { status: e.http, body: { error: e.error, detail: fim.mensagem } };
      }
      // Corrida com outra chamada: se ela rejeitou, segue como nova tentativa.
      const agora = await deps.lerReserva(reserva.id);
      if (!agora || !ESTADOS_JA_REJEITADA.includes(agora.status)) {
        return { status: 409, body: { error: 'reservation_not_pending', status: agora?.status ?? null } };
      }
      reserva = agora;
      novoEstado = agora.status;
      idempotente = true;
    }
  } else if (ESTADOS_JA_REJEITADA.includes(reserva.status)) {
    idempotente = true; // nova tentativa: a RPC já correu
  } else {
    return { status: 409, body: { error: 'reservation_not_pending', status: reserva.status } };
  }

  // 3. Dinheiro. Nunca lança: o que falhar fica registado e a equipa é avisada.
  const devolucao = await devolverPrePagamento(reserva, deps);

  // 4. Registo, como no admin-cancel-reservation, e aviso à equipa se a devolução não saiu.
  try {
    await deps.registar(linhaDeRegisto({
      reserva,
      parceiroId: quem.id,
      idempotente,
      motivo: pedido.motivo,
      novoEstado,
      devolucao,
    }));
  } catch (e) {
    console.error('[partner-reject-reservation] registo falhou:', e);
  }
  if (devolucao.resultado === 'failed') {
    try {
      await deps.avisarEquipa(avisoDeFalha(reserva, devolucao));
    } catch (e) {
      console.error('[partner-reject-reservation] aviso à equipa falhou:', e);
    }
  }

  return {
    status: 200,
    body: {
      success: true,
      idempotent: idempotente,
      reservation_id: reserva.id,
      new_status: novoEstado,
      refund: {
        result: devolucao.resultado,
        amount_cents: devolucao.cents,
        amount: devolucao.cents / 100,
      },
    },
  };
}
