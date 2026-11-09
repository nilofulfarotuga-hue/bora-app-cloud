// Prova em PGlite (Postgres em WASM) da PROPOSTA cartão e MB Way da Casa (m11, 09/11/2026), com as
// funções REAIS da Casa lidas de produção (pg_get_functiondef, só leitura) e as tabelas com a estrutura
// real (colunas, valores por defeito, CHECK e UNIQUE lidos de produção). Nada toca em produção.
// Stubs só para o que sai da base: avisos (push), a rotação de ofertas e o convite de orçamentos — gravam
// numa tabela para se provar QUANDO são chamados.
//
// Uso: node provar_cartao_mbway.mjs <pasta-pglite> <casa_funcs.json> <casa_ddl.json> <proposta.md>
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const [, , pasta, funcsJson, ddlJson, propostaMd] = process.argv;
const { PGlite } = await import(pathToFileURL(join(pasta, 'node_modules/@electric-sql/pglite/dist/index.js')).href);
const linhas = (f) => { const j = JSON.parse(fs.readFileSync(f, 'utf8')); return j.rows ?? j; };
const funcs = linhas(funcsJson);
const ddl = linhas(ddlJson);
const md = fs.readFileSync(propostaMd, 'utf8');
const proposta = md.match(/```sql\n([\s\S]*?)```/)[1];

process.on('unhandledRejection', (e) => { console.error('ERRO:', e.message, e.where ?? ''); process.exit(2); });
const db = await PGlite.create();
let falhas = 0;
const ok = (cond, msg) => { console.log(`${cond ? 'OK   ' : 'FALHA'} ${msg}`); if (!cond) falhas++; };
const um = async (sql, p) => (await db.query(sql, p)).rows[0];
const erro = async (sql, p) => { try { await db.query(sql, p); return null; } catch (e) { return e.message; } };

const CLIENTE = '11111111-1111-1111-1111-111111111111';
const PRO_USER = '22222222-2222-2222-2222-222222222222';
const PROF = '33333333-3333-3333-3333-333333333333';
const ROUPEIRO = '44444444-4444-4444-4444-444444444444';
const MOVEL = '55555555-5555-5555-5555-555555555555';
const ORC = '66666666-6666-6666-6666-666666666666';
const comoCliente = `select set_config('request.jwt.claims', '{"sub":"${CLIENTE}","role":"authenticated"}', false)`;
const comoPro = `select set_config('request.jwt.claims', '{"sub":"${PRO_USER}","role":"authenticated"}', false)`;

// ─── base ────────────────────────────────────────────────────────────────────
await db.exec(`
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema auth;
create table auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table public.platform_settings (key text primary key, value jsonb, description text, category text,
  updated_at timestamptz default now(), updated_by uuid, is_secret boolean default false);
create table public.users (id uuid primary key, name text, phone text, email text, role text);
create function public.is_admin() returns boolean language sql stable as $$ select false $$;
create function public.is_demo_email(text) returns boolean language sql stable as $$ select false $$;
create function public.is_demo_user(uuid) returns boolean language sql stable as $$ select false $$;
create function public.log_admin_action(text, text, text, jsonb) returns void language sql as $$ select $$;
create table public.chamadas (quem text, pedido uuid, titulo text, texto text, em timestamptz default clock_timestamp());
create function public._cleaning_distance_km(lat1 float8, lng1 float8, lat2 float8, lng2 float8) returns float8
  language sql immutable as $$ select 6371 * 2 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))) $$;
`);
for (const t of ddl) {
  const partes = [t.colunas, t.restricoes].filter(Boolean).join(',\n  ');
  await db.exec(`create table public.${t.tabela} (\n  ${partes}\n);`);
  // os índices únicos que já vêm das restrições UNIQUE não se criam duas vezes
  if (t.unicos) await db.exec(t.unicos.split(';\n').map((s) => s.replace(/^CREATE UNIQUE INDEX /, 'CREATE UNIQUE INDEX IF NOT EXISTS ') + ';').join('\n'));
}
// como o pg_dump: os corpos só se verificam quando a função corre (há funções da Casa que usam
// coisas de fora que estes cenários nunca chamam)
await db.exec('set check_function_bodies = off');
for (const f of funcs) await db.exec(f.def + ';');
await db.exec('set check_function_bodies = on');
// stubs do que sai da base (avisos, rotação, convites) — registam a chamada
await db.exec(`
drop function public._casa_notificar(uuid, text, text, text, text, uuid);
drop function public._casa_notificar_admin(text, text);
drop function public._casa_proxima_oferta(uuid);
drop function public._casa_convidar(uuid);
create or replace function public._casa_notificar(p_user uuid, p_papel text, p_kind text, p_titulo text, p_texto text, p_pedido uuid)
  returns void language sql as $$ insert into chamadas values ('aviso:' || p_papel, p_pedido, p_titulo, p_texto) $$;
create or replace function public._casa_notificar_admin(p_titulo text, p_texto text)
  returns void language sql as $$ insert into chamadas values ('admin', null, p_titulo, p_texto) $$;
create or replace function public._casa_proxima_oferta(p_id uuid)
  returns void language sql as $$ insert into chamadas values ('oferta', p_id, null, null) $$;
create or replace function public._casa_convidar(p_id uuid)
  returns void language sql as $$ insert into chamadas values ('convite', p_id, null, null) $$;
create or replace function public._casa_valores_validos() returns boolean language sql stable as $$ select true $$;
`);
const sigs = (await db.query(`select pg_get_function_identity_arguments('public._casa_notificar'::regproc) a`)).rows[0];
ok(!!sigs, 'stubs de avisos/ofertas carregados');

