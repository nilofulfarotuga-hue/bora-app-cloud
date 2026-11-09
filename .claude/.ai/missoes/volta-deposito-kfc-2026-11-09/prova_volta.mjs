// Prova local (PGlite) da missão volta-deposito-kfc-2026-11-09.
// Uso: bun prova_volta.mjs <pasta fn> <migração parte1> <proposta parte2 .md>
import { PGlite } from '@electric-sql/pglite'
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm'
import fs from 'node:fs'

const [FN, M2, M3MD] = process.argv.slice(2)
const db = new PGlite({ extensions: { pg_trgm } })
const ok = []
const falhas = []
function check(nome, cond, info) {
  ;(cond ? ok : falhas).push(nome + (info !== undefined ? ' → ' + JSON.stringify(info) : ''))
}
const q = async (sql, p) => (await db.query(sql, p)).rows
const lerFn = (n) => fs.readFileSync(`${FN}/${n}.sql`, 'utf8')

await db.exec(`
create schema extensions;
create extension pg_trgm schema extensions;
create or replace function extensions.unaccent(t text) returns text language sql immutable as $$
  select translate(t, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC') $$;
create role anon; create role authenticated; create role service_role;
create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('t.uid', true), '')::uuid $$;
create function auth.role() returns text language sql as $$ select coalesce(nullif(current_setting('t.role', true), ''), 'service_role') $$;
create function public.is_admin() returns boolean language sql as $$ select true $$;
create function public.log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb) returns void language sql as $$ select $$;
create table platform_settings (key text primary key, value jsonb);
create table restaurants (id text primary key, name text, is_partner boolean default false);
create table products (id text primary key, restaurant_id text, name text, category text, price numeric,
  is_available boolean default true, photo_url text, description text, discount_price double precision);
create table product_option_groups (id text primary key, product_id text, name text);
create table product_option_items (id text primary key default gen_random_uuid()::text, group_id text, name text,
  price_add numeric default 0, is_available boolean default true);
create table product_variants (id text primary key, product_id text, price numeric);
create table orders (id text primary key, user_id uuid, status text, payment_method text, service_type text,
  is_partner_store boolean default false, restaurant_id text, cash_total_due numeric, final_total numeric, price numeric,
  items jsonb, delivered_at timestamptz, created_at timestamptz default now(), customer_total numeric, total numeric,
  subtotal numeric, delivery_fee numeric, service_fee numeric, bag_fee numeric, small_order_fee numeric,
  helper_fee_eur numeric, is_purchase_finalized boolean, wallet_applied_cents int, tokens_applied_value_cents int,
  menu_credit_applied_cents int, tip_amount_cents int, vendor_name text, final_purchase_value numeric,
  errand_description text, is_test_order boolean);
create table order_receipts_v2 (id uuid primary key default gen_random_uuid(), order_id text, receipt_parsed jsonb);
create table catalog_price_updates (id uuid primary key default gen_random_uuid(), product_id text, restaurant_id text,
  order_id text, receipt_id uuid, old_base numeric, new_base numeric, confianca numeric, linha_talao text, status text,
  decided_at timestamptz, decided_by text, option_item_id text);
create table admin_notifications (id bigserial primary key, event_type text, severity text, entity_type text,
  entity_id text, summary text, payload jsonb);
create table order_purchase_items_v2 (order_id text, status text, original_name text);
create table wallet_transactions (id bigserial primary key, user_id uuid, amount_cents int, kind text, reason text,
  related_order_id text, idempotency_key text unique, balance_after_cents int);
create table order_invoice_requests (order_id text, nif text, nome text);
create table ledger_entries (id uuid default gen_random_uuid(), user_id text, user_type text, order_id uuid,
  amount numeric, type text, reference text,
  constraint ledger_entries_type_check check (type = any (array['earning','cash_adjustment','commission','payout'])));
create table partner_weekly_settlements (id uuid default gen_random_uuid(), partner_id text, week_start_at timestamptz);
create table checkin_premios_vales (id uuid, user_id uuid, tipo text, estado text, valido_ate timestamptz,
  loja_id text, minimo_cents int, valor_cents int, pedido_id text, usado_em timestamptz, atualizado_em timestamptz,
  custo_cents int, quantidade int);
create table create_order_recentes (user_id uuid, hash text, order_id text, resultado jsonb, criado_em timestamptz);
insert into platform_settings values ('catalog_price_live_update_enabled', 'true');
`)

