// Prova local (PGlite) do vigia B3 — sem tocar em produção.
// Uso: PGLITE_DIR=<pasta com node_modules/@electric-sql/pglite> node provar_sentinela.mjs
import { readFileSync } from 'node:fs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(AQUI, '../../..');
const PG = process.env.PGLITE_DIR || 'C:/Users/danil/AppData/Local/Temp/pglite-prova';
const { PGlite } = await import(pathToFileURL(resolve(PG, 'node_modules/@electric-sql/pglite/dist/index.js')).href);

const db = new PGlite();
const ok = [], falhou = [];
const q = async (sql) => (await db.query(sql)).rows;
const um = async (sql) => (await q(sql))[0];
const exec = (sql) => db.exec(sql);
const teste = (nome, cond, detalhe = '') => {
  (cond ? ok : falhou).push(nome + (cond ? '' : ' -> ' + detalhe));
  console.log((cond ? 'PASSOU  ' : 'FALHOU  ') + nome + (cond ? '' : ' -> ' + detalhe));
};
const varrer = async () => (await um('select public.sentinela_varrer() as r')).r;
const eventos = async (where = 'true') => q(`select * from public.sentinela_eventos where ${where} order by id`);

await exec(readFileSync(resolve(AQUI, 'sentinela_stubs.sql'), 'utf8'));
await exec(readFileSync(resolve(REPO, 'supabase/migrations/20261122190000_hermes_diretor_tabelas.sql'), 'utf8'));
const MIG = readFileSync(resolve(REPO, 'supabase/migrations/20261122190100_sentinela_funcoes.sql'), 'utf8');
await exec(MIG);
console.log('contrato + migração carregados\n');

// (0) pg_cron agendado, e a migração é repetível
await exec(MIG);
const jobs = await q(`select * from cron.job where jobname='sentinela-varrer'`);
teste('0a agendada de minuto a minuto uma só vez (migração repetida não duplica)', jobs.length === 1 && jobs[0].schedule === '* * * * *' && jobs[0].command.includes('sentinela_varrer'), JSON.stringify(jobs));
const sets = await um(`select count(*)::int c from platform_settings where category='sentinela'`);
teste('0b definições criadas na categoria sentinela', sets.c === 13, String(sets.c));

// (1) pedido parado: 1 evento, a 2.ª varredura não repete
await exec(`insert into orders(id,restaurant_id,order_type,status,created_at,status_updated_at) values ('P1','R1','partnerRestaurant','created', now()-interval '20 minutes', now()-interval '20 minutes')`);
const r1 = await varrer();
let ev = await eventos(`chave_dedup='pedido:P1:loja'`);
teste('1a pedido parado gera 1 evento', ev.length === 1 && ev[0].tipo === 'pedido_parado' && ev[0].gravidade === 'urgente', JSON.stringify(r1));
await varrer();
ev = await eventos(`chave_dedup='pedido:P1:loja'`);
teste('1b a 2.ª varredura não repete', ev.length === 1, String(ev.length));
const reg = await um(`select public.sentinela_registar('pedido_parado','urgente','pedido:P1:loja','x','{}'::jsonb) as r`);
teste('1c registar com a mesma chave devolve null', reg.r === null);

// (2) urgente cria despacho para o emerson, prioridade 90
const d = await q(`select d.* from despacho d join sentinela_eventos e on e.despacho_id=d.id where e.chave_dedup='pedido:P1:loja'`);
teste('2 urgente cria 1 despacho para emerson, prioridade 90, ligado ao evento', d.length === 1 && d[0].para === 'emerson' && d[0].prioridade === 90 && d[0].tipo === 'tarefa' && d[0].tarefa.includes('P1'), JSON.stringify(d));

