// Prova local (PGlite) das migrações …190000 (contrato) e …190300 (fiscal e lições). Não toca em produção.
// Uso: node provar_fiscal_licoes.mjs
// Se o PGlite não estiver instalado ao pé deste ficheiro, PGLITE_DIR = pasta que tem node_modules/@electric-sql/pglite.
import { readFileSync } from 'node:fs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const AQUI = dirname(fileURLToPath(import.meta.url));
const M = join(AQUI, '..', '..', 'migrations');
let PGlite;
try { ({ PGlite } = await import('@electric-sql/pglite')); }
catch {
  const r = createRequire(join(process.env.PGLITE_DIR, 'x.js'));
  ({ PGlite } = await import(pathToFileURL(r.resolve('@electric-sql/pglite')).href));
}

const db = new PGlite();
const ok = [], falhou = [];
const q = async (sql, p) => (await db.query(sql, p)).rows;
const espera = async (nome, fn, cond) => {
  try { const r = await fn(); const v = cond(r); (v ? ok : falhou).push(nome + (v ? '' : ' -> ' + JSON.stringify(r).slice(0, 400))); return r; }
  catch (e) { falhou.push(nome + ' -> ERRO ' + e.message); }
};
const erro = async (nome, fn, texto) => {
  try { await fn(); falhou.push(nome + ' -> não deu erro'); }
  catch (e) { const v = e.message.includes(texto); (v ? ok : falhou).push(nome + (v ? '' : ' -> ' + e.message)); }
};
const carrega = async (nome, ficheiro) => {
  try { await db.exec(readFileSync(ficheiro, 'utf8')); ok.push('carrega ' + nome); }
  catch (e) { console.log('FALHOU a carregar', nome, e.message, e.where ?? ''); process.exit(2); }
};

await carrega('stubs', join(AQUI, 'fiscal_stubs.sql'));
await carrega('contrato 190000', join(M, '20261122190000_hermes_diretor_tabelas.sql'));
await carrega('fiscal e licoes 190300', join(M, '20261122190300_fiscal_e_licoes.sql'));
// 2.ª carga: a migração tem de poder correr outra vez sem duplicar lições
await carrega('fiscal e licoes 190300 (2.a vez)', join(M, '20261122190300_fiscal_e_licoes.sql'));

const PROVA = JSON.stringify({ tipo: 'select', conteudo: 'select count(*) from orders -> 12', como_refazer: 'select count(*) from orders' });
const nova = async (para, precisa) =>
  (await q(`insert into despacho(para, titulo, tarefa, precisa_auditoria) values ($1,'t','faz isto',$2) returning id`, [para, precisa]))[0].id;
const fechar = (id, prova) => q(`update despacho set estado='feita', terminada_em=now(), prova_dados=$2::jsonb where id=$1 returning estado, terminada_em, auditada, auditoria_nota`, [id, prova]);
const ver = async (id) => (await q(`select estado, para, auditada, auditoria_tentativas, auditoria_nota, tarefa, terminada_em from despacho where id=$1`, [id]))[0];

// ── constraint ──
await espera('0: o CHECK do estado tem os 8 estados, com a-auditar',
  () => q(`select pg_get_constraintdef(oid) d from pg_constraint where conname='despacho_estado_check'`),
  r => r[0].d.includes('a-auditar') && (r[0].d.match(/'[a-z-]+'::text/g) || []).length === 8);

// ── (1) prova certa → a-auditar → auditar ok → feita ──
const t1 = await nova('hermes', true);
await espera('1a: com prova valida fica a-auditar', () => fechar(t1, PROVA), r => r[0].estado === 'a-auditar' && r[0].auditada === null);
await espera('1b: auditar(ok) -> feita e auditada=true',
  async () => { const a = (await q(`select despacho_auditar($1,true,'conferi no SELECT') r`, [t1]))[0].r; return [a, await ver(t1)]; },
  ([a, v]) => a.ok && v.estado === 'feita' && v.auditada === true && v.terminada_em !== null && v.auditoria_nota === 'conferi no SELECT');
await espera('1c: auditar outra vez uma tarefa feita e recusado', () => q(`select despacho_auditar($1,true,'x') r`, [t1]),
  r => r[0].r.ok === false && r[0].r.erro === 'estado_errado');

