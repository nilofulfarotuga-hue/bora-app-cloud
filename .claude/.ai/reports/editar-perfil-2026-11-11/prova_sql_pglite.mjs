// Prova local (PGlite, Postgres em WASM) das migrações editar-perfil-2026-11-11.
// Uso: node prova.mjs <repo>
// Nada toca em produção: as tabelas/funções de fora (auth, users, pedidos do
// robô, avisos) são réplicas mínimas; admin_approve_action vem do repo e é
// conferido por md5(prosrc) contra o valor lido de produção.
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

const require = createRequire(import.meta.url);
const PGLITE = 'C:/Users/danil/AppData/Local/Temp/claude/e2669589ce73d1a9/fae7e923-e38a-48d6-b0f1-c30572ed49f0/scratchpad/node_modules/@electric-sql/pglite/dist/index.cjs';
const { PGlite } = require(PGLITE);

const repo = process.argv[2];
const MIG1 = path.join(repo, 'supabase/migrations/20261111180000_editar_perfil_cliente.sql');
const MIG2 = path.join(repo, 'supabase/migrations/20261111180100_aprovar_account_update_pelo_nucleo.sql');
const OLD = path.join(repo, 'supabase/migrations/20260507070100_5f_beta_alpha_b3_other_functions.sql');
const PROD_MD5_APPROVE = '4ca3a167f4e82d5158ceb37e71b628c3';

const md5 = (s) => crypto.createHash('md5').update(s).digest('hex');
const db = new PGlite();
const q = async (sql, params) => (await db.query(sql, params)).rows;
const out = {};

// ── réplicas mínimas do que existe em produção ─────────────────────────────
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth; create schema net; create schema vault;
create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb, raw_app_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table vault.decrypted_secrets (name text, decrypted_secret text);
insert into vault.decrypted_secrets values ('project_url','https://x.supabase.co'),('service_role_key','k');
create table net.chamadas (url text, body jsonb);
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
  headers jsonb default '{}', timeout_milliseconds int default 1000) returns bigint
  language sql as $$ insert into net.chamadas values (url, body) returning 1::bigint $$;

create table public.users (id uuid primary key, name text, phone text, role text);
create table public.admin_audit_log (id bigserial primary key, admin_id uuid, action text,
  target_type text, target_id text, details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now());
create table public.support_pending_actions (
  id uuid primary key default gen_random_uuid(), session_id uuid, user_id uuid references public.users(id),
  skill_name text not null, action_type text not null, action_payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','dispatched','executed','failed','rejected')),
  proposed_at timestamptz default now(), reviewed_at timestamptz, reviewed_by uuid, executed_at timestamptz,
  execution_result jsonb, rejection_reason text, user_message text, agent_reasoning text,
  dispatch_target text, dispatched_at timestamptz);
create table public.in_app_notifications (id uuid primary key default gen_random_uuid(), user_id uuid,
  kind text, title text, body text, related_id text, read_at timestamptz, created_at timestamptz default now());
create table public.orders (id text primary key, user_id uuid, status text, customer_notes text,
  dropoff_address text, dropoff_lat float8, dropoff_lng float8);
create table public.reservations (id uuid primary key, status text, reserved_for timestamptz, client_user_id uuid);
create table public.platform_settings (key text primary key, value jsonb);

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = v_uid
      AND (
        COALESCE(raw_app_meta_data->>'role','') = 'admin'
        OR email IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com')
      )
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.is_conta_convidado() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'auth'
AS $function$
  select exists (
    select 1 from auth.users u
    where u.id = auth.uid() and lower(u.email) = 'guest@bora.com'
  );
$function$;
CREATE OR REPLACE FUNCTION public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text, p_body text DEFAULT NULL::text, p_related_id text DEFAULT NULL::text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF p_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users au WHERE au.id = p_user_id) THEN
    RETURN NULL;
  END IF;
  INSERT INTO in_app_notifications (user_id, kind, title, body, related_id)
    VALUES (p_user_id, p_kind, p_title, p_body, p_related_id)
    RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[_push_in_app_notification] skipped for user %: %', p_user_id, SQLERRM;
  RETURN NULL;
