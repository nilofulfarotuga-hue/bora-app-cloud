// Prova da migração 20261118210000 em PGlite (Postgres real, PL/pgSQL).
// Uso: node prova_excecao.mjs <pasta-pglite> <migração>
import { createRequire } from 'module';
import fs from 'fs';
const [, , pasta, migracao] = process.argv;
const require = createRequire(pasta + '/package.json');
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();

const stubs = `
create schema auth; create schema vault; create schema net;
create table auth.users(id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true),'')::uuid $$;
create view vault.decrypted_secrets as select 'project_url'::text as name, 'https://x'::text as decrypted_secret union all select 'service_role_key','k';
create table net.chamadas(id serial, url text, body jsonb);
create function net.http_post(url text, headers jsonb, body jsonb) returns bigint language sql as $$ insert into net.chamadas(url, body) values (url, body) returning id::bigint $$;

create table public.platform_settings(key text primary key, value jsonb);
insert into public.platform_settings values ('provider_atividade_obrigatoria','true'::jsonb), ('provider_atividade_corte','"2026-10-20T00:00:00Z"'::jsonb);
create function public._provider_atividade_config() returns table(ligado boolean, corte timestamptz) language sql stable as $$
  select coalesce((select (value #>> '{}')::boolean from platform_settings where key='provider_atividade_obrigatoria'), false),
         (select (value #>> '{}')::timestamptz from platform_settings where key='provider_atividade_corte') $$;
create function public.is_admin() returns boolean language sql stable as $$
  select exists(select 1 from auth.users where id = auth.uid() and coalesce(raw_app_meta_data->>'role','')='admin') $$;
create function public._admin_op_guard() returns table(admin_id uuid, admin_email text) language plpgsql as $$
begin if not public.is_admin() then raise exception 'admin_required'; end if;
  return query select auth.uid(), (select email from auth.users where id=auth.uid()); end $$;

create table public.provider_atividade(user_id uuid primary key, atividade_status text default 'por_enviar', documento_path text);
create table public.provider_atividade_eventos(id serial, user_id uuid, evento text, estado_antes text, estado_depois text, motivo text, autor uuid, autor_tipo text, detalhe jsonb, created_at timestamptz default now());
create function public._provider_atividade_garantir(p uuid) returns public.provider_atividade language plpgsql as $$
declare r public.provider_atividade; begin insert into provider_atividade(user_id) values (p) on conflict do nothing;
select * into r from provider_atividade where user_id=p; return r; end $$;
create function public._provider_atividade_evento(p_uid uuid, p_evento text, p_antes text, p_depois text, p_motivo text, p_autor uuid, p_autor_tipo text, p_detalhe jsonb default '{}') returns void language sql as $$
  insert into provider_atividade_eventos(user_id, evento, estado_antes, estado_depois, motivo, autor, autor_tipo, detalhe) values (p_uid,p_evento,p_antes,p_depois,p_motivo,p_autor,p_autor_tipo,p_detalhe) $$;
create table public.admin_audit_log(id serial, action text, entity_type text, entity_id text, details jsonb);
create function public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb) returns void language sql as $$
  insert into admin_audit_log(action, entity_type, entity_id, details) values ($1,$2,$3,$4) $$;
-- Produção tem as duas versões (entity_id text e uuid): a chamada tem de escolher sem ambiguidade.
create function public.log_admin_action(p_action text, p_entity_type text, p_entity_id uuid, p_details jsonb) returns void language sql as $$
  insert into admin_audit_log(action, entity_type, entity_id, details) values ($1,$2,$3::text,$4) $$;

create table public.drivers(id uuid primary key, user_id uuid, approval_status text, created_at timestamptz);
create table public.cleaners(id uuid primary key, user_id uuid, approval_status text, created_at timestamptz);
create table public.washers(id uuid primary key, user_id uuid, approval_status text, created_at timestamptz);
create table public.casa_profissionais(id uuid primary key, user_id uuid, approval_status text, created_at timestamptz);
-- Tipos iguais aos de produção (conferidos 18/11 em information_schema): service_providers.id é TEXT.
create table public.service_providers(id text primary key, user_id uuid, approval_status text, created_at timestamptz);
create function public.admin_approve_driver(p_driver_id uuid, p_force boolean, p_justification text) returns jsonb language plpgsql as $$
begin perform public._admin_op_guard(); update drivers set approval_status='approved' where id=p_driver_id; return '{}'; end $$;
create function public.admin_review_cleaner(p_cleaner_id uuid, p_action text, p_reason text) returns jsonb language plpgsql as $$
begin perform public._admin_op_guard(); update cleaners set approval_status='approved' where id=p_cleaner_id; return '{}'; end $$;
create function public.admin_rever_lavador(p_washer_id uuid, p_accao text, p_motivo text) returns jsonb language plpgsql as $$
begin update washers set approval_status='approved' where id=p_washer_id; return '{}'; end $$;
create function public.admin_casa_decidir_profissional(p_id uuid, p_acao text, p_motivo text) returns jsonb language plpgsql as $$
begin update casa_profissionais set approval_status='approved' where id=p_id; return '{}'; end $$;
create function public.admin_appointment_provider_approve(p_provider_id text) returns void language plpgsql as $$
begin update service_providers set approval_status='approved' where id=p_provider_id; end $$;

create table public.users(id uuid primary key, fcm_token text);
create table public.driver_push_tokens(user_id uuid, fcm_token text, active boolean);
create table public.provider_push_tokens(user_id uuid, fcm_token text, active boolean);
create table public.client_push_tokens(user_id uuid, fcm_token text, active boolean);
create table public.in_app_notifications(id uuid primary key default gen_random_uuid(), user_id uuid, kind text, title text, body text, related_id text);
create function public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text, p_body text default null, p_related_id text default null) returns uuid language plpgsql as $$
declare v uuid; begin insert into in_app_notifications(user_id,kind,title,body,related_id) values (p_user_id,p_kind,p_title,p_body,p_related_id) returning id into v; return v; end $$;
create role anon; create role authenticated;
`;

