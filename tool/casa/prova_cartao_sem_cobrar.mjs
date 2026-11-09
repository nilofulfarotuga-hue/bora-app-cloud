// Prova do cartão e MB Way da Casa em produção SEM COBRAR NINGUÉM (m11, 09/11/2026, depois do "autorizo").
// Conta de TESTE e2e_client_a@boraapp.test (posta como testadora da Casa só durante a prova), pelo mesmo
// caminho da app (casa_* e Edge casa-checkout). Nunca confirma um pagamento: o PaymentIntent do cartão nasce
// sem método de pagamento (requires_payment_method) e ninguém o confirma.
//
//   node tool/casa/prova_cartao_sem_cobrar.mjs <saida.json>
//
// 1. casa_config: pagamento_cartao = true.
// 2. Roupeiro 80 € por cartão → 'aguarda_pagamento' (não vai a ninguém).
// 3. Edge create → devolve clientSecret (o pagamento existe na Stripe, por confirmar: 0 € cobrados).
// 4. Edge mark_held com esse pagamento → recusa 402 payment_not_completed (não foi pago).
// 5. Edge create_mbway num pedido de cartão → recusa not_mbway_pedido (o portão antes da Stripe).
// 6. Cancelar → 0 €; Edge reverse → nothing_to_reverse (nada foi cobrado).
// Chaves lidas de backend/.env e .dart_defines; nunca se escrevem.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const RAIZ = 'C:/BoraLocal/projetosflutter/bora_app';
const saida = process.argv[2] ?? 'C:/BoraLocal/missoes/m11-amigo-rosto-2026-11-09/prova-cartao-sem-cobrar.json';
const CONTA = 'e2e_client_a@boraapp.test';
const ROUPEIRO = '4a895068-baf3-4d94-b24b-911ecf25550d';

function lerChaves(caminho) {
  if (!existsSync(caminho)) return {};
  const t = readFileSync(caminho, 'utf8').trim();
  if (t.startsWith('{')) return JSON.parse(t);
  const o = {};
  for (const l of t.split(/\r?\n/)) {
    const m = l.match(/^\s*([A-Za-z0-9_]+)\s*=\s*"?([^"\r\n]*)"?\s*$/);
    if (m) o[m[1]] = m[2];
  }
  return o;
}
const env = { ...lerChaves(`${RAIZ}/backend/.env`), ...lerChaves(`${RAIZ}/.dart_defines`) };
const url = Object.entries(env).find(([k, v]) => /SUPABASE_URL/i.test(k) && /^https:/.test(v))?.[1];
const servidor = Object.entries(env).find(([k, v]) => /SERVICE_ROLE|SECRET_KEY|SERVICE_KEY/i.test(k) && /^(eyJ|sb_secret_)/.test(v))?.[1];
const publica = Object.entries(env).find(([k, v]) => /ANON|PUBLISHABLE/i.test(k) && /^(eyJ|sb_publishable_)/.test(v))?.[1];
if (!url || !servidor || !publica) { console.log('FALTAM CHAVES'); process.exit(2); }

