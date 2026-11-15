// deno test --no-check --no-lock --cached-only supabase/functions/admin-cancel-reservation/logica_test.ts
// fechar-tudo-15-11: o admin cancela uma reserva paga e a Bora devolve — sem rede, com falsos.
// A RPC falsa imita admin_cancel_reservation_on_behalf_of (lida no servidor a 15/11): estados
// finais respondem idempotent=true; 'pending'/'approved' cancelam com ou sem direito (janela 2 h).
// A Stripe falsa guarda as devoluções por chave de idempotência e nunca devolve mais do que o
// pagamento recebeu, como a verdadeira.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import * as parceiro from '../partner-reject-reservation/logica.ts';
import {
  type Chamador,
  centsPorDevolver,
  chaveIdempotencia,
  type Dependencias,
  type DevolucaoStripe,
  type FimDaRpc,
  httpDoErroDaRpc,
  lerPedido,
  MENSAGEM_JA_CANCELADA,
  type PagamentoStripe,
  type Reserva,
  tratar,
  validarPagamento,
} from './logica.ts';

const ID = '0b5c3e2a-1d4f-4a6b-9c8d-7e6f5a4b3c2d';
const ADMIN: Chamador = { id: 'admin-1', email: 'equipa@bora.pt', papel: 'admin' };
const TOKEN = 'exemplo-de-sessao-admin'; // só tem de não vir vazio; a sessão é o falso `utilizador`
const ESTADOS_FINAIS = ['cancelled_refunded', 'cancelled_no_refund', 'rejected', 'no_show'];

function reserva(extra: Partial<Reserva> = {}): Reserva {
  return {
    id: ID,
    restaurant_id: 'rest-1',
    status: 'approved',
    prepayment_pi: 'pi_1',
    prepayment_cents: 300,
    stripe_account: 'empresa',
    ...extra,
  };
}

function pagamento(extra: Partial<PagamentoStripe> = {}): PagamentoStripe {
  return {
    id: 'pi_1',
    status: 'succeeded',
    amount_received: 300,
    metadata: { purpose: 'reservation_prepayment', reservation_id: ID },
    ...extra,
  };
}

interface Opcoes {
  reserva?: Reserva | null;
  /** Horas até à reserva quando a RPC cancela (janela = 2 h). */
  horas?: number;
  quem?: Chamador | null;
  pagamento?: PagamentoStripe;
  devolucoes?: DevolucaoStripe[];
  /** criar_uma_vez: a 1.ª devolução lança antes de chegar à Stripe; perder_resposta: a Stripe
   *  faz a 1.ª devolução mas a resposta perde-se pelo caminho. */
  stripeFalha?: 'ler' | 'criar' | 'criar_uma_vez' | 'perder_resposta';
  devolucaoFalhada?: boolean;
  leituraFalha?: boolean;
  registoFalha?: boolean;
  rpc?: () => FimDaRpc;
}

