// Prova local (PGlite = Postgres real em WASM) da PROPOSTA
// docs/propostas/fechar-app-15-11/3f-favor-a-estafeta-ocupado.md — fechar-app-15-11, Bloco 3 (f).
//
// O SQL provado é o que está ESCRITO na proposta (entre <!-- SQL-3F:INICIO --> e
// <!-- SQL-3F:FIM -->): não há segunda cópia. As funções "de produção" obtêm-se
// tirando à proposta as linhas entre "-- >>> 3f" e "-- <<< 3f"; o md5 do corpo tem
// de dar o de produção (lido a 14/11/2026), senão a prova pára.
//
// Porquê local: a tranca recusa DDL de despacho em produção, mesmo em rollback.
// Aqui montam-se réplicas pequenas das tabelas (só as colunas que as duas funções
// tocam) e funções de apoio a fingir (motor, guarda fiscal, alcance do estafeta,
// admin_reassign_order). O que NÃO se prova aqui: dois aceites ao mesmo tempo
// (o PGlite tem uma só ligação) e os gatilhos verdadeiros da tabela orders.
//
// Uso: node supabase/tests/fechar_app_3f_prova.mjs <pasta-com-node_modules-do-pglite>
//
// Teste anti-mentira: MUTACAO="texto=>outro" estraga a proposta de propósito; a
// prova TEM de falhar. Dois estragos que ela apanha:
//   MUTACAO="IF v_ativos > 0 THEN=>IF v_ativos > 99 THEN"
//   MUTACAO="o.service_type = 'errand' INTO v_favor=>o.service_type = 'outro' INTO v_favor"

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

const ler = (...p) => readFileSync(path.join(aqui, ...p), 'utf8').replace(/\r\n/g, '\n');
const doc = ler('..', '..', 'docs', 'propostas', 'fechar-app-15-11', '3f-favor-a-estafeta-ocupado.md');
const bloco = (doc.match(/<!-- SQL-3F:INICIO -->\n```sql\n([\s\S]*?)\n```\n<!-- SQL-3F:FIM -->/) ?? [])[1];
if (!bloco) throw new Error('não encontrei o bloco SQL-3F na proposta');

/// A proposta sem as linhas novas = o que está em produção.
const semLinhasNovas = (sql) => {
  const fora = [];
  let dentro = false;
  for (const linha of sql.split('\n')) {
    if (linha.includes('-- >>> 3f')) { dentro = true; continue; }
    if (linha.includes('-- <<< 3f')) { dentro = false; continue; }
    if (!dentro) fora.push(linha);
  }
  if (dentro) throw new Error('marcador "-- >>> 3f" sem fecho');
  return fora.join('\n');
};
const producao = semLinhasNovas(bloco);

let proposta = bloco;
if (process.env.MUTACAO) {
  const [de, para] = process.env.MUTACAO.split('=>');
  if (!proposta.includes(de)) throw new Error(`mutação não encontrada: ${de}`);
  proposta = proposta.split(de).join(para);
  console.log(`MUTAÇÃO aplicada: ${de} => ${para}`);
}

// md5(prosrc) e length(prosrc) em PRODUÇÃO, lidos a 14/11/2026 23:3x UTC.
const PROD = {
  'public.driver_accept_offer(text)': { md5: '1bd68d8d36fcde2ed7c08af8082aade3', len: 2162 },
  'public.ops_reassign_order(text, text, text, text, boolean)': { md5: '2edbd2d9778d032506ed7481ac36d3d6', len: 3652 },
};

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

// Estafetas de prova (identificadores inventados).
const E1 = '11111111-1111-4111-8111-111111111111'; // drivers.id = user_id (como o de 14/11)
const E2_USER = '22222222-2222-4222-8222-222222222222'; // legado: drivers.id diferente do user_id
const E2_ID = '2222aaaa-2222-4222-8222-222222222222';
const E3 = '33333333-3333-4333-8333-333333333333'; // livre

