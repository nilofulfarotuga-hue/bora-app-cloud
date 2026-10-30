// deno test supabase/functions/_shared/gorjeta_test.ts
// Missão gorjetas-taxa-2026-10-30: a gorjeta do carrinho cobrada no mesmo pagamento nunca entra nas
// contas da compra (cancelamentos, taxa), a charge-tip nunca a cobra outra vez e a devolução é sempre
// a gorjeta inteira, uma só vez. Stripe e banco de brincar (nada sai do PC).
import { gorjetaNoPagamento, repartirReembolso, type Pago } from './cobranca_stripe.ts';
import {
  devolverGorjetasDoPedido, devolverUmaGorjeta, gorjetaJaVaiNoCartao, type GorjetaParaDevolver,
} from './gorjeta_devolver.ts';

function igual(a: unknown, b: unknown, msg: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
}

const PI = 'pi_pedido';
const g = (amount_cents: number, status: string, pi: string | null = PI, devolvida_para: string | null = null) =>
  ({ amount_cents, status, stripe_payment_intent_id: pi, devolvida_para });

// Pedido de 10,00 € (8,00 cartão + 2,00 saldo) com 2,00 € de gorjeta no mesmo pagamento:
// a Stripe cobrou 10,00 (8 da compra + 2 de gorjeta).
function pago(recebido: number, devolvido: number, gorjetas: ReturnType<typeof g>[]): Pago {
  const gj = gorjetaNoPagamento(gorjetas, PI);
  return {
    piId: PI, stripeCents: Math.max(0, recebido - gj.total),
    stripeDisponivelCents: Math.max(0, recebido - devolvido - gj.porDevolverNaStripe),
    walletCents: 200, tokensCents: 0, tokensValorCents: 0, tokensCount: 0, totalCents: 1000,
    piStatus: 'succeeded', gorjetaJuntoCents: gj.total,
  };
}

Deno.test('gorjeta paga junto: fora da compra e por devolver na Stripe', () => {
  igual(gorjetaNoPagamento([g(200, 'succeeded')], PI), { total: 200, porDevolverNaStripe: 200 }, 'succeeded');
});

Deno.test('gorjeta já devolvida ao meio: continua fora da compra, já não está na Stripe', () => {
  igual(gorjetaNoPagamento([g(200, 'refunded', PI, 'meio')], PI), { total: 200, porDevolverNaStripe: 0 }, 'refunded meio');
});

Deno.test('gorjeta devolvida ao saldo: o dinheiro ficou na Stripe e não pode ir para a compra', () => {
  igual(gorjetaNoPagamento([g(200, 'refunded', PI, 'carteira')], PI), { total: 200, porDevolverNaStripe: 200 }, 'refunded carteira');
});

Deno.test('MB Way por pagar só conta se já leva o PI deste pedido', () => {
  igual(gorjetaNoPagamento([g(200, 'pending', null)], PI), { total: 0, porDevolverNaStripe: 0 }, 'sem PI');
  igual(gorjetaNoPagamento([g(200, 'pending', 'pi_outro')], PI), { total: 0, porDevolverNaStripe: 0 }, 'outro PI');
  igual(gorjetaNoPagamento([g(200, 'pending', PI)], PI), { total: 200, porDevolverNaStripe: 200 }, 'mesmo PI');
});

Deno.test('cancelamento sem taxa: a compra volta 8 ao cartão + 2 ao saldo; a gorjeta não entra', () => {
  igual(repartirReembolso(1000, pago(1000, 0, [g(200, 'succeeded')])), { stripeCents: 800, carteiraCents: 200 }, 'repartição');
});

Deno.test('sem a v3 a gorjeta "comia" a parte do saldo (o erro que isto evita)', () => {
  const antigo: Pago = { ...pago(1000, 0, []), stripeCents: 1000, stripeDisponivelCents: 1000 };
  igual(repartirReembolso(1000, antigo), { stripeCents: 1000, carteiraCents: 0 }, 'antes');
});

Deno.test('taxa de cancelamento 1,50 €: só a compra paga a taxa; a gorjeta fica de fora inteira', () => {
  igual(repartirReembolso(1000 - 150, pago(1000, 0, [g(200, 'succeeded')])), { stripeCents: 800, carteiraCents: 50 }, 'com taxa');
});

Deno.test('gorjeta já devolvida antes ao cartão: a compra ainda pode voltar toda', () => {
  igual(repartirReembolso(1000, pago(1000, 200, [g(200, 'refunded', PI, 'meio')])), { stripeCents: 800, carteiraCents: 200 }, 'depois da gorjeta');
});

