-- ============================================================================
-- BORA — FASE 2 · PARTE B · M1
-- ============================================================================
-- Move the admin gate from `user_metadata.bora_role` to
-- `app_metadata.role` (which is already populated for the admin user
-- and is immutable by client-side code — only writable via service_role).
--
-- This fixes the regression introduced in Phase-1 where setting
-- `bora_role='admin'` on the admin user broke `loginClientAsync`,
-- `loginDriverAsync` and `loginPartnerAsync` (each rejects roles other
-- than its own). The admin can now log in normally as a client.
--
-- Plan: .claude/.ai/reports/2026-04-28-fase2B-plan-S2.md §1
-- Pre-state captured in: same report (PRE-M1 backup).
-- ============================================================================

BEGIN;

-- 1. Revert bora_role for the admin user → 'client' (so loginClientAsync
-- accepts the login). Other keys preserved.
UPDATE auth.users
SET raw_user_meta_data =
  COALESCE(raw_user_meta_data, '{}'::jsonb)
  || '{"bora_role":"client"}'::jsonb
WHERE email = 'nilofulfarotuga@gmail.com';

-- 2. Belt-and-braces: ensure raw_app_meta_data.role='admin' is intact.
UPDATE auth.users
SET raw_app_meta_data =
  COALESCE(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"admin"}'::jsonb
WHERE email = 'nilofulfarotuga@gmail.com';

-- 3. Replace the Phase-1 trigger to protect raw_app_meta_data.role.
-- raw_app_meta_data is normally only writable by service_role, but
-- this is defense-in-depth in case any future migration merges metadata
-- wholesale.
DROP TRIGGER IF EXISTS trg_protect_admin_bora_role ON auth.users;
DROP FUNCTION IF EXISTS public.protect_admin_bora_role();

CREATE OR REPLACE FUNCTION public.protect_admin_app_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_old_role TEXT;
  v_new_role TEXT;
  v_email    TEXT;
BEGIN
  v_email := COALESCE(OLD.email, NEW.email);
  IF v_email <> 'nilofulfarotuga@gmail.com' THEN
    RETURN NEW;
  END IF;

  v_old_role := OLD.raw_app_meta_data ->> 'role';
  v_new_role := NEW.raw_app_meta_data ->> 'role';

  IF v_old_role = 'admin' AND COALESCE(v_new_role, '') <> 'admin' THEN
    NEW.raw_app_meta_data :=
      COALESCE(NEW.raw_app_meta_data, '{}'::jsonb)
      || '{"role":"admin"}'::jsonb;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_admin_app_role ON auth.users;
CREATE TRIGGER trg_protect_admin_app_role
  BEFORE UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_admin_app_role();

COMMENT ON FUNCTION public.protect_admin_app_role() IS
  'Phase-2-B replacement of protect_admin_bora_role: protects raw_app_meta_data.role=admin instead of user_metadata.bora_role.';

COMMIT;
