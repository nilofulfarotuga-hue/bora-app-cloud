// Prova local (PGlite) da migração 20261109223000_amigo_voz.sql — pendências 09/11/2026, bloco I.
// Uso: node provar_amigo_voz.mjs <migração.sql>   (numa pasta com @electric-sql/pglite@0.2.17)
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const sql = readFileSync(process.argv[2], 'utf8');
const db = new PGlite();
const r = [];
const ok = (nome, cond, extra = '') => { r.push(`${cond ? 'OK ' : 'FALHA'} ${nome}${extra ? ' — ' + extra : ''}`); if (!cond) process.exitCode = 1; };
const U1 = '11111111-1111-1111-1111-111111111111';
const U2 = '22222222-2222-2222-2222-222222222222';
const U3 = '33333333-3333-3333-3333-333333333333';

await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to authenticated, anon, service_role;
  grant execute on function auth.uid() to authenticated, anon, service_role;
  grant usage on schema public to authenticated, anon, service_role;
  create table public.platform_settings (key text primary key, value jsonb, description text not null, category text not null,
    updated_at timestamptz default now(), updated_by uuid, is_secret boolean default false);
  -- já existe uma definição com o mesmo nome: a migração NÃO a pode mudar
  insert into public.platform_settings (key, value, description, category) values
    ('assistant_enabled', 'true', 'x', 'assistente'),
    ('amigo_voz_velocidade', '1.0', 'x', 'assistente');
  create function public.is_admin() returns boolean language sql stable as $$ select current_setting('app.admin', true) = '1' $$;
  grant execute on function public.is_admin() to authenticated, anon;
  create table public.admin_audit_log (id serial primary key, action text, entity_type text, entity_id_text text, details jsonb, admin_id uuid);
  create function public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb default null)
    returns void language plpgsql security definer set search_path = public as $$
    begin insert into public.admin_audit_log (action, entity_type, entity_id_text, details, admin_id)
          values (p_action_type, p_entity_type, p_entity_id, p_details, auth.uid()); end $$;
  create function public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id uuid, p_details jsonb default null)
    returns void language plpgsql security definer set search_path = public as $$ begin raise exception 'sobrecarga uuid usada'; end $$;
  grant execute on function public.log_admin_action(text, text, text, jsonb) to authenticated;
  create schema storage;
  create table storage.buckets (id text primary key, name text, public boolean default false,
    file_size_limit bigint, allowed_mime_types text[]);
  insert into auth.users values ('${U1}'), ('${U2}'), ('${U3}');
