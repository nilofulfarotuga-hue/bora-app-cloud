// deno test --no-check --no-lock --cached-only supabase/functions/admin-cancel-reservation/logica_test.ts
// fechar-tudo-15-11: o admin cancela uma reserva paga e a Bora devolve — sem rede, com falsos.
// A RPC falsa imita admin_cancel_reservation_on_behalf_of (lida no servidor a 15/11): estados
// finais respondem idempotent=true; 'pending'/'approved' cancelam com ou sem direito (janela 2 h).
// A Stripe falsa porta-se como a verdadeira (revisão do Juiz da Claude.ai, 15/11 17:2x): por
// chave de idempotência guarda os parâmetros do 1.º pedido e a resposta que deu; a mesma chave
// com outros parâmetros dá idempotency_error; a mesma chave com os mesmos parâmetros devolve a
// resposta GUARDADA (a de quando foi criada, mesmo que a devolução tenha falhado depois); um
// pedido que nem chegou à Stripe não guarda nada; e nunca devolve mais do que o pagamento recebeu.
import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import * as parceiro from '../partner-reject-reservation/logica.ts';
import {
  type Chamador,
  centsPorDevolver,
  chaveIdempotencia,
  type Dependencias,
  devolverPrePagamento,
  type DevolucaoStripe,
  type FimDaRpc,
  httpDoErroDaRpc,
  lerPedido,
  MENSAGEM_JA_CANCELADA,
  type PagamentoStripe,
  precisaDeAviso,
  type Reserva,
  tratar,
  validarPagamento,
} from './logica.ts';

const ID = '0b5c3e2a-1d4f-4a6b-9c8d-7e6f5a4b3c2d';
const ADMIN: Chamador = { id: 'admin-1', email: 'equipa@bora.pt', papel: 'admin' };
const TOKEN = 'exemplo-de-sessao-admin'; // só tem de não vir vazio; a sessão é o falso `utilizador`
const ESTADOS_FINAIS = ['cancelled_refunded', 'cancelled_no_refund', 'rejected', 'no_show'];
const METADATA = { purpose: 'reservation_admin_cancel', reservation_id: ID };

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
  /** Estado com que a Stripe cria as devoluções novas (por defeito 'succeeded'). */
  estadoDasNovas?: string;
  /** A lista de devoluções lê-se da 1.ª vez e falha nas seguintes. */
  listaFalhaNaReleitura?: boolean;
  leituraFalha?: boolean;
  registoFalha?: boolean;
  rpc?: () => FimDaRpc;
}

