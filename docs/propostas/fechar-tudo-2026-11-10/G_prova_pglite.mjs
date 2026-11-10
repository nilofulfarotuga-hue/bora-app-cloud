// Prova local (PGlite) do Bloco G da missão fechar-tudo-2026-11-10 — regras do check-in.
// Carrega as funções REAIS de produção (cópia de 10/11/2026, só leitura), aplica as 6 migrações
// do repo por ordem e corre os cenários R2, R3, R4, R5, R6, R8 e a migração de dados.
// Uso: bun prova_checkin_g.mjs <pasta com as funções .sql> <settings.json> <pasta das migrações>
import { PGlite } from '@electric-sql/pglite'
import fs from 'node:fs'
import path from 'node:path'

const [FN, SETTINGS, MIGS] = process.argv.slice(2)
const db = new PGlite()
const ok = []
const falhas = []
const check = (nome, cond, info) =>
  (cond ? ok : falhas).push(nome + (info !== undefined ? ' → ' + JSON.stringify(info) : ''))
const q = async (sql, p) => (await db.query(sql, p)).rows
const one = async (sql, p) => (await q(sql, p))[0]
const como = async (uid) => db.exec(`select set_config('t.uid', '${uid ?? ''}', false)`)

await db.exec(`
set check_function_bodies = off;
create role anon; create role authenticated; create role service_role;
create schema auth; create schema vault; create schema net;
create table auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('t.uid', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql as $$ select '{}'::jsonb $$;
create table vault.decrypted_secrets (name text, decrypted_secret text);
insert into vault.decrypted_secrets values ('project_url','https://x.supabase.co'),('service_role_key','k');
create table net.pedidos (id bigserial primary key, url text, body jsonb);
create function net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds int) returns bigint
  language sql as $$ insert into net.pedidos (url, body) values (url, body) returning id $$;
create table public.platform_settings (key text primary key, value jsonb, description text, category text,
  updated_at timestamptz, updated_by uuid, is_secret boolean default false);
create table public.users (id uuid primary key, name text, email text, role text, phone text, marketing_opt_in boolean);
create table public.user_roles (user_id uuid, role text);
create table public.restaurants (id text primary key, name text, photo_url text, cover_url text, hero_image_url text);
create table public.products (id text primary key, restaurant_id text, name text, photo_url text);
create table public.orders (id text primary key, user_id uuid, status text, payment_status text, price numeric,
  is_test_order boolean default false, restaurant_id text, created_at timestamptz default now());
create table public.order_status_events (order_id text, to_status text, actor_uid uuid, occurred_at timestamptz default now());
create table public.tvde_rides (id bigserial, client_id uuid, status text, created_at timestamptz default now());
create table public.cleaning_bookings (id bigserial, client_user_id uuid, status text, cleaner_id uuid,
  payment_method text, payment_status text, completed_at timestamptz, scheduled_at timestamptz, is_test_order boolean);
create table public.client_push_tokens (user_id uuid, active boolean);
create table public.e2e_log (id bigserial, fluxo text, passo text, estado text, detalhe text, device text, run_id text);
create table public.admin_notifications (id uuid default gen_random_uuid(), created_at timestamptz default now(),
  event_type text, severity text, entity_type text, entity_id text, summary text, payload jsonb default '{}', deep_link text);
create table public.bora_tokens (user_id uuid, role text, amount int, expires_at timestamptz, source_order_id text);
create function public.get_user_tokens(p_user_id uuid) returns int language sql as $$ select coalesce(sum(amount),0)::int from public.bora_tokens where user_id = p_user_id $$;
create function public.is_demo_email(e text) returns boolean language sql as $$ select false $$;
create function public._push_in_app_notification(a uuid, b text, c text, d text, e text) returns void language sql as $$ select $$;
create function public.is_admin() returns boolean language sql as $$ select current_setting('t.admin', true) = 'sim' $$;
create function public.log_admin_action(a text, b text, c text, d jsonb) returns void language sql as $$ select $$;
create table public.daily_checkins (id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id),
  checkin_date date, streak_day smallint check (streak_day between 1 and 7), tokens_awarded int default 0 check (tokens_awarded >= 0),
  created_at timestamptz default now(), constraint daily_checkins_um_por_dia unique (user_id, checkin_date));
create table public.checkin_escada (user_id uuid primary key references auth.users(id), guardado_chave text, guardado_dia smallint,
  guardado_titulo text, guardado_tipo text, guardado_marco jsonb, guardado_ciclo_inicio date, guardado_em timestamptz,
  garantido_ate timestamptz, decisao text default 'pendente' check (decisao in ('pendente','continuar')), reinicio_data date,
  levantados int default 0, ultimo_vale_id uuid, ultimo_levantado_em timestamptz, criado_em timestamptz default now(),
  atualizado_em timestamptz default now());
create table public.checkin_premios_vales (id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id),
  marco smallint check (marco between 1 and 365), marco_chave text, tipo text check (tipo in ('produto','servico','desconto')),
  ciclo_inicio date, estado text default 'por_usar' check (estado in ('por_usar','reservado','usado','expirado','anulado','guardado','a_espera_pedido')),
  titulo text, loja_id text, produto_id text, quantidade int default 1, opcoes text[] default '{}', opcao text,
  valor_cents int default 0, custo_cents int default 0 check (custo_cents >= 0), emitido_em timestamptz default now(),
  ativado_em timestamptz, valido_ate timestamptz, ativar_em date, esperar_ate timestamptz, reservado_ate timestamptz,
  usado_em timestamptz, pedido_id text, marcacao_tipo text, marcacao_id uuid, pago_loja_em timestamptz, pago_loja_por uuid,
  pago_loja_nota text, anulado_em timestamptz, anulado_por uuid, motivo text, origem text default 'checkin', criado_por uuid,
  visto_em timestamptz, atualizado_em timestamptz default now(), minimo_cents int);
create unique index checkin_premios_vales_um_por_ciclo on public.checkin_premios_vales (user_id, marco_chave, ciclo_inicio) where (origem = 'checkin');
create table public.checkin_lembretes_envios (id bigserial primary key, user_id uuid references auth.users(id), dia date,
  turno text, dia_sequencia smallint, tokens int, pedido_http bigint, enviado_em timestamptz default now(),
  constraint checkin_lembretes_envios_turno_check check (turno in ('manha','noite')),
  constraint checkin_lembretes_um_por_turno unique (user_id, dia, turno));
`)

