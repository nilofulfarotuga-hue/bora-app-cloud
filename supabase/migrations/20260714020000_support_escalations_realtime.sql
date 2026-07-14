-- Chat guiado (2026-07-14) — Realtime publication para support_escalations.
-- Sem isto, AdminSupportEscalationsScreen fica só com refresh manual: a
-- subscrição onPostgresChanges nunca dispara em INSERT/UPDATE.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='support_escalations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_escalations;
  END IF;
END $$;
