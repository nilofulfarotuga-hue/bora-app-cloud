-- ============================================================================
-- BORA — avatars bucket RLS policies (T6 — fix 400/403 on profile photo upload)
-- ============================================================================
-- Root cause (per .claude/.ai/reports/2026-04-29-cliente-bugs-investigacao.md):
--   The avatars bucket has INSERT policy but no UPDATE policy. Flutter uses
--   `upsert: true` which becomes a POST that the server interprets as
--   UPDATE-or-INSERT. Without UPDATE policy, the second upload by the same
--   user fails with 400 (RLS denial returned as malformed-request).
--
-- Fix: ensure all 4 CRUD policies exist with the canonical path pattern:
--   avatars/{userId}/avatar.jpg  →  auth.uid()::text = (storage.foldername(name))[1]
--
-- Idempotent (DROP IF EXISTS + CREATE). Safe to re-apply.
-- ============================================================================

BEGIN;

-- 1. Ensure bucket exists and is public (read-only for everyone, write gated by RLS).
INSERT INTO storage.buckets (id, name, public)
  VALUES ('avatars', 'avatars', true)
  ON CONFLICT (id) DO UPDATE SET public = true;

-- 2. Drop any pre-existing policies on storage.objects that target avatars
--    (idempotent re-apply) — naming convention defensive against historical drift.
DROP POLICY IF EXISTS "avatars_select_public"  ON storage.objects;
DROP POLICY IF EXISTS "avatars_insert_owner"   ON storage.objects;
DROP POLICY IF EXISTS "avatars_update_owner"   ON storage.objects;
DROP POLICY IF EXISTS "avatars_delete_owner"   ON storage.objects;

-- 3. SELECT: anyone (auth or not) can read avatars (public profile pics).
CREATE POLICY "avatars_select_public"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'avatars');

-- 4. INSERT: authenticated user can upload only inside their own folder.
CREATE POLICY "avatars_insert_owner"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- 5. UPDATE: authenticated user can replace their own avatar (THE MISSING PIECE).
CREATE POLICY "avatars_update_owner"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- 6. DELETE: authenticated user can delete their own avatar (used in account deletion / "remove photo").
CREATE POLICY "avatars_delete_owner"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

COMMIT;

-- ============================================================================
-- POST-APPLY SMOKE TEST
-- ============================================================================
-- 1. Confirm 4 policies exist:
--      SELECT policyname, cmd FROM pg_policies
--       WHERE schemaname = 'storage' AND tablename = 'objects'
--         AND policyname LIKE 'avatars_%' ORDER BY policyname;
--      -- Expect: avatars_delete_owner, avatars_insert_owner,
--      --         avatars_select_public, avatars_update_owner.
-- 2. From a real client device, upload twice in a row — second upload should
--    succeed (was failing with 400 before).
-- 3. Confirm public read: open https://<project>.supabase.co/storage/v1/object/public/avatars/<uid>/avatar.jpg
--    in a non-authenticated browser tab.
-- ============================================================================