/** Base, RPC e Stripe falsas. Conta tudo o que foi chamado. */
function mundo(op: Opcoes = {}) {
  let linha: Reserva | null = op.reserva === undefined ? reserva() : op.reserva;
  const horas = op.horas ?? 24;
  const pag = op.pagamento ?? pagamento();
  const devolucoes: DevolucaoStripe[] = [...(op.devolucoes ?? [])];
  const porChave = new Map<string, DevolucaoStripe>();
  let falhasPorDar = op.stripeFalha === 'criar_uma_vez' || op.stripeFalha === 'perder_resposta' ? 1 : 0;
  const conta = {
    rpc: 0,
    lerReserva: 0,
    stripe: 0,
    criar: 0,
    chaves: [] as string[],
    metadata: [] as Record<string, string>[],
    contasPedidas: [] as string[],
    registos: [] as Record<string, unknown>[],
    avisos: [] as { reservaId: string; resumo: string; detalhes: Record<string, unknown> }[],
  };
  const deps: Dependencias = {
    utilizador: () => Promise.resolve(op.quem === undefined ? ADMIN : op.quem),
    cancelarPelaRpc: (id, _motivo) => {
      conta.rpc++;
      if (op.rpc) return Promise.resolve(op.rpc());
      if (!linha || linha.id !== id) {
        return Promise.resolve<FimDaRpc>({ ok: false, mensagem: 'reservation_not_found' });
      }
      const r = linha;
      if (ESTADOS_FINAIS.includes(r.status)) {
        return Promise.resolve<FimDaRpc>({
          ok: true,
          dados: {
            success: true,
            idempotent: true,
            status: r.status,
            will_refund: r.status === 'cancelled_refunded',
            prepayment_pi: r.prepayment_pi,
            client_user_id: 'cliente-1',
            prepayment_cents: r.prepayment_cents,
          },
        });
      }
      if (!['pending', 'approved'].includes(r.status)) {
        return Promise.resolve<FimDaRpc>({ ok: false, mensagem: `cannot_cancel_status: ${r.status}` });
      }
      const comDireito = horas >= 2;
      const novo = comDireito ? 'cancelled_refunded' : 'cancelled_no_refund';
      linha = { ...r, status: novo };
      return Promise.resolve<FimDaRpc>({
        ok: true,
        dados: {
          success: true,
          idempotent: false,
          status: novo,
          will_refund: comDireito,
          hours_until_reservation: horas,
          prepayment_pi: r.prepayment_pi,
          client_user_id: 'cliente-1',
          prepayment_cents: r.prepayment_cents,
        },
      });
    },
    lerReserva: (id) => {
      conta.lerReserva++;
      if (op.leituraFalha) return Promise.reject(new Error('base em baixo'));
      return Promise.resolve(linha && linha.id === id ? { ...linha } : null);
    },
    stripe: (r) => {
      conta.stripe++;
      conta.contasPedidas.push(String(r.stripe_account));
      return {
        conta: r.stripe_account === 'empresa' ? 'empresa' : 'pessoal',
        lerPagamento: () =>
          op.stripeFalha === 'ler' ? Promise.reject(new Error('stripe em baixo')) : Promise.resolve(pag),
        listarDevolucoes: () => Promise.resolve([...devolucoes]),
        devolver: (_pi, cents, chave, metadata) => {
          conta.criar++;
          conta.chaves.push(chave);
          conta.metadata.push(metadata);
          if (op.stripeFalha === 'criar') return Promise.reject(new Error('charge_disputed'));
          if (op.stripeFalha === 'criar_uma_vez' && falhasPorDar > 0) {
            falhasPorDar--;
            return Promise.reject(new Error('api_connection_error'));
          }
          const ja = porChave.get(chave);
          if (ja) return Promise.resolve(ja); // mesma chave → a mesma devolução
          const feito = devolucoes
            .filter((d) => d.status !== 'failed' && d.status !== 'canceled')
            .reduce((s, d) => s + d.amount, 0);
          if (feito + cents > (pag.amount_received ?? 0)) {
            return Promise.reject(new Error('amount_too_large')); // a Stripe nunca passa do recebido
          }
          const nova: DevolucaoStripe = {
            id: `re_${porChave.size + 1}`,
            amount: cents,
            status: op.devolucaoFalhada ? 'failed' : 'succeeded',
          };
          porChave.set(chave, nova);
          devolucoes.push(nova);
          if (op.stripeFalha === 'perder_resposta' && falhasPorDar > 0) {
            falhasPorDar--;
            return Promise.reject(new Error('socket hang up')); // feita na Stripe, resposta perdida
          }
          return Promise.resolve(nova);
        },
      };
    },
    registar: (l) => {
      if (op.registoFalha) return Promise.reject(new Error('base em baixo'));
      conta.registos.push(l);
      return Promise.resolve();
    },
    avisarEquipa: (a) => {
      conta.avisos.push(a);
      return Promise.resolve();
    },
  };
  const totalDevolvido = () =>
    devolucoes.filter((d) => d.status === 'succeeded').reduce((s, d) => s + d.amount, 0);
  return { deps, conta, totalDevolvido, estado: () => linha?.status };
}

function refundDe(r: { body: Record<string, unknown> }): Record<string, unknown> {
  return r.body.refund as Record<string, unknown>;
}

function detalhes(l: Record<string, unknown>): Record<string, unknown> {
  return l.details as Record<string, unknown>;
}