// definições de produção (checkin_*) e funções reais
const st = JSON.parse(fs.readFileSync(SETTINGS, 'utf8'))
const settings = (st.rows || st)[0].j.settings
for (const s of settings) {
  await db.query('insert into public.platform_settings (key, value) values ($1, $2::jsonb) on conflict (key) do nothing',
    [s.key, JSON.stringify(s.value)])
}
await db.exec((st.rows || st)[0].j.is_demo + ';')
const fns = fs.readdirSync(FN).filter((f) => f.endsWith('.sql'))
for (const f of fns) {
  try { await db.exec(fs.readFileSync(path.join(FN, f), 'utf8') + ';') } catch (e) { falhas.push('carregar ' + f + ': ' + e.message) }
}
await db.exec(`create trigger trg_checkin_marcos_apos_checkin after insert on public.daily_checkins
  for each row execute function public._checkin_marcos_apos_checkin();`)

// ── estado ANTES das migrações (para a migração de dados) ──
const hoje = (await one(`select (now() at time zone 'Europe/Lisbon')::date::text d`)).d
const U = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
async function pessoa(n, { pedido = false, nome = 'P' + n } = {}) {
  const id = U(n)
  await db.query(`insert into auth.users (id, email) values ($1, $2)`, [id, `p${n}@teste.pt`])
  await db.query(`insert into public.users (id, name, email, role, phone) values ($1, $2, $3, 'client', '912345678')`, [id, nome, `p${n}@teste.pt`])
  await db.query(`insert into public.client_push_tokens values ($1, true)`, [id])
  if (pedido) await pedidoPago(id, 'sabores-brasil-guarda')
  return id
}
let nPed = 0
async function pedidoPago(uid, loja) {
  const oid = 'o' + ++nPed
  await db.query(`insert into public.orders (id, user_id, status, payment_status, price, restaurant_id) values ($1,$2,'delivered','paid',12,$3)`, [oid, uid, loja])
  await db.query(`insert into public.order_status_events (order_id, to_status, actor_uid) values ($1,'delivered', null)`, [oid])
}
// dias seguidos de check-in a acabar em `ate` (0 = hoje, 1 = ontem…), inseridos sem passar pela função
async function dias(uid, n, ate = 0, hora = null) {
  for (let k = n - 1 + ate; k >= ate; k--) {
    await db.query(`insert into public.daily_checkins (user_id, checkin_date, streak_day, tokens_awarded, created_at)
      values ($1, $2::date - $3::int, 1, 0, coalesce($4::timestamptz, now()))`, [uid, hoje, k, hora])
  }
}
await db.exec(`insert into public.restaurants values
  ('sabores-brasil-guarda','Sabores do Brasil','https://f/loja-keli.jpg',null,null),
  ('goola-acai-guarda','Goola Açaí','https://f/loja-goola.jpg',null,null),
  ('leonidas-guarda','Leonidas','https://f/loja-leo.jpg',null,null),
  ('burgerking-guarda','Burger King','https://f/loja-bk.jpg',null,null),
  ('continente-guarda','Continente','https://f/loja-continente.jpg',null,null);
  insert into public.products values ('premio-checkin-salgados','sabores-brasil-guarda','2 salgados','https://f/salgados.jpg'),
  ('premio-checkin-acai','goola-acai-guarda','Açaí','https://f/acai.jpg'),
  ('premio-checkin-leonidas-barra','leonidas-guarda','Barra',null);`)