/** Base, RPC e Stripe falsas. Conta tudo o que foi chamado. */
function mundo(op: Opcoes = {}) {
  let linha: Reserva | null = op.reserva === undefined ? reserva() : op.reserva;
  const horas = op.horas ?? 24;
  const pag = op.pagamento ?? pagamento();
  const devolucoes: DevolucaoStripe[] = (op.devolucoes ?? []).map((d) => ({ ...d }));
  /** Como a Stripe: por chave, os parâmetros do 1.º pedido e a resposta dada (uma cópia). */
  const porChave = new Map<string, { parametros: string; resposta: DevolucaoStripe }>();
  let criadas = 0;
  let estadoDasNovas = op.estadoDasNovas ?? 'succeeded';
  let falhasPorDar = op.stripeFalha === 'criar_uma_vez' || op.stripeFalha === 'perder_resposta' ? 1 : 0;
  const conta = {
    rpc: 0,
    lerReserva: 0,
    stripe: 0,
    listar: 0,
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

function refundDe(r: { body: Record<string, unknown> }): Record<string, unknown> {
  return r.body.refund as Record<string, unknown>;
}

function detalhes(l: Record<string, unknown>): Record<string, unknown> {
  return l.details as Record<string, unknown>;
}

// ── pedido, chave e erros ───────────────────────────────────────────────────────────────────────

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

Deno.test('chave de idempotência: uma por tentativa (admin-cancel-rsv-<id>-<devoluções já na lista>)', () => {
  assertEquals(chaveIdempotencia(ID, 0), `admin-cancel-rsv-${ID}-0`);
  assertEquals(chaveIdempotencia(ID, 2), `admin-cancel-rsv-${ID}-2`);
  assertEquals(chaveIdempotencia(ID, -1), `admin-cancel-rsv-${ID}-0`);
  assertEquals(chaveIdempotencia(ID, 1.7), `admin-cancel-rsv-${ID}-1`);
  assert(chaveIdempotencia(ID, 0) !== chaveIdempotencia(ID, 1), 'tentativas diferentes, chaves diferentes');
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
    refund: {
      result: 'succeeded',
      stripe_id: 're_1',
      amount: 3,
      amount_cents: 300,
      error: null,
      reason: null,
      stripe_status: 'succeeded',
    },
  });
  assertEquals(m.conta.rpc, 1);
  assertEquals(m.conta.criar, 1);
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}-0`]); // a lista estava vazia
  assertEquals(m.conta.metadata[0], METADATA);
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
  assertEquals(det.refund_status, 'succeeded');
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
    stripe_status: null,
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

// ── a Stripe falsa porta-se como a verdadeira ───────────────────────────────────────────────────

Deno.test('Stripe falsa = verdadeira: mesma chave e mesmos parâmetros → a resposta guardada; outros → idempotency_error', async () => {
  const m = mundo({ reserva: reserva({ status: 'cancelled_refunded' }) });
  await tratar({ reservation_id: ID }, TOKEN, m.deps); // nova tentativa: devolve com a chave -0
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}-0`]);
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
  // continua a dizer 'succeeded' — foi isto que a chave fixa da v21 apanhava numa nova tentativa.
  m.mudarNaStripe('re_1', 'failed');
  const repetida = await s.devolver('pi_1', 300, chaveIdempotencia(ID, 0), METADATA);
  assertEquals(repetida.status, 'succeeded');
  assertEquals(m.totalDevolvido(), 0); // e não mexeu dinheiro nenhum
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

Deno.test('devolução criada, depois falhou na Stripe, nova tentativa: cria OUTRA com chave nova e diz o estado real', async () => {
  const m = mundo();
  const a = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(a).result, 'succeeded');
  assertEquals(refundDe(a).stripe_id, 're_1');
  assertEquals(m.totalDevolvido(), 300);

  m.mudarNaStripe('re_1', 'failed'); // o banco do cliente recusou: a Stripe passa-a a 'failed'
  assertEquals(m.totalDevolvido(), 0);
  m.mudarEstadoDasNovas('pending'); // e a próxima fica a caminho (como no MB WAY)

  const b = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(b.status, 200);
  assertEquals(b.body.idempotent, true);
  assertEquals(b.body.message, 'already cancelled — missing refund issued now');
  assertEquals(refundDe(b).result, 'succeeded');
  assertEquals(refundDe(b).stripe_id, 're_2'); // uma devolução NOVA, não a resposta guardada da re_1
  assertEquals(refundDe(b).stripe_status, 'pending'); // o estado real dela
  assertEquals(refundDe(b).amount_cents, 300);
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}-0`, `admin-cancel-rsv-${ID}-1`]);
  assertEquals(m.conta.criar, 2);
  assertEquals(detalhes(m.conta.registos[1]).refund_id, 're_2');
  assertEquals(detalhes(m.conta.registos[1]).refund_status, 'pending');
  assertEquals(m.conta.avisos.length, 0);

  m.mudarNaStripe('re_2', 'succeeded');
  assertEquals(m.totalDevolvido(), 300); // o cliente recebe os 3 € uma vez

  // E uma 3.ª chamada já não devolve nada.
  const c = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(c).result, 'already_refunded');
  assertEquals(m.conta.criar, 2);
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
  // O 1.º pedido nem chegou à Stripe (nada guardado) e a lista continuou vazia: a mesma chave
  // serve e a Stripe cria a devolução.
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}-0`, `admin-cancel-rsv-${ID}-0`]);
  assertEquals(m.totalDevolvido(), 300);
  assertEquals(m.conta.avisos.length, 1); // só o da 1.ª
});

