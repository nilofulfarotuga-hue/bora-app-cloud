-- 2026-11-09 — missão pendencias-2026-11-09, Bloco B — o comprovativo diz o meio certo.
--
-- Porque existe: o comprovativo semanal de acerto dizia sempre "Enviado por MB Way".
-- A 09/11 o da Boom! Burger saiu assim, mas o acerto foi pago por transferência bancária
-- (payment_reference = 'Transferência bancária 09/11/2026'). A fila settlement_receipts não
-- guardava o meio; a Edge settlement-receipt inventava-o.
--
-- O que muda:
--   1. settlement_receipts ganha a coluna payment_reference (texto tal como o painel o gravou
--      no acerto). A Edge lê daí o meio ("transferência bancária", "MB Way para <número>",
--      ...); sem meio claro escreve só "Pagamento efetuado".
--   2. _settlement_receipt_enqueue (gatilho AFTER UPDATE OF status nas 5 tabelas de acerto:
--      driver_, partner_, cleaner_, washer_weekly_settlements e appointment_payouts) passa a
--      copiar NEW.payment_reference para a fila. Parte da definição em produção a 09/11/2026
--      (igual à de 20260907000353); só se acrescentam v_ref e a coluna no INSERT.
--
-- Não muda nenhum valor cobrado nem pago: é só o texto do meio no comprovativo.
-- Idempotente: ADD COLUMN IF NOT EXISTS e CREATE OR REPLACE. Não mexe em linhas existentes
-- (a 09/11 a fila tinha 0 linhas por enviar: 32 sent, 1 skipped), por isso não há backup.

ALTER TABLE public.settlement_receipts
  ADD COLUMN IF NOT EXISTS payment_reference text;

COMMENT ON COLUMN public.settlement_receipts.payment_reference IS
  'Cópia do payment_reference do acerto no momento em que passou a paid/received. '
  'A Edge settlement-receipt tira daqui o meio do comprovativo; sem meio claro diz só "Pagamento efetuado".';

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
  v_ref    text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('paid','received') THEN RETURN NEW; END IF;

  v_row := to_jsonb(NEW);
  v_sid := v_row ->> v_idcol;
  v_ws  := (v_row ->> 'week_start_at')::timestamptz;
  -- 09/11/2026: o meio escolhido no painel vem no payment_reference do acerto (as 5 tabelas
  -- têm a coluna). Copia-se tal e qual; quem o lê é a Edge.
  v_ref := NULLIF(btrim(v_row ->> 'payment_reference'), '');

  SELECT w.subject_name, w.subject_email, w.net_cents
    INTO v_name, v_email, v_cents
  FROM public.weekly_digest_log w
  WHERE w.subject_type = v_type
    AND w.subject_id = v_sid
    AND w.week_start_at::date = v_ws::date
  LIMIT 1;

  INSERT INTO public.settlement_receipts
    (subject_type, subject_id, week_start_at, kind, subject_name, to_email, amount_cents, payment_reference)
  VALUES (v_type, v_sid, v_ws, NEW.status, v_name, v_email, COALESCE(v_cents, 0), v_ref)
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

-- Função de gatilho: ninguém a chama à mão (como em 20260907000353).
REVOKE ALL ON FUNCTION public._settlement_receipt_enqueue() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._settlement_receipt_enqueue() FROM anon, authenticated;
