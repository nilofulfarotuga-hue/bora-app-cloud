// Prova local (PGlite = Postgres real em WASM) das propostas 01 e 02 da missão fecho-contabilista-2026-11-10.
// Não toca na produção. Precisa de:
//   <pasta>/node_modules/@electric-sql/pglite@0.2.17
//   <pasta>/dump.json   (exportado só por leitura com exportar.mjs: colunas reais + linhas reais de out/nov 2026)
//   <pasta>/fn/*.sql    (definições EM VIGOR de admin_monthly_closeout, fecho_mensal_prestadores,
//                        driver_monthly_invoice_summary, lidas com pg_get_functiondef)
// Uso: bun prova_pglite.mjs <pasta>     (o node deste PC dá "unreachable" no WASM; com bun corre)
import fs from 'node:fs'
import path from 'node:path'

const PASTA = process.argv[2]
const AQUI = path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, '$1')
const { PGlite } = await import(path.join(PASTA, 'node_modules/@electric-sql/pglite/dist/index.js'))
const dump = JSON.parse(fs.readFileSync(path.join(PASTA, 'dump.json'), 'utf8'))
const db = new PGlite()
let falhas = 0
const ok = (cond, msg) => { console.log((cond ? 'OK   ' : 'FALHA') + ' ' + msg); if (!cond) falhas++ }
const um = async (sql, params) => (await db.query(sql, params)).rows[0]

const BUILTIN = /^(text|integer|bigint|smallint|numeric(\(.*\))?|boolean|uuid|jsonb|json|date|real|double precision|timestamp with time zone|timestamp without time zone|time without time zone|character varying(\(\d+\))?|character(\(\d+\))?|interval|bytea|inet)(\[\])?$/
const tipo = (t) => (BUILTIN.test(t) ? t : t.endsWith('[]') ? 'text[]' : 'text')

await db.exec(`
  create schema auth; create schema vault; create schema net;
  create role anon; create role authenticated; create role service_role; create role authenticator;
  grant usage on schema public, auth to anon, authenticated, service_role, authenticator;
  grant anon, authenticated, service_role to authenticator;
  create table auth.users (id uuid primary key, email text);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function public.is_admin() returns boolean language sql stable as $$ select coalesce(current_setting('test.admin', true), '0') = '1' $$;
  create function public.log_admin_action(text, text, text, jsonb) returns void language sql as $$ select $$;
  create function public.log_admin_action(text, text, uuid, jsonb) returns uuid language sql as $$ select null::uuid $$;
  create view vault.decrypted_secrets as select 'project_url'::text as name, 'http://x'::text as decrypted_secret
    union all select 'sb_secret_backend', 'chave-de-teste';
  create function net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds int) returns bigint language sql as $$ select 42::bigint $$;
  grant execute on all functions in schema auth to anon, authenticated, service_role, authenticator;
`)
await db.query(`insert into auth.users select * from json_populate_recordset(null::auth.users, $1::json)`, [JSON.stringify(dump.auth_users)])

for (const t of dump.tabelas) {
  const cols = t.cols.map((c) => `"${c.n}" ${tipo(c.t)}`).join(', ')
  await db.exec(`create table ${t.t} (${cols})`)
  await db.query(`insert into ${t.t} select * from json_populate_recordset(null::${t.t}, $1::json)`, [JSON.stringify(t.dados)])
}
await db.exec(`alter table public.fecho_mensal_contabilista_log add unique (ano, mes)`)
// Funções de apoio reais, por ordem de dependência (tenta até todas entrarem).
let porCriar = [...dump.funcoes]
for (let volta = 0; volta < 5 && porCriar.length; volta++) {
  const falharam = []
  for (const f of porCriar) {
    try { await db.exec(f.def) } catch (e) { falharam.push(Object.assign(f, { erro: e.message })) }
  }
  porCriar = falharam
}
for (const f of porCriar) console.log('aviso: função de apoio ' + f.proname + ' falhou: ' + f.erro)

// 1) As funções EM VIGOR reproduzem os números do ar?  (prova de que a base local é fiel)
for (const n of ['admin_monthly_closeout', 'fecho_mensal_prestadores', 'driver_monthly_invoice_summary']) {
  await db.exec(fs.readFileSync(path.join(PASTA, 'fn', n + '.sql'), 'utf8'))
}
await db.exec(`select set_config('request.jwt.claims', '{"role":"service_role"}', false)`)
for (const [m, ref] of [[10, dump.referencia.out10], [11, dump.referencia.out11]]) {
  const r = (await um(`select public.admin_monthly_closeout(2026, $1) x`, [m])).x
  ok(Number(r.para_as_financas.total_a_declarar) === Number(ref.para_as_financas.total_a_declarar) &&
     Number(r.totais.receita_propria_bora) === Number(ref.totais.receita_propria_bora) &&
     Number(r.totais.pedidos_entregues) === Number(ref.totais.pedidos_entregues),
     `base local = ar no mês ${m} (versão em vigor): total ${r.para_as_financas.total_a_declarar} / ar ${ref.para_as_financas.total_a_declarar}`)
}

