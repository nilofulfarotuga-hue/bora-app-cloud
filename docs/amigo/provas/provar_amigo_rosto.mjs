// Prova local (PGlite) da migração 20261109060000_amigo_rosto.sql — m11, 09/11/2026.
// Uso: node provar_amigo_rosto.mjs <migração.sql>
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const sql = readFileSync(process.argv[2], 'utf8');
const db = new PGlite();
const r = [];
const ok = (nome, cond, extra = '') => { r.push(`${cond ? 'OK ' : 'FALHA'} ${nome}${extra ? ' — ' + extra : ''}`); if (!cond) process.exitCode = 1; };

await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to authenticated, anon;
  grant execute on function auth.uid() to authenticated, anon;
  grant usage on schema public to authenticated, anon, service_role;
  create table public.platform_settings (key text primary key, value jsonb, description text, category text,
    updated_at timestamptz default now(), updated_by uuid, is_secret boolean default false);
  insert into public.platform_settings (key, value, category) values
    ('assistant_enabled', 'true', 'assistente'), ('assistant_personality_enabled', 'true', 'assistente'),
    ('amigo_rosto_ativo', 'false', 'assistente');  -- já existe: a migração NÃO pode mexer
  create function public.is_admin() returns boolean language sql stable as $$ select current_setting('app.admin', true) = '1' $$;
  grant execute on function public.is_admin() to authenticated;
  insert into auth.users values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222');
`);

// 1. corre duas vezes (idempotente)
for (const volta of [1, 2]) {
  try { await db.exec(sql); ok(`migração volta ${volta}`, true); }
  catch (e) { ok(`migração volta ${volta}`, false, e.message); }
}
const s = await db.query(`select key, value from public.platform_settings where key like 'amigo\\_%' order by key`);
ok('5 definições amigo_*', s.rows.length === 5, JSON.stringify(s.rows));
ok('definição que já existia ficou igual (on conflict do nothing)',
  s.rows.find((x) => x.key === 'amigo_rosto_ativo')?.value === false);
const vel = s.rows.find((x) => x.key === 'amigo_voz_velocidade')?.value;
ok('velocidade 1.0', Number(vel) === 1, String(vel));
const var_ = s.rows.find((x) => x.key === 'amigo_rosto_variante')?.value;
ok('variante rosto_camisa', var_ === 'rosto_camisa', String(var_));
const b = await db.query(`select count(*)::int n from public.bkp_platform_settings_amigo_20261109`);
ok('cópia antes de mexer', b.rows[0].n === 3, `${b.rows[0].n} linhas`);

// 2. RLS: o cliente insere e lê só o seu
const U1 = '11111111-1111-1111-1111-111111111111', U2 = '22222222-2222-2222-2222-222222222222';
async function como(uid, admin, f) {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid}', false); select set_config('app.admin', '${admin ? 1 : 0}', false);`);
  try { return await f(); } finally { await db.exec('reset role;'); }
}
await como(U1, false, async () => {
  await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo, plataforma) values ('${U1}', 'abrir', 'android')`);
  await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo, plataforma) values ('${U1}', 'voz', 'android')`);
  await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo, duracao_s, plataforma) values ('${U1}', 'fim', 95, 'android')`);
  ok('dono insere o seu', true);
  try { await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo) values ('${U2}', 'abrir')`); ok('não insere em nome de outro', false); }
  catch { ok('não insere em nome de outro', true); }
  try { await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo) values ('${U1}', 'mentira')`); ok('tipo inválido recusado', false); }
  catch { ok('tipo inválido recusado', true); }
  try { await db.query(`select public.admin_amigo_rosto_overview(30)`); ok('não-admin não vê o painel', false); }
  catch (e) { ok('não-admin não vê o painel', /admin_required/.test(e.message)); }
});
await como(U2, false, async () => {
  await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo, plataforma) values ('${U2}', 'abrir', 'web')`);
  await db.exec(`insert into public.assistant_amigo_eventos (user_id, tipo, plataforma) values ('${U2}', 'escrita', 'web')`);
  const v = await db.query(`select count(*)::int n from public.assistant_amigo_eventos`);
  ok('cliente só lê o seu', v.rows[0].n === 2, `${v.rows[0].n} linhas`);
});
await como(U2, true, async () => {
  const v = await db.query(`select public.admin_amigo_rosto_overview(30) as o`);
  const o = v.rows[0].o;
  ok('painel: 2 aberturas, 2 clientes', o.aberturas === 2 && o.clientes === 2, JSON.stringify({ a: o.aberturas, c: o.clientes }));
  ok('painel: voz 1, escrita 1, 50 %', o.mensagens_voz === 1 && o.mensagens_escrita === 1 && Number(o.pct_voz) === 50, `${o.pct_voz}`);
  ok('painel: tempo médio 95 s', Number(o.tempo_medio_s) === 95, `${o.tempo_medio_s}`);
  ok('painel: interruptores', o.interruptores?.amigo_rosto_variante === 'rosto_camisa', JSON.stringify(o.interruptores));
  ok('painel: por plataforma', Array.isArray(o.por_plataforma) && o.por_plataforma.length === 2);
});
console.log(r.join('\n'));
