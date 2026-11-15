// Prova local (PGlite = Postgres real em WASM) da migração
// 20261115123226_push_token_papel_handyman.sql — fechar-app-15-11, Bloco 3 (d).
//
// Porquê local: a tranca recusa DDL em produção, mesmo em rollback. Aqui
// montam-se réplicas das quatro tabelas de aparelhos (colunas e regras lidas
// de produção a 14/11), instala-se a função COMO ESTAVA em produção, vê-se o
// erro medido ("INVALID_ROLE: handyman"), aplica-se a migração TAL COMO ESTÁ
// e corre-se cada regra.
//
// Uso: node supabase/tests/fechar_app_3d_prova.mjs <pasta-com-node_modules-do-pglite>
//   (npm install @electric-sql/pglite@0.2.17 nessa pasta)
//
// Teste anti-mentira: MUTACAO="texto=>outro" estraga a migração de propósito;
// a prova TEM de falhar. Dois estragos que ela apanha:
//   MUTACAO="'cleaner', 'washer', 'handyman'=>'cleaner', 'washer'"
//   MUTACAO="(text, text, text, text) FROM anon;=>(text, text, text, text) FROM PUBLIC;"

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const pastaPglite = process.argv[2];
if (!pastaPglite) {
  console.error('falta a pasta do pglite');
  process.exit(2);
}
const require = createRequire(path.join(path.resolve(pastaPglite), 'x.js'));
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href);

const ler = (...p) => readFileSync(path.join(aqui, ...p), 'utf8').replace(/\r\n/g, '\n');
let migracao = ler('..', 'migrations', '20261115123226_push_token_papel_handyman.sql');
if (process.env.MUTACAO) {
  const [de, para] = process.env.MUTACAO.split('=>');
  if (!migracao.includes(de)) throw new Error(`mutação não encontrada: ${de}`);
  migracao = migracao.split(de).join(para);
  console.log(`MUTAÇÃO aplicada: ${de} => ${para}`);
}

// md5(prosrc) e tamanho de public.register_push_token em PRODUÇÃO, lidos a
// 14/11/2026 (select md5(prosrc), length(prosrc) from pg_proc …).
const MD5_PRODUCAO = '4c811f8766f1d26f5f3979dc693da0be';
const TAMANHO_PRODUCAO = 3044;

const ASSINATURA = 'public.register_push_token(text, text, text, text)';

const db = new PGlite();
let falhas = 0;
let ok = 0;
const certo = (nome, cond, detalhe = '') => {
  if (cond) {
    ok++;
    console.log(`  OK  ${nome}`);
  } else {
    falhas++;
    console.log(`  FALHOU  ${nome} ${detalhe}`);
  }
};
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const um = async (sql, params = []) => (await q(sql, params))[0];
const como = async (uid) =>
  db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid ?? '']);
/// Corre como um papel do Supabase (anon / authenticated) e devolve o id ou o erro.
const registar = async (papelPg, role, aparelho, plataforma = 'android', etiqueta = 'android 14') => {
  await db.exec(`set role ${papelPg}`);
  try {
    const r = await um(`select public.register_push_token($1, $2, $3, $4) id`,
      [role, aparelho, etiqueta, plataforma]);
    return { id: r.id };
  } catch (e) {
    return { erro: e.message };
  } finally {
    await db.exec('reset role');
  }
};
/// As linhas de prestador de uma pessoa (o aparelho vem com o nome "aparelho").
const dePrestador = (uid, papel) => q(
  `select id, user_id, role, fcm_token as aparelho, platform, device_label, active, fail_count, last_fail_at
     from public.provider_push_tokens where user_id = $1 and role = $2`, [uid, papel]);