END;
$function$;
`);

// admin_approve_action tal como está no repo; confere-se contra produção.
const old = fs.readFileSync(OLD, 'utf8');
const ini = old.search(/CREATE OR REPLACE FUNCTION public\.admin_approve_action\(p_action_id uuid\)/);
const tag = old.slice(ini).match(/AS (\$[a-z_]*\$)/)[1];
const corpoIni = old.indexOf(tag, ini) + tag.length;
const corpoFim = old.indexOf(tag, corpoIni);
const fnSql = old.slice(ini, corpoFim + tag.length) + ';';
await db.exec(fnSql);
const [{ m }] = await q(`select md5(prosrc) m from pg_proc where proname='admin_approve_action'`);
out.approve_repo_igual_producao = m === PROD_MD5_APPROVE ? true : `DIFERENTE ${m}`;

// dados de teste
const CLI = '11111111-1111-4111-8111-111111111111';
const ADM = '22222222-2222-4222-8222-222222222222';
const GUEST = '33333333-3333-4333-8333-333333333333';
await db.exec(`
insert into auth.users values ('${CLI}','cliente.teste@bora.test','{"bora_name":"Cliente Velho","bora_phone":"+351900000010","outro":"fica"}','{}'),
                              ('${ADM}','nilofulfarotuga@gmail.com','{}','{}'),
                              ('${GUEST}','guest@bora.com','{}','{}');