await db.exec(`
  create schema auth;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

  create table public.drivers (id uuid primary key, user_id uuid, phone text, name text);
  create table public.orders (
    id text primary key,
    status text not null,
    service_type text,
    errand_speed text,
    assigned_driver_id text,
    driver_id uuid,
    current_driver_offer_id text,
    driver_offer_expires_at timestamptz,
    driver_phone text,
    tried_driver_ids text[],
    dispatch_last_tick_at timestamptz
  );

  -- o motor a fingir: só regista que foi acordado
  create table public._motor_chamado (order_id text, em timestamptz default clock_timestamp());
  create function public.invoke_dispatch_engine(p_order_id text default null) returns void
    language sql as $$ insert into public._motor_chamado (order_id) values (p_order_id) $$;

  -- a guarda fiscal a fingir: bloqueado quem estiver nesta tabela
  create table public._fiscal_bloqueados (uid uuid primary key);
  create function public._estafeta_fiscal_bloqueado(p_uid uuid) returns boolean
    language sql stable as $$ select exists (select 1 from public._fiscal_bloqueados f where f.uid = p_uid) $$;

  -- apoio do ops_reassign_order
  create table public.admin_audit_log (
    id bigserial primary key, action text, entity_type text, entity_id_text text,
    admin_email text, admin_id uuid, details jsonb);
  create function public._driver_reachability(p_ref text)
    returns table (driver_id uuid, user_id uuid, name text, is_banned boolean, online_agora boolean,
                   tem_notificacoes boolean, last_heartbeat_at timestamptz, last_platform text,
                   approval_status text)
    language sql stable as $$
      select d.id, d.user_id, d.name, false, true, true, now(), 'android', 'approved'
        from public.drivers d
       where d.id::text = p_ref or d.user_id::text = p_ref
       limit 1 $$;
  -- o mesmo efeito do admin_reassign_order de produção num pedido já pronto
  create function public.admin_reassign_order(p_order_id text, p_new_driver text, p_motivo text default '')
    returns jsonb language plpgsql as $$
    declare v_d record; v_new text;
    begin
      select d.id, d.user_id, d.name into v_d from public.drivers d
       where d.id::text = p_new_driver or d.user_id::text = p_new_driver limit 1;
      v_new := coalesce(v_d.user_id, v_d.id)::text;
      update public.orders
         set assigned_driver_id = v_new, driver_id = coalesce(v_d.user_id, v_d.id),
             current_driver_offer_id = null, driver_offer_expires_at = null,
             status = case when status = 'callingDriver' then 'driverAccepted' else status end
       where id = p_order_id;
      return jsonb_build_object('ok', true, 'estafeta', v_d.name, 'novo_driver', v_new, 'pre_atribuicao', false);
    end $$;
`);

/// Recomeça do zero: três estafetas, nenhum pedido.
const limpar = async () => {
  await db.exec(`
    truncate public.orders, public.drivers, public._motor_chamado, public._fiscal_bloqueados;
    truncate public.admin_audit_log restart identity;
  `);
  await db.query(`insert into public.drivers (id, user_id, phone, name) values
    ($1, $1, '000', 'Estafeta Um'), ($2, $3, '000', 'Estafeta Dois'), ($4, $4, '000', 'Estafeta Três')`,
    [E1, E2_ID, E2_USER, E3]);
};
const pedido = async (id, serviceType, status, atribuido = null) =>
  db.query(`insert into public.orders (id, service_type, status, assigned_driver_id, driver_id)
            values ($1, $2, $3, $4, $5)`,
    [id, serviceType, status, atribuido, atribuido && atribuido !== E2_ID ? atribuido : atribuido ? E2_USER : null]);
/// A oferta escrita à mão: a MESMA frase do registo de 14/11 16:32:00.
const ofertaAMao = async (id, uid) =>
  db.query(`update orders set current_driver_offer_id=$2,
              driver_offer_expires_at=now()+interval '120 seconds', dispatch_last_tick_at=now()
            where id=$1 and status='callingDriver' and assigned_driver_id is null
              and current_driver_offer_id is null`, [id, uid]);
const aceitar = async (uid, id) => {
  await como(uid);
  return (await um(`select public.driver_accept_offer($1) r`, [id])).r;
};
const ver = async (id) => um(`select * from public.orders where id = $1`, [id]);
const ativosDe = async (uid) => (await um(
  `select count(*)::int n from public.orders
    where status in ('driverAccepted','pickedUp','onTheWay') and assigned_driver_id = $1`, [uid])).n;
