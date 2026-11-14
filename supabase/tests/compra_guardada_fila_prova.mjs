// Prova local (PGlite = Postgres real em WASM) da migração
// 20261114190000_compra_guardada_e_fila_estafeta.sql — compra-guardada-2026-11-14.
//
// Porquê local: a tranca recusa DDL em produção (apply_migration e DO+EXECUTE),
// mesmo em rollback. Aqui aplica-se a migração TAL COMO ESTÁ sobre réplicas
// mínimas de auth/vault/net/orders/drivers e corre-se cada regra.
//
// Uso: node supabase/tests/compra_guardada_fila_prova.mjs <pasta-com-node_modules-do-pglite>
//   (npm install @electric-sql/pglite@0.2.17 nessa pasta)

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const pastaPglite = process.argv[2];
if (!pastaPglite) {
  console.error('falta a pasta do pglite');
  process.exit(2);
}
const require = createRequire(path.join(path.resolve(pastaPglite), 'x.js'));
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href);
let migracao = readFileSync(
  path.join(aqui, '..', 'migrations', '20261114190000_compra_guardada_e_fila_estafeta.sql'),
  'utf8',
);
// Teste anti-mentira: MUTACAO="texto=>outro" estraga a migração de propósito;
// a prova TEM de falhar.
if (process.env.MUTACAO) {
  const [de, para] = process.env.MUTACAO.split('=>');
  if (!migracao.includes(de)) throw new Error(`mutação não encontrada: ${de}`);
  migracao = migracao.split(de).join(para);
  console.log(`MUTAÇÃO aplicada: ${de} => ${para}`);
}

const db = new PGlite();
let falhas = 0;
let ok = 0;
const certo = (nome, cond, detalhe = '') => {
  if (cond) {
    ok++;
    console.log(`  OK  ${nome}`);
  } else {
    falhas++;
    console.log(`  FALHOU  ${nome} ${detalhe}`);
  }
};
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const um = async (sql, params = []) => (await q(sql, params))[0];
const como = async (uid) =>
  db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid ?? '']);

// ── réplicas mínimas do Supabase ──────────────────────────────────────────
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin;
  create schema auth; create schema vault; create schema net;
  create table auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}');
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table vault.decrypted_secrets (name text, decrypted_secret text);
  insert into vault.decrypted_secrets values ('project_url', 'https://exemplo.supabase.co');
  create table net.chamadas (url text, body jsonb);
  create function net.http_post(url text, headers jsonb, body jsonb) returns bigint
    language sql as $$ insert into net.chamadas values (url, body); select 1::bigint $$;

  create table public.drivers (id uuid primary key, user_id uuid, name text);
  create table public.orders (
    id text primary key, user_id uuid, status text, service_type text,
    is_partner_store boolean default false, assigned_driver_id text,
    is_purchase_finalized boolean default false, items jsonb default '[]',
    restaurant_id text, vendor_name text, customer_name text, errand_speed text,
    driver_assigned_at timestamptz, created_at timestamptz default now(),
    payment_method text default 'cash');
  create table public.in_app_notifications (user_id uuid, kind text, title text, body text, related_id text);

  create function public.is_admin() returns boolean language sql stable as $$
    select exists (select 1 from auth.users u where u.id = auth.uid()
                   and coalesce(u.raw_app_meta_data->>'role','') = 'admin') $$;
  create function public.is_demo_user(uuid) returns boolean language sql as $$ select false $$;
  create function public._service_role_key() returns text language sql as $$ select 'chave' $$;
  create function public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text,
      p_body text default null, p_related_id text default null) returns uuid language plpgsql as $$
    begin insert into public.in_app_notifications values (p_user_id, p_kind, p_title, p_body, p_related_id);
          return gen_random_uuid(); end $$;
