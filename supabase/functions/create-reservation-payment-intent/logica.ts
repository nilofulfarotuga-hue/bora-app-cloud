// supabase/functions/create-reservation-payment-intent/logica.ts
//
// Conserto P0 do Juiz da Claude.ai (15/11/2026 18:42; "Autorizo tudo" do Danilo às 15:15).
//
// O problema da v10 (no ar até hoje): o cliente Supabase era criado com a chave secreta MAS com o
// cabeçalho Authorization do cliente, por isso as escritas corriam como `authenticated`. Desde
// 15/11 o gatilho trg_00_reservas_campos_protegidos recusa a um cliente mudar `prepayment_pi`, e o
// `update({ prepayment_pi })` depois de criar o PaymentIntent falhava em silêncio (o erro era
// ignorado): reserva paga sem o pagamento gravado, presa.
//
// O que muda (v11):
//  1. Quem chama é identificado pelo token do pedido (admin.auth.getUser(token)); sem sessão
//     válida = 401, como antes.
//  2. TODAS as escritas (inserir a reserva, gravar o prepayment_pi, apagar a reserva por acabar)
//     vão por um cliente com a chave do servidor SEM o Authorization do cliente (service_role):
//     o gatilho deixa passar e a RLS não se mete.
//  3. Se gravar o prepayment_pi falhar (erro ou 0 linhas), cancela-se o PaymentIntent na Stripe e
//     devolve-se erro (500 save_prepayment_pi_failed). Nunca se devolve um clientSecret de um
//     pagamento que a base de dados não conhece. Cancelado o PI, apaga-se a reserva que este pedido
//     acabou de criar (ainda 'pending_payment', sem pagamento). Se o cancelamento falhar, a reserva
//     FICA (o webhook ainda a encontra pelo metadata.reservation_id) e a equipa é avisada.
// Igual à v10: corpo e códigos das respostas de sucesso, guarda "Em breve", valor lido de
// platform_settings.reservation_prepayment_cents (300 por defeito, mínimo 50), conta Stripe
// decidida em _shared/stripe_contas.ts, chave de idempotência `rsv_<id da reserva>`.
//
// Sem rede: o index.ts liga isto ao Supabase e à Stripe; o logica_test.ts usa falsos.

import { COMING_SOON_RESERVATION_MSG, comingSoonResponseBody } from '../_shared/coming_soon.ts';

export const PROPOSITO = 'reservation_prepayment';

export type Resposta = { status: number; corpo: Record<string, unknown> };

export interface IntentCriado {
  id: string;
  client_secret: string | null;
  status?: string;
}

export interface CorpoReserva {
  restaurant_id?: string;
  people?: number;
  reserved_for?: string;
  client_name?: string;
  client_phone?: string;
  notes?: string;
  idempotency_key?: string;
  stripe_contas_v2?: boolean | string;
}

export interface StripePronta {
  conta: string;
  criarIntent(params: Record<string, unknown>, chave: string): Promise<IntentCriado>;
  cancelarIntent(id: string): Promise<void>;
}

export interface Dependencias {
  /** id do utilizador dono do token (confirmado no Auth), ou null. */
  utilizadorDoToken(token: string): Promise<{ id: string } | null>;
  restauranteEmBreve(restaurantId: string): Promise<boolean>;
  /** Valor bruto de platform_settings.reservation_prepayment_cents (null = sem linha). */
  lerValorPrepagamento(): Promise<unknown>;
  prepararStripe(body: CorpoReserva): Promise<StripePronta>;
  /** INSERT com a chave do servidor. */
  inserirReserva(linha: Record<string, unknown>): Promise<{ id: string } | { erro: string }>;
  /** UPDATE com a chave do servidor; devolve null se gravou 1 linha, ou a mensagem do erro. */
  gravarPi(reservaId: string, piId: string): Promise<string | null>;
  apagarReserva(reservaId: string): Promise<void>;
  respostaConta(conta: string): Record<string, unknown>;
  avisarEquipa(resumo: string, detalhes: Record<string, unknown>): Promise<void>;
}

/** O token do cabeçalho Authorization (sem "Bearer "), ou '' se não houver. */
export function tokenBearer(cabecalho: string | null | undefined): string {
  const h = cabecalho ?? '';
  return /^bearer\s+/i.test(h) ? h.replace(/^bearer\s+/i, '').trim() : '';
}