const motor = async () => (await q(`select order_id from public._motor_chamado order by em`)).map((r) => r.order_id);
const corpo = async (assinatura) =>
  um(`select md5(prosrc) md5, length(prosrc) len, prosrc, prosecdef, proconfig
        from pg_proc where oid = $1::regprocedure`, [assinatura]);

// ─────────────────────────────────────────────────────────────────────────────
console.log('0) as funções de partida são as de produção (md5 do corpo)');
await db.exec(producao);
for (const [assinatura, esperado] of Object.entries(PROD)) {
  const f = await corpo(assinatura);
  certo(`${assinatura.split('(')[0]}: proposta sem as linhas "3f" = produção (${esperado.len} caracteres)`,
    f.md5 === esperado.md5 && f.len === esperado.len, `md5=${f.md5} len=${f.len}`);
}

console.log('\n1) o caso de 14/11 com as funções de produção: o defeito repete-se');
await limpar();
await pedido('auchan', 'storeShopping', 'driverAccepted', E1);
await pedido('favor', 'errand', 'callingDriver');
await ofertaAMao('favor', E1);
let r = await aceitar(E1, 'favor');
certo('produção: o estafeta ocupado aceita o Favor (ok=true)', r.ok === true, JSON.stringify(r));
certo('produção: fica com 2 pedidos em mãos (Auchan + Favor)', (await ativosDe(E1)) === 2);

await limpar();
await pedido('auchan', 'storeShopping', 'driverAccepted', E1);
await pedido('favor', 'errand', 'callingDriver');
await como(null);
r = (await um(`select public.ops_reassign_order('favor', $1, 'pedido do Danilo', 'prova') r`, [E1])).r;
certo('produção: o caminho dos agentes também dá o Favor ao ocupado', r.ok === true && (await ativosDe(E1)) === 2,
  JSON.stringify(r));

// ─────────────────────────────────────────────────────────────────────────────
console.log('\n2) aplica-se a proposta tal como está escrita');
await db.exec(proposta);
for (const assinatura of Object.keys(PROD)) {
  const f = await corpo(assinatura);
  certo(`${assinatura.split('(')[0]}: o corpo mudou e traz as linhas "3f"`,
    f.md5 !== PROD[assinatura].md5 && f.prosrc.includes('-- >>> 3f') && f.prosrc.includes('-- <<< 3f'));
}

console.log('\n3) o mesmo caso de 14/11, agora com a proposta');
await limpar();
await pedido('auchan', 'storeShopping', 'driverAccepted', E1);
await pedido('favor', 'errand', 'callingDriver');
await ofertaAMao('favor', E1);
certo('a oferta à mão ficou escrita (a proposta não mexe em quem escreve ofertas)',
  (await ver('favor')).current_driver_offer_id === E1);
r = await aceitar(E1, 'favor');
certo('aceitar responde ok=false, offer_expired_or_taken, motivo favor_so_com_estafeta_livre, ativos=1',
  r.ok === false && r.error === 'offer_expired_or_taken' && r.motivo === 'favor_so_com_estafeta_livre' && r.ativos === 1,
  JSON.stringify(r));
let f = await ver('favor');
certo('o Favor continua à procura (callingDriver), sem estafeta',
  f.status === 'callingDriver' && f.assigned_driver_id === null && f.driver_id === null, JSON.stringify(f));
certo('a oferta foi largada (não fica presa 120 s no estafeta ocupado)',
  f.current_driver_offer_id === null && f.driver_offer_expires_at === null);
certo('o estafeta NÃO ficou marcado como tentado', f.tried_driver_ids === null);
certo('o motor foi acordado uma vez, para este Favor', JSON.stringify(await motor()) === JSON.stringify(['favor']));
const a = await ver('auchan');
certo('o pedido que ele tinha em mãos ficou igual', a.status === 'driverAccepted' && a.assigned_driver_id === E1);
certo('o estafeta continua só com 1 pedido', (await ativosDe(E1)) === 1);

console.log('\n4) quando ele fica livre, o Favor volta a poder ser dele');
await db.query(`update public.orders set status = 'delivered' where id = 'auchan'`);
await ofertaAMao('favor', E1); // aqui faz de motor: já não há pedido em mãos
r = await aceitar(E1, 'favor');
f = await ver('favor');
certo('livre: aceita o Favor (ok=true) e fica com ele',
  r.ok === true && f.status === 'driverAccepted' && f.assigned_driver_id === E1 && f.driver_id === E1, JSON.stringify(r));
