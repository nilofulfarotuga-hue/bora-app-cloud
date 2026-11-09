-- M10 (09/11/2026), item 2.14 da ordem do Danilo ("create_order sem protecao a toque duplo",
-- erro de 26/10 por fechar). AUTORIZO do Danilo de 08/11 para os blocos da missao.
--
-- O QUE FAZ: o create_order que esta no ar (md5 70a937fd...) fica INTACTO, so muda de nome para
-- public._create_order_core(jsonb). O nome public.create_order(jsonb) passa a ser um embrulho fino:
--   - pedido em DINHEIRO feito pelo proprio cliente (auth.uid() presente): fecha um cadeado por cliente
--     (pg_advisory_xact_lock) e, se o MESMO pedido (mesmo p_input, byte a byte em jsonb) foi criado ha
--     menos de 60 s e nao esta cancelado, devolve a resposta do primeiro (com "repetido": true) em vez
--     de criar outro. Dois toques ao mesmo tempo ficam em fila no cadeado; o segundo ve o primeiro.
--   - tudo o resto (cartao, MB Way, chamadas do servidor com service_role, Edge do Stripe) passa
--     direto ao corpo, sem cadeado nem tabela.
-- Nao muda nenhuma conta: precos, taxas, carteira e tokens sao todos do _create_order_core.
-- _promotions_server_ready lia o texto do create_order a procura de "product_promocao_ativa"; passa a
-- ler o corpo (_create_order_core) quando ele existe, senao as promocoes desligavam-se em silencio.
--
-- ATENCAO para quem mexer no create_order depois disto: o corpo vive em _create_order_core. Um
-- "create or replace function public.create_order" com o corpo inteiro tira a protecao (nao parte nada).
-- Idempotente: correr outra vez nao renomeia de novo nem cria duas tabelas.

create table if not exists public.create_order_recentes (
  user_id    uuid        not null,
  hash       text        not null,
  order_id   text,
  resultado  jsonb       not null,
  criado_em  timestamptz not null default now()
);
create index if not exists create_order_recentes_user_hash_idx
  on public.create_order_recentes (user_id, hash, criado_em desc);
alter table public.create_order_recentes enable row level security;
revoke all on table public.create_order_recentes from public, anon, authenticated;
comment on table public.create_order_recentes is
  'M10 09/11/2026: respostas do create_order em dinheiro dos ultimos minutos, para o toque duplo devolver o mesmo pedido. So o embrulho do create_order escreve aqui; limpa-se sozinha (1 dia).';

do $$
begin
  if to_regprocedure('public._create_order_core(jsonb)') is null then
    alter function public.create_order(jsonb) rename to _create_order_core;
  end if;
end $$;
revoke execute on function public._create_order_core(jsonb) from public, anon, authenticated;
grant execute on function public._create_order_core(jsonb) to service_role;

create or replace function public.create_order(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid  uuid := auth.uid();
  v_hash text;
  v_prev public.create_order_recentes;
  v_res  jsonb;
begin
  -- So o toque duplo em dinheiro do proprio cliente; o resto vai direto ao corpo de sempre.
  if v_uid is null or coalesce(p_input->>'payment_method', '') <> 'cash' then
    return public._create_order_core(p_input);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('create_order:' || v_uid::text, 0));
  v_hash := md5(p_input::text);

  select * into v_prev
    from public.create_order_recentes r
   where r.user_id = v_uid and r.hash = v_hash
     and r.criado_em > now() - interval '60 seconds'
   order by r.criado_em desc
   limit 1;

  if found and exists (select 1 from public.orders o
                        where o.id = v_prev.order_id
                          and coalesce(o.status, '') not in ('cancelled', 'canceled')) then
    return v_prev.resultado || jsonb_build_object('repetido', true);
  end if;

  v_res := public._create_order_core(p_input);

  insert into public.create_order_recentes (user_id, hash, order_id, resultado)
  values (v_uid, v_hash, v_res->>'order_id', v_res);
  delete from public.create_order_recentes where criado_em < now() - interval '1 day';

  return v_res;
end $function$;

revoke all on function public.create_order(jsonb) from public, anon;
grant execute on function public.create_order(jsonb) to authenticated, service_role;
comment on function public.create_order(jsonb) is
  'M10 09/11/2026: embrulho do create_order. Pedido em dinheiro do proprio cliente: cadeado por cliente e o mesmo pedido repetido em menos de 60 s devolve o primeiro ("repetido": true). O corpo (precos, taxas, carteira, tokens) esta em _create_order_core, intacto.';

create or replace function public._promotions_server_ready()
returns boolean
language sql
stable
set search_path to 'public', 'pg_catalog'
as $function$
  -- M10 09/11/2026: o corpo do create_order passou a viver em _create_order_core (embrulho do toque duplo).
  select (select count(*) from pg_proc p
           where p.oid in (to_regprocedure('public.quote_order_pricing(jsonb)'),
                           coalesce(to_regprocedure('public._create_order_core(jsonb)'),
                                    to_regprocedure('public.create_order(jsonb)')))
             and p.prosrc like '%product_promocao_ativa%') = 2;
$function$;