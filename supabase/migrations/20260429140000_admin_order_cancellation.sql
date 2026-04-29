-- ============================================================================
-- BORA — Admin order cancellation schema (FASE 4 · BUG 3 · M1)
-- ============================================================================
-- Schema for admin-initiated cancellation of orders. Adds the columns and
-- ENUMs needed by:
--   - admin_cancel_order RPC (M2)
--   - admin-cancel-order Edge Function (M3)
--   - AdminOrderDetailScreen Timeline tab (F1)
--
-- DESIGN DECISIONS (Danilo 2026-04-29):
--   - Status canónico para admin = 'cancelled' (NÃO 'rejected'). 'rejected'
--     fica reservado para auto-fail do sistema (TTL, dispatch fail).
--   - cancellation_initiator distingue origem: client / admin / system.
--   - Refund FULL sempre (Bora absorve perda em pickedUp/onTheWay).
--   - Reuse columnas existentes onde possível: cancel_reason, cancelled_at,
--     refund_amount já existem (cliente already-cancelled flow).
--   - NÃO cria tabela order_status_history — timeline usa admin_audit_log
--     (entity_type='order') + colunas de orders.
--
-- Out of scope desta migration:
--   - RPC admin_cancel_order        → M2 (separate migration)
--   - Edge Function admin-cancel-order → M3
--   - Reatribuir estafeta           → fase posterior
--
-- Plan reference: .claude/.ai/reports/2026-04-29-fase4-bug3-b2-plano.md
-- ============================================================================

BEGIN;

-- ─── 1. ENUM: cancellation_reason_code ─────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
                 WHERE t.typname='cancellation_reason_code' AND n.nspname='public') THEN
    CREATE TYPE public.cancellation_reason_code AS ENUM (
      'client_request',
      'partner_unable',
      'driver_unavailable',
      'payment_failed',
      'fraud_suspected',
      'address_invalid',
      'food_quality_issue',
      'system_error',
      'other'
    );
  END IF;
END $$;

COMMENT ON TYPE public.cancellation_reason_code IS
  'Canonical cancellation categories for aggregate reporting and dispute handling. Free-form detail goes in orders.cancel_reason TEXT.';

-- ─── 2. ENUM: cancellation_initiator ───────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
                 WHERE t.typname='cancellation_initiator' AND n.nspname='public') THEN
    CREATE TYPE public.cancellation_initiator AS ENUM ('client', 'admin', 'system');
  END IF;
END $$;

COMMENT ON TYPE public.cancellation_initiator IS
  'Who triggered the cancellation. client = client-cancel-order Edge Function; admin = admin-cancel-order Edge Function; system = TTL auto-reject etc.';

-- ─── 3. ALTER orders — admin cancellation columns ──────────────────────────
-- Idempotente. NÃO altera tipo de refund_amount existente (float8 legacy).
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cancelled_by             UUID,
  ADD COLUMN IF NOT EXISTS cancellation_initiator   public.cancellation_initiator,
  ADD COLUMN IF NOT EXISTS cancellation_reason_code public.cancellation_reason_code,
  ADD COLUMN IF NOT EXISTS refund_id                TEXT,
  ADD COLUMN IF NOT EXISTS refund_status            TEXT,
  ADD COLUMN IF NOT EXISTS refunded_at              TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.cancelled_by IS
  'auth.users.id do admin que cancelou (NULL para client/system cancellations).';
COMMENT ON COLUMN public.orders.cancellation_initiator IS
  'Origem do cancel: client / admin / system. Quando NULL, ordem não foi cancelada (status=cancelled apenas em fluxo legacy).';
COMMENT ON COLUMN public.orders.cancellation_reason_code IS
  'Categoria canónica (ENUM cancellation_reason_code). Set por admin-cancel-order ou client-cancel-order.';
COMMENT ON COLUMN public.orders.refund_id IS
  'Stripe refund ID (re_…) quando aplicável. NULL para cash/mbway-pendente/failed.';
COMMENT ON COLUMN public.orders.refund_status IS
  'Estado do refund: none / not_applicable / pending / succeeded / failed. Defensiva: text livre, validado em código.';
COMMENT ON COLUMN public.orders.refunded_at IS
  'UTC timestamp do refund Stripe bem-sucedido. NULL se não houve refund.';

-- ─── 4. Index — consultas admin de canceladas recentes ─────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_cancelled_admin
  ON public.orders (cancelled_at DESC)
  WHERE cancellation_initiator = 'admin';

COMMIT;
