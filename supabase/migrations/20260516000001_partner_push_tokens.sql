-- Multi-device FCM token registry for partner accounts.
-- Replaces the single-token column restaurants.fcm_token approach with a
-- per-(partner_id, fcm_token) row keyed on auth.users(id), enabling a partner
-- to receive pushes on every signed-in device.

CREATE TABLE IF NOT EXISTS public.partner_push_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token    text NOT NULL,
  device_label text,
  platform     text,
  active       boolean NOT NULL DEFAULT true,
  fail_count   smallint NOT NULL DEFAULT 0,
  last_fail_at timestamptz,
  last_used_at timestamptz NOT NULL DEFAULT now(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (partner_id, fcm_token)
);

ALTER TABLE public.partner_push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY partner_push_tokens_own ON public.partner_push_tokens
  FOR ALL TO authenticated
  USING (partner_id = auth.uid())
  WITH CHECK (partner_id = auth.uid());

GRANT ALL ON public.partner_push_tokens TO authenticated;
GRANT ALL ON public.partner_push_tokens TO service_role;
