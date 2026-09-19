-- Upload de documentos KYC (bucket cleaner-documents) falhava com HTTP 400
-- "permission denied for table users": o upsert do storage avalia tambem as
-- policies de SELECT do bucket, e a policy de admin fazia
-- EXISTS(SELECT 1 FROM auth.users ...) — tabela que o role authenticated nao
-- pode ler. Passa a ler o mesmo role directamente do claim app_metadata do
-- JWT (auth.jwt()), sem tocar em auth.users. Semanticamente equivalente:
-- app_metadata do JWT = raw_app_meta_data.
DROP POLICY IF EXISTS "admin_read_all_cleaner_docs" ON storage.objects;
CREATE POLICY "admin_read_all_cleaner_docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'cleaner-documents'
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );
