// Prova local (PGlite = Postgres em WASM, nada toca em produção) das migrações da missão m4:
//   20261108210000_amigo_bora_v1.sql e 20261108220000_suporte_conversa_admin.sql
// Uso: node provar_sql.mjs <pasta-com-node_modules-do-pglite> <migração1> <migração2>
// Cria por baixo o mínimo do esquema de produção (tabelas e funções que as migrações usam),
// corre as migrações DUAS vezes (idempotência) e verifica os cenários. Sai com código 1 se falhar.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [, , pasta, ...migracoes] = process.argv;
const { PGlite } = await import(pathToFileURL(join(pasta, 'node_modules/@electric-sql/pglite/dist/index.js')).href);
const db = new PGlite();
let falhas = 0;
const ok = (cond, msg, extra) => {
  console.log(`${cond ? 'OK  ' : 'FALHA'} ${msg}${extra !== undefined ? ' → ' + JSON.stringify(extra) : ''}`);
  if (!cond) falhas++;
};
const q = async (sql, params) => (await db.query(sql, params)).rows;
const um = async (sql, params) => (await q(sql, params))[0];
async function como(uid, admin, fn) {
  await db.exec(`select set_config('test.uid', '${uid ?? ''}', false), set_config('test.admin', '${admin ? 'on' : 'off'}', false)`);
  try { return await fn(); } finally { await db.exec(`select set_config('test.uid', '', false), set_config('test.admin', 'off', false)`); }
}
async function erro(fn) { try { await fn(); return null; } catch (e) { return e.message; } }

