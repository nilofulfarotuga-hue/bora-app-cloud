// supabase/functions/admin-cancel-reservation/logica.ts
//
// fechar-tudo-15-11 (15/11/2026; "Autorizo tudo" do Danilo às 15:15, ordem da Claude.ai às 16:15).
// O ADMIN cancela uma reserva em nome do cliente; se faltar mais do que a janela (2 h), a Bora
// devolve o pré-pagamento na Stripe.
//
// O que muda em relação à v21 (no ar até hoje), de propósito:
//  1. O pagamento e o valor vêm da Stripe, não das colunas da reserva. A v21 devolvia
//     `prepayment_cents` ao `prepayment_pi` gravados na linha, colunas que o CLIENTE podia mudar
//     até hoje (RLS reservations_client_owner; o gatilho trg_00_reservas_campos_protegidos fechou
//     isso a 15/11, e o INSERT direto continua aberto). Agora só conta o PaymentIntent com
//     metadata.purpose='reservation_prepayment' e metadata.reservation_id = esta reserva (gravados
//     pelo servidor em create-reservation-payment-intent e create-mbway-reservation-payment-intent)
//     e 'succeeded'; devolve-se o que ele recebeu menos o que já foi devolvido (feito ou a caminho).
//     É a regra de partner-reject-reservation/logica.ts; o logica_test.ts confere que as duas
//     dizem o mesmo.
//  2. Nova tentativa segura: reserva já 'cancelled_refunded' (a RPC responde idempotent=true) →
//     não se cancela outra vez, só se devolve o que ainda faltar. A v21 saía logo ("no action
//     taken") e uma devolução que tivesse falhado nunca mais era tentada por aqui.
//  3. Se a devolução não sair, a equipa é avisada no painel E no telemóvel
//     (notify_admin_urgent_push: linha no painel + push urgente).
//  4. Revisão do Juiz da Claude.ai (15/11, 17:2x) — chave de idempotência POR TENTATIVA:
//     admin-cancel-rsv-<id>-<n.º de devoluções que a Stripe já lista para o pagamento>. Com a
//     chave fixa da v21, uma devolução que saiu 'failed'/'canceled' e era tentada de novo em
//     24 h com o mesmo valor recebia da Stripe a resposta GUARDADA da 1.ª ('succeeded') e o
//     painel dizia "devolvido" sem dinheiro nenhum a mexer. Agora a tentativa seguinte já vê a
//     falhada na lista, usa outra chave e cria uma devolução NOVA. Se mesmo assim a Stripe
//     responder com uma devolução que já estava na lista, é uma resposta repetida: vale o estado
//     da lista e nada saiu agora (resultado failed, a equipa vê).
//  5. Erro ao criar a devolução: relê-se a lista antes de dar o alarme. Se já não falta nada
//     (saiu e só a resposta se perdeu), é already_refunded e ninguém é avisado à toa.
// Igual à v21: só admin (app_metadata.role='admin'); a RPC admin_cancel_reservation_on_behalf_of
// muda o estado, avisa o cliente e regista a ação; conta Stripe onde o pré-pagamento entrou
// (reservations.stripe_account); linha 'reservation_cancel_complete' no admin_audit_log;
// códigos HTTP e corpos das respostas (só se acrescentam campos: refund.amount_cents,
// refund.reason, refund.stripe_status).
//
// Sem rede: o index.ts liga isto ao Supabase e à Stripe; o logica_test.ts usa falsos.

export const PROPOSITO_PREPAGAMENTO = 'reservation_prepayment';
/** Estado em que a RPC já cancelou COM direito a devolução: numa nova chamada, devolve-se o que faltar. */
export const ESTADO_CANCELADA_COM_DEVOLUCAO = 'cancelled_refunded';
export const ACAO_REGISTO = 'reservation_cancel_complete';
export const TIPO_AVISO = 'reservation_refund_failed';
export const MENSAGEM_JA_CANCELADA = 'already cancelled — no action taken';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Devoluções que contam como feitas ou a caminho ('failed' e 'canceled' não contam). */
const DEVOLUCAO_CONTA = new Set(['succeeded', 'pending', 'requires_action']);

export type ResultadoDevolucao =
  | 'succeeded' // devolução pedida agora à Stripe
  | 'already_refunded' // já não havia nada por devolver
  | 'not_applicable' // reserva sem pré-pagamento
  | 'not_paid' // o pagamento nunca foi cobrado: nada a devolver
  | 'no_payment_intent' // a reserva diz que houve pré-pagamento mas não tem pagamento gravado
  | 'forfeited_window' // cancelada dentro da janela: a Bora retém, a Stripe nem se lê
  | 'failed'; // não saiu: a equipa é avisada e trata