/** Igual à v10: parseInt do valor, 300 quando não há linha. */
export function centsDoValor(valor: unknown): number {
  return parseInt(String(valor ?? 300), 10);
}

function erro(status: number, corpo: Record<string, unknown>): Resposta {
  return { status, corpo };
}

function mensagem(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/**
 * Gravar o PI falhou: cancela o PaymentIntent e, se o cancelamento sair, apaga a reserva que este
 * pedido criou. Nunca lança.
 */
export async function desfazer(
  deps: Dependencias,
  stripe: StripePronta,
  reservaId: string,
  piId: string,
  motivo: string,
  origem: string,
): Promise<Resposta> {
  let cancelado = true;
  let erroCancelar: string | null = null;
  try {
    await stripe.cancelarIntent(piId);
  } catch (e) {
    cancelado = false;
    erroCancelar = mensagem(e);
  }
  if (cancelado) {
    try {
      await deps.apagarReserva(reservaId);
    } catch (e) {
      console.error(`[${origem}] apagar reserva ${reservaId} falhou:`, mensagem(e));
    }
  } else {
    try {
      await deps.avisarEquipa(
        `Reserva ${reservaId}: pagamento ${piId} criado mas não gravado e não deu para o cancelar`,
        { origem, reservation_id: reservaId, payment_intent: piId, motivo, erro_cancelar: erroCancelar },
      );
    } catch (e) {
      console.error(`[${origem}] avisar equipa falhou:`, mensagem(e));
    }
  }
  console.error(`[${origem}] save prepayment_pi failed:`, motivo, piId,
    cancelado ? 'PI cancelado' : `PI NAO cancelado: ${erroCancelar}`);
  return erro(500, {
    ok: false,
    error: 'save_prepayment_pi_failed',
    message: 'Não foi possível registar o pagamento da reserva. Nada foi cobrado; tenta de novo.',
    payment_intent_cancelled: cancelado,
  });
}

export async function tratar(
  cabecalhoAuth: string | null,
  body: CorpoReserva,
  deps: Dependencias,
): Promise<Resposta> {
  const origem = 'create-reservation-payment-intent';
  const token = tokenBearer(cabecalhoAuth);
  const user = token ? await deps.utilizadorDoToken(token) : null;
  if (!user) return erro(401, { error: 'auth required' });

  if (!body || !body.restaurant_id || !body.people || !body.reserved_for) {
    return erro(400, { error: 'missing fields' });
  }

  if (await deps.restauranteEmBreve(body.restaurant_id)) {
    return erro(409, comingSoonResponseBody(COMING_SOON_RESERVATION_MSG));
  }

  const cents = centsDoValor(await deps.lerValorPrepagamento());
  if (cents < 50) {
    return erro(400, { error: 'prepayment too small (Stripe min 0.50 EUR)' });
  }

  const stripe = await deps.prepararStripe(body);
  const conta = stripe.conta;

  const rsv = await deps.inserirReserva({
    stripe_account: conta,
    client_user_id: user.id,
    restaurant_id: body.restaurant_id,
    people: body.people,
    reserved_for: body.reserved_for,
    client_name: body.client_name,
    client_phone: body.client_phone,
    notes: body.notes,
    status: 'pending_payment',
    prepayment_cents: cents,
  });
  if ('erro' in rsv) {
    return erro(500, { error: 'failed to create reservation: ' + rsv.erro });
  }

  const chave = body.idempotency_key ?? `rsv_${rsv.id}`;
  const intent = await stripe.criarIntent({
    amount: cents,
    currency: 'eur',
    payment_method_types: ['card'],
    metadata: {
      reservation_id: rsv.id,
      restaurant_id: body.restaurant_id,
      purpose: PROPOSITO,
      bora_conta: conta,
    },
  }, chave);

  let falha: string | null;
  try {
    falha = await deps.gravarPi(rsv.id, intent.id);
  } catch (e) {
    falha = mensagem(e);
  }
  if (falha) return await desfazer(deps, stripe, rsv.id, intent.id, falha, origem);

  return {
    status: 200,
    corpo: {
      reservation_id: rsv.id,
      paymentIntentId: intent.id,
      clientSecret: intent.client_secret,
      amount_cents: cents,
      ...deps.respostaConta(conta),
    },
  };
}