await db.exec(`
insert into auth.users (id, email) values ('${CLIENTE}', 'cliente@teste'), ('${PRO_USER}', 'pro@teste');
insert into public.users (id, name) values ('${CLIENTE}', 'Cliente Teste'), ('${PRO_USER}', 'Pro Teste');
insert into public.platform_settings (key, value) values
  ('casa_enabled', 'true'), ('max_cash_amount_cents', '4000'), ('casa_min_lead_hours', '2'),
  ('casa_cancel_free_hours', '12'), ('casa_cancel_half_hours', '2'), ('casa_bora_pct', '15');
insert into public.casa_oficios (codigo, nome, ativo, ordem, fase) values ('montagem', 'Montagem', true, 1, 1);
insert into public.casa_servicos (id, oficio, nome, modo, preco_cents, unidade, min_quantidade, max_quantidade, duracao_min, perguntas, ativo, ordem)
values ('${ROUPEIRO}', 'montagem', 'Montar roupeiro', 'fixo', 8000, 'movel', 1, 5, 180, '[]', true, 1),
       ('${MOVEL}', 'montagem', 'Montar móvel médio', 'fixo', 4000, 'movel', 1, 10, 90, '[]', true, 2),
       ('${ORC}', 'montagem', 'Outro (orçamento)', 'orcamento', null, 'tarefa', 1, 1, 120, '[]', true, 3);
insert into public.casa_profissionais (id, user_id, name, email, approval_status, is_active, base_lat, base_lng, service_radius_km)
values ('${PROF}', '${PRO_USER}', 'Pro Teste', 'pro@teste', 'approved', true, 40.53, -7.26, 15);
insert into public.casa_disponibilidade (profissional_id, weekday, start_time, end_time)
select '${PROF}', d, '08:00', '20:00' from generate_series(0, 6) d;
`);

const criar = (servico, metodo, chave) => `select public.casa_criar_pedido('${servico}', 1, 'teste', '{}'::jsonb,
  'Rua de Teste 1', 'Guarda', '6300-000', 40.537, -7.267,
  (date_trunc('day', now() at time zone 'Europe/Lisbon') + interval '2 days 10 hours') at time zone 'Europe/Lisbon',
  '${metodo}', '${chave}') as j`;

// ─── ANTES (funções de produção, sem a proposta) ─────────────────────────────
await db.exec(comoCliente);
ok((await erro(criar(ROUPEIRO, 'card', 'antes-1')))?.includes('pagamento_cartao_indisponivel'),
  'ANTES: cartão recusado (pagamento_cartao_indisponivel), como hoje em produção');
