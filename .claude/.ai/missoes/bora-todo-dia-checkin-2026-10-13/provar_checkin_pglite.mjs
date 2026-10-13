// Prova do check-in diário num Postgres LOCAL (PGlite) com uma base FALSA mínima.
// Corre a migração da base (20261013060000_checkin_diario_base.sql) e a proposta de
// crédito (proposta-credito-checkin.md) e verifica as regras do Danilo de 13/10/2026.
// As tabelas de que o SQL depende são criadas aqui com o mesmo nome e forma (incluindo
// o índice único real de bora_tokens); rede, segredos e pg_cron são dublês. Nada toca a produção.
// Uso: bun provar_checkin_pglite.mjs <pasta com node_modules/@electric-sql/pglite> <migração.sql> <proposta.md>
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const [, , pgliteDir, migracao, proposta] = process.argv
const { PGlite } = await import(pathToFileURL(`${pgliteDir}/node_modules/@electric-sql/pglite/dist/index.js`).href)
const db = new PGlite()
const sqlBase = readFileSync(migracao, 'utf8')
const sqlCredito = (readFileSync(proposta, 'utf8').replace(/\r\n/g, '\n').match(/```sql\n([\s\S]*?)```/) ?? [])[1]
if (!sqlCredito) throw new Error('bloco ```sql não encontrado na proposta')

let falhas = 0, total = 0
const ok = (cond, msg) => { total++; console.log(`${cond ? 'OK    ' : 'FALHOU'} ${msg}`); if (!cond) falhas++ }
const q = async (s, p) => (await db.query(s, p)).rows
const one = async (s, p) => (await q(s, p))[0]
const como = async (uid) => db.query(`SELECT set_config('app.uid', $1, false)`, [uid ?? ''])
const comoAdmin = async (sim) => db.query(`SELECT set_config('app.admin', $1, false)`, [sim ? '1' : '0'])
const set = async (k, v) => db.query(`UPDATE public.platform_settings SET value = $2::jsonb WHERE key = $1`, [k, JSON.stringify(v)])

// ---- base falsa -----------------------------------------------------------
await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth; CREATE SCHEMA net; CREATE SCHEMA vault; CREATE SCHEMA cron;
CREATE TABLE auth.users(id uuid primary key, email text);
CREATE TABLE public.users(id uuid primary key, name text, email text, phone text, role text, marketing_opt_in boolean not null default false);
CREATE TABLE public.user_roles(user_id uuid, role text, created_at timestamptz default now());
CREATE TABLE public.client_push_tokens(id uuid primary key default gen_random_uuid(), user_id uuid, fcm_token text, active boolean);
CREATE TABLE public.platform_settings(key text primary key, value jsonb, description text, category text,
  updated_at timestamptz, updated_by uuid, is_secret boolean default false);
INSERT INTO public.platform_settings(key, value) VALUES ('token_value_cents_x100', '50');
CREATE TABLE public.bora_tokens(id uuid primary key default gen_random_uuid(), user_id uuid not null, role text not null,
  amount integer not null, created_at timestamptz default now(), expires_at timestamptz not null,
  source_order_id text, is_used boolean default false, used_at timestamptz);
CREATE UNIQUE INDEX idx_bora_tokens_order_role ON public.bora_tokens (source_order_id, role) WHERE source_order_id IS NOT NULL;
CREATE TABLE public.net_calls(id serial, url text, body jsonb);
CREATE TABLE vault.decrypted_secrets(name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES ('service_role_key','sk-falsa'),('project_url','https://falso.local');
CREATE TABLE cron.job(jobid bigserial primary key, jobname text, schedule text, command text);
CREATE FUNCTION cron.schedule(n text, s text, c text) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job(jobname, schedule, command) VALUES (n, s, c) RETURNING jobid $$;
CREATE FUNCTION cron.unschedule(id bigint) RETURNS boolean LANGUAGE sql AS $$ DELETE FROM cron.job WHERE jobid = id RETURNING true $$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.uid', true), '')::uuid $$;
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('app.admin', true) = '1', false) $$;
CREATE FUNCTION public.get_user_tokens(p_user_id uuid) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(amount), 0)::INTEGER FROM bora_tokens WHERE user_id = p_user_id AND is_used = FALSE AND expires_at > now() $$;
CREATE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000) RETURNS bigint LANGUAGE plpgsql AS $$
  DECLARE v bigint; BEGIN INSERT INTO public.net_calls(url, body) VALUES (url, body) RETURNING id INTO v; RETURN v; END $$;