const A = '00000000-0000-4000-8000-00000000000a'; // admin
const N = '00000000-0000-4000-8000-00000000000b'; // não-admin
const P1 = '00000000-0000-4000-8000-000000000001', P2 = '00000000-0000-4000-8000-000000000002';
const C1 = '10000000-0000-4000-8000-000000000001', C2 = '10000000-0000-4000-8000-000000000002';
const D1 = '20000000-0000-4000-8000-000000000001';
const P3 = '00000000-0000-4000-8000-000000000003', S1 = 'prov-texto-1';

let ok = 0, falhou = 0;
const prova = (nome, cond, extra = '') => { if (cond) { ok++; console.log('OK  ', nome); } else { falhou++; console.log('FALHA', nome, extra); } };
const tenta = async (sql) => { try { await db.exec(sql); return null; } catch (e) { return e.message; } };
const comoUser = (uid, sql) => `begin; select set_config('test.uid','${uid}', true); ${sql}; commit;`;

await db.exec(stubs);
// Gatilhos iguais aos de produção (trg_atividade_antes_de_ativar) — criados depois da migração.
await db.exec(fs.readFileSync(migracao, 'utf8'));
for (const t of ['drivers', 'cleaners', 'washers', 'casa_profissionais', 'service_providers']) {
  await db.exec(`create trigger trg_atividade_antes_de_ativar before update of approval_status on public.${t} for each row when (new.approval_status = 'approved' and old.approval_status is distinct from 'approved') execute function fn_atividade_antes_de_ativar();`);
}
await db.exec(`insert into auth.users values ('${A}','admin@x','{"role":"admin"}'), ('${N}','n@x','{}'), ('${P1}','p1@x','{}'), ('${P2}','p2@x','{}'), ('${P3}','p3@x','{}');
  insert into service_providers values ('${S1}','${P3}','pending', now());
  insert into cleaners values ('${C1}','${P1}','pending', now()), ('${C2}','${P2}','pending', now());
  insert into drivers values ('${D1}','${P2}','pending', now());
  insert into provider_atividade values ('${P1}','em_analise','p1/c.png'), ('${P2}','por_enviar',null);`);

// 1. A trava continua: admin a aprovar normalmente sem comprovativo → recusa.
let e = await tenta(comoUser(A, `select admin_review_cleaner('${C1}','approve','')`));
await db.exec('rollback').catch(() => {});
prova('aprovar normal sem comprovativo é recusado (atividade_por_aprovar)', e && e.includes('atividade_por_aprovar'), e);

// 2. Não-admin não usa a exceção nem com a marca posta à mão.
e = await tenta(comoUser(N, `select set_config('bora.excecao_atividade','${P1}', true); update cleaners set approval_status='approved' where id='${C1}'`));
await db.exec('rollback').catch(() => {});
prova('não-admin com a marca posta à mão continua bloqueado', e && e.includes('atividade_por_aprovar'), e);
e = await tenta(comoUser(N, `select admin_aprovar_prestador_excecao('cleaner','${C1}','motivo bem comprido')`));
await db.exec('rollback').catch(() => {});
prova('não-admin não chama a exceção (admin_required)', e && e.includes('admin_required'), e);

// 3. Motivo curto → recusa.
e = await tenta(comoUser(A, `select admin_aprovar_prestador_excecao('cleaner','${C1}','curto')`));
await db.exec('rollback').catch(() => {});
prova('motivo com menos de 10 letras é recusado', e && e.includes('motivo_excecao_curto'), e);

