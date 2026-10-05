// Prova do contrato das chamadas novas da app (ronda 04/10, fechada a 05/10/2026).
//
// Faz pelo PostgREST exactamente o que a app faz, com as contas de demonstração
// (as mesmas do integration_test/demo_real_test.dart) e a chave pública da app:
//   A. cliente  -> quote_order_pricing (as chaves que o CartStore.resumo lê),
//                  carrinho_guardar, leitura de volta, carrinho_convertido.
//   B. estafeta -> driver_heartbeat_segredo_obter (com sessão) e
//                  driver_heartbeat_segredo (sem sessão, como o serviço em
//                  segundo plano), com o segredo certo e com um errado.
//
// Não escreve segredos nem tokens na saída. Uso:
//   node prova_contrato.mjs <raiz-do-repo>
import fs from 'node:fs';

const raiz = process.argv[2] ?? '.';
const viagem = fs.readFileSync(`${raiz}/web/viagem.html`, 'utf8');
const url = viagem.match(/https:\/\/[a-z0-9]+\.supabase\.co/)[0];
const anon = (viagem.match(/sb_publishable_[A-Za-z0-9_-]+/) ??
  viagem.match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/))[0];
const teste = fs.readFileSync(`${raiz}/integration_test/demo_real_test.dart`, 'utf8');
const senha = teste.match(/'DEMO_PASSWORD', defaultValue: '([^']+)'/)[1];
const emailCliente = teste.match(/'DEMO_EMAIL', defaultValue: '([^']+)'/)[1];
const emailEstafeta = teste.match(/'DEMO_EMAIL_ESTAFETA',\s*defaultValue: '([^']+)'/)[1];

const dizer = (...a) => console.log(...a);

async function entrar(email) {
  const r = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: senha }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`login ${email}: HTTP ${r.status} ${j.error_description ?? j.msg ?? ''}`);
  return j.access_token;
}

async function chamar(caminho, { token, corpo, metodo = 'POST' } = {}) {
  const r = await fetch(`${url}/rest/v1/${caminho}`, {
    method: metodo,
    headers: {
      apikey: anon,
      Authorization: `Bearer ${token ?? anon}`,
      'Content-Type': 'application/json',
    },
    body: metodo === 'GET' ? undefined : JSON.stringify(corpo ?? {}),
  });
  const t = await r.text();
  let j = null;
  try { j = t ? JSON.parse(t) : null; } catch { j = t; }
  return { http: r.status, corpo: j };
}

// ── A. CLIENTE ──────────────────────────────────────────────────────────────
dizer('== A. cliente demo:', emailCliente);
const tCliente = await entrar(emailCliente);

// O mesmo p_input do CartStore.entradaDoQuote(): 2 x iogurte do Auchan
// (2,05 de catálogo -> 2,36 no ecrã com os 15% do não-parceiro).
const precoEcra = 2.36, precoBase = 2.05, qtd = 2;
const nome = 'IOGURTE DANONE AROMA MORANGO BANANA E TUTTI FRUTTI 8X120G';
const entrada = {
  service_type: 'storeShopping',
  is_partner_store: false,
  items: [{ productId: 'auc-1001769', name: nome, price: precoEcra, quantity: qtd,
            purchaseStatus: 'pending', basePrice: precoBase }],
  product_lines: [{ product_id: 'auc-1001769', quantity: qtd, unit_price: precoBase, name: nome }],
  distance_km: 1.4,
  apartment_delivery: false,
  pickup_lat: 40.540592, pickup_lng: -7.266362,
  destination_lat: 40.5373, destination_lng: -7.2680,
  wallet_applied_cents: 0,
  include_debt: true,
  payment_method: 'card',
};
const q = await chamar('rpc/quote_order_pricing', { token: tCliente, corpo: { p_input: entrada } });
dizer('A1 quote_order_pricing http', q.http);
const chaves = ['service_type', 'subtotal', 'service_fee', 'delivery_fee', 'bag_fee',
  'apartment_surcharge', 'small_order_fee', 'customer_total', 'debt_settle_cents'];
