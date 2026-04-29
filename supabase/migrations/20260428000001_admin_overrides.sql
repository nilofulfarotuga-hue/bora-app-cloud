-- ============================================================================
-- BORA — Admin overrides (Fase 1 da auditoria)
-- ============================================================================
-- Resolve duas coisas numa única migration:
--
-- 1. BUG 4 — toggle "activar parceiro" no painel admin estava partido porque
--    o código tentava actualizar `restaurants.is_active`, coluna inexistente.
--    Adoptámos a Opção A do diagnóstico: nova coluna `is_active_admin` com
--    semântica de override administrativo (default `true` → preserva
--    comportamento actual).
--
-- 2. `bora_role='admin'` do user `nilofulfarotuga@gmail.com` foi sobrescrito
--    por um signup posterior do app cliente (passou para `'client'`). Repomos
--    o role e instalamos um trigger BEFORE UPDATE em `auth.users` que protege
--    contra futuras sobreposições.
--
-- Relatório: .claude/.ai/reports/2026-04-28-bug4-partner-toggle-diagnosis.md
-- ============================================================================

BEGIN;

-- ── 1. is_active_admin em restaurants ──────────────────────────────────────
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS is_active_admin BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.restaurants.is_active_admin IS
  'Override administrativo. Se false, admin suspendeu este parceiro. Default true preserva comportamento. Distingue-se de is_online (toggle do próprio parceiro).';

CREATE INDEX IF NOT EXISTS idx_restaurants_is_active_admin
  ON public.restaurants (is_active_admin)
  WHERE is_active_admin = false;
-- Index parcial: típico há poucos parceiros suspensos, este é o caso a
-- consultar (admin a rever suspensos).

-- ── 2. Repor bora_role='admin' para o admin ────────────────────────────────
UPDATE auth.users
SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                        || '{"bora_role":"admin"}'::jsonb
WHERE email = 'nilofulfarotuga@gmail.com';

-- ── 3. Trigger anti-overwrite em auth.users ────────────────────────────────
-- Se um update tentar mudar o `bora_role` do admin de `admin` para outra
-- coisa (ou apagar), o trigger restaura `admin` no NEW antes de gravar.
CREATE OR REPLACE FUNCTION public.protect_admin_bora_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_old_role TEXT;
  v_new_role TEXT;
  v_old_email TEXT;
BEGIN
  -- Lock-list de emails admin protegidos. Mantém-se pequeno e
  -- explícito; novos admins requerem migration.
  v_old_email := COALESCE(OLD.email, NEW.email);
  IF v_old_email <> 'nilofulfarotuga@gmail.com' THEN
    RETURN NEW;
  END IF;

  v_old_role := OLD.raw_user_meta_data ->> 'bora_role';
  v_new_role := NEW.raw_user_meta_data ->> 'bora_role';

  -- Se o OLD já era admin e o NEW está a degradar (NULL ou outro role),
  -- repõe admin sem perder o resto do metadata novo.
  IF v_old_role = 'admin' AND COALESCE(v_new_role, '') <> 'admin' THEN
    NEW.raw_user_meta_data :=
      COALESCE(NEW.raw_user_meta_data, '{}'::jsonb)
      || '{"bora_role":"admin"}'::jsonb;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_admin_bora_role ON auth.users;
CREATE TRIGGER trg_protect_admin_bora_role
  BEFORE UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_admin_bora_role();

COMMENT ON FUNCTION public.protect_admin_bora_role() IS
  'BEFORE UPDATE on auth.users. If the admin user has bora_role=admin and an update would degrade it, the role is restored. Lock-list of protected emails is hardcoded and explicit.';

COMMIT;