// funções reais (cópia de produção, 09/11/2026)
for (const n of ['_talao_norm', '_talao_e_modificador', '_talao_e_acompanhamento', '_talao_casar_itens',
  'catalog_price_update_from_receipt', '_recibo_pedido']) {
  try { await db.exec(lerFn(n) + ';') } catch (e) { falhas.push('carregar ' + n + ': ' + e.message) }
}

// ── Talão do KFC de hoje (pedido 488ad8e3) ──
const recibos = JSON.parse(fs.readFileSync(`${FN}/recibos.json`, 'utf8'))
const kfc = recibos.find((r) => r.id === '2190210d-6714-477c-9d11-4dfe657831af')
const casarAntes = (await q('select public._talao_casar_itens($1::jsonb, $2::jsonb) r', [JSON.stringify(kfc.items), JSON.stringify(kfc.lines)]))[0].r
const resumoCasar = (r) => r.map((m) => `${m.product_id?.slice(0, 12)}:${m.casou ? m.base_talao_cents : 'x'}`).join(' ')
console.log('KFC casar ANTES  :', resumoCasar(casarAntes))

// outros talões (BK, McDonald's, Continente) — o resultado ANTES, para comparar depois
const outros = recibos.filter((r) => r.id !== kfc.id && Array.isArray(r.lines) && r.lines.length > 0 && Array.isArray(r.items))
const antes = {}
for (const r of outros) {
  antes[r.id] = (await q('select public._talao_casar_itens($1::jsonb, $2::jsonb) r', [JSON.stringify(r.items), JSON.stringify(r.lines)]))[0].r
}

// robô do catálogo ANTES, com os preços antigos do KFC (antes da correção da Claude.ai)
async function semearKfc(precos) {
  await db.exec(`delete from catalog_price_updates; delete from products where restaurant_id='kfc-guarda';
    delete from orders where id='kfc-ped'; delete from order_receipts_v2;`)
  await db.query(`insert into restaurants values ('kfc-guarda','KFC Guarda',false) on conflict do nothing`)
  const ids = kfc.items.map((i) => i.productId)
  for (let k = 0; k < ids.length; k++) {
    await db.query(`insert into products (id, restaurant_id, name, category, price) values ($1,'kfc-guarda',$2,'Menus',$3)`,
      [ids[k], kfc.items[k].name, precos[k]])
  }
  await db.query(`insert into orders (id, restaurant_id, is_partner_store, items, status, payment_method, service_type, user_id)
    values ('kfc-ped','kfc-guarda',false,$1,'onTheWay','cash','restaurant', gen_random_uuid())`, [JSON.stringify(kfc.items)])
  const rid = (await q(`insert into order_receipts_v2 (order_id, receipt_parsed) values ('kfc-ped', $1) returning id`,
    [JSON.stringify({ lines: kfc.lines, store: 'KFC' })]))[0].id
  return rid
}
let rid = await semearKfc([6.20, 6.07, 8.39])
const robAntes = (await q(`select public.catalog_price_update_from_receipt($1) r`, [rid]))[0].r
const propAntes = await q(`select product_id, old_base, new_base, status from catalog_price_updates order by product_id`)
console.log('Robô ANTES:', JSON.stringify(robAntes), JSON.stringify(propAntes))

// ── PARTE 1 ──
try {
  await db.exec(fs.readFileSync(M2, 'utf8'))
  ok.push('PARTE 1 aplica sem erros (âncoras de catalog_price_update_from_receipt e _recibo_pedido = 1)')
} catch (e) {
  falhas.push('PARTE 1 falhou: ' + e.message)
}

