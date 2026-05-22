-- Sessão 2026-05-22 — Fixes críticos dispatch + reject
--
-- Bug 1: invoke_dispatch_engine() tinha URL placeholder 'SEU_PROJECT_REF'
--        em vez do project ref real. Qualquer chamada (incluindo triggers
--        on_order_calling_driver / on_order_insert_calling_driver) falhava
--        silenciosamente. Agora aponta para o project correcto + suporta
--        argumento opcional p_order_id para invocações pontuais.
--
-- Bug 2: RPC driver_reject_offer NÃO EXISTIA. main.dart (CallKit reject) +
--        order_store (UI reject) chamavam esta RPC mas devolvia "function
--        does not exist", silenciado por catch. Sem isto, ao rejeitar:
--          - current_driver_offer_id não era limpo
--          - driver não era adicionado a tried_driver_ids
--          - dispatch-engine NÃO era invocado para redispatch
--        Resultado: pedido ficava preso até timeout de 40s.
--
-- Cycle A→A com 1 driver: para funcionar correctamente, é OBRIGATÓRIO
-- adicionar o driver a tried_driver_ids no reject. O dispatch-engine
-- detecta "all eligible online drivers tried → cycle reset" e re-oferece.
-- Sem o add a tried_driver_ids, o reset nunca dispara e o offer fica vazio.

-- ───────────────────────────────────────────────────────────────────────────
-- Fix 1: invoke_dispatch_engine
-- ───────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.invoke_dispatch_engine();

CREATE OR REPLACE FUNCTION public.invoke_dispatch_engine(p_order_id text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'extensions'
AS $$
DECLARE
  v_jwt text := public._dispatch_jwt();
  v_body jsonb;
BEGIN
  v_body := CASE
    WHEN p_order_id IS NULL THEN '{}'::jsonb
    ELSE jsonb_build_object('orderId', p_order_id)
  END;
  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_jwt
    ),
    body    := v_body
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.invoke_dispatch_engine(text) TO authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- Fix 2: driver_reject_offer
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.driver_reject_offer(p_order_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_driver_id text;
  v_updated int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;
  v_driver_id := v_uid::text;

  -- Atomically: clear offer + add this driver to tried_driver_ids,
  -- but only if THIS driver still holds the offer (prevents double-reject
  -- race where another driver already accepted).
  UPDATE public.orders
     SET current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL,
         tried_driver_ids = CASE
           WHEN v_driver_id = ANY(COALESCE(tried_driver_ids, '{}'::text[]))
             THEN tried_driver_ids
           ELSE array_append(COALESCE(tried_driver_ids, '{}'::text[]), v_driver_id)
         END,
         dispatch_last_tick_at = NOW()
   WHERE id = p_order_id
     AND status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id = v_driver_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_offer_held');
  END IF;

  -- Wake dispatch-engine immediately so the next driver (or same driver
  -- via cycle reset when alone) gets the offer.
  PERFORM public.invoke_dispatch_engine(p_order_id);

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_reject_offer(text) TO authenticated;
