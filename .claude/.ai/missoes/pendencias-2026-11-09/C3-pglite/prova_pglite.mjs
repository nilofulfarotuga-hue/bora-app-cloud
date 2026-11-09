// Prova do C3 (pendencias-2026-11-09) em PGlite: definições de PRODUÇÃO (md5 igual ao ar),
// dados reais do talão BK a244493e e do pedido 56fa8623, migração 20261109214000 tal e qual.
import fs from 'node:fs';
import { PGlite } from './node_modules/@electric-sql/pglite/dist/index.js';
import { pg_trgm } from './node_modules/@electric-sql/pglite/dist/contrib/pg_trgm.js';

const AQUI = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MIG = process.argv[2];
const VOLTA = process.argv[3];
const defs = fs.readFileSync(AQUI + 'defs_prod.sql', 'utf8');
const migSql = fs.readFileSync(MIG, 'utf8');
const voltaSql = VOLTA && fs.existsSync(VOLTA) ? fs.readFileSync(VOLTA, 'utf8') : null;

const REC = 'a244493e-5a85-4e20-ae01-ed6e20ebab62';
const ORD = '56fa8623-dd4d-4ae6-86b0-96679f20fbf8';
const MENU = 'bk-078771af-f4cb-451a-b645-3738400175df';
const BACON = MENU + '-g4-i7';
const LINES = [
  { qty: 1, name: '3C Whopper', unit_price_cents: 0 }, { qty: 1, name: 'Tripwhopper', unit_price_cents: 947 },
  { qty: 1, name: 'EXTRA BACON 2 FATIAS', unit_price_cents: 250 }, { qty: 1, name: 'Com Cebola', unit_price_cents: 0 },
  { qty: 1, name: 'Batatas Media', unit_price_cents: 265 }, { qty: 1, name: 'Cola Media', unit_price_cents: 33 },
  { qty: 1, name: '3C Whopper', unit_price_cents: 0 }, { qty: 1, name: 'Tripwhopper', unit_price_cents: 947 },
  { qty: 1, name: 'EXTRA BACON 2 FATIAS', unit_price_cents: 250 }, { qty: 1, name: 'Com Pepino', unit_price_cents: 0 },
  { qty: 1, name: 'Extra Alface', unit_price_cents: 0 }, { qty: 1, name: 'Patatas Supreme M PT', unit_price_cents: 265 },
  { qty: 1, name: 'Cola Zero Media', unit_price_cents: 33 }, { qty: 1, name: 'Saco de Papel', unit_price_cents: 5 },
];
const item = (bebida, acomp, acompAdd, extras) => ({
  name: 'Triple Whopper Spicy Menu', quantity: 1, basePrice: 13.25, productId: MENU, purchaseStatus: 'pending',
  selected_options_priced: [
    { group: 'Bebidas', items: [{ name: bebida, price_add: 0.08 }] },
    { group: 'Acompanhamentos', items: [{ name: acomp, price_add: acompAdd }] },
    { group: 'Adiciona extras Triple Whopper Spicy', items: extras },
    { group: 'Carne', items: [{ name: 'Triple Whopper Spicy', price_add: 0 }] },
  ],
});
const ITEMS = [
  item('Coca Cola®', 'Batatas Fritas Clássicas', 0, [{ name: 'EXTRA Cebola', price_add: 0 }, { name: 'EXTRA Bacon', price_add: 0.91 }]),
  item('Coca Cola Zero®', 'Batatas Supreme King Mix', 0.5,
    [{ name: 'EXTRA Alface', price_add: 0 }, { name: 'EXTRA Picles', price_add: 0 }, { name: 'EXTRA Bacon', price_add: 0.91 }]),
];
const G4 = [['i0', 'EXTRA Bacon+Queijo', 1.65], ['i1', 'EXTRA Carne whopper®', 2.15], ['i2', 'EXTRA Cebola', 0], ['i3', 'EXTRA Ketchup', 0],
  ['i4', 'EXTRA Tomate', 0], ['i5', 'EXTRA Alface', 0], ['i6', 'EXTRA Picles', 0], ['i7', 'EXTRA Bacon', 0.91], ['i8', 'EXTRA Queijo', 0.74],
  ['i9', 'EXTRA Molho Sriracha', 0]];

