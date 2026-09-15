-- Fix PGRST203: remove old 11-param overload of driver_register_or_update.
-- PostgREST could not choose between the 11-param and 14-param versions,
-- so the driver signup RPC failed silently ("preso depois do IBAN").
-- Keep ONLY the 14-param version (created in 20260527100000). Idempotent.
-- Already applied to remote via MCP on 2026-05-31; this file syncs the repo
-- so `supabase db reset` / CI do not recreate the duplicate.
DROP FUNCTION IF EXISTS public.driver_register_or_update(
  text, text, text, text, text, text, text, text, text, text, text
);
