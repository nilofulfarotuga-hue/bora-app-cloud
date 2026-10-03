-- ============================================================================
-- BORA — Sessão 3B-NOVA — Wallet com Saldo Negativo (B1 + B2)
-- ============================================================================
-- Permite client_wallets.free_balance_cents ficar negativo até hard floor.
-- Soft cap (gate em RPC): -€10. Hard floor (CHECK constraint DB): -€20.
-- Cap absoluto por ajuste de pedido: €10.
-- Audit-trail completo via wallet_transactions (balance_after_cents +
-- idempotency_key).
--
-- Decisão fiscal (Danilo + contabilista, 2026-05-04):
-- Regime Art. 53.º CIVA — isenção IVA enquanto facturação anual <€15.000.
-- Cada débito gera nota interna referenciada na factura do PRÓXIMO pedido.
-- Ver business_rules.md secção "Wallet — Saldo Negativo".
--
-- Kill-switch: platform_settings.wallet_negative_enabled = false → RPCs
-- caem no comportamento Sessão 3 (extraRequired).
-- ============================================================================

BEGIN;

-- ── 1. CHECK constraint: permitir negativo até -€20 (hard floor) ───────────
ALTER TABLE public.client_wallets
  DROP CONSTRAINT IF EXISTS client_wallets_free_balance_cents_check;

ALTER TABLE public.client_wallets
  ADD CONSTRAINT client_wallets_free_balance_cents_check
  CHECK (free_balance_cents >= -2000);

-- ── 2. wallet_transactions: balance_after_cents + idempotency_key ──────────
ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS balance_after_cents INTEGER;

ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_wallet_tx_idempotency_key
  ON public.wallet_transactions (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ── 3. Expandir CHECK kind (novos valores Sessão 3B) ───────────────────────
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_kind_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_kind_check
  CHECK (kind IN (
    'refund_credit_free','refund_credit_tokens',
    'order_payment','admin_grant','admin_revoke',
    'cashback','referral',
    -- Sessão 3B-NOVA
    'debit',         -- débito pós-entrega (sacos, substituições, adições)
    'settlement',    -- liquidação automática de saldo devedor anterior
    'adjustment',    -- ajuste manual (uso futuro)
    'forgive'        -- admin perdoa dívida
  ));

-- ── 4. platform_settings: 6 chaves novas + kill-switch ─────────────────────
INSERT INTO public.platform_settings (key, value, description) VALUES
  ('wallet_max_negative_balance_cents', '-1000'::jsonb,
   'Soft cap: cliente bloqueado de criar pedidos se balance < este valor (-€10).'),
  ('wallet_hard_floor_cents', '-2000'::jsonb,
   'Hard floor DB: espelho do CHECK constraint em client_wallets (-€20).'),
  ('max_extra_charge_cents', '1000'::jsonb,
   'Cap absoluto cents por ajuste pós-entrega (€10/pedido). Defesa em depth.'),
  ('wallet_negative_alert_days', '90'::jsonb,
   'Dias inactividade com saldo negativo para gerar alerta admin.'),
  ('wallet_negative_action_days', '180'::jsonb,
   'Dias inactividade com saldo negativo para action_required (cobrar/perdoar/suspender).'),
  ('wallet_negative_enabled', 'true'::jsonb,
   'Kill-switch: false → create_order salta gate+settlement; finalize cai em extraRequired (comportamento Sessão 3).')
ON CONFLICT (key) DO NOTHING;

COMMIT;