// outros pedidos: pronto sem estafeta e a caminho; agendado para o futuro não
await exec(`insert into orders(id,restaurant_id,order_type,status,created_at,status_updated_at,dispatch_calling_since) values
  ('P2','R1','nonPartnerPurchase','callingDriver', now()-interval '30 minutes', now()-interval '10 minutes', now()-interval '9 minutes'),
  ('P3','R1','errand','onTheWay', now()-interval '2 hours', now()-interval '60 minutes', null),
  ('P4','R1','partnerRestaurant','created', now()-interval '30 minutes', now()-interval '30 minutes', null)`);
await exec(`update orders set scheduled_for = now() + interval '3 hours' where id='P4'`);
await varrer();
teste('1d pronto sem estafeta e a caminho geram evento; pedido agendado para o futuro não',
  (await eventos(`chave_dedup in ('pedido:P2:sem_estafeta','pedido:P3:a_caminho')`)).length === 2 && (await eventos(`chave_dedup like 'pedido:P4:%'`)).length === 0);

// (6) pedido de teste não gera nada
await exec(`insert into orders(id,restaurant_id,order_type,status,created_at,status_updated_at,is_test_order) values ('T1','R1','partnerRestaurant','created', now()-interval '40 minutes', now()-interval '40 minutes', true)`);
await varrer();
teste('6 pedido de teste (is_test_order) não gera nada', (await eventos(`chave_dedup like 'pedido:T1:%'`)).length === 0);

// serviços: TVDE, reserva, marcação, encomenda por telefone
await exec(`insert into tvde_rides(status,created_at) values ('solicitada', now()-interval '10 minutes'), ('agendada', now()-interval '10 minutes')`);
await exec(`insert into reservations(status,created_at,reserved_for) values ('pending', now()-interval '40 minutes', now()+interval '1 day')`);
await exec(`insert into appointments(status,awaiting_since) values ('awaiting_confirmation', now()-interval '3 hours')`);
await exec(`insert into encomendas_telefone(order_id,criado_em) values ('E1', now()-interval '45 minutes'), ('E2', now()-interval '45 minutes')`);
await exec(`update encomendas_telefone set cancelado_em=now() where order_id='E2'`);
await varrer();
teste('3a TVDE, reserva, marcação e encomenda por telefone (a cancelada não) geram 1 evento cada',
  (await eventos(`chave_dedup like 'tvde:%'`)).length === 1 && (await eventos(`chave_dedup like 'reserva:%'`)).length === 1 &&
  (await eventos(`chave_dedup like 'marcacao:%'`)).length === 1 && (await eventos(`chave_dedup like 'encomenda_tel:%'`)).length === 1);
const m = await um(`select gravidade from sentinela_eventos where chave_dedup like 'marcacao:%'`);
teste('3b marcação por confirmar é normal e não cria despacho', m.gravidade === 'normal' && (await um(`select count(*)::int c from sentinela_eventos where chave_dedup like 'marcacao:%' and despacho_id is not null`)).c === 0);

// pagamento estranho
await exec(`insert into payment_drafts_alertados(draft_id,alertado_em) values (gen_random_uuid(), now()-interval '2 minutes'), (gen_random_uuid(), now()-interval '3 hours')`);
await exec(`insert into payment_reconciliation_findings(kind,severity,entity_type,entity_id,run_at) values ('orfao','high','order','P1', now()-interval '1 minute')`);
await varrer();
teste('3c pagamento estranho: só achados novos (2 eventos urgentes)', (await eventos(`tipo='pagamento_estranho' and gravidade='urgente'`)).length === 2);

// (3) carrinho: info, sem despacho
await exec(`update platform_settings set value='0' where key='sentinela_carrinho_hora'`);
await exec(`insert into carrinhos_abandonados(user_id,n_itens,atualizado_em) values (gen_random_uuid(), 2, now()), (gen_random_uuid(), 1, now()), (gen_random_uuid(), 1, now()-interval '5 days')`);
await exec(`insert into carrinhos_abandonados(user_id,n_itens,atualizado_em,convertido_em) values (gen_random_uuid(), 1, now(), now())`);
await varrer(); await varrer();
const car = await eventos(`tipo='carrinho_abandonado'`);
teste('3 carrinho: 1 evento info por dia, com a contagem, sem despacho',
  car.length === 1 && car[0].gravidade === 'info' && car[0].despacho_id === null && car[0].dados.abandonados === 2 && car[0].dados.convertidos === 1, JSON.stringify(car));