const BASE = `
create schema extensions; create extension pg_trgm schema extensions;
create or replace function extensions.unaccent(t text) returns text language sql immutable as
$$ select translate(t, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC') $$;
create schema auth;
create function auth.jwt() returns jsonb language sql stable as $$ select nullif(current_setting('request.jwt.claims', true), '')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
create function public._admin_op_guard() returns table(admin_id uuid, admin_email text) language plpgsql as $$
begin
  if auth.uid() is null then raise exception 'admin_required: not authenticated'; end if;
  if (auth.jwt()->'app_metadata'->>'role') is distinct from 'admin' then raise exception 'admin_required'; end if;
  return query select auth.uid(), null::text;
end $$;
create function public.log_admin_action(a text, b text, c text, d jsonb) returns void language sql as $$ select $$;
create table platform_settings(key text primary key, value jsonb);
create table order_receipts_v2(id uuid primary key, order_id text, receipt_parsed jsonb);
create table orders(id text primary key, restaurant_id text, is_partner_store boolean, items jsonb);
create table order_purchase_items_v2(order_id text, status text, original_name text);
create table products(id text primary key, name text, price numeric, restaurant_id text);
create table product_option_groups(id text primary key, product_id text, name text);
create table product_option_items(id text primary key, group_id text, name text, price_add numeric, is_available boolean default true);
create table catalog_price_updates(id uuid primary key default gen_random_uuid(), product_id text, restaurant_id text, order_id text,
  receipt_id uuid, old_base numeric, new_base numeric, confianca numeric, linha_talao text, status text,
  created_at timestamptz default now(), decided_at timestamptz, decided_by text);
create table admin_notifications(id uuid primary key default gen_random_uuid(), event_type text, severity text, entity_type text,
  entity_id text, summary text, payload jsonb, created_at timestamptz default now());
`;

async function novaBase() {
  const db = new PGlite({ extensions: { pg_trgm } });
  await db.exec(BASE);
  for (const d of defs.split(/^-- @@FN \S+\n/m).filter((x) => x.trim())) await db.exec(d);
  await db.query(`insert into platform_settings values ('catalog_price_live_update_enabled', 'true'::jsonb)`);
  await db.query(`insert into order_receipts_v2 values ($1, $2, $3)`, [REC, ORD, JSON.stringify({ lines: LINES, store: 'Burger King' })]);
  await db.query(`insert into orders values ($1, 'burgerking-guarda', false, $2)`, [ORD, JSON.stringify(ITEMS)]);
  await db.query(`insert into products values ($1, 'Triple Whopper Spicy Menu', 13.25, 'burgerking-guarda')`, [MENU]);
  for (const [g, n] of [['g0', 'Carne'], ['g1', 'Acompanhamentos'], ['g2', 'Bebidas'], ['g4', 'Adiciona extras Triple Whopper Spicy']])
    await db.query(`insert into product_option_groups values ($1, $2, $3)`, [MENU + '-' + g, MENU, n]);
  for (const [i, n, p] of G4) await db.query(`insert into product_option_items(id, group_id, name, price_add) values ($1, $2, $3, $4)`,
    [MENU + '-g4-' + i, MENU + '-g4', n, p]);
  await db.query(`insert into product_option_items(id, group_id, name, price_add) values
    ($1, $2, 'Coca Cola®', 0.08), ($3, $2, 'Coca Cola Zero®', 0.08), ($4, $5, 'Batatas Fritas Clássicas', 0), ($6, $5, 'Batatas Supreme King Mix', 0.5)`,
    [MENU + '-g2-i9', MENU + '-g2', MENU + '-g2-i1', MENU + '-g1-i3', MENU + '-g1', MENU + '-g1-i8']);
  return db;
}
const one = async (db, sql, p = []) => (await db.query(sql, p)).rows[0];
const all = async (db, sql, p = []) => (await db.query(sql, p)).rows;
const temOpcao = async (db) => !!(await one(db, `select 1 x from information_schema.columns where table_name='catalog_price_updates' and column_name='option_item_id'`));
const linhas = async (db) => all(db, `select product_id produto, old_base::text old, new_base::text new, status, linha_talao linha,
   ${(await temOpcao(db)) ? 'option_item_id' : 'null'} opcao, confianca::text conf from catalog_price_updates where receipt_id = $1 order by created_at, linha_talao`, [REC]);
const precos = async (db) => one(db, `select (select price::text from products where id=$1) menu, (select price_add::text from product_option_items where id=$2) bacon,
   (select md5(string_agg(id||':'||price_add::text, ',' order by id)) from product_option_items) opcoes`, [MENU, BACON]);