`)

// pessoas
const U = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const pessoas = [
  // n, nome, telefone, users.role, linha em user_roles, aparelho ativo
  [1, 'Cliente Um', '912345678', 'client', false, true],
  [2, 'Cliente Dois', '+351 913 000 000', 'driver', true, true],      // cliente só por user_roles
  [3, 'Cliente Tres', '00351914000000', 'client', false, false],
  [4, 'Cliente Quatro', '351915000000', 'client', false, false],
  [5, 'Cliente Cinco', '(916) 000-000', 'client', false, false],
  [6, 'Sem Telemovel', '', 'client', false, true],
  [7, 'Cliente Sete', '917000000', 'client', false, false],
  [8, 'Cliente Oito', '918000000', 'client', false, false],
  [9, 'Nunca Fez', '919000000', 'client', false, true],
  [10, 'Ontem Dia Tres', '920000000', 'client', false, true],         // 920… não é telemóvel? é: 92x existe
  [11, 'Aparelho Desligado', '921000000', 'client', false, false],
  [12, 'Fixo Lisboa', '212345678', 'client', false, true],
  [13, 'So Estafeta', '922000000', 'driver', false, true],
]
for (const [n, nome, tel, role, ur, push] of pessoas) {
  await q(`INSERT INTO auth.users(id, email) VALUES ($1, $2)`, [U(n), `p${n}@teste.local`])
  await q(`INSERT INTO public.users(id, name, email, phone, role) VALUES ($1,$2,$3,$4,$5)`, [U(n), nome, `p${n}@teste.local`, tel, role])
  if (ur) await q(`INSERT INTO public.user_roles(user_id, role) VALUES ($1, 'client')`, [U(n)])
  await q(`INSERT INTO public.client_push_tokens(user_id, fcm_token, active) VALUES ($1, $2, $3)`, [U(n), `tok-${n}`, push])
}

// ---- 1. migração da base ---------------------------------------------------
try { await db.exec(sqlBase); ok(true, 'migração da base corre sem erro (tabelas, definições, funções, cron)') }
catch (e) { ok(false, `migração da base: ${e.message}`); process.exit(1) }
try { await db.exec(sqlBase); ok(true, 'migração da base corre segunda vez sem erro (idempotente)') }
catch (e) { ok(false, `segunda corrida da migração: ${e.message}`) }
ok((await q(`SELECT 1 FROM cron.job WHERE jobname = 'checkin-lembretes'`)).length === 1, 'tarefa checkin-lembretes agendada uma vez só')
ok((await q(`SELECT 1 FROM platform_settings WHERE key IN ('checkin_rewards','checkin_token_expiry_days')`)).length === 0,
  'a base não grava valores em tokens (vão com a proposta do crédito)')
ok(JSON.stringify((await one(`SELECT public._checkin_premios() AS p`)).p) === '[5,5,10,10,15,15,40]', 'sem a definição, os prémios são os do Danilo: 5,5,10,10,15,15,40')

const hoje = (await one(`SELECT (now() AT TIME ZONE 'Europe/Lisbon')::date::text AS d`)).d
const diaMenos = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Europe/Lisbon')::date - $1::int)::text AS d`, [n])).d
const historico = async (n, dias, dia) => q(`INSERT INTO public.daily_checkins(user_id, checkin_date, streak_day, tokens_awarded) VALUES ($1, $2::date, $3, 0)`, [U(n), await diaMenos(dias), dia])
const status = async (n) => { await como(U(n)); return (await one(`SELECT public.client_checkin_status() AS s`)).s }
const checkin = async (n) => { await como(U(n)); return (await one(`SELECT public.client_daily_checkin() AS r`)).r }
const tokensDe = async (n) => q(`SELECT amount, source_order_id, extract(epoch FROM (expires_at - now()))/86400 AS dias FROM bora_tokens WHERE user_id = $1 ORDER BY created_at`, [U(n)])

// ---- 2. antes do crédito existir: tudo desligado ----------------------------
let s = await status(1)
ok(s.enabled === false && s.reason === 'desligado', `sem a função de crédito o check-in está desligado (enabled=${s.enabled}, reason=${s.reason})`)
await comoAdmin(false)
let lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
ok(lem.motivo === 'desligado', 'sem a função de crédito não sai nenhum lembrete')

