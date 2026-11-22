// Prova local (PGlite) da porta do Hermes — bloco B4 da missão hermes-diretor-2026-11-20. Não toca em produção.
// Uso: PGLITE_DIR=<pasta com node_modules/@electric-sql/pglite> node provar_porta.mjs
import { readFileSync } from 'node:fs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(AQUI, '../../..');
const PG = process.env.PGLITE_DIR || 'C:/Users/danil/AppData/Local/Temp/pglite-prova';
const { PGlite } = await import(pathToFileURL(resolve(PG, 'node_modules/@electric-sql/pglite/dist/index.js')).href);

const db = new PGlite();
const ok = [], falhou = [];
const q = async (sql, p) => (await db.query(sql, p)).rows;
const um = async (sql, p) => (await q(sql, p))[0];
const exec = (sql) => db.exec(sql);
const teste = (nome, cond, detalhe = '') => {
  (cond ? ok : falhou).push(nome);
  console.log((cond ? 'PASSOU  ' : 'FALHOU  ') + nome + (cond ? '' : ' -> ' + (typeof detalhe === 'string' ? detalhe : JSON.stringify(detalhe))));
};
const erro = async (sql, p) => { try { await q(sql, p); return null; } catch (e) { return String(e.message || e); } };
const decidir = async (op, aut = null) => (await um('select public.hermes_porta_decidir($1::jsonb, $2::bigint) as r', [JSON.stringify(op), aut])).r;
const classe = async (tipo, objeto) => (await um('select classe from public.hermes_porta_classes where tipo=$1 and objeto=$2', [tipo, objeto]))?.classe;
const pedir = async (acao, valor, op, t = false) => (await um('select public.hermes_autorizacao_pedir($1,$2,$3,$4::jsonb,$5) as r', [acao, 'prova local', valor, JSON.stringify(op), t])).r;
const dec = async (id, d, via, texto = null) => (await um('select public.hermes_autorizacao_decidir($1,$2,$3,$4,$5,$6) as r', [id, d, via, 'danilo', texto, 111])).r;
const lerSql = async (sql, lim = 200) => (await um('select public.hermes_porta_sql_ler($1,$2) as r', [sql, lim])).r;

await exec(readFileSync(resolve(AQUI, 'porta_stubs.sql'), 'utf8'));
await exec(readFileSync(resolve(REPO, 'supabase/migrations/20261122190000_hermes_diretor_tabelas.sql'), 'utf8'));
const MIG = readFileSync(resolve(REPO, 'supabase/migrations/20261122190200_hermes_porta_funcoes.sql'), 'utf8');
await exec(MIG);
await exec(MIG);   // repetível
console.log('stubs + contrato + migração da porta carregados (2 vezes)\n');

// ── 0. estrutura
const job = await q(`select * from cron.job where jobname='hermes-porta-reclassificar'`);
teste('0a reclassificação agendada uma só vez', job.length === 1, job.length);
const ag = await um(`select arquivado, substituto from public.agentes_estado where agente='critico'`);
teste('0b a marca ARQUIVADO da nota passou para a coluna (substituto=fiscal)', ag.arquivado === true && ag.substituto === 'fiscal', ag);
const dono = await um(`select pg_get_userbyid(proowner) d, provolatile v from pg_proc where proname='hermes_porta_sql_ler'`);
teste('0c a leitura livre pertence ao papel de leitura e é STABLE', dono.d === 'hermes_leitor' && dono.v === 's', dono);

// ── A. sem semente: tudo trancado
let r = (await um('select public.hermes_porta_reclassificar() as r')).r;
teste('A1 sem semente a classificação diz com_semente=false', r.com_semente === false, r);
teste('A2 sem semente uma tabela normal fica como valor (trancada)', await classe('tabela', 'clientes_teste') === 'dinheiro');
let d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'clientes_teste', query: 'id=eq.1', corpo: { nota: 'x' } });
teste('A3 sem semente até um campo inocente pede o autorizo', d.permitido === false && d.precisa_autorizo === true, d);

