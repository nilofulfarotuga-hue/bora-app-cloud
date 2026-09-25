-- PROPOSTA — NÃO APLICADA. Aguarda "vai" do Danilo.
-- 2026-08-21 · Cancelar reserva no painel depois dos 20 minutos
--
-- O PROBLEMA
-- `admin_tvde_reservation_cancel` só encontra reservas com `status='agendada'`.
-- Aos 20 minutos da hora o sweep activa a reserva e o status passa a
-- 'motorista_atribuido' — a partir daí a RPC devolve 'reservation_not_found' e
-- o botão do painel deixa de servir. O admin não tem de saber essa diferença.
--
-- PORQUE NÃO USEI O CAMINHO ÓBVIO
-- Dava jeito mandar o painel chamar `tvde_cancel_ride(id,'cliente',motivo)`,
-- que aceita qualquer estado. MAS essa função COBRA: o `v_is_admin` serve
-- só para autorizar (linha 18) e para etiquetar o evento (linha 80) — não
-- isenta nada. Na linha 68, um cancelamento com actor='cliente' fora do prazo
-- de cortesia aplica `tvde_cancel_fee_cents` (250). Ou seja: um cancelamento
-- feito pelo ADMIN passaria a cobrar 2,50 EUR ao CLIENTE.
--
-- A CORRECÇÃO
-- Alargar o filtro de estado da RPC de admin — que não calcula taxa nenhuma —
-- para apanhar também a reserva já activada. Nada muda em valores: é a mesma
-- operação sem taxa que já existe hoje para 'agendada', a valer também nos
-- 20 minutos seguintes.
--
-- Com isto o painel NÃO precisa de mudar: passa a funcionar nos dois casos
-- com a mesma chamada.

CREATE OR REPLACE FUNCTION public.admin_tvde_reservation_cancel(
  p_ride_id uuid,
  p_reason  text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ride public.tvde_rides; v_driver uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  -- [2026-08-21] Era só `status = 'agendada'`. Passa a apanhar também a
  -- reserva já activada pelo sweep (aos 20 min ela fica
  -- 'motorista_atribuido' com reservation_status='ativada').
  SELECT * INTO v_ride FROM public.tvde_rides
   WHERE id = p_ride_id
     AND (
          status = 'agendada'
       OR (status = 'motorista_atribuido'
           AND reservation_status IN ('atribuida','ativada'))
     );
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  v_driver := v_ride.reservation_driver_id;

  UPDATE public.tvde_rides
     SET status             = 'cancelada_cliente',
         reservation_status = 'cancelada',
         cancel_reason      = p_reason,
         updated_at         = now()
   WHERE id = p_ride_id;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (p_ride_id, 'cancelada_cliente', 'admin',
          jsonb_build_object('reason', p_reason,
                             'estado_antes', v_ride.status,
                             'sem_taxa', true));

  -- Avisar o motorista, se já havia um escolhido.
  IF v_driver IS NOT NULL THEN
    PERFORM public.tvde_reservation_push(v_driver, p_ride_id, 'reservation_cancelled');
  END IF;

  RETURN true;
END;
$$;