ok((await erro(criar(ROUPEIRO, 'cash', 'antes-2')))?.includes('dinheiro_acima_do_limite'),
  'ANTES: roupeiro 80 € em dinheiro recusado (limite 40 €)');

// ─── a proposta, duas vezes ──────────────────────────────────────────────────
await db.exec('reset role');
await db.exec(proposta);
await db.exec(proposta);
ok(true, 'proposta aplicada 2 vezes sem erro (idempotente)');
const cols = await um(`select count(*)::int n from information_schema.columns where table_name = 'casa_pedidos'
  and column_name in ('stripe_payment_intent_id','stripe_account','reembolso_ref','reembolso_cents','reembolsado_em')`);
ok(cols.n === 5, `casa_pedidos ganhou as 5 colunas do pagamento (${cols.n})`);
const sw = await um(`select value from platform_settings where key = 'casa_pagamento_app_ativo'`);
ok(sw?.value === false, 'interruptor casa_pagamento_app_ativo nasce false');
for (const [fn, sig] of [['casa_pagamento_confirmado', '(uuid,text,integer,text,text)'], ['casa_reembolso_registado', '(uuid,text,integer)']]) {
  const r = await um(`select has_function_privilege('anon', 'public.${fn}${sig}', 'execute') a,
    has_function_privilege('authenticated', 'public.${fn}${sig}', 'execute') b,
    has_function_privilege('service_role', 'public.${fn}${sig}', 'execute') c`);
  ok(!r.a && !r.b && r.c, `${fn}: anon e clientes NÃO podem chamar; só o servidor (service_role)`);
}

// ─── DESLIGADO: nada muda ────────────────────────────────────────────────────
await db.exec(comoCliente);
ok((await erro(criar(ROUPEIRO, 'card', 'off-1')))?.includes('pagamento_cartao_indisponivel'),
  'interruptor desligado: cartão continua recusado');
ok((await erro(criar(ROUPEIRO, 'mbway', 'off-2')))?.includes('pagamento_cartao_indisponivel'),
  'interruptor desligado: MB Way continua recusado');
ok((await um(`select public.casa_config() ->> 'pagamento_cartao' v`)).v === 'false', 'casa_config.pagamento_cartao = false');
const cashOk = (await um(criar(MOVEL, 'cash', 'off-3'))).j;
ok(cashOk.estado === 'procura', 'dinheiro 40 € continua igual: nasce em procura');
ok((await um(`select count(*)::int n from chamadas where quem = 'oferta' and pedido = '${cashOk.id}'`)).n === 1,
  'dinheiro: vai logo aos profissionais (1 chamada da rotação)');

// ─── LIGADO ──────────────────────────────────────────────────────────────────
await db.exec(`update platform_settings set value = 'true' where key = 'casa_pagamento_app_ativo'`);
ok((await um(`select public.casa_config() ->> 'pagamento_cartao' v`)).v === 'true', 'ligado: casa_config.pagamento_cartao = true');
ok((await erro(criar(ROUPEIRO, 'cash', 'on-0')))?.includes('dinheiro_acima_do_limite'),
  'ligado: roupeiro 80 € em DINHEIRO continua recusado (o limite é só do dinheiro)');
await db.exec(`delete from chamadas`);
const card = (await um(criar(ROUPEIRO, 'card', 'on-1'))).j;
ok(card.estado === 'aguarda_pagamento' && card.payment_status === 'unpaid' && card.total_cents === 8000,
  `roupeiro 80 € por cartão: aguarda_pagamento, unpaid, 8000 (${card.estado}, ${card.payment_status}, ${card.total_cents})`);
ok((await um(`select count(*)::int n from chamadas`)).n === 0,
  'por pagar: NÃO vai a nenhum profissional e não avisa o painel');
const cardDup = (await um(criar(ROUPEIRO, 'card', 'on-1'))).j;
ok(cardDup.id === card.id, 'mesma chave de idempotência devolve o mesmo pedido');

// cancelar por pagar = 0 €
const mb = (await um(criar(ROUPEIRO, 'mbway', 'on-2'))).j;
ok(mb.estado === 'aguarda_pagamento', 'MB Way 80 €: aguarda_pagamento');
const simMb = (await um(`select public.casa_cancelar_simulacao('${mb.id}') j`)).j;
ok(Number(simMb.cancel_fee_cents) === 0, `cancelar por pagar: 0 € (${simMb.cancel_fee_cents})`);
const canMb = (await um(`select public.casa_cancelar('${mb.id}', 'teste') j`)).j;
ok(canMb.cancel_fee_cents === 0, 'cancelado por pagar: taxa 0');

// ─── o servidor confirma o pagamento ─────────────────────────────────────────
await db.exec('reset role');
const conf = (pedido, pi, valor, conta = 'empresa') =>
  `select public.casa_pagamento_confirmado('${pedido}', '${pi}', ${valor}, '${conta}', 'prova') j`;
ok((await um(conf(card.id, 'pi_errado', 7999))).j.erro === 'valor_diferente', 'valor diferente do pedido: recusado');
ok((await um(conf(card.id, 'xx_1', 8000))).j.erro === 'pagamento_invalido', 'id de pagamento inválido: recusado');
await db.exec(`delete from chamadas`);
const c1 = (await um(conf(card.id, 'pi_card_1', 8000))).j;
ok(c1.ok === true && c1.estado === 'procura', `pagamento retido → procura (${JSON.stringify(c1)})`);
const linha = await um(`select payment_status, stripe_payment_intent_id, stripe_account, estado from casa_pedidos where id = '${card.id}'`);
ok(linha.payment_status === 'held' && linha.stripe_payment_intent_id === 'pi_card_1' && linha.stripe_account === 'empresa',
  'pedido fica held, com o pagamento e a conta Stripe gravados');
ok((await um(`select count(*)::int n from chamadas where quem = 'oferta' and pedido = '${card.id}'`)).n === 1,
  'só agora vai aos profissionais (1 chamada da rotação)');
ok((await um(`select count(*)::int n from chamadas where quem = 'admin'`)).n === 1, 'e o painel é avisado uma vez');
ok((await um(conf(card.id, 'pi_card_1', 8000))).j.ja_estava === true, 'repetir o mesmo pagamento: idempotente (ja_estava)');
ok((await um(conf(card.id, 'pi_card_2', 8000))).j.erro === 'outro_pagamento_ja_retido',
  'segundo pagamento diferente no mesmo pedido: recusado (a Edge devolve-o)');
ok((await erro(`update casa_pedidos set stripe_payment_intent_id = 'pi_card_1' where id = '${mb.id}'`))?.includes('ux_casa_pedidos_payment_intent'),
  'o mesmo pagamento não pode ficar em dois pedidos (índice único)');

// pagamento que chega depois de o pedido cair → devolver por inteiro
const tarde = (await um(conf(mb.id, 'pi_mb_tarde', 8000, 'pessoal'))).j;
ok(tarde.ok === true && tarde.reembolsar === true, `MB Way aprovado depois de cancelado: marcado para devolver (${JSON.stringify(tarde)})`);
const lt = await um(`select reembolso_pendente, cancel_fee_cents, payment_status from casa_pedidos where id = '${mb.id}'`);
ok(lt.reembolso_pendente === true && lt.cancel_fee_cents === 0 && lt.payment_status === 'held', 'reembolso pendente, taxa 0');

// ─── cliente cancela um pedido pago com mais de 12 h → devolução total ───────
await db.exec(comoCliente);
const can = (await um(`select public.casa_cancelar('${card.id}', 'mudei de ideias') j`)).j;
ok(can.cancel_fee_cents === 0, 'pago e cancelado com mais de 12 h: taxa 0');
await db.exec('reset role');
ok((await um(`select reembolso_pendente r from casa_pedidos where id = '${card.id}'`)).r === true, 'fica reembolso pendente');
ok((await um(`select public.casa_reembolso_registado('${card.id}', 're_x', 8001) j`)).j.erro === 'valor_invalido',
  'devolver mais do que o pedido: recusado');
