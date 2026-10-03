-- ============================================================================
-- LIMPEZA — paridade FASE 2 (auditoria 2026-07-05):
--   1) chat cliente ↔ profissional (padrão TVDE E1: tabela dedicada + read +
--      mark_read RPC + push via _cleaning_notify_user)
--   2) telefone da profissional no perfil público (pós-aceitação) — botão LIGAR
--   3) card público do CLIENTE para a profissional (padrão tvde_ride_passenger_card)
--   4) admin lê conversas (read-only + audit log)
--   5) bucket privado cleaner-documents (KYC) — padrão restaurant-documents
-- Nada aqui toca zonas financeiras.
-- ============================================================================

-- ---------- 1. cleaning_messages ----------
CREATE TABLE IF NOT EXISTS public.cleaning_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  UUID NOT NULL REFERENCES public.cleaning_bookings(id) ON DELETE CASCADE,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client','cleaner')),
  message     TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 2000),
  read        BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cleaning_messages_booking
  ON public.cleaning_messages (booking_id, created_at);

ALTER TABLE public.cleaning_messages ENABLE ROW LEVEL SECURITY;

-- Participantes: cliente da reserva OU a profissional atribuída.
-- Chat disponível de "confirmada" (accepted) até o cliente confirmar
-- (estados accepted/on_the_way/in_progress/done) — decisão da missão.
DO $$
BEGIN
  BEGIN
    CREATE POLICY cleaning_messages_select_participant ON public.cleaning_messages
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.cleaning_bookings b
          WHERE b.id = booking_id
            AND (b.client_user_id = auth.uid()
                 OR b.cleaner_id IN (SELECT id FROM public.cleaners WHERE user_id = auth.uid()))
        )
      );
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    CREATE POLICY cleaning_messages_insert_participant ON public.cleaning_messages
      FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.cleaning_bookings b
          WHERE b.id = booking_id
            AND b.status IN ('accepted','on_the_way','in_progress','done')
            AND (
              (sender_role = 'client'  AND b.client_user_id = auth.uid())
              OR
              (sender_role = 'cleaner' AND b.cleaner_id IN
                 (SELECT id FROM public.cleaners WHERE user_id = auth.uid()))
            )
        )
      );
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
-- (sem UPDATE/DELETE diretos — read via RPC, padrão tvde_messages)

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cleaning_messages;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- ---------- 1b. marcar lidas (padrão tvde_mark_messages_read) ----------
CREATE OR REPLACE FUNCTION public.cleaning_mark_messages_read(
  p_booking_id uuid, p_my_role text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings;
BEGIN
  IF p_my_role NOT IN ('client','cleaner') THEN RAISE EXCEPTION 'invalid_role'; END IF;
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF p_my_role = 'client' AND v_b.client_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'booking_not_yours' USING ERRCODE = '42501';
  END IF;
  IF p_my_role = 'cleaner' AND NOT EXISTS
     (SELECT 1 FROM cleaners WHERE id = v_b.cleaner_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'booking_not_yours' USING ERRCODE = '42501';
  END IF;
  UPDATE cleaning_messages
  SET read = true
  WHERE booking_id = p_booking_id AND read = false AND sender_role <> p_my_role;
END $$;
REVOKE ALL ON FUNCTION public.cleaning_mark_messages_read(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_mark_messages_read(uuid, text) TO authenticated;

-- ---------- 1c. push de mensagem nova (fire-and-forget) ----------
CREATE OR REPLACE FUNCTION public._cleaning_chat_push()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings; v_to uuid;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = NEW.booking_id;
  IF v_b.id IS NULL OR v_b.cleaner_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_role = 'client' THEN
    SELECT user_id INTO v_to FROM cleaners WHERE id = v_b.cleaner_id;
  ELSE
    v_to := v_b.client_user_id;
  END IF;
  PERFORM public._cleaning_notify_user(
    v_to, 'cleaning_chat', 'Nova mensagem 💬',
    left(NEW.message, 96), NEW.booking_id::text);
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER trg_cleaning_chat_push
  AFTER INSERT ON public.cleaning_messages
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_chat_push();

-- ---------- 2. perfil público da profissional v2 (+ phone pós-aceitação) ----------
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
    'cleanings_done', v_c.cleanings_done,
    -- telefone só com serviço em curso (privacidade: nem antes nem depois)
    'phone', CASE WHEN v_b.status IN ('accepted','on_the_way','in_progress','done')
                  THEN v_c.phone ELSE NULL END
  );
END $$;
REVOKE ALL ON FUNCTION public.cleaning_booking_cleaner_public(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_booking_cleaner_public(uuid) TO authenticated;

-- ---------- 3. card público do CLIENTE p/ a profissional atribuída ----------
-- Espelha tvde_ride_passenger_card (identidade SÓ depois de aceitar).
CREATE OR REPLACE FUNCTION public.cleaning_booking_client_public(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'auth' AS $$
DECLARE v_b cleaning_bookings;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL THEN RAISE EXCEPTION 'booking_not_found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM cleaners
                 WHERE id = v_b.cleaner_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'not_booking_cleaner' USING ERRCODE = '42501';
  END IF;
  IF v_b.status NOT IN ('accepted','on_the_way','in_progress','done') THEN
    RAISE EXCEPTION 'booking_not_active';
  END IF;
  RETURN (
    SELECT jsonb_build_object(
      'name', COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data ->> 'bora_name'),
      'photo_url', u.photo_url,
      'phone', u.phone
    )
    FROM public.users u
    LEFT JOIN auth.users au ON au.id = u.id
    WHERE u.id = v_b.client_user_id
  );
END $$;
REVOKE ALL ON FUNCTION public.cleaning_booking_client_public(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_booking_client_public(uuid) TO authenticated;

-- ---------- 4. admin lê conversas (read-only + audit) ----------
CREATE OR REPLACE FUNCTION public.admin_list_cleaning_messages(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  PERFORM public.log_admin_action('cleaning_chat_viewed', 'cleaning_booking',
    p_booking_id::text, '{}'::jsonb);
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(m) ORDER BY m.created_at)
    FROM cleaning_messages m
    WHERE m.booking_id = p_booking_id
  ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_list_cleaning_messages(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_cleaning_messages(uuid) TO authenticated;

-- ---------- 5. bucket privado cleaner-documents (KYC) ----------
INSERT INTO storage.buckets (id, name, public)
VALUES ('cleaner-documents', 'cleaner-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "cleaners_upload_own_docs" ON storage.objects;
CREATE POLICY "cleaners_upload_own_docs"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'cleaner-documents'
    AND (storage.foldername(name))[1] = (auth.uid())::text
  );

DROP POLICY IF EXISTS "cleaners_read_own_docs" ON storage.objects;
CREATE POLICY "cleaners_read_own_docs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'cleaner-documents'
    AND (storage.foldername(name))[1] = (auth.uid())::text
  );

DROP POLICY IF EXISTS "cleaners_update_own_docs" ON storage.objects;
CREATE POLICY "cleaners_update_own_docs"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'cleaner-documents'
    AND (storage.foldername(name))[1] = (auth.uid())::text
  );

DROP POLICY IF EXISTS "admin_read_all_cleaner_docs" ON storage.objects;
CREATE POLICY "admin_read_all_cleaner_docs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'cleaner-documents'
    AND EXISTS (
      SELECT 1 FROM auth.users
      WHERE users.id = auth.uid()
        AND ((users.raw_app_meta_data ->> 'role') = 'admin')
    )
  );