async function sessao(email) {
  const g = await fetch(`${url}/auth/v1/admin/generate_link`, {
    method: 'POST', headers: { apikey: servidor, Authorization: `Bearer ${servidor}`, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email }),
  }).then((r) => r.json());
  const v = await fetch(`${url}/auth/v1/verify`, {
    method: 'POST', headers: { apikey: publica, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: g?.properties?.hashed_token ?? g?.hashed_token }),
  }).then((r) => r.json());
  if (!v.access_token) throw new Error(`sessão falhou para ${email}`);
  return { token: v.access_token, uid: v.user?.id };
}
async function rpc(s, nome, params) {
  const r = await fetch(`${url}/rest/v1/rpc/${nome}`, {
    method: 'POST', headers: { apikey: publica, Authorization: `Bearer ${s.token}`, 'content-type': 'application/json' },
    body: JSON.stringify(params ?? {}),
  });
  const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
  return { status: r.status, j };
}
async function edge(s, body) {
  const r = await fetch(`${url}/functions/v1/casa-checkout`, {
    method: 'POST', headers: { apikey: publica, Authorization: `Bearer ${s.token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
  return { status: r.status, j };
}
function amanhaAs10() {
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Lisbon' }).format(new Date());
  const d = new Date(`${hoje}T10:00:00Z`); d.setUTCDate(d.getUTCDate() + 2); return d.toISOString();
}

const r = { conta: CONTA };
const s = await sessao(CONTA);
r.pagamento_cartao = (await rpc(s, 'casa_config')).j?.pagamento_cartao;

const c = await rpc(s, 'casa_criar_pedido', {
  p_servico_id: ROUPEIRO, p_quantidade: 1, p_descricao: 'TESTE M11 cartao — prova sem cobrar, cancela-se já',
  p_respostas: { marca: 'IKEA', material: 'Sim, já tenho tudo' },
  p_address_street: 'Praça Luís de Camões (TESTE — não ir)', p_address_city: 'Guarda', p_address_postal: '6300-725',
  p_lat: 40.5373, p_lng: -7.2675, p_scheduled_at: amanhaAs10(), p_payment_method: 'card', p_idempotency_key: randomUUID(),
});
r.criar = { status: c.status, estado: c.j?.estado, total_cents: c.j?.total_cents, is_test: c.j?.is_test, erro: c.status >= 400 ? (c.j?.message ?? c.j) : undefined };
const id = c.j?.id;
if (!id) { writeFileSync(saida, JSON.stringify(r, null, 2)); console.log('PROVA', JSON.stringify({ ok: false, passo: 'criar', ...r.criar })); process.exit(1); }
r.pedido = id;

const cr = await edge(s, { action: 'create', pedidoId: id, stripe_contas_v2: true });
r.edge_create = { status: cr.status, tem_client_secret: typeof cr.j?.clientSecret === 'string', pi_status: cr.j?.status, conta: cr.j?.stripe_account, amountCents: cr.j?.amountCents, erro: cr.j?.error };
const pi = cr.j?.paymentIntentId;
r.payment_intent = pi;

const mk = pi ? await edge(s, { action: 'mark_held', pedidoId: id, paymentIntentId: pi }) : { status: 0, j: null };
r.edge_mark_held = { status: mk.status, erro: mk.j?.error, pi_status: mk.j?.status };

const mb = await edge(s, { action: 'create_mbway', pedidoId: id, phone: '912345678' });
r.edge_create_mbway_em_pedido_de_cartao = { status: mb.status, erro: mb.j?.error };

const lido = (await rpc(s, 'casa_pedido', { p_pedido_id: id })).j;
r.antes_de_cancelar = { estado: lido?.estado, payment_status: lido?.payment_status };
const can = await rpc(s, 'casa_cancelar', { p_pedido_id: id, p_motivo: 'Prova do cartao sem cobrar (m11)' });
r.cancelar = { status: can.status, cancel_fee_cents: can.j?.cancel_fee_cents };
const rv = await edge(s, { action: 'reverse', pedidoId: id });
r.edge_reverse = { status: rv.status, note: rv.j?.note, erro: rv.j?.error };

writeFileSync(saida, JSON.stringify(r, null, 2));
const ok = r.pagamento_cartao === true && r.criar.estado === 'aguarda_pagamento' && r.edge_create.tem_client_secret
  && r.edge_create.amountCents === 8000 && r.edge_mark_held.status === 402 && r.edge_create_mbway_em_pedido_de_cartao.erro === 'not_mbway_pedido'
  && r.cancelar.cancel_fee_cents === 0 && r.edge_reverse.note === 'nothing_to_reverse';
console.log('PROVA', JSON.stringify({ ok, pedido: id, ...r, conta: undefined }));
