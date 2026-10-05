// Simulação do stripe-webhook (ronda 04/10, Bloco A) — base de dados falsa + Stripe falsa.
//
// Uso:  deno run -A --config <deno.json com {"nodeModulesDir":"auto"}> simular_webhook.ts <caminho do index.ts>
//
// Corre o index.ts VERDADEIRO (stripe@14.21.0 e supabase-js@2 verdadeiros, vindos do esm.sh).
// O que é falso é a rede: o fetch global é trocado ANTES de importar o módulo e responde
//   - http://falso.local/rest/v1/...      → um PostgREST mínimo em memória (tabelas + RPCs)
//   - http://falso.local/functions/v1/... → finalize / dispatch-engine / notify-partner falsos
//   - https://api.stripe.com/v1/...       → Stripe falsa (retrieve do PI, refunds)
// A assinatura do evento é HMAC-SHA256 a sério (constructEventAsync verifica-a).
// Sai com código 0 só se TODOS os cenários passarem. Contra o v35 TEM de falhar.

// deno-lint-ignore-file no-explicit-any
const alvo = Deno.args[0];
if (!alvo) { console.error('falta o caminho do index.ts'); Deno.exit(2); }

const BASE = 'http://falso.local';
const SEGREDO = 'whsec_simulacao';
Deno.env.set('SUPABASE_URL', BASE);
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'chave-servico-falsa');
Deno.env.set('STRIPE_SECRET_KEY', 'sk_test_falsa');
Deno.env.set('STRIPE_WEBHOOK_SECRET', SEGREDO);

// ── estado do mundo falso ───────────────────────────────────────────────────
let db: any;
function novoMundo() {
  db = {
    t: { orders: {}, tips: {}, carwash_bookings: {}, tvde_rides: {}, stripe_webhook_events: {}, payment_drafts: {} },
    subs: [] as any[],
    rpcChamadas: [] as string[],
    falharRpc: new Set<string>(),
    falharPatch: new Set<string>(),
    edge: { notify: 0, dispatch: 0, finalize: 0 },
    stripe: { refunds: 0, retrieves: 0 },
    finalizeCria: null as any,
  };
}
const PK: Record<string, string> = { stripe_webhook_events: 'event_id' };

function valor(v: string): any {
  if (v === 'null') return null;
  if (v === 'true') return true;
  if (v === 'false') return false;
  return v;
}
function lista(v: string): string[] {
  return v.replace(/^\(/, '').replace(/\)$/, '').split(',').map((x) => x.replace(/^"|"$/g, ''));
}
function passa(row: any, col: string, expr: string): boolean {
  const neg = expr.startsWith('not.');
  const e = neg ? expr.slice(4) : expr;
  const i = e.indexOf('.');
  const op = e.slice(0, i), arg = e.slice(i + 1);
  const cell = row[col];
  let r: boolean;
  if (op === 'eq') r = String(cell) === String(valor(arg));
  else if (op === 'neq') r = String(cell) !== String(valor(arg));
  else if (op === 'in') r = lista(arg).includes(String(cell));
  else if (op === 'is') r = arg === 'null' ? cell == null : cell === valor(arg);
  else throw new Error(`filtro não suportado: ${col}=${expr}`);
  return neg ? !r : r;
}
const NAO_FILTRO = new Set(['select', 'on_conflict', 'columns', 'order', 'limit']);

function resposta(corpo: any, status = 200) {
  return new Response(corpo === undefined ? null : JSON.stringify(corpo), {
    status, headers: { 'Content-Type': 'application/json' },
  });
}
function erroPg(msg: string, status = 400) {
  return resposta({ message: msg, code: 'P0001', details: null, hint: null }, status);
}