// ─── Esquema mínimo (cópia das colunas de produção que as migrações usam) ─────
await db.exec(`

do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create schema if not exists auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create function public.is_admin() returns boolean language sql stable as $$ select current_setting('test.admin', true) = 'on' $$;
create function public.is_conta_convidado() returns boolean language sql stable as $$ select false $$;
create function public.is_demo_user(uuid) returns boolean language sql stable as $$ select false $$;
create table public.admin_audit_log (id uuid default gen_random_uuid(), action text, entity_type text, entity_id_text text, details jsonb, criado timestamptz default now());
create function public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb default null)
  returns void language plpgsql as $$ begin insert into public.admin_audit_log(action, entity_type, entity_id_text, details) values (p_action_type, p_entity_type, p_entity_id, p_details); end $$;
create table public.admin_notifications (id uuid primary key default gen_random_uuid(), created_at timestamptz default now(), event_type text, severity text,
  entity_type text, entity_id text, summary text, payload jsonb, deep_link text, read_at timestamptz, archived_at timestamptz);
create function public.notify_admin_urgent_push(p_event_type text, p_summary text, p_entity_type text, p_entity_id text, p_payload jsonb, p_deep_link text)
  returns uuid language plpgsql as $$ declare v uuid; begin insert into public.admin_notifications(event_type, summary, entity_type, entity_id, payload, deep_link)
  values (p_event_type, p_summary, p_entity_type, p_entity_id, p_payload, p_deep_link) returning id into v; return v; end $$;
create table public.notificacoes_cliente (user_id uuid, kind text, title text, body text, ref text);
create function public._push_in_app_notification(p_user uuid, p_kind text, p_title text, p_body text, p_ref text)
  returns void language plpgsql as $$ begin insert into public.notificacoes_cliente values (p_user, p_kind, p_title, p_body, p_ref); end $$;
create schema if not exists cron;
create table cron.job (jobname text primary key, schedule text, command text);
create function cron.schedule(p_nome text, p_quando text, p_cmd text) returns bigint language plpgsql as $$
  begin insert into cron.job values (p_nome, p_quando, p_cmd) on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command; return 1; end $$;
create schema if not exists vault;
create table vault.decrypted_secrets (name text, decrypted_secret text);
create schema if not exists net;
create function net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds int default 5000) returns bigint language sql as $$ select 1::bigint $$;

create table public.platform_settings (key text primary key, value jsonb not null, description text, category text, updated_at timestamptz not null default now(), updated_by uuid, is_secret boolean not null default false);
insert into public.platform_settings(key, value) values
  ('assistant_enabled', 'true'), ('claude_robos', '{"ligado": true, "edge-assistente": {"usar": true, "modelo": "claude-sonnet-5-5", "prioridade": 1}}');
create table public.users (id uuid primary key, name text, email text, phone text);
create table public.restaurants (id text primary key, name text, created_at timestamptz default now(), approved_at timestamptz, approval_status text default 'approved',
  coming_soon boolean default false, is_active_admin boolean default true, category text, is_partner boolean default true);
create table public.orders (id text primary key, user_id uuid, status text, service_type text, vendor_name text, restaurant_id text, items jsonb,
  customer_total numeric, created_at timestamptz default now(), is_test_order boolean default false);
create table public.cleaning_bookings (id uuid primary key default gen_random_uuid(), client_user_id uuid, status text, created_at timestamptz default now(), scheduled_at timestamptz);
create table public.home_banners (id uuid primary key default gen_random_uuid(), titulo text, subtitulo text, tipo_destino text, destino text, ordem int default 0,
  ativo boolean default true, inicio timestamptz, fim timestamptz, atualizado_em timestamptz default now());
create table public.assistant_client_memory (id uuid primary key default gen_random_uuid(), user_id uuid, kind text, key text, value jsonb, source text,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table public.assistant_conversations (id uuid primary key default gen_random_uuid(), user_id uuid, started_at timestamptz default now(), cost_usd numeric default 0, messages_count int default 0);
create table public.assistant_cart_proposals (id uuid primary key default gen_random_uuid(), conversation_id uuid, opened_at timestamptz, order_id text, created_at timestamptz default now());
create table public.ia_gastos (id bigserial, quando timestamptz default now(), robo text, custo_usd numeric);
create table public.support_chatbot_sessions (id uuid primary key default gen_random_uuid(), user_id uuid, user_role text default 'client', order_id text,
  messages_count int default 0, started_at timestamptz default now(), ended_at timestamptz, escalated boolean default false, escalation_reason text,
  ticket_id uuid, mode text default 'ai' constraint support_chatbot_sessions_mode_check check (mode = any (array['ai','human_persona'])),
  persona_name text, escalated_pending boolean default false);
create table public.support_chatbot_messages (id uuid primary key default gen_random_uuid(), session_id uuid references public.support_chatbot_sessions(id) on delete cascade,
  role text constraint support_chatbot_messages_role_check check (role = any (array['user','assistant','tool','system'])), content text, tool_name text,
  tool_input jsonb, tool_output jsonb, tokens_used int, created_at timestamptz default now());
create table public.support_tickets (id uuid primary key default gen_random_uuid(), user_id uuid, user_role text, channel text, subject text, question text,
  body text, order_id text, session_id uuid, status text);
-- Gatilhos que já existem em produção (as migrações só trocam as funções).
create function public.notify_support_user_message_admin() returns trigger language plpgsql as $$ begin
  perform public.notify_admin_urgent_push('support_user_message', 'x', 'support_session', new.session_id::text, '{}'::jsonb, '/admin/support-escalations'); return new; end $$;
create trigger trg_notify_support_user_message_admin after insert on public.support_chatbot_messages for each row execute function public.notify_support_user_message_admin();
create function public.notify_support_ticket_admin() returns trigger language plpgsql as $$ begin
  perform public.notify_admin_urgent_push('support_ticket_new', 'x', 'support_ticket', new.id::text, '{}'::jsonb, '/admin/support'); return new; end $$;
create trigger trg_notify_support_ticket_admin after insert on public.support_tickets for each row execute function public.notify_support_ticket_admin();
`);

