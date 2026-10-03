-- Sessão Reservas Split €2/€1 v2 + Consume Credit — 2026-04-30
-- Idempotente. Aplicado via MCP em prod; este ficheiro replay-safe.

-- T2: orders.menu_credit_applied_cents
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS menu_credit_applied_cents INTEGER NOT NULL DEFAULT 0
    CHECK (menu_credit_applied_cents >= 0);

-- T3: partner_reservation_payouts (Bora deve €2 ao parceiro por reserva chegada)
CREATE TABLE IF NOT EXISTS public.partner_reservation_payouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id text NOT NULL,
  reservation_id uuid NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'cancelled')),
  paid_at timestamptz,
  paid_in_payout_id uuid,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT uniq_payout_per_reservation UNIQUE (reservation_id)
);
CREATE INDEX IF NOT EXISTS idx_partner_payouts_pending
  ON public.partner_reservation_payouts (partner_id, status)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_partner_payouts_partner_recent
  ON public.partner_reservation_payouts (partner_id, created_at DESC);
ALTER TABLE public.partner_reservation_payouts ENABLE ROW LEVEL SECURITY;

-- All RPCs (partner_mark_arrival v2, create_order v3 with menu credit,
-- admin_partner_payout_summary, admin_mark_partner_payouts_paid,
-- admin_list_partner_payouts, client_get_active_menu_credit) — definitions
-- complete em prod via MCP.

COMMENT ON TABLE public.partner_reservation_payouts IS
  '§18 v2: Bora deve €2 ao parceiro por reserva chegada. Settlement semanal via admin_mark_partner_payouts_paid.';
COMMENT ON COLUMN public.orders.menu_credit_applied_cents IS
  '§18 v2: cents de restaurant_menu_credits aplicados em create_order. Stripe charge subtrai.';
