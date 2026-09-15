-- Item 90 do goal paridade-admin-360 (P0 segurança, auditoria 360° 2026-07-01):
-- receipts + order-photos estavam PÚBLICOS (qualquer pessoa com o URL lia talões
-- e fotos de encomendas de clientes). driver-documents já estava privado (verificado).
--
-- Porque é seguro virar agora:
-- - Leitura: PrivateBucketImage re-assina URLs (incl. URLs public/ antigos na BD);
--   AdminReceiptsScreen usa createSignedUrl; policies SELECT scoped já existem
--   (admin / dono do pedido / participantes).
-- - Escrita: uploads vão por Edge Functions upload-receipt / upload-order-photo
--   (service_role, imune a RLS).
-- Rollback: UPDATE storage.buckets SET public=true WHERE id IN ('receipts','order-photos');
--
-- Também remove as policies anon de escrita NÃO-scoped (qualquer anon podia
-- INSERT/UPDATE qualquer objeto — adulteração de talões). O caminho de upload
-- real é Edge Fn; a policy "order-photos upload own" (authenticated, scoped) fica.

UPDATE storage.buckets SET public = false WHERE id IN ('receipts', 'order-photos');

DROP POLICY IF EXISTS receipts_anon_insert ON storage.objects;
DROP POLICY IF EXISTS receipts_anon_update ON storage.objects;
DROP POLICY IF EXISTS order_photos_anon_insert ON storage.objects;
DROP POLICY IF EXISTS order_photos_anon_update ON storage.objects;
