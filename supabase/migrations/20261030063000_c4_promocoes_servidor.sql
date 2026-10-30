-- C4 promocoes: o servidor aplica o preco promocional no quote_order_pricing e no create_order (30/10/2026).
-- Autorizacao do Danilo: 29/10 18:02 "eu autorizo tudo, publicar ja hoje" e 30/10 05:22 "tudo o que falamos nesta conversa tem de estar pronto e a funcionar" (adendo 11).
-- Prova em rollback: PARTE P de docs/propostas/missao-geral-2026-10-28/C4_promocoes/01_servidor_precos_proposta.sql (FALHOU=0) e pedido da Boom com promocao de teste (mostrado = gravado).
-- So a linha do preco do produto muda (COALESCE com round(discount_price::numeric,2) quando product_promocao_ativa); comissoes, taxas e entrega intocadas.

create or replace function pg_temp.c4_trocar(p_def text, p_nome text)
returns text
language plpgsql
as $t$
declare
  a1 text := '(SELECT p.price FROM products p WHERE p.id = (v_line->>''product_id'') LIMIT 1),';
  -- 30/10/2026: discount_price é double precision e price é numeric na base; converte-se para numeric com
  -- 2 casas para o COALESCE continuar numeric (sem vírgula flutuante nas contas do dinheiro).
  b1 text := '(SELECT round(p.discount_price::numeric, 2) FROM products p WHERE p.id = (v_line->>''product_id'') AND public.product_promocao_ativa(p.id) LIMIT 1),'
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

-- Interruptor (nenhuma promocao ativa a 30/10 05:45: as 14 antigas nao tem datas).
UPDATE public.platform_settings SET value = 'true'::jsonb, updated_at = now() WHERE key = 'promotions_enabled';