// ── pedido, chave e erros: como na v21 ──────────────────────────────────────────────────────────

Deno.test('pedido: lido como na v21 (id obrigatório, motivo limpo)', () => {
  assertEquals(lerPedido(null), { erro: 'invalid_reservation_id' });
  assertEquals(lerPedido([]), { erro: 'invalid_reservation_id' });
  assertEquals(lerPedido('texto'), { erro: 'invalid_reservation_id' });
  assertEquals(lerPedido({ reservation_id: 'abc' }), { erro: 'invalid_reservation_id' });
  assertEquals(lerPedido({ reservation_id: 12 }), { erro: 'invalid_reservation_id' });
  assertEquals(
    lerPedido({ reservation_id: ` ${ID.toUpperCase()} `, reason: '  cliente pediu  ' }),
    { reservationId: ID, motivo: 'cliente pediu' },
  );
  assertEquals(lerPedido({ reservation_id: ID, reason: '   ' }), { reservationId: ID, motivo: null });
  assertEquals(lerPedido({ reservation_id: ID }), { reservationId: ID, motivo: null });
});

Deno.test('chave de idempotência: a mesma da v21 (admin-cancel-rsv-<id>)', () => {
  assertEquals(chaveIdempotencia(ID), `admin-cancel-rsv-${ID}`);
});

Deno.test('erros da RPC: os mesmos códigos HTTP da v21', () => {
  assertEquals(httpDoErroDaRpc('reservation_not_found'), 404);
  assertEquals(httpDoErroDaRpc('cannot_cancel_status: pending_payment'), 409);
  assertEquals(httpDoErroDaRpc('NOT_ADMIN'), 403);
  assertEquals(httpDoErroDaRpc('qualquer outra coisa'), 500);
});

Deno.test('regras do pagamento iguais às de partner-reject-reservation (gémeos)', () => {
  const pagamentos: PagamentoStripe[] = [
    pagamento(),
    pagamento({ metadata: { purpose: 'reservation_prepayment', reservation_id: 'outra' } }),
    pagamento({ metadata: { purpose: 'order', reservation_id: ID } }),
    pagamento({ metadata: null }),
    pagamento({ metadata: {} }),
    pagamento({ status: 'processing', amount_received: 0 }),
    pagamento({ status: 'requires_payment_method', amount_received: 0 }),
    pagamento({ status: 'canceled', amount_received: 0 }),
    pagamento({ amount_received: 0 }),
    pagamento({ amount_received: null }),
    pagamento({ amount_received: 5000 }),
  ];
  const listas: DevolucaoStripe[][] = [
    [],
    [{ id: 're_1', amount: 300, status: 'succeeded' }],
    [{ id: 're_1', amount: 300, status: 'pending' }],
    [{ id: 're_1', amount: 300, status: 'requires_action' }],
    [{ id: 're_1', amount: 300, status: 'failed' }],
    [{ id: 're_1', amount: 300, status: 'canceled' }],
    [{ id: 're_1', amount: 100, status: 'succeeded' }, { id: 're_2', amount: 50, status: 'pending' }],
    [{ id: 're_1', amount: 900, status: 'succeeded' }],
    [{ id: 're_1', amount: -5, status: 'succeeded' }],
  ];
  for (const p of pagamentos) {
    assertEquals(validarPagamento(ID, p), parceiro.validarPagamento(ID, p), JSON.stringify(p));
    for (const l of listas) {
      assertEquals(centsPorDevolver(p, l), parceiro.centsPorDevolver(p, l), JSON.stringify([p, l]));
    }
  }
});

// ── o caminho feliz ─────────────────────────────────────────────────────────────────────────────

Deno.test('admin cancela reserva paga com tempo: RPC uma vez, devolve 3 € com a chave e regista', async () => {
  const m = mundo();
  const r = await tratar({ reservation_id: ID, reason: 'Cliente pediu ao suporte' }, TOKEN, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body, {
    success: true,
    idempotent: false,
    reservation_id: ID,
    new_status: 'cancelled_refunded',
    refund: { result: 'succeeded', stripe_id: 're_1', amount: 3, amount_cents: 300, error: null, reason: null },
  });
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}`]);
  assertEquals(m.conta.metadata[0], { purpose: 'reservation_admin_cancel', reservation_id: ID });
  assertEquals(m.conta.contasPedidas, ['empresa']); // a conta onde entrou
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(m.conta.registos.length, 1);
  const reg = m.conta.registos[0];
  assertEquals(reg.action, 'reservation_cancel_complete');
  assertEquals(reg.admin_id, 'admin-1');
  assertEquals(reg.admin_email, 'equipa@bora.pt');
  assertEquals(reg.entity_type, 'reservation');
  assertEquals(reg.entity_id, ID);
  const det = detalhes(reg);
  assertEquals(det.new_status, 'cancelled_refunded');
  assertEquals(det.idempotent, false);
  assertEquals(det.will_refund, true);
  assertEquals(det.refund_result, 'succeeded');
  assertEquals(det.stripe_account, 'empresa');
  assertEquals(det.refund_id, 're_1');
  assertEquals(det.refund_amount, 3);
  assertEquals(det.prepayment_cents, 300);
  assertEquals(det.hours_until, 24);
  assertEquals(det.reason, 'Cliente pediu ao suporte');
  assertEquals(m.conta.avisos.length, 0);
  assertEquals(m.estado(), 'cancelled_refunded');
});

Deno.test('reserva paga na conta pessoal: devolve pela pessoal', async () => {
  const m = mundo({ reserva: reserva({ stripe_account: 'pessoal' }) });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'succeeded');
  assertEquals(m.conta.contasPedidas, ['pessoal']);
  assertEquals(detalhes(m.conta.registos[0]).stripe_account, 'pessoal');
});

Deno.test('dentro da janela (< 2 h): a Bora retém e a Stripe nem se lê', async () => {
  const m = mundo({ horas: 1 });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.new_status, 'cancelled_no_refund');
  assertEquals(refundDe(r), {
    result: 'forfeited_window',
    stripe_id: null,
    amount: null,
    amount_cents: 0,
    error: null,
    reason: null,
  });
  assertEquals(m.conta.lerReserva, 0);
  assertEquals(m.conta.stripe, 0);
  assertEquals(m.conta.registos.length, 1);
  assertEquals(detalhes(m.conta.registos[0]).will_refund, false);
  assertEquals(detalhes(m.conta.registos[0]).prepayment_cents, 300);
  assertEquals(m.conta.avisos.length, 0);
});

// ── quem chama ──────────────────────────────────────────────────────────────────────────────────

Deno.test('quem não é admin não mexe em nada', async () => {
  const m = mundo({ quem: { id: 'cliente-1', email: 'c@x.pt', papel: null } });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r, { status: 403, body: { error: 'admin_required' } });
  assertEquals(m.conta.rpc, 0);
  assertEquals(m.conta.stripe, 0);
});

Deno.test('sessão inválida: 401 unauthorized e nada muda', async () => {
  const m = mundo({ quem: null });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r, { status: 401, body: { error: 'unauthorized' } });
  assertEquals(m.conta.rpc, 0);
});

Deno.test('sem token: 401 missing_token; id inválido: 400 antes do token (ordem da v21)', async () => {
  const m = mundo();
  assertEquals(await tratar({ reservation_id: ID }, '', m.deps), { status: 401, body: { error: 'missing_token' } });
  assertEquals(
    await tratar({ reservation_id: 'x' }, '', m.deps),
    { status: 400, body: { error: 'invalid_reservation_id' } },
  );
  assertEquals(m.conta.rpc, 0);
});

// ── erros da RPC ────────────────────────────────────────────────────────────────────────────────

Deno.test('erros da RPC passam como na v21 e não tocam na Stripe', async () => {
  const naoExiste = mundo({ reserva: null });
  assertEquals(
    await tratar({ reservation_id: ID }, TOKEN, naoExiste.deps),
    { status: 404, body: { error: 'rpc_error', detail: 'reservation_not_found' } },
  );
  const porPagar = mundo({ reserva: reserva({ status: 'pending_payment' }) });
  assertEquals(
    await tratar({ reservation_id: ID }, TOKEN, porPagar.deps),
    { status: 409, body: { error: 'rpc_error', detail: 'cannot_cancel_status: pending_payment' } },
  );
  const naoAdmin = mundo({ rpc: () => ({ ok: false, mensagem: 'NOT_ADMIN' }) });
  assertEquals((await tratar({ reservation_id: ID }, TOKEN, naoAdmin.deps)).status, 403);
  const estranha = mundo({ rpc: () => ({ ok: true, dados: { success: false } }) });
  assertEquals(
    await tratar({ reservation_id: ID }, TOKEN, estranha.deps),
    { status: 500, body: { error: 'rpc_unexpected', detail: { success: false } } },
  );
  for (const w of [naoExiste, porPagar, naoAdmin, estranha]) {
    assertEquals(w.conta.stripe, 0);
    assertEquals(w.conta.registos.length, 0);
  }
});

// ── novas tentativas ────────────────────────────────────────────────────────────────────────────

Deno.test('duas chamadas seguidas: uma devolução só', async () => {
  const m = mundo();
  const a = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  const b = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(a).result, 'succeeded');
  assertEquals(b.status, 200);
  assertEquals(b.body.success, true);
  assertEquals(b.body.idempotent, true);
  assertEquals(b.body.previous_status, 'cancelled_refunded');
  assertEquals(b.body.message, MENSAGEM_JA_CANCELADA);
  assertEquals(refundDe(b).result, 'already_refunded');
  assertEquals(refundDe(b).amount, 3);
  assertEquals(m.conta.rpc, 2);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(detalhes(m.conta.registos[1]).idempotent, true);
});

Deno.test('nova tentativa depois de a Stripe falhar: devolve agora o que faltava', async () => {
  const m = mundo({ stripeFalha: 'criar_uma_vez' });
  const a = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(a).result, 'failed');
  assertEquals(refundDe(a).error, 'api_connection_error');
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.totalDevolvido(), 0);
  const b = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(b.body.idempotent, true);
  assertEquals(b.body.message, 'already cancelled — missing refund issued now');
  assertEquals(refundDe(b).result, 'succeeded');
  assertEquals(refundDe(b).amount_cents, 300);
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}`, `admin-cancel-rsv-${ID}`]);
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(m.conta.avisos.length, 1); // só o da 1.ª
});