r = await aceitar(E1, 'favor');
certo('repetir o aceite continua a responder idempotent=true', r.ok === true && r.idempotent === true, JSON.stringify(r));

console.log('\n5) o que não pode mudar no aceitar');
await limpar();
await pedido('favor', 'errand', 'callingDriver');
await ofertaAMao('favor', E3);
r = await aceitar(E3, 'favor');
certo('estafeta livre aceita um Favor', r.ok === true && (await ver('favor')).assigned_driver_id === E3, JSON.stringify(r));

await limpar();
await pedido('entrega-1', 'restaurant', 'pickedUp', E1);
await pedido('entrega-2', 'restaurant', 'callingDriver');
await ofertaAMao('entrega-2', E1);
r = await aceitar(E1, 'entrega-2');
certo('estafeta com uma entrega aceita OUTRA entrega (pedidos em cima uns dos outros, como hoje)',
  r.ok === true && (await ativosDe(E1)) === 2, JSON.stringify(r));
certo('e o motor não foi acordado por causa disso', (await motor()).length === 0);

await limpar();
await pedido('favor-em-curso', 'errand', 'driverAccepted', E1);
await pedido('entrega', 'restaurant', 'callingDriver');
await ofertaAMao('entrega', E1);
r = await aceitar(E1, 'entrega');
certo('quem tem um Favor em curso ainda pode aceitar uma entrega que lhe ofereçam (não é esta regra)',
  r.ok === true, JSON.stringify(r));

await limpar();
await pedido('antigo', 'restaurant', 'onTheWay', E2_ID); // atribuído pela chave antiga (drivers.id)
await pedido('favor', 'errand', 'callingDriver');
await ofertaAMao('favor', E2_USER);
r = await aceitar(E2_USER, 'favor');
certo('pedido em mãos guardado com drivers.id (legado) também conta como ocupado',
  r.ok === false && r.motivo === 'favor_so_com_estafeta_livre' && r.ativos === 1, JSON.stringify(r));

await limpar();
await pedido('entregue', 'restaurant', 'delivered', E1);
await pedido('cancelado', 'restaurant', 'cancelled', E1);
await pedido('de-outro', 'restaurant', 'onTheWay', E3);
await pedido('favor', 'errand', 'callingDriver');
await ofertaAMao('favor', E1);
r = await aceitar(E1, 'favor');
certo('pedidos já entregues, cancelados ou de outro estafeta não contam', r.ok === true, JSON.stringify(r));

await limpar();
await pedido('favor', 'errand', 'callingDriver');
await ofertaAMao('favor', E3);
r = await aceitar(E1, 'favor');
f = await ver('favor');
certo('oferta de outro estafeta: offer_expired_or_taken sem motivo, e a oferta do outro fica intacta',
  r.ok === false && r.error === 'offer_expired_or_taken' && r.motivo === undefined &&
  f.current_driver_offer_id === E3 && (await motor()).length === 0, JSON.stringify(r));

await limpar();
await db.query(`insert into public._fiscal_bloqueados values ($1)`, [E3]);
await pedido('entrega', 'restaurant', 'callingDriver');
await ofertaAMao('entrega', E3);
r = await aceitar(E3, 'entrega');
certo('a trava fiscal continua a responder estafeta_sem_nif_atividade',
  r.ok === false && r.error === 'estafeta_sem_nif_atividade', JSON.stringify(r));

r = await aceitar(null, 'entrega');
certo('sem sessão continua unauthorized', r.ok === false && r.error === 'unauthorized', JSON.stringify(r));

// ─────────────────────────────────────────────────────────────────────────────
console.log('\n6) o caminho dos agentes (ops_reassign_order) com a proposta');
const ops = async (id, estafeta, forcar = false) => {
  await como(null);
  return (await um(`select public.ops_reassign_order($1, $2, 'motivo de prova', 'prova', $3) r`,
    [id, estafeta, forcar])).r;
};
const auditorias = async () => (await um(`select count(*)::int n from public.admin_audit_log`)).n;