// vale antigo por usar SEM pedido e outro COM pedido (casos que existem em produção a 10/11)
const vSem = await pessoa(901)
const vCom = await pessoa(902, { pedido: true })
await db.query(`insert into public.checkin_premios_vales (user_id, marco, marco_chave, tipo, ciclo_inicio, estado, titulo, custo_cents, ativado_em, valido_ate)
  values ($1, 8, 'leonidas_barra', 'produto', current_date - 8, 'por_usar', 'barra', 243, now() - interval '5 days', now() + interval '25 days'),
         ($2, 8, 'leonidas_barra', 'produto', current_date - 8, 'por_usar', 'barra', 243, now() - interval '5 days', now() + interval '25 days')`, [vSem, vCom])

// ── aplicar as 6 migrações por ordem ──
const migs = fs.readdirSync(MIGS).filter((f) => /^20261110200[0-5]00_checkin_g_/.test(f)).sort()
check('6 migrações encontradas', migs.length === 6, migs)
for (const f of migs) {
  try { await db.exec(fs.readFileSync(path.join(MIGS, f), 'utf8')) } catch (e) { falhas.push('aplicar ' + f + ': ' + e.message) }
}

// migração de dados
const mSem = await one(`select estado, esperar_ate > now() + interval '24 days' longo from public.checkin_premios_vales where user_id = $1`, [vSem])
const mCom = await one(`select estado from public.checkin_premios_vales where user_id = $1`, [vCom])
check('DADOS: vale por usar sem pedido passa a esperar pelo pedido', mSem.estado === 'a_espera_pedido', mSem)
check('DADOS: prazo da espera nunca menor que o que tinha', mSem.longo === true)
check('DADOS: vale com pedido fica por usar', mCom.estado === 'por_usar', mCom)
check('DADOS: backups criados', (await one(`select (select count(*) from public.bkp_checkin_premios_vales_20261110)::int n`)).n === 2)