Deno.test('charge-tip create: a gorjeta já vai no pagamento do cartão?', () => {
  // pedido que existe: só o rascunho do PI DESTE pedido conta
  igual(gorjetaJaVaiNoCartao({ pedidoExiste: true, rascunhoDoPiDoPedidoComGorjeta: true, rascunhoRecentePorUsarComGorjeta: false }), true, 'pago com cartão + gorjeta');
  // "tentou cartão, desistiu, pagou com saldo": há um rascunho recente com gorjeta por usar, mas o
  // pedido (só saldo) não tem esse PI → cobra-se à parte
  igual(gorjetaJaVaiNoCartao({ pedidoExiste: true, rascunhoDoPiDoPedidoComGorjeta: false, rascunhoRecentePorUsarComGorjeta: true }), false, 'desistiu do cartão e pagou com saldo');
  // pedido ainda a nascer no webhook: vale o rascunho recente por usar
  igual(gorjetaJaVaiNoCartao({ pedidoExiste: false, rascunhoDoPiDoPedidoComGorjeta: false, rascunhoRecentePorUsarComGorjeta: true }), true, 'pedido a nascer');
  igual(gorjetaJaVaiNoCartao({ pedidoExiste: false, rascunhoDoPiDoPedidoComGorjeta: false, rascunhoRecentePorUsarComGorjeta: false }), false, 'nada');
});

// ── Banco e Stripe de brincar ───────────────────────────────────────────────
type Linha = Record<string, unknown>;
function bancoDeBrincar(linhas: Linha[]) {
  const rpcs: { nome: string; args: Record<string, unknown> }[] = [];
  // deno-lint-ignore no-explicit-any
  function consulta(op: 'update' | 'select', patch?: Linha): any {
    const filtros: ((l: Linha) => boolean)[] = [];
    // deno-lint-ignore no-explicit-any
    const b: any = {
      eq(c: string, v: unknown) { filtros.push((l) => l[c] === v); return b; },
      in(c: string, vs: unknown[]) { filtros.push((l) => vs.includes(l[c])); return b; },
      select() { return b; },
      then(ok: (x: unknown) => unknown, ko?: (e: unknown) => unknown) {
        const alvo = linhas.filter((l) => filtros.every((f) => f(l)));
        if (op === 'update') alvo.forEach((l) => Object.assign(l, patch));
        return Promise.resolve({ data: alvo.map((l) => ({ ...l })), error: null }).then(ok, ko);
      },
    };
    return b;
  }
  return {
    rpcs,
    from(_t: string) { return { update: (p: Linha) => consulta('update', p), select: (_c: string) => consulta('select') }; },
    rpc(nome: string, args: Record<string, unknown>) { rpcs.push({ nome, args }); return Promise.resolve({ data: {}, error: null }); },
  };
}

interface Cenario { pi: Record<string, unknown>; reembolsos: Record<string, unknown>[]; falhaGet?: boolean }
function stripeDeBrincar(c: Cenario) {
  const posts: { url: string; corpo: string }[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada);
    const r = (x: unknown, s = 200) => new Response(JSON.stringify(x), { status: s });
    if (init?.method === 'POST') {
      posts.push({ url, corpo: String(init.body ?? '') });
      if (url.endsWith('/v1/refunds')) {
        const p = new URLSearchParams(String(init.body ?? ''));
        const novo = { id: `re_${posts.length}`, status: 'succeeded', amount: Number(p.get('amount')), metadata: { tip_id: p.get('metadata[tip_id]') } };
        c.reembolsos.push(novo);
        return r(novo);
      }
      return r({});
    }
    if (c.falhaGet) return r({ error: { message: 'rede em baixo' } }, 500);
    if (url.includes('/v1/refunds?')) return r({ data: c.reembolsos });
    if (url.includes('/v1/payment_intents/')) return r(c.pi);
    return r({}, 404);
  }) as typeof fetch;
  return { posts, repor: () => { globalThis.fetch = original; } };
}

const TIP = (extra: Partial<GorjetaParaDevolver> = {}): GorjetaParaDevolver & Linha => ({
  id: 'tip1', order_id: 'p1', tvde_ride_id: null, client_user_id: 'u1', amount_cents: 200, method: 'card',
  moment: 'checkout', status: 'succeeded', stripe_payment_intent_id: PI, cobrada_junto: true,
  failure_reason: null, devolucao_tentativas: 0, ...extra,
});
const piPago = (recebido: number, devolvido: number) =>
  ({ id: PI, status: 'succeeded', amount_received: recebido, latest_charge: { amount_refunded: devolvido } });
const SEM_FUGAS = { sanitizeOps: false, sanitizeResources: false };

