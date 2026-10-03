-- 20260602100000_create_restaurant_documents_bucket.sql
-- Sessão noturna 2026-06-02 — FIX RGPD bloqueador de lançamento.
--
-- PROBLEMA: owner_doc_url e activity_doc_url do parceiro (docs de identidade
-- do dono + alvará de actividade) estavam a ser guardados no bucket
-- `restaurant-assets` que é PÚBLICO. Qualquer pessoa com o URL via o doc.
-- Violação RGPD confirmada (URLs `/storage/v1/object/public/restaurant-assets/...owner_doc-*.jpg`).
--
-- FIX: criar bucket `restaurant-documents` PRIVADO + RLS espelhando
-- exactamente o padrão do `driver-documents` (que já funciona).
-- Logo+hero continuam em `restaurant-assets` público (correcto).

-- 1. Criar bucket privado (idempotente)
INSERT INTO storage.buckets (id, name, public)
VALUES ('restaurant-documents', 'restaurant-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- 2. Policies (padrão idêntico a driver-documents)

-- Upload: authenticated user → na sua própria pasta (auth.uid)
-- OU em pasta temp-* (signup pré-link de auth.uid acontece em temp folder)
DROP POLICY IF EXISTS "partners_upload_own_or_temp_docs" ON storage.objects;
CREATE POLICY "partners_upload_own_or_temp_docs"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-documents'
    AND (
      (storage.foldername(name))[1] = (auth.uid())::text
      OR (storage.foldername(name))[1] LIKE 'temp-%'
    )
  );

-- Leitura — dono lê os seus próprios docs (pasta = auth.uid)
DROP POLICY IF EXISTS "partners_read_own_docs" ON storage.objects;
CREATE POLICY "partners_read_own_docs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'restaurant-documents'
    AND (storage.foldername(name))[1] = (auth.uid())::text
  );

-- Leitura admin — qualquer ficheiro neste bucket
DROP POLICY IF EXISTS "admin_read_all_restaurant_docs" ON storage.objects;
CREATE POLICY "admin_read_all_restaurant_docs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'restaurant-documents'
    AND EXISTS (
      SELECT 1 FROM auth.users
      WHERE users.id = auth.uid()
        AND ((users.raw_app_meta_data ->> 'role') = 'admin')
    )
  );

-- Admin assina URLs (mesmo padrão de admin_sign_driver_docs)
DROP POLICY IF EXISTS "admin_sign_restaurant_docs" ON storage.objects;
CREATE POLICY "admin_sign_restaurant_docs"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'restaurant-documents'
    AND (
      (storage.foldername(name))[1] = (auth.uid())::text
      OR EXISTS (
        SELECT 1 FROM auth.users
        WHERE users.id = auth.uid()
          AND ((users.raw_app_meta_data ->> 'role') = 'admin')
      )
    )
  );

-- UPDATE/DELETE: sem policy = bloqueado para todos excepto service_role
-- (operações admin destrutivas via Edge Function com service_role).