// ── B. com semente: cada coisa na sua classe
await exec(`insert into public.platform_settings (key, value, category) values ('hermes_porta_dinheiro', '{
  "padrao_tabelas": "(carteira|pagamento)", "padrao_funcoes": "(pagar|reembols)", "padrao_colunas": "(preco|taxa|_cents$)",
  "padrao_chaves": "(comissao|preco|taxa)", "padrao_segredo_tabelas": "(push_tokens)$", "padrao_segredo_colunas": "^(iban|nif|fcm_token)$"
}'::jsonb, 'hermes')`);
r = (await um('select public.hermes_porta_reclassificar() as r')).r;
const sinc = (await um('select public.hermes_porta_leitor_sincronizar() as r')).r;
teste('B1 tabela normal = livre', await classe('tabela', 'clientes_teste') === 'livre');
teste('B2 tabela de valor pelo nome = dinheiro', await classe('tabela', 'carteiras_teste') === 'dinheiro');
teste('B3 tabela livre com gatilho que mexe em valores = dinheiro', await classe('tabela', 'registos_teste') === 'dinheiro');
teste('B4 cópia de segurança = controlo', await classe('tabela', 'bkp_clientes_20261101') === 'controlo');
teste('B5 pedidos = operação', await classe('tabela', 'orders') === 'operacao');
teste('B6 tabela de chaves de aviso = segredo', await classe('tabela', 'avisos_push_tokens') === 'segredo');
teste('B7 as tabelas da própria porta = controlo/segredo', await classe('tabela', 'hermes_autorizacoes') === 'controlo' && await classe('tabela', 'hermes_porta_classes') === 'controlo');
teste('B8 função de valor pelo nome', await classe('funcao', 'pagar_parceiro_teste') === 'dinheiro');
teste('B9 função que mexe numa tabela de valor (nome inocente)', await classe('funcao', 'ajusta_escondido_teste') === 'dinheiro');
teste('B10 função que CHAMA uma função de valor (contágio)', await classe('funcao', 'chama_ajuste_teste') === 'dinheiro');
teste('B11 função normal = livre; função que só lê valores = livre', await classe('funcao', 'marcar_visto_teste') === 'livre' && await classe('funcao', 'ler_total_teste') === 'livre');
teste('B12 função que lê o cofre = segredo', await classe('funcao', 'le_cofre_teste') === 'segredo');
teste('B13 ops_reassign_order = operação; outra função que mexe em pedidos = dinheiro', await classe('funcao', 'ops_reassign_order') === 'operacao' && await classe('funcao', 'fecha_pedido_teste') === 'dinheiro');
teste('B14 as funções da porta e das autorizações = controlo', await classe('funcao', 'hermes_autorizacao_decidir') === 'controlo' && await classe('funcao', 'hermes_porta_reclassificar') === 'controlo');

// ── C. as 7 provas da missão (a…g)
let l = await lerSql('select count(*)::int as n from orders');
teste('(a) ler uma tabela qualquer: contagem de pedidos', l.ok === true && l.linhas[0].n === 2, l);
d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'clientes_teste', query: 'id=eq.1', corpo: { nota: 'ligar amanha' } });
teste('(b) PATCH num campo não-financeiro de uma tabela de teste: permitido', d.permitido === true && d.classe === 'livre', d);
const opCarteira = { tipo: 'rest', metodo: 'PATCH', tabela: 'carteiras_teste', query: 'id=eq.1', corpo: { saldo_cents: 1000 } };
d = await decidir(opCarteira);
teste('(c) PATCH numa tabela de valor sem autorização: recusado com "precisa do autorizo do Danilo"', d.permitido === false && d.precisa_autorizo === true && /precisa do autorizo do Danilo/.test(d.motivo), d);
const opApagar = { tipo: 'rest', metodo: 'DELETE', tabela: 'clientes_teste', query: 'id=eq.2' };
d = await decidir(opApagar);
teste('(d) DELETE sem autorização: recusado (mesmo em tabela livre)', d.permitido === false && d.precisa_autorizo === true && /apagar/.test(d.motivo), d);
let p = await pedir('Pôr 10 euros na carteira de teste', 10, opCarteira, true);
let av = await q(`select * from public.avisos_teste order by id`);
let linha = await um('select estado, teste, valor_eur::text v, expira_em > now() + interval \'29 minutes\' as validade from public.hermes_autorizacoes where id=$1', [p.id]);
teste('(e) pedir_autorizacao: linha pendente + UMA mensagem ao Danilo com "TESTE da missão — não precisas de fazer nada" e o link do painel',
  p.ok === true && linha.estado === 'pendente' && linha.teste === true && linha.validade === true && av.length === 1 && /TESTE da missão — não precisas de fazer nada/.test(av[0].texto) && av[0].link === '/admin/autorizacoes/' + p.id, { p, linha, av });