// Dados antes das migrações.
const A = '11111111-1111-1111-1111-111111111111'; // cliente com 3 sextas no Jyosmi
const B = '22222222-2222-2222-2222-222222222222'; // outro cliente
const ADM = '33333333-3333-3333-3333-333333333333';
const S = '44444444-4444-4444-4444-444444444444'; // cliente do suporte
await db.exec(`
insert into auth.users values ('${A}', 'ana@teste.pt'), ('${B}', 'bruno@teste.pt'), ('${S}', 'said@teste.pt');
insert into public.users values ('${A}', 'Ana Teste', 'ana@teste.pt', '910000001'), ('${S}', 'S. Teste', 'said@teste.pt', '961000000');
insert into public.restaurants(id, name, approved_at, category) values
  ('jyosmi-sushi-guarda', 'Jyosmi Sushi', now() - interval '200 days', 'sushi'),
  ('loja-nova', 'Loja Nova', now() - interval '3 days', 'padaria'),
  ('loja-em-breve', 'Em Breve', now() - interval '2 days', 'x');
update public.restaurants set coming_soon = true where id = 'loja-em-breve';
-- Sextas às 20h de Lisboa (= 20h UTC em novembro): 23/10, 30/10 e 06/11/2026.
insert into public.orders values
  ('o1', '${A}', 'delivered', 'restaurant', 'Jyosmi Sushi', 'jyosmi-sushi-guarda', '[{"name":"Combinado Tradicional","quantity":1,"productId":"p1"},{"name":"Gyoza","quantity":1,"productId":"p2"}]', 21.5, '2026-10-23 20:05:00+00', true),
  ('o2', '${A}', 'delivered', 'restaurant', 'Jyosmi Sushi', 'jyosmi-sushi-guarda', '[{"name":"Combinado Tradicional","quantity":1,"productId":"p1"}]', 15.0, '2026-10-30 20:10:00+00', true),
  ('o3', '${A}', 'delivered', 'restaurant', 'Jyosmi Sushi', 'jyosmi-sushi-guarda', '[{"name":"Combinado Tradicional","quantity":2,"productId":"p1"}]', 31.0, '2026-11-06 19:55:00+00', true),
  ('o4', '${A}', 'delivered', 'storeShopping', 'Continente', 'continente-guarda', '[{"name":"Leite"}]', 12.0, '2026-11-03 10:00:00+00', false),
  ('o5', '${A}', 'cancelled', 'restaurant', 'Jyosmi Sushi', 'jyosmi-sushi-guarda', '[]', 20.0, '2026-10-16 20:00:00+00', false),
  ('o6', '${B}', 'delivered', 'errand', 'Favor', null, '[]', 6.0, '2026-11-01 12:00:00+00', false);
insert into public.cleaning_bookings(client_user_id, status) values ('${A}', 'completed');
insert into public.home_banners(titulo, tipo_destino, destino, ordem) values
  ('Novidade: Bora Assistente', 'categoria', 'assistente', 1), ('5 € de boas-vindas', 'codigo', 'BEMVINDO', 2);
insert into public.home_banners(titulo, tipo_destino, destino, ordem, fim) values ('Promo velha', 'loja', 'x', 3, now() - interval '1 day');
insert into public.assistant_client_memory(user_id, kind, key, value) values ('${A}', 'restricao_alimentar', 'glúten', '{"text":"sem glúten"}');
insert into public.support_chatbot_sessions(id, user_id) values ('${S}', '${S}');
`);
// Aviso antigo com o link velho (tem de ser corrigido pela migração).
await db.exec(`insert into public.support_chatbot_messages(session_id, role, content) values ('${S}', 'user', 'falar com assistente')`);
const antes = await um(`select deep_link from public.admin_notifications order by created_at limit 1`);
ok(antes.deep_link === '/admin/support-escalations', 'antes da migração o aviso apontava para as escaladas', antes.deep_link);

// ─── Migrações, duas vezes ────────────────────────────────────────────────────
for (const volta of [1, 2]) {
  for (const m of migracoes) {
    const e = await erro(() => db.exec(readFileSync(m, 'utf8')));
    ok(e === null, `migração ${m.split(/[\\/]/).pop()} correu (volta ${volta})`, e ?? undefined);
  }
}

