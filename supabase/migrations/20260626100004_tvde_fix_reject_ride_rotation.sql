CREATE OR REPLACE FUNCTION public.tvde_reject_ride(p_ride_id uuid)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.tvde_rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;

  IF v_ride.current_offer_driver_id = v_uid AND v_ride.status = 'solicitada' THEN
    UPDATE public.tvde_rides
       SET tried_driver_ids = CASE
             WHEN v_uid = ANY(tried_driver_ids) THEN tried_driver_ids
             ELSE array_append(tried_driver_ids, v_uid) END,
           current_offer_driver_id = NULL,
           offer_expires_at = NULL,
           updated_at = now()
     WHERE id = p_ride_id;
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, 'solicitada', 'driver', jsonb_build_object('rejected_by', v_uid));
    PERFORM public.tvde_offer_to_next(p_ride_id);
  ELSE
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, v_ride.status, 'driver', jsonb_build_object('rejected_by', v_uid, 'stale', true));
  END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  RETURN v_ride;
END;
$function$;