const p2 = await pedir('Pôr 10 euros na carteira de teste', 10, opCarteira, true);
teste('(e2) o mesmo pedido repetido não cria outro nem manda outra mensagem', p2.id === p.id && p2.repetido === true && (await q('select 1 from public.avisos_teste')).length === 1, p2);
d = await decidir(opCarteira, p.id);
teste('(e3) autorização ainda pendente não deixa passar', d.permitido === false && /ainda nao autorizou/.test(d.motivo), d);
await exec(`update public.hermes_autorizacoes set expira_em = now() - interval '1 minute' where id = ${p.id}`);
d = await decidir(opCarteira, p.id);
teste('(f) autorização expirada: recusada', d.permitido === false && /expirou/.test(d.motivo), d);
p = await pedir('Pôr 10 euros na carteira de teste', 10, opCarteira);
let dd = await dec(p.id, 'autorizada', 'telegram', 'ok pode ser');
teste('(g0) "autorizo" pelo Telegram sem a palavra autorizo: não vale', dd.ok === false, dd);
dd = await dec(p.id, 'autorizada', 'telegram', 'eu autorizo 2');
av = await q(`select texto from public.avisos_teste order by id desc limit 1`);
teste('(g1) com a palavra: autorizada, e sai logo a confirmação "Registei o teu autorizo… Se não foste tu, responde NÃO"', dd.ok === true && /Registei o teu autorizo/.test(av[0].texto) && /responde NÃO/.test(av[0].texto), { dd, av });
d = await decidir({ ...opCarteira, corpo: { saldo_cents: 999999 } }, p.id);
teste('(g2) a autorização só serve para a operação exata (outro valor é recusado e NÃO a gasta)', d.permitido === false && /nao e a mesma/.test(d.motivo), d);
d = await decidir(opCarteira, p.id);
teste('(g3) 1.ª vez com a operação certa: passa', d.permitido === true && d.autorizacao_id == p.id, d);
d = await decidir(opCarteira, p.id);
teste('(g) autorização usada 2 vezes: a 2.ª é recusada', d.permitido === false && /ja foi usada/.test(d.motivo), d);
const aud = await um(`select count(*)::int n from public.admin_audit_log where action like 'hermes_autorizacao_%'`);
teste('(g4) tudo fica no registo de auditoria', aud.n >= 3, aud);

// ── D. as outras regras da porta
d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'clientes_teste', query: 'select=id', corpo: { nota: 'x' } });
teste('D1 PATCH sem filtro: recusado', d.permitido === false && /filtro/.test(d.motivo), d);
d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'orders', query: 'id=eq.P1', corpo: { status: 'cancelled' } });
teste('D2 escrever em pedidos: recusado, manda para as funções ops_*', d.permitido === false && /ops_reassign_order/.test(d.motivo), d);
d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'hermes_autorizacoes', query: 'id=eq.1', corpo: { estado: 'autorizada' } });
teste('D3 o Hermes não consegue aprovar o próprio pedido (tabela de controlo)', d.permitido === false && d.classe === 'controlo', d);
d = await decidir({ tipo: 'rpc', funcao: 'hermes_autorizacao_decidir', args: { p_id: 1 } });
teste('D4 nem chamar a função que decide', d.permitido === false && d.classe === 'controlo', d);
d = await decidir({ tipo: 'rest', metodo: 'GET', tabela: 'avisos_push_tokens' });
teste('D5 tabela de segredos: nem ler', d.permitido === false && d.classe === 'segredo', d);
d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'produtos_teste', query: 'id=eq.1', corpo: { nome: 'Arroz agulha', disponivel: false } });
const d2 = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'produtos_teste', query: 'id=eq.1', corpo: { preco: 0.01 } });
teste('D6 produto: mudar nome e disponibilidade passa; mudar o preço pede o autorizo', d.permitido === true && d2.permitido === false && d2.precisa_autorizo === true && /preco/.test(d2.motivo), { d, d2 });
d = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'platform_settings', query: 'key=eq.sentinela_minutos_loja', corpo: { value: 9 } });
const d3 = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'platform_settings', query: 'key=eq.comissao_parceiro_pct', corpo: { value: 1 } });
const d4 = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'platform_settings', query: 'key=eq.hermes_porta_dinheiro', corpo: { value: {} } });
const d5 = await decidir({ tipo: 'rest', metodo: 'PATCH', tabela: 'platform_settings', query: 'key=eq.chave_api_externa', corpo: { value: 'x' } });
teste('D7 definições: limiar do vigia passa; comissão pede o autorizo; a lista do dinheiro e os segredos não se tocam',
  d.permitido === true && d3.precisa_autorizo === true && d4.permitido === false && d4.classe === 'controlo' && d5.permitido === false, { d, d3, d4, d5 });