// ─── M4: Amigo Bora ───────────────────────────────────────────────────────────
const f = (await um(`select public.assistant_amigo_factos($1) f`, [A])).f;
ok(f.pedidos_entregues === 4, 'factos: 4 pedidos entregues (o cancelado não conta)', f.pedidos_entregues);
const h = f.habitos?.[0];
ok(h && h.dia === 5 && h.periodo === 'noite' && h.loja_id === 'jyosmi-sushi-guarda' && h.vezes === 3 && h.ultimo_pedido_id === 'o3',
  'factos: hábito "sexta à noite: Jyosmi" 3 vezes, último pedido o3', h);
ok(f.habitos.length === 1, 'factos: só um hábito (o Continente foi 1 vez)', f.habitos.length);
ok(f.recorrentes?.[0]?.nome === 'Combinado Tradicional' && f.recorrentes[0].vezes === 3, 'factos: artigo recorrente', f.recorrentes);
ok(f.lojas_favoritas?.[0]?.id === 'jyosmi-sushi-guarda', 'factos: loja favorita', f.lojas_favoritas?.[0]);
ok(f.categorias.restaurante === 3 && f.categorias.mercado === 1 && f.categorias.limpeza === 1, 'factos: categorias', f.categorias);
ok(Number(f.ticket_medio_eur) === 19.88, 'factos: ticket médio (21,5+15+31+12)/4', f.ticket_medio_eur);
ok(!JSON.stringify(f).match(/card|cart[aã]o|iban|stripe/i), 'factos: nada de pagamento');

const ctx = (await um(`select public.assistant_amigo_contexto($1) c`, [A])).c;
ok(ctx.ultimos_pedidos.length === 5 && ctx.ultimos_pedidos[0].pedido_id === 'o3', 'contexto: 5 últimos pedidos, o mais recente primeiro', ctx.ultimos_pedidos.map((x) => x.pedido_id));
ok(ctx.promocoes.length === 1 && ctx.promocoes[0].destino === 'BEMVINDO', 'contexto: só promoções ativas e nunca a faixa do assistente', ctx.promocoes);
ok(ctx.parceiros_novos.length === 1 && ctx.parceiros_novos[0].id === 'loja-nova', 'contexto: parceiro novo (o "em breve" fica fora)', ctx.parceiros_novos);

const faixa = await um(`select ativo from public.home_banners where destino = 'assistente'`);
ok(faixa.ativo === false, 'faixa permanente do assistente desligada');
ok(Number((await um(`select count(*) n from public.bkp_home_banners_assistente_20261108`)).n) === 1, 'cópia da faixa feita antes de mexer');
const sets = await q(`select key from public.platform_settings where key in ('assistant_personality_enabled','deixa_promocoes_enabled','assistant_amigo_model','assistant_amigo_welcome_text')`);
ok(sets.length === 4, 'definições novas criadas', sets.map((s) => s.key));
const robos = (await um(`select value from public.platform_settings where key = 'claude_robos'`)).value;
ok(robos['edge-amigo']?.modelo === 'claude-haiku-5-5' && robos['edge-assistente']?.modelo === 'claude-sonnet-5-5', 'claude_robos: edge-amigo (Haiku) junto, os outros intactos');
ok((await q(`select 1 from cron.job where jobname = 'amigo-bora-perfis'`)).length === 1, 'cron amigo-bora-perfis marcado');

