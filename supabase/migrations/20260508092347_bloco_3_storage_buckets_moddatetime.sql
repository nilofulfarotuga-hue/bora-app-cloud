-- ═══════════════════════════════════════════════════════════
-- BLOCO 3 — Storage buckets + auth hardening
-- Data: 2026-05-08 / Sessão 7-SEC-2
-- Decisões Danilo:
--   avatars=público, order-photos=cliente+driver+admin+partner
-- ═══════════════════════════════════════════════════════════

-- ─── PARTE 1: avatars (público mas separar ops) ────────────
DROP POLICY IF EXISTS "avatars_anyone_all_operations" ON storage.objects;

CREATE POLICY "avatars_select_public" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'avatars');

CREATE POLICY "avatars_insert_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "avatars_update_own" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "avatars_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ─── PARTE 2: order-photos (privatizar + restringir) ───────
UPDATE storage.buckets SET public = false WHERE id = 'order-photos';

DROP POLICY IF EXISTS "order-photos read" ON storage.objects;

CREATE POLICY "order_photos_select_participants" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'order-photos'
    AND (
      is_admin()
      OR (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.id = (storage.foldername(name))[2]
          AND (
            o.user_id = auth.uid()
            OR o.assigned_driver_id::text = auth.uid()::text
            OR EXISTS (
              SELECT 1 FROM public.restaurants r
              WHERE r.id = o.restaurant_id
                AND r.user_ = auth.uid()
            )
          )
      )
    )
  );

-- ─── PARTE 3: moddatetime extension (mover schema) ─────────
CREATE SCHEMA IF NOT EXISTS extensions;
ALTER EXTENSION moddatetime SET SCHEMA extensions;