// 2) Aplica a proposta 01 inteira (como uma migração).
await db.exec(fs.readFileSync(path.join(AQUI, '01_fecho_contabilista_regras_hugo.sql'), 'utf8'))
ok(true, 'proposta 01 aplicada sem erro de sintaxe')
const bkp = await um(`select count(*)::int n from public.bkp_funcoes_fecho_20261110`)
ok(bkp.n === 3, `backup das 3 funções antigas guardado (${bkp.n})`)

// 3) Outubro: números do fecho conferido a 10/11 (Claude.ai): total Bora 159,17; entregas 129,56; tokens 3,29.
const o10 = (await um(`select public.admin_monthly_closeout(2026, 10) x`)).x
const rub = o10.para_as_financas.rubricas
const soma = Object.values(rub).reduce((a, v) => a + Number(v), 0)
ok(Math.abs(soma - Number(o10.totais.receita_propria_bora)) < 0.005, `outubro: soma das rubricas ${soma.toFixed(2)} = receita própria ${o10.totais.receita_propria_bora}`)
ok(Number(o10.totais.receita_propria_bora) === 129.56, `outubro: entregas e mercados 129,56 (${o10.totais.receita_propria_bora})`)
ok(Number(rub.tokens_descontados) === -3.29, `outubro: tokens descontados -3,29 (${rub.tokens_descontados})`)
ok(Number(rub.margem_nao_parceiros) === 31.42 && Number(rub.comissao_lojas_parceiras) === 3.59, `outubro: margem nos produtos 31,42 + 3,59 = 35,01 (${rub.margem_nao_parceiros} + ${rub.comissao_lojas_parceiras})`)
ok(Number(rub.ajustes_descontos) === 0, `outubro: ajustes 0 (${rub.ajustes_descontos})`)
ok(Number(o10.para_as_financas.total_a_declarar) === 159.17, `outubro: total da Bora 159,17 (${o10.para_as_financas.total_a_declarar})`)
const fat = o10.para_as_financas.faturas_recibo
ok(fat.length === 1 && fat[0].destinatario === 'Consumidor final' && Number(fat[0].valor) === 159.17, `outubro: UMA linha Consumidor final de 159,17 (${fat.length} linha(s), ${fat[0]?.valor})`)
const txt = o10.para_as_financas.texto
ok(!/TVDE/i.test(txt) && !/por loja parceira com a comissão/.test(txt) && /nunca às lojas/.test(txt), 'outubro: texto sem TVDE, sem "uma por loja parceira com a comissão", com "nunca às lojas"')
ok(o10.entidade.nif === '322151171', `outubro: entidade Danilo em nome individual (${o10.entidade.nif})`)
const o11 = (await um(`select public.admin_monthly_closeout(2026, 11) x`)).x
ok(o11.entidade.tipo === 'sociedade' && o11.entidade.nif === '519686233', `novembro: entidade a sociedade 519686233 (${o11.entidade.nif})`)
const soma11 = Object.values(o11.para_as_financas.rubricas).reduce((a, v) => a + Number(v), 0)
ok(Math.abs(soma11 - Number(o11.totais.receita_propria_bora)) < 0.005, `novembro: soma das rubricas ${soma11.toFixed(2)} = receita própria ${o11.totais.receita_propria_bora}`)

// 4) Prestadores: sem IVA/retenção fixos; lojas faturadas aos clientes.
const p10 = (await um(`select public.fecho_mensal_prestadores(2026, 10) x`)).x
ok(/confirmad/.test(p10.adquirente.iva_prestador) && /contabilista/.test(p10.adquirente.retencao) && !/^Sem retenção/.test(p10.adquirente.retencao), 'prestadores: IVA e retenção "confirmados pelo contabilista"')
ok(p10.lojas_parceiras.every((l) => /nunca à loja/.test(l.fatura_bora.descricao)), 'lojas parceiras: "faturada aos clientes, nunca à loja"')

