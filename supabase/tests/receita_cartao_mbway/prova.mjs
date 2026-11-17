// Prova local (PGlite = Postgres a correr no node) da migração 20261117120000_receita_cartao_mbway.sql.
// Uso: node prova.mjs <caminho-da-migracao>
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const mig = readFileSync(process.argv[2], 'utf8');
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8').replace(/^﻿/, '');
const db = new PGlite();
const passo = async (nome, sql) => {
  try { await db.exec(sql); console.log(`ok   ${nome}`); }
  catch (e) { console.log(`ERRO ${nome}: ${e.message}${e.position ? ' (posição ' + e.position + ')' : ''}${e.where ? ' | ' + e.where : ''}`); process.exit(2); }
};
await passo('esquema de ensaio', base);
await passo('migração (1.ª vez)', mig);
// Corre a migração 2.ª vez: tem de ser repetível sem erro.
await passo('migração (2.ª vez, repetível)', mig);

const A = '11111111-1111-1111-1111-111111111111'; // cliente
const B = '22222222-2222-2222-2222-222222222222'; // outro cliente
const F = '33333333-3333-3333-3333-333333333333'; // dono da farmácia
const D = '44444444-4444-4444-4444-444444444444'; // estafeta (user_id)
await db.exec(`
  insert into auth.users values ('${A}','a@x.pt','{"name":"Ana"}'),('${B}','b@x.pt','{}'),('${F}','f@x.pt','{}');
  insert into users values ('${A}','Ana Cliente','912000000'),('${B}','Bruno','913000000');
  insert into drivers (user_id, name) values ('${D}','Rui Estafeta Silva');
  insert into restaurants values
    ('farmacia-se-guarda','Farmácia da Sé','Rua da Sé 1',40.5373,-7.2676,false,false,'${F}',null,'pharmacy','publico'),
    ('farmacia-demo','Farmácia Demo','Rua X',40.54,-7.27,false,true,'${F}',null,'pharmacy','publico');
`);

let n = 0, falhas = 0;
const ok = (nome, cond, extra = '') => { n++; if (!cond) falhas++; console.log(`${cond ? 'PASSA' : 'FALHA'} ${n}. ${nome}${extra ? ' — ' + extra : ''}`); };
const como = async (uid, admin = false) => {
  await db.query(`select set_config('test.uid', $1, false), set_config('test.admin', $2, false)`, [uid ?? '', admin ? 'sim' : '']);
};
const um = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const erro = async (sql, p = []) => { try { await db.query(sql, p); return null; } catch (e) { return e.message; } };
const novaReceita = async (uid = A, loja = 'farmacia-se-guarda', valor = 1250) => (await um(
  `insert into pedidos_prescricao (restaurant_id,user_id,tipo,estado,morada,lat,lng,valor_medicamentos_cents,taxa_servico_cents,is_demo)
   values ($1,$2,'receita','aceite','Rua do Cliente 5, Guarda',40.5450,-7.2600,$3,600,$4) returning id`, [loja, uid, valor, loja === 'farmacia-demo'])).id;
const pin = (orderId) => { const h = orderId.replace(/-/g, '').slice(0, 4); return String((parseInt(h, 16) % 9000) + 1000); };

// ---------- cartão
await como(A);
const r1 = await novaReceita();
const c1 = (await um(`select prescricao_preparar_pedido($1,'card') j`, [r1])).j;
ok('cartão: devolve cart_input montado pelo servidor', c1.metodo === 'card' && c1.cart_input?.payment_method === 'card'
   && c1.cart_input.errand_estimated_purchase_cents === 1250 && c1.cart_input.service_type === 'errand');