`);

const ADMIN = '00000000-0000-0000-0000-0000000000ad';
const EST = '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7'; // o estafeta de 14/11
const EST_DRIVERS_ID = '11111111-1111-1111-1111-111111111111';
const OUTRO = '22222222-2222-2222-2222-222222222222';
const CLIENTE = '33333333-3333-3333-3333-333333333333';
await db.query(`insert into auth.users values ($1,'admin@x', '{"role":"admin"}'), ($2,'e@x','{}'), ($3,'o@x','{}'), ($4,'c@x','{}')`,
  [ADMIN, EST, OUTRO, CLIENTE]);
await db.query(`insert into public.drivers values ($1, $2, 'Estafeta Teste'), ($3, $3, 'Outro')`,
  [EST_DRIVERS_ID, EST, OUTRO]);

// ── a migração, tal como está no repo ─────────────────────────────────────
await db.exec(migracao);
console.log('migração aplicada no PGlite');

const itensAuchan = JSON.stringify([
  { productId: 'p-pizza', name: 'Pizza 4 queijos', price: 3.45, quantity: 2 },
  { productId: 'p-queijo', name: 'Queijo ralado', price: 1.15, quantity: 1 },
  { productId: 'p-leite', name: 'Leite', price: 0.92, quantity: 6 },
  { productId: 'p-pizza', name: 'Pizza 4 queijos (sem cebola)', price: 3.45, quantity: 1 },
]);
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, items, restaurant_id, vendor_name, customer_name, driver_assigned_at)
  values ('auchan', $1, 'driverAccepted', 'storeShopping', $2, $3, 'auchan-guarda', 'Auchan', 'Cliente A', '2026-11-14T14:52:00Z')`,
  [CLIENTE, EST, itensAuchan]);

console.log('\n1) gravar o progresso');
await como(EST);
const itens = JSON.stringify({
  'p-pizza#0': { s: 'unavailable', q: 2 }, 'p-queijo#0': { s: 'unavailable', q: 1 },
  'p-leite#0': { s: 'bought', q: 6 }, 'p-pizza#1': { s: 'pending', q: 1 },
});
const extras = JSON.stringify([
  { id: 'extra_1', nome: 'Pizza margarita', preco_cents: 299, qtd: 2, s: 'bought' },
  { id: 'extra_2', nome: 'Desmarcado', preco_cents: 100, qtd: 1, s: 'pending' },
]);
let r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', $1, $2, 3, null, null, 100) r`, [itens, extras])).r;
certo('estafeta atribuído grava', r.ok === true && r.applied === true && r.marcados === 3, JSON.stringify(r));
let linha = await um(`select * from public.order_purchase_drafts where order_id='auchan'`);
certo('linha no servidor com 3 marcados, 3 sacos, seq 100', linha.marcados === 3 && linha.bag_count === 3 && Number(linha.client_seq) === 100);

r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', '{}'::jsonb, null, null, null, null, 50) r`)).r;
linha = await um(`select * from public.order_purchase_drafts where order_id='auchan'`);
certo('gravação atrasada (seq 50) não apaga a nova', r.applied === false && r.stale === true && linha.marcados === 3);

r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', $1, $2, 3, null, null, 100) r`, [itens, extras])).r;
certo('repetir o mesmo seq (rede repetiu) é aceite sem estragar', r.applied === true && r.marcados === 3);

r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', null, null, null, 2345, 'receipts/auchan/1.jpg', 101) r`)).r;
linha = await um(`select * from public.order_purchase_drafts where order_id='auchan'`);
certo('talão (valor+foto) entra sem apagar os itens', r.applied && linha.receipt_total_cents === 2345 &&
  linha.receipt_photo_path === 'receipts/auchan/1.jpg' && linha.marcados === 3 && linha.bag_count === 3);

console.log('\n2) quem pode e o que se recusa');
await como(OUTRO);
r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', '{}'::jsonb) r`)).r;
certo('outro estafeta: NOT_ASSIGNED_DRIVER', r.error === 'NOT_ASSIGNED_DRIVER');
await como(null);
r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', '{}'::jsonb) r`)).r;
certo('sem sessão: UNAUTHENTICATED', r.error === 'UNAUTHENTICATED');
await como(EST);
r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', '{"x#0":{"s":"roubado"}}'::jsonb) r`)).r;
certo('estado inválido: INVALID_PAYLOAD', r.error === 'INVALID_PAYLOAD');
r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', '[]'::jsonb) r`)).r;
certo('itens que não são objeto: INVALID_PAYLOAD', r.error === 'INVALID_PAYLOAD');
r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', null, null, 500) r`)).r;
certo('500 sacos: INVALID_BAG_COUNT', r.error === 'INVALID_BAG_COUNT');
r = (await um(`select public.estafeta_guardar_progresso_compra('nao-existe', '{}'::jsonb) r`)).r;
certo('pedido inexistente: ORDER_NOT_FOUND', r.error === 'ORDER_NOT_FOUND');

