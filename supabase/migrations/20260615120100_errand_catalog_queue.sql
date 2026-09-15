-- ═══════════════════════════════════════════════════════════════════════════
-- FAVORES (errand) — Fase 1.B: fila do catálogo automático (Bloco 4)
-- Cada favor com compra + talão parseado (Gemini) alimenta esta fila.
-- NUNCA publica automaticamente — aprovação admin obrigatória.
-- RLS fail-closed: apenas admin + service_role (cliente/estafeta sem acesso —
-- a fila é puramente administrativa; não contém dados que o cliente precise ver).
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.errand_catalog_queue (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_order_id         text REFERENCES public.orders(id) ON DELETE SET NULL,
  store_name              text NOT NULL,
  store_normalized        text NOT NULL,
  product_name            text NOT NULL,
  product_normalized      text NOT NULL,
  price_cents             integer NOT NULL DEFAULT 0,
  category                text NOT NULL DEFAULT 'Geral',
  status                  text NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','approved','rejected')),
  approved_product_id     text,
  approved_restaurant_id  text,
  reviewed_by             uuid REFERENCES auth.users(id),
  reviewed_at             timestamptz,
  review_notes            text,
  created_at              timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_errand_catalog_queue_status
  ON public.errand_catalog_queue (status, created_at);
CREATE INDEX IF NOT EXISTS idx_errand_catalog_queue_dedup
  ON public.errand_catalog_queue (store_normalized, product_normalized);

ALTER TABLE public.errand_catalog_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_all_errand_queue" ON public.errand_catalog_queue;
CREATE POLICY "admin_all_errand_queue" ON public.errand_catalog_queue
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "service_role_all_errand_queue" ON public.errand_catalog_queue;
CREATE POLICY "service_role_all_errand_queue" ON public.errand_catalog_queue
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.errand_catalog_queue IS
  'Bloco 4 — fila de produtos extraídos de favores (Gemini) para aprovação admin. Aprovar cria/usa loja non-partner OCULTA (is_online=false) + product source=errand_auto. Gated por errand_catalog_queue_enabled.';