for (const k of chaves) dizer(`   ${k} =`, q.corpo?.[k]);
const subtotalDoCarrinho = precoEcra * qtd;
const bate = Math.abs((q.corpo?.subtotal ?? -1) - subtotalDoCarrinho) <= 0.011;
dizer(`A2 subtotal do servidor bate com o do carrinho (${subtotalDoCarrinho.toFixed(2)}):`, bate);
const soma = ['subtotal', 'service_fee', 'delivery_fee', 'bag_fee', 'small_order_fee']
  .reduce((s, k) => s + Number(q.corpo?.[k] ?? 0), 0);
dizer('A3 soma das parcelas =', soma.toFixed(2), '| customer_total =', q.corpo?.customer_total);

const g = await chamar('rpc/carrinho_guardar', { token: tCliente, corpo: {
  p_loja: 'Auchan', p_loja_id: 'auchan-guarda',
  p_resumo: `${qtd}× ${nome}`,
  p_total: Number(Number(q.corpo?.customer_total ?? 0).toFixed(2)),
  p_n_itens: qtd,
} });
dizer('A4 carrinho_guardar http', g.http, g.corpo ?? '');
const sel = 'carrinhos_abandonados?select=loja,loja_id,resumo,total,n_itens,convertido_em,avisado_em';
const l1 = await chamar(sel, { token: tCliente, metodo: 'GET' });
dizer('A5 lido de volta:', JSON.stringify(l1.corpo));
const c = await chamar('rpc/carrinho_convertido', { token: tCliente });
dizer('A6 carrinho_convertido http', c.http, c.corpo ?? '');
const l2 = await chamar(sel, { token: tCliente, metodo: 'GET' });
const linha = Array.isArray(l2.corpo) ? l2.corpo[0] : null;
dizer('A7 depois: n_itens =', linha?.n_itens, '| convertido_em preenchido =', !!linha?.convertido_em);
const semSessao = await chamar('rpc/carrinho_guardar', { corpo: {
  p_loja: 'x', p_loja_id: 'x', p_resumo: 'x', p_total: 1, p_n_itens: 1 } });
dizer('A8 carrinho_guardar SEM sessão http', semSessao.http, '(tem de recusar)');

// ── B. ESTAFETA ─────────────────────────────────────────────────────────────
dizer('== B. estafeta demo:', emailEstafeta);
const tEstafeta = await entrar(emailEstafeta);
const s = await chamar('rpc/driver_heartbeat_segredo_obter', { token: tEstafeta });
const segredo = s.corpo?.segredo ?? '';
dizer('B1 segredo_obter http', s.http, '| ok =', s.corpo?.ok, '| driver_id =', s.corpo?.driver_id,
  '| tamanho do segredo =', segredo.length);
const s2 = await chamar('rpc/driver_heartbeat_segredo_obter', { token: tEstafeta });
dizer('B2 pedir outra vez devolve o mesmo segredo:', s2.corpo?.segredo === segredo);
const b = await chamar('rpc/driver_heartbeat_segredo', { corpo: {
  p_driver_id: s.corpo?.driver_id, p_segredo: segredo } });
dizer('B3 batimento SEM sessão, segredo certo: http', b.http, JSON.stringify(b.corpo));
const mau = await chamar('rpc/driver_heartbeat_segredo', { corpo: {
  p_driver_id: s.corpo?.driver_id, p_segredo: 'x'.repeat(segredo.length || 40) } });
dizer('B4 batimento SEM sessão, segredo errado: http', mau.http, JSON.stringify(mau.corpo));
const semS = await chamar('rpc/driver_heartbeat_segredo_obter', {});
dizer('B5 segredo_obter SEM sessão http', semS.http, '(tem de recusar)');
