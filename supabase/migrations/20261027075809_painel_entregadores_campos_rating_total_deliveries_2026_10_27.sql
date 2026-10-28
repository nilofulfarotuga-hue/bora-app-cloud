-- 27/10/2026 (Danilo: "nao esta a aparecer no meu painel administrativo"):
-- O ecra "Entregadores" do painel (lista e ficha do estafeta) pede ao banco as
-- colunas rating e total_deliveries, que nao existem em drivers (as reais sao
-- avg_rating e ratings_count). O pedido dava erro 400 e o ecra caia calado na
-- versao curta: sem selfie, sem foto do documento, sem foto do veiculo, sem morada.
-- Provado nos logs: 6 pedidos do telemovel do Danilo as 07:45-07:46 com
-- "column drivers.rating does not exist".
-- Correcao: campos calculados do PostgREST (funcao que recebe a linha de drivers).
-- O mesmo pedido passa a dar 200 em todas as versoes ja instaladas (Android,
-- iPhone e web), sem mexer em colunas, RLS, dinheiro ou despacho.
-- Para desfazer: drop function public.rating(public.drivers);
--                drop function public.total_deliveries(public.drivers);

create or replace function public.rating(d public.drivers)
returns numeric
language sql
stable
set search_path = public
as $$
  select d.avg_rating
$$;

create or replace function public.total_deliveries(d public.drivers)
returns integer
language sql
stable
set search_path = public
as $$
  select count(*)::integer
  from public.orders o
  where o.status = 'delivered'
    and (o.assigned_driver_id in (d.user_id::text, d.id::text)
         or o.driver_id in (d.user_id, d.id))
$$;

comment on function public.rating(public.drivers) is
  'Campo calculado (PostgREST) para o painel admin: devolve drivers.avg_rating. Criado 27/10/2026 porque o ecra Entregadores pede "rating" e a coluna nao existe.';
comment on function public.total_deliveries(public.drivers) is
  'Campo calculado (PostgREST) para o painel admin: pedidos entregues pelo estafeta (assigned_driver_id ou driver_id = drivers.user_id ou drivers.id). Criado 27/10/2026.';

grant execute on function public.rating(public.drivers) to anon, authenticated, service_role;
grant execute on function public.total_deliveries(public.drivers) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
