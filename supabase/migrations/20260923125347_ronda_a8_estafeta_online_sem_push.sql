-- =============================================================================
-- ronda-fecho-2026-09-22 · A8 — estafeta online sem token push
-- (a) RPC meu_estado_push(): a app do estafeta pergunta ao servidor se tem
--     aparelho registado (fcm_token legado, driver_push_tokens, provider_push_tokens)
--     e mostra o aviso "Sem notificações: não vais receber pedidos".
-- (b) Alerta ao admin: quando um estafeta passa a online sem nenhum token,
--     notify_admin_urgent_push (inbox + push + Telegram), no máximo uma vez por
--     6 horas por estafeta (drivers.push_alert_admin_at). Contas demo não alertam.
-- (c) A sugestão do Robot B de 17/09 ("Estafeta em linha sem token de
--     notificação push", 472d162d) é fechada como aplicada — o aviso na app e o
--     alerta ao admin são a resposta — com rasto em robot_audit_log.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.meu_estado_push()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_legacy boolean := false;
  v_driver_tokens int := 0;
  v_provider_tokens int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  SELECT (d.fcm_token IS NOT NULL AND length(d.fcm_token) > 0) INTO v_legacy
    FROM public.drivers d WHERE d.user_id = v_uid OR d.id = v_uid LIMIT 1;
  SELECT count(*) INTO v_driver_tokens FROM public.driver_push_tokens t
   WHERE t.user_id = v_uid AND t.active;
  SELECT count(*) INTO v_provider_tokens FROM public.provider_push_tokens t
   WHERE t.user_id = v_uid AND t.active;
  RETURN jsonb_build_object(
    'tem_token', COALESCE(v_legacy, false) OR v_driver_tokens > 0 OR v_provider_tokens > 0,
    'aparelhos', v_driver_tokens + v_provider_tokens + (CASE WHEN COALESCE(v_legacy, false) THEN 1 ELSE 0 END),
    'legacy', COALESCE(v_legacy, false),
    'verificado_em', now());
END;
$function$;
REVOKE ALL ON FUNCTION public.meu_estado_push() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.meu_estado_push() FROM anon;
GRANT EXECUTE ON FUNCTION public.meu_estado_push() TO authenticated;

ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS push_alert_admin_at timestamptz;

CREATE OR REPLACE FUNCTION public.fn_driver_online_sem_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := COALESCE(NEW.user_id, NEW.id);
  v_tem boolean;
BEGIN
  IF COALESCE(NEW.is_online, false) AND NOT COALESCE(OLD.is_online, false) THEN
    v_tem := (NEW.fcm_token IS NOT NULL AND length(NEW.fcm_token) > 0)
          OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = v_uid AND t.active)
          OR EXISTS (SELECT 1 FROM public.provider_push_tokens t WHERE t.user_id = v_uid AND t.active);
    IF NOT v_tem
       AND (NEW.push_alert_admin_at IS NULL OR NEW.push_alert_admin_at < now() - interval '6 hours')
       AND NOT COALESCE(public.is_demo_user(v_uid), false) THEN
      BEGIN
        PERFORM public.notify_admin_urgent_push(
          'driver_online_sem_push',
          E'📵 ' || COALESCE(NULLIF(trim(NEW.name), ''), 'Estafeta') || ' ligou-se sem notificações\n'
            || 'Não vai receber pedidos até ativar as notificações na app'
            || COALESCE(' · ' || NULLIF(trim(NEW.phone), ''), '') || '.',
          'driver', v_uid::text,
          jsonb_build_object('driver_id', NEW.id, 'user_id', NEW.user_id, 'name', NEW.name,
                             'phone', NEW.phone, 'last_platform', NEW.last_platform),
          '/admin/pendencias');
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'fn_driver_online_sem_push: alerta falhou (%)', sqlerrm;
      END;
      NEW.push_alert_admin_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_driver_online_sem_push ON public.drivers;
CREATE TRIGGER trg_driver_online_sem_push
BEFORE UPDATE OF is_online ON public.drivers
FOR EACH ROW EXECUTE FUNCTION public.fn_driver_online_sem_push();

-- (c) fechar a sugestão do Robot B de 17/09
UPDATE public.robot_suggestions
   SET status = 'aplicada', reviewed_at = now()
 WHERE id = '472d162d-d4bd-4e28-85fc-106c4c40f645' AND status = 'nova';

INSERT INTO public.robot_audit_log (suggestion_id, operation, params, result, executed_by)
SELECT '472d162d-d4bd-4e28-85fc-106c4c40f645', 'fechar_sugestao',
       jsonb_build_object('motivo', 'ronda-fecho-2026-09-22 A8: aviso na app do estafeta (meu_estado_push) + alerta ao admin (trg_driver_online_sem_push) + linha em Pendências de operação'),
       jsonb_build_object('status', 'aplicada'),
       'ronda-fecho-2026-09-22'
 WHERE NOT EXISTS (SELECT 1 FROM public.robot_audit_log
                    WHERE suggestion_id = '472d162d-d4bd-4e28-85fc-106c4c40f645' AND operation = 'fechar_sugestao');
