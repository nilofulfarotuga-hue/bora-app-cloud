-- ═════════════════════════════════════════════════════════════════════════════
-- PROPOSTA C4 — o servidor passa a aplicar products.discount_price  (29/10/2026)
-- NÃO APLICADA. NÃO EXECUTADA (a sessão que a escreveu não tem acesso à base).
-- Mexe em DINHEIRO (o que o cliente paga): só se aplica com o "vai" do Danilo.
-- Ler primeiro: 00_LEIA-ME.md (a regra de dinheiro em português).
--
-- ORDEM:
--   0. aplicar supabase/migrations/20261029200800_c4_promocoes.sql (colunas, histórico,
--      product_promocao_ativa, interruptor promotions_enabled = false). Sem isto nada daqui corre.
--   1. correr a PARTE P (prova). Termina SEMPRE com um erro de propósito que desfaz tudo; o
--      relatório vem no texto do erro. Ler as linhas "FALHOU" (não deve haver nenhuma).
--   2. correr a PARTE A (aplicar). Faz o backup das 2 funções e troca o preço do produto.
--   3. confirmar com select public.promotions_status();  → server_ready = true, enabled = false.
--   4. só então o Danilo liga o interruptor no painel (Promoções).
--
-- O QUE MUDA, e só isto: nas duas funções do checkout — quote_order_pricing (o que o cartão e o
-- ecrã de pagamento usam) e create_order (o que grava o pedido) — a linha que lê
-- `products.price` para cada linha do carrinho passa a ler PRIMEIRO `products.discount_price`
-- quando product_promocao_ativa(produto) = true (interruptor ligado + promoção válida agora,
-- com data de início, não desligada, produto não vendido ao peso). Em qualquer outro caso a
-- expressão antiga corre igual, linha por linha.
--
-- O QUE NÃO MUDA (de propósito): pricing_calculate, pricing_calculate_loja, partner_store_share
-- e small_order_fee_calc não são tocadas. Já recebem o SUBTOTAL; como o subtotal passa a ser
-- o promocional, a comissão da Bora, o markup oculto, a taxa de serviço, a taxa de pedido
-- pequeno e a entrega grátis por valor calculam-se sobre o preço promocional (a regra do Danilo).
-- ═════════════════════════════════════════════════════════════════════════════


-- ═════════════════════════════════════════════════════════════════════════════
-- PARTE P — PROVA (desfeita no fim). Correr numa só chamada, ANTES da parte A.
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function pg_temp.c4_trocar(p_def text, p_nome text)
returns text
language plpgsql
as $t$
declare
  a1 text := '(SELECT p.price FROM products p WHERE p.id = (v_line->>''product_id'') LIMIT 1),';
  b1 text := '(SELECT p.discount_price FROM products p WHERE p.id = (v_line->>''product_id'') AND public.product_promocao_ativa(p.id) LIMIT 1),'
             || chr(10) || '            ' || a1;
  n integer;
begin
  -- já trocada: devolve a definição como está (executá-la outra vez é inofensivo)
  if position('product_promocao_ativa' in p_def) > 0 then
    return p_def;
  end if;
  n := (length(p_def) - length(replace(p_def, a1, ''))) / length(a1);
  if n <> 2 then
    raise exception '%: esperava 2 trechos do preço do produto, encontrei % — NÃO se troca nada; rever a definição viva', p_nome, n;
  end if;
  return replace(p_def, a1, b1);
end
$t$;

do $prova$
declare
  v_uid  uuid;
  v_rep  text := '';
  v_old  text;
  v_mk   numeric;
  r      record;
  v_in   jsonb;
  v_qo   jsonb;
  v_q0   jsonb;
  v_q1   jsonb;
  v_q2   jsonb;
  v_q3   jsonb;
  v_q4   jsonb;
  v_q5   jsonb;
  v_disc numeric;
  v_exp  numeric;
  v_n    integer;
  v_dif  integer;
  v_tipos text;
  i      integer;
begin
  -- Os dois campos têm de ter o mesmo tipo, senão a troca mudaria os arredondamentos de TODOS os pedidos.
  select string_agg(column_name || '=' || data_type, ', ' order by column_name) into v_tipos
    from information_schema.columns
   where table_schema = 'public' and table_name = 'products' and column_name in ('price', 'discount_price');
  v_rep := v_rep || 'Tipos: ' || v_tipos || E'\n';
  if (select count(distinct data_type) from information_schema.columns
       where table_schema = 'public' and table_name = 'products'
         and column_name in ('price', 'discount_price')) <> 1 then
    raise exception 'FALHOU: price e discount_price têm tipos diferentes (%): rever antes de trocar', v_tipos;
  end if;

  -- Simular um utilizador autenticado (o quote exige auth.uid()).
  select id into v_uid from auth.users order by created_at limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);

  -- A função ANTIGA fica guardada com outro nome, só para comparar (desaparece com o rollback).
  v_old := pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure);
  execute replace(v_old, 'FUNCTION public.quote_order_pricing(', 'FUNCTION public.zz_quote_old_prova(');

  -- A troca (a mesma da parte A).
  execute pg_temp.c4_trocar(pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure), 'quote_order_pricing');
  execute pg_temp.c4_trocar(pg_get_functiondef('public.create_order(jsonb)'::regprocedure), 'create_order');

  select coalesce((value #>> '{}')::numeric, 0.15) into v_mk
    from public.platform_settings where key = 'non_partner_markup_pct';
  v_mk := coalesce(v_mk, 0.15);

  -- ── P1. Sem promoção nenhuma: a função nova dá EXATAMENTE o que a antiga dava ─────────────
  -- 6 produtos de lojas parceiras + 6 de não parceiras, com o interruptor desligado e ligado.
  for i in 0..1 loop
    update public.platform_settings
       set value = to_jsonb(i = 1) where key = 'promotions_enabled';
    v_n := 0; v_dif := 0;
    for r in
      (select p.id as pid, p.restaurant_id as rid, p.price::numeric as price, true as parceiro
         from public.products p join public.restaurants rs on rs.id = p.restaurant_id
        where coalesce(rs.is_partner, false) and p.price::numeric between 1 and 40
          and not coalesce(p.sold_by_weight, false) and p.discount_price is null
          and coalesce(nullif(to_jsonb(rs) ->> 'pausa_ate', '')::timestamptz, '-infinity') <= now()
        order by p.id limit 6)
      union all
      (select p.id, p.restaurant_id, p.price::numeric, false
         from public.products p join public.restaurants rs on rs.id = p.restaurant_id
        where not coalesce(rs.is_partner, false) and p.price::numeric between 1 and 40
          and not coalesce(p.sold_by_weight, false) and p.discount_price is null
          and coalesce(nullif(to_jsonb(rs) ->> 'pausa_ate', '')::timestamptz, '-infinity') <= now()
        order by p.id limit 6)
    loop
      v_in := jsonb_build_object(
        'service_type', case when r.parceiro then 'restaurant' else 'storeShopping' end,
        'distance_km', 2, 'restaurant_id', r.rid,
        'product_lines', jsonb_build_array(jsonb_build_object('product_id', r.pid, 'quantity', 2, 'unit_price', r.price)),
        'items', '[]'::jsonb);
      v_qo := public.zz_quote_old_prova(v_in);
      v_q0 := public.quote_order_pricing(v_in);
      v_n := v_n + 1;
      if v_qo is distinct from v_q0 then
        v_dif := v_dif + 1;
        v_rep := v_rep || 'FALHOU P1 ' || r.pid || ': antiga=' || v_qo::text || ' nova=' || v_q0::text || E'\n';
      end if;
    end loop;
    v_rep := v_rep || 'P1 interruptor=' || (i = 1)::text || ': ' || v_n || ' produtos sem promoção, diferentes da função antiga: ' || v_dif || E'\n';
  end loop;

  -- ── P2. Um pedido de teste (2 unidades) com e sem promoção, linha a linha ────────────────
  for r in
    (select p.id as pid, p.restaurant_id as rid, p.price::numeric as price, true as parceiro
       from public.products p join public.restaurants rs on rs.id = p.restaurant_id
      where coalesce(rs.is_partner, false) and p.price::numeric between 2 and 40
        and not coalesce(p.sold_by_weight, false) and p.discount_price is null
        and coalesce(nullif(to_jsonb(rs) ->> 'pausa_ate', '')::timestamptz, '-infinity') <= now()
      order by p.id limit 1)
    union all
    (select p.id, p.restaurant_id, p.price::numeric, false
       from public.products p join public.restaurants rs on rs.id = p.restaurant_id
      where not coalesce(rs.is_partner, false) and p.price::numeric between 2 and 40
        and not coalesce(p.sold_by_weight, false) and p.discount_price is null
        and coalesce(nullif(to_jsonb(rs) ->> 'pausa_ate', '')::timestamptz, '-infinity') <= now()
      order by p.id limit 1)
  loop
    v_disc := round(r.price * 0.8, 2);
    v_in := jsonb_build_object(
      'service_type', case when r.parceiro then 'restaurant' else 'storeShopping' end,
      'distance_km', 2, 'restaurant_id', r.rid,
      'product_lines', jsonb_build_array(jsonb_build_object('product_id', r.pid, 'quantity', 2, 'unit_price', r.price)),
      'items', '[]'::jsonb);

    -- sem promoção (referência)
    update public.platform_settings set value = 'false'::jsonb where key = 'promotions_enabled';
    v_q0 := public.quote_order_pricing(v_in);

    -- promoção válida (−20 %), interruptor DESLIGADO → tem de dar igual à referência
    update public.products
       set discount_price = v_disc, discount_starts_at = now() - interval '1 hour',
           discount_ends_at = now() + interval '1 day', discount_enabled = true
     where id = r.pid;
    v_q1 := public.quote_order_pricing(v_in);

    -- interruptor LIGADO + promoção ativa → subtotal promocional
    update public.platform_settings set value = 'true'::jsonb where key = 'promotions_enabled';
    v_q2 := public.quote_order_pricing(v_in);
    v_exp := case when r.parceiro then v_disc * 2 else round(v_disc * (1 + v_mk), 2) * 2 end;

    -- desligada pelo admin → igual à referência
    update public.products set discount_enabled = false where id = r.pid;
    v_q3 := public.quote_order_pricing(v_in);

    -- expirada (acabou há 1 h) → igual à referência
    update public.products
       set discount_enabled = true, discount_starts_at = now() - interval '2 hours',
           discount_ends_at = now() - interval '1 hour'
     where id = r.pid;
    v_q4 := public.quote_order_pricing(v_in);

    -- agendada (começa daqui a 1 h) → igual à referência
    update public.products
       set discount_starts_at = now() + interval '1 hour', discount_ends_at = now() + interval '2 hours'
     where id = r.pid;
    v_q5 := public.quote_order_pricing(v_in);

    v_rep := v_rep || E'\nP2 ' || case when r.parceiro then 'LOJA PARCEIRA' else 'LOJA NÃO PARCEIRA' end
      || ' produto ' || r.pid || ' preço ' || r.price || ' → promocional ' || v_disc || ' (2 unidades)' || E'\n';
    v_rep := v_rep || '   campo                 sem promoção   com promoção' || E'\n';
    v_rep := v_rep || '   subtotal              ' || (v_q0 ->> 'subtotal') || '   ' || (v_q2 ->> 'subtotal') || E'\n';
    v_rep := v_rep || '   taxa de entrega       ' || (v_q0 ->> 'delivery_fee') || '   ' || (v_q2 ->> 'delivery_fee') || E'\n';
    v_rep := v_rep || '   taxa de serviço       ' || (v_q0 ->> 'service_fee') || '   ' || (v_q2 ->> 'service_fee') || E'\n';
    v_rep := v_rep || '   taxa pedido pequeno   ' || (v_q0 ->> 'small_order_fee') || '   ' || (v_q2 ->> 'small_order_fee') || E'\n';
    v_rep := v_rep || '   comissão da Bora      ' || (v_q0 ->> 'platform_commission') || '   ' || (v_q2 ->> 'platform_commission') || E'\n';
    v_rep := v_rep || '   ganho do estafeta     ' || (v_q0 ->> 'driver_earnings') || '   ' || (v_q2 ->> 'driver_earnings') || E'\n';
    v_rep := v_rep || '   total do cliente      ' || (v_q0 ->> 'customer_total') || '   ' || (v_q2 ->> 'customer_total') || E'\n';
    if r.parceiro then
      v_rep := v_rep || '   a loja recebe         ' || public.partner_store_share((v_q0 ->> 'subtotal')::numeric, r.rid)
        || '   ' || public.partner_store_share((v_q2 ->> 'subtotal')::numeric, r.rid) || E'\n';
    end if;

    -- tolerância de 2 cêntimos: o servidor multiplica em ponto flutuante e arredonda ao cêntimo (2 unidades),
    -- esta conta é em numeric; uma diferença maior que isso é erro a sério.
    if abs((v_q2 ->> 'subtotal')::numeric - v_exp) > 0.02 then
      v_rep := v_rep || 'FALHOU P2 subtotal promocional esperado ' || round(v_exp, 2) || ' obtido ' || (v_q2 ->> 'subtotal') || E'\n';
    end if;
    if v_q1 is distinct from v_q0 then v_rep := v_rep || 'FALHOU P2 interruptor desligado mudou o pedido' || E'\n'; end if;
    if v_q3 is distinct from v_q0 then v_rep := v_rep || 'FALHOU P2 promoção desligada pelo admin mudou o pedido' || E'\n'; end if;
    if v_q4 is distinct from v_q0 then v_rep := v_rep || 'FALHOU P2 promoção expirada mudou o pedido' || E'\n'; end if;
    if v_q5 is distinct from v_q0 then v_rep := v_rep || 'FALHOU P2 promoção agendada mudou o pedido' || E'\n'; end if;
    if (v_q2 ->> 'customer_total')::numeric >= (v_q0 ->> 'customer_total')::numeric then
      v_rep := v_rep || 'FALHOU P2 o total com promoção não ficou abaixo do total sem promoção' || E'\n';
    end if;
  end loop;

  -- ── P3. As duas funções ficaram trocadas e o servidor diz que está pronto ───────────────
  v_rep := v_rep || E'\nP3 quote_order_pricing com a troca: '
    || ((length(pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure))
         - length(replace(pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure), 'product_promocao_ativa', '')))
        / length('product_promocao_ativa')) || ' sítio(s) (esperado 2)' || E'\n';
  v_rep := v_rep || 'P3 create_order com a troca: '
    || ((length(pg_get_functiondef('public.create_order(jsonb)'::regprocedure))
         - length(replace(pg_get_functiondef('public.create_order(jsonb)'::regprocedure), 'product_promocao_ativa', '')))
        / length('product_promocao_ativa')) || ' sítio(s) (esperado 2)' || E'\n';
  v_rep := v_rep || 'P3 promotions_status(): ' || public.promotions_status()::text || E'\n';
  v_rep := v_rep || 'NOTA: o create_order tem a MESMA linha de preço que o quote (a troca é textualmente a mesma); '
    || 'a primeira encomenda real com promoção deve ser conferida por SELECT (orders.subtotal = preço promocional × unidades).' || E'\n';

  -- Desfaz TUDO (a troca, as promoções de teste, o interruptor, o histórico de teste).
  raise exception E'PROVA C4 (desfeita — nada ficou na base):\n%', v_rep;