// ── (2) prova falsa: devolvida 2 vezes ao mesmo agente, à 3.ª falhou ──
const t2 = await nova('emerson', true);
await fechar(t2, PROVA);
await espera('2a: 1.a devolucao -> aberta, mesmo agente, nota no fim da tarefa',
  async () => { await q(`select despacho_auditar($1,false,'o SELECT da 11, nao 12')`, [t2]); return ver(t2); },
  v => v.estado === 'aberta' && v.para === 'emerson' && v.auditoria_tentativas === 1 && v.auditada === false
    && v.tarefa.endsWith('\n[FISCAL 1/2] o SELECT da 11, nao 12') && v.terminada_em === null);
await fechar(t2, PROVA);
await espera('2b: com nova prova volta a a-auditar', () => ver(t2), v => v.estado === 'a-auditar');
await espera('2c: 2.a devolucao -> aberta, [FISCAL 2/2], mesmo agente',
  async () => { await q(`select despacho_auditar($1,false,'continua errado')`, [t2]); return ver(t2); },
  v => v.estado === 'aberta' && v.para === 'emerson' && v.auditoria_tentativas === 2
    && v.tarefa.includes('[FISCAL 1/2]') && v.tarefa.endsWith('[FISCAL 2/2] continua errado'));
await fechar(t2, PROVA);
await espera('2d: 3.a falha -> falhou (sem o vigia instalado nao rebenta)',
  async () => { const a = (await q(`select despacho_auditar($1,false,'prova falsa outra vez') r`, [t2]))[0].r; return [a, await ver(t2)]; },
  ([a, v]) => a.ok && a.estado === 'falhou' && v.estado === 'falhou' && v.auditoria_tentativas === 3 && v.auditada === false);
// com o vigia presente, a 3.ª falha regista um evento urgente
await db.exec(`create table sentinela_log (tipo text, gravidade text, chave text, titulo text, dados jsonb);
  create function public.sentinela_registar(a text,b text,c text,d text,e jsonb) returns bigint language plpgsql as $$ begin insert into sentinela_log values (a,b,c,d,e); return 1; end $$;`);
const t2b = await nova('hermes', true);
for (const nota of ['a', 'b', 'c']) { await fechar(t2b, PROVA); await q(`select despacho_auditar($1,false,$2)`, [t2b, nota]); }
await espera('2e: 3.a falha com o vigia -> evento urgente, tipo sistema, para o emerson', () => q(`select * from sentinela_log`),
  r => r.length === 1 && r[0].tipo === 'sistema' && r[0].gravidade === 'urgente' && r[0].dados.para === 'emerson' && Number(r[0].dados.despacho_id) === Number(t2b));

// ── (3) precisa de auditoria e vem sem prova: nao fecha ──
for (const [rotulo, prova] of [
  ['sem prova_dados', null],
  ['tipo inventado', JSON.stringify({ tipo: 'palavra', conteudo: 'fiz' })],
  ['conteudo vazio', JSON.stringify({ tipo: 'log', conteudo: '  ' })],
  ['prova que nao e objeto', JSON.stringify('fiz')]]) {
  const t = await nova('hermes', true);
  await espera('3: ' + rotulo + ' -> aberta, sem contar tentativa',
    async () => { await fechar(t, prova); return ver(t); },
    v => v.estado === 'aberta' && v.auditoria_tentativas === 0
      && v.auditoria_nota === 'sem prova: a tarefa só fecha com prova verificável' && v.terminada_em === null);
}
const tAuto = await nova('hermes', true);
await espera('3b: o agente nao consegue marcar auditada=true sozinho (sem prova)',
  async () => { await q(`update despacho set estado='feita', auditada=true, prova_dados=null where id=$1`, [tAuto]); return ver(tAuto); },
  v => v.estado === 'aberta' && v.auditada !== true);
const tAuto2 = await nova('hermes', true);
await espera('3c: nem com prova valida (fica a-auditar, auditada nao passa)',
  async () => { await q(`update despacho set estado='feita', auditada=true, prova_dados=$2::jsonb where id=$1`, [tAuto2, PROVA]); return ver(tAuto2); },
  v => v.estado === 'a-auditar' && v.auditada !== true);

// ── (4) tarefa normal fecha como hoje ──
const t4 = await nova('hermes', false);
await espera('4: sem precisa_auditoria fecha direto, sem prova', () => fechar(t4, null),
  r => r[0].estado === 'feita' && r[0].terminada_em !== null && r[0].auditada === null);

