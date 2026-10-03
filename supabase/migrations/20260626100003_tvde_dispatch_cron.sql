-- ============================================================================
-- BORA MOTORISTA (TVDE) — FASE 2 · pg_cron sweep (timeout SERVER-SIDE)
-- ============================================================================
-- Expira ofertas vencidas e passa ao próximo motorista a cada 15s, independente
-- do app do motorista estar aberto. Isolado do dispatch do delivery.
-- ============================================================================

DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('tvde_dispatch_sweep');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;

SELECT cron.schedule('tvde_dispatch_sweep', '15 seconds', $$SELECT public.tvde_dispatch_sweep();$$);