// ── RPCs falsas (mesma semântica das do banco, o essencial) ──────────────────
function rpc(nome: string, a: any): Response {
  db.rpcChamadas.push(nome);
  if (db.falharRpc.has(nome)) return erroPg(`falha simulada em ${nome}`, 500);
  switch (nome) {
    case 'registar_cobranca_stripe': {
      const o = db.t.orders[a.p_order_id];
      if (!a.p_cents || a.p_cents <= 0 || !o || o.payment_intent_id !== a.p_payment_intent_id
        || (o.stripe_charge_cents ?? 0) !== 0) return resposta(false);
      o.stripe_charge_cents = a.p_cents;
      return resposta(true);
    }
    case 'confirm_cleaning_payment_webhook': return resposta({ ok: true });
    case 'confirm_carwash_payment_webhook': {
      const b = db.t.carwash_bookings[a.p_booking_id];
      if (!b) return resposta({ ok: false, error: 'booking_not_found' });
      if (b.payment_status !== 'unpaid') return resposta({ ok: true, already_marked: true });
      if (b.total_cents !== a.p_amount_cents) return resposta({ ok: false, error: 'amount_mismatch' });
      b.payment_status = 'held'; b.stripe_payment_intent_id = a.p_payment_intent_id;
      return resposta({ ok: true, booking_id: a.p_booking_id });
    }
    case 'tvde_reservation_mark_paid': {
      const r = db.t.tvde_rides[a.p_ride_id];
      if (!r || !r.scheduled_at) return resposta(false);
      if (r.reservation_status !== 'aguarda_pagamento') return resposta(true);
      r.reservation_status = 'a_procurar'; r.payment_status = 'succeeded';
      return resposta(true);
    }
    case 'tvde_activate_paid_subscription': {
      const ja = db.subs.find((s: any) => s.pi === a.p_payment_intent_id);
      if (ja) return resposta(ja);
      const s = { id: `sub_${db.subs.length + 1}`, pi: a.p_payment_intent_id, plan: a.p_plan,
        km_included: a.p_km_included ?? null, origin: a.p_origin_label ?? null };
      db.subs.push(s);
      return resposta(s);
    }
    case 'notify_admin_urgent_push': return resposta(null);
    default: return erroPg(`rpc desconhecida na base falsa: ${nome}`, 404);
  }
}

// ── PostgREST mínimo ─────────────────────────────────────────────────────────
async function rest(req: Request, url: URL): Promise<Response> {
  const tabela = url.pathname.replace('/rest/v1/', '');
  if (tabela.startsWith('rpc/')) return rpc(tabela.slice(4), await req.json());
  const linhas = db.t[tabela];
  if (!linhas) return erroPg(`tabela desconhecida: ${tabela}`, 404);
  const filtros = [...url.searchParams.entries()].filter(([k]) => !NAO_FILTRO.has(k));
  const casam = () => Object.values(linhas).filter((r: any) => filtros.every(([c, e]) => passa(r, c, e)));
  const prefer = req.headers.get('Prefer') ?? '';
  const objeto = (req.headers.get('Accept') ?? '').includes('vnd.pgrst.object');

  if (req.method === 'GET') {
    const rs = casam();
    if (objeto) return rs.length === 1 ? resposta(rs[0]) : erroPg('JSON object requested, multiple (or no) rows returned', 406);
    return resposta(rs);
  }
  if (req.method === 'PATCH') {
    if (db.falharPatch.has(tabela)) return erroPg(`falha simulada no UPDATE de ${tabela}`, 500);
    const patch = await req.json();
    const rs = casam();
    for (const r of rs) Object.assign(r, patch);
    if (prefer.includes('return=representation')) return objeto ? resposta(rs[0] ?? null) : resposta(rs);
    return new Response(null, { status: 204 });
  }
  if (req.method === 'POST') {
    const corpo = await req.json();
    const pk = PK[tabela] ?? 'id';
    for (const row of (Array.isArray(corpo) ? corpo : [corpo])) {
      if (linhas[row[pk]]) {
        if (prefer.includes('ignore-duplicates')) continue;
        if (prefer.includes('merge-duplicates')) { Object.assign(linhas[row[pk]], row); continue; }
        return erroPg('duplicate key value violates unique constraint', 409);
      }
      linhas[row[pk]] = { received_at: new Date().toISOString(), processed_at: null, last_error: null, ...row };
    }
    return new Response(null, { status: 201 });
  }
  return erroPg(`método não suportado ${req.method}`, 405);
}