// ── R2: todo o prémio espera um pedido pago; desbloqueia sozinho ──
const a = await pessoa(1)                       // sem pedido
await dias(a, 7, 1)                             // 7 dias até ontem
await como(a)
const r1 = await one(`select public.client_daily_checkin() r`)   // hoje = dia 8 → barra Leonidas guardada
const e1 = (await one(`select public._checkin_estado_marcos($1) e`, [a])).e
check('R2: chega ao dia 8 com a barra guardada', e1.escada.guardado?.chave === 'leonidas_barra', e1.escada.guardado)
check('R2: estado diz que precisa de pedido', e1.precisa_pedido === true)
const lev = (await one(`select public.client_checkin_escada_levantar() r`)).r
check('R2: "Quero este" sem pedido dá vale à espera', lev.ok === true && lev.vale?.estado === 'a_espera_pedido', lev.vale?.estado)
await db.exec(`insert into public.tvde_rides (client_id, status) values ('${a}', 'finalizada')`)
await one(`select public.checkin_premios_manutencao()`)
check('R2: corrida TVDE não desbloqueia (interruptor desligado)',
  (await one(`select estado from public.checkin_premios_vales where user_id = $1`, [a])).estado === 'a_espera_pedido')
await db.exec(`update public.platform_settings set value = 'true' where key = 'checkin_pedido_conta_tvde'`)
check('R2: com o interruptor TVDE ligado a corrida conta', (await one(`select public._checkin_teve_pedido_pago($1, 30) t`, [a])).t === true)
await db.exec(`update public.platform_settings set value = 'false' where key = 'checkin_pedido_conta_tvde'`)
await pedidoPago(a, 'leonidas-guarda')
const man = (await one(`select public.checkin_premios_manutencao() r`)).r
check('R2: depois de comprar, desbloqueia sozinho', (await one(`select estado from public.checkin_premios_vales where user_id = $1`, [a])).estado === 'por_usar', man)

// ── R3: "Quero este" recomeça só a escada; a semana de tokens continua ──
const b = await pessoa(2, { pedido: true })
await dias(b, 13, 1)                            // 13 dias até ontem; a semana de tokens: dias 1..7,1..6
await db.exec(`update public.daily_checkins d set streak_day = s.sd from (
  select id, ((row_number() over (order by checkin_date) - 1) % 7) + 1 sd from public.daily_checkins where user_id = '${b}') s where s.id = d.id`)
await como(b)
await one(`select public.client_daily_checkin()`)    // hoje = dia 14 → salgados (o mais valioso a que chegou)
const lb = (await one(`select public.client_checkin_escada_levantar() r`)).r
check('R3: "Quero este" com pedido dá vale por usar', lb.ok === true && lb.vale?.estado === 'por_usar', lb.reason)
const eb = (await one(`select public._checkin_estado_marcos($1) e`, [b])).e
check('R3: a escada volta ao início (0 hoje, amanhã dia 1)', eb.dia_marco === 0, eb.dia_marco)
const sb = (await one(`select public._checkin_estado($1) e`, [b])).e
check('R3: a semana de tokens NÃO recomeça (amanhã é o dia 1 da semana só se hoje foi o 7)', sb.next_day === (sb.streak_day >= 7 ? 1 : sb.streak_day + 1), sb)
await db.exec(`update public.platform_settings set value = 'true' where key = 'checkin_quero_este_recomeca_semana'`)
const sb2 = (await one(`select public._checkin_estado($1) e`, [b])).e
check('R3: com o interruptor ligado, a semana também volta ao Dia 1', sb2.next_day === 1, sb2.next_day)
await db.exec(`update public.platform_settings set value = 'false' where key = 'checkin_quero_este_recomeca_semana'`)
check('R3: dias seguidos de check-in continuam a contar (sequência real intacta)',
  (await one(`select dias from public._checkin_sequencia($1, $2::date)`, [b, hoje])).dias === 14)

