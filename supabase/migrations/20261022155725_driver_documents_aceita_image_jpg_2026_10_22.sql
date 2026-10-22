-- A app do estafeta envia contentType 'image/jpg' (tirado da extensão .jpg).
-- O bucket só aceitava 'image/jpeg' → upload-driver-document dava 415 e a app
-- engolia o erro: estafetas ficavam sem foto do documento/selfie/veículo.
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/jpg','image/png','image/webp','application/pdf']
 where id = 'driver-documents';
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/jpg','image/png','application/pdf']
 where id = 'provider-atividade';