insert into public.users values ('${CLI}','Cliente Velho','+351900000010','client'),('${ADM}','Danilo',null,'client'),('${GUEST}','Convidado',null,'client');
`);

// ── migrações tal como estão no repo ───────────────────────────────────────
const m1 = fs.readFileSync(MIG1, 'utf8');
const m2 = fs.readFileSync(MIG2, 'utf8');
out.md5_mig1 = md5(m1);
out.md5_mig2 = md5(m2);
await db.exec(m1);
await db.exec(m2);
out.mig2_reaplicada_sem_erro = await db.exec(m2).then(() => true, (e) => e.message); // idempotente

const como = async (uid) => {
  await db.exec(`select set_config('request.jwt.claim.sub', '${uid ?? ''}', false)`);
};
const rpc = async (sql) => (await q(sql))[0];
const fichas = async () => rpc(`select u.name, u.phone, a.raw_user_meta_data meta from public.users u join auth.users a on a.id=u.id where u.id='${CLI}'`);

await como(CLI);
out.t1_grava = (await rpc(`select public.client_update_my_profile('  Cliente   E2E  Editado ', '+351 912 345 678') r`)).r;
out.t1_ficha = await fichas();
out.t2_igual = (await rpc(`select public.client_update_my_profile('Cliente E2E Editado', '912345678') r`)).r;
out.t2b_so_nome_tel_vazio = (await rpc(`select public.client_update_my_profile('Cliente E2E Editado', '') r`)).r.alterado;
out.t3_nome_A = (await rpc(`select public.client_update_my_profile('A', null) r`)).r.codigo;
out.t3_nome_12 = (await rpc(`select public.client_update_my_profile('12', null) r`)).r.codigo;
out.t3_nome_61 = (await rpc(`select public.client_update_my_profile(repeat('a',61), null) r`)).r.codigo;
out.t3_nome_60_ok = (await rpc(`select public.client_update_my_profile(repeat('b',60), null) r`)).r.ok;
out.t4_tel_812 = (await rpc(`select public.client_update_my_profile('Nome Bom', '812345678') r`)).r.codigo;
out.t4_tel_curto = (await rpc(`select public.client_update_my_profile('Nome Bom', '9123') r`)).r.codigo;
out.t4_tel_00351 = (await rpc(`select public.client_update_my_profile('Cliente E2E Editado', '00351 93-111-2222') r`)).r.phone;
out.t7_cliente_no_admin = await q(`select public.admin_update_client_contact('${CLI}', 'Hack Hack', null)`).then(() => 'NAO BLOQUEOU', (e) => e.message);
out.t7b_cliente_historico = await q(`select * from public.admin_get_profile_changes('${CLI}', 5)`).then(() => 'NAO BLOQUEOU', (e) => e.message);

await como(null);
out.t5_sem_sessao = (await rpc(`select public.client_update_my_profile('Xx Yy', null) r`)).r.codigo;
await como(GUEST);
out.t5b_convidado = (await rpc(`select public.client_update_my_profile('Xx Yy', null) r`)).r.codigo;

// limite diário (10 por dia, só para o próprio cliente)
await como(CLI);
for (let i = 0; i < 12; i++) await q(`select public.client_update_my_profile('Nome Repetido ${String.fromCharCode(97 + i)}', null)`);
out.t13_limite = (await rpc(`select public.client_update_my_profile('Nome Depois Limite', null) r`)).r.codigo;

await como(ADM);
out.t6_admin = (await rpc(`select public.admin_update_client_contact('${CLI}', 'Cliente E2E Admin', null) r`)).r;
out.t6_admin_sem_mudanca = (await rpc(`select public.admin_update_client_contact('${CLI}', null, null) r`)).r;
out.t6_admin_tel_invalido = (await rpc(`select public.admin_update_client_contact('${CLI}', null, '123') r`)).r;

const [{ id: act }] = await q(`insert into public.support_pending_actions (user_id, skill_name, action_type, action_payload, user_message)
  values ('${CLI}','GENERAL_FAQ','ACCOUNT_UPDATE','{"name":"Cliente E2E Robo","phone":"+351 913 000 000"}','prova') returning id`);
out.t8_robo = (await rpc(`select public.admin_approve_action('${act}') r`)).r;
out.t8_estado = (await rpc(`select status, executed_at is not null exec from public.support_pending_actions where id='${act}'`));
out.t8_ficha = await fichas();

const [{ id: act2 }] = await q(`insert into public.support_pending_actions (user_id, skill_name, action_type, action_payload, user_message)
  values ('${CLI}','GENERAL_FAQ','ACCOUNT_UPDATE','{"name":"Outro Nome","email":"x@y.z"}','prova') returning id`);
out.t9_proibido = (await rpc(`select public.admin_approve_action('${act2}') r`)).r;
out.t9_estado = (await rpc(`select status from public.support_pending_actions where id='${act2}'`)).status;

const [{ id: act3 }] = await q(`insert into public.support_pending_actions (user_id, skill_name, action_type, action_payload, user_message)
  values ('${CLI}','GENERAL_FAQ','ACCOUNT_UPDATE','{"phone":"812"}','prova') returning id`);
out.t9b_tel_mau = (await rpc(`select public.admin_approve_action('${act3}') r`)).r;
out.t9b_estado_e_ficha_intacta = { estado: (await rpc(`select status from public.support_pending_actions where id='${act3}'`)).status, ficha: (await fichas()).phone };
out.t9c_duplo_toque = await q(`select public.admin_approve_action('${act}')`).then(() => 'NAO BLOQUEOU', (e) => e.message);

out.t_avisos = await q(`select kind, title, body from public.in_app_notifications where user_id='${CLI}' order by created_at`);
out.t_push_chamadas = (await rpc(`select count(*)::int n from net.chamadas`)).n;
out.t10_historico = await q(`select origem, quem, antes, depois, pending_action_id is not null tem_pedido from public.admin_get_profile_changes('${CLI}', 6)`);
out.t_auditoria_admin = await q(`select action, details from public.admin_audit_log`);

out.t11_privilegios = await rpc(`select
  has_function_privilege('authenticated','public._apply_user_profile_change(uuid,text,text,uuid,text,uuid)','execute') auth_apply,
  has_function_privilege('anon','public._apply_user_profile_change(uuid,text,text,uuid,text,uuid)','execute') anon_apply,
  has_function_privilege('authenticated','public._notify_profile_changed(uuid,jsonb,text)','execute') auth_notify,
  has_function_privilege('anon','public.client_update_my_profile(text,text)','execute') anon_client,
  has_function_privilege('authenticated','public.client_update_my_profile(text,text)','execute') auth_client,
  has_function_privilege('anon','public.admin_get_profile_changes(uuid,integer)','execute') anon_hist,
  has_table_privilege('authenticated','public.user_profile_changes','select') auth_tab`);

const [{ def }] = await q(`select def from public.bkp_fn_admin_approve_action_20261111 limit 1`);
const [{ novo }] = await q(`select pg_get_functiondef('public.admin_approve_action(uuid)'::regprocedure) novo`);
const a = "WHEN 'ACCOUNT_UPDATE' THEN", b = "WHEN 'PASSWORD_RESET' THEN";
out.t12_outros_ramos_iguais = def.slice(0, def.indexOf(a)) === novo.slice(0, novo.indexOf(a)) && def.slice(def.indexOf(b)) === novo.slice(novo.indexOf(b));

console.log(JSON.stringify(out, null, 1));