ok('cartão: não cria pedido antes de pagar', (await um(`select count(*)::int c from orders`)).c === 0);
const ref1 = (await um(`select pagamento_ref from pedidos_prescricao where id=$1`, [r1])).pagamento_ref;
ok('cartão: código de levantamento reservado e na descrição', ref1 && c1.cart_input.errand_description.includes(`Código de levantamento: ${ref1}.`));
const c1b = (await um(`select prescricao_preparar_pedido($1,'card') j`, [r1])).j;
ok('cartão: toque duplo mantém o mesmo código', c1b.codigo_levantamento === ref1);
ok('cartão: a farmácia NÃO é avisada antes do pagamento', (await um(`select count(*)::int c from avisos where id=$1`, [r1])).c === 0);
// O que o finalize-order-from-intent faz: create_order como serviço (sem sessão) com o rascunho + pago.
await como(null);
const fin = (await um(`select create_order($1::jsonb || jsonb_build_object('payment_already_confirmed', true, 'user_id', $2::text)) j`, [c1.cart_input, A])).j;
let pp = await um(`select * from pedidos_prescricao where id=$1`, [r1]);
ok('cartão pago: receita confirmada e ligada ao pedido', pp.estado === 'confirmado' && pp.order_id === fin.order_id && pp.metodo_pagamento === 'card');
ok('cartão pago: código de entrega = PIN do pedido', pp.codigo_entrega === pin(fin.order_id), `${pp.codigo_entrega} vs ${pin(fin.order_id)}`);
ok('cartão pago: código de levantamento = o reservado', pp.codigo_levantamento === ref1);
ok('cartão pago: total = medicamentos + taxa do Favor', pp.total_cents === 1250 + pp.taxa_servico_cents && pp.taxa_servico_cents >= 600, `${pp.total_cents} = 1250 + ${pp.taxa_servico_cents}`);
ok('cartão pago: farmácia avisada "O cliente pagou"', (await um(`select count(*)::int c from avisos where id=$1 and titulo like 'O cliente pagou%'`, [r1])).c === 1);
await como(A);
ok('cartão: depois de confirmado já não prepara outra vez', (await erro(`select prescricao_preparar_pedido($1,'card')`, [r1]))?.startsWith('NAO_CONFIRMAVEL'));

// ---------- cartão adulterado no telemóvel (valor da compra mais baixo)
const r2 = await novaReceita();
const c2 = (await um(`select prescricao_preparar_pedido($1,'card') j`, [r2])).j;
await como(null);
await db.query(`select create_order($1::jsonb || jsonb_build_object('payment_already_confirmed', true, 'user_id', $2::text, 'errand_estimated_purchase_cents', 100))`, [c2.cart_input, A]);
pp = await um(`select * from pedidos_prescricao where id=$1`, [r2]);
ok('adulterado: receita NÃO fica confirmada', pp.estado === 'aceite' && pp.order_id === null);
ok('adulterado: alerta gravado e aviso urgente ao admin', (pp.pagamento_alerta || '').includes('valor da compra diferente')
   && (await um(`select count(*)::int c from admin_push where tipo='prescricao_pagamento_alerta'`)).c === 1, pp.pagamento_alerta);
// distância encolhida
await como(A);
const r2b = await novaReceita();
const c2b = (await um(`select prescricao_preparar_pedido($1,'card') j`, [r2b])).j;
await como(null);
await db.query(`select create_order($1::jsonb || jsonb_build_object('payment_already_confirmed', true, 'user_id', $2::text, 'distance_km', 0.1))`, [c2b.cart_input, A]);
ok('adulterado: distância menor não liga', (await um(`select estado from pedidos_prescricao where id=$1`, [r2b])).estado === 'aceite');

// ---------- MB Way
await como(A);
const r3 = await novaReceita(A, 'farmacia-se-guarda', 1300);
const m1 = (await um(`select prescricao_preparar_pedido($1,'mbway') j`, [r3])).j;
let o3 = await um(`select * from orders where id=$1`, [m1.order_id]);
ok('MB Way: pedido criado à espera de pagamento', o3 && o3.payment_method === 'mbway' && o3.payment_status === 'pending' && o3.user_id === A);
ok('MB Way: total devolvido = medicamentos + taxa', m1.total_cents === Math.round(Number(o3.price) * 100));
ok('MB Way: valor a pedir = margem do Favor (payment_buffer_total)', m1.cobrar_cents === Math.round(Number(o3.payment_buffer_total) * 100) && m1.cobrar_cents > m1.total_cents, `${m1.cobrar_cents} > ${m1.total_cents}`);
const m2 = (await um(`select prescricao_preparar_pedido($1,'mbway') j`, [r3])).j;
ok('MB Way: toque duplo devolve o MESMO pedido', m2.order_id === m1.order_id && m2.repetido === true
   && (await um(`select count(*)::int c from orders where user_id=$1 and payment_method='mbway'`, [A])).c === 1);