Deno.test('resposta perdida a meio: a Stripe devolveu, a nova chamada vê-o e não devolve outra vez', async () => {
  const m = mundo({ stripeFalha: 'perder_resposta' });
  const a = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(a).result, 'failed'); // a Edge não soube; a equipa é avisada
  const b = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(b).result, 'already_refunded');
  assertEquals(m.conta.criar, 1);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('a mesma chave na Stripe falsa responde com a mesma devolução', async () => {
  const m = mundo({ reserva: reserva({ status: 'cancelled_refunded' }) });
  await tratar({ reservation_id: ID }, TOKEN, m.deps);
  const segunda = await m.deps.stripe(reserva()).devolver('pi_1', 300, chaveIdempotencia(ID), {});
  assertEquals(segunda.id, 're_1');
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('já cancelada sem direito, rejeitada ou sem comparência: resposta igual à v21, sem Stripe', async () => {
  for (const estado of ['cancelled_no_refund', 'rejected', 'no_show']) {
    const m = mundo({ reserva: reserva({ status: estado }) });
    const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
    assertEquals(r, {
      status: 200,
      body: {
        success: true,
        idempotent: true,
        reservation_id: ID,
        message: MENSAGEM_JA_CANCELADA,
        previous_status: estado,
      },
    });
    assertEquals(m.conta.lerReserva, 0);
    assertEquals(m.conta.stripe, 0);
    assertEquals(m.conta.registos.length, 0);
  }
});

// ── o pagamento vem da Stripe ───────────────────────────────────────────────────────────────────

Deno.test('pagamento trocado na reserva: não devolve e avisa a equipa', async () => {
  const m = mundo({
    reserva: reserva({ prepayment_pi: 'pi_de_um_pedido', prepayment_cents: 5000 }),
    pagamento: pagamento({
      id: 'pi_de_um_pedido',
      amount_received: 5000,
      metadata: { purpose: 'order', order_id: 'pedido-9' },
    }),
  });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r.status, 200);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).error, 'pi_mismatch');
  assertEquals(m.conta.criar, 0);
  assertEquals(m.totalDevolvido(), 0);
  assertEquals(m.conta.avisos.length, 1);
  assert(m.conta.avisos[0].resumo.includes('50,00 €'));
  assert(m.conta.avisos[0].resumo.includes('conferir antes de reembolsar'));
  assertEquals(detalhes(m.conta.registos[0]).refund_reason, 'pi_mismatch');
});