// (4) erro repetido N vezes -> 1 evento normal; 2 vezes -> nada
await exec(`insert into order_lifecycle_errors(order_id,component,error_message) select 'X'||g, 'compA', 'falhou o passo 12345678-aaaa-bbbb por a@b.pt' from generate_series(1,3) g`);
await exec(`insert into order_lifecycle_errors(order_id,component,error_message) select 'Y'||g, 'compB', 'outro erro' from generate_series(1,2) g`);
await varrer(); await varrer();
const er = await eventos(`tipo='erro_repetido' and chave_dedup like 'erro:ciclo:%'`);
teste('4a erro repetido 3 vezes gera 1 evento normal (2 vezes não gera)', er.length === 1 && er[0].gravidade === 'normal' && er[0].dados.vezes === 3, JSON.stringify(er));
teste('4b a amostra do erro não leva email nem id longo', er.length === 1 && !JSON.stringify(er[0].dados).includes('a@b.pt') && !JSON.stringify(er[0].dados).includes('12345678'), JSON.stringify(er[0]?.dados));

// tarefa agendada falhada: 1 falha = normal; 3 seguidas = urgente
await exec(`insert into cron.job(jobname,schedule,command) values ('job-a','* * * * *','x'),('job-b','* * * * *','y')`);
await exec(`insert into cron.job_run_details(jobid,status,start_time) select (select jobid from cron.job where jobname='job-a'),'failed', now()-interval '1 minute'`);
await exec(`insert into cron.job_run_details(jobid,status,start_time) select (select jobid from cron.job where jobname='job-b'),'failed', now()-g*interval '1 minute' from generate_series(1,3) g`);
await varrer();
const cr = await q(`select titulo, gravidade from sentinela_eventos where chave_dedup like 'erro:cron:%' order by titulo`);
teste('4c cron falhado: 1 falha normal, 3 seguidas urgente', cr.length === 2 && cr.find(x => x.titulo.includes('job-a'))?.gravidade === 'normal' && cr.find(x => x.titulo.includes('job-b'))?.gravidade === 'urgente', JSON.stringify(cr));

// (5) conversa com pedido de humano: urgente, sem texto no JSON
const SID = (await um(`insert into support_chatbot_sessions(ultima_msg_em) values (now()) returning id`)).id;
await exec(`insert into support_chatbot_messages(session_id,role,content,created_at) values ('${SID}','user','Quero falar com uma pessoa, o meu email é joao@exemplo.pt e o telefone 912345678', now()-interval '1 minute')`);
await exec(`insert into whatsapp_contacts(numero,ultima_msg_em) values ('351912345678', now())`);
await exec(`insert into whatsapp_messages(numero,direcao,texto,created_at) values ('351912345678','entrada','isto é uma reclamação, não resolve nada', now()-interval '1 minute')`);
const AID = (await um(`insert into assistant_conversations(status,last_message_at) values ('open', now()-interval '20 minutes') returning id`)).id;
await exec(`insert into assistant_chat_messages(conversation_id,role,content,created_at) values ('${AID}','user','quanto custa a entrega?', now()-interval '20 minutes')`);
await exec(`insert into support_tickets(satisfaction,created_at) values (1, now())`);
await varrer();
const ro = await eventos(`tipo='robo_em_apuros'`);
const txt = JSON.stringify(ro.map(e => [e.titulo, e.dados]));
const porMotivo = (rob, mot) => ro.find(e => e.dados.robo === rob && e.dados.motivo === mot);
teste('5a pedido de humano no suporte é urgente e cria despacho', porMotivo('suporte', 'pede_humano')?.gravidade === 'urgente' && porMotivo('suporte', 'pede_humano')?.despacho_id != null, ro.map(e => e.chave_dedup).join(' ; '));
teste('5b o JSON dos eventos não tem texto da conversa, email nem telefone', ro.length > 0 && !/joao@|912345678|Quero falar|reclamação|não resolve|351912|quanto custa/i.test(txt), txt);
teste('5c WhatsApp pede humano (urgente), Amigo sem resposta e nota baixa (normais)',
  porMotivo('whatsapp', 'pede_humano')?.gravidade === 'urgente' && porMotivo('amigo', 'sem_resposta')?.gravidade === 'normal' && porMotivo('suporte', 'nota_baixa')?.gravidade === 'normal',
  ro.map(e => e.chave_dedup).join(' ; '));
