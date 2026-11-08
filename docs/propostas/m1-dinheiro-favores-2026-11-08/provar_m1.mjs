// Prova local (PGlite) das propostas SQL da missão m1-dinheiro-favores-2026-11-08.
// Uso: bun provar_m1.mjs <pasta-das-propostas>
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
const db = new PGlite({ extensions: { pg_trgm } });
let ok = 0, falhas = 0;
const prova = (nome, cond, detalhe = '') => {
  if (cond) { ok++; console.log('PASS', nome); } else { falhas++; console.log('FAIL', nome, detalhe); }
};
const q1 = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const comoUid = async (uid, admin = false) => {
  await db.query(`select set_config('test.uid', $1, false), set_config('test.admin', $2, false)`, [uid ?? '', admin ? 'true' : 'false']);
};

const BASE = `
create role anon; create role authenticated; create role service_role;
create schema extensions; create extension pg_trgm schema extensions;
create function extensions.unaccent(t text) returns text language sql immutable as $$
  select translate(t, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ®', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC ') $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('email', 'admin@teste') $$;
create schema vault; create table vault.decrypted_secrets(name text, decrypted_secret text);
insert into vault.decrypted_secrets values ('project_url','https://x.supabase.co'),('service_role_key','sb_secret_x');
create schema net; create table net.calls(id serial, url text, body jsonb);
create function net.http_post(url text, headers jsonb default '{}', body jsonb default '{}', timeout_milliseconds int default 5000)
  returns bigint language plpgsql as $$ begin insert into net.calls(url, body) values (url, body); return 1; end $$;
create schema storage; create table storage.buckets(id text primary key, name text, public bool);
create table storage.objects(bucket_id text, name text, metadata jsonb, created_at timestamptz default now());
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'),1)-1] $$; alter table storage.objects enable row level security;
create function public.is_admin() returns boolean language sql stable as $$ select coalesce(current_setting('test.admin', true), '') = 'true' $$;
create table public.users(id uuid primary key, name text, email text, phone text);
create table public.drivers(id uuid primary key default gen_random_uuid(), user_id uuid);
create table public.platform_settings(key text primary key, value jsonb not null, description text, category text, updated_at timestamptz, updated_by uuid, is_secret bool);
create table public.admin_audit_log(id uuid default gen_random_uuid(), admin_id uuid, admin_email text, action text not null, entity_type text, entity_id uuid, details jsonb, entity_id_text text, created_at timestamptz default now());
create table public.admin_notifications(id uuid default gen_random_uuid(), created_at timestamptz default now(), event_type text not null, severity text not null, entity_type text, entity_id text, summary text not null, payload jsonb);
create table public.cancellation_requests(id uuid primary key default gen_random_uuid(), order_id text not null, requester_role text not null check (requester_role in ('driver','partner','client')), requester_id uuid not null, reason text not null, status text check (status in ('pending','approved','rejected','withdrawn')), fee_cents int, refund_cents int, created_at timestamptz default now());
create unique index uq_cancel_req_pending_per_order on public.cancellation_requests(order_id) where status = 'pending';
create table public.notifs(user_id uuid, kind text, title text, body text, related text);
create function public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text, p_body text, p_related_id text)
  returns void language sql as $$ insert into public.notifs values (p_user_id, p_kind, p_title, p_body, p_related_id) $$;
create table public.orders(id text primary key, user_id uuid, assigned_driver_id text, current_driver_offer_id text, service_type text, status text,
  payment_method text, payment_buffer_total float8, delivery_fee numeric, errand_estimated_purchase_cents int, errand_budget_status text,
  errand_budget_requested_cents int, errand_has_purchase bool, is_purchase_finalized bool, final_total numeric, final_purchase_value float8,
  stripe_charge_cents int, wallet_applied_cents int, tokens_applied_value_cents int, menu_credit_applied_cents int, extra_charge_amount float8,
  extra_charge_settled_at timestamptz, extra_charge_settled_via text, subtotal numeric, price numeric, cash_total_due numeric, delivered_at timestamptz,
  created_at timestamptz default now(), errand_description text, is_partner_store bool, is_test_order bool, items jsonb, service_fee numeric,
  bag_fee numeric, small_order_fee numeric, helper_fee_eur numeric, customer_total numeric, total numeric, tip_amount_cents int, vendor_name text,
  restaurant_id text, stripe_account text);
create table public.order_receipts_v2(id uuid primary key default gen_random_uuid(), order_id text unique, photo_url text, photo_taken_at timestamptz,
  driver_typed_total_cents int, reimbursement_status text, reimbursement_amount_cents int, receipt_parsed jsonb);
create table public.order_invoice_requests(order_id text primary key, user_id uuid, nif text, nome text);
create table public.client_billing_profile(user_id uuid primary key, nif text, nome text);
create table public.tips(id uuid primary key default gen_random_uuid(), target text, order_id text, tvde_ride_id uuid, client_user_id uuid, provider_user_id uuid,
  amount_cents int, method text, moment text, status text, stripe_payment_intent_id text, stripe_fee_cents int, created_at timestamptz default now(),
  paid_at timestamptz, cobrada_junto bool default false, stripe_account text default 'pessoal',
  liquido_prestador_cents int generated always as (case when moment = 'after' and method in ('card','mbway') then greatest(0, amount_cents - coalesce(stripe_fee_cents, 25 + ceil(amount_cents * 0.015)::int)) else amount_cents end) stored);
create table public.products(id text primary key, price numeric, restaurant_id text);
create table public.catalog_price_updates(id uuid default gen_random_uuid(), product_id text not null, restaurant_id text, order_id text, receipt_id uuid,
  old_base numeric not null, new_base numeric not null, confianca numeric, linha_talao text, status text, created_at timestamptz default now(), decided_at timestamptz, decided_by text);
create table public.cleaners(id uuid, user_id uuid); create table public.cleaning_bookings(cleaner_id uuid, status text, completed_at timestamptz, cleaner_earnings_cents int, is_test_order bool);
create table public.washers(id uuid, user_id uuid); create table public.carwash_bookings(washer_id uuid, status text, completed_at timestamptz, washer_earnings_cents int);
create function public.driver_earnings_summary() returns jsonb language sql as $$ select '{"ok":true,"dia":{"total_cents":523},"semana":{"total_cents":523}}'::jsonb $$;
insert into public.platform_settings(key, value) values ('catalog_price_live_update_enabled', 'true');
`;

