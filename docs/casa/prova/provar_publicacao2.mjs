// Prova em PGlite (Postgres 16 em WASM) da migração 20261109074000 e dos SQL da PUBLICAÇÃO 2 da Casa,
// com as funções REAIS de produção (pg_get_functiondef lido a 09/11/2026 para defs.json) e tabelas-modelo
// com as colunas de produção. Stubs só para o que sai da base: avisos push (_casa_notificar) e rotação.
// Uso (numa pasta do %TEMP% com `npm install @electric-sql/pglite@0.2.17`, este ficheiro e o defs.json):
//   npx --no-install supabase db query --remote=ojykpzwqrtusfeakzrna --read-only --agent no \
//       --output-format json -f defs.sql > defs.json        (só leitura: as funções tal como estão no ar)
//   node provar_publicacao2.mjs <pasta-do-repo>
// Resultado de 09/11/2026 em prova_pglite_2026-11-09.txt.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import path from 'node:path';

const repo = process.argv[2];
const sqlDir = path.join(repo, 'docs/casa/sql');
const defs = JSON.parse(fs.readFileSync(new URL('./defs.json', import.meta.url), 'utf8'));
const db = new PGlite();

const ADMIN = 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
const PRO_USER = '503a2e09-2111-44b5-9852-d6d5897467f1';
const PROF = 'ad8e790d-7519-4366-9565-257f816babd1';

await db.exec(`
create schema auth; create schema supabase_migrations;
create table auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table supabase_migrations.schema_migrations (version text primary key, statements text[], name text,
  created_by text, idempotency_key text unique, rollback text[]);
create table public.platform_settings (key text primary key, value jsonb, description text, category text,
  updated_at timestamptz default now(), updated_by uuid references auth.users(id), is_secret boolean default false);
create table public.users (id uuid primary key, role text, marketing_opt_in boolean default false, fcm_token text);
create table public.casa_oficios (codigo text primary key, nome text, descricao text, fase smallint,
  documento_exigido text, ativo boolean, ordem int, updated_at timestamptz, updated_by uuid);
create table public.casa_servicos (id uuid primary key default gen_random_uuid(), oficio text references casa_oficios,
  nome text, descricao text, modo text, preco_cents int, unidade text, min_quantidade numeric, max_quantidade numeric,
  duracao_min int, perguntas jsonb, ativo boolean, ordem int, created_at timestamptz, updated_at timestamptz, updated_by uuid);
create table public.casa_profissionais (id uuid primary key, user_id uuid unique, name text, phone text, email text,
  photo_url text, bio text, nif text, legal_name text, iban text, address text, birth_date date,
  dsa_self_certified_at timestamptz, dsa_self_cert_version text, base_lat float8, base_lng float8, base_address text,
  service_radius_km numeric, has_van boolean, has_tools boolean, approval_status text, approved_at timestamptz,
  approved_by uuid, rejection_reason text, is_active boolean, rating_avg numeric, ratings_count int, jobs_done int,
  sem_comissao_ate date, docs jsonb, created_at timestamptz default now(), updated_at timestamptz);
create table public.casa_profissional_oficios (profissional_id uuid references casa_profissionais(id) on delete cascade,
  oficio text references casa_oficios(codigo), estado text default 'pending'
  check (estado in ('pending','approved','rejected','suspended')), ligado boolean default true, decidido_por uuid,
  decidido_em timestamptz, motivo text, created_at timestamptz default now(), primary key (profissional_id, oficio));
create table public.casa_documentos (id uuid primary key default gen_random_uuid(), profissional_id uuid, tipo text,
  estado text, validade date);
create table public.casa_pedidos (id uuid primary key default gen_random_uuid(), profissional_id uuid, estado text,
  offer_profissional_id uuid, offer_expires_at timestamptz);
create table public.casa_ofertas (pedido_id uuid, profissional_id uuid, resposta text, respondida_em timestamptz);
create table public.admin_audit_log (id uuid primary key default gen_random_uuid(), admin_id uuid, admin_email text,
  action text, entity_type text, entity_id uuid, details jsonb, ip_address text, created_at timestamptz default now(),
  entity_id_text text);
create table public.home_banners (id uuid primary key default gen_random_uuid(), titulo text, subtitulo text,
  imagem_url text, cor_inicio text default '#16A34A', cor_fim text default '#F97316', tipo_destino text default 'nenhum'
  check (tipo_destino in ('loja','categoria','cozinha','produto','codigo','nenhum')), destino text, ordem int default 100,
  ativo boolean default true, inicio timestamptz, fim timestamptz, patrocinado boolean default false, parceiro_id text,
  criado_em timestamptz default now(), atualizado_em timestamptz default now());
create table public.push_broadcasts (id uuid primary key default gen_random_uuid(),
  segment text check (segment in ('all','clients','drivers','partners')),
  title text check (length(title) between 1 and 100), body text check (length(body) between 1 and 500),
  scheduled_at timestamptz, status text check (status in ('pending','sending','sent','failed')), sent_count int,
  failed_count int, created_by uuid, created_at timestamptz default now(), completed_at timestamptz,
  only_marketing_opt_in boolean, status_note text, target_user_ids uuid[], kind text, claimed_at timestamptz);
create table public.in_app_notifications (user_id uuid, kind text, title text, body text);
create table public.provider_push_tokens (user_id uuid, role text, platform text, active boolean, updated_at timestamptz);
create table public.orders (id text, user_id uuid, created_at timestamptz);
create table public.drivers (user_id uuid, is_online boolean);
-- Stubs do que sai da base (push e rotação): registam a chamada.
create table public._avisos (user_id uuid, papel text, tipo text, titulo text);
create function public._casa_notificar(p_user_id uuid, p_papel text, p_tipo text, p_titulo text, p_corpo text,
  p_pedido_id uuid) returns void language sql as $$ insert into public._avisos values (p_user_id, p_papel, p_tipo, p_titulo) $$;
create function public._casa_proxima_oferta(p_pedido_id uuid) returns void language sql as $$ select $$;
`);

