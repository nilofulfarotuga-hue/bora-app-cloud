-- F8 (MISSAO TOTAL 2026-08-15): RECONCILIADOR DE PAGAMENTOS.
-- Tabela de achados + wrapper + cron diario 05:45 UTC.
-- APLICADAS em producao a 2026-08-16 (payments_reconciler_table_f8 +
-- payments_reconciler_cron_f8). Kill switch: payments_reconciler_enabled.
-- PROVA E2E: 1a corrida real achou refund_prometido_sem_refund (corrida
-- e3a6cc36, pre-v9) e o alerta admin+Telegram saiu (alerted:true).

CREATE TABLE IF NOT EXISTS public.payment_reconciliation_findings (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_at       timestamptz NOT NULL DEFAULT now(),
  kind         text NOT NULL,
  severity     text NOT NULL DEFAULT 'warn',
  entity_type  text,
  entity_id    text,
  pi_id        text,
  amount_cents integer,
  details      jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolved_at  timestamptz,
  UNIQUE (kind, pi_id, entity_id)
);

ALTER TABLE public.payment_reconciliation_findings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS recon_admin_read ON public.payment_reconciliation_findings;
CREATE POLICY recon_admin_read ON public.payment_reconciliation_findings
  FOR SELECT TO authenticated USING (public.is_admin());

INSERT INTO public.platform_settings (key, value, category)
VALUES ('payments_reconciler_enabled', 'true'::jsonb, 'automation')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.run_payments_reconciler()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_url text; v_key text; v_req bigint;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE WARNING '[run_payments_reconciler] vault secrets em falta';
    RETURN NULL;
  END IF;
  SELECT net.http_post(
    url := v_url || '/functions/v1/payments-reconciler',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  ) INTO v_req;
  RETURN v_req;
END $function$;

REVOKE ALL ON FUNCTION public.run_payments_reconciler() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.run_payments_reconciler() FROM anon;
REVOKE ALL ON FUNCTION public.run_payments_reconciler() FROM authenticated;

SELECT cron.schedule(
  'payments-reconciler-daily',
  '45 5 * * *',
  'SELECT public.run_payments_reconciler();'
);
