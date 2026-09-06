-- ============================================================================
-- BORA — FASE 4: foto prova prateleira vazia (Glovo-style)
-- ============================================================================
-- Driver tira foto ao marcar item indisponível em storeShopping. Foto vai
-- para storage bucket order-photos com path
--   {driver_uid}/{order_id}/unavailable_{productId}_{ts}.jpg
-- (satisfaz policy "order-photos upload own" — folder1=auth.uid).
-- URL pública guardada em orders.items_unavailable_photos JSONB
-- (Map<productId, url>).
--
-- Coluna NÃO está em enforce_financial_immutability — driver pode UPDATE
-- direct sem GUC bypass.
-- ============================================================================

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS items_unavailable_photos JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.orders.items_unavailable_photos IS
  'Map productId → photo URL. Driver tira foto da prateleira vazia ao marcar item como unavailable em storeShopping. Storage path: {driver_uid}/{order_id}/unavailable_{productId}_{ts}.jpg em bucket order-photos.';

COMMIT;
