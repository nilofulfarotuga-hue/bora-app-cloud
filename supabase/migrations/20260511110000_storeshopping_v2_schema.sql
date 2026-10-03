-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCO 3.1 — StoreShopping v2 schema (paralelo a v1, backward compat total)
-- - orders.purchase_flow_version (default 1 = legacy, 2 = novo fluxo)
-- - order_purchase_items_v2 (checklist do estafeta)
-- - order_receipts_v2 (foto talão + OCR + reembolso)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS purchase_flow_version SMALLINT NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.orders.purchase_flow_version IS
  '5G — 1=legacy finalize_storeshopping_purchase, 2=novo fluxo v2 (storeShopping não-parceiro com checklist + foto talão + OCR + reembolso).';

-- ═══════════════════════════════════════════════════════════════════════════
-- Items v2 (snapshot original + estado pós-compra)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.order_purchase_items_v2 (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                      text NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  original_item_id              uuid,
  original_name                 text NOT NULL,
  original_price_cents          integer NOT NULL DEFAULT 0,
  original_qty                  smallint NOT NULL DEFAULT 1,
  status                        text NOT NULL CHECK (status IN (
    'pending','purchased','unavailable','replaced','added'
  )),
  actual_name                   text,
  actual_price_cents            integer,
  actual_qty                    smallint,
  client_confirmed_at           timestamptz,
  client_confirmation_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  updated_at                    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_purchase_items_v2_order
  ON public.order_purchase_items_v2 (order_id);

ALTER TABLE public.order_purchase_items_v2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "client_select_own_items" ON public.order_purchase_items_v2;
CREATE POLICY "client_select_own_items" ON public.order_purchase_items_v2
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "driver_rw_assigned_items" ON public.order_purchase_items_v2;
CREATE POLICY "driver_rw_assigned_items" ON public.order_purchase_items_v2
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.assigned_driver_id = auth.uid()::text)
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.assigned_driver_id = auth.uid()::text)
  );

DROP POLICY IF EXISTS "admin_select_all_items" ON public.order_purchase_items_v2;
CREATE POLICY "admin_select_all_items" ON public.order_purchase_items_v2
  FOR SELECT USING (public.is_admin());

DROP POLICY IF EXISTS "service_role_all_items" ON public.order_purchase_items_v2;
CREATE POLICY "service_role_all_items" ON public.order_purchase_items_v2
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.order_purchase_items_v2 IS
  '5G — Checklist do estafeta no fluxo storeShopping v2.';

-- ═══════════════════════════════════════════════════════════════════════════
-- Receipts v2 (foto + OCR + reembolso)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.order_receipts_v2 (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                      text NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  photo_url                     text NOT NULL,
  photo_taken_at                timestamptz NOT NULL DEFAULT now(),
  driver_typed_total_cents      integer NOT NULL,
  ocr_extracted_total_cents     integer,
  ocr_diff_cents                integer,
  ocr_flagged                   boolean NOT NULL DEFAULT false,
  ocr_raw_response              jsonb,
  ocr_ran_at                    timestamptz,
  reimbursement_status          text NOT NULL DEFAULT 'pending_admin'
    CHECK (reimbursement_status IN ('pending_admin','admin_paid','cash_settled','rejected')),
  reimbursement_amount_cents    integer,
  reimbursement_processed_at    timestamptz,
  reimbursement_admin_id        uuid REFERENCES auth.users(id),
  reimbursement_admin_notes     text,
  created_at                    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_receipts_v2_reimb_status
  ON public.order_receipts_v2 (reimbursement_status, created_at);
CREATE INDEX IF NOT EXISTS idx_order_receipts_v2_ocr_flagged
  ON public.order_receipts_v2 (ocr_flagged) WHERE ocr_flagged = true;

ALTER TABLE public.order_receipts_v2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "client_select_own_receipt" ON public.order_receipts_v2;
CREATE POLICY "client_select_own_receipt" ON public.order_receipts_v2
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "driver_rw_own_receipt" ON public.order_receipts_v2;
CREATE POLICY "driver_rw_own_receipt" ON public.order_receipts_v2
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.assigned_driver_id = auth.uid()::text)
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.assigned_driver_id = auth.uid()::text)
  );

DROP POLICY IF EXISTS "admin_select_all_receipts" ON public.order_receipts_v2;
CREATE POLICY "admin_select_all_receipts" ON public.order_receipts_v2
  FOR SELECT USING (public.is_admin());

DROP POLICY IF EXISTS "admin_update_receipts" ON public.order_receipts_v2;
CREATE POLICY "admin_update_receipts" ON public.order_receipts_v2
  FOR UPDATE USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "service_role_all_receipts" ON public.order_receipts_v2;
CREATE POLICY "service_role_all_receipts" ON public.order_receipts_v2
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.order_receipts_v2 IS
  '5G — Foto talão storeShopping v2. OCR Gemini Flash shadow (Decisão H). Reembolso (Decisão L novo modelo): Stripe/MBWay→pending_admin; CASH→cash_settled auto.';

-- Bucket criado via apply_migration anterior; RLS de storage.objects requer
-- aplicação manual via Studio (privilégios de owner). Ver TODO_STORAGE_RLS.sql.
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', false)
ON CONFLICT (id) DO NOTHING;