// ── réplicas mínimas do Supabase ──────────────────────────────────────────
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin;
  create schema auth;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to anon, authenticated, service_role;

  -- A armadilha do Supabase: cada função nova do schema public nasce com
  -- EXECUTE direto para anon. Sem o REVOKE … FROM anon fica aberta.
  alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

  create table public.client_push_tokens (
    id uuid primary key default gen_random_uuid(), user_id uuid not null, fcm_token text not null,
    device_label text, platform text check (platform = any (array['android','ios','web'])),
    active boolean not null default true, fail_count smallint not null default 0,
    last_fail_at timestamptz, last_used_at timestamptz not null default now(),
    created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
    unique (user_id, fcm_token));
  create table public.driver_push_tokens (like public.client_push_tokens including all);
  create table public.partner_push_tokens (
    id uuid primary key default gen_random_uuid(), partner_id uuid not null, fcm_token text not null,
    device_label text, platform text,
    active boolean not null default true, fail_count smallint not null default 0,
    last_fail_at timestamptz, last_used_at timestamptz not null default now(),
    created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
    unique (partner_id, fcm_token));
  -- provider_push_tokens: colunas e regras de produção (casa_01, 31/10).
  create table public.provider_push_tokens (
    id uuid primary key default gen_random_uuid(), user_id uuid not null, role text not null,
    fcm_token text not null, device_label text, platform text,
    active boolean not null default true, fail_count smallint not null default 0,
    last_fail_at timestamptz, last_used_at timestamptz not null default now(),
    created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
    constraint provider_push_tokens_platform_check check (platform = any (array['android','ios','web'])),
    constraint provider_push_tokens_role_check check (role = any (array['cleaner','washer','delivery','handyman'])),
    constraint provider_push_tokens_unicos unique (user_id, role, fcm_token));
`);

const PESSOA = '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7'; // a conta de 14/11 (seis papéis)
const OUTRA = '22222222-2222-2222-2222-222222222222';
const APARELHO = 'aparelho-de-prova-A';

// ── 0) a função COMO ESTAVA em produção a 14/11 ───────────────────────────
// O corpo de "antes" tira-se da própria migração desfazendo as duas mexidas
// (a lista e o comentário novo). Se o md5 bater com o de produção, fica
// provado que a migração é produção + essas mexidas, e mais nada.
const LINHA_NOVA = "IN ('cleaner', 'washer', 'handyman')";
const LINHA_ANTIGA = "IN ('cleaner', 'washer')";
const COMENTARIO_NOVO =
  "  -- [15/11/2026] 'handyman' (Casa e manutenção): o CHECK já o aceitava desde\n" +
  '  -- 31/10; faltava esta lista.\n';
const desfazer = (corpo) => corpo.replace(COMENTARIO_NOVO, '').replace(LINHA_NOVA, LINHA_ANTIGA);

const corpoAntes = desfazer(migracao.split('$function$')[1] ?? '');
await db.exec(`
  CREATE OR REPLACE FUNCTION public.register_push_token(
    p_role text, p_fcm_token text, p_device_label text DEFAULT NULL::text, p_platform text DEFAULT NULL::text)
   RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
  AS $function$${corpoAntes}$function$;
