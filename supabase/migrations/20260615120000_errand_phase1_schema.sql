-- ═══════════════════════════════════════════════════════════════════════════
-- FAVORES (errand) — Fase 1.A: schema aditivo
-- Bloco 2 (campos errand em orders) + Bloco 3 (campos parsed em order_receipts_v2)
-- + Bloco 4 (products.source default). 100% ADITIVO, backward-compat total.
-- NÃO toca pricing/create_order/dispatch (Fase 2). NÃO altera colunas financeiras.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── orders: campos do pedido de favor (todos nullable / default seguro) ──────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS errand_description              text,
  ADD COLUMN IF NOT EXISTS errand_location                 text,
  ADD COLUMN IF NOT EXISTS errand_location_lat             double precision,
  ADD COLUMN IF NOT EXISTS errand_location_lng             double precision,
  ADD COLUMN IF NOT EXISTS errand_home_stop                boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS errand_home_stop_reason         text,
  ADD COLUMN IF NOT EXISTS errand_home_stop_cash_cents     integer,
  ADD COLUMN IF NOT EXISTS errand_speed                    text,
  ADD COLUMN IF NOT EXISTS errand_has_purchase             boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS errand_estimated_purchase_cents integer;

-- CHECK errand_speed (idempotente; permite NULL para pedidos não-errand)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_errand_speed_check') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_errand_speed_check
      CHECK (errand_speed IS NULL OR errand_speed IN ('normal','express'));
  END IF;
END $$;

-- CHECK errand_home_stop_reason (idempotente; sem acentos para consistência)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_errand_home_stop_reason_check') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_errand_home_stop_reason_check
      CHECK (errand_home_stop_reason IS NULL OR errand_home_stop_reason IN ('receita','cartao','dinheiro','outro'));
  END IF;
END $$;

COMMENT ON COLUMN public.orders.errand_description IS
  'Favores: descrição livre do favor (máx errand_description_max_chars).';
COMMENT ON COLUMN public.orders.errand_location_lat IS
  'Favores: latitude do local do favor (para validar distância server-side — SEC-2).';
COMMENT ON COLUMN public.orders.errand_home_stop_cash_cents IS
  'Favores: dinheiro recebido do cliente na paragem em casa (modo dinheiro). Estafeta regista na recolha.';

-- ── order_receipts_v2: dados estruturados do parser Gemini (Bloco 3) ─────────
ALTER TABLE public.order_receipts_v2
  ADD COLUMN IF NOT EXISTS receipt_parsed             jsonb,
  ADD COLUMN IF NOT EXISTS receipt_parsed_total_cents integer,
  ADD COLUMN IF NOT EXISTS receipt_match              boolean,
  ADD COLUMN IF NOT EXISTS receipt_parsed_store       text;

COMMENT ON COLUMN public.order_receipts_v2.receipt_parsed IS
  'Bloco 3: parse Gemini 2.5-flash {store,total_cents,lines[],datetime}. SHADOW — valor digitado pelo estafeta é a fonte de verdade.';
COMMENT ON COLUMN public.order_receipts_v2.receipt_match IS
  'Bloco 3: false quando |digitado - parsed| > receipt_divergence_alert_cents. Apenas alerta admin, não bloqueia.';

-- ── products: source default (coluna JÁ EXISTE — só ajustar default) ─────────
ALTER TABLE public.products ALTER COLUMN source SET DEFAULT 'manual';
