-- F3 — SISTEMA DE FECHO SEMANAL (camada de comunicação pós-settlements).
-- Aplicado a produção via MCP 2026-08-17; este ficheiro é o registo reprodutível.
-- NÃO muda cobranças: lê settlements já fechados e comunica. Estado final consolidado.

-- ── F3.1: fundação ──────────────────────────────────────────────────────────
ALTER TABLE public.cleaners ADD COLUMN IF NOT EXISTS mbway_phone text;
ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS mbway_phone text;
ALTER TABLE public.service_providers ADD COLUMN IF NOT EXISTS mbway_phone text;

CREATE TABLE IF NOT EXISTS public.weekly_digest_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start_at timestamptz NOT NULL,
  week_end_at timestamptz NOT NULL,
  subject_type text NOT NULL,          -- driver | cleaner | provider | partner
  subject_id text NOT NULL,
  subject_name text,
  subject_email text,
  subject_phone text,
  net_cents integer NOT NULL DEFAULT 0, -- SIGNED: positivo=Bora paga, negativo=deve ao Bora
  direction text NOT NULL DEFAULT 'zero', -- bora_pays | owes_bora | zero
  breakdown jsonb NOT NULL DEFAULT '[]'::jsonb,
  email_html text,
  email_to text,
  email_status text NOT NULL DEFAULT 'pending', -- sent | aguarda_dominio | skipped | failed | pending
  email_sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (week_start_at, subject_type, subject_id)
);
ALTER TABLE public.weekly_digest_log ENABLE ROW LEVEL SECURITY;
DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='weekly_digest_log' AND policyname='weekly_digest_log_admin_all') THEN
    CREATE POLICY weekly_digest_log_admin_all ON public.weekly_digest_log
      FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  END IF;
END $do$;

INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('bora_mbway_phone', '""'::jsonb, 'Numero MB Way do Bora para cobrancas do fecho semanal (vazio = "entraremos em contacto")', 'fecho_semanal'),
  ('weekly_digest_emails_enabled', 'false'::jsonb, 'Liga o envio EXTERNO dos emails do fecho semanal (so quando o dominio estiver verificado no Resend)', 'fecho_semanal')
ON CONFLICT (key) DO NOTHING;

-- ── F3.2: compilador (ver definição completa aplicada via MCP) ──────────────
-- public.weekly_closeout_compile(p_week_start date) — lê os 4 settlements da
-- semana, normaliza net SIGNED, breakdown por vertical, upsert em weekly_digest_log,
-- devolve resumo {to_pay, to_receive, zero_count}. REVOKE de public/anon/authenticated.

-- ── F3.4: cron (2.ª 09:00 UTC, depois de todos os settlements) ──────────────
-- SELECT cron.schedule('weekly-closeout-digest', '0 9 * * 1', <pg_net POST à EF>);

-- ── F3.5a: RPCs admin (todas is_admin) ──────────────────────────────────────
-- admin_weekly_closeout_list(date) — lista + join estado pago + settings.
-- admin_mark_settlement_paid(text,text,date) — muda ESTADO do settlement + audit.
-- admin_update_weekly_closeout_settings(text,boolean) — MB Way + toggle.
-- admin_resend_weekly_digest(date) — re-invoca a EF.

-- NOTA: as definições PL/pgSQL completas (compilador + 4 RPCs admin) foram aplicadas
-- via MCP apply_migration (migrations f32_compiler, f34_cron, f35_admin_rpcs,
-- f35_list_add_settings). A EF `weekly-closeout-digest` vive em
-- supabase/functions/weekly-closeout-digest/index.ts. Verdade corrente = produção.