const robo = async (db) => { const r = (await one(db, `select public.catalog_price_update_from_receipt($1) r`, [REC])).r; delete r.extras_mais_caros_detalhe; return r; };
const fnmd5 = async (db) => one(db, `select md5(pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure)) robo,
   md5(pg_get_functiondef('public.admin_approve_catalog_price_update(uuid)'::regprocedure)) aprovar`);
const curto = (r) => ({ ...r, extras_mais_caros: (r.extras_mais_caros || []).length });

async function cenario(db, nome, menu12) {
  await db.exec('begin');
  if (menu12) await db.query(`update products set price = 12.00 where id = $1`, [MENU]);
  const antes = await precos(db);
  const r = await robo(db);
  const out = { nome, res: curto(r), linhas: await linhas(db), precos_antes: antes, precos_depois: await precos(db),
    aviso_extra: (await one(db, `select count(*)::int n from admin_notifications where event_type='catalogo_extra_mais_caro'`)).n };
  if (await temOpcao(db)) {
    // aprovar no painel (admin simulado): a linha do extra e a linha do produto
    await db.query(`select set_config('request.jwt.claims', $1, true)`,
      [JSON.stringify({ sub: '00000000-0000-0000-0000-0000000000c3', role: 'authenticated', app_metadata: { role: 'admin' } })]);
    const ex = await one(db, `select id from catalog_price_updates where receipt_id=$1 and option_item_id is not null`, [REC]);
    if (ex) {
      out.aprovar_extra = (await one(db, `select public.admin_approve_catalog_price_update($1) r`, [ex.id])).r;
      out.estado_extra = (await one(db, `select status from catalog_price_updates where id=$1`, [ex.id])).status;
      out.precos_apos_aprovar_extra = await precos(db);
    }
    const r2 = await robo(db);
    out.segunda_corrida = { extras_pendentes: r2.extras_pendentes,
      linhas_extra: (await one(db, `select count(*)::int n from catalog_price_updates where receipt_id=$1 and option_item_id is not null`, [REC])).n };
    const pr = await one(db, `select id from catalog_price_updates where receipt_id=$1 and option_item_id is null and status='pending' limit 1`, [REC]);
    if (pr) {
      out.aprovar_produto = (await one(db, `select public.admin_approve_catalog_price_update($1) r`, [pr.id])).r;
      out.precos_apos_aprovar_produto = await precos(db);
    }
  }
  await db.exec('rollback');
  return out;
}

const res = {};
let db = await novaBase();
res.inicio = { ...(await precos(db)), fn: await fnmd5(db) };
res.A_antes = await cenario(db, 'antes', false);
res.B_antes_menu12 = await cenario(db, 'antes, menu a 12,00', true);
await db.exec(migSql);
const m1 = await fnmd5(db);
await db.exec(migSql);
const m2 = await fnmd5(db);
res.C_migracao = { md5_1: m1, md5_2: m2, idempotente: JSON.stringify(m1) === JSON.stringify(m2), coluna: await temOpcao(db),
  bkp: await all(db, `select nome, md5(definicao) md5 from bkp_fn_robo_extras_20261109 order by nome`) };
res.D_depois = await cenario(db, 'depois', false);
res.E_depois_menu12 = await cenario(db, 'depois, menu a 12,00', true);
res.fim = await precos(db);
await db.close();

// Ordem com a migração da sessão paralela (volta-deposito-kfc): secção "4. Robô do talão" dela.
if (voltaSql) {
  const ini = voltaSql.indexOf('-- ── 4. Robô do talão');
  const fim = voltaSql.indexOf('-- ── 5.');
  const parte = voltaSql.slice(ini, fim);
  for (const ordem of ['volta_depois_c3', 'c3_depois_volta']) {
    const d2 = await novaBase();
    const out = { ordem };
    try {
      if (ordem === 'volta_depois_c3') { await d2.exec(parte); await d2.exec(migSql); }
      else { await d2.exec(migSql); await d2.exec(parte); }
      const def = (await one(d2, `select pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure) d`)).d;
      out.tem_volta = def.includes('v_absurdas'); out.tem_c3 = def.includes('extras_pendentes');
      out.cenario = await cenario(d2, ordem, false);
    } catch (e) { out.erro = String(e.message || e); }
    res['F_' + ordem] = out;
    await d2.close();
  }
}
console.log(JSON.stringify(res, null, 1));
