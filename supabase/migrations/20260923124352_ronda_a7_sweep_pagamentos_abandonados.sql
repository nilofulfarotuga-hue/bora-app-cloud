-- =============================================================================
-- ronda-fecho-2026-09-22 · A7 — o cron tvde_sweep_abandoned_payments apanha
-- também as corridas que nunca chegaram a ter PaymentIntent (payment_status NULL
-- ou 'pendente') e as reservas online paradas em aguarda_pagamento.
-- Antes (versão 20260922153827): só status='solicitada' com payment_status em
-- requires_payment_method/requires_action/requires_confirmation e sem tentativas.
-- Agora:
--   1) corrida imediata online (card/mbway), 'solicitada', sem motorista nem
--      oferta a decorrer, com pagamento por concluir (NULL, pendente,
--      requires_payment_method, requires_action, requires_confirmation) e mais
--      de 20 minutos -> tvde_cancel_ride(..., 'payment_abandoned').
--      'processing' continua de fora (MB Way a meio); 'not_charged' também.
--   2) reserva online 'agendada' + reservation_status='aguarda_pagamento' há mais
--      de tvde_reservation_payment_timeout_minutes (rede de segurança do
--      tvde_reservations_sweep, mesma escrita que ele faz) -> cancelada_cliente /
--      payment_timeout.
-- O cron 62 (*/10 * * * *) fica igual.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.tvde_sweep_abandoned_payments()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_n integer := 0;
  v_ptmo int := COALESCE((public.get_setting('tvde_reservation_payment_timeout_minutes') #>> '{}')::int, 15);
begin
  -- 1) corridas imediatas online sem pagamento concluído (inclui requires_action e sem PI)
  for v_id in
    select r.id from public.tvde_rides r
    where r.status = 'solicitada'
      and r.scheduled_at is null
      and r.payment_method in ('card','mbway')
      and coalesce(r.payment_status,'') in ('', 'pendente',
            'requires_payment_method','requires_action','requires_confirmation')
      and r.driver_id is null
      and r.current_offer_driver_id is null
      and r.created_at < now() - interval '20 minutes'
    order by r.created_at
    limit 50
  loop
    begin
      perform public.tvde_cancel_ride(v_id, 'cliente', 'payment_abandoned');
      v_n := v_n + 1;
    exception when others then
      raise notice 'sweep abandoned: falhou em % (%)', v_id, sqlerrm;
    end;
  end loop;

  -- 2) reservas online que ficaram em aguarda_pagamento além do prazo
  for v_id in
    select r.id from public.tvde_rides r
    where r.status = 'agendada'
      and r.reservation_status = 'aguarda_pagamento'
      and r.created_at < now() - make_interval(mins => v_ptmo)
    order by r.created_at
    limit 50
  loop
    begin
      update public.tvde_rides
         set status = 'cancelada_cliente', reservation_status = 'cancelada',
             cancel_reason = 'payment_timeout', updated_at = now()
       where id = v_id and status = 'agendada' and reservation_status = 'aguarda_pagamento';
      if found then
        insert into public.tvde_ride_events (ride_id, status, actor, meta)
        values (v_id, 'cancelada_cliente', 'system',
                jsonb_build_object('motivo', 'pagamento nao concluido',
                                   'origem', 'tvde_sweep_abandoned_payments'));
        v_n := v_n + 1;
      end if;
    exception when others then
      raise notice 'sweep abandoned (reserva): falhou em % (%)', v_id, sqlerrm;
    end;
  end loop;

  return v_n;
end;
$function$;

REVOKE ALL ON FUNCTION public.tvde_sweep_abandoned_payments() FROM PUBLIC, anon, authenticated;