const casarDepois = (await q('select public._talao_casar_itens($1::jsonb, $2::jsonb) r', [JSON.stringify(kfc.items), JSON.stringify(kfc.lines)]))[0].r
console.log('KFC casar DEPOIS :', resumoCasar(casarDepois))
const porId = Object.fromEntries(casarDepois.map((m) => [m.product_id, m]))
check('Box 6 Hotwings = 6,20 (0,55 + 5,65)', porId['kfc-ca992720-ca03-4741-b7db-9d5090b65759']?.base_talao_cents === 620, porId['kfc-ca992720-ca03-4741-b7db-9d5090b65759']?.grupo)
const wrap = casarDepois.find((m) => (m.linha || '').includes('WRAP'))
const bbq = casarDepois.find((m) => (m.linha || '').includes('KENTUCKY'))
check('Menu Wrap Coronel = 8,45 (5,02 + 1,70 + 1,73)', wrap?.base_talao_cents === 845, wrap?.grupo)
check('Menu Kentucky BBQ = 9,15 (5,64 + 1,74 + 1,77)', bbq?.base_talao_cents === 915, bbq?.grupo)
check('DEPOSITO e SACO fora dos produtos', !JSON.stringify(casarDepois).includes('DEPOSITO') && !JSON.stringify(casarDepois).includes('SACO'))

// regressão: outros talões casam igual (ou melhor) ao que casavam
let iguais = 0, mudaram = []
for (const r of outros) {
  const d = (await q('select public._talao_casar_itens($1::jsonb, $2::jsonb) r', [JSON.stringify(r.items), JSON.stringify(r.lines)]))[0].r
  const a = antes[r.id]
  if (JSON.stringify(a.map((m) => [m.casou, m.base_talao_cents])) === JSON.stringify(d.map((m) => [m.casou, m.base_talao_cents]))) iguais++
  else mudaram.push({ loja: r.receipt_parsed_store, antes: a.map((m) => m.casou ? m.base_talao_cents : 'x'), depois: d.map((m) => m.casou ? m.base_talao_cents : 'x'), linhas: r.lines.map((l) => `${l.name}=${l.unit_price_cents}`).join(' | ').slice(0, 300) })
}
console.log(`Outros talões: ${iguais}/${outros.length} iguais; mudaram:`, JSON.stringify(mudaram, null, 1))

// robô do catálogo DEPOIS, preços antigos → sobe o Wrap e o BBQ, a caixa bate, nada absurdo
rid = await semearKfc([6.20, 6.07, 8.39])
const robDepois = (await q(`select public.catalog_price_update_from_receipt($1) r`, [rid]))[0].r
const propDepois = await q(`select product_id, old_base::text, new_base::text, status from catalog_price_updates order by product_id`)
console.log('Robô DEPOIS (preços antigos):', JSON.stringify(robDepois), JSON.stringify(propDepois))
check('robô: nenhuma proposta absurda (nada abaixo de 40% nem acima de 250%)',
  propDepois.every((p) => Number(p.new_base) >= Number(p.old_base) * 0.4 && Number(p.new_base) <= Number(p.old_base) * 2.5))
check('robô: Menu Wrap Coronel 6,07 → 8,45', propDepois.some((p) => p.old_base === '6.07' && p.new_base === '8.45'))
check('robô: Menu Kentucky BBQ 8,39 → 9,15', propDepois.some((p) => p.old_base === '8.39' && p.new_base === '9.15'))
rid = await semearKfc([6.20, 8.45, 9.15])
const robCerto = (await q(`select public.catalog_price_update_from_receipt($1) r`, [rid]))[0].r
check('robô com o catálogo já certo: 3 batem, 0 propostas', robCerto.ja_batiam === 3 && (await q('select count(*)::int n from catalog_price_updates'))[0].n === 0, robCerto)