// ── (9) percentagem ──
for (let i = 0; i < 2; i++) { const t = await nova('agente-p', true); await fechar(t, PROVA); await q(`select despacho_auditar($1,true,'ok')`, [t]); }
const tPend = await nova('agente-p', true); await fechar(tPend, PROVA);   // fica a-auditar
await nova('agente-p', false).then(t => fechar(t, null));                  // normal: nao conta nas auditorias
await espera('9a: vista por agente: 4 terminadas, 3 precisavam, 2 auditadas ok -> 66.7%',
  () => q(`select * from despacho_auditoria_24h where agente='agente-p'`),
  r => Number(r[0].terminadas) === 4 && Number(r[0].precisavam_auditoria) === 3 && Number(r[0].auditadas_ok) === 2 && Number(r[0].pct_auditadas) === 66.7);
await espera('9b: o resumo total bate com a conta feita a mao', async () => {
  const mao = (await q(`select count(*) filter (where precisa_auditoria and terminada_em >= now()-interval '24 hours') p,
                               count(*) filter (where precisa_auditoria and auditada is true and terminada_em >= now()-interval '24 hours') o from despacho`))[0];
  const r = (await q(`select despacho_auditoria_resumo() r`))[0].r;
  return { mao, r };
}, ({ mao, r }) => r.precisavam_auditoria === Number(mao.p) && r.auditadas_ok === Number(mao.o)
  && Number(r.pct_auditadas) === Math.round(1000 * Number(mao.o) / Number(mao.p)) / 10);

// ── (5) licoes: soma e nao duplica ──
await espera('5a: licoes iniciais = 6 x 3 robos = 18; a 2.a carga da migracao nao duplicou',
  () => q(`select count(*)::int n, min(vezes) mn, max(vezes) mx from licoes_robos where origem='missao-hermes-diretor'`),
  r => r[0].n === 18 && r[0].mn === 1 && r[0].mx === 1);
const l1 = (await q(`select licao_robo_gravar('suporte','respondeu mal','  Nunca digas X ao cliente  ','fiscal') id`))[0].id;
const l2 = (await q(`select licao_robo_gravar('suporte','outra vez','nunca digas x ao cliente') id`))[0].id;
await espera('5b: a mesma regra 2 vezes soma vezes e nao duplica',
  () => q(`select count(*)::int n, max(vezes) v from licoes_robos where robo='suporte' and lower(btrim(regra))='nunca digas x ao cliente'`),
  r => r[0].n === 1 && r[0].v === 2 && String(l1) === String(l2));
await espera('5c: o mesmo texto noutro robo e outra licao',
  async () => { await q(`select licao_robo_gravar('amigo','e','nunca digas x ao cliente')`); return q(`select count(*)::int n from licoes_robos where lower(btrim(regra))='nunca digas x ao cliente'`); },
  r => r[0].n === 2);
await erro('5d: robo invalido e recusado', () => q(`select licao_robo_gravar('chefe','e','r')`), 'robô inválido');
await erro('5e: regra vazia e recusada', () => q(`select licao_robo_gravar('amigo','e','   ')`), 'não podem ficar vazios');
await espera('5f: texto longo e cortado a 600',
  async () => { const id = (await q(`select licao_robo_gravar('hermes','e',repeat('a',900)) id`))[0].id; return q(`select length(regra) l from licoes_robos where id=$1`, [id]); },
  r => r[0].l === 600);
await espera('5g: repetir uma licao arquivada reativa-a', async () => {
  await q(`update licoes_robos set ativa=false, arquivada_em=now(), arquivada_por='danilo' where id=$1`, [l1]);
  await q(`select licao_robo_gravar('suporte','e','nunca digas x ao cliente')`);
  return q(`select ativa, arquivada_em, vezes, editada_em is not null ed from licoes_robos where id=$1`, [l1]);
}, r => r[0].ativa === true && r[0].arquivada_em === null && r[0].vezes === 3 && r[0].ed === true);

// ── (6) licoes_robo_texto: corte e arquivadas ──
await db.exec(`insert into licoes_robos(robo,errou,regra,vezes) values
  ('whatsapp','e','regra A repetida',5),('whatsapp','e','regra B',2),('whatsapp','e','regra C',1),
  ('whatsapp','e','regra ARQUIVADA',9),('whatsapp','e','regra INATIVA',9);
  update licoes_robos set arquivada_em=now() where regra='regra ARQUIVADA';
  update licoes_robos set ativa=false where regra='regra INATIVA';`);