Deno.test('resposta perdida a meio: a Stripe devolveu, a lista relida mostra-o — already_refunded e sem alarme', async () => {
  const m = mundo({ stripeFalha: 'perder_resposta' });
  const a = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(a.status, 200);
  assertEquals(refundDe(a).result, 'already_refunded');
  assertEquals(refundDe(a).reason, 'resposta_perdida');
  assertEquals(refundDe(a).stripe_id, 're_1');
  assertEquals(refundDe(a).amount_cents, 300);
  assertEquals(refundDe(a).error, null); // não é falha: o dinheiro saiu
  assertEquals(m.conta.listar, 2); // relida antes de dar o alarme
  assertEquals(m.conta.avisos.length, 0); // ninguém é acordado à toa
  assertEquals(detalhes(m.conta.registos[0]).stripe_error, 'socket hang up'); // fica no registo
  const b = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(b).result, 'already_refunded');
  assertEquals(m.conta.criar, 1);
  assertEquals(m.totalDevolvido(), 300);
});

Deno.test('erro ao criar e nem a lista se relê: failed com o erro original, equipa avisada', async () => {
  const m = mundo({ stripeFalha: 'criar', listaFalhaNaReleitura: true });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).error, 'charge_disputed');
  assertEquals(refundDe(r).reason, 'stripe_error');
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
  assertEquals(falhada.chaves, [`admin-cancel-rsv-${ID}-1`]);
  assertEquals(a.resultado, 'failed');
  assertEquals(a.motivo, 'refund_failed');
  assertEquals(a.estadoStripe, 'failed');
  assertEquals(a.refundId, 're_1');
  assertEquals(a.cents, 0);
  assert(precisaDeAviso(a));
  // A lista diz que a re_1 (1 €) saiu e faltam 2 €; a Stripe repete a re_1: nada saiu agora.
  const parcial = comStripe(
    [{ id: 're_1', amount: 100, status: 'succeeded' }],
    { id: 're_1', amount: 100, status: 'succeeded' },
  );
  const b = await devolverPrePagamento(reserva(), parcial.deps);
  assertEquals(b.resultado, 'failed');
  assertEquals(b.motivo, 'refund_replay');
  assertEquals(b.cents, 0);
  assert(precisaDeAviso(b));
});

Deno.test('a mesma chave na Stripe falsa responde com a mesma devolução', async () => {
  const m = mundo({ reserva: reserva({ status: 'cancelled_refunded' }) });
  await tratar({ reservation_id: ID }, TOKEN, m.deps);
  const segunda = await m.deps.stripe(reserva()).devolver('pi_1', 300, chaveIdempotencia(ID, 0), METADATA);
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
  assertEquals(m.conta.chaves, [`admin-cancel-rsv-${ID}-1`]); // já havia uma na lista
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

Deno.test('a Stripe recusa a devolução: reserva fica cancelada, equipa avisada (push por reserva), resposta 200', async () => {
  const m = mundo({ stripeFalha: 'criar' });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(r.status, 200);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).error, 'charge_disputed');
  assertEquals(detalhes(m.conta.registos[0]).stripe_error, 'charge_disputed');
  assertEquals(m.conta.listar, 2); // relida antes do alarme: continuava a faltar tudo
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.conta.avisos[0].reservaId, ID);
  assertEquals(m.conta.avisos[0].detalhes.push_ref, `reservation_refund_failed:${ID}`);
  assert(m.conta.avisos[0].resumo.includes('3,00 €'));
  assertEquals(m.estado(), 'cancelled_refunded');
});

Deno.test('a devolução criada sai falhada: failed, com o id, equipa avisada', async () => {
  const m = mundo({ devolucaoFalhada: true });
  const r = await tratar({ reservation_id: ID }, TOKEN, m.deps);
  assertEquals(refundDe(r).result, 'failed');
  assertEquals(refundDe(r).reason, 'refund_failed');
  assertEquals(refundDe(r).stripe_id, 're_1');
  assertEquals(refundDe(r).stripe_status, 'failed');
  assertEquals(m.conta.avisos.length, 1);
  assertEquals(m.conta.avisos[0].detalhes.refund_id, 're_1');
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