// ── classificador ──
const casos = [
  ['Água sem Gás Alcalina pH 9,5 Monchique (emb. 6 x 1,5 lt)', 'Bebidas', 'continente-guarda', 'marcar', 6],
  ['Refrigerante Coca-Cola Original Lata (emb. 33 cl)', 'Bebidas', 'continente-guarda', 'marcar', 1],
  ['Cerveja Super Bock Mini (emb. 6 x 25 cl)', 'Bebidas', 'continente-guarda', 'duvidoso', 0],
  ['Cerveja Sagres Lata (emb. 24 x 33 cl)', 'Bebidas', 'continente-guarda', 'marcar', 24],
  ['Vinho Tinto Douro (emb. 75 cl)', 'Bebidas', 'continente-guarda', 'excluido', 0],
  ['Iogurte Líquido Manga e Papaia (emb. 640 gr (4 un))', 'Laticínios', 'continente-guarda', 'nao_bebida', 0],
  ['Leite Meio Gordo (emb. 1 lt)', 'Laticínios', 'continente-guarda', 'nao_bebida', 0], ['Bebida Láctea Ucal Lata 25cl', 'Bebidas', 'continente-guarda', 'excluido', 0], ['Água das Pedras 25cl', 'Bebidas', 'continente-guarda', 'duvidoso', 0],
  ['Água Luso 5 lt', 'Bebidas', 'continente-guarda', 'excluido', 0],
  ['Sumo de Laranja Compal Clássico (emb. 1 lt)', 'Bebidas', 'continente-guarda', 'duvidoso', 0],
  ['Ice Tea Lipton Manga 1,5 lt', 'Bebidas', 'continente-guarda', 'marcar', 1],
  ['Red Bull Energy Drink 25cl', 'Bebidas', 'kfc-guarda', 'marcar', 1],
  ['Pepsi Lata', null, 'kfc-guarda', 'marcar', 1],
  ['Água 50cl', null, 'kfc-guarda', 'marcar', 1],
  ['Coca-Cola Média', null, 'burgerking-guarda', 'excluido', 0],
  ['Coca-Cola Média', null, 'mcdonalds-guarda', 'excluido', 0],
  ['Whisky Johnnie Walker 70cl', 'Bebidas', 'continente-guarda', 'excluido', 0],
  ['Batata Frita Lays', 'Snacks', 'continente-guarda', 'nao_bebida', 0],
  ['Néctar de Pêssego Compal (emb. 6 x 20 cl) pacote', 'Bebidas', 'continente-guarda', 'excluido', 0],
]
for (const [nome, cat, loja, estado, units] of casos) {
  const r = (await q('select public.volta_classificar($1,$2,$3) r', [nome, cat, loja]))[0].r
  check(`classificar "${nome}" @${loja} = ${estado}/${units}`, r.estado === estado && r.units === units, r)
}

// ── depósito por linha (produto + opção do menu) ──
await db.exec(`
  insert into platform_settings values ('volta_deposit_cents','10'),('volta_deposit_enabled','true') on conflict (key) do update set value = excluded.value;
  insert into products (id, restaurant_id, name, price) values ('cont-agua6','continente-guarda','Água 6x1,5',4.2),('kfc-menu','kfc-guarda','Menu Wrap',8.45);
  update products set deposit_units = 6 where id = 'cont-agua6';
  insert into product_option_groups values ('g1','kfc-menu','Escolha a Bebida');
  insert into product_option_items (id, group_id, name, price_add, deposit_units) values ('o1','g1','Pepsi Lata',0,1),('o2','g1','Água 50cl',0,1),('o3','g1','Sem bebida',0,0);
`)
const dep = (await q(`select units, items from public.volta_deposito_itens($1::jsonb)`, [JSON.stringify([
  { productId: 'cont-agua6', name: 'Água', quantity: 2, deposit_units: 0 },
  { productId: 'kfc-menu', name: 'Menu Wrap', quantity: 3, selected_options: [{ group: 'Escolha a Bebida', items: ['Pepsi Lata'] }] },
  { productId: 'kfc-menu', name: 'Menu Wrap', quantity: 1, selected_options: [{ group: 'Escolha a Bebida', items: ['Sem bebida'] }] },
  { productId: 'nao-existe', name: 'X', quantity: 1 },
])]))[0]
check('volta_deposito_itens: 2 packs de 6 + 3 menus com lata = 15 embalagens', dep.units === 15, dep.units)
check('volta_deposito_itens: por linha 12/3/0/0 e cêntimos 120/30/0/0',
  JSON.stringify(dep.items.map((i) => [i.deposit_units, i.deposit_cents])) === JSON.stringify([[12, 120], [3, 30], [0, 0], [0, 0]]), dep.items.map((i) => [i.deposit_units, i.deposit_cents]))