// ── R4: a melhor sugestão ──
const c = await pessoa(3)
await pedidoPago(c, 'goola-acai-guarda'); await pedidoPago(c, 'goola-acai-guarda')
const s19 = (await one(`select public._checkin_sugestao($1, 19) s`, [c])).s
check('R4: no dia 19 sugere o mais valioso (açaí 9,22)', s19?.chave === 'acai', s19?.chave)
const s14 = (await one(`select public._checkin_sugestao($1, 14) s`, [c])).s
check('R4: no dia 14 sugere os salgados (6,30)', s14?.chave === 'salgados', s14?.chave)
// empate de valor: o da loja onde mais pediu
await db.exec(`update public.platform_settings set value = jsonb_set(value, '{valor_cents}', '922') where key = 'checkin_marco_salgados'`)
const sEmp = (await one(`select public._checkin_sugestao($1, 19) s`, [c])).s
check('R4: entre iguais, a loja onde mais pediu (Goola, 2 pedidos)', sEmp?.chave === 'acai', sEmp?.chave)
await pedidoPago(c, 'sabores-brasil-guarda'); await pedidoPago(c, 'sabores-brasil-guarda'); await pedidoPago(c, 'sabores-brasil-guarda')
const sEmp2 = (await one(`select public._checkin_sugestao($1, 19) s`, [c])).s
check('R4: com mais pedidos na Keli, entre iguais passa aos salgados', sEmp2?.chave === 'salgados', sEmp2?.chave)
await db.exec(`update public.platform_settings set value = jsonb_set(value, '{valor_cents}', '630') where key = 'checkin_marco_salgados'`)
check('R4: o serviço do dia 30 (sem valor) conta como o maior', (await one(`select public._checkin_sugestao($1, 30) s`, [c])).s?.chave === 'mes')
// a escada guarda a sugestão
await dias(c, 14, 1)
await como(c)
await one(`select public.client_daily_checkin()`)    // dia 15: sem degrau novo ativo (desconto desligado)
const ec = (await one(`select public._checkin_estado_marcos($1) e`, [c])).e
check('R4: o estado traz uma sugestão só, com foto e valor', ec.sugestao?.chave === 'salgados' && ec.sugestao?.valor_cents === 630 && !!ec.sugestao?.foto_url, ec.sugestao)
check('R4: marcos trazem valor em euros e foto real (produto; loja quando não há)',
  ec.marcos.find((m) => m.chave === 'acai')?.foto_url === 'https://f/acai.jpg' &&
  ec.marcos.find((m) => m.chave === 'leonidas_barra')?.foto_url === 'https://f/loja-leo.jpg' &&
  ec.marcos.find((m) => m.chave === 'acai')?.valor_cents === 922)

// ── R5: perdão, 1 por mês, só com compra ──
const d = await pessoa(4, { pedido: true })
await dias(d, 6, 2)                              // 6 dias até anteontem; ontem falhou
const ed0 = (await one(`select public._checkin_estado_marcos($1) e`, [d])).e
check('R5: antes do check-in, o perdão aparece pendente e a sequência segura', ed0.perdao.pendente === true && ed0.dias_seguidos === 7, { p: ed0.perdao, d: ed0.dias_seguidos })
await como(d)
await one(`select public.client_daily_checkin()`)
const pd = await one(`select count(*)::int n from public.checkin_perdoes where user_id = $1`, [d])
check('R5: com pedido, o dia falhado é perdoado sozinho', pd.n === 1)
const ed = (await one(`select public._checkin_estado_marcos($1) e`, [d])).e
check('R5: a sequência continua (dia 8, com o dia 7 perdoado)', ed.dia_marco === 8 && ed.perdao.dias.includes(7), { dia: ed.dia_marco, dias: ed.perdao.dias })
check('R5: a escada não perde o degrau por causa do perdão (barra guardada no dia 8)', ed.escada.guardado?.chave === 'leonidas_barra')
check('R5: aviso "Usámos o teu perdão" por ver', !!ed.perdao.aviso_dia)
await one(`select public.client_checkin_perdao_visto()`)
check('R5: depois de visto, o aviso some', !(await one(`select public._checkin_estado_marcos($1) e`, [d])).e.perdao.aviso_dia)
check('R5: só 1 por mês', (await one(`select public._checkin_perdao_pode($1, $2::date - 1) p`, [d, hoje])).p === false)
// segundo perdão no mesmo mês: não
const d2 = await pessoa(5, { pedido: true })
await db.query(`insert into public.checkin_perdoes (user_id, dia, mes) values ($1, $2::date - 8, date_trunc('month', $2::date - 8)::date)`, [d2, hoje])
await dias(d2, 4, 2)
await como(d2)
await one(`select public.client_daily_checkin()`)
const mesmoMes = (await one(`select date_trunc('month', $1::date - 8) = date_trunc('month', $1::date - 1) m`, [hoje])).m
check('R5: segundo dia falhado no mesmo mês não é perdoado',
  (await one(`select count(*)::int n from public.checkin_perdoes where user_id = $1`, [d2])).n === (mesmoMes ? 1 : 2), { mesmoMes })
