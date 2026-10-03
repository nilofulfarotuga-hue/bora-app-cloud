-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) a 20/09/2026 21:51 — versão 20260920205140.
-- Espelho exacto de supabase_migrations.schema_migrations (lido a 20/09 21:55 pelo Claude Code).
ALTER TABLE public.driver_weekly_settlements
  ADD COLUMN IF NOT EXISTS tvde_rides_count   integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tvde_earnings      numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tvde_cash_received numeric DEFAULT 0;

COMMENT ON COLUMN public.driver_weekly_settlements.tvde_rides_count IS
  'Contas claras 20/09/2026: corridas TVDE finalizadas na semana. Antes desta data o acerto so contava entregas.';
COMMENT ON COLUMN public.driver_weekly_settlements.tvde_earnings IS
  'Ganho do motorista nas corridas TVDE da semana (entra em total_earnings).';
COMMENT ON COLUMN public.driver_weekly_settlements.tvde_cash_received IS
  'Dinheiro que o motorista recebeu em mao nas corridas TVDE pagas a dinheiro (entra em total_cash_received).';