// ---- 3. funções puras --------------------------------------------------------
const casos = [
  [null, null, 1, 'sem histórico → Dia 1'],
  ['ontem', 1, 2, 'ontem Dia 1 → Dia 2'],
  ['ontem', 6, 7, 'ontem Dia 6 → Dia 7'],
  ['ontem', 7, 1, 'ontem Dia 7 → ciclo novo, Dia 1'],
  ['anteontem', 4, 1, 'falhou ontem → volta ao Dia 1'],
]
for (const [quando, dia, esperado, txt] of casos) {
  const d = quando === null ? null : await diaMenos(quando === 'ontem' ? 1 : 2)
  const r = (await one(`SELECT public._checkin_dia_de_hoje($1::date, $2::int, $3::date) AS d`, [d, dia, hoje])).d
  ok(r === esperado, `_checkin_dia_de_hoje: ${txt} (deu ${r})`)
}
const tel = async (n) => (await one(`SELECT public._checkin_telemovel_confirmado($1) AS t`, [U(n)])).t
ok(await tel(1), 'telemóvel 912345678 conta como confirmado')
ok(await tel(2), 'telemóvel "+351 913 000 000" conta como confirmado')
ok(await tel(3), 'telemóvel 00351914000000 conta como confirmado')
ok(await tel(4), 'telemóvel 351915000000 conta como confirmado')
ok(await tel(5), 'telemóvel "(916) 000-000" conta como confirmado')
ok(!(await tel(6)), 'telemóvel vazio NÃO conta')
ok(!(await tel(12)), 'número fixo 212345678 NÃO conta')

// ---- 4. aplicar a proposta de crédito ---------------------------------------
try { await db.exec(sqlCredito); ok(true, 'proposta de crédito criada sem erro') }
catch (e) { ok(false, `proposta de crédito: ${e.message}`); process.exit(1) }
ok(JSON.stringify((await one(`SELECT value FROM platform_settings WHERE key='checkin_rewards'`)).value) === '[5,5,10,10,15,15,40]'
  && (await one(`SELECT value FROM platform_settings WHERE key='checkin_token_expiry_days'`)).value === 60,
  'a proposta grava prémios 5,5,10,10,15,15,40 e validade 60 dias')

s = await status(1)
ok(s.enabled === true && s.eligible === true && s.streak_day === 1 && s.already_done === false && s.tokens_today === 5,
  `estado antes do primeiro check-in: Dia 1, vale 5 (${JSON.stringify({ e: s.enabled, el: s.eligible, d: s.streak_day, t: s.tokens_today })})`)

// Dia 1
let r = await checkin(1)
let t = await tokensDe(1)
ok(r.ok === true && r.already_done === false && r.streak_day === 1 && r.tokens_awarded === 5 && r.next_reward === 5,
  `Dia 1: ganha 5, amanhã vale 5 (${JSON.stringify({ ok: r.ok, ad: r.already_done, d: r.streak_day, t: r.tokens_awarded, n: r.next_reward })})`)
ok(t.length === 1 && t[0].amount === 5 && t[0].source_order_id === `checkin-${hoje}-${U(1)}`, `token gravado com source_order_id checkin-${hoje}-<uid> (${t[0]?.source_order_id})`)
ok(t[0].dias > 59.9 && t[0].dias < 60.1, `validade de 60 dias (${Number(t[0].dias).toFixed(3)})`)
ok(r.balance === 5, `saldo devolvido na hora = 5 (${r.balance})`)

// duplicado no mesmo dia
r = await checkin(1)
t = await tokensDe(1)
ok(r.ok === true && r.already_done === true && r.tokens_awarded === 0 && t.length === 1, 'segundo toque no mesmo dia não dá tokens nem grava outra linha')
ok((await one(`SELECT count(*)::int AS n FROM daily_checkins WHERE user_id = $1`, [U(1)])).n === 1, 'um check-in por dia de calendário')

// dia seguido (cliente só por user_roles) + dois clientes no mesmo dia (índice único)
await historico(2, 1, 2)
r = await checkin(2)
t = await tokensDe(2)
ok(r.ok && r.streak_day === 3 && r.tokens_awarded === 10, `ontem Dia 2 → hoje Dia 3, 10 tokens (deu Dia ${r.streak_day}, ${r.tokens_awarded})`)
ok(t.length === 1 && t[0].amount === 10, 'segundo cliente do mesmo dia também recebe (sem choque no índice único)')

