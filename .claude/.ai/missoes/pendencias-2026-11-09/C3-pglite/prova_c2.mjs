import fs from 'node:fs';
import { PGlite } from './node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
await db.exec(`create table products(id text primary key, name text, price numeric, restaurant_id text);
create table product_option_groups(id text primary key, product_id text, name text);
create table product_option_items(id text primary key, group_id text, name text, price_add numeric, is_available boolean default true, sort_order int, created_at timestamptz default now());
insert into products values ('bk-a','Whopper',7.35,'burgerking-guarda'),('bk-b','Menu Whopper',8.75,'burgerking-guarda'),('kfc-x','Zinger',6,'kfc-guarda');
insert into product_option_groups values ('bk-a-g1','bk-a','Adiciona extras Whopper'),('bk-b-g4','bk-b','Adiciona extras Whopper'),('kfc-x-g1','kfc-x','Extras');
insert into product_option_items(id,group_id,name,price_add) values ('bk-a-g1-i8','bk-a-g1','EXTRA Bacon',0.91),('bk-a-g1-i9','bk-a-g1','EXTRA Queijo',0.74),
 ('bk-b-g4-i1','bk-b-g4','EXTRA Bacon',0.91),('bk-b-g4-i2','bk-b-g4','EXTRA Bacon',1.50),('kfc-x-g1-i1','kfc-x-g1','EXTRA Bacon',0.91);`);
const sql = fs.readFileSync(process.argv[2], 'utf8');
const r = await db.exec(sql);
for (const x of r) if (x.rows?.length) console.log(JSON.stringify(x.rows));
console.log('depois', JSON.stringify((await db.query(`select id, price_add::text from product_option_items order by id`)).rows));
// segunda corrida: idempotente (não muda nada, cópia original fica)
const r2 = await db.exec(sql);
console.log('2a corrida mudou', JSON.stringify(r2.filter(x=>x.rows?.length)[1]?.rows), 'bkp bacon', JSON.stringify((await db.query(`select id, price_add::text from bkp_products_bk_extras_20261109 order by id`)).rows));