Deno.test('pagamento de OUTRA reserva do mesmo cliente: não devolve', async () => {
  const m = mundo({
    pagamento: pagamento({ metadata: { purpose: 'reservation_prepayment', reservation_id: 'outra-reserva' } }),
  });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(m.conta.criar, 0);
});

Deno.test('valor inflacionado na reserva: devolve só o que o pagamento recebeu', async () => {
  const m = mundo({ reserva: reserva({ prepayment_cents: 9000 }) });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'succeeded');
  assertEquals(refundDe(r).amount_cents, 300);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('já houve uma devolução parcial: devolve só a diferença', async () => {
  const m = mundo({ devolucoes: [{ id: 're_0', amount: 100, status: 'succeeded' }] });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'succeeded');
  assertEquals(refundDe(r).amount_cents, 200);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('pagamento ainda em processamento: nada devolvido, equipa avisada', async () => {
  const m = mundo({ pagamento: pagamento({ status: 'processing', amount_received: 0 }) });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).reason, 'payment_processing');
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('pagamento nunca cobrado: não há o que devolver, sem aviso', async () => {
  const m = mundo({ pagamento: pagamento({ status: 'requires_payment_method', amount_received: 0 }) });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'not_paid');
  assertEquals(refundDe(r).error, null);
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 0);
});

Deno.test('reserva sem pré-pagamento: not_applicable, sem ir à Stripe', async () => {
  const m = mundo({ reserva: reserva({ prepayment_pi: null, prepayment_cents: 0 }) });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'not_applicable');
  assertEquals(m.conta.stripe, 0);
  assertEquals(m.conta.avisos.length, 0);
});

Deno.test('pré-pagamento sem pagamento gravado: no_payment_intent (nome da v21) e a equipa vê', async () => {
  const m = mundo({ reserva: reserva({ prepayment_pi: null, prepayment_cents: 300 }) });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'no_payment_intent');
  assertEquals(m.conta.stripe, 0);
  assertEquals(m.conta.avisos.length, 1);
  assert(m.conta.avisos[0].resumo.includes('conferir se o cliente pagou'));
});

Deno.test('Stripe em baixo ao ler o pagamento: nada devolvido, equipa avisada', async () => {
  const m = mundo({ stripeFalha: 'ler' });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).error, 'stripe em baixo');
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('a Stripe recusa a devolução: reserva fica cancelada, equipa avisada, resposta 200', async () => {
  const m = mundo({ stripeFalha: 'criar' });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r.status, 200);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).error, 'charge_disputed');
  assertEquals(detalhes(m.conta.registos[0]).stripe_error, 'charge_disputed');
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.estado(), 'cancelled_refunded');
});

Deno.test('a devolução criada sai falhada: failed, com o id, equipa avisada', async () => {
  const m = mundo({ devolucaoFalhada: true });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).reason, 'refund_failed');
  assertEquals(refundDe(r).stripe_id, 're_1');
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('não deu para ler a reserva depois de cancelar: sem Stripe, equipa avisada', async () => {
  const m = mundo({ leituraFalha: true });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).reason, 'reserva_ilegivel');
  assertEquals(refundDe(r).error, 'base em baixo');
  assertEquals(m.conta.stripe, 0);
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(detalhes(m.conta.registos[0]).prepayment_cents, 300); // da RPC
});

Deno.test('registo em baixo não estraga a resposta', async () => {
  const m = mundo({ registoFalha: true });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r.status, 200);
  assertEquals(refundDe(r).result, 'succeeded');
});