end
$prova$;


-- ═════════════════════════════════════════════════════════════════════════════
-- PARTE A — APLICAR (só depois da prova limpa e do "vai" do Danilo)
-- Correr numa só chamada. A função pg_temp.c4_trocar tem de ser criada de novo nesta sessão
-- (copiar o bloco "create or replace function pg_temp.c4_trocar" de cima).
-- ═════════════════════════════════════════════════════════════════════════════

-- A.1 Backup das duas funções vivas (tabelas fechadas por RLS, sem políticas)
create table if not exists public.bkp_fn_quote_order_pricing_20261029 (
  guardado_em timestamptz not null default now(),
  definicao   text not null
);
create table if not exists public.bkp_fn_create_order_20261029 (
  guardado_em timestamptz not null default now(),
  definicao   text not null
);
alter table public.bkp_fn_quote_order_pricing_20261029 enable row level security;
alter table public.bkp_fn_create_order_20261029 enable row level security;

insert into public.bkp_fn_quote_order_pricing_20261029 (definicao)
select pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure)
 where not exists (select 1 from public.bkp_fn_quote_order_pricing_20261029);
insert into public.bkp_fn_create_order_20261029 (definicao)
select pg_get_functiondef('public.create_order(jsonb)'::regprocedure)
 where not exists (select 1 from public.bkp_fn_create_order_20261029);

-- A.2 A troca (para tudo se não encontrar exatamente 2 trechos em cada função)
do $a$
begin
  execute pg_temp.c4_trocar(pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure), 'quote_order_pricing');
  execute pg_temp.c4_trocar(pg_get_functiondef('public.create_order(jsonb)'::regprocedure), 'create_order');
end
$a$;

-- A.3 Conferir (esperado: server_ready = true, enabled = false)
select public.promotions_status();


-- ═════════════════════════════════════════════════════════════════════════════
-- COMO REVERTER (sem apagar nada): repõe as duas funções e desliga o interruptor
-- ═════════════════════════════════════════════════════════════════════════════
-- update public.platform_settings set value = 'false'::jsonb where key = 'promotions_enabled';
-- do $r$ begin
--   execute (select definicao from public.bkp_fn_quote_order_pricing_20261029 order by guardado_em limit 1);
--   execute (select definicao from public.bkp_fn_create_order_20261029 order by guardado_em limit 1);
-- end $r$;
