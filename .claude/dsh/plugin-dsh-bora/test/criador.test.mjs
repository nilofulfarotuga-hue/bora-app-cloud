// Testes do Creator Mode (receitas): o que pode e não pode ser uma ferramenta criada pelo Dipsy.
// Correr: node --test test/criador.test.mjs   (offline, sem rede nem dsh)
import test from 'node:test'
import assert from 'node:assert/strict'
import { validarReceita, preencher, perfilAtual } from '../lib/criador.js'

const SQL_HOJE = "select count(*) as pedidos from public.orders where (created_at at time zone 'Europe/Lisbon')::date = (now() at time zone 'Europe/Lisbon')::date"
const base = { nome: 'pedidos_hoje', descricao: 'Diz quantos pedidos houve hoje no Bora', tipo: 'consulta_sql', sql: SQL_HOJE }

test('receita: pedidos de hoje passa', () => assert.equal(validarReceita(base).nome, 'pedidos_hoje'))
test('receita: ponto e vírgula final é tirado', () => assert.equal(validarReceita({ ...base, sql: SQL_HOJE + ';' }).sql, SQL_HOJE))
test('receita: com parâmetro de data passa', () => {
  const r = validarReceita({ ...base, nome: 'pedidos_do_dia', sql: 'select count(*) from orders where created_at::date = {{dia}}', parametros: [{ nome: 'dia', tipo: 'data' }] })
  assert.equal(preencher(r, { dia: '2026-10-31' }), "select count(*) from orders where created_at::date = '2026-10-31'::date")
})
test('receita: texto com aspa é escapado', () => {
  const r = validarReceita({ ...base, nome: 'por_loja', sql: 'select count(*) from restaurants where name = {{loja}}', parametros: [{ nome: 'loja' }] })
  assert.equal(preencher(r, { loja: "O'Neill" }), "select count(*) from restaurants where name = 'O''Neill'")
})
test('receita: número inválido recusa', () => {
  const r = validarReceita({ ...base, nome: 'ultimos', sql: 'select id from orders order by created_at desc limit {{n}}', parametros: [{ nome: 'n', tipo: 'numero' }] })
  assert.throws(() => preencher(r, { n: '1; drop table orders' }))
})
test('receita: data inválida recusa', () => {
  const r = validarReceita({ ...base, nome: 'pedidos_do_dia', sql: 'select count(*) from orders where created_at::date = {{dia}}', parametros: [{ nome: 'dia', tipo: 'data' }] })
  assert.throws(() => preencher(r, { dia: "2026-10-31' or 1=1 --" }))
})
for (const [nome, extra] of [
  ['UPDATE', { sql: 'update orders set price = 0' }],
  ['DELETE', { sql: 'delete from e2e_log' }],
  ['dois comandos', { sql: 'select 1; select 2' }],
  ['CTE que apaga', { sql: 'with d as (delete from e2e_log returning *) select count(*) from d' }],
  ['função de dinheiro', { sql: 'select admin_refund_order(1)' }],
  ['tokens protegidos', { sql: 'select * from bora_tokens' }],
  ['sem SQL', { sql: '' }],
  ['nome mau', { nome: 'Pedidos-Hoje' }],
  ['nome curto', { nome: 'pe' }],
  ['descrição curta', { descricao: 'x' }],
  ['tipo inventado', { tipo: 'comando_shell' }],
  ['marcador sem parâmetro', { sql: 'select count(*) from orders where id = {{id}}' }],
  ['segredo .env', { descricao: 'lê o ficheiro .env do bora' }],
  ['chave escrita', { sql: "select 'sbp_abcdefghijklmnopqrstuvwxyz0123' as x" }],
  ['web para fora', { tipo: 'leitura_web', url: 'https://example.com/x' }],
  ['web para telegram', { tipo: 'leitura_web', url: 'https://api.telegram.org/bot1/getMe' }],
  ['web sem https', { tipo: 'leitura_web', url: 'file:///C:/Users/danil/.ssh/id_ed25519' }],
]) test(`receita recusada: ${nome}`, () => assert.throws(() => validarReceita({ ...base, ...extra }), /Receita recusada|tem de|falta/))
test('receita: leitura web do nosso site passa', () => assert.equal(validarReceita({ ...base, nome: 'site_no_ar', tipo: 'leitura_web', url: 'https://boraguarda.com/' }).url, 'https://boraguarda.com/'))
test('receita: parâmetro na url é codificado', () => {
  const r = validarReceita({ ...base, nome: 'pagina_site', tipo: 'leitura_web', url: 'https://boraguarda.com/{{p}}', parametros: [{ nome: 'p', padrao: 'x' }] })
  assert.equal(preencher(r, { p: '../../a b' }), 'https://boraguarda.com/..%2F..%2Fa%20b')
})
test('perfil: --profile lab', () => assert.equal(perfilAtual(['node', 'bin.js', '--profile', 'lab']), 'lab'))
test('perfil: forma curta web', () => assert.equal(perfilAtual(['node', 'bin.js', 'web']), 'web'))
test('perfil: por omissão headless', () => assert.equal(perfilAtual(['node', 'bin.js']), process.env.DSH_PROFILE ?? 'headless'))
