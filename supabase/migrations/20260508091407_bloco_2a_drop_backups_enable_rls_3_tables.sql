-- ═══════════════════════════════════════════════════════════
-- BLOCO 2a — Drop 6 backups + RLS nas 3 tabelas activas
-- Data: 2026-05-08 / Sessão 7-SEC-1
-- Decisão Danilo: drop backups (Abril 2026, já não necessários)
-- ═══════════════════════════════════════════════════════════

-- ─── PARTE 1: DROP 6 BACKUPS ────────────────────────────────
DROP TABLE IF EXISTS public.products_cleanup_backup_20260419 CASCADE;
DROP TABLE IF EXISTS public.products_backup_2026_04_18 CASCADE;
DROP TABLE IF EXISTS public.products_taxonomy_backup_20260419 CASCADE;
DROP TABLE IF EXISTS public.lidl_products_backup_20260420 CASCADE;
DROP TABLE IF EXISTS public.intermarche_products_backup_20260420 CASCADE;
DROP TABLE IF EXISTS public.products_backup_glovo_continente_guarda_20260422 CASCADE;

-- ─── PARTE 2: token_config (config pública leitura) ────────
ALTER TABLE public.token_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "token_config_select_authenticated" ON public.token_config
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "token_config_modify_admin" ON public.token_config
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- ─── PARTE 3: driver_token_transactions (driver vê próprio) ─
ALTER TABLE public.driver_token_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dtt_select_own_driver" ON public.driver_token_transactions
  FOR SELECT TO authenticated
  USING (driver_id::text = auth.uid()::text OR is_admin());

CREATE POLICY "dtt_modify_admin" ON public.driver_token_transactions
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- ─── PARTE 4: market_update_schedule (admin only) ──────────
ALTER TABLE public.market_update_schedule ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mus_admin_only" ON public.market_update_schedule
  FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());
