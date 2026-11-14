// Prova local (PGlite = Postgres real em WASM) da PROPOSTA
// docs/propostas/fechar-app-15-11/3g-estado-dos-itens-depois-do-talao.md — fechar-app-15-11, Bloco 3 (g).
//
// O SQL provado é o que está ESCRITO na proposta (entre <!-- SQL-3G:INICIO --> e
// <!-- SQL-3G:FIM -->, e o Passo B entre <!-- SQL-3G-ANTIGOS:… -->): não há segunda cópia.
//
// Porquê local: a tranca recusa DDL em produção, mesmo em rollback. Aqui montam-se
// réplicas pequenas de orders e de order_purchase_items_v2 (colunas lidas de produção
// a 14/11/2026), o gatilho trg_opi_v2_block_duplicate COM O TEXTO DE PRODUÇÃO, e um
// "fecho de prova": as três frases de finalizar_talao_nao_parceiro que interessam,
// pela mesma ordem (linhas 146–180 gravar o talão; 285–293 marcar fechado; 342–343
// passar a onTheWay). A função verdadeira não corre aqui (precisa de meia base atrás).
// O que NÃO se prova aqui: a convivência com os outros gatilhos de orders.
//
// Uso: node supabase/tests/fechar_app_3g_prova.mjs <pasta-com-node_modules-do-pglite>
//
// Teste anti-mentira: MUTACAO="texto=>outro" estraga a proposta de propósito; a
// prova TEM de falhar. Dois estragos que ela apanha:
//   MUTACAO="WHEN 'purchased' THEN 'bought'=>WHEN 'purchased' THEN 'pending'"
//   MUTACAO="BEFORE UPDATE OF status ON public.orders=>BEFORE UPDATE OF price ON public.orders"

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
const doc = ler('..', '..', 'docs', 'propostas', 'fechar-app-15-11', '3g-estado-dos-itens-depois-do-talao.md');
const blocoDe = (nome) => {
  const m = doc.match(new RegExp(`<!-- ${nome}:INICIO -->\\n\`\`\`sql\\n([\\s\\S]*?)\\n\`\`\`\\n<!-- ${nome}:FIM -->`));
  if (!m) throw new Error(`não encontrei o bloco ${nome} na proposta`);
  return m[1];
};
let proposta = blocoDe('SQL-3G');
const antigos = blocoDe('SQL-3G-ANTIGOS');
if (process.env.MUTACAO) {
  const [de, para] = process.env.MUTACAO.split('=>');
  if (!proposta.includes(de)) throw new Error(`mutação não encontrada: ${de}`);
  proposta = proposta.split(de).join(para);
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

await db.exec(`
  create role anon nologin;
  create role authenticated nologin;

  create table public.orders (
    id text primary key,
    status text not null,
    service_type text,
    items jsonb,
    is_purchase_finalized boolean default false,
    purchase_flow_version integer default 1,
    price numeric, subtotal numeric, final_total numeric, final_purchase_value numeric,
    bag_fee numeric, delivery_fee numeric
  );

  create table public.order_purchase_items_v2 (
    id uuid primary key default gen_random_uuid(),
    order_id text not null,
    original_item_id text,
    original_name text,
    original_price_cents integer,
    original_qty smallint,
    status text,
    actual_name text,
    actual_price_cents integer,
    actual_qty smallint,
    client_confirmed_at timestamptz,
    client_confirmation_message_id uuid,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
  );
  create index idx_order_purchase_items_v2_order on public.order_purchase_items_v2 (order_id);

  -- TEXTO DE PRODUÇÃO (pg_get_functiondef a 14/11/2026): junta linhas iguais do talão.
  CREATE OR REPLACE FUNCTION public.fn_opi_v2_block_duplicate()
   RETURNS trigger
   LANGUAGE plpgsql
   SET search_path TO 'public', 'pg_temp'
  AS $function$
  begin
    if exists (
      select 1
      from public.order_purchase_items_v2 t
      where t.order_id = new.order_id
        and coalesce(t.original_name, '') = coalesce(new.original_name, '')
        and coalesce(t.status, '') = coalesce(new.status, '')
        and coalesce(t.original_qty, -1) = coalesce(new.original_qty, -1)
        and coalesce(t.original_price_cents, -1) = coalesce(new.original_price_cents, -1)
    ) then
      return null;
    end if;
    return new;
  end;
  $function$;
  create trigger trg_opi_v2_block_duplicate before insert on public.order_purchase_items_v2
    for each row execute function public.fn_opi_v2_block_duplicate();

  -- FECHO DE PROVA: as três frases de finalizar_talao_nao_parceiro que interessam,
  -- pela ordem de produção. O identificador do produto só entra se parecer um UUID,
  -- tal como em produção (é por isso que em produção está quase sempre vazio).
  create function public._fecho_de_prova(p_order_id text, p_items jsonb) returns integer
  language plpgsql as $$
  declare v_item jsonb; v_rows integer;
  begin
    for v_item in select * from jsonb_array_elements(p_items) loop
      insert into public.order_purchase_items_v2 (
        order_id, original_item_id, original_name, original_price_cents, original_qty, status,
        actual_name, actual_price_cents, actual_qty)
      values (
        p_order_id,
        case when nullif(v_item->>'original_item_id','') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then (v_item->>'original_item_id')::uuid else null end,
        coalesce(v_item->>'original_name',''),
        coalesce((v_item->>'original_price_cents')::integer, 0),
        coalesce((v_item->>'original_qty')::smallint, 1),
        coalesce(v_item->>'status','pending'),
        v_item->>'actual_name',
        nullif(v_item->>'actual_price_cents','')::integer,
        nullif(v_item->>'actual_qty','')::smallint);
    end loop;
    update public.orders set
      final_total = 32.27,
      final_purchase_value = 24.39,
      is_purchase_finalized = true,
      purchase_flow_version = 2
    where id = p_order_id;
    update public.orders set status = 'onTheWay'
     where id = p_order_id and status in ('driverAccepted', 'pickedUp');
    get diagnostics v_rows = row_count;
    return v_rows;
  end $$;
`);

// A compra do pedido de 14/11 (b2b746d7): os preços, as quantidades e o que aconteceu a
// cada produto são os de produção; os nomes são inventados (não interessam à prova).
// [nome, preço, quantidade, o que aconteceu, (trocado por: nome, cêntimos, quantidade)]
const COMPRA = [
  ['Produto A', 3.05, 1, 'purchased'],
  ['Produto B', 3.32, 1, 'purchased'],
  ['Produto C', 1.9, 1, 'unavailable'],
  ['Produto D', 1.02, 2, 'purchased'],
  ['Produto E', 0.49, 6, 'purchased'],
  ['Produto F', 3.43, 1, 'replaced', 'Outro F', 213, 1],
  ['Produto G', 0.93, 2, 'purchased'],
  ['Produto H', 2.06, 1, 'replaced', 'Outro H', 137, 1],
  ['Produto I', 0.45, 4, 'purchased'],
  ['Produto J', 2.83, 1, 'purchased'],
  ['Produto K', 2.67, 1, 'unavailable'],
  ['Produto L', 2.83, 2, 'replaced', 'Outro L', 332, 2],
];
const ESPERADO = { purchased: 'bought', unavailable: 'unavailable', replaced: 'replaced' };

/// A lista do pedido tal como a app a grava ao criar (tudo "pending").
const listaDoPedido = (compra) => compra.map(([nome, preco, qtd], i) => ({
  name: nome, price: preco, quantity: qtd, basePrice: preco, productId: `auc-${1000 + i}`,
  purchaseStatus: 'pending', deposit_cents: i === 4 ? 10 : 0, deposit_units: 0,
}));
/// O p_items do fecho, no formato de TalaoNaoParceiroService.montarItens — baralhado de
/// propósito: em produção a ordem das linhas do talão não é a da lista.
const talaoDe = (compra, extras = []) => {
  const linhas = compra.map(([nome, preco, qtd, estado, outroNome, outroCents, outraQtd], i) => ({
    original_item_id: `auc-${1000 + i}`,
    original_name: nome,
    original_price_cents: Math.round(preco * 100),
    original_qty: qtd,
    status: estado,
    ...(estado === 'replaced'
      ? { actual_name: outroNome, actual_price_cents: outroCents, actual_qty: outraQtd } : {}),
  }));
  return [...linhas.reverse(), ...extras];
};
const criar = async (id, compra, extra = {}) =>
  db.query(
    `insert into public.orders (id, status, service_type, items, price, subtotal, final_total, bag_fee, delivery_fee)
     values ($1, $2, $3, $4::jsonb, 37.75, 33.56, 37.75, 0.2, 2.5)`,
    [id, extra.status ?? 'driverAccepted', extra.service_type ?? 'storeShopping',
      JSON.stringify(extra.items ?? listaDoPedido(compra))]);
const fechar = async (id, talao) =>
  (await um(`select public._fecho_de_prova($1, $2::jsonb) n`, [id, JSON.stringify(talao)])).n;
const ver = async (id) => um(`select * from public.orders where id = $1`, [id]);
const estados = async (id) => (await ver(id)).items.map((i) => i.purchaseStatus);
const semEstado = (items) => items.map(({ purchaseStatus, ...resto }) => resto);
const igual = (x, y) => JSON.stringify(x) === JSON.stringify(y);

// ─────────────────────────────────────────────────────────────────────────────
console.log('1) como está hoje: o fecho grava o talão e a lista fica toda "pending"');
await criar('hoje', COMPRA);
let n = await fechar('hoje', talaoDe(COMPRA));
let p = await ver('hoje');
const linhasHoje = await q(`select status, count(*)::int n, count(original_item_id)::int com_id
                              from public.order_purchase_items_v2 where order_id = 'hoje' group by 1 order by 1`);
certo('o fecho passou o pedido a onTheWay e marcou-o fechado',
  n === 1 && p.status === 'onTheWay' && p.is_purchase_finalized === true);
certo('o talão ficou com 7 comprados, 3 trocados, 2 em falta (como o b2b746d7)',
  igual(linhasHoje.map((l) => [l.status, l.n]), [['purchased', 7], ['replaced', 3], ['unavailable', 2]]),
  JSON.stringify(linhasHoje));
certo('nenhuma linha do talão guardou o identificador do produto (como em produção)',
  linhasHoje.every((l) => l.com_id === 0));
certo('DEFEITO: os 12 produtos da lista continuam "pending"',
  igual(await estados('hoje'), Array(12).fill('pending')), JSON.stringify(await estados('hoje')));

// ─────────────────────────────────────────────────────────────────────────────
console.log('\n2) aplica-se a proposta tal como está escrita');
await db.exec(proposta);
const trg = await um(`select tgenabled, pg_get_triggerdef(oid) def from pg_trigger
                       where tgrelid = 'public.orders'::regclass and tgname = 'trg_orders_itens_estado_do_talao'`);
certo('o gatilho existe, antes da mudança de estado, só para onTheWay/delivered de pedido fechado',
  !!trg && /BEFORE UPDATE OF status/.test(trg.def) && /onTheWay/.test(trg.def) && /delivered/.test(trg.def) &&
  /is_purchase_finalized/.test(trg.def), trg?.def);
const priv = await um(`select
  has_function_privilege('anon', 'public._itens_com_estado_do_talao(text, jsonb)', 'EXECUTE') a1,
  has_function_privilege('authenticated', 'public._itens_com_estado_do_talao(text, jsonb)', 'EXECUTE') a2,
  has_function_privilege('anon', 'public.fn_orders_itens_estado_do_talao()', 'EXECUTE') b1,
  has_function_privilege('authenticated', 'public.fn_orders_itens_estado_do_talao()', 'EXECUTE') b2`);
certo('as duas funções nascem fechadas a anon e a authenticated',
  !priv.a1 && !priv.a2 && !priv.b1 && !priv.b2, JSON.stringify(priv));

console.log('\n3) a mesma compra, agora com a proposta');
await criar('novo', COMPRA);
const antes = await ver('novo');
n = await fechar('novo', talaoDe(COMPRA));
p = await ver('novo');
const esperados = COMPRA.map((c) => ESPERADO[c[3]]);
certo('cada produto ficou com o estado do talão, na posição certa',
  igual(p.items.map((i) => i.purchaseStatus), esperados), JSON.stringify(p.items.map((i) => i.purchaseStatus)));
certo('7 comprados, 3 trocados, 2 em falta; nenhum "pending"',
  esperados.filter((e) => e === 'bought').length === 7 && !p.items.some((i) => i.purchaseStatus === 'pending'));
certo('os dois produtos de 2,83 € (1 e 2 unidades) não se confundem: J comprado, L trocado',
  p.items[9].purchaseStatus === 'bought' && p.items[11].purchaseStatus === 'replaced');
certo('a lista tem os mesmos 12 produtos pela mesma ordem; só mudou o purchaseStatus',
  p.items.length === 12 && igual(semEstado(p.items), semEstado(antes.items)));
certo('o pedido fechou e seguiu como antes (onTheWay, fechado, versão 2)',
  n === 1 && p.status === 'onTheWay' && p.is_purchase_finalized === true && p.purchase_flow_version === 2);
const dinheiro = (o) => [o.price, o.subtotal, o.final_total, o.final_purchase_value, o.bag_fee, o.delivery_fee];
certo('os valores ficaram os que o fecho gravou (os mesmos do pedido sem a proposta)',
  igual(dinheiro(p), dinheiro(await ver('hoje'))), JSON.stringify(dinheiro(p)));

console.log('\n4) casos de fronteira');
// produtos acrescentados pelo estafeta não entram na lista do pedido
await criar('com-extra', COMPRA.slice(0, 3));
await fechar('com-extra', talaoDe(COMPRA.slice(0, 3), [{
  original_name: 'Extra', original_price_cents: 0, original_qty: 1, status: 'added',
  actual_name: 'Extra', actual_price_cents: 150, actual_qty: 1 }]));
p = await ver('com-extra');
certo('produto acrescentado pelo estafeta fica só no talão: a lista continua com 3 produtos',
  p.items.length === 3 && igual(p.items.map((i) => i.purchaseStatus), ['bought', 'bought', 'unavailable']));

// dois produtos iguais, os dois comprados: o talão junta-os numa linha
const DOIS_IGUAIS = [['Água', 0.5, 1, 'purchased'], ['Água', 0.5, 1, 'purchased'], ['Pão', 1.2, 1, 'unavailable']];
await criar('iguais', DOIS_IGUAIS);
await fechar('iguais', talaoDe(DOIS_IGUAIS));
certo('dois produtos iguais com o mesmo destino: o talão guarda uma linha e os dois ficam certos',
  (await um(`select count(*)::int n from public.order_purchase_items_v2 where order_id = 'iguais'`)).n === 2 &&
  igual(await estados('iguais'), ['bought', 'bought', 'unavailable']), JSON.stringify(await estados('iguais')));

// dois produtos iguais com destinos diferentes: cada um com a sua linha
const IGUAIS_MISTOS = [['Leite', 0.9, 1, 'purchased'], ['Leite', 0.9, 1, 'unavailable']];
await criar('mistos', IGUAIS_MISTOS);
await fechar('mistos', talaoDe(IGUAIS_MISTOS));
certo('dois iguais, um comprado e um em falta: um de cada (primeiro o comprado)',
  igual(await estados('mistos'), ['bought', 'unavailable']), JSON.stringify(await estados('mistos')));

// três iguais com destinos diferentes: o talão perdeu uma linha, não se adivinha
const TRES_MISTOS = [['Ovo', 0.3, 1, 'purchased'], ['Ovo', 0.3, 1, 'purchased'], ['Ovo', 0.3, 1, 'unavailable']];
await criar('tres', TRES_MISTOS);
await fechar('tres', talaoDe(TRES_MISTOS));
certo('três iguais com destinos diferentes: o que sobra fica como estava (não se adivinha)',
  igual(await estados('tres'), ['bought', 'unavailable', 'pending']), JSON.stringify(await estados('tres')));

// mesmo nome e preço, quantidades diferentes
const QTD = [['Iogurte', 0.6, 4, 'unavailable'], ['Iogurte', 0.6, 2, 'purchased']];
await criar('qtd', QTD);
await fechar('qtd', talaoDe(QTD));
certo('mesmo nome e preço com quantidades diferentes não se confundem',
  igual(await estados('qtd'), ['unavailable', 'bought']), JSON.stringify(await estados('qtd')));

// produto da lista sem linha no talão
await criar('sem-par', COMPRA.slice(0, 3));
await fechar('sem-par', [{ original_name: 'Compra inteira', original_price_cents: 827, original_qty: 1, status: 'purchased' }]);
certo('talão com nomes diferentes dos do pedido: nada casa, a lista fica como estava',
  igual(await estados('sem-par'), ['pending', 'pending', 'pending']));

// pedido de restaurante parceiro: sem talão, nunca fechado por esta via
await criar('parceiro', COMPRA.slice(0, 2), { service_type: 'restaurant', status: 'pickedUp' });
const parceiroAntes = (await um(`select items::text t from public.orders where id = 'parceiro'`)).t;
await db.query(`update public.orders set status = 'onTheWay' where id = 'parceiro'`);
await db.query(`update public.orders set status = 'delivered' where id = 'parceiro'`);
certo('pedido sem talão (parceiro): a lista não mexe, nem a caminho nem entregue',
  (await um(`select items::text t from public.orders where id = 'parceiro'`)).t === parceiroAntes);

// pedido com talão mas ainda não marcado fechado: o gatilho não entra
await criar('nao-fechado', COMPRA.slice(0, 2), { status: 'pickedUp' });
await db.query(`insert into public.order_purchase_items_v2 (order_id, original_name, original_price_cents, original_qty, status)
                values ('nao-fechado', 'Produto A', 305, 1, 'unavailable')`);
await db.query(`update public.orders set status = 'onTheWay' where id = 'nao-fechado'`);
certo('com linhas do talão mas sem is_purchase_finalized: não mexe',
  igual(await estados('nao-fechado'), ['pending', 'pending']));

// fecho feito com o pedido já a caminho: o UPDATE final do fecho não apanha nenhuma linha
await criar('ja-a-caminho', COMPRA, { status: 'onTheWay' });
n = await fechar('ja-a-caminho', talaoDe(COMPRA));
certo('fecho com o pedido já a caminho: a mudança de estado não aconteceu e a lista ainda está "pending"',
  n === 0 && igual(await estados('ja-a-caminho'), Array(12).fill('pending')));
await db.query(`update public.orders set status = 'delivered' where id = 'ja-a-caminho'`);
certo('a rede: ao entregar, a lista acerta-se', igual(await estados('ja-a-caminho'), esperados),
  JSON.stringify(await estados('ja-a-caminho')));

// repetir não estraga
const umaVez = (await um(`select items::text t from public.orders where id = 'novo'`)).t;
await db.query(`update public.orders set status = 'delivered' where id = 'novo'`);
certo('passar depois a entregue não muda mais nada na lista (repetir é inofensivo)',
  (await um(`select items::text t from public.orders where id = 'novo'`)).t === umaVez);

// mudanças que não são para onTheWay/delivered
await db.query(`update public.orders set status = 'cancelled' where id = 'hoje'`);
certo('outras mudanças de estado (cancelado) não mexem na lista',
  igual(await estados('hoje'), Array(12).fill('pending')));

// lista que não é uma lista
await criar('estranho', [], { items: { nota: 'não é uma lista' } });
await fechar('estranho', talaoDe(COMPRA.slice(0, 1)));
p = await ver('estranho');
certo('items que não é uma lista: o pedido segue e fica como estava',
  p.status === 'onTheWay' && igual(p.items, { nota: 'não é uma lista' }), JSON.stringify(p.items));

console.log('\n5) um erro lá dentro nunca trava o fecho');
await db.exec(`
  alter function public._itens_com_estado_do_talao(text, jsonb) rename to _itens_guardada;
  create function public._itens_com_estado_do_talao(p_order_id text, p_items jsonb) returns jsonb
    language plpgsql as $$ begin raise exception 'rebentou de propósito'; end $$;
`);
await criar('com-erro', COMPRA);
n = await fechar('com-erro', talaoDe(COMPRA));
p = await ver('com-erro');
certo('com a função de apoio a rebentar, o fecho acaba na mesma (onTheWay, fechado)',
  n === 1 && p.status === 'onTheWay' && p.is_purchase_finalized === true);
certo('e a lista fica como estava', igual(p.items.map((i) => i.purchaseStatus), Array(12).fill('pending')));
await db.exec(`
  drop function public._itens_com_estado_do_talao(text, jsonb);
  alter function public._itens_guardada(text, jsonb) rename to _itens_com_estado_do_talao;
`);

console.log('\n6) Passo B: acertar os pedidos antigos, com cópia de segurança');
// "hoje" voltou a cancelado; usa-se um pedido antigo novo, fechado antes da proposta existir
await db.exec(`alter table public.orders disable trigger trg_orders_itens_estado_do_talao`);
await criar('antigo', COMPRA);
await fechar('antigo', talaoDe(COMPRA));
await db.query(`update public.orders set status = 'delivered' where id = 'antigo'`);
await db.exec(`alter table public.orders enable trigger trg_orders_itens_estado_do_talao`);
certo('pedido antigo, entregue antes da proposta: lista toda "pending"',
  igual(await estados('antigo'), Array(12).fill('pending')));
const outrosAntes = (await q(`select id, items::text t from public.orders where id <> 'antigo' order by id`));
const dinheiroAntes = dinheiro(await ver('antigo'));
await db.exec(antigos);
const copia = await q(`select id from public.bkp_orders_items_talao_20261115 order by id`);
certo('a cópia de segurança guardou só pedidos fechados que iam mudar (não o parceiro, o já certo, nem o não fechado)',
  copia.some((c) => c.id === 'antigo') &&
  !copia.some((c) => ['parceiro', 'novo', 'nao-fechado', 'sem-par'].includes(c.id)),
  JSON.stringify(copia.map((c) => c.id)));
certo('o pedido antigo ficou com os estados certos', igual(await estados('antigo'), esperados));
certo('estado, e valores do pedido antigo não mexeram',
  (await ver('antigo')).status === 'delivered' && igual(dinheiro(await ver('antigo')), dinheiroAntes));
const outrosDepois = (await q(`select id, items::text t from public.orders where id <> 'antigo' order by id`));
const mudaram = outrosDepois.filter((o, i) => o.t !== outrosAntes[i].t).map((o) => o.id);
certo('dos outros pedidos só mudaram os que estavam na cópia',
  mudaram.every((id) => copia.some((c) => c.id === id)), JSON.stringify(mudaram));
await db.query(`update public.orders o set items = b.items
                  from public.bkp_orders_items_talao_20261115 b where b.id = o.id and o.id = 'antigo'`);
certo('desfazer pela cópia devolve a lista antiga',
  igual(await estados('antigo'), Array(12).fill('pending')));

console.log(`\nRESULTADO: ${ok} certos, ${falhas} falhados`);
process.exit(falhas ? 1 : 0);