`);

console.log('\n0) antes da migração — a função tal como estava em produção');
let f = await um(`select md5(prosrc) m, length(prosrc) n from pg_proc where oid = '${ASSINATURA}'::regprocedure`);
certo('o corpo de "antes" é byte a byte o de produção (md5 + tamanho)',
  f.m === MD5_PRODUCAO && f.n === TAMANHO_PRODUCAO, `md5=${f.m} tamanho=${f.n}`);
await como(PESSOA);
let r = await registar('authenticated', 'handyman', APARELHO);
certo('reproduz o erro medido: INVALID_ROLE: handyman', r.erro === 'INVALID_ROLE: handyman', JSON.stringify(r));
r = await registar('authenticated', 'cleaner', APARELHO);
certo('o faxineiro já registava (os outros 5 pedidos deram 200)', !!r.id, JSON.stringify(r));
certo('antes: nenhum aparelho guardado com o papel handyman', (await dePrestador(PESSOA, 'handyman')).length === 0);
await db.exec('truncate public.provider_push_tokens');

// ── a migração, tal como está no repo ─────────────────────────────────────
let aplicou = true;
try {
  await db.exec(migracao);
  await db.exec(migracao); // duas vezes: tem de ser repetível
  console.log('\nmigração aplicada no PGlite (duas vezes)');
} catch (e) {
  aplicou = false;
  console.log(`\nA MIGRAÇÃO REBENTOU: ${e.message}`);
}
certo('a migração aplica-se (e a verificação do fim não se queixa)', aplicou);

console.log('\n1) o profissional da Casa regista o aparelho');
await como(PESSOA);
r = await registar('authenticated', 'handyman', APARELHO);
certo('handyman → devolve o id do aparelho', !!r.id, JSON.stringify(r));
let linhas = await dePrestador(PESSOA, 'handyman');
certo('uma linha em provider_push_tokens (dono, papel, aparelho, plataforma)',
  linhas.length === 1 && linhas[0].aparelho === APARELHO && linhas[0].platform === 'android' &&
  linhas[0].active === true && linhas[0].id === r.id, JSON.stringify(linhas));
// O que a Edge Function notify-handyman pergunta antes de tocar:
// as linhas ativas da pessoa com role='handyman'.
certo('o notify-handyman passa a ter a quem tocar', linhas.filter((l) => l.active).length === 1);

console.log('\n2) registar outra vez não duplica e reativa');
await db.query(`update public.provider_push_tokens set active=false, fail_count=3, last_fail_at=now() where id=$1`, [r.id]);
const r2 = await registar('authenticated', 'handyman', APARELHO, 'android', null);
linhas = await dePrestador(PESSOA, 'handyman');
certo('mesmo aparelho, mesmo papel → a mesma linha', r2.id === r.id && linhas.length === 1, JSON.stringify(r2));
certo('volta a ativo, falhas a zero, etiqueta antiga conservada',
  linhas[0]?.active === true && linhas[0]?.fail_count === 0 && linhas[0]?.last_fail_at === null &&
  linhas[0]?.device_label === 'android 14', JSON.stringify(linhas[0]));

console.log('\n3) os seis papéis da mesma pessoa, no mesmo aparelho (o caso de 14/11)');
await db.exec('truncate public.provider_push_tokens, public.client_push_tokens, public.driver_push_tokens, public.partner_push_tokens');
const seis = {};
for (const papel of ['client', 'driver', 'partner', 'cleaner', 'washer', 'handyman']) {
  seis[papel] = await registar('authenticated', papel, APARELHO);
}
certo('os seis registos passam (antes eram 5 + um 400)',
  Object.values(seis).every((x) => !!x.id), JSON.stringify(seis));
const porTabela = await um(`select
  (select count(*)::int from public.client_push_tokens  where user_id = $1)    c,
  (select count(*)::int from public.driver_push_tokens  where user_id = $1)    d,
  (select count(*)::int from public.partner_push_tokens where partner_id = $1) p,
  (select array_agg(role order by role) from public.provider_push_tokens where user_id = $1) prov`, [PESSOA]);
certo('cada papel na sua gaveta; prestadores: uma linha POR PAPEL',
  porTabela.c === 1 && porTabela.d === 1 && porTabela.p === 1 &&
  JSON.stringify(porTabela.prov) === JSON.stringify(['cleaner', 'handyman', 'washer']), JSON.stringify(porTabela));

console.log('\n4) a lista não abriu mais do que devia');
for (const mau of ['delivery', 'admin', 'HANDYMAN', 'handyman ', '', 'tudo']) {
  const x = await registar('authenticated', mau, APARELHO);
  certo(`papel "${mau}" continua recusado`, x.erro === `INVALID_ROLE: ${mau}`, JSON.stringify(x));
}
let x = await registar('authenticated', null, APARELHO);
certo('papel nulo recusado', (x.erro ?? '').startsWith('INVALID_ROLE'), JSON.stringify(x));
x = await registar('authenticated', 'handyman', '   ');
certo('aparelho vazio → FCM_TOKEN_REQUIRED', x.erro === 'FCM_TOKEN_REQUIRED', JSON.stringify(x));
x = await registar('authenticated', 'handyman', APARELHO, 'windows');
certo('plataforma desconhecida → INVALID_PLATFORM', x.erro === 'INVALID_PLATFORM', JSON.stringify(x));

console.log('\n5) quem pode chamar');
await como(null);
x = await registar('authenticated', 'handyman', APARELHO);
certo('sem conta (auth.uid() nulo) → UNAUTHENTICATED', x.erro === 'UNAUTHENTICATED', JSON.stringify(x));
await como(OUTRA);
x = await registar('anon', 'handyman', 'aparelho-de-fora');
certo('anon não chama (permission denied)', /permission denied/.test(x.erro ?? ''), JSON.stringify(x));
certo('nada entrou em nome de anon', (await dePrestador(OUTRA, 'handyman')).length === 0);
const priv = await um(`select
  has_function_privilege('anon', '${ASSINATURA}', 'EXECUTE') anon,
  has_function_privilege('authenticated', '${ASSINATURA}', 'EXECUTE') auth,
  has_function_privilege('service_role', '${ASSINATURA}', 'EXECUTE') srv,
  (select count(*)::int from pg_proc p, aclexplode(p.proacl) a
    where p.oid = '${ASSINATURA}'::regprocedure and a.grantee = 0) publico`);
certo('fechada a anon e a PUBLIC; aberta a authenticated e service_role',
  priv.anon === false && priv.publico === 0 && priv.auth === true && priv.srv === true, JSON.stringify(priv));
x = await registar('authenticated', 'handyman', 'aparelho-de-prova-B');
linhas = await dePrestador(OUTRA, 'handyman');
certo('o aparelho fica no nome de quem chama, nunca de outro',
  linhas.length === 1 && linhas[0].id === x.id && linhas[0].user_id === OUTRA, JSON.stringify(linhas));

console.log('\n6) a função continua a ser a de produção, mais uma linha');
f = await um(`select prosecdef, proconfig, prosrc from pg_proc where oid = '${ASSINATURA}'::regprocedure`);
certo('SECURITY DEFINER com search_path fixo (public, pg_temp)',
  f.prosecdef === true && JSON.stringify(f.proconfig) === JSON.stringify(['search_path=public, pg_temp']),
  JSON.stringify(f.proconfig));
certo('a guarda é auth.uid(), nunca current_user',
  f.prosrc.includes('auth.uid()') && !/current_user|session_user/.test(f.prosrc));
certo('a linha nova está lá', f.prosrc.includes(LINHA_NOVA));
const md5Desfeito = (await um(`select md5($1::text) m`, [desfazer(f.prosrc)])).m;
certo('desfeita a linha nova, o corpo volta a ser o de produção (md5)', md5Desfeito === MD5_PRODUCAO, md5Desfeito);

console.log('\n7) a app e a base dizem os mesmos papéis');
const dart = ler('..', '..', 'lib', 'services', 'push_token_service.dart');
const bloco = (dart.match(/papeisComPush\s*=\s*\{([\s\S]*?)\};/) ?? [])[1] ?? '';
const papeisDaApp = [...bloco.replace(/\/\/.*$/gm, '').matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
certo('a app declara os seis papéis, handyman incluído',
  papeisDaApp.length === 6 && papeisDaApp.includes('handyman'), JSON.stringify(papeisDaApp));
await como(PESSOA);
for (const papel of papeisDaApp) {
  const y = await registar('authenticated', papel, 'aparelho-de-prova-C');
  certo(`papel da app "${papel}" é aceite pela base`, !!y.id, JSON.stringify(y));
}

console.log(`\nRESULTADO: ${ok} certos, ${falhas} falhados`);
process.exit(falhas ? 1 : 0);