ok('MB Way vivo: cartão recusado (PAGAMENTO_EM_CURSO)', (await erro(`select prescricao_preparar_pedido($1,'card')`, [r3]))?.startsWith('PAGAMENTO_EM_CURSO'));
const eCash = await erro(`update pedidos_prescricao set estado='confirmado', metodo_pagamento='cash', order_id='outro' where id=$1`, [r3]);
ok('MB Way vivo: dinheiro recusado (não cria 2.º pedido)', eCash?.startsWith('PAGAMENTO_EM_CURSO'), eCash);
const eCanc = await erro(`update pedidos_prescricao set estado='cancelado' where id=$1`, [r3]);
ok('MB Way vivo: cancelar a receita recusado', eCanc?.startsWith('PAGAMENTO_EM_CURSO'));
ok('MB Way por pagar: farmácia ainda não avisada', (await um(`select count(*)::int c from avisos where id=$1`, [r3])).c === 0);
await como(null);
await db.query(`update orders set payment_status='paid' where id=$1`, [m1.order_id]); // o que o webhook faz
pp = await um(`select * from pedidos_prescricao where id=$1`, [r3]);
ok('MB Way pago: receita confirmada e ligada', pp.estado === 'confirmado' && pp.order_id === m1.order_id && pp.metodo_pagamento === 'mbway'
   && pp.codigo_entrega === pin(m1.order_id));
ok('MB Way pago: farmácia avisada', (await um(`select count(*)::int c from avisos where id=$1 and titulo like 'O cliente pagou%'`, [r3])).c === 1);

// MB Way recusado/expirado → pedido cancelado → receita volta a poder pagar
await como(A);
const r4 = await novaReceita(A, 'farmacia-se-guarda', 1400);
const m4 = (await um(`select prescricao_preparar_pedido($1,'mbway') j`, [r4])).j;
await como(null);
await db.query(`update orders set status='cancelled' where id=$1`, [m4.order_id]);
ok('MB Way cancelado: receita livre outra vez', (await um(`select pagamento_order_id from pedidos_prescricao where id=$1`, [r4])).pagamento_order_id === null);
await como(A);
const c4 = (await um(`select prescricao_preparar_pedido($1,'card') j`, [r4])).j;
ok('MB Way cancelado: pode pagar com cartão a seguir (mesmo código)', c4.metodo === 'card'
   && c4.codigo_levantamento === (await um(`select pagamento_ref from pedidos_prescricao where id=$1`, [r4])).pagamento_ref);
// MB Way pago depois de cancelado (o webhook reativa o pedido) → liga na mesma pelo código
await como(null);
await db.query(`update orders set status='created', payment_status='pending' where id=$1`, [m4.order_id]);
await db.query(`update pedidos_prescricao set pagamento_conferir = jsonb_set(pagamento_conferir,'{metodo}','"mbway"') where id=$1`, [r4]);
await db.query(`update orders set payment_status='paid' where id=$1`, [m4.order_id]);
ok('MB Way pago tarde (pedido reativado): liga à receita', (await um(`select order_id from pedidos_prescricao where id=$1`, [r4])).order_id === m4.order_id);

// ---------- cartão começado há pouco: não deixa dinheiro nem cancelar
await como(A);
const r5 = await novaReceita();
const c5 = (await um(`select prescricao_preparar_pedido($1,'card') j`, [r5])).j;
await db.query(`insert into payment_drafts (user_id, payload) values ($1,$2)`, [A, c5.cart_input]);
const e5 = await erro(`update pedidos_prescricao set estado='cancelado' where id=$1`, [r5]);
ok('cartão a decorrer (<10 min): cancelar recusado', e5?.startsWith('PAGAMENTO_EM_CURSO'), e5);
await db.query(`update payment_drafts set created_at = now() - interval '11 minutes'`);
ok('cartão abandonado (>10 min): cancelar passa', (await erro(`update pedidos_prescricao set estado='cancelado' where id=$1`, [r5])) === null);
// pagamento tardio de uma receita já cancelada → alerta, não liga
await como(null);
await db.query(`select create_order($1::jsonb || jsonb_build_object('payment_already_confirmed', true, 'user_id', $2::text))`, [c5.cart_input, A]);
pp = await um(`select * from pedidos_prescricao where id=$1`, [r5]);
ok('pago depois de cancelada: não liga e avisa o admin', pp.order_id === null && (pp.pagamento_alerta || '').includes('cancelado'), pp.pagamento_alerta);

// ---------- outros casos
await como(A);
const r6 = await novaReceita(A, 'farmacia-demo');
ok('loja de demonstração: recusa pagar (confirma-se sem cobrar)', (await erro(`select prescricao_preparar_pedido($1,'card')`, [r6]))?.startsWith('DEMONSTRACAO'));
await como(B);
ok('outro cliente: NAO_ENCONTRADO', (await erro(`select prescricao_preparar_pedido($1,'card')`, [r2]))?.startsWith('NAO_ENCONTRADO'));
await como(A);
ok('dinheiro por este caminho: METODO_INVALIDO', (await erro(`select prescricao_preparar_pedido($1,'cash')`, [r2]))?.startsWith('METODO_INVALIDO'));
await db.query(`update platform_settings set value='"false"' where key='pharmacy_prescription_real_orders_enabled'`);
ok('interruptor desligado: RECEITA_REAL_POR_LIGAR', (await erro(`select prescricao_preparar_pedido($1,'card')`, [r2]))?.startsWith('RECEITA_REAL_POR_LIGAR'));
await db.query(`update platform_settings set value='"true"' where key='pharmacy_prescription_real_orders_enabled'`);
await db.query(`update platform_settings set value='false' where key='mbway_enabled'`);
const r7 = await novaReceita(A, 'farmacia-se-guarda', 1500);
ok('MB Way desligado: frase clara', (await erro(`select prescricao_preparar_pedido($1,'mbway')`, [r7]))?.startsWith('MBWAY_DESLIGADO'));
await db.query(`update platform_settings set value='true' where key='mbway_enabled'`);
const r8 = await um(`insert into pedidos_prescricao (restaurant_id,user_id,tipo,estado,morada,valor_medicamentos_cents) values ('farmacia-se-guarda',$1,'receita','aceite','morada escrita à mão sem mapa',900) returning id`, [A]);
ok('morada sem coordenadas: FALTA_LOCALIZACAO', (await erro(`select prescricao_preparar_pedido($1,'card')`, [r8.id]))?.startsWith('FALTA_LOCALIZACAO'));

// pedido em dinheiro da receita que fica pago na entrega: nada muda
await como(null);
const cashOrder = (await um(`insert into orders (user_id,status,payment_status,payment_method,service_type,errand_description)
  values ($1,'delivered','pending','cash','errand','Receita: ... Código de levantamento: ZZZZZZ. Pagar') returning id`, [A])).id;
await db.query(`update pedidos_prescricao set estado='confirmado', metodo_pagamento='cash', order_id=$2 where id=$1`, [r7, cashOrder]);
await db.query(`update orders set payment_status='paid' where id=$1`, [cashOrder]);
ok('dinheiro pago na entrega: receita fica igual', (await um(`select estado, pagamento_alerta from pedidos_prescricao where id=$1`, [r7])).estado === 'confirmado');

// ---------- farmácia aberta/fechada logo à entrada
await como(A);
let cons = (await um(`select farmacia_consentimento('farmacia-se-guarda') j`)).j;
ok('consentimento: aberta=true', cons.aberta === true && cons.taxa_servico_cents === 600);
await db.query(`select set_config('test.aberta','nao',false)`);
cons = (await um(`select farmacia_consentimento('farmacia-se-guarda') j`)).j;
ok('consentimento: fechada → aberta=false, abre_as 09:00', cons.aberta === false && cons.abre_as === '09:00');
cons = (await um(`select farmacia_consentimento('farmacia-demo') j`)).j;
ok('consentimento: loja de demonstração nunca "fechada"', cons.aberta === true);
await db.query(`select set_config('test.aberta','sim',false)`);

// ---------- a farmácia vê a entrega
await db.query(`update orders set driver_id=$2, status='driverAccepted' where id=$1`, [fin.order_id, D]);
await como(F);
let ent = (await db.query(`select * from farmacia_prescricoes_entrega($1::uuid[])`, [[r1, r3]])).rows;
ok('farmácia vê estado e 1.º nome do estafeta', ent.length === 2 && ent.find(e => e.prescricao_id === r1)?.estafeta_nome === 'Rui'
   && ent.find(e => e.prescricao_id === r1)?.estado_pedido === 'driverAccepted');
await como(B);
ent = (await db.query(`select * from farmacia_prescricoes_entrega($1::uuid[])`, [[r1, r3]])).rows;
ok('outra pessoa não vê nada', ent.length === 0);

// ---------- painel admin
await como(F, true);
const lst = (await db.query(`select admin_prescricoes_listar() j`)).rows.map(r => r.j);
const l1 = lst.find(x => x.id === r1);
ok('admin: pedido ligado, estado, estafeta e método', l1?.order_id === fin.order_id && l1?.pedido_estado === 'driverAccepted'
   && l1?.estafeta_nome === 'Rui Estafeta Silva' && l1?.metodo_pagamento === 'card');
ok('admin: alerta visível', lst.some(x => (x.pagamento_alerta || '').includes('valor da compra diferente')));
await como(B);
ok('admin: só admin', (await erro(`select admin_prescricoes_listar()`))?.includes('Somente admin'));

console.log(`\n${n - falhas}/${n} passaram${falhas ? ` — ${falhas} FALHARAM` : ''}`);
process.exit(falhas ? 1 : 0);