// sem compra não há perdão
const e5 = await pessoa(6)
await dias(e5, 5, 2)
await como(e5)
await one(`select public.client_daily_checkin()`)
check('R5: sem compra não há perdão', (await one(`select count(*)::int n from public.checkin_perdoes where user_id = $1`, [e5])).n === 0)
check('R5: sem compra a sequência recomeça', (await one(`select public._checkin_estado_marcos($1) e`, [e5])).e.dia_marco === 1)

// ── R6: teto de custo mensal + aviso dos 80% ──
await db.exec(`update public.platform_settings set value = '1000' where key = 'checkin_premios_tecto_custo_cents'`)
const custoAgora = (await one(`select public._checkin_custo_mes_cents(null) c`)).c
const f = await pessoa(7, { pedido: true })
await como(f)
const vf = (await one(`select public._checkin_vale_emitir($1, (select value || jsonb_build_object('chave','acai') from public.platform_settings where key='checkin_marco_acai'), current_date) v`, [f])).v
const ef = (await one(`select estado, ativar_em from public.checkin_premios_vales where id = $1`, [vf]))
check('R6: passando o teto, o prémio fica guardado para o mês seguinte', ef.estado === (custoAgora + 790 > 1000 ? 'guardado' : 'por_usar'), { custoAgora, ef })
await db.exec(`update public.platform_settings set value = '1200' where key = 'checkin_premios_tecto_custo_cents'`)
const custo2 = (await one(`select public._checkin_custo_mes_cents(null) c`)).c
await one(`select public.checkin_premios_manutencao()`)
const avisos = (await one(`select count(*)::int n from public.admin_notifications where event_type = 'checkin_tecto_aviso'`)).n
check('R6: aviso no painel aos 80% (uma vez por mês)', avisos === (custo2 * 100 >= 1200 * 80 ? 1 : 0), { custo2, avisos })
await one(`select public.checkin_premios_manutencao()`)
check('R6: o aviso não se repete no mesmo mês', (await one(`select count(*)::int n from public.admin_notifications where event_type = 'checkin_tecto_aviso'`)).n === avisos)
await db.exec(`select set_config('t.admin', 'sim', false)`)
const res = (await one(`select public.admin_checkin_regras_resumo() r`)).r
check('R6: o resumo do painel traz custo, teto, % e aviso', res.tecto_cents === 1200 && res.custo_mes_cents === custo2 && typeof res.aviso === 'boolean', { c: res.custo_mes_cents, p: res.pct_usado, a: res.aviso })
check('PAINEL: interruptores R2-R8 com explicação', Object.keys(res.definicoes).length >= 12 && !!res.definicoes.checkin_perdao_ativo?.descricao)
check('PAINEL: escada com foto, valor e custo', res.degraus.some((g) => g.chave === 'acai' && g.custo_cents === 790 && g.foto_url))
check('PAINEL: quem está em que dia', Array.isArray(res.por_dia) && res.por_dia.length > 0, res.por_dia)
const def = (await one(`select public.admin_checkin_regra_definir('checkin_perdao_por_mes', '2'::jsonb) r`)).r
check('PAINEL: muda uma regra', def.ok === true)
let erro = null
try { await one(`select public.admin_checkin_regra_definir('checkin_rewards', '[1,1,1,1,1,1,1]'::jsonb)`) } catch (e) { erro = e.message }
check('PAINEL: não deixa mudar o que não é regra do check-in (tokens da semana)', /chave_nao_e_regra/.test(erro || ''), erro)
erro = null
try { await one(`select public.admin_checkin_degrau_editar('desconto_continente_3', '{"ativo": true}'::jsonb)`) } catch (e) { erro = e.message }
check('PAINEL/R7: degrau de desconto não se liga', /desconto_fica_desligado/.test(erro || ''), erro)
const ed2 = (await one(`select public.admin_checkin_degrau_editar('acai', '{"custo_cents": 800, "foto_url": "https://f/acai2.jpg"}'::jsonb) r`)).r
check('PAINEL: edita custo e foto do degrau', ed2.foto_url === 'https://f/acai2.jpg' && Number(ed2.custo_cents) === 800, ed2)
await db.exec(`select set_config('t.admin', '', false)`)
erro = null
try { await one(`select public.admin_checkin_regras_resumo()`) } catch (e) { erro = e.message }
check('PAINEL: sem ser admin, recusa', /admin_required/.test(erro || ''), erro)

