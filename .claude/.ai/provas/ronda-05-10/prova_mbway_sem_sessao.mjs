// Prova que ficou em falta no relatório do checkout (ronda 04/10): a função
// create-mbway-payment-intent (v30) recusa quem não tem sessão e quem não é dono
// do pedido — sempre ANTES de tocar no Stripe (ninguém é cobrado por esta prova).
//   node prova_mbway_sem_sessao.mjs <raiz-do-repo>
import fs from 'node:fs';

const raiz = process.argv[2] ?? '.';
const viagem = fs.readFileSync(`${raiz}/web/viagem.html`, 'utf8');
const url = viagem.match(/https:\/\/[a-z0-9]+\.supabase\.co/)[0];
const anon = (viagem.match(/sb_publishable_[A-Za-z0-9_-]+/) ??
  viagem.match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/))[0];
const teste = fs.readFileSync(`${raiz}/integration_test/demo_real_test.dart`, 'utf8');
const senha = teste.match(/'DEMO_PASSWORD', defaultValue: '([^']+)'/)[1];
const email = teste.match(/'DEMO_EMAIL', defaultValue: '([^']+)'/)[1];

async function mbway(cabecalhos, corpo) {
  const r = await fetch(`${url}/functions/v1/create-mbway-payment-intent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...cabecalhos },
    body: JSON.stringify(corpo),
  });
  return `http ${r.status} ${(await r.text()).slice(0, 120)}`;
}
const pedidoQueNaoExiste = { order_id: '00000000-0000-4000-8000-00000000dead', phone: '+351910000000' };

console.log('1 sem cabeçalho de sessão   ->', await mbway({ apikey: anon }, pedidoQueNaoExiste));
console.log('2 só com a chave pública    ->', await mbway({ apikey: anon, Authorization: `Bearer ${anon}` }, pedidoQueNaoExiste));

const login = await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: 'POST', headers: { apikey: anon, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: senha }),
});
const { access_token } = await login.json();
console.log('3 com sessão, pedido alheio/inexistente ->',
  await mbway({ apikey: anon, Authorization: `Bearer ${access_token}` }, pedidoQueNaoExiste));