// drivers.id também conta como "atribuído" (a mesma regra do fecho)
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id) values ('via-drivers-id', $1, 'driverAccepted', 'storeShopping', $2)`, [CLIENTE, EST_DRIVERS_ID]);
r = (await um(`select public.estafeta_guardar_progresso_compra('via-drivers-id', '{}'::jsonb) r`)).r;
certo('estafeta atribuído pelo drivers.id também grava', r.ok === true);

console.log('\n3) ler o rascunho');
r = (await um(`select public.estafeta_ler_progresso_compra('auchan') r`)).r;
certo('estafeta lê o rascunho (sem driver_uid)', r.ok && r.rascunho.marcados === 3 && !('driver_uid' in r.rascunho));
await como(OUTRO);
r = (await um(`select public.estafeta_ler_progresso_compra('auchan') r`)).r;
certo('outro utilizador não lê', r.error === 'NOT_ASSIGNED_DRIVER');
await como(ADMIN);
r = (await um(`select public.estafeta_ler_progresso_compra('auchan') r`)).r;
certo('admin lê', r.ok === true);

console.log('\n4) itens para o fecho (mesmo formato de montarItens da app)');
const fecho = (await um(`select public._rascunho_compra_itens_fecho('auchan') r`)).r;
const esperado = [
  { original_item_id: 'p-pizza', original_name: 'Pizza 4 queijos', original_price_cents: 345, original_qty: 2, status: 'unavailable' },
  { original_item_id: 'p-queijo', original_name: 'Queijo ralado', original_price_cents: 115, original_qty: 1, status: 'unavailable' },
  { original_item_id: 'p-leite', original_name: 'Leite', original_price_cents: 92, original_qty: 6, status: 'purchased' },
  { original_item_id: 'p-pizza', original_name: 'Pizza 4 queijos (sem cebola)', original_price_cents: 345, original_qty: 1, status: 'purchased' },
  { original_name: 'Pizza margarita', original_price_cents: 0, original_qty: 2, status: 'added', actual_name: 'Pizza margarita', actual_price_cents: 299, actual_qty: 2 },
];
const norm = (a) => JSON.stringify(a.map((o) => Object.fromEntries(Object.entries(o).sort())));
certo('p_items igual ao da app (extra desmarcado fica de fora)', norm(fecho) === norm(esperado), JSON.stringify(fecho));

r = (await um(`select public.admin_rascunho_compra('auchan') r`)).r;
certo('admin_rascunho_compra: itens com estado e hora', r.ok && r.itens.length === 4 && r.itens[0].estado === 'unavailable'
  && r.itens[3].estado === 'pending' && r.ultima_marcacao && r.total_talao_cents === 2345);
await como(EST);
let recusou = false;
try { await um(`select public.admin_rascunho_compra('auchan')`); } catch (e) { recusou = /FORBIDDEN/.test(e.message); }
certo('estafeta não abre o painel (FORBIDDEN)', recusou);

console.log('\n5) pedido fechado / compra fechada');
await db.exec(`update public.orders set is_purchase_finalized = true where id='auchan'`);
r = (await um(`select public.estafeta_guardar_progresso_compra('auchan', '{}'::jsonb, null, null, null, null, 999) r`)).r;
certo('compra já fechada: ok com finalized (não grava)', r.ok && r.finalized === true && r.applied === false);
await db.exec(`update public.orders set status='delivered' where id='via-drivers-id'`);
r = (await um(`select public.estafeta_guardar_progresso_compra('via-drivers-id', '{}'::jsonb) r`)).r;
certo('pedido entregue: ORDER_CLOSED', r.error === 'ORDER_CLOSED');
await db.exec(`update public.orders set is_purchase_finalized = false where id='auchan'`);

console.log('\n6) fila do estafeta (os mesmos cenários do teste Dart)');
const fila = async (uid) => (await q(`select order_id, posicao, estado from public.fila_do_estafeta($1)`, [uid]));
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, errand_speed, driver_assigned_at)
  values ('favor', $1, 'driverAccepted', 'errand', $2, 'normal', '2026-11-14T16:32:00Z')`, [CLIENTE, EST]);
