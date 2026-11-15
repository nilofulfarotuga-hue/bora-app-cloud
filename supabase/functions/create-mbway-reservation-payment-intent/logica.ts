// supabase/functions/create-mbway-reservation-payment-intent/logica.ts
//
// Conserto P0 do Juiz da Claude.ai (15/11/2026 18:42; "Autorizo tudo" do Danilo às 15:15).
//
// O problema da v6 (no ar até hoje): o cliente Supabase era criado com a chave secreta MAS com o
// cabeçalho Authorization do cliente, por isso as escritas corriam como `authenticated`. Desde
// 15/11 o gatilho trg_00_reservas_campos_protegidos recusa a um cliente mudar `prepayment_pi`; a
// v6 só escrevia o erro no log e respondia ok:true. Resultado: o cliente aprovava no MB WAY e a
// reserva ficava sem o pagamento gravado.
//
// O que muda (v7):
//  1. Quem chama é identificado pelo token do pedido (admin.auth.getUser(token)); sem sessão
//     válida = 401, como antes.
//  2. TODAS as escritas (inserir a reserva, gravar o prepayment_pi, apagar a reserva por acabar)
//     vão por um cliente com a chave do servidor SEM o Authorization do cliente (service_role).
//  3. Se gravar o prepayment_pi falhar (erro ou 0 linhas), cancela-se o PaymentIntent na Stripe
//     (o pedido no telemóvel deixa de valer) e devolve-se erro 500 save_prepayment_pi_failed.
//     Cancelado o PI, apaga-se a reserva que este pedido criou. Se o cancelamento falhar, a
//     reserva FICA (o webhook ainda a encontra pelo metadata.reservation_id) e a equipa é avisada.
// Igual à v6: telefone em E.164 (+351 por defeito), guarda "Em breve", valor de
// platform_settings.reservation_prepayment_cents (300 por defeito, mínimo 50), conta Stripe de
// _shared/stripe_contas.ts, chave `mbway_rsv_<id>`, erro da Stripe ao criar → apaga a reserva e
// 500 'stripe_error: ...', corpo da resposta de sucesso.
//
// Sem rede: o index.ts liga isto ao Supabase e à Stripe; o logica_test.ts usa falsos.

import { COMING_SOON_RESERVATION_MSG, comingSoonResponseBody } from '../_shared/coming_soon.ts';

export const PROPOSITO = 'reservation_prepayment';

export type Resposta = { status: number; corpo: Record<string, unknown> };

export interface IntentCriado {
  id: string;
  status?: string;
}

export interface CorpoReservaMbway {
  restaurant_id?: string;
  people?: number;
  reserved_for?: string;
  client_name?: string;
  client_phone?: string;
  notes?: string;
  phone?: string;
  idempotency_key?: string;
  stripe_contas_v2?: boolean | string;
}

export interface StripePronta {
  conta: string;
  modo: string;
  criarIntent(params: Record<string, unknown>, chave: string): Promise<IntentCriado>;
  cancelarIntent(id: string): Promise<void>;
}

export interface Dependencias {
  utilizadorDoToken(token: string): Promise<{ id: string } | null>;
  restauranteEmBreve(restaurantId: string): Promise<boolean>;
  lerValorPrepagamento(): Promise<unknown>;
  prepararStripe(body: CorpoReservaMbway): Promise<StripePronta>;
  inserirReserva(linha: Record<string, unknown>): Promise<{ id: string } | { erro: string }>;
  /** null se gravou 1 linha, senão a mensagem do erro. */
  gravarPi(reservaId: string, piId: string): Promise<string | null>;
  apagarReserva(reservaId: string): Promise<void>;
  avisarEquipa(resumo: string, detalhes: Record<string, unknown>): Promise<void>;
}

export function tokenBearer(cabecalho: string | null | undefined): string {
  const h = cabecalho ?? '';
  return /^bearer\s+/i.test(h) ? h.replace(/^bearer\s+/i, '').trim() : '';
}

/** Igual à v6: com '+' fica como está; senão +351 e tira um 0 à frente. */
export function telefoneE164(phone: string): string {
  return phone.startsWith('+') ? phone : `+351${phone.replace(/^0/, '')}`;
}