await limpar();
await pedido('auchan', 'storeShopping', 'driverAccepted', E1);
await pedido('favor', 'errand', 'callingDriver');
r = await ops('favor', E1);
f = await ver('favor');
certo('Favor pronto + estafeta ocupado: ok=false, favor_so_com_estafeta_livre, pedidos_em_maos=1',
  r.ok === false && r.error === 'favor_so_com_estafeta_livre' && r.pedidos_em_maos === 1 &&
  typeof r.o_que_fazer === 'string' && r.estafeta === 'Estafeta Um', JSON.stringify(r));
certo('o pedido não mexeu e não ficou linha de auditoria',
  f.status === 'callingDriver' && f.assigned_driver_id === null && (await auditorias()) === 0);

r = await ops('favor', E1, true);
f = await ver('favor');
let aud = await um(`select details from public.admin_audit_log order by id desc limit 1`);
certo('com p_forcar => true (ordem do Danilo) passa, e a auditoria diz forcado=true',
  r.ok === true && r.forcado === true && f.status === 'driverAccepted' && f.assigned_driver_id === E1 &&
  aud?.details?.forcado === true, JSON.stringify(r));

await limpar();
await pedido('favor', 'errand', 'callingDriver');
r = await ops('favor', E3);
certo('Favor + estafeta livre: passa como hoje', r.ok === true && (await ver('favor')).assigned_driver_id === E3,
  JSON.stringify(r));

await limpar();
await pedido('entrega-1', 'restaurant', 'onTheWay', E1);
await pedido('entrega-2', 'restaurant', 'callingDriver');
r = await ops('entrega-2', E1);
certo('entrega normal + estafeta ocupado: passa como hoje', r.ok === true && (await ativosDe(E1)) === 2,
  JSON.stringify(r));

await limpar();
await pedido('auchan', 'storeShopping', 'driverAccepted', E1);
await pedido('favor-agendado', 'errand', 'preparing');
r = await ops('favor-agendado', E1);
certo('Favor ainda não pronto (reserva para mais tarde): a regra nova não se mete',
  r.error !== 'favor_so_com_estafeta_livre' && r.pre_atribuicao === true, JSON.stringify(r));

await limpar();
await pedido('antigo', 'restaurant', 'pickedUp', E2_ID);
await pedido('favor', 'errand', 'callingDriver');
r = await ops('favor', E2_USER);
certo('ocupado pela chave antiga (drivers.id) também conta',
  r.ok === false && r.error === 'favor_so_com_estafeta_livre', JSON.stringify(r));

await limpar();
await pedido('favor', 'errand', 'driverAccepted', E1);
r = await ops('favor', E1);
certo('o próprio Favor não conta como "pedido em mãos" do estafeta', r.error !== 'favor_so_com_estafeta_livre',
  JSON.stringify(r));

await como(null);
r = (await um(`select public.ops_reassign_order('favor', $1, '', 'prova') r`, [E1])).r;
certo('sem motivo continua agente_e_motivo_obrigatorios', r.error === 'agente_e_motivo_obrigatorios', JSON.stringify(r));

// ─────────────────────────────────────────────────────────────────────────────
console.log('\n7) as funções continuam com a mesma forma');
let fn = await corpo('public.driver_accept_offer(text)');
certo('driver_accept_offer: SECURITY DEFINER com search_path vazio',
  fn.prosecdef === true && JSON.stringify(fn.proconfig) === JSON.stringify(['search_path=""']), JSON.stringify(fn.proconfig));
certo('driver_accept_offer: a guarda é auth.uid(), nunca current_user',
  fn.prosrc.includes('auth.uid()') && !/current_user|session_user/.test(fn.prosrc));
certo('driver_accept_offer: tudo o que é novo vem com o esquema (search_path vazio)',
  !/\b(FROM|UPDATE|JOIN)\s+(orders|drivers)\b/i.test(fn.prosrc));
fn = await corpo('public.ops_reassign_order(text, text, text, text, boolean)');
certo('ops_reassign_order: SECURITY DEFINER com search_path=public',
  fn.prosecdef === true && JSON.stringify(fn.proconfig) === JSON.stringify(['search_path=public']), JSON.stringify(fn.proconfig));

console.log(`\nRESULTADO: ${ok} certos, ${falhas} falhados`);
process.exit(falhas ? 1 : 0);