let f = await fila(EST);
certo('14/11: Auchan ativo, Favor em espera', JSON.stringify(f) === JSON.stringify([
  { order_id: 'auchan', posicao: 1, estado: 'ativo' }, { order_id: 'favor', posicao: 2, estado: 'em_espera' }]), JSON.stringify(f));

await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, errand_speed, restaurant_id, driver_assigned_at) values
  ('entrega', $1, 'driverAccepted', 'restaurant', $2, null, 'kfc', '2026-11-14T16:40:00Z'),
  ('urgente', $1, 'driverAccepted', 'errand', $2, 'express', null, '2026-11-14T16:45:00Z'),
  ('mesma-loja', $1, 'driverAccepted', 'storeShopping', $2, null, 'auchan-guarda', '2026-11-14T16:50:00Z')`, [CLIENTE, EST]);
f = await fila(EST);
certo('urgente logo a seguir; entrega; Favor normal no fim; mesma loja ativa',
  f.map((x) => `${x.order_id}:${x.estado}`).join(',') ===
  'auchan:ativo,mesma-loja:ativo,urgente:em_espera,entrega:em_espera,favor:em_espera', JSON.stringify(f));

await db.exec(`update public.orders set status='delivered' where id in ('auchan','mesma-loja')`);
f = await fila(EST);
certo('entregou: o urgente abre, os outros esperam', f.map((x) => `${x.order_id}:${x.estado}`).join(',') ===
  'urgente:ativo,entrega:em_espera,favor:em_espera', JSON.stringify(f));
let emCurso = await um(`select order_id from public.estafeta_pedido_em_curso where driver_uid=$1`, [EST]);
certo('em curso guardado passou ao urgente', emCurso?.order_id === 'urgente', JSON.stringify(emCurso));
await db.exec(`update public.orders set status='pickedUp' where id='entrega'`);
f = await fila(EST);
certo('recolhido nunca se esconde (fica ativo ao lado do em curso)', f[0].order_id === 'urgente' &&
  f.map((x) => `${x.order_id}:${x.estado}`).join(',') === 'urgente:ativo,entrega:ativo,favor:em_espera', JSON.stringify(f));

// Favor JÁ em curso e uma entrega aceite depois: a entrega espera pelo Favor
const TERCEIRO = '44444444-4444-4444-4444-444444444444';
await db.query(`insert into auth.users values ($1,'t@x','{}')`, [TERCEIRO]);
await db.query(`insert into public.drivers values ($1, $1, 'Terceiro')`, [TERCEIRO]);
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, errand_speed)
  values ('t-favor', $1, 'callingDriver', 'errand', null, 'normal')`, [CLIENTE]);
await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1, driver_assigned_at='2026-11-14T08:00:00Z' where id='t-favor'`, [TERCEIRO]);
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, restaurant_id)
  values ('t-entrega', $1, 'callingDriver', 'restaurant', null, 'kfc')`, [CLIENTE]);
await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1, driver_assigned_at='2026-11-14T08:30:00Z' where id='t-entrega'`, [TERCEIRO]);
f = await fila(TERCEIRO);
certo('Favor já em curso: a entrega aceite depois fica em espera', f.map((x) => `${x.order_id}:${x.estado}`).join(',') ===
  't-favor:ativo,t-entrega:em_espera', JSON.stringify(f));
await db.exec(`update public.orders set status='delivered' where id='t-favor'`);
f = await fila(TERCEIRO);
certo('entregou o Favor: a entrega abre', f.map((x) => `${x.order_id}:${x.estado}`).join(',') === 't-entrega:ativo', JSON.stringify(f));
await db.exec(`update public.orders set status='delivered' where id='t-entrega'`);
emCurso = await um(`select order_id from public.estafeta_pedido_em_curso where driver_uid=$1`, [TERCEIRO]);
certo('sem pedidos: o em curso é apagado', emCurso === undefined, JSON.stringify(emCurso));
// em curso velho (aponta para um pedido já entregue): o próximo aceite toma o lugar
await db.query(`insert into public.estafeta_pedido_em_curso (driver_uid, order_id) values ($1, 't-favor')`, [TERCEIRO]);
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, restaurant_id)
  values ('t-novo', $1, 'callingDriver', 'restaurant', null, 'kfc')`, [CLIENTE]);
