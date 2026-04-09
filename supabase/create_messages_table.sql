-- =============================================================================
-- BORA APP — Messages table migration
-- Paste this in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to run multiple times (fully idempotent).
-- =============================================================================

-- 1. Create the table --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
  id          TEXT        PRIMARY KEY,
  order_id    TEXT        NOT NULL,
  sender_id   TEXT        NOT NULL,
  sender_role TEXT        NOT NULL DEFAULT 'client',
  type        TEXT        NOT NULL DEFAULT 'text',
  content     TEXT        NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Ensure all columns exist (idempotent for existing tables) ---------------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS sender_role TEXT NOT NULL DEFAULT 'client',
  ADD COLUMN IF NOT EXISTS type        TEXT NOT NULL DEFAULT 'text';

-- 3. Row Level Security -------------------------------------------------------
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_all_authenticated" ON public.messages;

-- Any authenticated session (including anonymous sign-in) can read/write.
-- The app uses signInAnonymously() so auth.uid() is always non-null.
CREATE POLICY "messages_all_authenticated"
  ON public.messages
  FOR ALL
  USING      (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- 4. Realtime -----------------------------------------------------------------
-- Allows ChatStore to receive INSERT events via .onPostgresChanges().
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

-- 5. Quick verification -------------------------------------------------------
-- After running, confirm with:
--   SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'messages';
