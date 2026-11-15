// supabase/functions/create-mbway-appointment-payment-intent/logica.ts
//
// Conserto P0 do Juiz da Claude.ai (15/11/2026 18:42; "Autorizo tudo" do Danilo às 15:15).
// Igual ao conserto de create-appointment-payment-intent (v5), para o MB WAY.
//
// O problema da v4 (no ar até hoje): o cliente Supabase era criado com a chave secreta MAS com o
// cabeçalho Authorization do cliente, por isso o `update({ deposit_pi, stripe_account })` depois
// de criar o PaymentIntent (e mandar o pedido ao MB WAY do cliente) corria como `authenticated` e
// o erro só ia para o log, com resposta ok:true. Com a guarda proposta para appointments
// (docs/propostas/fechar-tudo-15-11/appointments_guarda.PROPOSTA.sql) esse update deixa de passar:
// o cliente aprovava no MB WAY e a marcação ficava sem o pagamento gravado.
//
// O que muda (v5):
//  1. Quem chama é identificado pelo token do pedido (admin.auth.getUser(token)); sem sessão
//     válida = 401. A marcação continua a ser LIDA em nome do cliente (RLS ap_select, como na v4:
//     a de outra pessoa dá 404) e a confirmação de dono (client_user_id = utilizador → senão 403)
//     e de estado ('pending_payment' → senão 409) ficam iguais.
//  2. A escrita do deposit_pi/stripe_account vai por um cliente com a chave do servidor SEM o
//     Authorization do cliente (service_role), e só grava se a marcação ainda for deste cliente e
//     ainda estiver 'pending_payment' (o relógio pode tê-la expirado entretanto).
//  3. Se gravar falhar (erro ou 0 linhas), cancela-se o PaymentIntent (o pedido no MB WAY deixa
//     de valer) e devolve-se 500 save_deposit_pi_failed. Se o cancelamento falhar, a equipa é
//     avisada (notify_admin_urgent_push).
//  4. A chave de idempotência por omissão é fixa por marcação (`mbway_appt_<id>`): uma nova
//     tentativa depois de um PI cancelado recebia da Stripe a resposta GUARDADA da 1.ª (o PI
//     cancelado). Agora, quando a Stripe diz que a resposta é repetida (Idempotent-Replayed) e
//     esse PI já está 'canceled', cria-se um PI novo com a chave `mbway_appt_<id>_r<instante>`.
// Igual à v4: telefone em E.164 (+351 por defeito), guarda "Em breve", nunca cobrar valor por
// omissão (deposit_cents inválido/<50 → 400 invalid_charge_amount), metadata kind='appointment',
// conta Stripe de _shared/stripe_contas.ts, erro da Stripe ao criar → 500 'stripe_error: ...'
// (a marcação fica pending_payment), corpo da resposta de sucesso.
//
// Sem rede: o index.ts liga isto ao Supabase e à Stripe; o logica_test.ts usa falsos.

import { COMING_SOON_BOOKING_MSG, comingSoonResponseBody } from '../_shared/coming_soon.ts';

export type Resposta = { status: number; corpo: Record<string, unknown> };

export interface IntentCriado {
  id: string;
  status?: string;
  /** A Stripe respondeu com a resposta guardada de um pedido anterior com a mesma chave. */
  repetido?: boolean;
}

export interface Marcacao {
  id: string;
  client_user_id: string | null;
  provider_id: string | null;
  deposit_cents: unknown;
  status: string | null;
  deposit_pi?: string | null;
}

export interface CorpoMarcacaoMbway {
  appointment_id?: string;
  phone?: string; // MBWay phone (PT 9 dígitos OU já em E.164)
  idempotency_key?: string;
  stripe_contas_v2?: boolean | string;
}

export interface StripePronta {
  conta: string;
  modo: string;
  criarIntent(params: Record<string, unknown>, chave: string): Promise<IntentCriado>;
  estadoIntent(id: string): Promise<string>;
  cancelarIntent(id: string): Promise<void>;
}

export interface Dependencias {
  utilizadorDoToken(token: string): Promise<{ id: string } | null>;
  /** Lida em nome do cliente (RLS). null = não existe ou não a pode ver. */
  lerMarcacao(id: string): Promise<Marcacao | null>;
  parceiroEmBreve(providerId: string | null): Promise<boolean>;
  prepararStripe(body: CorpoMarcacaoMbway): Promise<StripePronta>;
  /** UPDATE com a chave do servidor; null se gravou 1 linha, senão a mensagem do erro. */
  gravarPi(marcacaoId: string, clienteId: string, piId: string, conta: string): Promise<string | null>;
  avisarEquipa(resumo: string, detalhes: Record<string, unknown>): Promise<void>;
  agora(): number;
}

export function tokenBearer(cabecalho: string | null | undefined): string {
  const h = cabecalho ?? '';
  return /^bearer\s+/i.test(h) ? h.replace(/^bearer\s+/i, '').trim() : '';
}

/** Igual à v4: com '+' fica como está; senão +351 e tira um 0 à frente. */
export function telefoneE164(phone: string): string {
  return phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;
}