`);

// 1. corre duas vezes (idempotente)
for (const volta of [1, 2]) {
  try { await db.exec(sql); ok(`migração volta ${volta}`, true); }
  catch (e) { ok(`migração volta ${volta}`, false, e.message); }
}
const s = await db.query(`select key, value from public.platform_settings where key like 'amigo\\_voz%' order by key`);
const def = Object.fromEntries(s.rows.map((x) => [x.key, x.value]));
ok('interruptor desligado por defeito', def.amigo_voz_servidor_ativo === false, JSON.stringify(def));
ok('teto 20000/dia', Number(def.amigo_voz_teto_dia) === 20000);
ok('limite por cliente 3000/dia', Number(def.amigo_voz_teto_utilizador_dia) === 3000);
ok('voz pt-PT-Standard-E', def.amigo_voz_nome === 'pt-PT-Standard-E');
ok('definição que já existia ficou igual', Number(def.amigo_voz_velocidade) === 1);
const b = await db.query(`select id, public, file_size_limit, allowed_mime_types from storage.buckets where id = 'amigo-voz'`);
ok('bucket amigo-voz privado, só MP3', b.rows.length === 1 && b.rows[0].public === false && b.rows[0].allowed_mime_types?.[0] === 'audio/mpeg', JSON.stringify(b.rows));
const bk = await db.query(`select count(*)::int n from public.bkp_platform_settings_amigo_voz_20261109`);
ok('cópia antes de mexer', bk.rows[0].n >= 1, `${bk.rows[0].n} linha(s)`);

// 2. Quem pode chamar o quê
async function como(role, uid, admin, f) {
  await db.exec(`set role ${role}; select set_config('request.jwt.claim.sub', '${uid ?? ''}', false); select set_config('app.admin', '${admin ? 1 : 0}', false);`);
  try { return await f(); } finally { await db.exec('reset role;'); }
}
const recusa = async (nome, role, uid, admin, q, re) => {
  await como(role, uid, admin, async () => {
    try { await db.query(q); ok(nome, false, 'passou'); }
    catch (e) { ok(nome, re.test(e.message), e.message); }
  });
};
await recusa('anon não reserva', 'anon', null, false, `select public.amigo_voz_reservar('${U1}', 10)`, /permission denied/);
await recusa('cliente não reserva (só a Edge)', 'authenticated', U1, false, `select public.amigo_voz_reservar('${U1}', 10)`, /permission denied/);
await recusa('cliente não conta', 'authenticated', U1, false, `select public.amigo_voz_contar('${U1}', 10, 'cache')`, /permission denied/);
await recusa('anon não vê o painel', 'anon', null, false, `select public.admin_amigo_voz_overview(30)`, /permission denied/);
await recusa('cliente não vê o painel', 'authenticated', U1, false, `select public.admin_amigo_voz_overview(30)`, /admin_required/);
await recusa('cliente não muda o teto', 'authenticated', U1, false, `select public.admin_amigo_voz_definir(p_teto_dia => 99)`, /admin_required/);
await recusa('anon não lê o consumo', 'anon', null, false, `select * from public.amigo_voz_consumo`, /permission denied/);

// 3. A reserva (a Edge, como service_role)
const reservar = (u, n) => como('service_role', null, false, async () => (await db.query(`select public.amigo_voz_reservar('${u}', ${n}) as j`)).rows[0].j);
const contar = (u, n, t) => como('service_role', null, false, async () => db.query(`select public.amigo_voz_contar('${u}', ${n}, '${t}')`));
let j = await reservar(U1, 100);
ok('interruptor desligado → recusa "desligado"', j.ok === false && j.motivo === 'desligado', JSON.stringify(j));
await db.exec(`update public.platform_settings set value = 'true' where key = 'amigo_voz_servidor_ativo'`);
j = await reservar(U1, 1500);
ok('ligado: reserva 1500', j.ok === true && Number(j.gerados) === 1500, JSON.stringify(j));
j = await reservar(U1, 1600);
ok('limite por cliente (1500+1600 > 3000)', j.ok === false && j.motivo === 'limite_utilizador', JSON.stringify(j));
j = await reservar(U2, 3000);
ok('outro cliente: 3000 cabem', j.ok === true, JSON.stringify(j));
await db.exec(`update public.platform_settings set value = '"5000"' where key = 'amigo_voz_teto_dia'`); // texto também se lê
j = await reservar(U3, 600);
ok('teto do dia (4500+600 > 5000) → "teto"', j.ok === false && j.motivo === 'teto', JSON.stringify(j));
j = await reservar(U3, 500);
ok('500 ainda cabem no teto', j.ok === true && Number(j.gerados) === 5000, JSON.stringify(j));
await contar(U1, 200, 'cache');
await contar(U3, 500, 'erro');   // a Google falhou: devolve os 500
await contar(U3, 80, 'sem_chave');
await recusa('tipo inválido recusado', 'service_role', null, false, `select public.amigo_voz_contar('${U1}', 1, 'outro')`, /tipo_invalido/);
await recusa('caracteres 0 → inválido (sem rebentar)', 'service_role', null, false,
  `select case when (public.amigo_voz_reservar('${U1}', 0)->>'motivo') = 'invalido' then 1/0 else 1 end`, /division by zero/);
const c = (await db.query(`select * from public.amigo_voz_consumo`)).rows;
ok('uma linha por dia', c.length === 1, `${c.length}`);
const d = c[0];
ok('gerados = 1500 + 3000 + 500 − 500 (erro devolvido) = 4500', Number(d.caracteres_gerados) === 4500, `${d.caracteres_gerados}`);
ok('cache: 1 pedido, 200 caracteres', d.pedidos_cache === 1 && Number(d.caracteres_cache) === 200);
ok('recusados: desligado + limite + teto + sem chave = 4', d.pedidos_recusados === 4, `${d.pedidos_recusados} / ${d.caracteres_recusados}`);
ok('erros: 1', d.erros === 1);
ok('pedidos: 8', d.pedidos === 8, `${d.pedidos}`);
const u3 = (await db.query(`select caracteres_gerados from public.amigo_voz_uso_utilizador where user_id = '${U3}'`)).rows[0];
ok('cliente 3: o erro devolveu-lhe os caracteres', u3.caracteres_gerados === 0, JSON.stringify(u3));

// 4. Painel (admin)
await como('authenticated', U2, true, async () => {
  const o = (await db.query(`select public.admin_amigo_voz_overview(30) as o`)).rows[0].o;
  ok('painel: hoje 4500 gerados', Number(o.hoje.caracteres_gerados) === 4500, JSON.stringify(o.hoje));
  ok('painel: mês = hoje', Number(o.mes.caracteres_gerados) === 4500);
  ok('painel: grátis Standard 4 milhões', Number(o.gratis_mes) === 4000000);
  ok('painel: % do grátis 0,11', Number(o.pct_gratis_mes) === 0.11, `${o.pct_gratis_mes}`);
  ok('painel: % do teto de hoje 90', Number(o.pct_teto_hoje) === 90, `${o.pct_teto_hoje}`);
  ok('painel: 3 clientes hoje', Number(o.clientes_hoje) === 3);
  ok('painel: definições', o.definicoes.amigo_voz_servidor_ativo === true && Number(o.definicoes.amigo_voz_teto_dia) === 5000, JSON.stringify(o.definicoes));
  const lidas = (await db.query(`select count(*)::int n from public.amigo_voz_consumo`)).rows[0].n;
  ok('admin lê a tabela de consumo', lidas === 1);
  try { await db.query(`select public.admin_amigo_voz_definir(p_voz => 'pt-BR-Standard-A')`); ok('voz do Brasil recusada', false); }
  catch (e) { ok('voz do Brasil recusada', /voz_invalida/.test(e.message), e.message); }
  try { await db.query(`select public.admin_amigo_voz_definir(p_teto_dia => 999999)`); ok('teto acima do grátis recusado', false); }
  catch (e) { ok('teto acima do grátis recusado', /teto_dia_invalido/.test(e.message), e.message); }
  const dep = (await db.query(`select public.admin_amigo_voz_definir(p_ativo => false, p_teto_dia => 30000, p_voz => 'pt-PT-Wavenet-E') as d`)).rows[0].d;
  ok('admin muda interruptor, teto e voz', dep.amigo_voz_servidor_ativo === false && Number(dep.amigo_voz_teto_dia) === 30000 && dep.amigo_voz_nome === 'pt-PT-Wavenet-E', JSON.stringify(dep));
  ok('o limite por cliente não mexeu', Number(dep.amigo_voz_teto_utilizador_dia) === 3000);
  const o2 = (await db.query(`select public.admin_amigo_voz_overview(30) as o`)).rows[0].o;
  ok('voz WaveNet → grátis 1 milhão', Number(o2.gratis_mes) === 1000000);
});
await como('authenticated', U1, false, async () => {
  const n = (await db.query(`select count(*)::int n from public.amigo_voz_consumo`)).rows[0].n;
  ok('cliente não vê o consumo (RLS)', n === 0, `${n}`);
});
const log = (await db.query(`select action, entity_id_text, details from public.admin_audit_log`)).rows;
ok('auditoria: 1 linha amigo_voz_definir com antes/depois', log.length === 1 && log[0].action === 'amigo_voz_definir' && log[0].details?.antes && log[0].details?.depois, JSON.stringify(log));
const desc = (await db.query(`select description from public.platform_settings where key = 'amigo_voz_teto_dia'`)).rows[0];
ok('a descrição da definição ficou', /caracteres por dia/.test(desc.description));
console.log(r.join('\n'));
