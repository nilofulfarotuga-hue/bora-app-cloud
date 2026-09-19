-- ============================================================================
-- LIMPEZA — RPC de perfil público da profissional de uma reserva.
-- A RLS de cleaners só expõe a própria linha; o tracking do cliente precisa
-- de nome/foto/rating da profissional atribuída. Guardada por posse da
-- reserva (cliente OU a própria profissional). Sem NIF/phone/email.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cleaning_booking_cleaner_public(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings; v_c cleaners;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF v_b.client_user_id <> auth.uid()
     AND NOT EXISTS (SELECT 1 FROM cleaners
                     WHERE (id = v_b.cleaner_id OR id = v_b.offer_cleaner_id)
                       AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'booking_not_yours' USING ERRCODE = '42501';
  END IF;
  IF v_b.cleaner_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_c FROM cleaners WHERE id = v_b.cleaner_id;
  RETURN jsonb_build_object(
    'name', v_c.name,
    'photo_url', v_c.photo_url,
    'bio', v_c.bio,
    'rating_avg', v_c.rating_avg,
    'ratings_count', v_c.ratings_count,
    'cleanings_done', v_c.cleanings_done
  );
END $$;
REVOKE ALL ON FUNCTION public.cleaning_booking_cleaner_public(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_booking_cleaner_public(uuid) TO authenticated;