// 4. Exceção do admin aprova, grava evento e auditoria.
e = await tenta(comoUser(A, `select admin_aprovar_prestador_excecao('cleaner','${C1}','Ordem do Danilo 18/11, comprovativo chega amanhã')`));
prova('exceção do admin passa', e === null, e);
let r = await db.query(`select approval_status from cleaners where id='${C1}'`);
prova('limpadora ficou aprovada', r.rows[0].approval_status === 'approved', JSON.stringify(r.rows));
r = await db.query(`select evento, estado_antes, motivo, autor::text, detalhe->>'papel' papel from provider_atividade_eventos where user_id='${P1}'`);
prova('evento excecao_admin em provider_atividade_eventos (quem e porquê)', r.rows.length === 1 && r.rows[0].evento === 'excecao_admin' && r.rows[0].autor === A && r.rows[0].papel === 'cleaner' && r.rows[0].motivo.startsWith('Ordem do Danilo'), JSON.stringify(r.rows));
r = await db.query(`select action, entity_id, details->>'motivo' m from admin_audit_log where action='prestador_aprovado_excecao'`);
prova('linha prestador_aprovado_excecao em admin_audit_log', r.rows.length === 1 && r.rows[0].entity_id === C1, JSON.stringify(r.rows));
r = await db.query(`select atividade_status from provider_atividade where user_id='${P1}'`);
prova('o comprovativo NÃO foi marcado como aprovado (fica em análise)', r.rows[0].atividade_status === 'em_analise', JSON.stringify(r.rows));

// 5. A marca não fica para a transação seguinte: outra pessoa continua bloqueada.
e = await tenta(comoUser(A, `select admin_review_cleaner('${C2}','approve','')`));
await db.exec('rollback').catch(() => {});
prova('a seguir, aprovar outra pessoa sem comprovativo continua recusado', e && e.includes('atividade_por_aprovar'), e);
// Nem na mesma transação: a marca é só para a pessoa da exceção.
e = await tenta(comoUser(A, `select admin_aprovar_prestador_excecao('driver','${D1}','Exceção para o estafeta P2'); select admin_review_cleaner('${C2}','approve','')`));
await db.exec('rollback').catch(() => {});
prova('mesma transação: a marca foi limpa antes de aprovar outro', e && e.includes('atividade_por_aprovar'), e);

// 6. Estafeta pela exceção.
e = await tenta(comoUser(A, `select admin_aprovar_prestador_excecao('driver','${D1}','Ordem do Danilo, estafeta de teste')`));
r = await db.query(`select approval_status from drivers where id='${D1}'`);
prova('estafeta aprovado pela exceção', e === null && r.rows[0].approval_status === 'approved', e || JSON.stringify(r.rows));

// 6b. Serviços (id de texto) pela exceção, e id inválido num papel uuid.
e = await tenta(comoUser(A, `select admin_aprovar_prestador_excecao('service_provider','${S1}','Ordem do Danilo, prestador de teste')`));
r = await db.query(`select approval_status from service_providers where id='${S1}'`);
prova('prestador de serviços (id de texto) aprovado pela exceção', e === null && r.rows[0].approval_status === 'approved', e || JSON.stringify(r.rows));
e = await tenta(comoUser(A, `select admin_aprovar_prestador_excecao('cleaner','nao-e-uuid','Motivo comprido o suficiente')`));
await db.exec('rollback').catch(() => {});
prova('id inválido num papel uuid dá prestador_nao_encontrado (não erro cru)', e && e.includes('prestador_nao_encontrado'), e);

// 7. Pedir documentos: aviso com kind próprio, papel em related_id, push e auditoria.
e = await tenta(comoUser(A, `select admin_pedir_documentos_em_falta('${P2}','driver','Faltam documentos na tua candidatura','Na tua conta de estafeta falta: foto do veículo.', array['foto do veículo'])`));
prova('pedir documentos passa', e === null, e);
r = await db.query(`select kind, related_id from in_app_notifications where user_id='${P2}'`);
prova('aviso no sino: kind documentos_em_falta, related_id driver', r.rows.length === 1 && r.rows[0].kind === 'documentos_em_falta' && r.rows[0].related_id === 'driver', JSON.stringify(r.rows));
r = await db.query(`select body->>'kind' k, body->>'relatedId' rel from net.chamadas`);
prova('push pedido à Edge notify-admin-message com kind e papel', r.rows.length === 1 && r.rows[0].k === 'documentos_em_falta' && r.rows[0].rel === 'driver', JSON.stringify(r.rows));
e = await tenta(comoUser(N, `select admin_pedir_documentos_em_falta('${P2}','driver','t','x')`));
await db.exec('rollback').catch(() => {});
prova('não-admin não pede documentos', e && e.includes('admin_required'), e);

// 8. Privilégios: anon não executa as funções novas.
r = await db.query(`select has_function_privilege('anon','public.admin_aprovar_prestador_excecao(text,text,text)','execute') a, has_function_privilege('anon','public.admin_pedir_documentos_em_falta(uuid,text,text,text,text[])','execute') b, has_function_privilege('authenticated','public.admin_aprovar_prestador_excecao(text,text,text)','execute') c`);
prova('anon sem execução; authenticated com execução', !r.rows[0].a && !r.rows[0].b && r.rows[0].c, JSON.stringify(r.rows));

console.log(`\n${ok} OK, ${falhou} falhas`);
process.exit(falhou ? 1 : 0);