// dia falhado
await historico(3, 2, 5)
r = await checkin(3)
ok(r.ok && r.streak_day === 1 && r.tokens_awarded === 5, `falhou ontem (anteontem Dia 5) → Dia 1, 5 tokens (deu Dia ${r.streak_day})`)

// dia 7 → 1
await historico(4, 1, 7)
r = await checkin(4)
ok(r.ok && r.streak_day === 1 && r.tokens_awarded === 5, `ontem Dia 7 → ciclo novo, Dia 1 (deu Dia ${r.streak_day})`)

// dia 6 → 7 = 40
await historico(5, 1, 6)
r = await checkin(5)
ok(r.ok && r.streak_day === 7 && r.tokens_awarded === 40 && r.next_reward === 5, `ontem Dia 6 → Dia 7, 40 tokens, amanhã volta a 5 (deu ${r.tokens_awarded}, próximo ${r.next_reward})`)

// sem telemóvel
r = await checkin(6)
ok(r.ok === false && r.reason === 'sem_telemovel' && (await tokensDe(6)).length === 0
  && (await one(`SELECT count(*)::int AS n FROM daily_checkins WHERE user_id=$1`, [U(6)])).n === 0,
  `sem telemóvel recusa e não grava nada (reason=${r.reason})`)

// não é cliente
r = await checkin(13)
ok(r.ok === false && r.reason === 'nao_cliente' && (await tokensDe(13)).length === 0, `estafeta sem papel de cliente recusa (reason=${r.reason})`)

// sem sessão
await como(null)
r = (await one(`SELECT public.client_daily_checkin() AS r`)).r
ok(r.ok === false && r.reason === 'sem_sessao', 'sem sessão recusa')

// require_phone desligado
await set('checkin_require_phone', false)
r = await checkin(6)
ok(r.ok && r.tokens_awarded === 5, 'com checkin_require_phone=false quem não tem telemóvel já ganha')
await set('checkin_require_phone', true)

// prémios do painel
await set('checkin_rewards', [1, 2, 3, 4, 5, 6, 100])
r = await checkin(7)
ok(r.ok && r.tokens_awarded === 1 && JSON.stringify(r.rewards) === '[1,2,3,4,5,6,100]', 'prémios editados no painel valem logo')
await set('checkin_rewards', ['x'])
r = await checkin(8)
ok(r.ok && r.tokens_awarded === 5, 'prémios inválidos → volta aos do Danilo (5)')
await set('checkin_rewards', [5, 5, 10, 10, 15, 15, 40])

// validade do painel
await q(`DELETE FROM daily_checkins WHERE user_id = $1`, [U(8)])
await q(`DELETE FROM bora_tokens WHERE user_id = $1`, [U(8)])
await set('checkin_token_expiry_days', 30)
r = await checkin(8)
t = await tokensDe(8)
ok(t.length === 1 && t[0].dias > 29.9 && t[0].dias < 30.1, `validade editada no painel (30 dias) vale logo (${Number(t[0]?.dias).toFixed(3)})`)
await set('checkin_token_expiry_days', 60)

// interruptor
await set('checkin_enabled', false)
r = await checkin(9)
s = await status(9)
ok(r.ok === false && r.reason === 'desligado' && s.enabled === false, 'checkin_enabled=false desliga o check-in')
await set('checkin_enabled', true)

// ---- 5. lembretes -------------------------------------------------------------
await historico(10, 1, 3)   // ontem Dia 3, ainda não fez hoje, aparelho ativo
await historico(11, 1, 2)   // ontem Dia 2, aparelho desligado
const horaAgora = (await one(`SELECT extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int AS h`)).h
await set('checkin_push_morning_hour', horaAgora)
await set('checkin_push_evening_enabled', false)
await q(`DELETE FROM net_calls`)
// RGPD (23/09): por defeito só quem aceitou promoções. Ninguém aceitou → ninguém recebe.
ok((await one(`SELECT value FROM platform_settings WHERE key='checkin_push_so_opt_in'`)).value === true, 'por defeito, lembretes só a quem aceitou promoções')
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
ok(lem.turno === 'manha' && lem.pessoas === 0 && (await q(`SELECT 1 FROM net_calls`)).length === 0,
  'sem ninguém com promoções aceites, não sai nenhum lembrete')
