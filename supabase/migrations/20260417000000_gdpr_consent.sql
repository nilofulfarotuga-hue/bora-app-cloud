-- ============================================================================
-- BORA — GDPR Consent (BR §20.1)
-- ============================================================================
-- PURPOSE:
--   Persist the moment the user accepted the Terms & Privacy Policy at signup.
--   Required for legal proof under GDPR (RGPD).
--
-- SCOPE:
--   Only adds columns. Never removes or modifies existing ones.
--   Consent for clients is stored in auth.users.raw_user_meta_data (written by
--   the Flutter client via supabase.auth.signUp data parameter) — no table
--   change needed for clients.
--   For drivers, the column lives on public.drivers because AuthStore upserts
--   directly after signUp.
-- ============================================================================

BEGIN;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS consent_accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS consent_version      TEXT;

COMMENT ON COLUMN public.drivers.consent_accepted_at IS
  'UTC timestamp at which the driver accepted Terms + Privacy Policy at signup. GDPR proof (BR §20.1).';

COMMENT ON COLUMN public.drivers.consent_version IS
  'Version identifier of the Terms/Privacy text the driver accepted. Bump when legal text changes.';

COMMIT;