await exec(`create table public.tabela_nova_teste (id int primary key, x text)`);
d = await decidir({ tipo: 'rest', metodo: 'POST', tabela: 'tabela_nova_teste', corpo: { id: 1 } });
teste('D8 tabela criada depois da classificação: na dúvida, pede o autorizo', d.permitido === false && d.precisa_autorizo === true && /nao classificada/.test(d.motivo), d);
d = await decidir({ tipo: 'rpc', funcao: 'marcar_visto_teste', args: { p: 1 } });
const d6 = await decidir({ tipo: 'rpc', funcao: 'chama_ajuste_teste', args: {} });
const d7 = await decidir({ tipo: 'rpc', funcao: 'le_cofre_teste', args: {} });
const d8 = await decidir({ tipo: 'rpc', funcao: 'ops_reassign_order', args: { p_order_id: 'P1' } });
const d9 = await decidir({ tipo: 'rpc', funcao: 'fecha_pedido_teste', args: { p: 'P1' } });
teste('D9 funções: normal passa; a de valor por contágio pede o autorizo; a do cofre nunca; ops_reassign_order passa; mexer em pedidos por fora pede o autorizo',
  d.permitido === true && d6.precisa_autorizo === true && d7.permitido === false && d8.permitido === true && d9.precisa_autorizo === true, { d, d6, d7, d8, d9 });
await exec(`set app.admin = '0'`);
dd = (await um(`select public.admin_hermes_autorizacao_decidir(1, 'autorizada', null) as r`)).r;
teste('D10 o botão do painel só funciona para o administrador', dd.ok === false && /administrador/.test(dd.erro), dd);
p = await pedir('Apagar o cliente de teste 2', null, opApagar);
await exec(`set app.admin = '1'`);
dd = (await um(`select public.admin_hermes_autorizacao_decidir(${p.id}, 'autorizada', null) as r`)).r;
d = await decidir(opApagar, p.id);
const g = (await um(`select public.hermes_apagados_guardar(${p.id}, 'clientes_teste', '[{"id":2,"nome":"Rui"}]'::jsonb) as n`)).n;
teste('D11 apagar com o botão Autorizo do painel: passa uma vez e a linha apagada fica guardada', dd.ok === true && d.permitido === true && g === 1 && (await um('select count(*)::int n from public.hermes_apagados')).n === 1, { dd, d, g });
const opAnular = { tipo: 'rest', metodo: 'PATCH', tabela: 'carteiras_teste', query: 'id=eq.1', corpo: { saldo_cents: 7 } };
p = await pedir('Teste de anular', 1, opAnular);
await dec(p.id, 'autorizada', 'telegram', 'autorizo');
const an = (await um(`select public.hermes_autorizacao_anular(${p.id}, 'danilo-telegram', 'NÃO') as r`)).r;
d = await decidir(opAnular, p.id);
teste('D11b o Danilo responde NÃO à confirmação: o autorizo é anulado e já não serve', an.ok === true && d.permitido === false && /recusou/.test(d.motivo), { an, d });
for (let i = 0; i < 12; i++) await pedir('pedido ' + i, 1, { tipo: 'rest', metodo: 'DELETE', tabela: 'clientes_teste', query: 'id=eq.' + (100 + i) });
const pend = (await um(`select count(*)::int n from public.hermes_autorizacoes where estado='pendente'`)).n;
teste('D12 no máximo 10 pedidos à espera do Danilo ao mesmo tempo', pend === 10, pend);