let carregadas = 0;
for (const d of defs) {
  try { await db.exec(d.def + ';'); carregadas++; }
  catch (e) { console.log(`(função ${d.proname} não carregou em PGlite: ${e.message} — fica stub)`); }
}
console.log(`funções reais de produção carregadas: ${carregadas} de ${defs.length}`);
await db.exec(`create or replace function public.is_demo_user(uuid) returns boolean language sql as $$ select false $$`)
  .catch(() => {});

// Dados de partida = estado lido em produção a 09/11/2026 ~07:20.
await db.exec(`
insert into auth.users values ('${ADMIN}', 'admin@teste.local', '{"role":"admin"}'),
  ('${PRO_USER}', 'pro@teste.local', '{}'),
  ('00000000-0000-0000-0000-00000000c001', 'c1@teste.local', '{}'),
  ('00000000-0000-0000-0000-00000000c002', 'c2@teste.local', '{}'),
  ('00000000-0000-0000-0000-00000000c003', 'c3@teste.local', '{}');
insert into public.users values ('00000000-0000-0000-0000-00000000c001','client',true,null),
  ('00000000-0000-0000-0000-00000000c002','client',true,null), ('00000000-0000-0000-0000-00000000c003','client',false,null);
insert into public.platform_settings (key, value, category) values
  ('casa_enabled','false','casa'), ('casa_valores_autorizados','{"autorizado":true}','casa'),
  ('casa_promo_primeiros_n','5','casa'), ('casa_promo_meses','2','casa'), ('casa_bora_pct','15','casa'),
  ('casa_max_fotos','5','casa'), ('casa_min_lead_hours','2','casa'), ('max_cash_amount_cents','4000','pagamentos');
insert into public.casa_oficios (codigo, nome, fase, documento_exigido, ativo, ordem) values
  ('montagem','Montagem',1,null,true,1), ('fixacao','Fixação',1,null,true,2), ('reparacoes','Reparações',1,null,true,3),
  ('canalizacao','Canalização',1,null,true,4), ('jardinagem','Jardinagem',1,null,true,5), ('mudancas','Mudanças',1,null,true,6),
  ('eletricidade','Eletricidade',2,'dgeg_eletricidade',false,7);
insert into public.casa_servicos (oficio, nome, modo, preco_cents, unidade, perguntas, ativo, ordem) values
  ('montagem','Montar roupeiro','fixo',8000,'movel','[{"id":"material","tipo":"escolha","opcoes":["Sim, já tenho tudo"]}]',true,14),
  ('eletricidade','Trocar candeeiro','fixo',3000,'tarefa','[{"id":"material"}]',true,5);
insert into public.casa_profissionais (id, user_id, name, approval_status, is_active, has_tools)
  values ('${PROF}', '${PRO_USER}', 'Danilo Fulfaro', 'pending', true, true);
insert into public.casa_profissional_oficios (profissional_id, oficio) values ('${PROF}','montagem'), ('${PROF}','fixacao');
`);