// ── Stripe falsa ─────────────────────────────────────────────────────────────
function stripeApi(req: Request, url: URL): Response {
  if (req.method === 'GET' && url.pathname.startsWith('/v1/payment_intents/')) {
    db.stripe.retrieves++;
    const id = url.pathname.split('/').pop();
    return resposta({ id, object: 'payment_intent', status: 'succeeded',
      latest_charge: { id: 'ch_falsa', object: 'charge', balance_transaction: { id: 'txn_falsa', fee: 25 } } });
  }
  if (req.method === 'POST' && url.pathname === '/v1/refunds') {
    db.stripe.refunds++;
    return resposta({ id: `re_${db.stripe.refunds}`, object: 'refund', status: 'succeeded' });
  }
  return resposta({ error: { message: `stripe falsa: ${req.method} ${url.pathname}` } }, 404);
}

// ── Edge Functions chamadas pelo webhook ─────────────────────────────────────
async function edge(req: Request, url: URL): Promise<Response> {
  const nome = url.pathname.replace('/functions/v1/', '');
  if (nome === 'notify-partner') { db.edge.notify++; return resposta({ ok: true }); }
  if (nome === 'dispatch-engine') { db.edge.dispatch++; return resposta({ ok: true }); }
  if (nome === 'finalize-order-from-intent') {
    db.edge.finalize++;
    const { payment_intent_id } = await req.json();
    const c = db.finalizeCria;
    if (!c) return resposta({ error: 'draft_not_found' }, 404);
    if (!db.t.orders[c.id]) db.t.orders[c.id] = { ...c, payment_intent_id };
    return resposta({ ok: true, order_id: c.id, idempotent: false });
  }
  return resposta({ error: `edge falsa desconhecida: ${nome}` }, 404);
}

globalThis.fetch = (async (entrada: any, init?: any) => {
  const req = entrada instanceof Request ? entrada : new Request(String(entrada), init);
  const url = new URL(req.url);
  if (url.origin === BASE && url.pathname.startsWith('/rest/v1/')) return rest(req, url);
  if (url.origin === BASE && url.pathname.startsWith('/functions/v1/')) return edge(req, url);
  if (url.hostname === 'api.stripe.com') return stripeApi(req, url);
  throw new Error(`rede bloqueada na simulação: ${req.method} ${req.url}`);
}) as typeof fetch;

// Captura o handler do Deno.serve em vez de abrir uma porta.
let handler: (req: Request) => Promise<Response>;
(Deno as any).serve = (h: any) => { handler = h; return { finished: Promise.resolve() }; };

// Os logs do webhook ficam num buffer (só se mostram quando um cenário falha).
const consoleOrig = { log: console.log, warn: console.warn, error: console.error };
let buffer: string[] = [];
for (const k of ['log', 'warn', 'error'] as const) {
  (console as any)[k] = (...a: any[]) => buffer.push(`  [${k}] ` + a.map((x) => typeof x === 'string' ? x : JSON.stringify(x)).join(' '));
}

const modUrl = new URL(alvo.replace(/\\/g, '/'), `file:///${Deno.cwd().replace(/\\/g, '/')}/`).href;
await import(modUrl);
if (!handler!) { consoleOrig.error('o módulo não chamou Deno.serve'); Deno.exit(2); }

async function assinar(corpo: string): Promise<string> {
  const t = Math.floor(Date.now() / 1000);
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(SEGREDO),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(`${t}.${corpo}`)));
  return `t=${t},v1=${[...sig].map((b) => b.toString(16).padStart(2, '0')).join('')}`;
}
function evento(id: string, type: string, pi: any) {
  return { id, object: 'event', type, api_version: '2023-10-16', created: 1,
    data: { object: { object: 'payment_intent', status: 'succeeded', amount: pi.amount_received ?? 0, ...pi } } };
}
async function enviar(ev: any): Promise<number> {
  const corpo = JSON.stringify(ev);
  const res = await handler(new Request(`${BASE}/functions/v1/stripe-webhook`, {
    method: 'POST', headers: { 'stripe-signature': await assinar(corpo) }, body: corpo,
  }));
  await res.text();
  return res.status;
}