// ── E. ler tudo, menos segredos, e sem conseguir escrever
teste('E1 a sincronização abriu tabelas inteiras, algumas só por colunas, e fechou as de segredo', sinc.inteiras > 3 && sinc.so_colunas_sem_segredo >= 1 && sinc.fechadas >= 2, sinc);
l = await lerSql('select id, nome from parceiros_teste');
let e = await erro(`select public.hermes_porta_sql_ler('select iban from parceiros_teste')`);
const e2 = await erro(`select public.hermes_porta_sql_ler('select * from parceiros_teste')`);
teste('E2 tabela com colunas reservadas: lê o nome, não lê o IBAN (nem por select *)', l.linhas[0].nome === 'Loja A' && /permission denied/.test(e || '') && /permission denied/.test(e2 || ''), { l, e, e2 });
e = await erro(`select public.hermes_porta_sql_ler('select * from avisos_push_tokens')`);
teste('E3 tabela de segredos: permissão negada', /permission denied/.test(e || ''), e);
e = await erro(`select public.hermes_porta_sql_ler('select * from platform_settings')`);
l = await lerSql(`select key, value, is_secret from hermes_platform_settings where key in ('chave_api_externa','sentinela_minutos_loja') order by key`);
teste('E4 definições: a tabela não abre; a vista mostra tudo com os segredos tapados', /permission denied/.test(e || '') && l.linhas[0].value === null && l.linhas[0].is_secret === true && l.linhas[1].value === 8, { e, l });
e = await erro(`select public.hermes_porta_sql_ler('with x as (insert into clientes_teste values (9, ''z'', null) returning 1) select * from x')`);
const ficou = (await um('select count(*)::int n from public.clientes_teste where id = 9')).n;
teste('E5 tentativa de ESCREVER dentro de um SELECT: o Postgres recusa e nada é escrito', /permission denied|data-modifying statement must be at the top level/.test(e || '') && ficou === 0, { e, ficou });
e = await erro(`select public.hermes_porta_sql_ler('update clientes_teste set nome = ''x''')`);
const e3 = await erro(`select public.hermes_porta_sql_ler('select 1; select 2')`);
const e4 = await erro(`select public.hermes_porta_sql_ler('select query_to_xml(''select 1'', true, false, '''')')`);
teste('E6 só SELECT, uma instrução só, sem funções de SQL dinâmico', /so leitura/.test(e || '') && /uma instrucao so/.test(e3 || '') && /nao deixa/.test(e4 || ''), { e, e3, e4 });
e = await erro(`select public.hermes_porta_sql_ler('select public.le_cofre_teste()')`);
teste('E7 chamar pela leitura uma função fechada (as novas nascem fechadas): permissão negada ou barrada', e !== null, e);
l = await lerSql('select generate_series(1, 5000) as n', 5000);
teste('E8 no máximo 1000 linhas por leitura', l.n === 1000, l.n);
const cols = (await um(`select public.hermes_porta_colunas('parceiros_teste') as c`)).c;
teste('E9 a operação colunas diz o que se pode ler', JSON.stringify(cols) === JSON.stringify(['id', 'nome']), cols);
d = await decidir({ tipo: 'rest', metodo: 'GET', tabela: 'parceiros_teste' });
const d10 = await decidir({ tipo: 'rest', metodo: 'GET', tabela: 'clientes_teste' });
teste('E10 pela leitura REST só passa a tabela que se pode ler inteira', d.permitido === false && /colunas reservadas/.test(d.motivo) && d10.permitido === true, { d, d10 });
const priv = await um(`select has_function_privilege('anon', 'public.hermes_porta_decidir(jsonb,bigint)', 'execute') a, has_function_privilege('authenticated', 'public.hermes_autorizacao_decidir(bigint,text,text,text,text,bigint)', 'execute') b, has_function_privilege('service_role', 'public.hermes_porta_decidir(jsonb,bigint)', 'execute') c, has_function_privilege('authenticated', 'public.admin_hermes_autorizacao_decidir(bigint,text,text)', 'execute') d`);
teste('E11 nada disto se abre a anon nem a utilizadores; só a porta (service_role) e o botão do admin', priv.a === false && priv.b === false && priv.c === true && priv.d === true, priv);

console.log(`\nRESULTADO: ${ok.length} passaram, ${falhou.length} falharam`);
if (falhou.length) { console.log('FALHARAM:\n - ' + falhou.join('\n - ')); process.exit(1); }
