// Prova a sério da Casa & Manutenção (missão m11, adendo 3, 09/11/2026) — pelo MESMO caminho da app
// (as funções casa_* que o CasaStore chama), com a CONTA DE TESTE e2e_client_a@boraapp.test.
//
//   node tool/casa/teste_pedido_casa.mjs <saida.json>
//
// 1. "Montar roupeiro" (80 €) em dinheiro → o servidor TEM de recusar (limite geral do dinheiro: 40 €).
// 2. "Montar móvel médio" (40 €) em dinheiro, amanhã às 10:00 (Lisboa), com "Sim, já tenho tudo".
// 3. Lê o pedido de volta, simula o cancelamento (tem de ser 0 €, faltam mais de 12 h) e cancela.
// Nada é cobrado: pagamento em mão, cancelado antes de alguém ir. Marcar como teste faz-se depois, no painel
// (admin_casa_marcar_teste), para nunca entrar em acertos.
// Sessão por link mágico gerado com a chave de servidor (nenhuma senha, nenhum email enviado). As chaves leem-se
// de backend/.env e .dart_defines do checkout principal e NUNCA se escrevem em lado nenhum.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const RAIZ = 'C:/BoraLocal/projetosflutter/bora_app';
const saida = process.argv[2] ?? 'C:/BoraLocal/missoes/m11-amigo-rosto-2026-11-09/prova-casa-pedido-teste.json';
const CONTA = 'e2e_client_a@boraapp.test';
const ROUPEIRO = '4a895068-baf3-4d94-b24b-911ecf25550d';
const MOVEL_MEDIO = '935fbdd5-bfc6-4870-a026-293b71a0f64a';

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
if (!url || !servidor || !publica) { console.log('FALTAM CHAVES (url/servidor/publicavel):', !!url, !!servidor, !!publica); process.exit(2); }

async function sessao(email) {
  const g = await fetch(`${url}/auth/v1/admin/generate_link`, {
    method: 'POST', headers: { apikey: servidor, Authorization: `Bearer ${servidor}`, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email }),
  }).then((r) => r.json());
  const h = g?.properties?.hashed_token ?? g?.hashed_token;
  const v = await fetch(`${url}/auth/v1/verify`, {
    method: 'POST', headers: { apikey: publica, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: h }),
  }).then((r) => r.json());
  if (!v.access_token) throw new Error(`sessão falhou para ${email}`);
  return { token: v.access_token, uid: v.user?.id };
}

async function rpc(s, nome, params) {
  const r = await fetch(`${url}/rest/v1/rpc/${nome}`, {
    method: 'POST', headers: { apikey: publica, Authorization: `Bearer ${s.token}`, 'content-type': 'application/json' },
    body: JSON.stringify(params ?? {}),
  });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { j = t; }
  return { status: r.status, j };
}

// amanhã às 10:00 em Lisboa (no inverno Lisboa = UTC)
function amanhaAs10Lisboa() {
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Lisbon' }).format(new Date());
  const d = new Date(`${hoje}T10:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  const offH = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Lisbon', hour: '2-digit', hourCycle: 'h23' }).format(d)) - 10;
  d.setUTCHours(d.getUTCHours() - offH);
  return d.toISOString();
}

const morada = {
  p_address_street: 'Praça Luís de Camões (TESTE — não ir)',
  p_address_city: 'Guarda',
  p_address_postal: '6300-725',
  p_lat: 40.5373,
  p_lng: -7.2675,
};
const quando = amanhaAs10Lisboa();
const r = { conta: CONTA, quando_utc: quando };

const s = await sessao(CONTA);
r.config = (await rpc(s, 'casa_config')).j;

// 1. roupeiro 80 € em dinheiro → tem de ser recusado
const a = await rpc(s, 'casa_criar_pedido', {
  p_servico_id: ROUPEIRO, p_quantidade: 1, p_descricao: 'TESTE M11 — prova do limite do dinheiro',
  p_respostas: { marca: 'IKEA', material: 'Sim, já tenho tudo' }, ...morada,
  p_scheduled_at: quando, p_payment_method: 'cash', p_idempotency_key: randomUUID(),
});
r.roupeiro_80_dinheiro = { status: a.status, resposta: a.j?.message ?? a.j };
r.roupeiro_recusado = a.status >= 400 && /dinheiro_acima_do_limite/.test(JSON.stringify(a.j));

// 2. móvel médio 40 € em dinheiro
const b = await rpc(s, 'casa_criar_pedido', {
  p_servico_id: MOVEL_MEDIO, p_quantidade: 1, p_descricao: 'TESTE M11 — pedido de prova, cancela-se já. Não ir.',
  p_respostas: { tipo_movel: 'Cómoda (teste)', material: 'Sim, já tenho tudo' }, ...morada,
  p_scheduled_at: quando, p_payment_method: 'cash', p_idempotency_key: randomUUID(),
});
r.movel_medio_40 = { status: b.status };
const pedidoId = b.j?.id;
if (b.status >= 400 || !pedidoId) {
  r.erro = b.j;
  writeFileSync(saida, JSON.stringify(r, null, 2));
  console.log('PROVA', JSON.stringify({ ok: false, passo: 'criar', status: b.status, erro: b.j?.message ?? b.j, roupeiro_recusado: r.roupeiro_recusado }));
  process.exit(1);
}
r.pedido_id = pedidoId;

// 3. lê de volta (dá tempo à oferta de sair)
await new Promise((ok) => setTimeout(ok, 15000));
const lido = (await rpc(s, 'casa_pedido', { p_pedido_id: pedidoId })).j;
const p = lido?.pedido ?? lido;
r.lido = {
  estado: p?.estado, payment_method: p?.payment_method, total_cents: p?.total_cents,
  scheduled_at: p?.scheduled_at, material: p?.respostas?.material,
};

// 4. simula e cancela
r.simulacao = (await rpc(s, 'casa_cancelar_simulacao', { p_pedido_id: pedidoId })).j;
const c = await rpc(s, 'casa_cancelar', { p_pedido_id: pedidoId, p_motivo: 'Pedido de teste da publicação (m11)' });
r.cancelar = { status: c.status, resposta: c.j };
const depois = (await rpc(s, 'casa_pedido', { p_pedido_id: pedidoId })).j;
r.estado_final = (depois?.pedido ?? depois)?.estado;

writeFileSync(saida, JSON.stringify(r, null, 2));
const taxa = c.j?.cancel_fee_cents ?? null;
console.log('PROVA', JSON.stringify({
  ok: r.roupeiro_recusado && c.status < 400 && taxa === 0,
  pedido: pedidoId, roupeiro_recusado: r.roupeiro_recusado, criado: r.lido,
  taxa_cancelar_cents: taxa, estado_final: r.estado_final,
}));