const todas = (await q(`select licoes_robo_texto('whatsapp', 100000) t`))[0].t;
await espera('6a: mais repetidas primeiro, formato "- regra", sem arquivadas nem inativas',
  async () => todas.split('\n').filter(l => /regra (A|B|C|ARQ|INA)/.test(l)),
  l => JSON.stringify(l) === JSON.stringify(['- regra A repetida', '- regra B', '- regra C']));
await espera('6b: p_max corta em linhas inteiras e nunca passa o limite', async () => {
  const dois = '- regra A repetida\n- regra B';
  const t = (await q(`select licoes_robo_texto('whatsapp', $1) t`, [dois.length + 3]))[0].t;   // a 3.ª linha ja nao cabe
  return { dois, t };
}, ({ dois, t }) => t === dois);
await espera('6c: p_max=20 devolve no maximo 20 caracteres', async () => (await q(`select licoes_robo_texto('whatsapp', 20) t`))[0].t, t => t.length > 0 && t.length <= 20);
await espera('6d: robo sem licoes devolve texto vazio', async () => (await q(`select licoes_robo_texto('sem-licoes', 2500) t`))[0].t, t => t === '');
await espera('6e: o bloco do amigo traz a regra do Editar perfil, a dos tokens e a da zona',
  async () => (await q(`select licoes_robo_texto('amigo', 2500) t`))[0].t,
  t => t.includes('«Editar perfil»') && t.includes('metade do valor dos tokens') && t.includes('Pinhel') && t.length <= 2500);

// ── (7) casos de teste ──
const c1 = (await q(`select robo_caso_gravar('amigo','Como edito o meu perfil?', array['Editar perfil'], array['não existe'], $1) id`, [l1]))[0].id;
await espera('7a: caso gravado (nunca corrido)',
  () => q(`select ativo, ultimo_resultado, ultima_corrida_em, licao_id, deve_conter from robos_casos_teste where id=$1`, [c1]),
  r => r[0].ativo && r[0].ultimo_resultado === null && r[0].ultima_corrida_em === null && String(r[0].licao_id) === String(l1) && r[0].deve_conter[0] === 'Editar perfil');
await espera('7b: resultado registado (passou)',
  async () => { await q(`select robo_caso_resultado($1,true,'Toca em Perfil > Editar perfil')`, [c1]); return q(`select ultimo_resultado, ultima_resposta, ultima_corrida_em is not null c from robos_casos_teste where id=$1`, [c1]); },
  r => r[0].ultimo_resultado === 'passou' && r[0].ultima_resposta.startsWith('Toca em Perfil') && r[0].c);
await espera('7c: a mesma pergunta atualiza o caso em vez de duplicar',
  async () => { const id = (await q(`select robo_caso_gravar('amigo','  como edito o meu PERFIL? ', array['Editar perfil'], '{}') id`))[0].id; return [id, (await q(`select count(*)::int n from robos_casos_teste`))[0].n]; },
  ([id, n]) => String(id) === String(c1) && n === 1);
const c2 = (await q(`select robo_caso_gravar('suporte','Entregam em Pinhel?', array['só na Guarda'], '{}') id`))[0].id;
await q(`select robo_caso_resultado($1,false,'Sim, entregamos')`, [c2]);
await q(`select robo_caso_gravar('suporte','Pergunta nova sem correr', array['x'], '{}')`);
await erro('7d: caso sem condicoes e recusado', () => q(`select robo_caso_gravar('amigo','p', '{}', '{}')`), 'pelo menos uma condição');
await erro('7e: resultado de caso que nao existe', () => q(`select robo_caso_resultado(99999,true,'x')`), 'não existe');
await espera('7f: regressao geral: 3 ativos, 1 passou, 1 falhou, 1 nunca corrido, nao pode publicar',
  async () => (await q(`select robos_regressao_resumo() r`))[0].r,
  r => r.casos_ativos === 3 && r.passaram === 1 && r.falharam === 1 && r.nunca_corridos === 1 && r.pode_publicar === false && r.ultima_corrida !== null);
await espera('7g: regressao so do amigo: 1 ativo, passou, pode publicar',
  async () => (await q(`select robos_regressao_resumo('amigo') r`))[0].r,
  r => r.casos_ativos === 1 && r.passaram === 1 && r.falharam === 0 && r.pode_publicar === true);

