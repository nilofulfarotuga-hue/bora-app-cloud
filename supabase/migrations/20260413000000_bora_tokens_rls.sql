-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: RLS for bora_tokens
-- Created:   2026-04-13
--
-- Security model:
--   • All writes go through SECURITY DEFINER functions (add_tokens,
--     consume_tokens, fn_award_tokens_on_delivery trigger) — these run as the
--     function owner and bypass RLS entirely.  No INSERT/UPDATE/DELETE policies
--     are needed; direct client mutations are implicitly denied.
--   • SELECT is restricted to the token owner only (user_id = auth.uid()).
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── 1. Enable RLS ───────────────────────────────────────────────────────────

ALTER TABLE bora_tokens ENABLE ROW LEVEL SECURITY;

-- Revoke direct table access from the default roles so that only
-- SECURITY DEFINER functions (which bypass RLS) can write.
REVOKE INSERT, UPDATE, DELETE ON bora_tokens FROM anon, authenticated;

-- ─── 2. SELECT policy — users see only their own tokens ──────────────────────

DROP POLICY IF EXISTS "tokens_select_own" ON bora_tokens;

CREATE POLICY "tokens_select_own"
  ON bora_tokens
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- ─── 3. Sanity notes ─────────────────────────────────────────────────────────
--
-- No INSERT policy   → direct inserts from the client are denied.
--                      add_tokens() is SECURITY DEFINER — it bypasses RLS.
--
-- No UPDATE policy   → direct updates from the client are denied.
--                      consume_tokens() is SECURITY DEFINER — it bypasses RLS.
--
-- No DELETE policy   → rows are never hard-deleted; expired tokens are filtered
--                      in queries via  expires_at > now().
--
-- Service-role key   → bypasses RLS entirely (used only server-side / Edge Fns).
-- ─────────────────────────────────────────────────────────────────────────────
