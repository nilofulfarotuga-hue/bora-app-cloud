-- ═══════════════════════════════════════════════════════════
-- BLOCO 2c — 4 views: SECURITY DEFINER → SECURITY INVOKER
-- Data: 2026-05-08 / Sessão 7-SEC-1
-- Razão: views em DEFINER bypassam RLS das tabelas subjacentes,
--        permitindo qualquer authenticated user ver IBANs/earnings
--        de todos drivers + totais financeiros.
-- ═══════════════════════════════════════════════════════════

ALTER VIEW public.v_cron_dispatch_health SET (security_invoker = true);
ALTER VIEW public.v_driver_withdrawals SET (security_invoker = true);
ALTER VIEW public.v_driver_weekly_earnings SET (security_invoker = true);
ALTER VIEW public.v_ledger_reconciliation SET (security_invoker = true);
