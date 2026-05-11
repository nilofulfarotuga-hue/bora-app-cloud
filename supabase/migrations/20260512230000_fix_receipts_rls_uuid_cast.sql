-- ════════════════════════════════════════════════════════════
-- BUG #4 (sessão exec post-test manual 2026-05-12)
-- Fix RLS receipts: cast uuid::text para comparação correcta.
--
-- Bug: orders.id é UUID, replace() retorna TEXT. Comparação directa
-- `o.id = replace(...)` falhava silenciosamente em runtime (operator
-- mismatch).
--
-- Adicionalmente: driver_insert_own_receipt estava aberta (só bucket
-- check). Restringir para EXISTS check no order assigned_driver_id.
--
-- NOTA: replace() é tolerante a path com OU sem prefixo 'receipts/'.
-- Cliente Flutter foi simultaneamente corrigido (BUG #1) para passar
-- path sem prefixo, mas RLS continua a aceitar ambos formatos (idempotente).
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "driver_insert_own_receipt" ON storage.objects;
DROP POLICY IF EXISTS "driver_select_own_receipt" ON storage.objects;
DROP POLICY IF EXISTS "client_select_own_receipt" ON storage.objects;

CREATE POLICY "driver_insert_own_receipt"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'receipts'
  AND EXISTS (
    SELECT 1 FROM orders o
    WHERE o.id::text = replace(replace(objects.name, 'receipts/', ''), '.jpg', '')
      AND o.assigned_driver_id = (auth.uid())::text
  )
);

CREATE POLICY "driver_select_own_receipt"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'receipts'
  AND EXISTS (
    SELECT 1 FROM orders o
    WHERE o.id::text = replace(replace(objects.name, 'receipts/', ''), '.jpg', '')
      AND o.assigned_driver_id = (auth.uid())::text
  )
);

CREATE POLICY "client_select_own_receipt"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'receipts'
  AND EXISTS (
    SELECT 1 FROM orders o
    WHERE o.id::text = replace(replace(objects.name, 'receipts/', ''), '.jpg', '')
      AND o.user_id = auth.uid()
  )
);

-- admin_select_all_receipts_storage inalterada (já correcta — só usa is_admin()).