await q(`UPDATE public.users SET marketing_opt_in = true WHERE id = ANY($1::uuid[])`, [[U(9), U(10), U(11), U(12), U(13)]])
await q(`UPDATE public.users SET marketing_opt_in = false WHERE id = $1`, [U(9)])
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
let chamadas = await q(`SELECT body FROM net_calls ORDER BY id`)
ok(JSON.stringify(chamadas.flatMap((c) => c.body.user_ids)) === JSON.stringify([U(10)]),
  'com promoções aceites só pelo 10, só o 10 recebe (o 9 não aceitou)')
await q(`DELETE FROM net_calls`)
await q(`DELETE FROM checkin_lembretes_envios`)
await set('checkin_push_so_opt_in', false)
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
chamadas = await q(`SELECT body FROM net_calls ORDER BY id`)
const alvos = chamadas.flatMap((c) => c.body.user_ids).sort()
ok(lem.turno === 'manha' && JSON.stringify(alvos) === JSON.stringify([U(9), U(10)].sort()),
  `manhã: só quem ainda não fez hoje, tem telemóvel e aparelho ativo (alvos=${alvos.map((a) => +a.slice(-3)).join(',')})`)
const corpo9 = chamadas.find((c) => c.body.user_ids.includes(U(9)))?.body
const corpo10 = chamadas.find((c) => c.body.user_ids.includes(U(10)))?.body
ok(corpo9?.body === 'O teu check-in de hoje vale 5 tokens.' && corpo10?.body === 'O teu check-in de hoje vale 10 tokens.',
  `texto da manhã com o valor de cada um ("${corpo9?.body}" / "${corpo10?.body}")`)
ok(corpo9?.type === 'checkin_diario' && chamadas.every((c) => c.body.title === 'Check-in diário'), 'tipo checkin_diario e título "Check-in diário"')
await q(`DELETE FROM net_calls`)
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
ok((await q(`SELECT 1 FROM net_calls`)).length === 0 && lem.pessoas === 0, 'manhã a correr outra vez: ninguém recebe duas vezes')

await set('checkin_push_morning_enabled', false)
await set('checkin_push_evening_enabled', true)
await set('checkin_push_evening_hour', horaAgora)
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
chamadas = await q(`SELECT body FROM net_calls ORDER BY id`)
ok(lem.turno === 'noite' && chamadas.length === 1 && JSON.stringify(chamadas[0].body.user_ids) === JSON.stringify([U(10)]),
  `noite: só quem tem sequência a correr e ainda não fez hoje (alvos=${chamadas.flatMap((c) => c.body.user_ids).map((a) => +a.slice(-3)).join(',')})`)
ok(chamadas[0]?.body.body === 'Não percas a tua sequência de 3 dias! Faz o check-in de hoje e ganha 10 tokens.', `texto da noite: "${chamadas[0]?.body.body}"`)
await q(`DELETE FROM net_calls`)
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
ok((await q(`SELECT 1 FROM net_calls`)).length === 0, 'noite a correr outra vez: ninguém recebe duas vezes')
const porPessoa = await one(`SELECT max(n)::int AS m FROM (SELECT user_id, count(*) n FROM checkin_lembretes_envios WHERE dia = $1::date GROUP BY 1) x`, [hoje])
ok(porPessoa.m === 2, `no máximo 2 lembretes de check-in por pessoa por dia (máximo visto: ${porPessoa.m})`)

// sequência de 1 dia (singular)
await q(`DELETE FROM checkin_lembretes_envios`)
await q(`DELETE FROM daily_checkins WHERE user_id = $1`, [U(10)])
await historico(10, 1, 1)
await q(`DELETE FROM net_calls`)
await one(`SELECT public.checkin_lembretes_processar() AS r`)
chamadas = await q(`SELECT body FROM net_calls ORDER BY id`)
ok(chamadas[0]?.body.body === 'Não percas a tua sequência de 1 dia! Faz o check-in de hoje e ganha 5 tokens.', `singular: "${chamadas[0]?.body.body}"`)

await set('checkin_push_evening_hour', (horaAgora + 1) % 24)
lem = (await one(`SELECT public.checkin_lembretes_processar() AS r`)).r
ok(lem.motivo === 'fora_de_hora', 'fora das horas das definições não sai nada')

