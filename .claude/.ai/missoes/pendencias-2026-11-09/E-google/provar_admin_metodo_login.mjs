// Prova local (PGlite, Postgres em WASM) da migração
// supabase/migrations/20261109221500_admin_metodo_login.sql — sem tocar em
// produção. Uso:
//   node provar_admin_metodo_login.mjs <pasta-node_modules-com-pglite> <migração>
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const [, , modulos, migracao] = process.argv;
const { PGlite } = await import(
  pathToFileURL(path.join(modulos, '@electric-sql/pglite/dist/index.js')).href
);
const db = new PGlite();
const sqlMig = readFileSync(migracao, 'utf8');

let falhas = 0;
const ok = (cond, txt) => {
  console.log(`${cond ? 'OK  ' : 'FALHA'} ${txt}`);
  if (!cond) falhas++;
};
async function erroDe(sql, params) {
  try {
    await db.query(sql, params);
    return null;
  } catch (e) {
    return e.message;
  }
}
const ADMIN = '00000000-0000-0000-0000-00000000000a';
const SO_EMAIL = '00000000-0000-0000-0000-000000000001';
const GOOGLE_E_EMAIL = '00000000-0000-0000-0000-000000000002';
const APPLE = '00000000-0000-0000-0000-000000000003';
const comoQuem = (uid) =>
  db.query(
    `select set_config('request.jwt.claims', $1, false), set_config('request.jwt.claim.sub', $2, false)`,
    [uid ? JSON.stringify({ sub: uid, role: 'authenticated' }) : '', uid ?? ''],
  );

// ── Mundo mínimo igual ao de produção ───────────────────────────────────────
await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth;
  create table auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
  create table auth.identities (
    id uuid default gen_random_uuid(), user_id uuid references auth.users(id),
    provider text not null, last_sign_in_at timestamptz, created_at timestamptz default now());
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table public.platform_settings (key text primary key, value jsonb, description text,
    category text, updated_at timestamptz default now(), updated_by uuid, is_secret boolean default false);
  -- is_admin() copiada de produção (09/11/2026).
  CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path TO 'public' AS $function$
  DECLARE v_uid UUID := auth.uid();
  BEGIN
    IF v_uid IS NULL THEN RETURN false; END IF;
    RETURN EXISTS (SELECT 1 FROM auth.users WHERE id = v_uid AND (
      COALESCE(raw_app_meta_data->>'role','') = 'admin'
      OR email IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com')));
  END; $function$;
  insert into public.platform_settings(key, value, category) values ('login_google_ativo', 'false', 'cliente');
  insert into auth.users(id, email) values
    ('${ADMIN}', 'nilofulfarotuga@gmail.com'),
    ('${SO_EMAIL}', 'so.email@exemplo.pt'),
    ('${GOOGLE_E_EMAIL}', 'ligada@exemplo.pt'),
    ('${APPLE}', 'apple@privaterelay.appleid.com');
  insert into auth.identities(user_id, provider, last_sign_in_at, created_at) values
    ('${ADMIN}', 'email', now() - interval '1 day', now() - interval '90 days'),
    ('${SO_EMAIL}', 'email', now() - interval '3 days', now() - interval '30 days'),
    ('${GOOGLE_E_EMAIL}', 'email', now() - interval '20 days', now() - interval '60 days'),
    ('${GOOGLE_E_EMAIL}', 'google', now() - interval '1 hour', now() - interval '1 hour'),
    ('${APPLE}', 'apple', null, now() - interval '2 hours');
`);

// ── A migração, duas vezes (tem de ser repetível) ───────────────────────────
await db.exec(sqlMig);
await db.exec(sqlMig);
ok(true, 'migração corre duas vezes seguidas sem erro');

const chamar = `select * from public.admin_clientes_metodo_login($1::uuid[]) order by user_id`;

await comoQuem(null);
let e = await erroDe(chamar, [null]);
ok(e && e.includes('admin_required'), `sem sessão → recusa (${e})`);

await comoQuem(SO_EMAIL);
e = await erroDe(chamar, [null]);
ok(e && e.includes('admin_required'), `cliente comum → recusa (${e})`);

await comoQuem(ADMIN);
const tudo = (await db.query(chamar, [null])).rows;
ok(tudo.length === 4, `admin vê as 4 contas (${tudo.length})`);
const por = Object.fromEntries(tudo.map((r) => [r.user_id, r]));
const txt = (r) => `${JSON.stringify(r.metodos)} último=${r.ultimo_metodo}`;
ok(JSON.stringify(por[SO_EMAIL].metodos) === '["email"]' && por[SO_EMAIL].ultimo_metodo === 'email',
  `só email → ${txt(por[SO_EMAIL])}`);
ok(JSON.stringify(por[GOOGLE_E_EMAIL].metodos) === '["email","google"]' &&
    por[GOOGLE_E_EMAIL].ultimo_metodo === 'google',
  `email + google ligado, entrou agora pelo Google → ${txt(por[GOOGLE_E_EMAIL])}`);
ok(JSON.stringify(por[APPLE].metodos) === '["apple"]' && por[APPLE].ultimo_metodo === 'apple',
  `apple sem data de entrada → ${txt(por[APPLE])}`);

const filtrado = (await db.query(chamar, [[SO_EMAIL, APPLE]])).rows;
ok(filtrado.length === 2 && filtrado.every((r) => [SO_EMAIL, APPLE].includes(r.user_id)),
  `filtro p_user_ids devolve só as 2 pedidas (${filtrado.length})`);

const mil = Array.from({ length: 1001 }, () => SO_EMAIL);
e = await erroDe(chamar, [mil]);
ok(e && e.includes('max 1000'), `mais de 1000 contas → recusa (${e})`);

const acl = (await db.query(
  `select proacl::text a, prosecdef from pg_proc where proname = 'admin_clientes_metodo_login'`)).rows[0];
ok(!/(^|[{,])=X/.test(acl.a) && !/anon=/.test(acl.a), `fechada a PUBLIC e anon: ${acl.a}`);
ok(/authenticated=X/.test(acl.a) && /service_role=X/.test(acl.a), 'aberta a authenticated e service_role');
ok(acl.prosecdef === true, 'SECURITY DEFINER');

const sets = (await db.query(
  `select key, value::text v, category, is_secret from public.platform_settings where key like 'login_%' order by key`)).rows;
console.log('     definições:', JSON.stringify(sets));
ok(sets.find((s) => s.key === 'login_apple_ativo')?.v === 'false', 'login_apple_ativo nasce false');
ok(sets.find((s) => s.key === 'login_google_ativo')?.v === 'false',
  'login_google_ativo que já existia não é pisado (on conflict do nothing)');
await db.exec(`delete from public.platform_settings where key = 'login_google_ativo'`);
await db.exec(sqlMig);
const g = (await db.query(`select value::text v from public.platform_settings where key='login_google_ativo'`)).rows[0];
ok(g?.v === 'true', 'base sem a linha → login_google_ativo nasce true');
ok(sets.every((s) => s.is_secret === false && s.category === 'cliente'),
  'públicas (is_secret=false) na categoria cliente, como visitantes_sem_conta');

console.log(falhas === 0 ? '\nTUDO VERDE' : `\n${falhas} FALHA(S)`);
process.exit(falhas === 0 ? 0 : 1);
