-- BORA — Sessão 3 (saco mercado): cobrança pós-entrega
--
-- Adições aditivas (sem backfill, sem mudar comportamento existente):
--   1. orders.cash_total_due NUMERIC NULL — total a cobrar em mão (cash + sacos)
--      Código novo escreve quando cash + bag_charge > 0; código antigo lê
--      final_total como fallback.
--   2. pending_charges TABLE — fila de cobranças automáticas pós-entrega
--      Sessão 3 actual NÃO insere ainda (charge automático = Sessão 3B).
--      Tabela criada para ficar pronta + RLS para admin auditar.
--
-- Política sacos mercado (storeShopping não-parceiro):
--   • bag_count: 0..5 (cap aplicado na RPC finalize_storeshopping_purchase)
--   • bag_fee = bag_count * €0.10 (max €0.50)
--   • Cobrança ao FINALIZAR compra:
--     - cash → soma a orders.cash_total_due (estafeta cobra em mão)
--     - card/mbway → marca payment_status='extraRequired' (Sessão 3B implementa
--       charge automático off_session via pending_charges)
--
-- ZERO BACKFILL: pedidos históricos mantêm cash_total_due=NULL e fluxo legacy.

BEGIN;

-- ── 1. orders.cash_total_due ───────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cash_total_due NUMERIC NULL;

COMMENT ON COLUMN public.orders.cash_total_due IS
  'Total a cobrar em dinheiro ao cliente na entrega (inclui valor do pedido + extras como sacos de mercado). NULL = usar final_total. Preenchido apenas para payment_method=cash quando finalize_storeshopping_purchase detecta extra > 0.';

-- ── 2. pending_charges ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pending_charges (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                 TEXT NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  amount_cents             INT NOT NULL CHECK (amount_cents BETWEEN 1 AND 50),
  reason                   TEXT NOT NULL CHECK (reason IN ('market_bags')),
  status                   TEXT NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','succeeded','failed','requires_action')),
  idempotency_key          TEXT NOT NULL UNIQUE,
  stripe_payment_intent_id TEXT NULL,
  error_code               TEXT NULL,
  retry_count              INT NOT NULL DEFAULT 0,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.pending_charges IS
  'Fila de cobranças automáticas pós-entrega (sacos mercado). Sessão 3B implementa drenagem via Edge Function charge-extra off_session.';

CREATE INDEX IF NOT EXISTS idx_pending_charges_status_created
  ON public.pending_charges (status, created_at);

CREATE INDEX IF NOT EXISTS idx_pending_charges_order
  ON public.pending_charges (order_id);

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.pending_charges_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pending_charges_updated_at ON public.pending_charges;
CREATE TRIGGER trg_pending_charges_updated_at
  BEFORE UPDATE ON public.pending_charges
  FOR EACH ROW EXECUTE FUNCTION public.pending_charges_set_updated_at();

-- RLS
ALTER TABLE public.pending_charges ENABLE ROW LEVEL SECURITY;

-- Admin SELECT/UPDATE (allowlist via JWT email)
DROP POLICY IF EXISTS pending_charges_admin_select ON public.pending_charges;
CREATE POLICY pending_charges_admin_select
  ON public.pending_charges
  FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() ->> 'email') IN ('nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')
  );

DROP POLICY IF EXISTS pending_charges_admin_update ON public.pending_charges;
CREATE POLICY pending_charges_admin_update
  ON public.pending_charges
  FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() ->> 'email') IN ('nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')
  );

-- INSERT só via SECURITY DEFINER (funções server-side); cliente/estafeta sem
-- INSERT directo. Não criamos policy INSERT para authenticated.

-- service_role bypassa RLS automaticamente (SUPABASE_SERVICE_ROLE_KEY no
-- webhook handler vai poder UPDATE status quando charge completa).

COMMIT;
