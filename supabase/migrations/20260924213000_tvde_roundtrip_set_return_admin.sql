-- O Danilo também marca (ou muda) a hora da volta pelo painel.
-- Missão tres-frentes-2026-09-24, bloco A5.
--
-- O miolo sai de `tvde_roundtrip_schedule_return` (migração 20260924210000) para
-- `tvde_roundtrip_schedule_return_core`, que recebe QUEM está a agir. A porta do cliente
-- continua a exigir que o vale seja dele; a do admin exige `is_admin()`. As regras — limites
-- de 30 min a 12 h, ganho do motorista, estado do vale — ficam escritas uma vez só.
--
-- Diferença de poder, de propósito: o cliente não pode marcar uma segunda volta; o admin
-- pode MUDAR uma volta já marcada, e nesse caso a anterior é cancelada sem taxa antes de
-- nascer a nova. Uma volta que já esteja a andar (motorista a caminho) não se mexe.
create or replace function public.tvde_roundtrip_schedule_return_core(
  p_credit_id uuid,
  p_return_at timestamptz,
  p_por_admin boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
DECLARE
  v_credit  public.tvde_roundtrip_credits;
  v_ida     public.tvde_rides;
  v_volta   public.tvde_rides;
  v_antiga  public.tvde_rides;
  v_hours   int := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 12);
  v_gap     int := COALESCE((public.get_setting('tvde_roundtrip_return_min_gap_minutes') #>> '{}')::int, 30);
  v_base    timestamptz;
  v_extra_km int;
  v_ret_earn int;
  v_ida_feita boolean;
BEGIN
  IF p_return_at IS NULL THEN RAISE EXCEPTION 'return_at_required'; END IF;

  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits WHERE id = p_credit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'credit_not_found'; END IF;
  IF v_credit.status NOT IN ('ativo', 'reservado') THEN
    RAISE EXCEPTION 'credit_not_usable: %', v_credit.status;
  END IF;
  IF now() > v_credit.expires_at THEN
    UPDATE public.tvde_roundtrip_credits SET status = 'expirado' WHERE id = p_credit_id;
    RAISE EXCEPTION 'credit_expired';
  END IF;
  IF v_credit.return_ride_id IS NOT NULL THEN RAISE EXCEPTION 'return_already_used'; END IF;

  IF v_credit.scheduled_return_ride_id IS NOT NULL THEN
    SELECT * INTO v_antiga FROM public.tvde_rides WHERE id = v_credit.scheduled_return_ride_id;
    IF FOUND AND v_antiga.status IN ('agendada','solicitada','motorista_atribuido',
                                     'motorista_a_caminho','motorista_chegou','em_andamento') THEN
      IF NOT p_por_admin THEN RAISE EXCEPTION 'return_already_scheduled'; END IF;
      IF v_antiga.status <> 'agendada' THEN RAISE EXCEPTION 'return_already_running: %', v_antiga.status; END IF;
      UPDATE public.tvde_rides
         SET status = 'cancelada_cliente', reservation_status = 'cancelada',
             cancel_reason = 'volta_remarcada_pelo_admin', cancel_fee_cents = 0,
             reservation_offer_driver_id = NULL, reservation_offer_expires_at = NULL,
             current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
       WHERE id = v_antiga.id;
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_antiga.id, 'cancelada_cliente', 'admin',
              jsonb_build_object('motivo', 'volta remarcada', 'nova_hora', p_return_at));
      UPDATE public.tvde_roundtrip_credits
         SET scheduled_return_ride_id = NULL, return_scheduled_at = NULL
       WHERE id = v_credit.id
      RETURNING * INTO v_credit;
    END IF;
  END IF;

  SELECT * INTO v_ida FROM public.tvde_rides WHERE id = v_credit.outbound_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'outbound_ride_not_found'; END IF;
  IF v_ida.status IN ('cancelada_cliente','cancelada_motorista','sem_motorista','no_show') THEN
    RAISE EXCEPTION 'outbound_cancelled';
  END IF;
  v_ida_feita := (v_ida.status = 'finalizada');

  v_base := COALESCE(v_credit.outbound_scheduled_at, v_ida.scheduled_at, v_ida.created_at);
  IF p_return_at < v_base + make_interval(mins => v_gap) THEN RAISE EXCEPTION 'return_too_soon'; END IF;
  IF p_return_at > v_base + make_interval(hours => v_hours) THEN RAISE EXCEPTION 'return_too_far'; END IF;
  IF p_return_at <= now() THEN RAISE EXCEPTION 'return_in_the_past'; END IF;

  v_extra_km := GREATEST(0, CEIL(COALESCE(v_ida.est_distance_km, 0)
                  - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_ret_earn := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int
                + v_extra_km * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    payment_method, status, scheduled_at, reservation_status,
    roundtrip_credit_id, is_return_leg, customer_note)
  VALUES (
    v_credit.client_id, v_ida.dest_lat, v_ida.dest_lng, v_ida.dest_label,
    v_ida.origin_lat, v_ida.origin_lng, v_ida.origin_label,
    v_ida.est_distance_km, 0, v_ret_earn, 0,
    'cash', 'agendada', p_return_at, 'a_procurar',
    v_credit.id, true, v_ida.customer_note)
  RETURNING * INTO v_volta;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (v_volta.id, 'agendada', CASE WHEN p_por_admin THEN 'admin' ELSE 'client' END,
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
  VALUES (v_ida.id, 'volta_marcada', CASE WHEN p_por_admin THEN 'admin' ELSE 'client' END,
    jsonb_build_object('credit_id', v_credit.id, 'volta_ride_id', v_volta.id,
                       'return_at', p_return_at, 'estado_do_vale', v_credit.status));

  PERFORM public.tvde_reservation_offer_to_next(v_volta.id);

  RETURN jsonb_build_object('volta', to_jsonb(v_volta), 'credit', to_jsonb(v_credit));
END $$;
revoke all on function public.tvde_roundtrip_schedule_return_core(uuid, timestamptz, boolean) from public;
revoke all on function public.tvde_roundtrip_schedule_return_core(uuid, timestamptz, boolean) from anon;
revoke all on function public.tvde_roundtrip_schedule_return_core(uuid, timestamptz, boolean) from authenticated;

-- Porta do CLIENTE: o vale tem de ser dele.
create or replace function public.tvde_roundtrip_schedule_return(
  p_credit_id uuid,
  p_return_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = public as $$
DECLARE v_uid uuid := auth.uid(); v_dono uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT client_id INTO v_dono FROM public.tvde_roundtrip_credits WHERE id = p_credit_id;
  IF v_dono IS NULL THEN RAISE EXCEPTION 'credit_not_found'; END IF;
  IF v_dono <> v_uid THEN RAISE EXCEPTION 'not_credit_owner'; END IF;
  RETURN public.tvde_roundtrip_schedule_return_core(p_credit_id, p_return_at, false);
END $$;
revoke all on function public.tvde_roundtrip_schedule_return(uuid, timestamptz) from public;
revoke all on function public.tvde_roundtrip_schedule_return(uuid, timestamptz) from anon;
grant execute on function public.tvde_roundtrip_schedule_return(uuid, timestamptz) to authenticated, service_role;

-- Porta do ADMIN: só quem é admin, e pode remarcar.
create or replace function public.admin_tvde_roundtrip_set_return(
  p_credit_id uuid,
  p_return_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = public as $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  RETURN public.tvde_roundtrip_schedule_return_core(p_credit_id, p_return_at, true);
END $$;
revoke all on function public.admin_tvde_roundtrip_set_return(uuid, timestamptz) from public;
revoke all on function public.admin_tvde_roundtrip_set_return(uuid, timestamptz) from anon;
grant execute on function public.admin_tvde_roundtrip_set_return(uuid, timestamptz) to authenticated, service_role;
