-- ============================================================================
-- BORA — Restrict v_cron_dispatch_health to admin (FASE 5 · BUG 5 · anomalia #5)
-- ============================================================================
-- BUG 5 deploy momento criou v_cron_dispatch_health com GRANT SELECT a
-- `authenticated` — qualquer utilizador autenticado podia ler metadados
-- operacionais (timestamps de falhas, contagens). Anomalia #5 do relatório
-- de fix.
--
-- FIX: redefinir a view para incluir gate JWT no WHERE clause, espelhando
-- o pattern de admin_audit_log (auth.jwt() -> app_metadata ->> role = 'admin').
-- Como views herdam permissões da underlying table (cron.job_run_details, sem
-- RLS), filtramos as rows directamente na view: admins vêem dados reais;
-- não-admins vêem aggregates zero (0/NULL — sem erro, sem leak).
--
-- Caller flows preservados:
--   - service_role JWT → auth.role()='service_role' → vê dados (Edge Functions)
--   - admin JWT (app_metadata.role='admin') → vê dados
--   - utilizador autenticado normal → 0 rows → aggregates zero/NULL
--   - anon → REVOKE explícito → erro de permissão
--
-- Pattern reference: 20260428000005_admin_gate_app_metadata.sql (admin_audit_log)
-- ============================================================================

-- Re-create view with admin gate inside WHERE clause
CREATE OR REPLACE VIEW public.v_cron_dispatch_health AS
SELECT
  COUNT(*) FILTER (WHERE start_time > now() - interval '24 hours') AS runs_24h,
  COUNT(*) FILTER (WHERE start_time > now() - interval '24 hours' AND status = 'succeeded') AS success_24h,
  COUNT(*) FILTER (WHERE start_time > now() - interval '24 hours' AND status = 'failed') AS failed_24h,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE start_time > now() - interval '24 hours' AND status = 'succeeded')
    / NULLIF(COUNT(*) FILTER (WHERE start_time > now() - interval '24 hours'), 0),
    2
  ) AS success_rate_pct,
  MAX(start_time) FILTER (WHERE status = 'failed') AS last_failure_at,
  MAX(start_time) FILTER (WHERE status = 'succeeded') AS last_success_at
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'bora-dispatch-maintenance' LIMIT 1)
  -- Admin gate: only admin JWT or service_role sees real aggregates.
  -- Non-admin authenticated callers get 0/NULL aggregates (rows filtered before COUNT).
  AND (
    -- Admin via JWT (Flutter / PostgREST authenticated com app_metadata.role='admin')
    COALESCE((auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin'
    -- Service role (Edge Functions) ou postgres internal (cron, MCP, manual)
    -- pg_has_role retorna TRUE para postgres+service_role, FALSE para authenticated/anon
    OR pg_has_role(current_user, 'service_role', 'USAGE')
  );

COMMENT ON VIEW public.v_cron_dispatch_health IS
  'Health summary of bora-dispatch-maintenance cron. Admin-gated: non-admin authenticated callers see zero aggregates (rows filtered by JWT role check inside WHERE). Threshold: alert if success_rate_pct < 90.';

-- Tighten grants: revoke from public/anon, keep authenticated+service_role
-- (the WHERE clause inside the view filters by role; non-admin sees empty)
REVOKE ALL ON public.v_cron_dispatch_health FROM PUBLIC;
REVOKE ALL ON public.v_cron_dispatch_health FROM anon;
GRANT SELECT ON public.v_cron_dispatch_health TO authenticated;
GRANT SELECT ON public.v_cron_dispatch_health TO service_role;
