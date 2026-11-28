// deno test --no-lock --cached-only supabase/functions/partner-reject-reservation/logica_test.ts
// fechar-tudo-15-11: o parceiro rejeita uma reserva paga e a Bora devolve — sem rede, com falsos.
// A Stripe falsa porta-se como a verdadeira (revisão do Juiz da Claude.ai, 15/11 17:2x; a mesma
// do admin-cancel-reservation/logica_test.ts): por chave de idempotência guarda os parâmetros do
// 1.º pedido e a resposta que deu; a mesma chave com outros parâmetros dá idempotency_error; a
// mesma chave com os mesmos parâmetros devolve a resposta GUARDADA (a de quando foi criada, mesmo
// que a devolução tenha falhado depois); um pedido que nem chegou à Stripe não guarda nada; e
// nunca devolve mais do que o pagamento recebeu.
import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  type AvisoEquipa,
  avisoDeFalha,
  centsPorDevolver,
  chaveIdempotencia,
  type Dependencias,
  devolverPrePagamento,
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
const METADATA = { purpose: 'reservation_partner_reject', reservation_id: ID };

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
  /** criar_uma_vez: a 1.ª devolução lança antes de chegar à Stripe; perder_resposta: a Stripe
   *  faz a 1.ª devolução mas a resposta perde-se pelo caminho. */
  stripeFalha?: 'ler' | 'criar' | 'criar_uma_vez' | 'perder_resposta';
  devolucaoFalhada?: boolean;
  /** Estado com que a Stripe cria as devoluções novas (por defeito 'succeeded'). */
  estadoDasNovas?: string;
  /** A lista de devoluções lê-se da 1.ª vez e falha nas seguintes. */
  listaFalhaNaReleitura?: boolean;
  registoFalha?: boolean;
  rpc?: (mudarEstado: (s: string) => void) => FimDaRpc;
}