// 5) Extras de outubro.
const x10 = (await um(`select public.fecho_contabilista_extras(2026, 10) x`)).x
ok(Number(x10.tokens_descontados_em_pedidos.valor) === 3.29, `extras outubro: tokens descontados 3,29 (${x10.tokens_descontados_em_pedidos.valor})`)
const bem = x10.codigos_promocionais.find((c) => c.codigo === 'BEMVINDO')
ok(bem && bem.usos === 7 && Number(bem.valor) === 35 && bem.com_pedido === 0, `extras outubro: BEMVINDO 7 usos, 35 €, 0 com pedido (${JSON.stringify(bem && { u: bem.usos, v: bem.valor, p: bem.com_pedido, usados: bem.tokens_ja_usados })})`)
ok(Number(x10.stripe_parte_bora.taxas) === 5.95 && x10.stripe_parte_bora.fonte === 'extrato_stripe', `extras outubro: taxas Stripe da parte Bora 5,95 (${x10.stripe_parte_bora.taxas}, ${x10.stripe_parte_bora.fonte})`)
console.log('   tokens oferecidos outubro:', x10.tokens_oferecidos.tokens, '=', x10.tokens_oferecidos.valor, '€; cancelados:', x10.cancelados_e_reembolsos.cancelados, '; reembolsos:', x10.cancelados_e_reembolsos.reembolsados, x10.cancelados_e_reembolsos.reembolsado_valor, '€; check-in emitidos:', x10.premios_checkin.emitidos)
const lig = await um(`select count(*)::int n, count(*) filter (where exists (select 1 from public.bora_tokens b where b.source_order_id = u.tokens_origem))::int ligados
                        from public.promo_code_uses u where u.code = 'BEMVINDO' and u.order_id is null`)
ok(lig.n > 0 && lig.n === lig.ligados, `BEMVINDO: todos os usos sem pedido ligam aos tokens creditados (${lig.ligados}/${lig.n})`)

// 6) Dados fiscais (DAC7).
const d = (await um(`select public.admin_prestadores_dados_fiscais() x`)).x
// Sem nomes no ficheiro (o repo é público): procura-se pelo papel e pelo que falta.
const sab = d.linhas.find((l) => l.papel === 'loja_parceira' && l.falta.includes('NIF'))
ok(!!sab, `DAC7: há loja parceira ativa sem NIF (${JSON.stringify(sab?.falta)})`)
const val = d.linhas.find((l) => l.papel === 'estafeta' && l.falta.includes('IBAN') && l.falta.includes('comprovativo de atividade'))
ok(!!val, `DAC7: há estafeta aprovado sem IBAN e sem comprovativo (${JSON.stringify(val?.falta)})`)
ok(!JSON.stringify(d).match(/PT50\d{6,}/), 'DAC7: nenhum IBAN em claro na resposta')
console.log('   DAC7:', d.total, 'linhas,', d.com_falta, 'com falta')
for (const l of d.linhas.filter((l) => l.em_falta)) console.log('     -', l.papel, '|', l.falta.join(', '))

// 7) O texto completo para o contabilista (outubro) e a nota do Danilo.
await db.exec(`select set_config('test.admin', '1', false); select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false)`)
await um(`select public.admin_fecho_contabilista_nota(2026, 10, 'Outubro foi no nome individual do Danilo.') x`)
const c10 = (await um(`select public.admin_fecho_contabilista(2026, 10) x`)).x
ok(/TOTAL RECEITA PRÓPRIA DA BORA: 159,17 €/.test(c10.texto), 'texto ao contabilista: total 159,17 €')
ok(/Nota do Danilo: Outubro foi no nome individual/.test(c10.texto), 'texto ao contabilista: leva a nota do Danilo')
ok(!/TVDE/i.test(c10.texto.replace(/sem TVDE/g, '')), 'texto ao contabilista: TVDE fora (só "sem TVDE" no título da Stripe)')
fs.writeFileSync(path.join(AQUI, 'texto_outubro_exemplo.txt'), c10.texto.replace(/\b\d{9}\b/g, (m) => (m === '322151171' || m === '519686233' || m.startsWith('5')) ? m : '#########'))
if (process.env.SAIDA_JSON) fs.writeFileSync(process.env.SAIDA_JSON, JSON.stringify({ fecho: o10, prest: p10, completo: c10 }))
const c11 = (await um(`select public.admin_fecho_contabilista(2026, 11) x`)).x
ok(/sociedade/.test(c11.texto.split('\n')[1]), 'texto de novembro: entidade é a sociedade')
const rv = (await um(`select public.admin_fecho_contabilista_reenviar(2026, 10) x`)).x
ok(rv.ok === true && rv.request_id === 42, 'reenviar: chama a Edge (net.http_post simulado)')

