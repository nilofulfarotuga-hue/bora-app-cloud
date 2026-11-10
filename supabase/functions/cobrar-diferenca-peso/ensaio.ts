// cobrar-diferenca-peso/ensaio.ts — MODO ENSAIO da diferença de peso no cartão.
// Missão fechar-tudo-2026-11-10, Bloco C. Pedido do Danilo: "Prova ponta a ponta em teste: melancia a
// mais → cobra a diferença; a menos → devolve; cartão recusado → pedido não trava e fica dívida
// visível no painel. Com as provas verdes, liga o interruptor."
//
// O que faz: corre o MESMO código do pedido real (_shared/peso_cartao.ts) contra a Stripe da EMPRESA
// em MODO DE TESTE, com cartões de teste da própria Stripe, sem tocar em `orders`, carteiras nem
// dinheiro real. O resultado vai para a tabela `ensaio_peso_cartao` (o painel mostra-a).
//
// Regras de segurança (testadas em ensaio_test.ts):
//   • só a chave STRIPE_TEST_SECRET_KEY_EMPRESA; se faltar → "falta a chave de teste", nunca cai
//     para a chave real;
//   • a chave tem de começar por sk_test_ ou rk_test_; uma chave real ali dentro é recusada;
//   • a Edge só aceita o ensaio com a chave de servidor (o painel chama pela RPC
//     admin_ensaio_peso_cartao, que faz net.http_post com a chave do cofre — igual ao talão);
//   • funciona com o interruptor weight_adjust_card_charge_enabled DESLIGADO (é para isso que serve).
//
// Os casos:
//   a_mais             melancia de 10,00 € pesou mais 2,50 €  → cartão cobrado (cartao_cobrado)
//   a_menos            melancia pesou menos 1,80 €            → carteira (o talão devolve à carteira
//                      Bora; o cartão NÃO é mexido — é a regra de 26/10, ver C_LEIA-ME.md)
//   recusado           cartão de teste 4000 0000 0000 0341 (guarda-se, mas recusa cobranças)
//                                                             → bora_assume (o pedido segue)
//   pede_autenticacao  cartão de teste 4000 0027 6000 3184 (o banco pede sempre autenticação)
//                                                             → bora_assume (o pedido segue)

import { acertoDaDiferenca, cobrarDiferencaNoCartao, type StripePeso } from '../_shared/peso_cartao.ts';

export const NOME_CHAVE_TESTE = 'STRIPE_TEST_SECRET_KEY_EMPRESA';
export const CASOS_ENSAIO = ['a_mais', 'a_menos', 'recusado', 'pede_autenticacao'] as const;
export type CasoEnsaio = typeof CASOS_ENSAIO[number];

interface PlanoCaso {
  /** Cartão de teste da Stripe (tokens pm_card_* do modo de teste). */
  cartao: string;
  /** true = o cartão guarda-se no cliente sem cobrar (os que recusam qualquer cobrança). */
  soGuardar: boolean;
  originalCents: number;
  /** Diferença líquida do talão (peso + acrescentados), em cêntimos. Negativa = saiu mais barato. */
  diferencaCents: number;
  /** O que o caso TEM de dar. */
  esperado: 'cartao_cobrado' | 'carteira' | 'bora_assume';
}

export const PLANO_ENSAIO: Record<CasoEnsaio, PlanoCaso> = {
  a_mais: { cartao: 'pm_card_visa', soGuardar: false, originalCents: 1000, diferencaCents: 250, esperado: 'cartao_cobrado' },
  a_menos: { cartao: 'pm_card_visa', soGuardar: false, originalCents: 1000, diferencaCents: -180, esperado: 'carteira' },
  recusado: { cartao: 'pm_card_chargeCustomerFail', soGuardar: true, originalCents: 1000, diferencaCents: 250, esperado: 'bora_assume' },
  pede_autenticacao: { cartao: 'pm_card_authenticationRequired', soGuardar: true, originalCents: 1000, diferencaCents: 250, esperado: 'bora_assume' },
};

/** O cliente Stripe que o ensaio usa: o do peso + criar cliente e guardar cartão. */
export interface StripeEnsaio extends StripePeso {
  customers: { create(params: Record<string, unknown>): Promise<{ id: string }> };
  paymentMethods: { attach(id: string, params: { customer: string }): Promise<{ id: string }> };
}

