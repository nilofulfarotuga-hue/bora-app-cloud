// Arrumação depois da prova de ecrãs: o browser da prova fechou com 2 artigos no
// carrinho do cliente de demonstração e o retrato ficou no servidor. Fecha-se como a
// app faria (carrinho_convertido), para a conta demo não ficar com um "abandonado".
//   node arrumar_retrato_demo.mjs <raiz-do-repo>
import fs from 'node:fs';
const raiz = process.argv[2] ?? '.';
const viagem = fs.readFileSync(`${raiz}/web/viagem.html`, 'utf8');
const url = viagem.match(/https:\/\/[a-z0-9]+\.supabase\.co/)[0];
const anon = (viagem.match(/sb_publishable_[A-Za-z0-9_-]+/) ?? viagem.match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/))[0];
const teste = fs.readFileSync(`${raiz}/integration_test/demo_real_test.dart`, 'utf8');
const senha = teste.match(/'DEMO_PASSWORD', defaultValue: '([^']+)'/)[1];
const email = teste.match(/'DEMO_EMAIL', defaultValue: '([^']+)'/)[1];
const login = await (await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: 'POST', headers: { apikey: anon, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: senha }) })).json();
const h = { apikey: anon, Authorization: `Bearer ${login.access_token}`, 'Content-Type': 'application/json' };
const c = await fetch(`${url}/rest/v1/rpc/carrinho_convertido`, { method: 'POST', headers: h, body: '{}' });
const l = await (await fetch(`${url}/rest/v1/carrinhos_abandonados?select=loja,n_itens,convertido_em`, { headers: h })).json();
console.log('carrinho_convertido http', c.status, '| depois:', JSON.stringify(l));
