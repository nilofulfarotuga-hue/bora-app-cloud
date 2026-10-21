-- Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4).
-- O balde público `avatars` tinha 4 políticas para anon E authenticated só com bucket_id='avatars':
-- qualquer pessoa, mesmo sem conta (só com a chave pública da app), podia enviar, substituir e apagar
-- a foto de perfil de qualquer pessoa (provado 21/10: upload e delete anónimos com HTTP 200; 10 fotos
-- de utilizadores reais alteráveis por anon). A app só escreve em '<uid>/avatar.jpg' com sessão
-- (profile_screen.dart, provider_upload_service.dart); a Edge upload-avatar e a delete-account usam a
-- chave de serviço (não passam por estas políticas). Ver as fotos continua público pelo URL público
-- do balde (não depende destas políticas).
-- Antes:
--   avatars_anon_delete DELETE {anon,authenticated} USING (bucket_id = 'avatars')
--   avatars_anon_insert INSERT {anon,authenticated} CHECK (bucket_id = 'avatars')
--   avatars_anon_select SELECT {anon,authenticated} USING (bucket_id = 'avatars')
--   avatars_anon_update UPDATE {anon,authenticated} USING (bucket_id = 'avatars') CHECK (bucket_id = 'avatars')
DROP POLICY IF EXISTS avatars_anon_delete ON storage.objects;
DROP POLICY IF EXISTS avatars_anon_insert ON storage.objects;
DROP POLICY IF EXISTS avatars_anon_select ON storage.objects;
DROP POLICY IF EXISTS avatars_anon_update ON storage.objects;

CREATE POLICY avatars_propria_pasta_select ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

CREATE POLICY avatars_propria_pasta_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

CREATE POLICY avatars_propria_pasta_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text)
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

CREATE POLICY avatars_propria_pasta_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);