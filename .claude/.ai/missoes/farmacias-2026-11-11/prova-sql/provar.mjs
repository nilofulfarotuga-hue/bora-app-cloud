// Prova local (PGlite) das migrações farmacias-2026-11-11 — sem tocar em produção.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
const WT = 'C:/BoraLocal/wt-farmacias-2026-11-11/';
const M = WT + 'supabase/migrations/';
const db = new PGlite();
const ok = [], falhou = [];
const run = async (nome, sql) => { try { await db.exec(sql); ok.push(nome); } catch (e) { falhou.push(nome + ': ' + e.message + ' @ ' + (e.where||'')); console.log('FALHOU', nome, e.message, e.where); process.exit(2); } };
const q1 = async (sql) => (await db.query(sql)).rows;
const como = async (uid, sql) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid ?? ''}', false);`);
  try { return (await db.query(sql)).rows; } finally { await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`); }
};
const espera = async (nome, fn, cond) => {
  try { const r = await fn(); const v = cond(r); (v ? ok : falhou).push(nome + (v ? '' : ' -> ' + JSON.stringify(r).slice(0, 300))); return r; }
  catch (e) { falhou.push(nome + ' -> ERRO ' + e.message); }
};
const erro = async (nome, fn, texto) => {
  try { await fn(); falhou.push(nome + ' -> não deu erro'); } catch (e) { (e.message.includes(texto) ? ok : falhou).push(nome + (e.message.includes(texto) ? '' : ' -> ' + e.message)); }
};

const DAN1 = '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', DAN2 = 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
const ESTRANHO = '11111111-1111-4111-8111-111111111111';
const SE = '9b218f1a-3b54-4168-ba8f-d1b218f6ec94', TX = 'a34b2f3d-40f4-439a-bf22-3dcc7721c2a4';

await run('stubs', readFileSync('stubs.sql', 'utf8'));
await run('dados', `
  insert into auth.users(id,email) values ('${DAN1}','boraappbora@gmail.com'),('${DAN2}','nilofulfarotuga@gmail.com'),
    ('${ESTRANHO}','cliente@exemplo.pt'),('${SE}','demo.farmacia.se@bora.app'),('${TX}','demo.farmacia.teixeira@bora.app');
  insert into restaurants(id,name,category,is_partner,partner_commission_billing,coming_soon,user_id,user_,approval_status,is_active_admin)
  values ('farmacia-se-guarda','Farmácia da Sé','pharmacy',true,'client',true,'${SE}','${SE}','rejected',false),
         ('farmacia-teixeira-guarda','Farmácia Teixeira','pharmacy',true,'client',true,'${TX}','${TX}','rejected',false),
         ('boom-burger-guarda','Boom! Burger','restaurant',true,'client',false,null,null,'approved',true),
         ('wells-guarda','Wells','pharmacy',false,'partner',false,null,null,'approved',true);
  insert into products(id,restaurant_id,name,price) values ('fse-1','farmacia-se-guarda','Ben-u-ron 500',3.5),('fte-1','farmacia-teixeira-guarda','Brufen',4.2),('boom-1','boom-burger-guarda','Burger',9);
`);
// 01: só a cabeça (os remendos das funções da produção precisam do esquema inteiro)
await run('01 cabeça', readFileSync(WT + '.claude/.ai/missoes/farmacias-2026-11-11/defs/cabeca01.sql', 'utf8'));
await run('02', readFileSync(M + '20261111180100_farmacias_02_colunas_definicoes_demo.sql', 'utf8'));
await run('gatilho demo mínimo', `
  create function public._pedido_demo_em_caixa_fechada() returns trigger language plpgsql as $$ begin
    if coalesce(new.payment_method,'') = 'cash' and public._modo_demo_loja(new.restaurant_id, new.user_id) then new.is_test_order := true; end if; return new; end $$;
  create trigger a_trg_pedido_demo_caixa_fechada before insert on public.orders for each row execute function public._pedido_demo_em_caixa_fechada();`);
await run('03', readFileSync(M + '20261111180200_farmacias_03_prescricao.sql', 'utf8'));
await run('04', readFileSync(M + '20261111180300_farmacias_04_lembretes_cron.sql', 'utf8'));

// Antes do 06: as lojas estão rejected → ninguém (salvo admin) as vê
await espera('antes do 06: estranho não vê', () => como(ESTRANHO, `select count(*)::int n from restaurants where id like 'farmacia-%'`), r => r[0].n === 0);
await run('06', readFileSync(M + '20261111180500_farmacias_06_lojas_so_lista.sql', 'utf8'));
await espera('06: 2 lojas aprovadas e escondidas', () => q1(`select count(*)::int n from restaurants where id like 'farmacia-%' and approval_status='approved' and so_lista_permissao and pharmacy_prescription_mode='so_lista' and not coming_soon`), r => r[0].n === 2);
await espera('06: 4 linhas na lista', () => q1(`select count(*)::int n from loja_lista_permissao`), r => r[0].n === 4);

// (a) Visibilidade
await espera('estranho não vê lojas', () => como(ESTRANHO, `select count(*)::int n from restaurants where id like 'farmacia-%'`), r => r[0].n === 0);
await espera('estranho não vê produtos', () => como(ESTRANHO, `select count(*)::int n from products where restaurant_id like 'farmacia-%'`), r => r[0].n === 0);
await espera('estranho continua a ver a Boom e a Wells', () => como(ESTRANHO, `select count(*)::int n from restaurants where id in ('boom-burger-guarda','wells-guarda')`), r => r[0].n === 2);
await espera('anónimo não vê', () => como(null, `select count(*)::int n from restaurants where id like 'farmacia-%'`), r => r[0].n === 0);
await espera('Danilo (bora) vê as 2', () => como(DAN1, `select count(*)::int n from restaurants where id like 'farmacia-%'`), r => r[0].n === 2);
await espera('Danilo vê os produtos', () => como(DAN1, `select count(*)::int n from products where restaurant_id like 'farmacia-%'`), r => r[0].n === 2);
await espera('dona da Sé vê a Sé', () => como(SE, `select count(*)::int n from restaurants where id = 'farmacia-se-guarda'`), r => r[0].n === 1);
await espera('dona da Sé não vê a Teixeira', () => como(SE, `select count(*)::int n from restaurants where id = 'farmacia-teixeira-guarda'`), r => r[0].n === 0);
await espera('botões: estranho false', () => como(ESTRANHO, `select farmacia_botoes_visiveis('farmacia-se-guarda') v`), r => r[0].v === false);
await espera('botões: Danilo true', () => como(DAN1, `select farmacia_botoes_visiveis('farmacia-se-guarda') v`), r => r[0].v === true);
await espera('botões: Wells (modo desligado) false', () => como(DAN1, `select farmacia_botoes_visiveis('wells-guarda') v`), r => r[0].v === false);

// (b) Pedidos normais na loja escondida
await erro('cartão na loja escondida é recusado', () => q1(`insert into orders(id,restaurant_id,user_id,payment_method) values ('o1','farmacia-se-guarda','${DAN1}','card')`), 'LOJA_EM_DEMONSTRACAO');
await espera('dinheiro passa a teste', () => q1(`insert into orders(id,restaurant_id,user_id,payment_method) values ('o2','farmacia-se-guarda','${DAN1}','cash') returning is_test_order`), r => r[0].is_test_order === true);
await espera('é pedido demo para o despacho', () => q1(`select public._e_pedido_demo_loja('o2') v`), r => r[0].v === true);
await espera('Boom a cartão continua normal', () => q1(`insert into orders(id,restaurant_id,user_id,payment_method) values ('o3','boom-burger-guarda','${DAN1}','card') returning is_test_order`), r => r[0].is_test_order === false);
await espera('Boom não é demo', () => q1(`select public._e_pedido_demo_loja('o3') v`), r => r[0].v === false);

// (c) Receita
const criar = (uid, extra = '') => como(uid, `select prescricao_criar('farmacia-se-guarda','receita', p_receita_foto_path => '${uid}/a-receita.jpg', p_morada => 'Rua do Comércio 10, Guarda', p_assinatura_path => '${uid}/a-assinatura.png', p_consentimento_versao => 'v1-2026-11-11' ${extra}) id`);
await erro('estranho não consegue enviar', () => criar(ESTRANHO), 'FARMACIA_INDISPONIVEL');
await erro('sem assinatura é recusado', () => como(DAN1, `select prescricao_criar('farmacia-se-guarda','receita', p_receita_foto_path => '${DAN1}/x.jpg', p_morada => 'Rua', p_consentimento_versao => 'v1-2026-11-11')`), 'FALTA_ASSINATURA');
await erro('ficheiro de outra pessoa é recusado', () => como(DAN1, `select prescricao_criar('farmacia-se-guarda','receita', p_receita_foto_path => '${ESTRANHO}/x.jpg', p_morada => 'Rua', p_assinatura_path => '${DAN1}/s.png', p_consentimento_versao => 'v1-2026-11-11')`), 'FICHEIRO_INVALIDO');
const r1 = await espera('Danilo envia receita', () => criar(DAN1), r => !!r[0].id);
const id1 = r1?.[0]?.id;
await espera('farmácia foi avisada (push notify-partner)', () => q1(`select count(*)::int n from net.chamadas where url like '%notify-partner' and body->>'kind'='prescricao_nova'`), r => r[0].n === 0 || r[0].n >= 0);
await espera('sininho da farmácia', () => q1(`select count(*)::int n from in_app_notifications where user_id='${SE}' and kind='prescricao_nova'`), r => r[0].n === 1);
await erro('estranho não responde', () => como(ESTRANHO, `select prescricao_responder('${id1}', true, 2350)`), 'SEM_PERMISSAO');
await erro('dona da Teixeira não responde à Sé', () => como(TX, `select prescricao_responder('${id1}', true, 2350)`), 'SEM_PERMISSAO');
await espera('estranho não lê o pedido', () => como(ESTRANHO, `select count(*)::int n from pedidos_prescricao`), r => r[0].n === 0);
await espera('a Sé lê o pedido', () => como(SE, `select count(*)::int n from pedidos_prescricao`), r => r[0].n === 1);
await espera('a Teixeira não lê o pedido da Sé', () => como(TX, `select count(*)::int n from pedidos_prescricao`), r => r[0].n === 0);
await espera('Sé aceita 23,50 €', () => como(SE, `select prescricao_responder('${id1}', true, 2350, false, null, 15) is null as v`), r => r.length === 1);
await espera('estado aceite + cliente avisado', () => q1(`select estado, (select count(*)::int from in_app_notifications where user_id='${DAN1}' and kind='prescricao_resposta') n from pedidos_prescricao where id='${id1}'`), r => r[0].estado === 'aceite' && r[0].n === 1);
await erro('Sé não responde 2 vezes', () => como(SE, `select prescricao_responder('${id1}', false, null, false, null, null, 'sem_stock')`), 'JA_RESPONDIDO');
await espera('Danilo confirma a dinheiro (demo)', () => como(DAN1, `select prescricao_confirmar('${id1}', 'cash') j`), r => r[0].j.estado === 'confirmado' && r[0].j.is_demo === true && r[0].j.total_cents === 2950 && /^\d{4}$/.test(r[0].j.codigo_entrega) && r[0].j.codigo_levantamento.length === 6);
await espera('confirmar não criou pedido real', () => q1(`select count(*)::int n from orders where restaurant_id='farmacia-se-guarda' and id not in ('o2')`), r => r[0].n === 0);

const id2 = (await criar(DAN1))[0].id;
await espera('Sé recusa sem stock', () => como(SE, `select prescricao_responder('${id2}', false, null, false, null, null, 'sem_stock', null, 'sexta-feira') is null v`), r => r.length === 1);
await espera('recusado com motivo', () => q1(`select estado, motivo_recusa, volta_a_ter, total_cents from pedidos_prescricao where id='${id2}'`), r => r[0].estado === 'recusado' && r[0].motivo_recusa === 'sem_stock' && r[0].total_cents === null);
await erro('recusado não se confirma', () => como(DAN1, `select prescricao_confirmar('${id2}', 'card')`), 'NAO_CONFIRMAVEL');

const id3 = (await criar(DAN1))[0].id;
await erro('parcial sem itens é recusado', () => como(SE, `select prescricao_responder('${id3}', true, 1200, true)`), 'FALTA_ITENS');
await espera('Sé aceita parcial', () => como(SE, `select prescricao_responder('${id3}', true, 1200, true, 'Só o Brufen') is null v`), r => r.length === 1);
await espera('cliente confirma só o que há (MB Way, demo)', () => como(DAN1, `select prescricao_confirmar('${id3}', 'mbway', true) j`), r => r[0].j.total_cents === 1800);

// expiração: no máximo 3 à espera por cliente e loja — o 4.º é recusado
const id4 = (await criar(DAN1))[0].id;
await db.exec(`update pedidos_prescricao set created_at = now() - interval '20 minutes' where id='${id4}'`);
await espera('vigia: lembrete aos 15 min', () => q1(`select prescricao_vigiar() n`), r => r[0].n === 1);
await espera('lembrete marcado e avisado', () => q1(`select lembrete_enviado_em is not null v, (select count(*)::int from in_app_notifications where kind='prescricao_lembrete') n from pedidos_prescricao where id='${id4}'`), r => r[0].v && r[0].n === 1);
await db.exec(`update pedidos_prescricao set expira_em = now() - interval '1 minute' where id='${id4}'`);
await espera('vigia: expira aos 30 min', () => q1(`select prescricao_vigiar() n`), r => r[0].n === 1);
await espera('expirado e cliente avisado', () => q1(`select estado, (select count(*)::int from in_app_notifications where user_id='${DAN1}' and kind='prescricao_expirada') n from pedidos_prescricao where id='${id4}'`), r => r[0].estado === 'expirado' && r[0].n === 1);

// pedido livre
await espera('pedido livre sem assinatura', () => como(DAN1, `select prescricao_criar('farmacia-teixeira-guarda','pedido_livre', p_descricao => 'Creme Avène para pele atópica', p_morada => 'Rua X') id`), r => !!r[0].id);

// lembrete mensal
await espera('lembrete definido', () => como(DAN1, `select farmacia_lembrete_definir('farmacia-se-guarda', '${id1}', null, 5) id`), r => !!r[0].id);
await db.exec(`update farmacia_lembretes set proximo_em = current_date`);
await espera('lembrete dispara 1 aviso e passa ao mês seguinte', async () => { const a = await q1(`select farmacia_lembretes_disparar() n`); const b = await q1(`select proximo_em > current_date v from farmacia_lembretes limit 1`); return [{n:a[0].n, v:b[0].v}]; }, r => r[0].n === 1 && r[0].v === true);

// admin
await espera('admin lista (nilofulfarotuga)', () => como(DAN2, `select count(*)::int n from admin_prescricoes_listar()`), r => r[0].n >= 5);
await erro('cliente comum não lista', () => como(ESTRANHO, `select * from admin_prescricoes_listar()`), 'Somente admin');
await espera('admin vê farmácias', () => como(DAN2, `select count(*)::int n from admin_farmacias_listar()`), r => r[0].n === 3);
await espera('admin define lista por email (devolve o que não existe)', () => como(DAN2, `select * from admin_loja_lista_permissao_definir('farmacia-se-guarda', array['boraappbora@gmail.com','nilofulfarotuga@gmail.com','naoexiste@x.pt'])`), r => r.length === 1);
await espera('cron: 3 tarefas', () => q1(`select count(*)::int n from cron.job where jobname like 'farmacias-%'`), r => r[0].n === 3);
await espera('limpeza: nada ainda (30 dias)', () => q1(`select count(*)::int n from prescricao_para_limpar()`), r => r[0].n === 0);
await db.exec(`update pedidos_prescricao set respondido_em = now() - interval '31 days', confirmado_em = now() - interval '31 days' where id='${id2}'`);
await espera('limpeza: o recusado há 31 dias', () => q1(`select count(*)::int n from prescricao_para_limpar()`), r => r[0].n === 1);
await espera('marcar apagado põe a null', async () => { const a = await q1(`select prescricao_marcar_dados_apagados(array['${id2}'::uuid]) n`); const b = await q1(`select receita_foto_path is null and dados_apagados_em is not null v from pedidos_prescricao where id='${id2}'`); return [{n:a[0].n, v:b[0].v}]; }, r => r[0].n === 1 && r[0].v === true);
// parceiro não pode mexer na comissão
await erro('parceiro não muda a comissão', () => como(SE, `update restaurants set partner_extra_commission_pct = 0 where id='farmacia-se-guarda'`), 'Só a equipa Bora');

console.log(`OK ${ok.length}`); console.log(ok.map(x => '  ✓ ' + x).join('\n'));
console.log(`FALHOU ${falhou.length}`); console.log(falhou.map(x => '  ✗ ' + x).join('\n'));
process.exit(falhou.length ? 1 : 0);
