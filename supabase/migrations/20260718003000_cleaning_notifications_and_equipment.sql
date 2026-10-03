-- MEGA-FIX 2026-07-18 Parte 7 — limpeza: fim das falhas silenciosas + canal certo + utensílios.
-- Ver .claude/.ai/knowledge/wiki/licoes/licao-exception-when-others-null.md
--                .../licao-notify-canal-errado.md

-- 1) Tabela de falhas de notificação — o invisível passa a observável.
CREATE TABLE IF NOT EXISTS public.notification_failures (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    uuid,
  kind       text,
  source     text,
  erro       text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notification_failures_created_at
  ON public.notification_failures (created_at DESC);

-- 2) _cleaning_notify_user — nunca mais engole exceções; usa notify-cleaner (canal certo).
CREATE OR REPLACE FUNCTION public._cleaning_notify_user(
  p_user_id uuid, p_kind text, p_title text, p_body text, p_booking_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url  text;
  v_key  text;
  v_type text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  -- Oferta nova → canal urgente insistente; restantes estados → canal normal.
  v_type := CASE
    WHEN p_kind ILIKE '%offer%' OR p_kind ILIKE '%oferta%' THEN 'cleaning_offer'
    ELSE 'cleaning_status'
  END;

  -- (1) In-app (badge/inbox). Falha → grava, não engole.
  BEGIN
    PERFORM public._push_in_app_notification(p_user_id, p_kind, p_title, p_body, p_booking_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_kind, '_cleaning_notify_user:in_app', SQLERRM);
    RAISE WARNING '_cleaning_notify_user in-app falhou (user=%): %', p_user_id, SQLERRM;
  END;

  -- (2) FCM via notify-cleaner (canal urgente para oferta). Falha → grava, não engole.
  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
    IF v_url IS NULL OR v_key IS NULL THEN
      INSERT INTO public.notification_failures (user_id, kind, source, erro)
      VALUES (p_user_id, p_kind, '_cleaning_notify_user:fcm', 'vault project_url/service_role_key em falta');
      RAISE WARNING '_cleaning_notify_user FCM: vault secrets em falta (user=%)', p_user_id;
    ELSE
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-cleaner',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object(
          'cleanerUserId', p_user_id::text,
          'bookingId', COALESCE(p_booking_id,''),
          'title', p_title, 'body', p_body,
          'kind', p_kind, 'type', v_type)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, p_kind, '_cleaning_notify_user:fcm', SQLERRM);
    RAISE WARNING '_cleaning_notify_user FCM falhou (user=%): %', p_user_id, SQLERRM;
  END;
END $function$;

-- 3) Utensílios da profissional — lista fixa PT-PT, multi-select no cadastro.
ALTER TABLE public.cleaners ADD COLUMN IF NOT EXISTS equipment jsonb NOT NULL DEFAULT '[]'::jsonb;

-- 3b) cleaner_apply passa a espelhar os materiais confirmados (docs.materials_list)
--     para a coluna `equipment` — o multi-select do cadastro já existe (checklist de
--     materiais obrigatórios); assim o cliente pode ver o que a profissional leva.
CREATE OR REPLACE FUNCTION public.cleaner_apply(p_name text, p_phone text, p_email text, p_nif text, p_bio text DEFAULT ''::text, p_photo_url text DEFAULT ''::text, p_base_address text DEFAULT ''::text, p_base_lat double precision DEFAULT NULL::double precision, p_base_lng double precision DEFAULT NULL::double precision, p_service_radius_km numeric DEFAULT 10, p_docs jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_existing cleaners; v_id uuid; v_equipment jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF length(trim(COALESCE(p_name,''))) < 3 THEN RAISE EXCEPTION 'name_required'; END IF;
  IF length(trim(COALESCE(p_phone,''))) < 9 THEN RAISE EXCEPTION 'phone_required'; END IF;

  -- Utensílios = a lista de materiais confirmada no cadastro (ou [] se ausente).
  v_equipment := COALESCE(p_docs->'materials_list', '[]'::jsonb);

  SELECT * INTO v_existing FROM cleaners WHERE user_id = v_uid;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.approval_status IN ('pending','approved') THEN
      RAISE EXCEPTION 'application_already_exists';
    END IF;
    UPDATE cleaners
    SET name = p_name, phone = p_phone, email = COALESCE(p_email,''), nif = COALESCE(p_nif,''),
        bio = COALESCE(p_bio,''), photo_url = COALESCE(p_photo_url,''),
        base_address = COALESCE(p_base_address,''), base_lat = p_base_lat, base_lng = p_base_lng,
        service_radius_km = COALESCE(p_service_radius_km, 10), docs = COALESCE(p_docs,'{}'::jsonb),
        equipment = v_equipment,
        approval_status = 'pending', rejection_reason = NULL
    WHERE id = v_existing.id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO cleaners (user_id, name, phone, email, nif, bio, photo_url,
                          base_address, base_lat, base_lng, service_radius_km, docs, equipment)
    VALUES (v_uid, p_name, p_phone, COALESCE(p_email,''), COALESCE(p_nif,''),
            COALESCE(p_bio,''), COALESCE(p_photo_url,''), COALESCE(p_base_address,''),
            p_base_lat, p_base_lng, COALESCE(p_service_radius_km, 10), COALESCE(p_docs,'{}'::jsonb), v_equipment)
    RETURNING id INTO v_id;
  END IF;

  PERFORM public._cleaning_notify_admin('Nova candidatura de profissional de limpeza',
    p_name || ' candidatou-se. Rever documentos no painel.');

  RETURN (SELECT to_jsonb(c) FROM cleaners c WHERE c.id = v_id);
END $function$;
