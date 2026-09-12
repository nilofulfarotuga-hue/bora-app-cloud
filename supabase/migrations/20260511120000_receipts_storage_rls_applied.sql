-- ═══════════════════════════════════════════════════════════════════════════
-- TODO — Aplicar via Supabase Studio (requer privilégios de owner em
-- storage.objects, que apply_migration não tem).
--
-- Como aplicar:
--   1. Abrir Supabase Studio → SQL Editor
--   2. Copiar + executar este ficheiro
--   3. Confirmar via:
--      SELECT policyname FROM pg_policies WHERE tablename='objects' AND schemaname='storage';
--
-- Pré-requisitos: bucket 'receipts' já criado pela migration
-- 20260511110000_storeshopping_v2_schema.sql (INSERT em storage.buckets).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Estafeta INSERT only se atribuído ao pedido
DROP POLICY IF EXISTS "driver_insert_own_receipt" ON storage.objects;
CREATE POLICY "driver_insert_own_receipt" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'receipts'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = REPLACE(REPLACE(name, 'receipts/', ''), '.jpg', '')
        AND o.assigned_driver_id = auth.uid()::text
    )
  );

-- 2. Estafeta SELECT só dos pedidos atribuídos
DROP POLICY IF EXISTS "driver_select_own_receipt" ON storage.objects;
CREATE POLICY "driver_select_own_receipt" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'receipts'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = REPLACE(REPLACE(name, 'receipts/', ''), '.jpg', '')
        AND o.assigned_driver_id = auth.uid()::text
    )
  );

-- 3. Cliente SELECT só dos seus pedidos
DROP POLICY IF EXISTS "client_select_own_receipt" ON storage.objects;
CREATE POLICY "client_select_own_receipt" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'receipts'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = REPLACE(REPLACE(name, 'receipts/', ''), '.jpg', '')
        AND o.user_id = auth.uid()
    )
  );

-- 4. Admin SELECT all
DROP POLICY IF EXISTS "admin_select_all_receipts_storage" ON storage.objects;
CREATE POLICY "admin_select_all_receipts_storage" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'receipts' AND public.is_admin()
  );