const dev = (await um(`select public.casa_reembolso_registado('${card.id}', 're_1', 8000) j`)).j;
ok(dev.ok === true, 'devolução registada');
const ld = await um(`select payment_status, reembolso_pendente, reembolso_cents, reembolso_ref from casa_pedidos where id = '${card.id}'`);
ok(ld.payment_status === 'estornado' && ld.reembolso_pendente === false && ld.reembolso_cents === 8000 && ld.reembolso_ref === 're_1',
  'pedido fica estornado, sem pendente, 8000 devolvidos, com a referência da Stripe');
ok((await um(`select count(*)::int n from chamadas where quem = 'aviso:client' and titulo = 'Devolução feita' and pedido = '${card.id}'`)).n === 1,
  'o cliente é avisado da devolução');
ok((await um(`select public.casa_reembolso_registado('${card.id}', 're_1', 8000) j`)).j.ja_estava === true, 'registar outra vez: idempotente');

// ─── orçamento aceite com cartão ─────────────────────────────────────────────
await db.exec(comoCliente);
const orc = (await um(criar(ORC, 'cash', 'orc-1'))).j;
ok(orc.estado === 'orcamentos', 'pedido de orçamento nasce em orcamentos');
await db.exec('reset role');
const q = await um(`insert into casa_orcamentos (pedido_id, profissional_id, preco_cents, duracao_min, estado, expira_em)
  values ('${orc.id}', '${PROF}', 12000, 120, 'enviado', now() + interval '1 day') returning id`);
await db.exec(`delete from chamadas`);
await db.exec(comoCliente);
const ac = (await um(`select public.casa_aceitar_orcamento('${q.id}', 'card') j`)).j;
ok(ac.estado === 'aguarda_pagamento' && ac.total_cents === 12000,
  `orçamento de 120 € aceite com cartão: aguarda_pagamento (${ac.estado}, ${ac.total_cents})`);
ok((await um(`select count(*)::int n from chamadas where quem = 'aviso:handyman'`)).n === 0,
  'o profissional ainda NÃO é avisado (falta o pagamento)');
await db.exec('reset role');
const c2 = (await um(conf(orc.id, 'pi_orc_1', 12000))).j;
ok(c2.ok === true && c2.estado === 'aceite', `pago → aceite (${JSON.stringify(c2)})`);
ok((await um(`select count(*)::int n from chamadas where quem = 'aviso:handyman' and texto like '%aceitou e pagou%'`)).n === 1,
  'só agora o profissional é avisado ("aceitou e pagou")');

// valor extra em pedido pago na app: fase 2
await db.exec(`update casa_pedidos set estado = 'em_curso' where id = '${orc.id}'`);
await db.exec(comoPro);
ok((await erro(`select public.casa_pedir_extra('${orc.id}', 1000, 'mais material')`))?.includes('extra_indisponivel_pago_na_app'),
  'pedido pago na app: pedir valor extra dá recusa clara (fase 2)');

// ─── confirmar e acerto: a Bora paga o ganho ao profissional ─────────────────
await db.exec('reset role');
await db.exec(`update casa_pedidos set estado = 'concluido', done_at = now() where id = '${orc.id}'`);
await db.exec(`select public._casa_confirmar('${orc.id}', false)`);
const cf = await um(`select estado, payment_status, comissao_cents, ganho_cents from casa_pedidos where id = '${orc.id}'`);
ok(cf.estado === 'confirmado' && cf.payment_status === 'released', `confirmado: held → released (${cf.payment_status})`);
const sem = await um(`select date_trunc('week', now()) w`);
const acerto = (await um(`select public.casa_calcular_acerto('${PROF}', $1, false) j`, [sem.w])).j;
ok(acerto.direction === 'bora_to_handyman' && Number(acerto.net_payout_cents) === cf.ganho_cents && acerto.recebido_em_mao_cents === 0,
  `acerto semanal: a Bora paga ${acerto.net_payout_cents} cêntimos ao profissional (ganho ${cf.ganho_cents}, comissão ${cf.comissao_cents})`);

console.log(falhas === 0 ? '\nTUDO CERTO' : `\n${falhas} FALHA(S)`);
process.exit(falhas === 0 ? 0 : 1);