// lotes de 150 (o push-clientes-alvo lê a lista por GET no endereço)
await q(`DELETE FROM checkin_lembretes_envios`)
await q(`DELETE FROM net_calls`)
const muitos = Array.from({ length: 151 }, (_, i) => U(1000 + i))
for (const [i, id] of muitos.entries()) {
  await q(`INSERT INTO auth.users(id, email) VALUES ($1, $2)`, [id, `m${i}@teste.local`])
  await q(`INSERT INTO public.users(id, name, email, phone, role, marketing_opt_in) VALUES ($1,$2,$3,$4,'client',true)`,
    [id, `Muitos ${i}`, `m${i}@teste.local`, `93${String(i).padStart(7, '0')}`])
  await q(`INSERT INTO public.client_push_tokens(user_id, fcm_token, active) VALUES ($1, $2, true)`, [id, `tok-m${i}`])
}
await set('checkin_push_morning_enabled', true)
await set('checkin_push_morning_hour', horaAgora)
await set('checkin_push_evening_enabled', false)
await set('checkin_push_so_opt_in', true)   // um passo anterior desligou-o
await one(`SELECT public.checkin_lembretes_processar() AS r`)
chamadas = await q(`SELECT body FROM net_calls ORDER BY id`)
const tamanhos = chamadas.map((c) => c.body.user_ids.length)
const todos = chamadas.flatMap((c) => c.body.user_ids)
ok(Math.max(...tamanhos) <= 150 && tamanhos.includes(150) && muitos.every((id) => todos.filter((x) => x === id).length === 1),
  `151 pessoas no mesmo dia vão em lotes de no máximo 150, cada uma uma vez (lotes: ${tamanhos.join(', ')})`)
const outros = todos.filter((x) => !muitos.includes(x)).map((a) => +a.slice(-4)).sort((a, b) => a - b)
ok(JSON.stringify(outros) === JSON.stringify([10]),
  `além das 151, só recebe quem pode (aceitou promoções, telemóvel, aparelho, não fez hoje): ${outros.join(',')}`)

// ---- 6. painel admin ------------------------------------------------------------
await comoAdmin(false)
let recusou = false
try { await one(`SELECT public.admin_checkin_resumo() AS r`) } catch (e) { recusou = /admin_required/.test(e.message) }
ok(recusou, 'resumo do painel recusa quem não é admin')
await comoAdmin(true)
const res = (await one(`SELECT public.admin_checkin_resumo() AS r`)).r
const hojeRes = res.por_dia.find((d) => d.dia === hoje)
const tokHoje = (await one(`SELECT sum(tokens_awarded)::int AS t, count(*)::int AS n FROM daily_checkins WHERE checkin_date = $1::date`, [hoje]))
ok(hojeRes && hojeRes.tokens === tokHoje.t && hojeRes.checkins === tokHoje.n,
  `resumo de hoje: ${hojeRes?.checkins} check-ins, ${hojeRes?.tokens} tokens (o ecrã converte em € com token_value_cents_x100)`)
ok(res.por_semana.length >= 1 && res.por_mes.length >= 1 && res.funcao_de_credito_existe === true, 'resumo por semana e por mês e diz que a função de crédito existe')
const optIn = (await one(`SELECT count(*)::int AS n FROM public.users WHERE marketing_opt_in AND role = 'client'`)).n
ok(Number(res.clientes_com_promocoes_aceites) === optIn, `resumo diz quantos clientes aceitaram promoções (${res.clientes_com_promocoes_aceites} = ${optIn})`)
const lista = (await q(`SELECT * FROM public.admin_checkin_clientes()`))
ok(lista.some((l) => l.user_id === U(5) && l.dia_sequencia === 7 && l.fez_hoje === true && l.total_tokens_checkin === 40),
  'lista do painel mostra quem está em que dia (Cliente Cinco no Dia 7, 40 tokens)')
const busca = (await q(`SELECT * FROM public.admin_checkin_clientes('Nunca')`))
ok(busca.length === 1 && busca[0].user_id === U(9) && busca[0].total_checkins === 0, 'pesquisa encontra cliente que ainda não fez check-in (para dar tokens)')

console.log(`\n${total - falhas}/${total} verificações passaram${falhas ? ` — ${falhas} FALHARAM` : ''}`)
process.exit(falhas ? 1 : 0)
