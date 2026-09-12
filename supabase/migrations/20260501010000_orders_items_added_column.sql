-- ============================================================================
-- BORA — Orders: items_added column for driver storeShopping additions
-- ============================================================================
-- Estafeta pode adicionar produtos durante storeShopping não-parceiro:
--   Caso A: cliente pediu via chat (acrescentar)
--   Caso B: estafeta substitui produto faltando (manteiga acabou →
--           adiciona "manteiga marca X" similar)
-- Estafeta escreve nome + preço base. App aplica +15%
-- (non_partner_markup_pct) auto antes de cobrar cliente.
-- ============================================================================

BEGIN;

-- ── Coluna ──────────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS items_added JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.orders.items_added IS
  'Items adicionados pelo estafeta durante storeShopping. JSONB array '
  '[{name, price_base_cents, price_final_cents, qty, added_at, reason}]. '
  'price_final = price_base * (1 + non_partner_markup_pct).';

-- ── Setting: limite extra charge ────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('max_extra_charge_pct', '0.30',
   'Limite extra_charge_amount como % do total original. Acima disto, '
   'log warning admin (não bloqueia).',
   'storeshopping')
ON CONFLICT (key) DO NOTHING;

COMMIT;