// ── Cenários ─────────────────────────────────────────────────────────────────
const cenarios: Array<[string, () => Promise<[boolean, string]>]> = [
  ['A.1 pedido pago (cartão/MB Way) grava stripe_charge_cents', async () => {
    db.t.orders.o1 = { id: 'o1', status: 'created', payment_status: 'pending', payment_intent_id: null,
      stripe_charge_cents: 0, is_partner_store: false, service_type: 'storeShopping', payment_method: 'mbway' };
    const st = await enviar(evento('evt_1', 'payment_intent.succeeded', { id: 'pi_1', amount_received: 1850, metadata: { order_id: 'o1' } }));
    const o = db.t.orders.o1;
    return [st === 200 && o.payment_status === 'paid' && o.stripe_charge_cents === 1850,
      `http=${st} payment_status=${o.payment_status} stripe_charge_cents=${o.stripe_charge_cents}`];
  }],
  ['A.1 pedido por draft/finalize grava stripe_charge_cents', async () => {
    db.finalizeCria = { id: 'o9', status: 'created', payment_status: 'paid', stripe_charge_cents: 0,
      is_partner_store: false, service_type: 'restaurant' };
    const st = await enviar(evento('evt_9', 'payment_intent.succeeded', { id: 'pi_9', amount_received: 990, metadata: { draft_id: 'd9' } }));
    const o = db.t.orders.o9;
    return [st === 200 && o?.stripe_charge_cents === 990, `http=${st} finalize=${db.edge.finalize} stripe_charge_cents=${o?.stripe_charge_cents}`];
  }],
  ['A.3 evento repetido NÃO processa duas vezes', async () => {
    db.t.orders.o2 = { id: 'o2', status: 'created', payment_status: 'pending', payment_intent_id: null,
      stripe_charge_cents: 0, is_partner_store: true, service_type: 'restaurant', payment_method: 'mbway',
      restaurant_id: 'r1', customer_total: 12.5 };
    const ev = evento('evt_2', 'payment_intent.succeeded', { id: 'pi_2', amount_received: 1250, metadata: { order_id: 'o2' } });
    const s1 = await enviar(ev);
    await new Promise((r) => setTimeout(r, 20)); // notify-partner é fire-and-forget
    const s2 = await enviar(ev);
    await new Promise((r) => setTimeout(r, 20));
    return [s1 === 200 && s2 === 200 && db.edge.notify === 1,
      `http=${s1}/${s2} avisos ao parceiro=${db.edge.notify} (esperado 1)`];
  }],
  ['A.3 falha de RPC → 500, regista last_error; a repetição da Stripe acaba o trabalho', async () => {
    db.falharRpc.add('confirm_cleaning_payment_webhook');
    const ev = evento('evt_3', 'payment_intent.succeeded', { id: 'pi_3', amount_received: 4000, metadata: { kind: 'cleaning', booking_id: 'c1' } });
    const s1 = await enviar(ev);
    const le1 = db.t.stripe_webhook_events.evt_3?.last_error ?? null; // foto do valor (a linha é a mesma)
    const pa1 = db.t.stripe_webhook_events.evt_3?.processed_at ?? null;
    db.falharRpc.delete('confirm_cleaning_payment_webhook');
    const s2 = await enviar(ev);
    const reg2 = db.t.stripe_webhook_events.evt_3;
    return [s1 === 500 && !!le1 && pa1 == null && s2 === 200 && !!reg2?.processed_at && reg2?.last_error == null,
      `http=${s1} depois ${s2}; last_error na 1.ª=${JSON.stringify(le1)}; processed_at no fim=${reg2?.processed_at ? 'sim' : 'não'}`];
  }],
  ['A.3 falha do UPDATE do pedido → 500 (antes: 200 e pedido por marcar)', async () => {
    db.t.orders.o4 = { id: 'o4', status: 'created', payment_status: 'pending', payment_intent_id: null,
      stripe_charge_cents: 0, is_partner_store: false, service_type: 'storeShopping', payment_method: 'mbway' };
    db.falharPatch.add('orders');
    const st = await enviar(evento('evt_4', 'payment_intent.succeeded', { id: 'pi_4', amount_received: 700, metadata: { order_id: 'o4' } }));
    return [st === 500, `http=${st} payment_status=${db.t.orders.o4.payment_status}`];
  }],
  ['A.7d gorjeta (kind=tip) fica succeeded com paid_at e taxa', async () => {
    db.t.tips.t1 = { id: 't1', status: 'requires_action', stripe_payment_intent_id: null };
    const st = await enviar(evento('evt_5', 'payment_intent.succeeded', { id: 'pi_5', amount_received: 200, metadata: { kind: 'tip', tip_id: 't1' } }));
    const t = db.t.tips.t1;
    return [st === 200 && t.status === 'succeeded' && !!t.paid_at && t.stripe_fee_cents === 25 && t.stripe_payment_intent_id === 'pi_5',
      `http=${st} status=${t.status} paid_at=${t.paid_at ? 'sim' : 'não'} taxa=${t.stripe_fee_cents ?? '-'}`];
  }],
  ['A.7c lavagem (kind=carwash) fica held', async () => {
    db.t.carwash_bookings.b1 = { id: 'b1', payment_status: 'unpaid', total_cents: 1500, status: 'scheduled' };
    const st = await enviar(evento('evt_6', 'payment_intent.succeeded', { id: 'pi_6', amount: 1500, amount_received: 1500, metadata: { kind: 'carwash', booking_id: 'b1' } }));
    const b = db.t.carwash_bookings.b1;
    return [st === 200 && b.payment_status === 'held' && b.stripe_payment_intent_id === 'pi_6', `http=${st} payment_status=${b.payment_status}`];
  }],
  ['A.7a reserva TVDE paga por MB Way fica a procurar motorista (app fechada)', async () => {
    db.t.tvde_rides.r1 = { id: 'r1', status: 'agendada', reservation_status: 'aguarda_pagamento',
      scheduled_at: '2026-10-06T10:00:00Z', payment_status: 'processing', est_fare_cents: 900 };
    const st = await enviar(evento('evt_7', 'payment_intent.succeeded', { id: 'pi_7', amount_received: 900, metadata: { kind: 'tvde_reservation', ride_id: 'r1', user_id: 'u1' } }));
    const r = db.t.tvde_rides.r1;
    return [st === 200 && r.reservation_status === 'a_procurar', `http=${st} reservation_status=${r.reservation_status} payment_status=${r.payment_status}`];
  }],
  ['A.7b plano TVDE grava os km pagos', async () => {
    const st = await enviar(evento('evt_8', 'payment_intent.succeeded', { id: 'pi_8', amount_received: 6000,
      metadata: { kind: 'tvde_plan', plan: 'mensal', user_id: 'u1', distance_km: '12.5', origin_label: 'Guarda' } }));
    const s = db.subs[0];
    return [st === 200 && s?.km_included === 12.5, `http=${st} km_included=${s?.km_included ?? '-'}`];
  }],
  ['controlo: metadata desconhecida continua 200', async () => {
    const st = await enviar(evento('evt_10', 'payment_intent.succeeded', { id: 'pi_10', amount_received: 100, metadata: {} }));
    return [st === 200, `http=${st}`];
  }],
];

consoleOrig.log(`Simulação stripe-webhook — alvo: ${alvo}`);
let falhas = 0;
for (const [nome, f] of cenarios) {
  novoMundo(); buffer = [];
  let ok = false, det = '';
  try { [ok, det] = await f(); } catch (e) { det = `EXCEPÇÃO: ${e instanceof Error ? e.message : e}`; }
  if (!ok) falhas++;
  consoleOrig.log(`${ok ? 'PASSA' : 'FALHA'}  ${nome} — ${det}`);
  if (!ok) for (const l of buffer.slice(-6)) consoleOrig.log(l.slice(0, 220));
}
consoleOrig.log(`RESULTADO: ${cenarios.length - falhas}/${cenarios.length} passam`);
Deno.exit(falhas === 0 ? 0 : 1);
