-- M1 — ROOT CAUSE FIX: loop dispatch-engine (5M+ invocações).
-- Causa provada: (1) decideRedispatch caso "pendente sem oferta" reagendava a cada
-- 10s SEM TTL; (2) cada invocação externa criava nova cadeia self-sustaining (sem
-- dedup quando não há oferta ativa) → multiplicação; (3) bora_dispatch_maintenance
-- lia dispatch_max_total_seconds_with_drivers_online mas NUNCA o usava, só
-- cancelava com drivers online, e reinvocava o engine sem TTL.
-- Fix: TTL honrado em TODOS os caminhos + claim atómico anti-duplicação + cancel
-- centralizado com alerta admin e push cliente.
-- Par deste fix no Edge: dispatch-engine v57 (TTL hard stop + claim em decideRedispatch).

-- A) Colunas de controlo de dispatch (não-financeiras)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS dispatch_calling_since timestamptz;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS dispatch_next_retry_at timestamptz;

COMMENT ON COLUMN public.orders.dispatch_calling_since IS
  'Inicio (ou re-inicio) da fase callingDriver — ancora do TTL absoluto de dispatch (dispatch_auto_cancel_safety_seconds).';
COMMENT ON COLUMN public.orders.dispatch_next_retry_at IS
  'Claim da cadeia de retry do dispatch-engine — só a cadeia que consegue o UPDATE condicional agenda o próximo retry (anti-duplicação).';

-- B) Trigger: marca o início da fase callingDriver e faz reset dos contadores
CREATE OR REPLACE FUNCTION public._set_dispatch_calling_since()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.status = 'callingDriver')
     OR (TG_OP = 'UPDATE' AND NEW.status = 'callingDriver'
         AND OLD.status IS DISTINCT FROM 'callingDriver') THEN
    NEW.dispatch_calling_since          := now();
    NEW.dispatch_online_attempt_seconds := 0;
    NEW.dispatch_next_retry_at          := NULL;
    NEW.dispatch_last_tick_at           := NULL;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_set_dispatch_calling_since ON public.orders;
CREATE TRIGGER trg_set_dispatch_calling_since
  BEFORE INSERT OR UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._set_dispatch_calling_since();

-- C) Cancel centralizado: idempotente + alerta admin + push FCM cliente best-effort.
--    (in-app ao cliente vem do trigger trg_notify_on_order_cancel, já com guard M2)
CREATE OR REPLACE FUNCTION public.dispatch_cancel_expired_order(p_order_id text, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row          public.orders%ROWTYPE;
  v_supabase_url text;
  v_service_key  text;
BEGIN
  UPDATE public.orders
     SET status                  = 'cancelled',
         cancelled_at            = now(),
         cancellation_initiator  = 'system',
         cancel_reason           = p_reason,
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL,
         dispatch_next_retry_at  = NULL
   WHERE id = p_order_id
     AND status = 'callingDriver'
     AND assigned_driver_id IS NULL
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN false;  -- já atribuído/cancelado entretanto — no-op idempotente
  END IF;

  -- Alerta admin no painel (admin_notifications)
  BEGIN
    PERFORM public.notify_admin_event(
      'dispatch_ttl_auto_cancel', 'critical',
      format('Pedido #%s auto-cancelado por TTL de dispatch (%s)',
             substring(p_order_id, 1, 8), p_reason),
      'order', p_order_id,
      jsonb_build_object(
        'reason', p_reason,
        'calling_since', v_row.dispatch_calling_since,
        'online_attempt_seconds', v_row.dispatch_online_attempt_seconds,
        'payment_method', v_row.payment_method,
        'payment_status', v_row.payment_status),
      '/admin/orders/' || p_order_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[dispatch_cancel_expired_order] notify_admin_event failed: %', SQLERRM;
  END;

  -- Push FCM ao cliente (best-effort, nunca quebra a transação)
  BEGIN
    IF v_row.user_id IS NOT NULL THEN
      SELECT decrypted_secret INTO v_supabase_url
        FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
      SELECT decrypted_secret INTO v_service_key
        FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
      IF v_supabase_url IS NOT NULL AND v_service_key IS NOT NULL THEN
        PERFORM net.http_post(
          url     := v_supabase_url || '/functions/v1/notify-client',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key),
          body := jsonb_build_object(
            'clientId', v_row.user_id::text,
            'orderId',  p_order_id,
            'title',    'Pedido cancelado',
            'body',     'Não encontrámos estafeta disponível. O teu pedido foi cancelado e o reembolso está em curso se aplicável.',
            'kind',     'cancellation',
            'type',     'order_status'));
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[dispatch_cancel_expired_order] notify-client push failed: %', SQLERRM;
  END;

  RETURN true;
END;
$function$;

-- D) bora_dispatch_maintenance v2 — honra TODAS as settings em TODOS os caminhos
CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order             record;
  v_cancelled_count   int := 0;
  v_ttl_max_count     int := 0;
  v_ttl_safety_count  int := 0;
  v_drivers_online    int;
  v_jwt               text := public._dispatch_jwt();
  v_max_total_s       int;
  v_safety_s          int;