async function correr(ficheiro, { esperaErro } = {}) {
  const sql = fs.readFileSync(path.join(sqlDir, ficheiro), 'utf8');
  try {
    const res = await db.exec(sql);
    if (esperaErro) { console.log(`✗ ${ficheiro}: devia ter recusado (${esperaErro})`); process.exitCode = 1; return; }
    const ultimo = res.filter((r) => r.rows && r.rows.length).pop();
    console.log(`✓ ${ficheiro}`);
    if (ultimo) for (const r of ultimo.rows) console.log('   ', JSON.stringify(r));
  } catch (e) {
    if (esperaErro && String(e.message).includes(esperaErro)) { console.log(`✓ ${ficheiro} recusou como devia: ${e.message}`); return; }
    console.log(`✗ ${ficheiro}: ${e.message}`); process.exitCode = 1;
  }
}

// Antes da migração, ligar a Casa recusa (falta o passo 1).
await correr('03_ligar_casa_e_selo.sql', { esperaErro: 'falta o passo 1' });
await correr('00_estado_antes.sql');
await correr('01_migracao_selo_novo.sql');
await correr('01_migracao_selo_novo.sql'); // idempotente
await correr('02_aprovar_danilo.sql');
await correr('02_aprovar_danilo.sql'); // idempotente
// A notificação recusa com a Casa desligada.
await correr('05_notificacao_clientes.sql', { esperaErro: 'ainda esta desligada' });
await correr('03_ligar_casa_e_selo.sql');
await correr('04_faixa_home.sql');
await correr('04_faixa_home.sql'); // não cria segunda faixa
await correr('05_notificacao_clientes.sql');
await correr('05_notificacao_clientes.sql', { esperaErro: 'ja houve uma difusao' });
await correr('06_verificar_depois.sql');

const q = async (s) => (await db.query(s)).rows;
console.log('--- verificações ---');
console.log('faixas da Casa:', (await q(`select count(*)::int n from home_banners where destino='casa'`))[0].n);
console.log('difusões:', JSON.stringify(await q(`select segment, kind, only_marketing_opt_in, cardinality(target_user_ids) pessoas, status from push_broadcasts`)));
console.log('sininho:', (await q(`select count(*)::int n from in_app_notifications`))[0].n, '(esperado 2: só os clientes com opt-in)');
console.log('avisos ao Danilo:', JSON.stringify(await q(`select tipo, titulo from _avisos`)));
console.log('auditoria:', JSON.stringify(await q(`select action, count(*)::int n from admin_audit_log group by action order by action`)));
console.log('valores ainda autorizados:', (await q(`select public._casa_valores_validos() v`))[0].v);
console.log('promoção do Danilo (sem_comissao_ate):', (await q(`select sem_comissao_ate from casa_profissionais`))[0].sem_comissao_ate);
const sel = (await q(`select public.get_setting('casa_novo_ate') v`))[0].v;
console.log('get_setting(casa_novo_ate) =', JSON.stringify(sel));

await correr('99_reverter.sql');