export interface LinhaEnsaio {
  caso: string;
  estado: 'ok' | 'falhou' | 'erro';
  esperado: string | null;
  resultado: string | null;
  valor_original_cents: number | null;
  diferenca_cents: number | null;
  pi_original: string | null;
  pi_extra: string | null;
  conta: 'empresa';
  erro: string | null;
  detalhe: Record<string, unknown>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** O corpo pede um ensaio? Devolve o caso (null = caso inválido) e quem pediu (uuid do admin). */
export function lerPedidoDeEnsaio(body: unknown):
  { ensaio: false } | { ensaio: true; caso: CasoEnsaio | null; pedidoPor: string | null } {
  if (!body || typeof body !== 'object') return { ensaio: false };
  const b = body as Record<string, unknown>;
  if (b.ensaio !== true) return { ensaio: false };
  const caso = (CASOS_ENSAIO as readonly string[]).includes(String(b.caso)) ? b.caso as CasoEnsaio : null;
  const pedidoPor = typeof b.pedido_por === 'string' && UUID.test(b.pedido_por) ? b.pedido_por : null;
  return { ensaio: true, caso, pedidoPor };
}

/** A chave de teste existe e é MESMO de teste? (nunca se aceita uma chave real neste modo) */
export function estadoChaveDeTeste(chave: string | null | undefined): 'ok' | 'falta' | 'nao_e_teste' {
  const c = String(chave ?? '').trim();
  if (!c) return 'falta';
  return c.startsWith('sk_test_') || c.startsWith('rk_test_') ? 'ok' : 'nao_e_teste';
}

export const MENSAGEM_FALTA_CHAVE =
  `Falta a chave de teste: põe a chave secreta de teste da Stripe da EMPRESA no segredo ${NOME_CHAVE_TESTE} das Edge Functions.`;
export const MENSAGEM_NAO_E_TESTE =
  `A chave em ${NOME_CHAVE_TESTE} não é de teste (tem de começar por sk_test_). O ensaio não a usa.`;

/** Linha de erro para gravar quando o ensaio nem chega a falar com a Stripe. */
export function linhaDeErro(caso: string, erro: string, detalhe: Record<string, unknown> = {}): LinhaEnsaio {
  const plano = (PLANO_ENSAIO as Record<string, PlanoCaso | undefined>)[caso];
  return {
    caso, estado: 'erro', esperado: plano?.esperado ?? null, resultado: null,
    valor_original_cents: plano?.originalCents ?? null, diferenca_cents: plano?.diferencaCents ?? null,
    pi_original: null, pi_extra: null, conta: 'empresa', erro, detalhe,
  };
}

/** O que o pedido REAL faz a seguir, para ficar escrito ao lado do resultado do ensaio. */
function oQueOPedidoRealFaz(resultado: string, diferencaCents: number): string {
  const euros = (Math.abs(diferencaCents) / 100).toFixed(2).replace('.', ',');
  switch (resultado) {
    case 'cartao_cobrado':
      return `final_total do pedido + ${euros} €, extra_charge_settled_via=cartao_peso, ajustes=cartao_cobrado, aviso no sino do cliente.`;
    case 'carteira':
      return `o talão credita ${euros} € na carteira Bora do cliente (refund_credit_free, storeshopping_v2_peso_variavel); o cartão não é mexido.`;
    case 'bora_assume':
      return `ajustes=bora_assume, aviso URGENTE ao Danilo (porteiro), o pedido segue para entrega e o painel do pedido mostra os ${euros} € por cobrar.`;
    default:
      return '';
  }
}

/**
 * Corre um caso contra a Stripe de TESTE. Nunca lança: qualquer falha inesperada vira estado 'erro'.
 * `id` serve para a idempotência e para o "pedido" de ensaio (ensaio-<id>), que não existe em orders.
 */
export async function correrEnsaio(stripe: StripeEnsaio, caso: CasoEnsaio, id: string): Promise<LinhaEnsaio> {
  const plano = PLANO_ENSAIO[caso];
  const orderId = `ensaio-${id}`;
  const meta = { ensaio: 'peso_cartao', caso, ensaio_id: id };
  const linha: LinhaEnsaio = {
    caso, estado: 'erro', esperado: plano.esperado, resultado: null,
    valor_original_cents: plano.originalCents, diferenca_cents: plano.diferencaCents,
    pi_original: null, pi_extra: null, conta: 'empresa', erro: null, detalhe: { cartao_de_teste: plano.cartao },
  };
  let etapa = 'cliente';
  try {
    // 1) cliente de teste
    const cliente = await stripe.customers.create({ description: 'Bora — ensaio do peso no cartão (modo de teste)', metadata: meta });
    linha.detalhe.cliente = cliente.id;

    // 2) pagamento original, como o create-payment-intent faz (cliente + guardar para off_session)
    etapa = 'pagamento_original';
    if (plano.soGuardar) {
      // cartões que recusam qualquer cobrança: guardam-se no cliente e o pagamento original fica
      // criado (sem confirmar) só para o código real ler dele o cartão e o cliente.
      const pm = await stripe.paymentMethods.attach(plano.cartao, { customer: cliente.id });
      const orig = await stripe.paymentIntents.create({
        amount: plano.originalCents, currency: 'eur', customer: cliente.id, payment_method: pm.id,
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' }, metadata: meta,
      }, { idempotencyKey: `peso_ensaio_orig_${id}` });
      linha.pi_original = orig.id;
      linha.detalhe.status_original = orig.status;
    } else {
      const orig = await stripe.paymentIntents.create({
        amount: plano.originalCents, currency: 'eur', customer: cliente.id, payment_method: plano.cartao,
        setup_future_usage: 'off_session', confirm: true,
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' }, metadata: meta,
      }, { idempotencyKey: `peso_ensaio_orig_${id}` });
      linha.pi_original = orig.id;
      linha.detalhe.status_original = orig.status;
      if (orig.status !== 'succeeded') {
        linha.erro = `pagamento original de teste ficou em ${orig.status}`;
        return linha;
      }
    }

    // 3) a decisão do talão (cópia do SQL) — pedido pago com cartão e interruptor LIGADO
    etapa = 'decisao';
    const acerto = acertoDaDiferenca(plano.diferencaCents, 'card', true);
    linha.detalhe.acerto_do_talao = acerto;

    // 4) o que o pedido real faria com essa decisão
    etapa = 'acerto';
    if (acerto === 'cartao_pendente') {
      const r = await cobrarDiferencaNoCartao(stripe, {
        piOriginal: linha.pi_original, amountCents: plano.diferencaCents, orderId, conta: 'empresa',
        idempotencyKey: `peso_ensaio_${id}`, metadataExtra: meta,
      });
      linha.resultado = r.resultado;
      if (r.ok) {
        linha.pi_extra = r.piId;
      } else {
        linha.pi_extra = r.piId ?? null;
        linha.detalhe.motivo = r.motivo; // o texto que o aviso URGENTE real leva
        linha.detalhe.erro_codigo = r.codigo ?? r.erro;
        if (r.status) linha.detalhe.status_extra = r.status;
      }
    } else {
      // a menos: o talão credita a carteira; a Stripe não é chamada. Confirma-se que o pagamento
      // original ficou intacto (o cliente pagou o valor previsto e nada foi mexido no cartão).
      linha.resultado = acerto;
      const lido = await stripe.paymentIntents.retrieve(linha.pi_original!);
      linha.detalhe.status_original_no_fim = lido.status;
      linha.detalhe.recebido_cents = lido.amount_received ?? null;
      if (lido.status !== 'succeeded' || (lido.amount_received ?? plano.originalCents) !== plano.originalCents) {
        linha.erro = 'o pagamento original mudou';
        linha.estado = 'falhou';
        return linha;
      }
    }
    linha.detalhe.o_pedido_real_faz = oQueOPedidoRealFaz(linha.resultado ?? '', plano.diferencaCents);
    linha.estado = linha.resultado === plano.esperado ? 'ok' : 'falhou';
    if (linha.estado === 'falhou') {
      linha.erro = `deu ${linha.resultado}, esperava ${plano.esperado}` +
        (linha.detalhe.motivo ? ` (${String(linha.detalhe.motivo)})` : '');
    }
    return linha;
  } catch (e) {
    linha.estado = 'erro';
    linha.erro = `${etapa}: ${(e instanceof Error ? e.message : String(e)).slice(0, 300)}`;
    return linha;
  }
}