BEGIN
  SELECT (value::text)::int INTO v_max_total_s
    FROM public.platform_settings WHERE key = 'dispatch_max_total_seconds_with_drivers_online';
  v_max_total_s := COALESCE(v_max_total_s, 1200);

  SELECT (value::text)::int INTO v_safety_s
    FROM public.platform_settings WHERE key = 'dispatch_auto_cancel_safety_seconds';
  v_safety_s := COALESCE(v_safety_s, 1800);

  SELECT count(*) INTO v_drivers_online
    FROM public.drivers
    WHERE is_online = true
      AND last_heartbeat_at > NOW() - INTERVAL '90 seconds';

  -- 1) Pagamentos abandonados (inalterado da v1)
  WITH abandoned AS (
    UPDATE public.orders
       SET status         = 'cancelled',
           payment_status = 'failed',
           cancel_reason  = 'payment_abandoned'
     WHERE status = 'created' AND payment_status = 'pending'
       AND payment_method IN ('card', 'mbway')
       AND created_at < NOW() - INTERVAL '10 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_cancelled_count FROM abandoned;
  IF v_cancelled_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] auto-cancelled % abandoned payment(s)', v_cancelled_count;
  END IF;

  -- 2) Backfill defensivo: callingDriver sem âncora TTL (pedidos pré-migration)
  UPDATE public.orders
     SET dispatch_calling_since = NOW()
   WHERE status = 'callingDriver' AND dispatch_calling_since IS NULL;

  -- 3) Acumulação do tempo de tentativa COM drivers online (inalterado da v1)
  IF v_drivers_online > 0 THEN
    UPDATE public.orders
       SET dispatch_online_attempt_seconds =
             COALESCE(dispatch_online_attempt_seconds, 0)
             + LEAST(
                 EXTRACT(EPOCH FROM (NOW() - COALESCE(dispatch_last_tick_at, NOW())))::int,
                 180
               ),
           dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  ELSE
    UPDATE public.orders
       SET dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  END IF;

  -- 4) Limpeza de extensões de parceiro expiradas (inalterado da v1)
  UPDATE public.orders
     SET dispatch_partner_decision_at = NULL,
         dispatch_extended_until      = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND dispatch_extended_until IS NOT NULL
     AND dispatch_extended_until < NOW();

  -- 5) TTL 1 (CORRIGIDO — antes lido e nunca usado): máximo de tentativa ativa
  --    com drivers online → dispatch_max_total_seconds_with_drivers_online
  IF v_drivers_online > 0 THEN
    FOR v_order IN
      SELECT id FROM public.orders
       WHERE status = 'callingDriver'
         AND assigned_driver_id IS NULL
         AND COALESCE(dispatch_online_attempt_seconds, 0) >= v_max_total_s
    LOOP
      IF public.dispatch_cancel_expired_order(v_order.id, 'dispatch_max_total_with_drivers_exceeded') THEN
        v_ttl_max_count := v_ttl_max_count + 1;
      END IF;
    END LOOP;
    IF v_ttl_max_count > 0 THEN
      RAISE NOTICE '[dispatch_maintenance] TTL max_total auto-cancel % order(s) (>=%s s)',
        v_ttl_max_count, v_max_total_s;
    END IF;
  END IF;

  -- 6) TTL 2 (CORRIGIDO — antes só corria com drivers online): safety absoluto,
  --    COM OU SEM drivers online → dispatch_auto_cancel_safety_seconds
  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND dispatch_calling_since IS NOT NULL
       AND dispatch_calling_since < NOW() - make_interval(secs => v_safety_s)
  LOOP
    IF public.dispatch_cancel_expired_order(v_order.id, 'dispatch_safety_timeout') THEN
      v_ttl_safety_count := v_ttl_safety_count + 1;
    END IF;
  END LOOP;
  IF v_ttl_safety_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] TTL safety auto-cancel % order(s) (>=%s s em callingDriver)',
      v_ttl_safety_count, v_safety_s;
  END IF;

  -- 7) Rotação de ofertas expiradas (inalterado da v1)
  UPDATE public.orders
     SET tried_driver_ids        = array_append(
                                     COALESCE(tried_driver_ids, '{}'::text[]),
                                     current_driver_offer_id
                                   ),
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id IS NOT NULL
     AND driver_offer_expires_at IS NOT NULL
     AND driver_offer_expires_at < NOW();

  -- 8) Reinvocação do engine (CORRIGIDO — antes sem TTL e sem dedup de cadeias):
  --    só pedidos dentro dos TTLs E sem cadeia de retry ativa (claim morto >60s)
  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND current_driver_offer_id IS NULL
       AND (dispatch_extended_until IS NULL OR dispatch_extended_until > NOW())
       AND (dispatch_calling_since IS NULL
            OR dispatch_calling_since > NOW() - make_interval(secs => v_safety_s))
       AND COALESCE(dispatch_online_attempt_seconds, 0) < v_max_total_s
       AND (dispatch_next_retry_at IS NULL
            OR dispatch_next_retry_at < NOW() - INTERVAL '60 seconds')
  LOOP
    PERFORM net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body    := jsonb_build_object('orderId', v_order.id::text)
    );
  END LOOP;
END;
$function$;

-- E) Backfill one-shot (DB limpa hoje — esperado 0 rows)
UPDATE public.orders
   SET dispatch_calling_since = NOW()
 WHERE status = 'callingDriver' AND dispatch_calling_since IS NULL;