/** Igual à v3/v4: número inteiro >= 50, senão null (nunca se cobra um valor por omissão). */
export function centsValidos(raw: unknown): number | null {
  const cents = typeof raw === 'number' ? raw : Number.parseInt(String(raw ?? ''), 10);
  return Number.isInteger(cents) && cents >= 50 ? cents : null;
}

function mensagem(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

const ORIGEM = 'create-mbway-appointment-payment-intent';

export async function tratar(
  cabecalhoAuth: string | null,
  body: CorpoMarcacaoMbway,
  deps: Dependencias,
): Promise<Resposta> {
  const token = tokenBearer(cabecalhoAuth);
  const user = token ? await deps.utilizadorDoToken(token) : null;
  if (!user) return { status: 401, corpo: { error: 'auth required' } };

  if (!body || !body.appointment_id || !body.phone) {
    return { status: 400, corpo: { error: 'missing fields (appointment_id, phone)' } };
  }

  const e164 = telefoneE164(body.phone);

  const appt = await deps.lerMarcacao(body.appointment_id);
  if (!appt) return { status: 404, corpo: { error: 'appointment not found' } };
  if (appt.client_user_id !== user.id) return { status: 403, corpo: { error: 'not your appointment' } };
  if (appt.status !== 'pending_payment') {
    return { status: 409, corpo: { error: 'invalid status: ' + appt.status } };
  }

  // "Em breve": nunca criar PaymentIntent (nem push MBWay) para um parceiro que ainda não aceita
  // marcações. Corre ANTES da Stripe.
  if (await deps.parceiroEmBreve(appt.provider_id)) {
    return { status: 409, corpo: comingSoonResponseBody(COMING_SOON_BOOKING_MSG) };
  }

  const cents = centsValidos(appt.deposit_cents);
  if (cents === null) {
    console.error(`[${ORIGEM}] invalid_charge_amount:`,
      `appointment=${appt.id}`, `deposit_cents=${JSON.stringify(appt.deposit_cents)}`);
    return {
      status: 400,
      corpo: {
        error: 'invalid_charge_amount',
        message: 'A marcação não tem um valor válido para cobrar.',
        appointment_id: appt.id,
      },
    };
  }

  const chaveBase = body.idempotency_key ?? `mbway_appt_${appt.id}`;
  const stripe = await deps.prepararStripe(body);
  const conta = stripe.conta;
  const params = {
    amount: cents,
    currency: 'eur',
    payment_method_types: ['mb_way'],
    payment_method_data: {
      type: 'mb_way',
      billing_details: { phone: e164 },
    },
    confirm: true,
    metadata: {
      kind: 'appointment',
      appointment_id: appt.id,
      provider_id: appt.provider_id,
      purpose: 'appointment_deposit',
      bora_conta: conta,
    },
  };

  let intent: IntentCriado;
  try {
    intent = await stripe.criarIntent(params, chaveBase);
    if (intent.repetido && (await stripe.estadoIntent(intent.id)) === 'canceled') {
      // Tentativa anterior com a mesma chave acabou cancelada: PI novo com chave nova.
      intent = await stripe.criarIntent(params, `${chaveBase}_r${deps.agora()}`);
    }
  } catch (stripeErr) {
    // Marcação fica pending_payment — o cliente pode tentar cartão a seguir.
    const msg = mensagem(stripeErr);
    console.error(`[${ORIGEM}] stripe failed:`, msg);
    return { status: 500, corpo: { error: 'stripe_error: ' + msg } };
  }

  console.log(`[${ORIGEM}] intent confirmed:`, intent.id, `appointment=${appt.id}`,
    `status=${intent.status}`, `mode=${stripe.modo}`);

  let falha: string | null;
  try {
    falha = await deps.gravarPi(appt.id, user.id, intent.id, conta);
  } catch (e) {
    falha = mensagem(e);
  }

  if (falha) {
    let cancelado = true;
    let erroCancelar: string | null = null;
    try {
      await stripe.cancelarIntent(intent.id);
    } catch (e) {
      cancelado = false;
      erroCancelar = mensagem(e);
    }
    if (!cancelado) {
      try {
        await deps.avisarEquipa(
          `Marcação ${appt.id}: MB WAY ${intent.id} criado mas não gravado e não deu para o cancelar`,
          { origem: ORIGEM, appointment_id: appt.id, payment_intent: intent.id, motivo: falha, erro_cancelar: erroCancelar },
        );
      } catch (e) {
        console.error(`[${ORIGEM}] avisar equipa falhou:`, mensagem(e));
      }
    }
    console.error(`[${ORIGEM}] save deposit_pi failed:`, falha, intent.id,
      cancelado ? 'PI cancelado' : `PI NAO cancelado: ${erroCancelar}`);
    return {
      status: 500,
      corpo: {
        ok: false,
        error: 'save_deposit_pi_failed',
        message: 'Não foi possível registar o pagamento da marcação. Se aparecer o pedido no MB WAY, não o aceites; tenta de novo.',
        appointment_id: appt.id,
        payment_intent_cancelled: cancelado,
      },
    };
  }

  return {
    status: 200,
    corpo: {
      ok: true,
      appointment_id: appt.id,
      paymentIntentId: intent.id,
      status: intent.status,
      amount_cents: cents,
      mode: stripe.modo,
      stripe_account: conta, // duas contas
    },
  };
}