const CLI = '11111111-1111-1111-1111-111111111111';
const DRV = '22222222-2222-2222-2222-222222222222';
const OUT = '33333333-3333-3333-3333-333333333333';
const ADM = '44444444-4444-4444-4444-444444444444';

try {
  await db.exec(BASE);
  for (const f of ['01_favor_diferencas_e_entrega_sem_codigo.sql', '02_favor_aprovacao_com_tecto.sql',
                   '03_nif_estafeta_e_recibo_cliente.sql', '04_gorjeta_conta_ganho_e_robo_talao.sql', '07_taloes_guardados_para_sempre.sql']) {
    try { await db.exec(readFileSync(join(dir, f), 'utf8')); prova(`aplica ${f}`, true); }
    catch (e) { prova(`aplica ${f}`, false, e.message); }
  }
  // reaplicar tudo outra vez (idempotência)
  for (const f of ['01_favor_diferencas_e_entrega_sem_codigo.sql', '02_favor_aprovacao_com_tecto.sql',
                   '03_nif_estafeta_e_recibo_cliente.sql', '04_gorjeta_conta_ganho_e_robo_talao.sql', '07_taloes_guardados_para_sempre.sql']) {
    try { await db.exec(readFileSync(join(dir, f), 'utf8')); prova(`reaplica ${f} (idempotente)`, true); }
    catch (e) { prova(`reaplica ${f}`, false, e.message); }
  }

  await db.exec(`
    insert into public.users values ('${CLI}','Cliente Demo','cliente@demo.pt','912000000');
    insert into public.drivers(user_id) values ('${DRV}'), ('${OUT}');
    -- Favor MB Way: estimativa 12,00 €, taxas 6,00 €, pagou 12×1,2+6 = 20,40 €
    insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method,payment_buffer_total,delivery_fee,
      errand_estimated_purchase_cents,errand_has_purchase,is_purchase_finalized,final_total,stripe_charge_cents,is_partner_store,errand_description)
    values ('fav-mb','${CLI}','${DRV}','errand','pickedUp','mbway',20.40,6.00,1200,true,false,18.00,2040,false,'3 sacos de pellets');
    insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method,payment_buffer_total,delivery_fee,
      errand_estimated_purchase_cents,errand_has_purchase,is_purchase_finalized,final_total,stripe_charge_cents,is_partner_store)
    values ('fav-card','${CLI}','${DRV}','errand','pickedUp','card',20.40,6.00,1200,true,false,18.00,2040,false);
    insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method,payment_buffer_total,delivery_fee,
      errand_estimated_purchase_cents,errand_has_purchase,is_purchase_finalized,final_total,is_partner_store)
    values ('fav-cash','${CLI}','${DRV}','errand','pickedUp','cash',null,6.00,1200,true,false,18.00,false);
  `);

  // ── Bloco 2: tecto ──────────────────────────────────────────────────────
  await comoUid(DRV);
  let r = (await q1(`select public.errand_teto_compra('fav-mb') r`)).r;
  prova('tecto MB Way = pago − taxas = 14,40 €', r.teto_cents === 1440, JSON.stringify(r));
  r = (await q1(`select public.errand_teto_compra('fav-cash') r`)).r;
  prova('tecto dinheiro = 12,00 × 1,15 = 13,80 €', r.teto_cents === 1380, JSON.stringify(r));
  await comoUid(OUT);
  r = (await q1(`select public.errand_teto_compra('fav-mb') r`)).r;
  prova('outro estafeta não lê o tecto', r.error === 'forbidden', JSON.stringify(r));

  await comoUid(DRV);
  r = (await q1(`select public.estafeta_favor_pedir_aprovacao('fav-mb', 1400, null) r`)).r;
  prova('valor dentro do tecto não pergunta', r.dentro_do_teto === true, JSON.stringify(r));
  r = (await q1(`select public.estafeta_favor_pedir_aprovacao('fav-mb', 1797, 'favores/etiqueta.jpg') r`)).r;
  prova('acima do tecto cria pedido pendente 180 s', r.ok === true && r.segundos === 180 && r.teto_cents === 1440, JSON.stringify(r));
  let c = await q1(`select body from net.calls where url like '%notify-client' order by id desc limit 1`);
  prova('cliente recebe push com toque persistente', c?.body?.ring === true && c?.body?.ring_seconds === 180, JSON.stringify(c));
  r = (await q1(`select public.estafeta_favor_pedir_aprovacao('fav-mb', 1900, null) r`)).r;
  prova('segundo pedido com o primeiro vivo → pedido_em_curso', r.error === 'pedido_em_curso', JSON.stringify(r));
  r = (await q1(`select public.estafeta_favor_sem_resposta('fav-mb', 'cancelar') r`)).r;
  prova('estafeta não pode sair antes do fim do prazo', r.error === 'ainda_a_espera', JSON.stringify(r));

  await comoUid(OUT);
  r = (await q1(`select public.cliente_favor_responder('fav-mb', 'aprovar') r`)).r;
  prova('quem não é dono não responde', r.error === 'pedido_nao_encontrado', JSON.stringify(r));
  await comoUid(CLI);
  r = (await q1(`select public.cliente_favor_responder('fav-mb', 'aprovar') r`)).r;
  prova('cliente aprova (MB Way) → pedido de diferença', r.ok === true && r.mbway?.ok === true && r.mbway?.valor_cents === 357, JSON.stringify(r));
  let fd = await q1(`select * from public.favor_diferencas where pedido_id='fav-mb' order by criado_em desc limit 1`);
  prova('favor_diferencas: 17,97 + 6,00 − 20,40 = 3,57 € pedido, tentativa 101', fd?.valor_cents === 357 && fd?.tentativa === 101 && fd?.estado === 'pedido', JSON.stringify(fd));
  await comoUid(DRV);
  r = (await q1(`select public.errand_teto_compra('fav-mb') r`)).r;
  prova('aprovado mas MB Way por pagar → estafeta espera', r.espera_pagamento_mbway === true && r.teto_cents === 1440, JSON.stringify(r));
  r = (await q1(`select public.favor_diferenca_resultado('fav-mb', 'pi_dif_1', 357, true, 'payment_intent.succeeded') r`)).r;
  prova('webhook: pago', r.ok === true && r.estado === 'pago', JSON.stringify(r));
  r = (await q1(`select public.favor_diferenca_resultado('fav-mb', 'pi_dif_1', 357, true, 'payment_intent.succeeded') r`)).r;
  prova('webhook repetido é idempotente', r.idempotente === true, JSON.stringify(r));
  r = (await q1(`select public.errand_teto_compra('fav-mb') r`)).r;
  prova('depois de pago o tecto sobe a 17,97 €', r.espera_pagamento_mbway === false && r.teto_cents === 1797, JSON.stringify(r));
  let n = await q1(`select count(*)::int n from public.notifs where user_id='${DRV}' and kind='errand_extra_pago'`);
  prova('estafeta avisado do pagamento', n.n === 1);
  // compra fecha a 17,97 → nada mais a pedir
  const antes = (await q1(`select count(*)::int n from net.calls where url like '%favor-cobrar-diferenca'`)).n;
  r = (await q1(`select public.finalize_errand_purchase('fav-mb', 1797, 'talao.jpg') r`)).r;
  const depois = (await q1(`select count(*)::int n from net.calls where url like '%favor-cobrar-diferenca'`)).n;
  prova('fechar a compra com a diferença já paga não pede outro MB Way', r.mbway_diferenca_pedida === false && depois === antes && r.dispute === false, JSON.stringify(r));

  // cartão: aprovação simples
  await comoUid(DRV);
  await q1(`select public.estafeta_favor_pedir_aprovacao('fav-card', 1600, null)`);
  await comoUid(CLI);
  r = (await q1(`select public.cliente_favor_responder('fav-card', 'so_ate_teto') r`)).r;
  let o = await q1(`select errand_budget_status from public.orders where id='fav-card'`);
  prova('cliente escolhe "comprar só até"', r.ok === true && o.errand_budget_status === 'so_ate_teto', JSON.stringify(r));

  // dinheiro: sem resposta → cancelar com taxa
  await comoUid(DRV);
  await q1(`select public.estafeta_favor_pedir_aprovacao('fav-cash', 1600, null)`);
  await db.exec(`update public.favor_aprovacoes set expira_em = now() - interval '1 second' where pedido_id='fav-cash'`);
  r = (await q1(`select public.estafeta_favor_sem_resposta('fav-cash', 'cancelar') r`)).r;
  let cr = await q1(`select * from public.cancellation_requests where order_id='fav-cash'`);
  prova('sem resposta → cancelamento pedido com taxa 3,00 €', r.ok === true && cr?.fee_cents === 300 && cr?.requester_role === 'driver', JSON.stringify({ r, cr }));
  n = await q1(`select count(*)::int n from public.admin_notifications where event_type='favor_cancelar_por_preco'`);
  prova('painel avisado do cancelamento', n.n === 1);

  // admin aprova pelo cliente
  await db.exec(`insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method,payment_buffer_total,delivery_fee,
      errand_estimated_purchase_cents,errand_has_purchase,is_purchase_finalized,final_total,stripe_charge_cents,is_partner_store)
    values ('fav-adm','${CLI}','${DRV}','errand','pickedUp','card',20.40,6.00,1200,true,false,18.00,2040,false)`);
  await comoUid(DRV);
  await q1(`select public.estafeta_favor_pedir_aprovacao('fav-adm', 1500, null)`);
  await comoUid(ADM, false);
  try { await q1(`select public.admin_favor_aprovar_pelo_cliente('fav-adm', 'falei com ele')`); prova('não-admin não aprova pelo cliente', false); }
  catch { prova('não-admin não aprova pelo cliente', true); }
  await comoUid(ADM, true);
  r = (await q1(`select public.admin_favor_aprovar_pelo_cliente('fav-adm', 'oi') r`)).r;
  prova('admin sem motivo → motivo_obrigatorio', r.error === 'motivo_obrigatorio', JSON.stringify(r));
  r = (await q1(`select public.admin_favor_aprovar_pelo_cliente('fav-adm', 'falei com o cliente por telefone') r`)).r;
  let aud = await q1(`select count(*)::int n from public.admin_audit_log where action='favor_aprovar_pelo_cliente' and entity_id_text='fav-adm'`);
  prova('admin aprova pelo cliente com registo', r.ok === true && aud.n === 1, JSON.stringify(r));
  r = (await q1(`select public.admin_favor_aprovacoes_listar(false, 50) r`)).r;
  prova('lista do painel traz os pedidos de aprovação', Array.isArray(r) && r.length === 4, JSON.stringify(r).slice(0, 200));

  // ── Bloco 3: entregue sem código ───────────────────────────────────────
  await db.exec(`insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method) values
    ('ent-1','${CLI}','${DRV}','restaurant','pickedUp','card'), ('ent-2','${CLI}',null,'restaurant','onTheWay','card'),
    ('ent-3','${CLI}','${DRV}','restaurant','preparing','card'), ('ent-4','${CLI}','${DRV}','restaurant','onTheWay','cash')`);
  await comoUid(ADM, true);
  r = (await q1(`select public.admin_marcar_entregue_sem_codigo('ent-1', 'abc') r`)).r;
  prova('sem motivo não fecha', r.error === 'motivo_obrigatorio');
  r = (await q1(`select public.admin_marcar_entregue_sem_codigo('ent-1', 'cliente sem o código, entreguei em mão') r`)).r;
  o = await q1(`select status, delivered_at from public.orders where id='ent-1'`);
  prova('pickedUp → delivered pelo painel', r.ok === true && o.status === 'delivered' && o.delivered_at !== null, JSON.stringify(r));
  r = (await q1(`select public.admin_marcar_entregue_sem_codigo('ent-1', 'outra vez mesmo pedido') r`)).r;
  prova('segunda vez é idempotente', r.ja_entregue === true);
  r = (await q1(`select public.admin_marcar_entregue_sem_codigo('ent-3', 'ainda na cozinha teste') r`)).r;
  prova('estado errado não fecha', r.error === 'estado_invalido');
  r = (await q1(`select public.admin_marcar_entregue_sem_codigo('ent-2', 'pedido sem estafeta teste') r`)).r;
  prova('sem estafeta não fecha', r.error === 'sem_estafeta');
  await comoUid(null);
  r = (await q1(`select public.ops_marcar_entregue_sem_codigo('ent-4', 'Danilo: É pra forçar e pronto', 'qualquer') r`)).r;
  prova('ops com quem inválido → recusa', r.error === 'quem_invalido');
  r = (await q1(`select public.ops_marcar_entregue_sem_codigo('ent-4', 'forçar', 'claude-ai') r`)).r;
  prova('ops sem a frase → recusa', r.error === 'motivo_com_a_frase_do_danilo');
  r = (await q1(`select public.ops_marcar_entregue_sem_codigo('ent-4', 'Danilo 08/11: É pra forçar e pronto', 'claude-ai') r`)).r;
  aud = await q1(`select admin_email from public.admin_audit_log where entity_id_text='ent-4'`);
  prova('ops do Claude.ai fecha e regista', r.ok === true && aud?.admin_email === 'ops:claude-ai', JSON.stringify(r));
  await comoUid(CLI);
  try { await q1(`select public.ops_marcar_entregue_sem_codigo('ent-4', 'tentativa do cliente xx', 'claude-ai')`); prova('cliente não chama a porta ops', false); }
  catch { prova('cliente não chama a porta ops', true); }

  // ── Bloco 4: NIF e recibo ──────────────────────────────────────────────
  await db.exec(`insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method,is_partner_store,vendor_name,items,subtotal,
      delivery_fee,service_fee,bag_fee,small_order_fee,customer_total,price,total,final_total,tip_amount_cents,wallet_applied_cents,
      tokens_applied_value_cents,menu_credit_applied_cents,stripe_charge_cents,restaurant_id,stripe_account) values
    ('bk','${CLI}','${DRV}','restaurant','onTheWay','mbway',false,'Burger King',
     '[{"name":"Triple Whopper Spicy Menu","quantity":1,"price":16.38},{"name":"Triple Whopper Spicy Menu","quantity":1,"price":16.95}]',
     33.33,0,0.99,0.30,0,34.62,34.62,34.62,34.62,200,0,0,0,3662,'burgerking-guarda','empresa'),
    ('parc','${CLI}','${DRV}','restaurant','onTheWay','card',true,'Parceiro','[]',10,2.5,0.5,0.3,0,13.3,13.3,13.3,13.3,0,0,0,0,1330,'p1','empresa');
    insert into public.order_invoice_requests values ('parc','${CLI}','292800000','Cliente Demo');`);
  await comoUid(DRV);
  r = (await q1(`select public.driver_order_invoice_nif('bk') r`)).r;
  prova('sem NIF do cliente → NIF da Bora 519686233', r.mostrar === true && r.pediu_fatura === false && r.nif === '519686233', JSON.stringify(r));
  await db.exec(`insert into public.order_invoice_requests values ('bk','${CLI}','292811111',null)`);
  r = (await q1(`select public.driver_order_invoice_nif('bk') r`)).r;
  prova('cliente pediu NIF → estafeta vê o NIF', r.pediu_fatura === true && r.nif === '292811111' && r.texto.includes('pede ao balcão'), JSON.stringify(r));
  r = (await q1(`select public.driver_order_invoice_nif('parc') r`)).r;
  prova('loja parceira → não mostra ao estafeta', r.mostrar === false && r.loja_parceira === true);
  await comoUid(OUT);
  r = (await q1(`select public.driver_order_invoice_nif('bk') r`)).r;
  prova('outro estafeta não vê o NIF', r.error === 'nao_e_o_teu_pedido');
  await db.exec(`update public.orders set status='delivered', delivered_at=now() where id='bk'`);
  let rec = await q1(`select * from public.recibos_clientes where order_id='bk'`);
  c = await q1(`select count(*)::int n from net.calls where url like '%recibo-pedido-cliente' and body->>'order_id'='bk'`);
  prova('entregue → recibo pedido uma vez', rec?.estado === 'pendente' && c.n === 1, JSON.stringify(rec));
  await db.exec(`update public.orders set status='delivered' where id='bk'`);
  c = await q1(`select count(*)::int n from net.calls where url like '%recibo-pedido-cliente' and body->>'order_id'='bk'`);
  prova('nova gravação não reenvia', c.n === 1);
  r = (await q1(`select public._recibo_pedido('bk') r`)).r;
  prova('recibo BK: total 34,62 + gorjeta 2,00 = pago 36,62 (= Stripe)', r.total_pedido_cents === 3462 && r.gorjeta_cents === 200 && r.total_pago_cents === 3662 && r.nif === '292811111', JSON.stringify(r).slice(0, 300));
  prova('recibo BK: 2 itens, taxa de serviço e saco', r.itens.length === 2 && r.linhas.length === 2);
  r = (await q1(`select public._recibo_pedido('fav-mb') r`)).r;
  prova('recibo de pedido não entregue = vazio', r === null);
  await db.exec(`update public.platform_settings set value='false' where key='recibo_cliente_email_enabled'`);
  await db.exec(`update public.orders set status='delivered' where id='parc'`);
  c = await q1(`select count(*)::int n from net.calls where url like '%recibo-pedido-cliente' and body->>'order_id'='parc'`);
  prova('interruptor desligado → não envia', c.n === 0);
  await comoUid(ADM, true);
  r = (await q1(`select public.admin_recibo_reenviar('parc') r`)).r;
  c = await q1(`select count(*)::int n from net.calls where url like '%recibo-pedido-cliente' and body->>'order_id'='parc'`);
  prova('painel reenvia mesmo desligado (forçado)', r.ok === true && c.n === 1, JSON.stringify(r));

  // ── Bloco 5: gorjeta, ganho e robô ─────────────────────────────────────
  await db.exec(`insert into public.tips(target, order_id, client_user_id, provider_user_id, amount_cents, method, moment, status, cobrada_junto, paid_at)
                 values ('order','bk','${CLI}','${DRV}',200,'mbway','checkout','succeeded',true, now())`);
  let t = await q1(`select stripe_account, liquido_prestador_cents from public.tips where order_id='bk'`);
  prova('gorjeta herda a conta empresa do pedido', t.stripe_account === 'empresa' && t.liquido_prestador_cents === 200, JSON.stringify(t));
  await db.exec(`insert into public.tips(target, order_id, amount_cents, method, moment, status, cobrada_junto) values ('order','ent-1',100,'card','checkout','pending',true)`);
  await db.exec(`update public.orders set stripe_account='empresa' where id='ent-1'`);
  t = await q1(`select stripe_account from public.tips where order_id='ent-1'`);
  prova('conta gravada depois → gorjeta acompanha', t.stripe_account === 'empresa');
  await comoUid(DRV);
  r = (await q1(`select public.meu_ganho_ao_vivo() r`)).r;
  prova('ganho do dia = 5,23 + gorjeta 2,00 = 7,23 €', r.hoje_cents === 723 && r.por_papel.some((l) => l.papel === 'gorjetas'), JSON.stringify(r));

  // robô com o talão real do BK 56fa8623 (08/11)
  const LINHAS = [{"qty":1,"name":"3C Whopper","unit_price_cents":0},{"qty":1,"name":"Tripwhopper","unit_price_cents":947},{"qty":1,"name":"EXTRA BACON 2 FATIAS","unit_price_cents":250},{"qty":1,"name":"Com Cebola","unit_price_cents":0},{"qty":1,"name":"Batatas Media","unit_price_cents":265},{"qty":1,"name":"Cola Media","unit_price_cents":33},{"qty":1,"name":"3C Whopper","unit_price_cents":0},{"qty":1,"name":"Tripwhopper","unit_price_cents":947},{"qty":1,"name":"EXTRA BACON 2 FATIAS","unit_price_cents":250},{"qty":1,"name":"Com Pepino","unit_price_cents":0},{"qty":1,"name":"Extra Alface","unit_price_cents":0},{"qty":1,"name":"Patatas Supreme M PT","unit_price_cents":265},{"qty":1,"name":"Cola Zero Media","unit_price_cents":33},{"qty":1,"name":"Saco de Papel","unit_price_cents":5}];
  const ITENS = [{"name":"Triple Whopper Spicy Menu","quantity":1,"productId":"bk-078771af-f4cb-451a-b645-3738400175df","selected_options_priced":[{"group":"Bebidas","items":[{"name":"Coca Cola®","price_add":0.08}]},{"group":"Acompanhamentos","items":[{"name":"Batatas Fritas Clássicas","price_add":0}]},{"group":"Adiciona extras Triple Whopper Spicy","items":[{"name":"EXTRA Cebola","price_add":0},{"name":"EXTRA Bacon","price_add":0.91}]},{"group":"Carne","items":[{"name":"Triple Whopper Spicy","price_add":0}]}]},{"name":"Triple Whopper Spicy Menu","quantity":1,"productId":"bk-078771af-f4cb-451a-b645-3738400175df","selected_options_priced":[{"group":"Bebidas","items":[{"name":"Coca Cola Zero®","price_add":0.08}]},{"group":"Acompanhamentos","items":[{"name":"Batatas Supreme King Mix","price_add":0.5}]},{"group":"Adiciona extras Triple Whopper Spicy","items":[{"name":"EXTRA Alface","price_add":0},{"name":"EXTRA Picles","price_add":0},{"name":"EXTRA Bacon","price_add":0.91}]},{"group":"Carne","items":[{"name":"Triple Whopper Spicy","price_add":0}]}]}];
  await db.query(`insert into public.orders(id, restaurant_id, is_partner_store, items, status) values ('bk-robo','burgerking-guarda',false,$1,'delivered')`, [JSON.stringify(ITENS)]);
  await db.query(`insert into public.products values ('bk-078771af-f4cb-451a-b645-3738400175df', 13.25, 'burgerking-guarda')`);
  const rid = (await q1(`insert into public.order_receipts_v2(order_id, receipt_parsed) values ('bk-robo', $1) returning id`, [JSON.stringify({ lines: LINHAS })])).id;
  const casar = (await q1(`select public._talao_casar_itens($1::jsonb, $2::jsonb) r`, [JSON.stringify(ITENS), JSON.stringify(LINHAS)])).r;
  console.log('   casamento:', JSON.stringify(casar));
  prova('menu 1 = Tripwhopper + batatas + cola = 12,45 €; extra 2,50 €', casar[0].casou && casar[0].base_talao_cents === 1245 && casar[0].extras_talao_cents === 250);
  prova('menu 2 casa com o 2.º Tripwhopper (12,45 € + 2,50 €)', casar[1].casou && casar[1].base_talao_cents === 1245 && casar[1].extras_talao_cents === 250);
  r = (await q1(`select public.catalog_price_update_from_receipt($1) r`, [rid])).r;
  const p = await q1(`select price from public.products where id='bk-078771af-f4cb-451a-b645-3738400175df'`);
  const cpu = await q1(`select status, old_base, new_base, linha_talao from public.catalog_price_updates order by created_at desc limit 1`);
  console.log('   robô:', JSON.stringify(r), JSON.stringify(cpu));
  prova('robô NÃO sobe o menu (talão mais barato) → pendente', r.aplicadas === 0 && r.pendentes === 1 && Number(p.price) === 13.25 && cpu.status === 'pending');
  prova('robô avisa que o EXTRA Bacon está mais caro ao balcão (2,50 vs 0,91)', r.extras_mais_caros.length === 2 && r.extras_mais_caros[0].extras_talao_cents === 250 && r.extras_mais_caros[0].extras_app_cents === 91);
  // regra "só sobe": um talão mais caro dentro de 50% aplica
  await db.query(`update public.products set price = 11.00 where id='bk-078771af-f4cb-451a-b645-3738400175df'`);
  const rid2 = (await q1(`insert into public.order_receipts_v2(order_id, receipt_parsed) values ('bk-robo2', $1) returning id`, [JSON.stringify({ lines: LINHAS })])).id;
  await db.query(`insert into public.orders(id, restaurant_id, is_partner_store, items, status) values ('bk-robo2','burgerking-guarda',false,$1,'delivered')`, [JSON.stringify(ITENS)]);
  r = (await q1(`select public.catalog_price_update_from_receipt($1) r`, [rid2])).r;
  const p2 = await q1(`select price from public.products where id='bk-078771af-f4cb-451a-b645-3738400175df'`);
  prova('talão mais caro (12,45 vs 11,08) → sobe a base para 12,37', r.aplicadas === 1 && Number(p2.price) === 12.37, JSON.stringify(r) + ' ' + p2.price);

  // ── Adendo 1: talões guardados para sempre ────────────────────────────
  await db.exec(`
    insert into public.orders(id,user_id,assigned_driver_id,service_type,status,payment_method,is_partner_store,vendor_name,restaurant_id,delivered_at)
      values ('tal-velho','${CLI}','${DRV}','storeShopping','delivered','cash',false,'Continente','continente-guarda', now()),
             ('tal-sem','${CLI}','${DRV}','storeShopping','delivered','cash',false,'Lidl','lidl-guarda', now());
    insert into public.order_receipts_v2(order_id, photo_url, photo_taken_at, driver_typed_total_cents)
      values ('tal-velho','tal-velho.jpg', now(), 1234), ('bk','receipts/bk.jpg', now(), 2995);
    insert into storage.objects(bucket_id, name, metadata) values
      ('receipts','tal-velho.jpg','{"size": 2048}'), ('receipts','bk.jpg','{"size": 4096}');`);
  await db.exec(readFileSync(join(dir, '07_taloes_guardados_para_sempre.sql'), 'utf8'));
  let nf = await q1(`select count(*)::int n, string_agg(path, ',' order by path) p from public.order_receipt_fotos where origem='antigo'`);
  prova('fotos antigas entram no registo tal como estão (2)', nf.n === 2 && nf.p === 'bk.jpg,tal-velho.jpg', JSON.stringify(nf));
  await db.exec(readFileSync(join(dir, '07_taloes_guardados_para_sempre.sql'), 'utf8'));
  nf = await q1(`select count(*)::int n from public.order_receipt_fotos`);
  prova('reaplicar o 07 não duplica fotos', nf.n === 2);
  // duas fotos novas do mesmo pedido (Favor com 2 lojas): as duas ficam
  await db.exec(`insert into public.order_receipt_fotos(order_id, path, foto_id, total_cents, driver_uid, tirada_em, tamanho_bytes)
      values ('tal-velho','2026/11/tal-velho/f1.jpg','f1',1234,'${DRV}', now(), 3000),
             ('tal-velho','2026/11/tal-velho/f2.jpg','f2',800,'${DRV}', now(), 3100)`);
  try { await db.exec(`insert into public.order_receipt_fotos(order_id, path) values ('tal-velho','2026/11/tal-velho/f1.jpg')`); prova('o mesmo ficheiro não entra duas vezes', false); }
  catch { prova('o mesmo ficheiro não entra duas vezes', true); }
  await comoUid(ADM, true);
  r = (await q1(`select public.admin_talao_do_pedido('tal-velho') r`)).r;
  prova('painel: 3 fotos do pedido, valor escrito 12,34 e NIF da Bora', r.fotos.length === 3 && r.valor_escrito_cents === 1234 && r.nif.nif === '519686233' && r.nif.origem === 'bora', JSON.stringify(r).slice(0, 300));
  r = (await q1(`select public.admin_talao_do_pedido('bk') r`)).r;
  prova('painel: NIF do cliente quando pediu fatura', r.nif.nif === '292811111' && r.nif.origem === 'cliente', JSON.stringify(r.nif));
  const mesAtual = (await q1(`select to_char(now() at time zone 'Europe/Lisbon', 'YYYY-MM') m`)).m;
  r = (await q1(`select public.admin_taloes_listar($1, null, null, 500) r`, [mesAtual])).r;
  prova('página Talões: as 4 fotos do mês', r.ok && r.fotos.length === 4, JSON.stringify(r).slice(0, 200));
  r = (await q1(`select public.admin_taloes_listar($1, 'continente', null, 500) r`, [mesAtual])).r;
  prova('filtro por loja (Continente = 3)', r.fotos.length === 3);
  r = (await q1(`select public.admin_taloes_listar('2020-01', null, null, 500) r`)).r;
  prova('outro mês vazio', r.fotos.length === 0);
  r = (await q1(`select public.admin_taloes_listar('2020-1', null, null, 500) r`)).r;
  prova('mês mal escrito recusado', r.error === 'mes_invalido');
  r = (await q1(`select public.admin_pedidos_sem_talao(null) r`)).r;
  prova('pedido entregue sem talão aparece (Lidl)', r.some((x) => x.order_id === 'tal-sem') && !r.some((x) => x.order_id === 'tal-velho'), JSON.stringify(r).slice(0, 300));
  await comoUid(OUT);
  try { await q1(`select public.admin_taloes_listar(null, null, null, 10)`); prova('estafeta não lê a página Talões', false); }
  catch { prova('estafeta não lê a página Talões', true); }
  const pol = await q1(`select count(*)::int n from pg_policies where tablename='objects' and policyname='driver_select_own_receipt_pasta'`);
  prova('política de leitura do estafeta no caminho novo criada', pol.n === 1);
} catch (e) {
  falhas++;
  console.log('ERRO GERAL', e.message);
}
console.log(`\nRESULTADO: ${ok} passaram, ${falhas} falharam`);
process.exit(falhas ? 1 : 0);