// ── (8) mapa da app ──
await db.exec(`insert into mapa_app(app, ecra, rota, elemento, tipo, ficheiro, versao) values
  ('cliente','EditProfileScreen','/perfil/editar','Editar Perfil','botao','lib/screens/edit_profile_screen.dart','1.0.0+1'),
  ('cliente','ProfileScreen',null,'Terminar sessão','botao','lib/screens/profile_screen.dart','1.0.0+1'),
  ('admin','AdminClientsScreen',null,'Editar perfil do cliente','botao','lib/screens/admin/admin_clients_screen.dart','1.0.0+1');`);
await espera('8a: "editar perfil" encontra "Editar Perfil" (sem maiusculas)',
  async () => (await q(`select mapa_app_tem('editar perfil') r`))[0].r,
  r => r.existe === true && r.total === 2 && r.encontrados.some(e => e.elemento === 'Editar Perfil' && e.app === 'cliente'));
await espera('8b: sem acentos: "TERMINAR SESSAO" encontra "Terminar sessão"',
  async () => (await q(`select mapa_app_tem('TERMINAR SESSAO') r`))[0].r, r => r.existe === true && r.encontrados[0].elemento === 'Terminar sessão');
await espera('8c: um botao inventado nao existe',
  async () => (await q(`select mapa_app_tem('Apagar conta de ouro') r`))[0].r, r => r.existe === false && r.total === 0);
await espera('8d: filtrar por app: "editar perfil" so no cliente', async () => (await q(`select mapa_app_tem('editar perfil','cliente') r`))[0].r, r => r.total === 1);
await espera('8e: texto vazio nao encontra nada', async () => (await q(`select mapa_app_tem('   ') r`))[0].r, r => r.existe === false);

// ── permissoes ──
await db.exec(`insert into auth.users values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin@teste.local'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cliente@exemplo.pt');`);
// "set session authorization" muda o session_user, como o PostgREST (que liga como "authenticator")
const como = async (uid, sql) => {
  await db.exec(`set session authorization fake_authenticator; set role authenticated; select set_config('request.jwt.claim.sub','${uid ?? ''}',false);`);
  try { return await q(sql); }
  finally { await db.exec(`reset role; reset session authorization; select set_config('request.jwt.claim.sub','',false);`); }
};
const ADMIN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', CLI = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
await espera('P1: admin autenticado le o resumo do fiscal', () => como(ADMIN, `select despacho_auditoria_resumo() r`), r => r[0].r.precisavam_auditoria >= 3);
await espera('P2: admin autenticado usa o mapa e a regressao',
  async () => [await como(ADMIN, `select mapa_app_tem('editar perfil') r`), await como(ADMIN, `select robos_regressao_resumo() r`)],
  ([a, b]) => a[0].r.existe === true && b[0].r.casos_ativos === 3);
for (const f of ['despacho_auditoria_resumo()', 'robos_regressao_resumo()', `mapa_app_tem('x')`]) {
  const r = await como(CLI, `select ${f}`).then(() => 'deixou', e => e.message);
  (r.includes('só para administradores') ? ok : falhou).push('P3: cliente normal recusado em ' + f + (r.includes('só para administradores') ? '' : ' -> ' + r));
}
for (const f of [`despacho_auditar(1,true,'x')`, `licao_robo_gravar('amigo','e','r')`, `licoes_robo_texto('amigo')`,
  `robo_caso_gravar('amigo','p',array['a'],'{}')`, `robo_caso_resultado(1,true,'x')`]) {
  const r = await como(ADMIN, `select ${f}`).then(() => 'deixou', e => e.message);
  (r.includes('permission denied') ? ok : falhou).push('P4: nem o admin autenticado chama ' + f.split('(')[0] + ' (so service_role)' + (r.includes('permission denied') ? '' : ' -> ' + r));
}
{
  const r = await como(null, `select mapa_app_tem('x')`).then(() => 'deixou', e => e.message);
  (r.includes('só para administradores') ? ok : falhou).push('P5: sem sessao recusado' + (r.includes('só para administradores') ? '' : ' -> ' + r));
}

console.log('\n=== RESULTADO ===');
for (const o of ok) console.log('  OK     ' + o);
for (const f of falhou) console.log('  FALHOU ' + f);
console.log(`\n${ok.length} ok, ${falhou.length} falharam`);
process.exit(falhou.length ? 1 : 0);