// Perfil: a Edge grava como service_role; aqui simula-se o upsert.
await db.exec(`insert into public.assistant_client_profile(user_id, perfil) values ('${A}', '{"nome_tratamento":"Ana"}')`);
ok((await erro(() => q(`select public.admin_amigo_overview(30)`))) !== null, 'overview: recusa quem não é admin');
const ov = await como(ADM, true, async () => (await um(`select public.admin_amigo_overview(30) v`)).v);
ok(ov.perfis.total === 1 && ov.interruptores.assistant_personality_enabled === true, 'overview: admin vê perfis e interruptores', { perfis: ov.perfis, i: ov.interruptores.assistant_personality_enabled });
const semMotivo = await como(ADM, true, () => erro(() => q(`select public.admin_amigo_ver_perfil('ana@teste.pt', 'curto')`)));
ok(semMotivo && /motivo_obrigatorio/.test(semMotivo), 'ver perfil: sem motivo não abre', semMotivo);
const vp = await como(ADM, true, async () => (await um(`select public.admin_amigo_ver_perfil('ana@teste.pt', 'cliente pediu ajuda no suporte') v`)).v);
ok(vp.ok && vp.perfil.nome_tratamento === 'Ana' && vp.memorias === 1, 'ver perfil: abre com motivo', vp);
const aud = await um(`select details->>'motivo' m from public.admin_audit_log where action = 'amigo_ver_perfil'`);
ok(aud?.m === 'cliente pediu ajuda no suporte', 'ver perfil: fica na auditoria com o motivo');

await db.exec(`insert into public.assistant_deixas(user_id, chave, tipo, texto) values ('${A}', 'promo:x', 'promocao', 'Já viste?')`);
const dId = (await um(`select id from public.assistant_deixas limit 1`)).id;
const clicB = await como(B, false, async () => (await um(`select public.assistant_amigo_deixa_clicada($1) r`, [dId])).r);
ok(clicB.ok === false, 'deixa: outro cliente não marca a deixa de ninguém');
const clicA = await como(A, false, async () => (await um(`select public.assistant_amigo_deixa_clicada($1) r`, [dId])).r);
ok(clicA.ok === true, 'deixa: o próprio marca como clicada');

const esq = await como(A, false, async () => (await um(`select public.assistant_amigo_esquecer() r`)).r);
ok(esq.ok && esq.memorias_apagadas === 1, 'esquecer tudo: apaga as memórias', esq);
const p2 = await um(`select perfil, esquecido_em from public.assistant_client_profile where user_id = $1`, [A]);
ok(JSON.stringify(p2.perfil) === '{}' && p2.esquecido_em !== null, 'esquecer tudo: perfil vazio e data marcada');
ok((await um(`select user_id from public.assistant_deixas where id = $1`, [dId])).user_id === null, 'esquecer tudo: as métricas deixam de apontar para o cliente');
const f2 = (await um(`select public.assistant_amigo_factos($1) f`, [A])).f;
ok(f2.pedidos_entregues === 0 && f2.habitos.length === 0, 'depois de esquecer, os pedidos antigos já não contam', f2.pedidos_entregues);
await como(A, false, () => q(`select public.assistant_amigo_lembrar(false)`));
const ctx2 = (await um(`select public.assistant_amigo_contexto($1) c`, [A])).c;
ok(ctx2.lembrar === false && JSON.stringify(ctx2.perfil) === '{}' && ctx2.ultimos_pedidos.length === 0, 'não lembrar: o contexto não leva perfil nem pedidos');

// ─── Adendo 1: suporte ────────────────────────────────────────────────────────
const velho = await um(`select deep_link from public.admin_notifications where event_type = 'support_user_message' order by created_at limit 1`);
ok(velho.deep_link === `/admin/support/sessions/${S}`, 'aviso antigo corrigido para abrir a conversa', velho.deep_link);
ok(Number((await um(`select count(*) n from public.bkp_admin_notifications_suporte_20261108`)).n) >= 1, 'cópia dos avisos antigos feita');
await db.exec(`insert into public.support_chatbot_messages(session_id, role, content) values ('${S}', 'user', 'olá, alguém?')`);
const novo = await um(`select deep_link from public.admin_notifications where event_type = 'support_user_message' order by created_at desc limit 1`);
ok(novo.deep_link === `/admin/support/sessions/${S}`, 'aviso novo abre a conversa', novo.deep_link);
await db.exec(`insert into public.support_tickets(user_id, subject, session_id, status) values ('${S}', 'Pedido de atendimento humano', '${S}', 'open')`);
const tk = await um(`select deep_link from public.admin_notifications where event_type = 'support_ticket_new' order by created_at desc limit 1`);
ok(tk.deep_link === `/admin/support/sessions/${S}`, 'pedido de ajuda vindo do chat abre a conversa', tk.deep_link);
await db.exec(`insert into public.support_tickets(user_id, subject, status) values ('${S}', 'por email', 'open')`);
const tk2 = await um(`select deep_link from public.admin_notifications where event_type = 'support_ticket_new' order by created_at desc limit 1`);
ok(tk2.deep_link === '/admin/support', 'pedido de ajuda sem conversa continua na lista de pedidos', tk2.deep_link);