await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1 where id='t-novo'`, [TERCEIRO]);
emCurso = await um(`select order_id from public.estafeta_pedido_em_curso where driver_uid=$1`, [TERCEIRO]);
certo('em curso velho é substituído pelo pedido aceite', emCurso?.order_id === 't-novo', JSON.stringify(emCurso));
// reescrever o MESMO estafeta de user_id para drivers.id não mexe no em curso
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, restaurant_id)
  values ('t-outro', $1, 'callingDriver', 'restaurant', null, 'pizzaria')`, [CLIENTE]);
await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1 where id='t-outro'`, [TERCEIRO]);
const T_DRV = '66666666-6666-6666-6666-666666666666';
await db.query(`update public.drivers set id = $1 where user_id = $2`, [T_DRV, TERCEIRO]);
// o texto muda (user_id → drivers.id) mas é a mesma pessoa
await db.query(`update public.orders set assigned_driver_id = $1 where id='t-novo'`, [T_DRV]);
emCurso = await um(`select order_id from public.estafeta_pedido_em_curso where driver_uid=$1`, [TERCEIRO]);
certo('mesmo estafeta reescrito: o em curso fica', emCurso?.order_id === 't-novo', JSON.stringify(emCurso));
await db.exec(`update public.orders set status='delivered' where id in ('t-novo','t-outro')`);

// pedido sem loja (encomenda) não passa à frente do Favor urgente (NULL num DESC)
const QUARTO = '55555555-5555-5555-5555-555555555555';
await db.query(`insert into auth.users values ($1,'q@x','{}')`, [QUARTO]);
await db.query(`insert into public.drivers values (gen_random_uuid(), $1, 'Quarto')`, [QUARTO]);
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, restaurant_id, errand_speed, driver_assigned_at) values
  ('q-kfc', $1, 'driverAccepted', 'restaurant', $2, 'kfc', null, '2026-11-14T09:00:00Z'),
  ('q-encomenda', $1, 'driverAccepted', 'sendPackage', $2, null, null, '2026-11-14T09:05:00Z'),
  ('q-urgente', $1, 'driverAccepted', 'errand', $2, null, 'express', '2026-11-14T09:10:00Z')`, [CLIENTE, QUARTO]);
await db.exec(`update public.orders set status='delivered' where id='q-kfc'`);
f = await fila(QUARTO);
certo('entregou o KFC: abre o urgente, não a encomenda sem loja', f.map((x) => `${x.order_id}:${x.estado}`).join(',') ===
  'q-urgente:ativo,q-encomenda:em_espera', JSON.stringify(f));
await db.exec(`update public.orders set status='delivered' where id in ('q-encomenda','q-urgente')`);

// linha sem productId: a app usa o nome como chave — o servidor também
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, items) values
  ('sem-id', $1, 'driverAccepted', 'storeShopping', $2, '[{"name":"Pão","price":0.5,"quantity":4}]')`, [CLIENTE, QUARTO]);
await como(QUARTO);
await um(`select public.estafeta_guardar_progresso_compra('sem-id', '{"Pão#0":{"s":"unavailable","q":4}}'::jsonb) r`);
const semId = (await um(`select public._rascunho_compra_itens_fecho('sem-id') r`)).r;
certo('linha sem productId: chave pelo nome, "não há" chega ao fecho', semId.length === 1 && semId[0].status === 'unavailable'
  && semId[0].original_item_id === 'Pão', JSON.stringify(semId));
await db.exec(`update public.orders set status='delivered' where id='sem-id'`);
await como(EST);

await como(EST);
const minha = (await um(`select public.estafeta_minha_fila() r`)).r;
certo('estafeta_minha_fila devolve a fila dele', minha.length === 3);
await como(ADMIN);
const filas = (await um(`select public.admin_filas_estafetas() r`)).r;
certo('admin_filas_estafetas: um estafeta com 3 pedidos', filas.length === 1 && filas[0].fila.length === 3 && filas[0].estafeta === 'Estafeta Teste', JSON.stringify(filas));

console.log('\n7) aviso ao cliente (gatilho)');
await db.exec(`delete from net.chamadas; delete from public.in_app_notifications;`);
// o estafeta está ocupado (urgente/entrega ativos); chega uma ENTREGA nova
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, restaurant_id, driver_assigned_at)
  values ('nova', $1, 'callingDriver', 'restaurant', null, 'pizzaria', now())`, [CLIENTE]);