/** Base, RPC e Stripe falsas. Conta tudo o que foi chamado. */
function mundo(op: Opcoes = {}) {
  let linha: Reserva | null = op.reserva === undefined ? reserva() : op.reserva;
  const pag = op.pagamento ?? pagamento();
  const devolucoes: DevolucaoStripe[] = (op.devolucoes ?? []).map((d) => ({ ...d }));
  /** Como a Stripe: por chave, os parâmetros do 1.º pedido e a resposta dada (uma cópia). */
  const porChave = new Map<string, { parametros: string; resposta: DevolucaoStripe }>();
  let criadas = 0;
  let estadoDasNovas = op.estadoDasNovas ?? 'succeeded';
  let falhasPorDar = op.stripeFalha === 'criar_uma_vez' || op.stripeFalha === 'perder_resposta' ? 1 : 0;
  const conta = {
    rpc: 0,
    stripe: 0,
    listar: 0,
    criar: 0,
    chaves: [] as string[],
    metadata: [] as Record<string, string>[],
    contasPedidas: [] as string[],
    registos: [] as Record<string, unknown>[],
    avisos: [] as AvisoEquipa[],
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
    stripe: (r) => {
      conta.stripe++;
      conta.contasPedidas.push(String(r.stripe_account));
      return {
        conta: r.stripe_account === 'empresa' ? 'empresa' : 'pessoal',
        lerPagamento: () =>
          op.stripeFalha === 'ler' ? Promise.reject(new Error('stripe em baixo')) : Promise.resolve(pag),
        listarDevolucoes: () => {
          conta.listar++;
          if (op.listaFalhaNaReleitura && conta.listar > 1) {
            return Promise.reject(new Error('stripe em baixo na lista'));
          }
          return Promise.resolve(devolucoes.map((d) => ({ ...d })));
        },
        devolver: (pi, cents, chave, metadata) => {
          conta.criar++;
          conta.chaves.push(chave);
          conta.metadata.push(metadata);
          if (op.stripeFalha === 'criar') return Promise.reject(new Error('charge_disputed'));
          if (op.stripeFalha === 'criar_uma_vez' && falhasPorDar > 0) {
            falhasPorDar--;
            return Promise.reject(new Error('api_connection_error')); // nem chegou à Stripe
          }
          const parametros = JSON.stringify({ pi, cents, metadata });
          const guardado = porChave.get(chave);
          if (guardado) {
            if (guardado.parametros !== parametros) {
              return Promise.reject(
                new Error(
                  `idempotency_error: Keys for idempotent requests can only be used with the same ` +
                    `parameters they were first used with (${chave})`,
                ),
              );
            }
            return Promise.resolve({ ...guardado.resposta }); // a resposta de quando foi criada
          }
          const feito = devolucoes
            .filter((d) => d.status !== 'failed' && d.status !== 'canceled')
            .reduce((s, d) => s + d.amount, 0);
          if (feito + cents > (pag.amount_received ?? 0)) {
            return Promise.reject(new Error('amount_too_large')); // a Stripe nunca passa do recebido
          }
          criadas++;
          const nova: DevolucaoStripe = {
            id: `re_${criadas}`,
            amount: cents,
            status: op.devolucaoFalhada ? 'failed' : estadoDasNovas,
          };
          devolucoes.push(nova);
          porChave.set(chave, { parametros, resposta: { ...nova } });
          if (op.stripeFalha === 'perder_resposta' && falhasPorDar > 0) {
            falhasPorDar--;
            return Promise.reject(new Error('socket hang up')); // feita na Stripe, resposta perdida
          }
          return Promise.resolve({ ...nova });
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
  /** O que a Stripe faz depois, sem ninguém chamar (ex.: o banco do cliente recusa a devolução). */
  const mudarNaStripe = (id: string, status: string) => {
    const d = devolucoes.find((x) => x.id === id);
    if (!d) throw new Error(`devolução ${id} não existe`);
    d.status = status;
  };
  const mudarEstadoDasNovas = (status: string) => {
    estadoDasNovas = status;
  };
  return { deps, conta, totalDevolvido, mudarNaStripe, mudarEstadoDasNovas, estado: () => linha?.status };
}

function detalhes(l: Record<string, unknown>): Record<string, unknown> {
  return l.details as Record<string, unknown>;
}

// ── pedido, chave e regras ──────────────────────────────────────────────────────────────────────

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

Deno.test('chave de idempotência: uma por tentativa (reserva-recusa-<id>-<devoluções já na lista>)', () => {
  assertEquals(chaveIdempotencia(ID, 0), `reserva-recusa-${ID}-0`);
  assertEquals(chaveIdempotencia(ID, 2), `reserva-recusa-${ID}-2`);
  assertEquals(chaveIdempotencia(ID, -1), `reserva-recusa-${ID}-0`);
  assertEquals(chaveIdempotencia(ID, 1.7), `reserva-recusa-${ID}-1`);
  assertEquals(chaveIdempotencia(ID, Number.NaN), `reserva-recusa-${ID}-0`);
  assert(chaveIdempotencia(ID, 0) !== chaveIdempotencia(ID, 1), 'tentativas diferentes, chaves diferentes');
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

// ── o caminho feliz ─────────────────────────────────────────────────────────────────────────────

Deno.test('dono rejeita reserva paga: RPC uma vez, devolve 3 € com a chave e regista', async () => {
  const m = mundo();
  const r = await tratar({ reservation_id: ID, reason: 'Cozinha fechada' }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.idempotent, false);
  assertEquals(r.body.new_status, 'rejected_refunded');
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-0`]); // a lista estava vazia
  assertEquals(m.conta.metadata[0], METADATA);
  assertEquals(m.conta.contasPedidas, ['empresa']); // a conta onde entrou
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(m.conta.registos.length, 1);
  assertEquals(m.conta.registos[0].action, 'reservation_partner_reject_complete');
  assertEquals(m.conta.registos[0].admin_id, null);
  const det = detalhes(m.conta.registos[0]);
  assertEquals(det.partner_user_id, PARCEIRO);
  assertEquals(det.refund_result, 'succeeded');
  assertEquals(det.stripe_account, 'empresa');
  assertEquals(det.refund_id, 're_1');
  assertEquals(det.refund_status, 'succeeded');
  assertEquals(det.reason, 'Cozinha fechada');
  assertEquals(m.conta.avisos.length, 0);
  assertEquals(m.estado(), 'rejected_refunded');
});

// ── quem chama ──────────────────────────────────────────────────────────────────────────────────

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

// ── a Stripe falsa porta-se como a verdadeira ───────────────────────────────────────────────────

Deno.test('Stripe falsa = verdadeira: mesma chave e mesmos parâmetros → a resposta guardada; outros → idempotency_error', async () => {
  const m = mundo({ reserva: reserva({ status: 'rejected_refunded' }) });
  await tratar({ reservation_id: ID }, m.deps); // nova tentativa: devolve com a chave -0
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-0`]);
  const s = m.deps.stripe(reserva());
  const segunda = await s.devolver('pi_1', 300, chaveIdempotencia(ID, 0), METADATA);
  assertEquals(segunda.id, 're_1'); // mesma chave → a mesma devolução
  assertEquals(m.totalDevolvido(), 300);
  await assertRejects(
    () => s.devolver('pi_1', 200, chaveIdempotencia(ID, 0), METADATA),
    Error,
    'idempotency_error',
  );
  // A resposta guardada é a de quando foi criada: se a devolução falhar depois, a mesma chave
  // continua a dizer 'succeeded' — foi isto que a chave fixa reserva-recusa-<id> apanhava numa
  // nova tentativa.
  m.mudarNaStripe('re_1', 'failed');
  const repetida = await s.devolver('pi_1', 300, chaveIdempotencia(ID, 0), METADATA);
  assertEquals(repetida.status, 'succeeded');
  assertEquals(m.totalDevolvido(), 0); // e não mexeu dinheiro nenhum
});

// ── novas tentativas ────────────────────────────────────────────────────────────────────────────

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
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-0`]);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('devolução criada, depois falhou na Stripe, nova tentativa: cria OUTRA com chave nova e diz o estado real', async () => {
  const m = mundo();
  const a = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(a.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(detalhes(m.conta.registos[0]).refund_id, 're_1');
  assertEquals(m.totalDevolvido(), 300);

  m.mudarNaStripe('re_1', 'failed'); // o banco do cliente recusou: a Stripe passa-a a 'failed'
  assertEquals(m.totalDevolvido(), 0);
  m.mudarEstadoDasNovas('pending'); // e a próxima fica a caminho (como no MB WAY)

  const b = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(b.status, 200);
  assertEquals(b.body.idempotent, true);
  assertEquals(b.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  // Primeiro o dinheiro: com a chave fixa, a Stripe respondia com a re_1 GUARDADA ('succeeded')
  // e o "succeeded" acima era falso — a resposta era igual, mas nenhuma devolução nova existia.
  const det = detalhes(m.conta.registos[1]);
  assertEquals(det.refund_id, 're_2'); // uma devolução NOVA, não a resposta guardada da re_1
  assertEquals(det.refund_status, 'pending'); // o estado real dela
  m.mudarNaStripe('re_2', 'succeeded');
  assertEquals(m.totalDevolvido(), 300); // o cliente recebe os 3 € uma vez
  // Depois o como: a RPC não se repete e a 2.ª tentativa usou outra chave.
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-0`, `reserva-recusa-${ID}-1`]);
  assertEquals(m.conta.criar, 2);
  assertEquals(det.idempotent, true);
  assertEquals(m.conta.avisos.length, 0);

  // E uma 3.ª chamada já não devolve nada.
  const c = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(c.body.refund, { result: 'already_refunded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.criar, 2);
});

Deno.test('reserva já rejeitada e nada devolvido ainda: devolve sem repetir a RPC', async () => {
  const m = mundo({ reserva: reserva({ status: 'rejected_refunded' }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.idempotent, true);
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.rpc, 0);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-0`]);
});

Deno.test('nova tentativa depois de a Stripe falhar: devolve agora o que faltava', async () => {
  const m = mundo({ stripeFalha: 'criar_uma_vez' });
  const a = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(a.status, 200);
  assertEquals(a.body.refund, { result: 'failed', amount_cents: 0, amount: 0 });
  assertEquals(detalhes(m.conta.registos[0]).stripe_error, 'api_connection_error');
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.totalDevolvido(), 0);
  assertEquals(m.estado(), 'rejected_refunded');
  const b = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(b.body.idempotent, true);
  assertEquals(b.body.refund, { result: 'succeeded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.rpc, 1);
  // O 1.º pedido nem chegou à Stripe (nada guardado) e a lista continuou vazia: a mesma chave
  // serve e a Stripe cria a devolução.
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-0`, `reserva-recusa-${ID}-0`]);
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(m.conta.avisos.length, 1); // só o da 1.ª
});

Deno.test('resposta perdida a meio: a Stripe devolveu, a lista relida mostra-o — already_refunded e sem alarme', async () => {
  const m = mundo({ stripeFalha: 'perder_resposta' });
  const a = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(a.status, 200);
  assertEquals(a.body.refund, { result: 'already_refunded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.listar, 2); // relida antes de dar o alarme
  assertEquals(m.conta.avisos.length, 0); // ninguém é acordado à toa
  const det = detalhes(m.conta.registos[0]);
  assertEquals(det.refund_result, 'already_refunded');
  assertEquals(det.refund_reason, 'resposta_perdida');
  assertEquals(det.refund_id, 're_1');
  assertEquals(det.refund_status, 'succeeded');
  assertEquals(det.stripe_error, 'socket hang up'); // fica no registo
  const b = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(b.body.refund, { result: 'already_refunded', amount_cents: 300, amount: 3 });
  assertEquals(m.conta.criar, 1);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('erro ao criar e nem a lista se relê: failed com o erro original, equipa avisada', async () => {
  const m = mundo({ stripeFalha: 'criar', listaFalhaNaReleitura: true });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.body.refund, { result: 'failed', amount_cents: 0, amount: 0 });
  const det = detalhes(m.conta.registos[0]);
  assertEquals(det.refund_reason, 'stripe_error');
  assertEquals(det.stripe_error, 'charge_disputed');
  assertEquals(m.conta.listar, 2);
  assertEquals(m.conta.avisos.length, 1);
});

Deno.test('resposta repetida com o id já na lista: vale o estado da lista e nada saiu agora', async () => {
  const comStripe = (lista: DevolucaoStripe[], resposta: DevolucaoStripe) => {
    const chaves: string[] = [];
    return {
      chaves,
      deps: {
        stripe: () => ({
          conta: 'empresa',
          lerPagamento: () => Promise.resolve(pagamento()),
          listarDevolucoes: () => Promise.resolve(lista.map((d) => ({ ...d }))),
          devolver: (_pi: string, _cents: number, chave: string) => {
            chaves.push(chave);
            return Promise.resolve({ ...resposta });
          },
        }),
      },
    };
  };
  // A lista diz que a re_1 falhou; a Stripe responde com a re_1 guardada ('succeeded').
  const falhada = comStripe(
    [{ id: 're_1', amount: 300, status: 'failed' }],
    { id: 're_1', amount: 300, status: 'succeeded' },
  );
  const a = await devolverPrePagamento(reserva(), falhada.deps);
  assertEquals(falhada.chaves, [`reserva-recusa-${ID}-1`]);
  assertEquals(a.resultado, 'failed');
  assertEquals(a.motivo, 'refund_failed');
  assertEquals(a.estadoStripe, 'failed');
  assertEquals(a.refundId, 're_1');
  assertEquals(a.cents, 0);
  // A lista diz que a re_1 (1 €) saiu e faltam 2 €; a Stripe repete a re_1: nada saiu agora.
  const parcial = comStripe(
    [{ id: 're_1', amount: 100, status: 'succeeded' }],
    { id: 're_1', amount: 100, status: 'succeeded' },
  );
  const b = await devolverPrePagamento(reserva(), parcial.deps);
  assertEquals(b.resultado, 'failed');
  assertEquals(b.motivo, 'refund_replay');
  assertEquals(b.cents, 0);
  assert(avisoDeFalha(reserva(), b).resumo.includes('reembolso antigo e nada saiu agora'));
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

// ── o pagamento vem da Stripe ───────────────────────────────────────────────────────────────────

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

Deno.test('já houve uma devolução parcial: devolve só a diferença', async () => {
  const m = mundo({ devolucoes: [{ id: 're_0', amount: 100, status: 'succeeded' }] });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.body.refund, { result: 'succeeded', amount_cents: 200, amount: 2 });
  assertEquals(m.conta.chaves, [`reserva-recusa-${ID}-1`]); // já havia uma na lista
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('a Stripe recusa a devolução: reserva fica rejeitada, equipa avisada (push por reserva), resposta 200', async () => {
  const m = mundo({ stripeFalha: 'criar' });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.status, 200);
  assertEquals(r.body.refund, { result: 'failed', amount_cents: 0, amount: 0 });
  assertEquals(m.conta.listar, 2); // relida antes do alarme: continuava a faltar tudo
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.conta.avisos[0].reservaId, ID);
  assertEquals(m.conta.avisos[0].detalhes.push_ref, `reservation_refund_failed:${ID}`);
  assertEquals(m.conta.avisos[0].detalhes.origem, 'partner-reject-reservation');
  assert(m.conta.avisos[0].resumo.includes('3,00 €'));
  assertEquals(m.conta.registos.length, 1);
  const det = detalhes(m.conta.registos[0]);
  assertEquals(det.refund_reason, 'stripe_error');
  assertEquals(det.stripe_error, 'charge_disputed');
  assertEquals(m.estado(), 'rejected_refunded');
});

Deno.test('a devolução criada sai falhada: failed, com o id, equipa avisada', async () => {
  const m = mundo({ devolucaoFalhada: true });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals(r.body.refund, { result: 'failed', amount_cents: 0, amount: 0 });
  const det = detalhes(m.conta.registos[0]);
  assertEquals(det.refund_reason, 'refund_failed');
  assertEquals(det.refund_id, 're_1');
  assertEquals(det.refund_status, 'failed');
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.conta.avisos[0].detalhes.refund_id, 're_1');
  assertEquals(m.conta.avisos[0].detalhes.refund_status, 'failed');
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
  assertEquals(m.conta.stripe, 0);
  assertEquals(m.conta.criar, 0);
  assertEquals(m.conta.avisos.length, 0);
});

Deno.test('pré-pagamento sem pagamento gravado: a equipa vê', async () => {
  const m = mundo({ reserva: reserva({ prepayment_pi: null, prepayment_cents: 300 }) });
  const r = await tratar({ reservation_id: ID }, m.deps);
  assertEquals((r.body.refund as Record<string, unknown>).result, 'failed');
  assertEquals(m.conta.stripe, 0);
  assertEquals(m.conta.avisos.length, 1);
  assert(m.conta.avisos[0].resumo.includes('conferir se o cliente pagou'));
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
    estadoStripe: null,
  });
  assertEquals(a.reservaId, ID);
  assert(a.resumo.includes('3,00 €'));
  assert(a.resumo.includes('conferir antes de reembolsar'));
  assertEquals(a.detalhes.push_ref, `reservation_refund_failed:${ID}`);
});