// ── recibo do cliente com a linha do depósito ──
await db.exec(`insert into orders (id, status, service_type, items, delivery_fee, deposit_cents, deposit_ajuste_cents, price, final_total, is_purchase_finalized, vendor_name)
  values ('rec-1','delivered','storeShopping','[{"name":"Água","quantity":1,"price":4.83}]',2.5,60,20,8.13,8.33,true,'Continente')`)
const rec = (await q(`select public._recibo_pedido('rec-1') r`))[0].r
const linhaDep = (rec.linhas || []).find((l) => String(l.nome).startsWith('Depósito Volta'))
check('recibo do cliente: linha "Depósito Volta (8 emb.)" = 80 cênt.', linhaDep?.valor_cents === 80 && linhaDep?.nome === 'Depósito Volta (8 emb.)', linhaDep)

// ── PARTE 2 (dinheiro): âncoras e compilação nas definições reais ──
for (const n of ['_create_order_core', 'quote_order_pricing', 'fn_award_tokens_on_delivery', 'post_order_to_ledger',
  'compute_partner_weekly_settlement', 'finalizar_talao_nao_parceiro', 'enforce_financial_immutability']) {
  try { await db.exec(lerFn(n) + ';') } catch (e) { falhas.push('carregar ' + n + ': ' + e.message) }
}
const md = fs.readFileSync(M3MD, 'utf8')
const sql3 = md.split('```sql')[1].split('```')[0]
try {
  await db.exec(sql3)
  ok.push('PARTE 2 aplica sem erros (todas as âncoras = 1, 7 funções de dinheiro compilam)')
} catch (e) {
  falhas.push('PARTE 2 falhou: ' + e.message)
}
const defs = Object.fromEntries((await q(`select proname, pg_get_functiondef(oid) d from pg_proc where proname in
  ('_create_order_core','quote_order_pricing','fn_award_tokens_on_delivery','post_order_to_ledger','compute_partner_weekly_settlement','finalizar_talao_nao_parceiro','enforce_financial_immutability')`)).map((r) => [r.proname, r.d]))
check('create_order: depósito fora do subtotal, tecto dos tokens sem ele, colunas no INSERT',
  /volta_deposito_itens\(v_items_enriched\)/.test(defs._create_order_core) && /v_customer_total - v_dep_cents/.test(defs._create_order_core) && /v_dep_units, v_dep_cents\n  \);/.test(defs._create_order_core))
