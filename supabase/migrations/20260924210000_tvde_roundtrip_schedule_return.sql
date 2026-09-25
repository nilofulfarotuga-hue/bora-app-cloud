-- Ida agora, volta marcada para uma hora certa (missão tres-frentes-2026-09-24, bloco A).
--
-- A CICATRIZ: a 24/09 uma cliente quis ir às 16h36 e voltar às 21h40. Não deu. O pedido na
-- hora (`_solicitarRoundtrip`) só oferece «chamo quando terminar», e a reserva não deixava
-- escolher as 17h00 porque a antecedência mínima eram 30 minutos. Ficou com a ida marcada
-- para as 21h40 e volta nenhuma — o contrário do que pediu.
--
-- Esta RPC é ADITIVA: não toca em `tvde_schedule_roundtrip` nem em `tvde_request_return_ride`.
-- Pega num vale que já existe (comprado na hora, ou reservado) e marca a perna da volta para
-- uma hora certa, igual à que o pacote marcado cria.
--
-- O ESTADO DO VALE, e porquê. O gatilho `fn_tvde_roundtrip_reserva_ciclo` já sabe tratar de
-- um vale com volta marcada, mas só olha para vales com `return_mode` preenchido, e o ramo
-- da IDA só age quando o vale está `reservado`. Por isso:
--   · ida ainda por fazer  → o vale passa a `reservado`. Deixa de aparecer como «tens uma
--     volta para chamar» (o `tvde_active_roundtrip_credit` só olha para `ativo`), o que
--     impede o cliente de pedir DUAS voltas com o mesmo vale; e se a ida for cancelada, o
--     gatilho anula o vale e cancela esta volta, sem taxa.
--   · ida já terminada     → o vale fica `usado`, com `return_ride_id`, exactamente como faz
--     o pedido da volta na hora. Se a volta cair, o gatilho devolve o vale a `ativo` e o
--     cliente pode chamá-la à mão.
-- Em qualquer dos casos o ciclo fica fechado e não há maneira de gastar o vale duas vezes.
create or replace function public.tvde_roundtrip_schedule_return(
  p_credit_id uuid,
  p_return_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = public as $$
DECLARE
  v_uid     uuid := auth.uid();
  v_credit  public.tvde_roundtrip_credits;
  v_ida     public.tvde_rides;
  v_volta   public.tvde_rides;
  v_hours   int := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 12);
  v_gap     int := COALESCE((public.get_setting('tvde_roundtrip_return_min_gap_minutes') #>> '{}')::int, 30);
  v_base    timestamptz;
  v_extra_km int;
  v_ret_earn int;
  v_ida_feita boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_return_at IS NULL THEN RAISE EXCEPTION 'return_at_required'; END IF;

  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits WHERE id = p_credit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credit_not_found'; END IF;
  IF v_credit.client_id <> v_uid THEN RAISE EXCEPTION 'not_credit_owner'; END IF;
  IF v_credit.status NOT IN ('ativo', 'reservado') THEN
    RAISE EXCEPTION 'credit_not_usable: %', v_credit.status;
  END IF;
  IF now() > v_credit.expires_at THEN
    UPDATE public.tvde_roundtrip_credits SET status = 'expirado' WHERE id = p_credit_id;
    RAISE EXCEPTION 'credit_expired';
  END IF;

  -- Uma volta por vale. Só se deixa marcar de novo se a anterior morreu.
  IF v_credit.return_ride_id IS NOT NULL THEN RAISE EXCEPTION 'return_already_used'; END IF;
  IF v_credit.scheduled_return_ride_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.tvde_rides r
                  WHERE r.id = v_credit.scheduled_return_ride_id
                    AND r.status IN ('agendada','solicitada','motorista_atribuido',
                                     'motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RAISE EXCEPTION 'return_already_scheduled';
  END IF;

  SELECT * INTO v_ida FROM public.tvde_rides WHERE id = v_credit.outbound_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'outbound_ride_not_found'; END IF;
  IF v_ida.status IN ('cancelada_cliente','cancelada_motorista','sem_motorista','no_show') THEN
    RAISE EXCEPTION 'outbound_cancelled';
  END IF;
  v_ida_feita := (v_ida.status = 'finalizada');

  -- Os mesmos limites do pacote marcado: nunca antes de 30 min depois da ida, nunca mais de
  -- 12 h depois dela. E, obviamente, nunca no passado.
  v_base := COALESCE(v_credit.outbound_scheduled_at, v_ida.scheduled_at, v_ida.created_at);
  IF p_return_at < v_base + make_interval(mins => v_gap) THEN RAISE EXCEPTION 'return_too_soon'; END IF;
  IF p_return_at > v_base + make_interval(hours => v_hours) THEN RAISE EXCEPTION 'return_too_far'; END IF;
  IF p_return_at <= now() THEN RAISE EXCEPTION 'return_in_the_past'; END IF;

  v_extra_km := GREATEST(0, CEIL(COALESCE(v_ida.est_distance_km, 0)
                  - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_ret_earn := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int
                + v_extra_km * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;

  -- A volta: caminho de volta da ida, tarifa 0 (já paga no pacote), sem nada a cobrar.
  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    payment_method, status, scheduled_at, reservation_status,
    roundtrip_credit_id, is_return_leg, customer_note)
  VALUES (
    v_uid, v_ida.dest_lat, v_ida.dest_lng, v_ida.dest_label,
    v_ida.origin_lat, v_ida.origin_lng, v_ida.origin_label,
    v_ida.est_distance_km, 0, v_ret_earn, 0,
    'cash', 'agendada', p_return_at, 'a_procurar',
    v_credit.id, true, v_ida.customer_note)
  RETURNING * INTO v_volta;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (v_volta.id, 'agendada', 'client',
    jsonb_build_object('scheduled_at', p_return_at, 'volta_do_pacote', true,
                       'marcada_depois_da_compra', true,
                       'credit_id', v_credit.id, 'ida_ride_id', v_ida.id,
                       'driver_earn_cents', v_ret_earn));

  UPDATE public.tvde_roundtrip_credits
     SET scheduled_return_ride_id = v_volta.id,
         return_mode              = 'marcada',
         return_scheduled_at      = p_return_at,
         expires_at               = GREATEST(expires_at, p_return_at + make_interval(hours => v_hours)),
         status                   = CASE WHEN v_ida_feita THEN 'usado' ELSE 'reservado' END,
         return_ride_id           = CASE WHEN v_ida_feita THEN v_volta.id ELSE return_ride_id END
   WHERE id = v_credit.id
  RETURNING * INTO v_credit;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (v_ida.id, 'volta_marcada', 'client',
    jsonb_build_object('credit_id', v_credit.id, 'volta_ride_id', v_volta.id,
                       'return_at', p_return_at, 'estado_do_vale', v_credit.status));

  -- Procurar motorista para a volta, como no pacote marcado em dinheiro.
  PERFORM public.tvde_reservation_offer_to_next(v_volta.id);

  RETURN jsonb_build_object('volta', to_jsonb(v_volta), 'credit', to_jsonb(v_credit));
END $$;

revoke all on function public.tvde_roundtrip_schedule_return(uuid, timestamptz) from public;
revoke all on function public.tvde_roundtrip_schedule_return(uuid, timestamptz) from anon;
grant execute on function public.tvde_roundtrip_schedule_return(uuid, timestamptz) to authenticated, service_role;