// ── R8: lembrete à hora habitual, máx. 1 por dia, pára depois de 3 falhas ──
await db.exec(`update public.platform_settings set value = '0' where key = 'checkin_marco_ativo'`)
const hora = new Date().toISOString()
const l0 = await pessoa(10); await dias(l0, 3, 1, hora)        // fez ontem
const l2 = await pessoa(11); await dias(l2, 3, 3, hora)        // falhou 2 dias
const l3 = await pessoa(12); await dias(l3, 3, 4, hora)        // falhou 3 dias → pára
const lOff = await pessoa(13); await dias(lOff, 3, 1, hora)    // desligou o lembrete
const lHoje = await pessoa(14); await dias(lHoje, 3, 0, hora)  // já fez hoje
await como(lOff)
await one(`select public.client_checkin_lembrete_definir(false)`)
const p1 = (await one(`select public.checkin_lembretes_processar() r`)).r
const env = (await q(`select user_id::text u, turno from public.checkin_lembretes_envios where dia = $1::date`, [hoje])).map((x) => x.u)
check('R8: envia a quem fez ontem', env.includes(l0), p1)
check('R8: envia a quem falhou 2 dias', env.includes(l2))
check('R8: pára depois de falhar 3 dias seguidos', !env.includes(l3))
check('R8: quem desligou não recebe', !env.includes(lOff))
check('R8: quem já fez hoje não recebe', !env.includes(lHoje))
const p2 = (await one(`select public.checkin_lembretes_processar() r`)).r
check('R8: no máximo 1 por dia', p2.pessoas === 0, p2)
const textos = (await q(`select body->>'body' t from net.pedidos where url like '%push-clientes-alvo%' order by id`)).map((x) => x.t)
check('R8: textos sem culpa nem urgência', textos.every((t) => !/perder|perdes|última|urgente/i.test(t)), textos)
await db.exec(`update public.platform_settings set value = '1' where key = 'checkin_lembrete_max_falhas'`)
const l1b = await pessoa(15); await dias(l1b, 3, 2, hora)
await one(`select public.checkin_lembretes_processar()`)
check('R8: com 1 falha máxima é a regra de 18/10 (falhou ontem → não recebe)',
  (await one(`select count(*)::int n from public.checkin_lembretes_envios where user_id = $1`, [l1b])).n === 0)

// ── fechadas a anónimos ──
const fechadas = ['_checkin_sugestao(uuid,integer)', '_checkin_perdao_pode(uuid,date)', '_checkin_custo_mes_cents(uuid)',
  'admin_checkin_regras_resumo()', 'admin_checkin_regra_definir(text,jsonb)', 'admin_checkin_degrau_editar(text,jsonb)',
  'client_checkin_perdao_visto()', 'client_checkin_lembrete_definir(boolean)', '_checkin_estado_marcos(uuid)']
for (const fn of fechadas) {
  const r = await one(`select has_function_privilege('anon', 'public.${fn}', 'execute') a`)
  check('anon não executa ' + fn, r.a === false)
}
check('authenticated executa client_checkin_lembrete_definir',
  (await one(`select has_function_privilege('authenticated', 'public.client_checkin_lembrete_definir(boolean)', 'execute') a`)).a === true)

console.log('\nOK (' + ok.length + '):\n  ' + ok.join('\n  '))
console.log('\nFALHAS (' + falhas.length + '):\n  ' + falhas.join('\n  '))
process.exit(falhas.length ? 1 : 0)