check('quote: devolve deposit_cents', /'deposit_cents', v_dep_cents/.test(defs.quote_order_pricing))
check('tokens sem o depósito', /NEW.price - \(COALESCE\(NEW.deposit_cents/.test(defs.fn_award_tokens_on_delivery))
check('livro-razão: deposit_volta', /'deposit_volta', 'deposit_volta'/.test(defs.post_order_to_ledger))
check('acerto do parceiro: + v_deposit', /v_share \+ v_deposit - v_cash_partner/.test(defs.compute_partner_weekly_settlement))
check('finalizar: depósito dos "Não há"', /v_unavailable_cents := v_unavailable_cents \+ v_dep_falta_cents/.test(defs.finalizar_talao_nao_parceiro))
check('imutabilidade: colunas do depósito', /NEW.deposit_cents        IS DISTINCT FROM OLD.deposit_cents/.test(defs.enforce_financial_immutability))
// o resto das funções ficou igual: tirar as linhas acrescentadas dá o original
const bkp = Object.fromEntries((await q(`select nome, definicao from bkp_fn_volta_20261109`)).map((r) => [r.nome, r.definicao]))
check('cópias guardadas em bkp_fn_volta_20261109', ['_create_order_core', 'quote_order_pricing', 'post_order_to_ledger'].every((n) => bkp[n]?.length > 100))

// gate: a app antiga (sem deposit_units nos itens) não paga depósito
const g1 = (await q(`select public.volta_app_mostra_deposito('{"items":[{"productId":"a","quantity":1}]}') r`))[0].r
const g2 = (await q(`select public.volta_app_mostra_deposito('{"items":[{"productId":"a","quantity":1,"deposit_units":0}]}') r`))[0].r
check('app antiga (sem a chave) não cobra; app nova (com a chave) cobra', g1 === false && g2 === true)

// ── fecho do talão pelo robô ──
await db.exec(`insert into products (id, restaurant_id, name, category, price) values ('cont-sagres','continente-guarda','Cerveja Sagres Lata (emb. 33 cl)','Bebidas',0.89)`)
async function pedido(id, metodo, status, depCents, items, parceiro = false) {
  await db.query(`insert into orders (id, user_id, status, payment_method, service_type, is_partner_store, restaurant_id,
     cash_total_due, final_total, price, items, deposit_cents) values ($1, '00000000-0000-0000-0000-000000000001', $2, $3,
     'storeShopping', $4, 'continente-guarda', $5, 10, 10, $6, $7)`,
    [id, status, metodo, parceiro, metodo === 'cash' ? 10 : null, JSON.stringify(items), depCents])
  return (await q(`insert into order_receipts_v2 (order_id, receipt_parsed) values ($1, '{}') returning id`, [id]))[0].id
}
const linhas = (dep) => ({ lines: [{ name: 'CERVEJA SAGRES LT', qty: 2, unit_price_cents: 89 }, ...(dep ? [{ name: 'DEPOSITO', qty: dep, unit_price_cents: 10 }] : [])] })
const itensSagres = [{ productId: 'cont-sagres', name: 'Cerveja Sagres Lata', quantity: 2 }]
// a) dinheiro, ainda por entregar, pedido cobrou 0 e o talão traz 2 DEPOSITO → +0,20 no que o estafeta cobra
let r1 = await pedido('t-cash', 'cash', 'onTheWay', 0, itensSagres)
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify(linhas(2))])
let o = (await q(`select cash_total_due::text, final_total::text, deposit_ajuste_cents, deposit_from_receipt_cents from orders where id='t-cash'`))[0]
check('talão +2 DEPOSITO (dinheiro por entregar): cash_total_due 10 → 10,20', o.cash_total_due === '10.20' && o.deposit_ajuste_cents === 20 && o.deposit_from_receipt_cents === 20, o)
const marcado = (await q(`select deposit_units, deposit_review, deposit_origem from products where id='cont-sagres'`))[0]
check('produto que gerou o depósito fica marcado (1 lata por unidade, origem talao)', marcado.deposit_units === 1 && marcado.deposit_origem === 'talao', marcado)
// repetir a leitura do mesmo talão não cobra duas vezes
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify({ ...linhas(2), store: 'Continente' })])
o = (await q(`select cash_total_due::text, deposit_ajuste_cents from orders where id='t-cash'`))[0]
check('ler o mesmo talão outra vez não cobra duas vezes', o.cash_total_due === '10.20' && o.deposit_ajuste_cents === 20, o)
// b) cartão: dívida na carteira
await db.exec(`update products set deposit_units = 0, deposit_review = false, deposit_origem = null where id='cont-sagres'`)
r1 = await pedido('t-card', 'card', 'onTheWay', 0, itensSagres)
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify(linhas(2))])
const wt = await q(`select amount_cents, kind, reason from wallet_transactions where related_order_id='t-card'`)
check('talão +2 DEPOSITO (cartão): dívida de 20 cênt. na carteira', wt.length === 1 && wt[0].amount_cents === -20 && wt[0].kind === 'debit', wt)
// c) dinheiro, pedido cobrou 0,60 e o talão só traz 2 → devolve 0,40 no que o estafeta cobra
r1 = await pedido('t-menos', 'cash', 'onTheWay', 60, itensSagres)
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify(linhas(2))])
o = (await q(`select cash_total_due::text, deposit_ajuste_cents from orders where id='t-menos'`))[0]
check('talão com MENOS depósito (dinheiro): cash_total_due 10 → 9,60', o.cash_total_due === '9.60' && o.deposit_ajuste_cents === -40, o)
// d) MB Way já entregue com MENOS → crédito na carteira
r1 = await pedido('t-mbway', 'mbway', 'delivered', 30, itensSagres)
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify(linhas(0))])
const wt2 = await q(`select amount_cents, kind from wallet_transactions where related_order_id='t-mbway'`)
check('talão sem depósito num pedido que cobrou 0,30 (MB Way): +30 cênt. na carteira', wt2.length === 1 && wt2[0].amount_cents === 30 && wt2[0].kind === 'refund_credit_free', wt2)
// e) loja parceira: nada
r1 = await pedido('t-parc', 'cash', 'onTheWay', 0, itensSagres, true)
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify(linhas(2))])
o = (await q(`select cash_total_due::text, deposit_ajuste_cents from orders where id='t-parc'`))[0]
check('loja parceira: o talão não mexe no depósito', o.cash_total_due === '10' && o.deposit_ajuste_cents === 0, o)
// f) diferença absurda (> 10 €) não se aplica sozinha
r1 = await pedido('t-grande', 'cash', 'onTheWay', 0, itensSagres)
await db.query(`update order_receipts_v2 set receipt_parsed = $2 where id = $1`, [r1, JSON.stringify({ lines: [{ name: 'DEPOSITO', qty: 200, unit_price_cents: 10 }] })])
o = (await q(`select cash_total_due::text, deposit_ajuste_cents from orders where id='t-grande'`))[0]
const av = await q(`select event_type from admin_notifications where entity_id='t-grande'`)
check('diferença > 10 €: não aplica, avisa o admin', o.cash_total_due === '10' && av.some((a) => a.event_type === 'volta_talao_diferenca_grande'), { o, av })
// g) linhas KFC: "2 DEPOSITO 10" lidas como 20 cêntimos
const kfcDep = (await q(`select coalesce(sum(round(coalesce((l->>'qty')::numeric,1)*coalesce((l->>'unit_price_cents')::numeric,0))),0)::int n
  from jsonb_array_elements($1::jsonb) l where public._talao_e_deposito(l->>'name')`, [JSON.stringify(kfc.lines)]))[0].n
check('talão do KFC de hoje: depósito lido = 20 cênt. (2 latas de Ice Tea)', kfcDep === 20, kfcDep)
const contDep = (await q(`select public._talao_e_deposito('VALOR DE DEPOSITO 6U') a, public._talao_e_deposito('FRANGO ASSADO EMB. KG C/MOLHO') b, public._talao_e_deposito('VASILHAME') c`))[0]
check('"VALOR DE DEPOSITO 6U" e "VASILHAME" são depósito; "FRANGO ASSADO EMB." não', contDep.a && !contDep.b && contDep.c, contDep)

console.log('\n=== OK (' + ok.length + ') ===\n' + ok.join('\n'))
console.log('\n=== FALHAS (' + falhas.length + ') ===\n' + falhas.join('\n'))
process.exit(falhas.length ? 1 : 0)