Deno.test({ name: 'devolução: valor = a gorjeta inteira, um só reembolso com tip_id', ...SEM_FUGAS, fn: async () => {
  const tip = TIP();
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: piPago(1200, 0), reembolsos: [] });
  try {
    const r = await devolverUmaGorjeta(db, 'sk_brincar', tip, 'meio', 'cancelado');
    igual(r.cents, 200, 'cêntimos'); igual(s.posts.length, 1, 'um POST');
    const p = new URLSearchParams(s.posts[0].corpo);
    igual([p.get('amount'), p.get('metadata[tip_id]')], ['200', 'tip1'], 'valor e tip_id');
    igual(tip.status, 'refunded', 'estado');
  } finally { s.repor(); }
} });

Deno.test({ name: 'devolução: reembolso já feito antes (resposta perdida na rede) → não repete', ...SEM_FUGAS, fn: async () => {
  const tip = TIP();
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: piPago(1200, 200), reembolsos: [{ id: 're_antigo', status: 'succeeded', metadata: { tip_id: 'tip1' } }] });
  try {
    const r = await devolverUmaGorjeta(db, 'sk_brincar', tip, 'meio', 'cancelado');
    igual(s.posts.length, 0, 'nenhum POST'); igual(r.acao, 'meio_ja_feito:re_antigo', 'ação'); igual(tip.status, 'refunded', 'estado');
  } finally { s.repor(); }
} });

Deno.test({ name: 'devolução: a Stripe tem menos do que a gorjeta → não devolve meia; erro + 1 aviso; pára', ...SEM_FUGAS, fn: async () => {
  const tip = TIP();
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: piPago(1200, 1100), reembolsos: [] });
  try {
    const r = await devolverUmaGorjeta(db, 'sk_brincar', tip, 'meio', 'cancelado');
    igual(r.acao, 'erro', 'erro'); igual(s.posts.length, 0, 'nenhum POST');
    igual([tip.status, tip.devolucao_tentativas], ['succeeded', 2], 'volta a paga e pára');
    igual(db.rpcs.filter((x) => x.nome === 'notify_admin_event').length, 1, 'um aviso');
  } finally { s.repor(); }
} });

Deno.test({ name: 'devolução: falhas de rede → aviso ao admin só à 2.ª, nunca outra vez', ...SEM_FUGAS, fn: async () => {
  const tip = TIP();
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: piPago(1200, 0), reembolsos: [], falhaGet: true });
  try {
    for (let i = 0; i < 3; i++) await devolverUmaGorjeta(db, 'sk_brincar', { ...tip }, 'meio', 'cancelado');
    igual(tip.devolucao_tentativas, 3, 'tentativas'); igual(tip.status, 'succeeded', 'continua por devolver');
    igual(db.rpcs.filter((x) => x.nome === 'notify_admin_event').length, 1, 'um só aviso');
  } finally { s.repor(); }
} });

Deno.test({ name: 'cancelado antes do webhook: MB Way junto com PI pago na Stripe → paga e devolvida uma vez', ...SEM_FUGAS, fn: async () => {
  const tip = TIP({ method: 'mbway', status: 'pending' });
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: piPago(1200, 0), reembolsos: [] });
  try {
    const r = await devolverGorjetasDoPedido(db, 'sk_brincar', 'p1', 'meio', 'cancelado');
    igual([r.devolvidaCents, s.posts.length, tip.status], [200, 1, 'refunded'], 'paga e devolvida');
    const r2 = await devolverGorjetasDoPedido(db, 'sk_brincar', 'p1', 'meio', 'cancelado');
    igual([r2.devolvidaCents, s.posts.length], [0, 1], 'segunda vez não faz nada');
  } finally { s.repor(); }
} });

Deno.test({ name: 'cancelado: MB Way junto ainda à espera do cliente → fica pending, sem reembolso', ...SEM_FUGAS, fn: async () => {
  const tip = TIP({ method: 'mbway', status: 'pending' });
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: { id: PI, status: 'processing' }, reembolsos: [] });
  try {
    const r = await devolverGorjetasDoPedido(db, 'sk_brincar', 'p1', 'meio', 'cancelado');
    igual([tip.status, s.posts.length, r.itens[0]?.acao], ['pending', 0, 'a_espera'], 'à espera');
  } finally { s.repor(); }
} });

Deno.test({ name: 'cancelado: MB Way junto que falhou na Stripe → cancelled, sem reembolso', ...SEM_FUGAS, fn: async () => {
  const tip = TIP({ method: 'mbway', status: 'pending' });
  const db = bancoDeBrincar([tip]);
  const s = stripeDeBrincar({ pi: { id: PI, status: 'requires_payment_method' }, reembolsos: [] });
  try {
    await devolverGorjetasDoPedido(db, 'sk_brincar', 'p1', 'meio', 'cancelado');
    igual([tip.status, s.posts.length], ['cancelled', 0], 'cancelada');
  } finally { s.repor(); }
} });
