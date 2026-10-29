-- ADENDO 4 — parte D: mapa simples de procura para estafetas.
--
-- Conta, por hora do dia (hora de Lisboa) e por celula de cerca de 500 m, os
-- pedidos de loja dos ultimos dias. So leitura. Usa o ponto de RECOLHA do
-- pedido (a loja), nunca a morada do cliente, e deixa de fora favores e
-- encomendas (a recolha dessas pode ser uma casa).
--
-- Quem pode chamar: estafeta aprovado e nao banido, ou admin. Fechada a anon.

create or replace function public.estafeta_mapa_procura(p_dias integer default 30)
returns table (hora smallint, lat_celula double precision, lng_celula double precision, pedidos integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_dias integer := greatest(1, least(coalesce(p_dias, 30), 60));
  -- 0,0045 graus de latitude sao cerca de 500 m; a longitude encolhe com o
  -- coseno da latitude (cerca de 40,5 graus na Guarda).
  v_lat_passo constant double precision := 0.0045;
  v_lng_passo constant double precision := 0.0059;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not (
    public.is_admin()
    or exists (select 1 from public.drivers d
                where d.user_id = v_uid
                  and d.approval_status = 'approved'
                  and coalesce(d.is_banned, false) = false)
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select (extract(hour from (o.created_at at time zone 'Europe/Lisbon')))::smallint as hora,
         (floor(coalesce(o.pickup_lat::double precision, r.lat) / v_lat_passo) * v_lat_passo + v_lat_passo / 2) as lat_celula,
         (floor(coalesce(o.pickup_lng::double precision, r.lng) / v_lng_passo) * v_lng_passo + v_lng_passo / 2) as lng_celula,
         count(*)::integer as pedidos
    from public.orders o
    left join public.restaurants r on r.id = o.restaurant_id
   where o.restaurant_id is not null
     and o.created_at >= now() - make_interval(days => v_dias)
     and o.status not in ('cancelled', 'rejected')
     and coalesce(o.pickup_lat::double precision, r.lat) is not null
     and coalesce(o.pickup_lng::double precision, r.lng) is not null
   group by 1, 2, 3
   order by 1, 4 desc;
end;
$$;
revoke all on function public.estafeta_mapa_procura(integer) from public, anon;
grant execute on function public.estafeta_mapa_procura(integer) to authenticated;