const totalUrg = (await um(`select count(*)::int c from sentinela_eventos where gravidade='urgente'`)).c;
const totalDesp = (await um(`select count(*)::int c from despacho where origem='evento' and prioridade=90`)).c;
teste('5d cada evento urgente tem exatamente 1 despacho (info/normal nenhum)', totalUrg === totalDesp && (await um(`select count(*)::int c from sentinela_eventos where gravidade<>'urgente' and despacho_id is not null`)).c === 0, `${totalUrg} urgentes vs ${totalDesp} despachos`);

// permissões
await exec(`set role authenticated`);
let negou = false; try { await db.query(`select public.sentinela_varrer()`); } catch (e) { negou = /permission denied/.test(e.message); }
await exec(`reset role`);
teste('P1 um utilizador autenticado não pode correr a varredura', negou);
await exec(`set role anon`);
let negouAnon = false; try { await db.query(`select * from public.sentinela_estado`); } catch (e) { negouAnon = /permission denied/.test(e.message); }
await exec(`reset role`);
teste('P2 anon não lê o estado da varredura', negouAnon);

// (8) um detetor a rebentar (tabela em falta) não impede os outros
await exec(`drop table tvde_rides`);
await exec(`insert into orders(id,restaurant_id,order_type,status,created_at,status_updated_at) values ('P9','R1','takeaway','created', now()-interval '25 minutes', now()-interval '25 minutes')`);
const rr = await varrer();
const est = await um(`select * from sentinela_estado where id=1`);
teste('8a detetor com tabela em falta não pára os outros (pedido novo detetado; erro no estado)',
  rr.por_detetor.servicos === 'erro' && rr.detetores_com_erro === 1 && (await eventos(`chave_dedup='pedido:P9:loja'`)).length === 1 && /tvde_rides/.test(est.ultimo_erro || ''), JSON.stringify(rr) + ' ' + est.ultimo_erro);
teste('8b estado da varredura guardado (hora, duração, eventos novos)', est.ultima_varredura != null && est.duracao_ms != null && est.eventos_novos === 1, JSON.stringify(est));

// (7) com sentinela_ligada=false nada é criado
await exec(`update platform_settings set value='false' where key='sentinela_ligada'`);
const antes = (await um(`select count(*)::int c from sentinela_eventos`)).c;
const antesD = (await um(`select count(*)::int c from despacho`)).c;
await exec(`insert into orders(id,restaurant_id,order_type,status,created_at,status_updated_at) values ('P10','R1','takeaway','created', now()-interval '25 minutes', now()-interval '25 minutes')`);
const rd = await varrer();
const depois = (await um(`select count(*)::int c from sentinela_eventos`)).c;
const depoisD = (await um(`select count(*)::int c from despacho`)).c;
teste('7a com sentinela_ligada=false nada é criado', rd.ligada === false && antes === depois && antesD === depoisD, JSON.stringify(rd));
await exec(`update platform_settings set value='true' where key='sentinela_ligada'`);
await varrer();
teste('7b ao religar, o pedido parado é apanhado', (await eventos(`chave_dedup='pedido:P10:loja'`)).length === 1);

console.log(`\nRESULTADO: ${ok.length} passaram, ${falhou.length} falharam`);
if (falhou.length) { console.log(falhou.join('\n')); process.exit(1); }
