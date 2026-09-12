-- BUG 4 fix — client_join_waitlist must reject empty profile fields.
--
-- Until now the function used COALESCE(name,'') / COALESCE(phone,'') which
-- always violated the table CHECK constraints
--   length(client_name)  >= 1
--   length(client_phone) >= 1
-- when the user had NULL/empty name or phone, surfacing as the generic
-- "Ocorreu um erro. Tenta de novo." in the app (PostgrestException 23514
-- not mapped in _mapErrorPtPt).
--
-- Fix: RAISE EXCEPTION with codes the Flutter mapper translates to
-- actionable messages telling the user to complete their profile.

CREATE OR REPLACE FUNCTION public.client_join_waitlist(
  p_restaurant_id   text,
  p_party           integer,
  p_target_date     date,
  p_target_time_start time without time zone DEFAULT NULL,
  p_target_time_end   time without time zone DEFAULT NULL,
  p_notes           text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid         uuid := auth.uid();
  v_user_record record;
  v_position    integer;
  v_existing    uuid;
  v_blocked     boolean;
  v_id          uuid;
  v_name        text;
  v_phone       text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_party < 1 OR p_party > 50 THEN RAISE EXCEPTION 'invalid_party_size'; END IF;
  IF p_target_date < CURRENT_DATE THEN RAISE EXCEPTION 'date_in_past'; END IF;

  -- Validar cliente nao blocked
  SELECT is_blocked INTO v_blocked
  FROM client_restaurant_profiles
  WHERE client_user_id = v_uid AND restaurant_id = p_restaurant_id;
  IF COALESCE(v_blocked, false) THEN RAISE EXCEPTION 'client_blocked_at_restaurant'; END IF;

  -- Buscar dados do cliente
  SELECT name, phone INTO v_user_record FROM users WHERE id = v_uid;
  IF v_user_record IS NULL THEN RAISE EXCEPTION 'user_not_found'; END IF;

  -- Validar perfil completo (BUG 4) — CHECK constraints exigem length >= 1
  v_name  := NULLIF(TRIM(v_user_record.name),  '');
  v_phone := NULLIF(TRIM(v_user_record.phone), '');
  IF v_name  IS NULL THEN RAISE EXCEPTION 'profile_incomplete_name';  END IF;
  IF v_phone IS NULL THEN RAISE EXCEPTION 'profile_incomplete_phone'; END IF;

  -- Verificar duplicado activo
  SELECT id INTO v_existing
  FROM reservation_waitlist
  WHERE client_user_id = v_uid
    AND restaurant_id  = p_restaurant_id
    AND target_date    = p_target_date
    AND status         = 'waiting';
  IF v_existing IS NOT NULL THEN RAISE EXCEPTION 'waitlist_already_active'; END IF;

  -- Position = max + 1 do dia
  SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
  FROM reservation_waitlist
  WHERE restaurant_id = p_restaurant_id
    AND target_date   = p_target_date
    AND status        = 'waiting';

  -- INSERT
  INSERT INTO reservation_waitlist (
    restaurant_id, client_user_id, client_name, client_phone,
    people, target_date, target_time_start, target_time_end,
    status, position, notes
  ) VALUES (
    p_restaurant_id, v_uid, v_name, v_phone,
    p_party, p_target_date, p_target_time_start, p_target_time_end,
    'waiting', v_position, p_notes
  ) RETURNING id INTO v_id;

  -- Trigger trg_waitlist_notify_partner_new ja envia push automatico

  RETURN jsonb_build_object(
    'success',     true,
    'waitlist_id', v_id,
    'position',    v_position
  );
END;
$function$;
