// Prova local (PGlite = Postgres real em WASM) das 3 migrações do bloco E da missão fechar-tudo-2026-11-10:
//   20261110190000_prestador_avisos_lidos, 20261110190100_products_alergenios_preenchido_em,
//   20261110190200_livro_reclamacoes_registo. Não toca na produção. 10/11/2026: 33/33 OK.
// Uso: bun prova_pglite_e.mjs   (o PGlite 0.2.x vem de outra worktree do PC; mudar o caminho do import se preciso)
import fs from 'node:fs'
const { PGlite } = await import('C:/BoraLocal/wt-fechar-g/.scratch/g/node_modules/@electric-sql/pglite/dist/index.js')
const WT = 'C:/BoraLocal/wt-fechar-e/supabase/migrations/'
const db = new PGlite()
let falhas = 0
const ok = (c, m) => { console.log((c ? 'OK   ' : 'FALHA') + ' ' + m); if (!c) falhas++ }
const q = async (s, p) => (await db.query(s, p)).rows
const erro = async (s) => { try { await db.exec(s); return null } catch (e) { return String(e.message) } }
await db.exec(`
  create schema auth;
  create role anon; create role authenticated;
  grant usage on schema public, auth to anon, authenticated;
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable security definer as $$ select coalesce(current_setting('test.admin', true), '0') = '1' $$;
  grant execute on all functions in schema auth to anon, authenticated;
  create table public.drivers (id uuid primary key default gen_random_uuid(), user_id uuid, email text, vehicle_type text, name text, phone text, approval_status text, is_banned boolean, deleted_at timestamptz);
  create table public.cleaners (id uuid primary key default gen_random_uuid(), user_id uuid, name text, phone text, email text, approval_status text, is_active boolean);
  create table public.washers (id uuid primary key default gen_random_uuid(), user_id uuid, name text, phone text, email text, approval_status text, is_active boolean, is_banned boolean);
  create table public.casa_profissionais (id uuid primary key default gen_random_uuid(), user_id uuid, name text, phone text, email text, approval_status text, is_active boolean);
  create table public.products (id text primary key, name text, price numeric, allergens text[]);
`)
for (const f of ['20261110190000_prestador_avisos_lidos.sql', '20261110190100_products_alergenios_preenchido_em.sql', '20261110190200_livro_reclamacoes_registo.sql']) {
  const sql = fs.readFileSync(WT + f, 'utf8')
  const e = await erro(sql)
  ok(e === null, 'aplica ' + f + (e ? ' — ' + e : ''))
  const e2 = await erro(sql)
  ok(e2 === null, 'reaplica (idempotente) ' + f + (e2 ? ' — ' + e2 : ''))
}
const U1 = '11111111-1111-1111-1111-111111111111', U2 = '22222222-2222-2222-2222-222222222222', AD = '99999999-9999-9999-9999-999999999999'
await db.exec(`
  insert into drivers (user_id, name, vehicle_type, approval_status) values ('${U1}','Est Um','moto','approved'), ('${U2}','Mot Dois','carro_passageiros','approved');
  insert into cleaners (user_id, name, approval_status, is_active) values ('${U1}','Limp Um','approved', true);
  insert into washers (user_id, name, approval_status) values (null,'Lav Sem Conta','pending');
  insert into casa_profissionais (user_id, name, approval_status) values ('${U2}','Casa Dois','approved');
`)
// ── E4 ──
await db.exec(`set role authenticated; set test.uid = '${U1}'; set test.admin = '0';`)
const r1 = (await q(`select public.prestador_marcar_aviso_lido('como_o_bora_decide','2026-11-10','limpeza','android') j`))[0].j
const r2 = (await q(`select public.prestador_marcar_aviso_lido('como_o_bora_decide','2026-11-10','estafeta','web') j`))[0].j
ok(r1.ok && r1.lido_em === r2.lido_em, 'marcar 2x: idempotente, devolve a 1.ª hora')
ok((await q(`select count(*)::int n from prestador_avisos_lidos`))[0].n === 1, 'u1 vê só a sua 1 linha')
ok((await erro(`select public.prestador_marcar_aviso_lido('outro','x')`))?.includes('AVISO_DESCONHECIDO'), 'aviso desconhecido recusado')
ok((await erro(`select public.prestador_marcar_aviso_lido('como_o_bora_decide','   ')`))?.includes('VERSAO_INVALIDA'), 'versão vazia recusada')
ok((await erro(`select * from public.admin_avisos_prestadores('como_o_bora_decide','2026-11-10')`))?.includes('SO_ADMIN'), 'painel recusado a não-admin')
ok((await erro(`update prestador_avisos_lidos set versao='x'`)) !== null, 'sem UPDATE para a app')
ok((await erro(`delete from prestador_avisos_lidos`)) !== null, 'sem DELETE para a app')
const eIns = await erro(`insert into prestador_avisos_lidos (user_id, aviso, versao, lido_em) values ('${U2}','como_o_bora_decide','2026-11-01', '2020-01-01')`)
ok(eIns === null, 'insert direto aceite' + (eIns ? ' — ' + eIns : ''))
const fora = await q(`select user_id::text u, lido_em from prestador_avisos_lidos where versao='2026-11-01'`)
ok(fora.length === 1 && fora[0].u === U1 && new Date(fora[0].lido_em).getFullYear() > 2025, 'insert direto: dono e hora são os do servidor')
await db.exec(`set test.uid = '${U2}'`)
ok((await q(`select count(*)::int n from prestador_avisos_lidos`))[0].n === 0, 'u2 não vê as linhas do u1')
await db.exec(`set test.uid = ''`)
ok((await erro(`select public.prestador_marcar_aviso_lido('como_o_bora_decide','2026-11-10')`))?.includes('SEM_SESSAO'), 'sem sessão recusado')
await db.exec(`set test.uid = '${AD}'; set test.admin = '1';`)
const pain = await q(`select papel, nome, lido_em, ultima_versao_lida from public.admin_avisos_prestadores('como_o_bora_decide','2026-11-10') order by papel, nome`)
ok(pain.length === 5, 'painel: 5 perfis (2 drivers, 1 limpeza, 1 lavagem, 1 casa) — ' + pain.length)
const est = pain.find((x) => x.nome === 'Est Um'), lim = pain.find((x) => x.nome === 'Limp Um'), mot = pain.find((x) => x.nome === 'Mot Dois')
ok(est?.papel === 'estafeta' && !!est.lido_em && !!lim?.lido_em, 'u1 leu: aparece lido como estafeta e como limpeza')
ok(mot?.papel === 'motorista' && !mot.lido_em, 'carro_passageiros = motorista, falta ler')
const lav = pain.find((x) => x.nome === 'Lav Sem Conta')
ok(!!lav && !lav.lido_em, 'prestador sem conta aparece como falta')
ok((await q(`select count(*)::int n from prestador_avisos_lidos`))[0].n === 2, 'admin vê todas as linhas')
// ── E6 ──
await db.exec(`reset role;`)
await db.exec(`insert into products (id, name, allergens) values ('p1','Prato A', array['gluten']), ('p2','Prato B', null)`)
let p = await q(`select id, alergenios_preenchido_em is not null c from products order by id`)
ok(p[0].c === true && p[1].c === false, 'insert: carimbo só com alergénios')
await db.exec(`update products set allergens = array['leite'] where id='p2'; update products set allergens = '{}' where id='p1';`)
p = await q(`select id, alergenios_preenchido_em is not null c from products order by id`)
ok(p[0].c === false && p[1].c === true, 'update: vazio volta a NULL, preenchido carimba')
const antes = (await q(`select alergenios_preenchido_em t from products where id='p2'`))[0].t
await db.exec(`update products set price = 9 where id='p2'; update products set allergens = array['leite'] where id='p2';`)
const depois = (await q(`select alergenios_preenchido_em t from products where id='p2'`))[0].t
ok(String(antes) === String(depois), 'mesma lista ou outra coluna: carimbo não muda')
// ── E2e ──
await db.exec(`set role authenticated; set test.uid = '${AD}'; set test.admin = '1';`)
const eReg = await erro(`insert into livro_reclamacoes_registo (recebida_em, canal, resumo, prazo) values ('2026-11-10','livro_eletronico','Atraso na entrega','2026-12-02')`)
ok(eReg === null, 'admin regista' + (eReg ? ' — ' + eReg : ''))
ok((await erro(`insert into livro_reclamacoes_registo (recebida_em, canal, resumo, prazo) values ('2026-11-10','livro_eletronico','Atraso','2026-11-10')`))?.includes('livro_reclamacoes_prazo_depois'), 'prazo tem de ser depois da receção')
ok((await erro(`update livro_reclamacoes_registo set estado='respondida'`))?.includes('respondida_com_data'), 'respondida exige data')
ok((await erro(`update livro_reclamacoes_registo set estado='respondida', respondida_em=now()`)) === null, 'admin marca respondida')
ok((await erro(`delete from livro_reclamacoes_registo`)) !== null, 'ninguém apaga')
await db.exec(`set test.admin = '0'; set test.uid = '${U1}'`)
ok((await q(`select count(*)::int n from livro_reclamacoes_registo`))[0].n === 0, 'não-admin não vê')
ok((await erro(`insert into livro_reclamacoes_registo (recebida_em, canal, resumo, prazo) values ('2026-11-10','email','Teste xx','2026-12-02')`)) !== null, 'não-admin não regista')
await db.exec(`reset role`)
const anonGrants = (await q(`select count(*)::int n from information_schema.role_routine_grants where grantee in ('anon','PUBLIC') and routine_name in ('prestador_marcar_aviso_lido','admin_avisos_prestadores')`))[0].n
ok(anonGrants === 0, 'funções novas fechadas a anon e PUBLIC')
console.log(falhas === 0 ? '\nTUDO OK' : `\n${falhas} FALHAS`)