// 8) Conferência (D1) e identidades (D3) de outubro e novembro.
for (const m of [10, 11]) {
  const cf = (await um(`select public.admin_fecho_conferencia(2026, $1) x`, [m])).x
  ok(cf.rubricas_batem && cf.lucro_bate, `conferência ${m}: rubricas batem e pago−mercadoria−estafetas = sobra`)
  console.log(`   conferência ${m}: ${cf.pedidos_com_diferenca.length} pedido(s) com diferença, ${cf.limpezas_com_diferenca.length} limpeza(s), ${cf.dinheiro_sem_valor_registado.length} em dinheiro sem valor registado ${JSON.stringify(cf.dinheiro_sem_valor_registado.map((x) => x.order_id.slice(0, 8) + ' ' + x.pago_fecho))}`)
  for (const p of cf.pedidos_com_diferenca) console.log('     ·', JSON.stringify(p))
  for (const p of cf.limpezas_com_diferenca) console.log('     ·', JSON.stringify(p))
}

// 10) Proposta 02 (remendo por âncora) numa cópia simulada das duas funções da Stripe.
await db.exec(`
  create function public.stripe_extrato_resumo(p_desde text, p_ate text, p_conta text) returns jsonb language plpgsql security definer set search_path to 'public' as $f$
  begin
    if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role' or current_user in ('postgres','service_role')) then
      raise exception 'admin_required'; end if;
    return '{}'::jsonb;
  end $f$;
  create function public.stripe_extrato_cruzar_base() returns jsonb language plpgsql security definer set search_path to 'public' as $f$
  begin
    if not (public.is_admin() or coalesce(auth.jwt()->>'role','') = 'service_role' or current_user in ('postgres','service_role')) then
      raise exception 'admin_required'; end if;
    return '{}'::jsonb;
  end $f$;
  grant execute on function public.stripe_extrato_resumo(text,text,text), public.stripe_extrato_cruzar_base() to authenticated;`)
await db.exec(fs.readFileSync(path.join(AQUI, '02_seguranca_guarda_current_user.sql'), 'utf8'))
const def2 = await um(`select pg_get_functiondef('public.stripe_extrato_resumo(text,text,text)'::regprocedure) d`)
ok(!/current_user in/.test(def2.d) && /session_user = 'postgres'/.test(def2.d), 'proposta 02: guarda trocada por session_user')
let repetiu = false
try { await db.exec(fs.readFileSync(path.join(AQUI, '02_seguranca_guarda_current_user.sql'), 'utf8')) } catch (e) { repetiu = /âncora encontrada 0 vezes/.test(e.message) }
ok(repetiu, 'proposta 02: correr outra vez pára sem mudar nada (âncora já não existe)')

// 9) Guardas: quem não é admin nem servidor NÃO entra (simula a ligação da app: authenticator → authenticated).
await db.exec(`select set_config('test.admin', '0', false); select set_config('request.jwt.claims', '{"role":"authenticated"}', false)`)
await db.exec(`grant usage on schema vault, net to authenticated`)
await db.exec(`set session authorization authenticator; set role authenticated`)
for (const f of ['admin_prestadores_dados_fiscais()', 'fecho_mensal_prestadores(2026,10)', 'admin_monthly_closeout(2026,10)',
                 'fecho_contabilista_extras(2026,10)', 'admin_fecho_contabilista(2026,10)', 'admin_fecho_conferencia(2026,10)']) {
  let negou = false
  try { await db.query(`select public.${f}`) } catch (e) { negou = /admin_required/.test(e.message) }
  ok(negou, `guarda: utilizador comum NÃO lê ${f}`)
}
let negou = false
try { await db.query(`select public._dados_fiscais_linhas()`) } catch (e) { negou = /permission denied/.test(e.message) }
ok(negou, 'guarda: _dados_fiscais_linhas() fechada a utilizadores')
const valUid = val?.user_id
await db.exec(`select set_config('test.uid', '${valUid}', false)`)
const meu = (await um(`select public.meus_dados_fiscais_em_falta() x`)).x
ok(meu.ok && meu.em_falta.length >= 1 && !JSON.stringify(meu).includes('"nif"'), `app: esse estafeta vê só o que lhe falta (${JSON.stringify(meu.em_falta)})`)

negou = false
try { await db.query(`select public.stripe_extrato_resumo('2026-10','2026-10','empresa')`) } catch (e) { negou = /admin_required/.test(e.message) }
ok(negou, 'proposta 02: utilizador comum já NÃO lê o resumo da Stripe')

console.log(falhas === 0 ? '\nTUDO CERTO' : `\n${falhas} FALHA(S)`)
process.exit(falhas === 0 ? 0 : 1)