export interface Reserva {
  id: string;
  restaurant_id: string | null;
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

/** O que a RPC admin_cancel_reservation_on_behalf_of devolve (jsonb). */
export interface RespostaRpc {
  success?: unknown;
  idempotent?: unknown;
  status?: unknown;
  will_refund?: unknown;
  hours_until_reservation?: unknown;
  prepayment_pi?: unknown;
  prepayment_cents?: unknown;
  client_user_id?: unknown;
}

export type FimDaRpc = { ok: true; dados: RespostaRpc | null } | { ok: false; mensagem: string };

/** Quem chama, confirmado no Auth. `papel` = app_metadata.role. */
export interface Chamador {
  id: string;
  email: string | null;
  papel: string | null;
}

export interface Dependencias {
  /** Utilizador do token, confirmado no Auth; null = sem sessão válida. */
  utilizador(): Promise<Chamador | null>;
  /** admin_cancel_reservation_on_behalf_of com o token do admin. */
  cancelarPelaRpc(id: string, motivo: string | null): Promise<FimDaRpc>;
  /** Linha da reserva, lida com a chave do servidor (pode lançar). */
  lerReserva(id: string): Promise<Reserva | null>;
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
  /** Mensagem de erro (Stripe ou base), só para o registo e para o painel. */
  erro: string | null;
  /** Estado REAL da devolução na Stripe (succeeded, pending, failed…), quando há uma só em causa. */
  estadoStripe: string | null;
}

const SEM_DEVOLUCAO: Devolucao = {
  resultado: 'not_applicable',
  cents: 0,
  conta: null,
  refundId: null,
  motivo: null,
  erro: null,
  estadoStripe: null,
};

function inteiro(v: unknown): number {
  return Math.trunc(Number(v ?? 0)) || 0;
}

/** Corpo do pedido, lido como na v21: { reservation_id: uuid, reason?: texto }. */
export function lerPedido(
  body: unknown,
): { reservationId: string; motivo: string | null } | { erro: string } {
  const b = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const id = String(b.reservation_id ?? '').trim();
  if (!id || !UUID_RE.test(id)) return { erro: 'invalid_reservation_id' };
  const motivo = String(b.reason ?? '').trim();
  // Minúsculas: a metadata da Stripe guarda o id como o Postgres o escreve.
  return { reservationId: id.toLowerCase(), motivo: motivo || null };
}

/**
 * Chave de idempotência de UMA tentativa: admin-cancel-rsv-<id>-<n>, com n = quantas devoluções a
 * Stripe já lista para o pagamento (todas, também as 'failed'/'canceled'). Duas chamadas que veem
 * a mesma lista (duplo clique, resposta perdida) dão a mesma chave e a Stripe faz uma devolução
 * só; depois de uma devolução falhada, a lista cresce e a nova tentativa cria outra a sério.
 * Limite conhecido: se a Stripe guardou um ERRO para a chave (ex.: 500) e a lista não cresceu,
 * as novas tentativas nas 24 h seguintes recebem o mesmo erro — falha segura (failed + aviso à
 * equipa), nunca um "devolvido" falso.
 */
export function chaveIdempotencia(reservaId: string, devolucoesVistas: number): string {
  return `admin-cancel-rsv-${reservaId}-${Math.max(0, Math.trunc(devolucoesVistas) || 0)}`;
}

/** Erro da RPC → código HTTP (os mesmos da v21). */
export function httpDoErroDaRpc(mensagem: string): number {
  const m = String(mensagem ?? '');
  if (m.startsWith('reservation_not_found')) return 404;
  if (m.startsWith('cannot_cancel_status')) return 409;
  if (m.startsWith('NOT_ADMIN')) return 403;
  return 500;
}

/** O pagamento é mesmo o pré-pagamento DESTA reserva, e foi cobrado? (= partner-reject) */
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

/** Quanto falta devolver: o que o pagamento recebeu menos as devoluções feitas ou a caminho. (= partner-reject) */
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

/**
 * Depois de um erro ao criar a devolução: relê a lista da Stripe. Se já não falta nada por
 * devolver (normalmente: a devolução saiu e só a resposta se perdeu), devolve o already_refunded
 * a responder; se ainda falta, ou se nem a lista se consegue ler, null (fica o erro original).
 */
async function jaNaoFaltaNada(
  s: StripeDaReserva,
  pi: string,
  pagamento: PagamentoStripe,
  antes: DevolucaoStripe[],
): Promise<Pick<Devolucao, 'resultado' | 'cents' | 'refundId' | 'estadoStripe' | 'motivo'> | null> {
  try {
    const lista = await s.listarDevolucoes(pi);
    const { jaDevolvido, falta } = centsPorDevolver(pagamento, lista);
    if (falta > 0) return null;
    const nova = lista.find((d) =>
      !antes.some((a) => a.id === d.id) && DEVOLUCAO_CONTA.has(String(d.status ?? ''))
    );
    return {
      resultado: 'already_refunded',
      cents: jaDevolvido,
      refundId: nova?.id ?? null,
      estadoStripe: nova ? String(nova.status ?? '') || null : null,
      motivo: 'resposta_perdida',
    };
  } catch (_) {
    return null;
  }
}

/** Devolve o pré-pagamento da reserva. Nunca lança: o que falhar volta em `resultado`. */
export async function devolverPrePagamento(
  reserva: Reserva,
  deps: Pick<Dependencias, 'stripe'>,
): Promise<Devolucao> {
  const pi = String(reserva.prepayment_pi ?? '').trim();
  if (!pi) {
    // Sem pagamento na Stripe não há o que devolver aqui; se a reserva diz que houve
    // pré-pagamento, a equipa tem de ver (o resultado é o mesmo nome da v21).
    return inteiro(reserva.prepayment_cents) > 0
      ? { ...SEM_DEVOLUCAO, resultado: 'no_payment_intent', motivo: 'no_payment_intent' }
      : SEM_DEVOLUCAO;
  }
  let conta: string | null = null;
  try {
    const s = deps.stripe(reserva);
    conta = s.conta;
    const pagamento = await s.lerPagamento(pi);
    const valido = validarPagamento(reserva.id, pagamento);
    if (valido === 'pi_mismatch' || valido === 'payment_processing') {
      return { ...SEM_DEVOLUCAO, conta, resultado: 'failed', motivo: valido };
    }
    if (valido === 'not_paid') {
      return { ...SEM_DEVOLUCAO, conta, resultado: 'not_paid', motivo: `pi_${pagamento.status}` };
    }
    const lista = await s.listarDevolucoes(pi);
    const { jaDevolvido, falta } = centsPorDevolver(pagamento, lista);
    if (falta <= 0) {
      return { ...SEM_DEVOLUCAO, conta, resultado: 'already_refunded', cents: jaDevolvido };
    }
    let refund: DevolucaoStripe;
    try {
      refund = await s.devolver(pi, falta, chaveIdempotencia(reserva.id, lista.length), {
        purpose: 'reservation_admin_cancel',
        reservation_id: reserva.id,
      });
    } catch (e) {
      // Pode ter saído e só a resposta se ter perdido: antes do alarme, a lista diz a verdade.
      const depois = await jaNaoFaltaNada(s, pi, pagamento, lista);
      if (depois) {
        return {
          ...SEM_DEVOLUCAO,
          ...depois,
          conta,
          erro: e instanceof Error ? e.message : String(e), // só para o registo
        };
      }
      throw e;
    }
    const repetida = lista.find((d) => d.id === refund.id);
    if (repetida) {
      // A Stripe devolveu a resposta GUARDADA de um pedido antigo com esta chave: nada saiu agora.
      // Vale o estado da lista (o de hoje), não o da resposta repetida. Com a lista certa não
      // acontece (a chave muda quando a lista cresce); se acontecer, a equipa vê.
      const naLista = String(repetida.status ?? '');
      return {
        ...SEM_DEVOLUCAO,
        conta,
        resultado: 'failed',
        motivo: DEVOLUCAO_CONTA.has(naLista) ? 'refund_replay' : `refund_${naLista || 'desconhecido'}`,
        refundId: refund.id,
        estadoStripe: naLista || null,
      };
    }
    const estado = String(refund.status ?? '');
    if (estado === 'failed' || estado === 'canceled') {
      return {
        ...SEM_DEVOLUCAO,
        conta,
        resultado: 'failed',
        motivo: `refund_${estado}`,
        refundId: refund.id,
        estadoStripe: estado,
      };
    }
    return {
      ...SEM_DEVOLUCAO,
      conta,
      resultado: 'succeeded',
      cents: falta,
      refundId: refund.id,
      estadoStripe: estado || null,
    };
  } catch (e) {
    return {
      ...SEM_DEVOLUCAO,
      conta,
      resultado: 'failed',
      motivo: 'stripe_error',
      erro: e instanceof Error ? e.message : String(e),
    };
  }
}

/** A devolução não saiu e alguém da equipa tem de tratar. */
export function precisaDeAviso(d: Devolucao): boolean {
  return d.resultado === 'failed' || d.resultado === 'no_payment_intent';
}

/** O bloco `refund` da resposta: os campos da v21 + amount_cents, reason e stripe_status. */
export function blocoDevolucao(d: Devolucao): Record<string, unknown> {
  return {
    result: d.resultado,
    stripe_id: d.refundId,
    amount: d.cents > 0 ? d.cents / 100 : null,
    amount_cents: d.cents,
    // Só quando a devolução não saiu: um erro que acabou bem (resposta perdida) fica no registo.
    error: precisaDeAviso(d) ? (d.erro ?? d.motivo) : null,
    reason: d.motivo,
    stripe_status: d.estadoStripe,
  };
}

/** Linha do admin_audit_log: os campos da v21 e os novos (idempotent, refund_reason, …). */
export function linhaDeRegisto(a: {
  quem: Chamador;
  reservaId: string;
  rpc: RespostaRpc;
  reserva: Reserva | null;
  idempotente: boolean;
  comDireito: boolean;
  motivo: string | null;
  devolucao: Devolucao;
}): Record<string, unknown> {
  const d = a.devolucao;
  return {
    admin_id: a.quem.id,
    admin_email: a.quem.email,
    action: ACAO_REGISTO,
    entity_type: 'reservation',
    entity_id: a.reservaId,
    details: {
      new_status: a.rpc.status ?? null,
      idempotent: a.idempotente,
      will_refund: a.comDireito,
      refund_result: d.resultado,
      refund_reason: d.motivo,
      stripe_account: d.conta,
      refund_id: d.refundId,
      refund_status: d.estadoStripe,
      refund_amount: d.cents > 0 ? d.cents / 100 : null,
      refund_cents: d.cents,
      stripe_error: d.erro,
      prepayment_cents: inteiro(a.reserva ? a.reserva.prepayment_cents : a.rpc.prepayment_cents),
      prepayment_pi: (a.reserva ? a.reserva.prepayment_pi : a.rpc.prepayment_pi) ?? null,
      hours_until: a.rpc.hours_until_reservation ?? null,
      reason: a.motivo,
    },
  };
}

export function euros(cents: number): string {
  return `${(cents / 100).toFixed(2).replace('.', ',')} €`;
}

/** O que a equipa precisa de fazer (painel em PT-BR), conforme o motivo. */
const PISTA_PARA_A_EQUIPA: Record<string, string> = {
  pi_mismatch:
    'o pagamento gravado na reserva não é o desta reserva (pode ter sido alterado); conferir antes de reembolsar',
  no_payment_intent: 'a reserva não tem pagamento gravado; conferir se o cliente pagou',
  payment_processing: 'o pagamento ainda está em processamento; reembolsar quando concluir',
  reserva_ilegivel: 'não deu para ler a reserva depois de cancelar; tentar de novo pelo painel',
  refund_replay:
    'a Stripe respondeu com um reembolso antigo e nada saiu agora; conferir os reembolsos na Stripe antes de repetir',
};

/** Aviso no painel quando a devolução não saiu. */
export function avisoDeFalha(a: {
  reservaId: string;
  reserva: Reserva | null;
  rpc: RespostaRpc;
  devolucao: Devolucao;
}): AvisoEquipa {
  const d = a.devolucao;
  const prepagamento = inteiro(a.reserva ? a.reserva.prepayment_cents : a.rpc.prepayment_cents);
  const cents = d.cents > 0 ? d.cents : prepagamento;
  const pista = PISTA_PARA_A_EQUIPA[d.motivo ?? ''] ?? 'reembolsar pelo painel de pagamentos';
  return {
    reservaId: a.reservaId,
    resumo: `Reserva #${a.reservaId.slice(0, 8)}: cancelada pela equipe e o reembolso de ${euros(cents)} ` +
      `ao cliente não foi feito — ${pista}.`,
    detalhes: {
      origem: 'admin-cancel-reservation',
      restaurant_id: a.reserva?.restaurant_id ?? null,
      motivo: d.motivo,
      stripe_account: d.conta,
      stripe_error: d.erro,
      refund_id: d.refundId,
      refund_status: d.estadoStripe,
      prepayment_pi: (a.reserva ? a.reserva.prepayment_pi : a.rpc.prepayment_pi) ?? null,
      prepayment_cents: prepagamento,
      // notify_admin_urgent_push: um push por reserva (sem isto, cada aviso novo tapava o anterior).
      push_ref: `${TIPO_AVISO}:${a.reservaId}`,
    },
  };
}

function mensagemNovaTentativa(d: Devolucao): string {
  if (d.resultado === 'succeeded') return 'already cancelled — missing refund issued now';
  if (precisaDeAviso(d)) return 'already cancelled — refund still missing, team notified';
  return MENSAGEM_JA_CANCELADA;
}

/** O pedido inteiro, do corpo à resposta. `token` = o Bearer do pedido ('' se não veio). */
export async function tratar(body: unknown, token: string, deps: Dependencias): Promise<Resposta> {
  // A mesma ordem da v21: corpo → token → sessão → papel → RPC.
  const pedido = lerPedido(body);
  if ('erro' in pedido) return { status: 400, body: { error: pedido.erro } };
  if (!token) return { status: 401, body: { error: 'missing_token' } };

  const quem = await deps.utilizador();
  if (!quem) return { status: 401, body: { error: 'unauthorized' } };
  if (quem.papel !== 'admin') return { status: 403, body: { error: 'admin_required' } };

  const reservaId = pedido.reservationId;

  // 1. Estado: a RPC de sempre (cancela, avisa o cliente, regista a ação). Idempotente.
  const fim = await deps.cancelarPelaRpc(reservaId, pedido.motivo);
  if (!fim.ok) {
    return { status: httpDoErroDaRpc(fim.mensagem), body: { error: 'rpc_error', detail: fim.mensagem } };
  }
  const r = fim.dados;
  if (!r || r.success !== true) return { status: 500, body: { error: 'rpc_unexpected', detail: r } };

  const idempotente = r.idempotent === true;
  if (idempotente && r.status !== ESTADO_CANCELADA_COM_DEVOLUCAO) {
    // Já cancelada sem direito a devolução (ou rejeitada / não compareceu): igual à v21.
    return {
      status: 200,
      body: {
        success: true,
        idempotent: true,
        reservation_id: reservaId,
        message: MENSAGEM_JA_CANCELADA,
        previous_status: r.status,
      },
    };
  }

  // 2. Dinheiro. Com direito: cancelada agora fora da janela, ou nova tentativa de uma
  //    'cancelled_refunded'. Nunca lança: o que falhar fica registado e a equipa é avisada.
  const comDireito = idempotente || r.will_refund === true;
  let reserva: Reserva | null = null;
  let devolucao: Devolucao;
  if (!comDireito) {
    devolucao = { ...SEM_DEVOLUCAO, resultado: 'forfeited_window' }; // < janela: a Bora retém
  } else {
    let erroLeitura: string | null = null;
    try {
      reserva = await deps.lerReserva(reservaId);
    } catch (e) {
      erroLeitura = e instanceof Error ? e.message : String(e);
    }
    devolucao = reserva
      ? await devolverPrePagamento(reserva, deps)
      : { ...SEM_DEVOLUCAO, resultado: 'failed', motivo: 'reserva_ilegivel', erro: erroLeitura };
  }

  // 3. Registo, como na v21, e aviso à equipa se a devolução não saiu.
  try {
    await deps.registar(linhaDeRegisto({
      quem,
      reservaId,
      rpc: r,
      reserva,
      idempotente,
      comDireito,
      motivo: pedido.motivo,
      devolucao,
    }));
  } catch (e) {
    console.error('[admin-cancel-reservation] registo falhou:', e);
  }
  if (precisaDeAviso(devolucao)) {
    try {
      await deps.avisarEquipa(avisoDeFalha({ reservaId, reserva, rpc: r, devolucao }));
    } catch (e) {
      console.error('[admin-cancel-reservation] aviso à equipa falhou:', e);
    }
  }

  const refund = blocoDevolucao(devolucao);
  if (idempotente) {
    return {
      status: 200,
      body: {
        success: true,
        idempotent: true,
        reservation_id: reservaId,
        message: mensagemNovaTentativa(devolucao),
        previous_status: r.status,
        refund,
      },
    };
  }
  return {
    status: 200,
    body: {
      success: true,
      idempotent: false,
      reservation_id: reservaId,
      new_status: r.status,
      refund,
    },
  };
}
