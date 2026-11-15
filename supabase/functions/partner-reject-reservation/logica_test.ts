// deno test --no-lock supabase/functions/partner-reject-reservation/logica_test.ts
// fechar-tudo-15-11: o parceiro rejeita uma reserva paga e a Bora devolve — sem rede, com falsos.
// A Stripe falsa guarda as devoluções por chave de idempotência, como a verdadeira.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  avisoDeFalha,
  centsPorDevolver,
  chaveIdempotencia,
  type Dependencias,
  type DevolucaoStripe,
  erroDaRpc,
  type FimDaRpc,
  lerPedido,
  type PagamentoStripe,
  type Reserva,
  tratar,
  validarPagamento,
} from './logica.ts';

const ID = '0b5c3e2a-1d4f-4a6b-9c8d-7e6f5a4b3c2d';
const PARCEIRO = 'parceiro-1';

function reserva(extra: Partial<Reserva> = {}): Reserva {
  return {
    id: ID,
    restaurant_id: 'rest-1',
    status: 'pending',
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
  utilizador?: string | null;
  pagamento?: PagamentoStripe;
  devolucoes?: DevolucaoStripe[];
  stripeFalha?: 'ler' | 'criar';
  registoFalha?: boolean;
  rpc?: (mudarEstado: (s: string) => void) => FimDaRpc;
}

/** Base, RPC e Stripe falsas. Conta tudo o que foi chamado. */
function mundo(op: Opcoes = {}) {
  let linha: Reserva | null = op.reserva === undefined ? reserva() : op.reserva;
  const devolucoes: DevolucaoStripe[] = [...(op.devolucoes ?? [])];
  const porChave = new Map<string, DevolucaoStripe>();
  const conta = {
    rpc: 0,
    criar: 0,
    chaves: [] as string[],
    metadata: [] as Record<string, string>[],
    registos: [] as Record<string, unknown>[],
    avisos: [] as unknown[],
  };
  const mudarEstado = (s: string) => {
    if (linha) linha = { ...linha, status: s };
  };
  const deps: Dependencias = {
    utilizador: () => Promise.resolve(op.utilizador === null ? null : { id: op.utilizador ?? PARCEIRO }),
    lerReserva: (id) => Promise.resolve(linha && linha.id === id ? { ...linha } : null),
    eDono: (_restaurante, uid) => Promise.resolve(uid === PARCEIRO),
    rejeitarPelaRpc: (_id, _motivo) => {
      conta.rpc++;
      if (op.rpc) return Promise.resolve<FimDaRpc>(op.rpc(mudarEstado));
      if (!linha || linha.status !== 'pending') {
        return Promise.resolve<FimDaRpc>({ ok: false, mensagem: `reservation_not_pending: ${linha?.status}` });
      }
      mudarEstado('rejected_refunded');
      return Promise.resolve<FimDaRpc>({ ok: true, status: 'rejected_refunded' });
    },
    stripe: () => ({
      conta: 'empresa',
      lerPagamento: () =>
        op.stripeFalha === 'ler'
          ? Promise.reject(new Error('stripe em baixo'))
          : Promise.resolve(op.pagamento ?? pagamento()),
      listarDevolucoes: () => Promise.resolve([...devolucoes]),
      devolver: (_pi, cents, chave, metadata) => {
        conta.criar++;
        conta.chaves.push(chave);
        conta.metadata.push(metadata);
        if (op.stripeFalha === 'criar') return Promise.reject(new Error('charge_disputed'));
        const ja = porChave.get(chave);
        if (ja) return Promise.resolve(ja);
        const nova = { id: `re_${porChave.size + 1}`, amount: cents, status: 'succeeded' };
        porChave.set(chave, nova);
        devolucoes.push(nova);
        return Promise.resolve(nova);
      },
    }),
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
  const totalDevolvido = () => devolucoes.reduce((s, d) => s + d.amount, 0);
  return { deps, conta, totalDevolvido, estado: () => linha?.status };
}

Deno.test('pedido: id obrigatório, motivo limpo e cortado', () => {
  assertEquals(lerPedido(null), { erro: 'invalid_body' });
  assertEquals(lerPedido([]), { erro: 'invalid_body' });
  assertEquals(lerPedido({ reservation_id: 'abc' }), { erro: 'invalid_reservation_id' });
  assertEquals(lerPedido({ reservation_id: 12 }), { erro: 'invalid_reservation_id' });
  assertEquals(
    lerPedido({ reservation_id: ` ${ID.toUpperCase()} `, reason: '  cozinha cheia  ' }),
    { reservationId: ID, motivo: 'cozinha cheia' },
  );
  assertEquals(lerPedido({ reservation_id: ID, reason: '   ' }), { reservationId: ID, motivo: null });
  const longo = lerPedido({ reservation_id: ID, reason: 'x'.repeat(900) });
  assert('motivo' in longo && longo.motivo?.length === 500);
});

Deno.test('chave de idempotência: reserva-recusa-<id>', () => {
  assertEquals(chaveIdempotencia(ID), `reserva-recusa-${ID}`);
});

Deno.test('erros da RPC viram código HTTP', () => {
  assertEquals(erroDaRpc('reservation_not_pending: approved'), { http: 409, error: 'reservation_not_pending' });
  assertEquals(erroDaRpc('not_your_restaurant'), { http: 403, error: 'not_your_restaurant' });
  assertEquals(erroDaRpc('reservation_not_found'), { http: 404, error: 'reservation_not_found' });
  assertEquals(erroDaRpc('auth_required'), { http: 401, error: 'auth_required' });
  assertEquals(erroDaRpc('convidado_sem_conta: entra ou cria conta'), { http: 403, error: 'convidado_sem_conta' });
  assertEquals(erroDaRpc('qualquer outra coisa'), { http: 500, error: 'rpc_error' });
});

Deno.test('só conta o pagamento DESTA reserva, e cobrado', () => {
  assertEquals(validarPagamento(ID, pagamento()), 'ok');
  assertEquals(
    validarPagamento(ID, pagamento({ metadata: { purpose: 'reservation_prepayment', reservation_id: 'outra' } })),
    'pi_mismatch',
  );
  assertEquals(validarPagamento(ID, pagamento({ metadata: { purpose: 'order', reservation_id: ID } })), 'pi_mismatch');
  assertEquals(validarPagamento(ID, pagamento({ metadata: null })), 'pi_mismatch');
  assertEquals(validarPagamento(ID, pagamento({ status: 'processing' })), 'payment_processing');
  assertEquals(
    validarPagamento(ID, pagamento({ status: 'requires_payment_method', amount_received: 0 })),
    'not_paid',
  );
  assertEquals(validarPagamento(ID, pagamento({ amount_received: 0 })), 'not_paid');
});

Deno.test('falta devolver = recebido menos devoluções feitas ou a caminho', () => {
  assertEquals(centsPorDevolver(pagamento(), []).falta, 300);
  assertEquals(centsPorDevolver(pagamento(), [{ id: 're_1', amount: 300, status: 'succeeded' }]).falta, 0);
  assertEquals(centsPorDevolver(pagamento(), [{ id: 're_1', amount: 300, status: 'pending' }]).falta, 0);
  assertEquals(centsPorDevolver(pagamento(), [{ id: 're_1', amount: 300, status: 'failed' }]).falta, 300);
  assertEquals(centsPorDevolver(pagamento(), [{ id: 're_1', amount: 100, status: 'succeeded' }]).falta, 200);
  assertEquals(centsPorDevolver(pagamento(), [{ id: 're_1', amount: 500, status: 'succeeded' }]).falta, 0);
});

Deno.test('dono rejeita reserva paga: RPC uma vez, devolve 3 € com a chave e regista', async () => {
  const m = mundo();
  const r = await tratar({ reservation_id: ID, reason: 'Cozinha fechada' }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.idempotent, false);
  assertEquals(r.body.new_status, 'rejected_refunded');
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}`]);
  assertEquals(m.conta.metadata[0], { purpose: 'reservation_partner_reject', reservation_id: ID });
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(m.conta.registos.length, 1);
  assertEquals(m.conta.registos[0].action, 'reservation_partner_reject_complete');
  assertEquals(m.conta.registos[0].admin_id, null);
  const det = m.conta.registos[0].details as Record<string, unknown>;
  assertEquals(det.partner_user_id, PARCEIRO);
  assertEquals(det.refund_result, 'succeeded');
  assertEquals(det.reason, 'Cozinha fechada');
  assertEquals(m.conta.avisos.length, 0);
  assertEquals(m.estado(), 'rejected_refunded');
});

Deno.test('quem não é dono não mexe em nada', async () => {
  const m = mundo({ utilizador: 'intruso-1' });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 403);
  assertEquals(r.body.error, 'not_your_restaurant');
  assertEquals(m.conta.rpc, 0);
  assertEquals(m.conta.criar, 0);
  assertEquals(m.estado(), 'pending');
});

Deno.test('quem não é dono também não força nova tentativa numa reserva já rejeitada', async () => {
  const m = mundo({ utilizador: 'intruso-1', reserva: reserva({ status: 'rejected_refunded' }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 403);
  assertEquals(m.conta.criar, 0);
});

Deno.test('sem sessão: 401 e nada muda', async () => {
  const m = mundo({ utilizador: null });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 401);
  assertEquals(m.conta.rpc, 0);
});

Deno.test('pedido inválido: 400 antes de tudo', async () => {
  const m = mundo();
  const r = await tratar({ reservation_id: 'x' }, m.deps);
  assertEquals(r.status, 400);
  assertEquals(m.conta.rpc, 0);
});

Deno.test('reserva que não existe: 404', async () => {
  const m = mundo({ reserva: null });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 404);
  assertEquals(r.body.error, 'reservation_not_found');
});

Deno.test('duas chamadas seguidas: uma devolução só', async () => {
  const m = mundo();
  const a = await tratar({ reservation_id: ID }, m.deps);
  const b = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(a.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(b.status, 200);
  assertEquals(b.body.idempotent, true);
  assertEquals(b.body.refund, { result: 'already_refunded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('nova tentativa depois de a Stripe falhar: devolve sem repetir a RPC', async () => {
  const m = mundo({ reserva: reserva({ status: 'rejected_refunded' }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.idempotent, true);
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.rpc, 0);
  assertEquals(m.conta.criar, 1);
});

Deno.test('a mesma chave na Stripe nunca devolve duas vezes (resposta perdida a meio)', async () => {
  // 1.ª chamada devolveu mas a lista ainda não a mostrava: a Stripe responde com a mesma devolução.
  const m = mundo({ reserva: reserva({ status: 'rejected_refunded' }) });
  await tratar({ reservation_id: ID }, m.deps);
  const segunda = await m.deps.stripe(reserva()).devolver('pi_1', 300, chaveIdempotencia(ID), {});
  assertEquals(segunda.id, 're_1');
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('corrida: outra chamada rejeitou entre a leitura e a RPC → segue como nova tentativa', async () => {
  const m = mundo({
    rpc: (mudar) => {
      mudar('rejected_refunded');
      return { ok: false, mensagem: 'reservation_not_pending: rejected_refunded' };
    },
  });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.idempotent, true);
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('corrida: outra chamada ACEITOU entretanto → 409 e nada se devolve', async () => {
  const m = mundo({
    rpc: (mudar) => {
      mudar('approved');
      return { ok: false, mensagem: 'reservation_not_pending: approved' };
    },
  });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 409);
  assertEquals(r.body, { error: 'reservation_not_pending', status: 'approved' });
  assertEquals(m.conta.criar, 0);
});

Deno.test('outro erro da RPC: devolve o código e não toca na Stripe', async () => {
  const m = mundo({ rpc: () => ({ ok: false, mensagem: 'convidado_sem_conta: entra ou cria conta' }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 403);
  assertEquals(r.body.error, 'convidado_sem_conta');
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.registos.length, 0);
});

Deno.test('reserva já aceite: 409 e nada muda', async () => {
  const m = mundo({ reserva: reserva({ status: 'approved' }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 409);
  assertEquals(r.body, { error: 'reservation_not_pending', status: 'approved' });
  assertEquals(m.conta.rpc, 0);
  assertEquals(m.conta.criar, 0);
});

Deno.test('pagamento trocado na reserva (colunas que o cliente pode mudar): não devolve e avisa', async () => {
  const m = mundo({
    reserva: reserva({ prepayment_pi: 'pi_de_um_pedido', prepayment_cents: 5000 }),
    pagamento: pagamento({
      id: 'pi_de_um_pedido',
      amount_received: 5000,
      metadata: { purpose: 'order', order_id: 'pedido-9' },
    }),
  });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.refund, { result: 'failed', amount_cents: 0, amount: 0 });
  assertEquals(m.conta.criar, 0);
  assertEquals(m.totalDevolvido(), 0);
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('valor inflacionado na reserva: devolve só o que o pagamento recebeu', async () => {
  const m = mundo({ reserva: reserva({ prepayment_cents: 9000 }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('a Stripe recusa a devolução: reserva fica rejeitada, equipa avisada, resposta 200', async () => {
  const m = mundo({ stripeFalha: 'criar' });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.refund, { result: 'failed', amount_cents: 0, amount: 0 });
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.conta.registos.length, 1);
  const det = m.conta.registos[0].details as Record<string, unknown>;
  assertEquals(det.refund_reason, 'stripe_error');
  assertEquals(det.stripe_error, 'charge_disputed');
  assertEquals(m.estado(), 'rejected_refunded');
});

Deno.test('Stripe em baixo ao ler o pagamento: nada devolvido, equipa avisada', async () => {
  const m = mundo({ stripeFalha: 'ler' });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals((r.body.refund as Record<string, unknown>).result, 'failed');
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('pagamento ainda em processamento: nada devolvido, equipa avisada', async () => {
  const m = mundo({ pagamento: pagamento({ status: 'processing', amount_received: 0 }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals((r.body.refund as Record<string, unknown>).result, 'failed');
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('pagamento nunca cobrado: não há o que devolver, sem aviso', async () => {
  const m = mundo({ pagamento: pagamento({ status: 'requires_payment_method', amount_received: 0 }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.body.refund, { result: 'not_paid', amount_cents: 0, amount: 0 });
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 0);
});

Deno.test('reserva sem pré-pagamento: rejeita sem ir à Stripe', async () => {
  const m = mundo({ reserva: reserva({ prepayment_pi: null, prepayment_cents: 0 }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.body.refund, { result: 'not_applicable', amount_cents: 0, amount: 0 });
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 0);
});

Deno.test('pré-pagamento sem pagamento gravado: a equipa vê', async () => {
  const m = mundo({ reserva: reserva({ prepayment_pi: null, prepayment_cents: 300 }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals((r.body.refund as Record<string, unknown>).result, 'failed');
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('registo em baixo não estraga a resposta', async () => {
  const m = mundo({ registoFalha: true });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
});

Deno.test('aviso à equipa diz o valor e o que fazer', () => {
  const a = avisoDeFalha(reserva(), {
    resultado: 'failed',
    cents: 0,
    conta: 'empresa',
    refundId: null,
    motivo: 'pi_mismatch',
    erro: null,
  });
  assertEquals(a.reservaId, ID);
  assert(a.resumo.includes('3,00 €'));
  assert(a.resumo.includes('conferir antes de reembolsar'));
});