ok((await erro(() => q(`select * from public.admin_suporte_sessoes(50, false)`))) !== null, 'lista de conversas: recusa quem não é admin');
const lista = await como(ADM, true, () => q(`select * from public.admin_suporte_sessoes(50, false)`));
ok(lista.length === 1 && lista[0].nao_lida === true && lista[0].nome === 'S. Teste' && lista[0].ultima_msg === 'olá, alguém?', 'lista: todas as conversas (não escalada incluída), não lida', lista[0]);
const conv = await como(ADM, true, async () => (await um(`select public.admin_suporte_conversa($1) c`, [S])).c);
ok(conv.ok && conv.cliente.telefone === '961000000' && conv.cliente.email === 'said@teste.pt' && conv.mensagens.length === 2, 'conversa: cliente, telefone, email e mensagens', { tel: conv.cliente.telefone, n: conv.mensagens.length });
const lista2 = await como(ADM, true, () => q(`select * from public.admin_suporte_sessoes(50, true)`));
ok(lista2.length === 0, 'abrir a conversa marca como lida');
const resp = await como(ADM, true, async () => (await um(`select public.admin_suporte_responder($1, $2) r`, [S, 'Olá S., sou da equipa Bora. Em que posso ajudar?'])).r);
ok(resp.ok === true, 'responder como Equipa Bora', resp);
const sess = await um(`select mode, admin_assumiu_em from public.support_chatbot_sessions where id = $1`, [S]);
ok(sess.mode === 'admin' && sess.admin_assumiu_em !== null, 'ao responder, a sessão passa a modo admin (robô calado)', sess.mode);
const msgAdmin = await um(`select role, content from public.support_chatbot_messages where role = 'admin'`);
ok(msgAdmin?.content?.startsWith('Olá S.'), 'a mensagem fica com papel admin (o chat da app recebe pelo Realtime)');
ok((await q(`select 1 from public.notificacoes_cliente where kind = 'suporte_resposta' and user_id = $1`, [S])).length === 1, 'o cliente recebe aviso no sininho');
ok((await q(`select 1 from public.admin_notifications where summary is not null and created_at > now() - interval '1 second' and event_type = 'support_user_message' and payload->>'message' like 'Olá S.%'`)).length === 0, 'a resposta do admin não gera aviso ao admin');
ok((await erro(() => q(`select public.admin_suporte_responder($1, '   ')`, [S]))) !== null, 'responder: recusa quem não é admin');
const dev = await como(ADM, true, async () => (await um(`select public.admin_suporte_devolver($1) r`, [S])).r);
ok(dev.mudou === true && (await um(`select mode from public.support_chatbot_sessions where id = $1`, [S])).mode === 'ai', 'devolver ao robô volta a modo ai');
const ult = await um(`select ultima_msg_em from public.support_chatbot_sessions where id = $1`, [S]);
ok(ult.ultima_msg_em !== null, 'última mensagem guardada na sessão (ordena a lista)');

console.log(falhas === 0 ? '\nTUDO OK' : `\n${falhas} FALHA(S)`);
process.exit(falhas === 0 ? 0 : 1);