await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1, driver_assigned_at=now() where id='nova'`, [EST]);
let avisos = await q(`select * from public.fila_avisos_cliente where order_id='nova'`);
let chamadas = await q(`select * from net.chamadas`);
let inapp = await q(`select * from public.in_app_notifications`);
certo('entrega em espera: 1 aviso registado', avisos.length === 1);
certo('push ao cliente com o texto do Danilo', chamadas.length === 1 && /noutro pedido perto de si/.test(chamadas[0].body.body)
  && chamadas[0].body.clientId === CLIENTE && chamadas[0].body.orderId === 'nova', JSON.stringify(chamadas));
certo('notificação na app do cliente', inapp.length === 1 && inapp[0].kind === 'order_queue');
await como(CLIENTE);
r = (await um(`select public.cliente_fila_do_meu_pedido('nova') r`)).r;
certo('cliente vê em_espera=true no ecrã', r.em_espera === true);
await como(OUTRO);
r = (await um(`select public.cliente_fila_do_meu_pedido('nova') r`)).r;
certo('outra pessoa não vê nada do pedido', r.em_espera === false);

// voltar a aceitar (ex.: reatribuição) não repete o aviso
await db.exec(`update public.orders set status='callingDriver' where id='nova'`);
await db.query(`update public.orders set status='driverAccepted' where id='nova'`);
chamadas = await q(`select * from net.chamadas`);
certo('um aviso por pedido (sem repetir)', chamadas.length === 1);

// Favor aceite por cima: nunca avisa
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, errand_speed)
  values ('favor2', $1, 'callingDriver', 'errand', $2, 'normal')`, [CLIENTE, EST]);
await db.exec(`update public.orders set status='driverAccepted' where id='favor2'`);
chamadas = await q(`select * from net.chamadas`);
certo('Favor em espera: o cliente não é avisado', chamadas.length === 1);

// estafeta livre: a entrega abre logo, sem aviso
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id) values ('livre', $1, 'callingDriver', 'restaurant', null)`, [CLIENTE]);
await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1 where id='livre'`, [OUTRO]);
chamadas = await q(`select * from net.chamadas`);
certo('estafeta livre: sem aviso de espera', chamadas.length === 1);

// o aviso nunca trava a aceitação, mesmo com o envio partido
await db.exec(`create or replace function net.http_post(url text, headers jsonb, body jsonb) returns bigint language plpgsql as $$ begin raise exception 'rede em baixo'; end $$;`);
await db.query(`insert into public.orders (id, user_id, status, service_type, assigned_driver_id, restaurant_id) values ('com-erro', $1, 'callingDriver', 'sendPackage', null, null)`, [CLIENTE]);
let passou = true;
try { await db.query(`update public.orders set status='driverAccepted', assigned_driver_id=$1, driver_assigned_at=now() where id='com-erro'`, [EST]); }
catch { passou = false; }
const st = await um(`select status from public.orders where id='com-erro'`);
certo('envio do aviso partido: a aceitação passa na mesma', passou && st.status === 'driverAccepted');

console.log('\n8) privilégios');
await db.exec(`set role anon`);
let negado = false;
try { await db.query(`select public.estafeta_guardar_progresso_compra('auchan','{}'::jsonb)`); } catch (e) { negado = /permission denied/.test(e.message); }
certo('anon não chama a gravação', negado);
negado = false;
try { await db.query(`select public.fila_do_estafeta($1)`, [EST]); } catch (e) { negado = /permission denied/.test(e.message); }
certo('anon não vê filas', negado);
await db.exec(`reset role; set role authenticated`);
negado = false;
try { await db.query(`select * from public.order_purchase_drafts`); } catch (e) { negado = /permission denied/.test(e.message); }
certo('authenticated não lê a tabela diretamente (só pelas funções)', negado);
negado = false;
try { await db.query(`select public.fila_do_estafeta($1)`, [EST]); } catch (e) { negado = /permission denied/.test(e.message); }
certo('authenticated não chama fila_do_estafeta de outro', negado);
let pode = false;
try { await db.query(`select public.estafeta_minha_fila()`); pode = true; } catch { pode = false; }
certo('authenticated chama estafeta_minha_fila', pode);
await db.exec(`reset role`);

console.log(`\nRESULTADO: ${ok} certos, ${falhas} falhados`);
process.exit(falhas ? 1 : 0);