export function centsDoValor(valor: unknown): number {
  return parseInt(String(valor ?? 300), 10);
}

function mensagem(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

const ORIGEM = 'create-mbway-reservation-payment-intent';

async function apagarSemLancar(deps: Dependencias, id: string) {
  try {
    await deps.apagarReserva(id);
  } catch (e) {
    console.error(`[${ORIGEM}] apagar reserva ${id} falhou:`, mensagem(e));
  }
}

export async function tratar(
  cabecalhoAuth: string | null,
  body: CorpoReservaMbway,
  deps: Dependencias,
): Promise<Resposta> {
  const token = tokenBearer(cabecalhoAuth);
  const user = token ? await deps.utilizadorDoToken(token) : null;
  if (!user) return { status: 401, corpo: { error: 'auth required' } };

  if (!body || !body.restaurant_id || !body.people || !body.reserved_for || !body.phone) {
    return { status: 400, corpo: { error: 'missing fields (restaurant_id, people, reserved_for, phone)' } };
  }

  const e164 = telefoneE164(body.phone);

  if (await deps.restauranteEmBreve(body.restaurant_id)) {
    return { status: 409, corpo: comingSoonResponseBody(COMING_SOON_RESERVATION_MSG) };
  }

  const cents = centsDoValor(await deps.lerValorPrepagamento());
  if (cents < 50) {
    return { status: 400, corpo: { error: 'prepayment too small (Stripe min 0.50 EUR)' } };
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
    return { status: 500, corpo: { error: 'failed to create reservation: ' + rsv.erro } };
  }

  const chave = body.idempotency_key ?? `mbway_rsv_${rsv.id}`;

  let intent: IntentCriado;
  try {
    intent = await stripe.criarIntent({
      amount: cents,
      currency: 'eur',
      payment_method_types: ['mb_way'],
      payment_method_data: {
        type: 'mb_way',
        billing_details: { phone: e164 },
      },
      confirm: true,
      metadata: {
        reservation_id: rsv.id,
        restaurant_id: body.restaurant_id,
        purpose: PROPOSITO,
        bora_conta: conta,
      },
    }, chave);
  } catch (stripeErr) {
    await apagarSemLancar(deps, rsv.id);
    const msg = mensagem(stripeErr);
    console.error(`[${ORIGEM}] stripe failed:`, msg);
    return { status: 500, corpo: { error: 'stripe_error: ' + msg } };
  }

  console.log(`[${ORIGEM}] intent confirmed:`, intent.id, `reservation=${rsv.id}`,
    `status=${intent.status}`, `mode=${stripe.modo}`);

  let falha: string | null;
  try {
    falha = await deps.gravarPi(rsv.id, intent.id);
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
    if (cancelado) {
      await apagarSemLancar(deps, rsv.id);
    } else {
      try {
        await deps.avisarEquipa(
          `Reserva ${rsv.id}: MB WAY ${intent.id} criado mas não gravado e não deu para o cancelar`,
          { origem: ORIGEM, reservation_id: rsv.id, payment_intent: intent.id, motivo: falha, erro_cancelar: erroCancelar },
        );
      } catch (e) {
        console.error(`[${ORIGEM}] avisar equipa falhou:`, mensagem(e));
      }
    }
    console.error(`[${ORIGEM}] save prepayment_pi failed:`, falha, intent.id,
      cancelado ? 'PI cancelado' : `PI NAO cancelado: ${erroCancelar}`);
    return {
      status: 500,
      corpo: {
        ok: false,
        error: 'save_prepayment_pi_failed',
        message: 'Não foi possível registar o pagamento da reserva. Se aparecer o pedido no MB WAY, não o aceites; tenta de novo.',
        payment_intent_cancelled: cancelado,
      },
    };
  }

  return {
    status: 200,
    corpo: {
      ok: true,
      reservation_id: rsv.id,
      paymentIntentId: intent.id,
      status: intent.status,
      amount_cents: cents,
      mode: stripe.modo,
      stripe_account: conta, // duas contas
    },
  };
}
