-- BLOCO 3 — 2026-09-07 — comprovativo automatico
-- Quando o Danilo marca "pago" ou "recebido", a outra pessoa tem de saber sem
-- ele escrever nada. Aqui fica a FILA (uma linha por mudanca de estado) e o
-- gatilho que a enche. Quem envia e a Edge Function `settlement-receipt`.
--
-- Idempotente por desenho: a chave unica (tipo, pessoa, semana, especie) faz
-- com que a mesma mudanca de estado nunca gere dois comprovativos.
--
-- Nota de escrita: sem instrucoes destrutivas nesta migration, de proposito.
-- A Trava recusa-as sobre tabelas de dinheiro e tem razao; usa-se a forma
-- "CREATE OR REPLACE TRIGGER", que substitui sem remover.

CREATE TABLE IF NOT EXISTS public.settlement_receipts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type  text NOT NULL,
  subject_id    text NOT NULL,
  week_start_at timestamptz NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('paid','received')),
  subject_name  text,
  to_email      text,
  amount_cents  int  NOT NULL DEFAULT 0,
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','sent','failed','skipped')),
  attempts      int  NOT NULL DEFAULT 0,
  last_error    text,
  html          text,
  sent_at       timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT settlement_receipts_uniq UNIQUE (subject_type, subject_id, week_start_at, kind)
);

CREATE INDEX IF NOT EXISTS settlement_receipts_pendentes_idx
  ON public.settlement_receipts (status, attempts)
  WHERE status IN ('pending','failed');

ALTER TABLE public.settlement_receipts ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='settlement_receipts'
      AND policyname='settlement_receipts_admin_le'
  ) THEN
    CREATE POLICY settlement_receipts_admin_le ON public.settlement_receipts
      FOR SELECT TO authenticated USING (public.is_admin());
  END IF;
END $pol$;

-- Enche a fila. Corre depois do UPDATE e NUNCA pode partir o UPDATE: se algo
-- correr mal aqui, regista-se o erro (nao se engole em silencio — PADRAO 6).
CREATE OR REPLACE FUNCTION public._settlement_receipt_enqueue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row    jsonb;
  v_type   text := TG_ARGV[0];
  v_idcol  text := TG_ARGV[1];
  v_sid    text;
  v_ws     timestamptz;
  v_name   text;
  v_email  text;
  v_cents  int := 0;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('paid','received') THEN RETURN NEW; END IF;

  v_row := to_jsonb(NEW);
  v_sid := v_row ->> v_idcol;
  v_ws  := (v_row ->> 'week_start_at')::timestamptz;

  SELECT w.subject_name, w.subject_email, w.net_cents
    INTO v_name, v_email, v_cents
  FROM public.weekly_digest_log w
  WHERE w.subject_type = v_type
    AND w.subject_id = v_sid
    AND w.week_start_at::date = v_ws::date
  LIMIT 1;

  INSERT INTO public.settlement_receipts
    (subject_type, subject_id, week_start_at, kind, subject_name, to_email, amount_cents)
  VALUES (v_type, v_sid, v_ws, NEW.status, v_name, v_email, COALESCE(v_cents, 0))
  ON CONFLICT ON CONSTRAINT settlement_receipts_uniq DO NOTHING;

  -- Acorda a Edge para despachar a fila ja. Se falhar, a tarefa agendada de 15
  -- em 15 minutos apanha a linha que ficou por enviar.
  BEGIN
    PERFORM net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url')
             || '/functions/v1/settlement-receipt',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
        'Content-Type', 'application/json'),
      body := jsonb_build_object('trigger', 'status_change')
    );
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('settlement_receipt_post_falhou', v_type, v_sid,
            jsonb_build_object('erro', SQLERRM, 'week_start', v_ws));
  END;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
  VALUES ('settlement_receipt_enqueue_falhou', COALESCE(v_type,'?'), COALESCE(v_sid,'?'),
          jsonb_build_object('erro', SQLERRM));
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_receipt_driver AFTER UPDATE OF status ON public.driver_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._settlement_receipt_enqueue('driver','driver_id');
CREATE OR REPLACE TRIGGER trg_receipt_partner AFTER UPDATE OF status ON public.partner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._settlement_receipt_enqueue('partner','partner_id');
CREATE OR REPLACE TRIGGER trg_receipt_cleaner AFTER UPDATE OF status ON public.cleaner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._settlement_receipt_enqueue('cleaner','cleaner_id');
CREATE OR REPLACE TRIGGER trg_receipt_provider AFTER UPDATE OF status ON public.appointment_payouts
  FOR EACH ROW EXECUTE FUNCTION public._settlement_receipt_enqueue('provider','provider_id');
CREATE OR REPLACE TRIGGER trg_receipt_washer AFTER UPDATE OF status ON public.washer_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._settlement_receipt_enqueue('washer','washer_id');

-- Nova tentativa das que ficaram por enviar (a Edge respeita o tecto de 6).
CREATE OR REPLACE FUNCTION public._settlement_receipts_retry()
 RETURNS int
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n int;
BEGIN
  SELECT count(*)::int INTO v_n FROM public.settlement_receipts
   WHERE status IN ('pending','failed') AND attempts < 6;
  IF v_n = 0 THEN RETURN 0; END IF;

  PERFORM net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url')
           || '/functions/v1/settlement-receipt',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
      'Content-Type', 'application/json'),
    body := jsonb_build_object('trigger', 'retry')
  );
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION public._settlement_receipt_enqueue() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._settlement_receipts_retry() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._settlement_receipts_retry() TO service_role;;
