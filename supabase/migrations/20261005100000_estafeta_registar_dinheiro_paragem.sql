-- Favor: dinheiro recebido na paragem em casa passa por função própria
-- (antes o telemóvel do estafeta fazia UPDATE directo em orders).
-- Mesmo efeito de hoje, com guarda: só o estafeta atribuído, só em favores,
-- só com o pedido a decorrer, valor não negativo. Ordem do Danilo 05/10/2026 ("vai").
-- A escrita directa não se fecha aqui: só depois de a app nova estar em todos os telemóveis.

create or replace function public.estafeta_registar_dinheiro_paragem(p_order_id text, p_cents integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $f$
declare
  v_uid uuid := auth.uid();
  v_n int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_cents is null or p_cents < 0 then
    return jsonb_build_object('ok', false, 'error', 'valor_invalido');
  end if;
  update public.orders o
     set errand_home_stop_cash_cents = p_cents
   where o.id = p_order_id
     and o.service_type = 'errand'
     and o.status in ('driverAccepted', 'pickedUp', 'onTheWay')
     and o.assigned_driver_id in (
           v_uid::text,
           (select d.id::text from public.drivers d where d.user_id = v_uid));
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', v_n > 0);
end
$f$;

revoke all on function public.estafeta_registar_dinheiro_paragem(text, integer) from public;
revoke all on function public.estafeta_registar_dinheiro_paragem(text, integer) from anon;
grant execute on function public.estafeta_registar_dinheiro_paragem(text, integer) to authenticated;
