-- [09/10/2026 · missão fecho-total-2026-10-09 · gaveta staged_fecho_mensal_20260929 sql_2]
-- A partir de platform_settings.estafeta_fiscal_prazo (15/10/2026) o estafeta sem NIF válido +
-- atividade aberta (driver_fiscal_status) não aceita entregas no servidor. A app já bloqueia.
-- Devolve {ok:false, error:"estafeta_sem_nif_atividade"} no mesmo estilo dos outros erros;
-- a repetição idempotente de quem já aceitou continua a dar ok. Contas demo ficam de fora.
-- Provado em transação desfeita antes de aplicar (5 cenários, ver
-- .claude/.ai/provas/fecho-total-2026-10-09/). md5 da definição no ar: 8cabacd260f8ddcc0de18f19b8192466.
CREATE OR REPLACE FUNCTION public.driver_accept_offer(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_rows integer;
  v_fiscal_bloqueado boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;
  -- FECHO MENSAL (staged_fecho_mensal_20260929, aplicado a 09/10/2026): a partir do prazo
  -- platform_settings.estafeta_fiscal_prazo (15/10/2026) o estafeta sem NIF válido + atividade
  -- aberta não aceita entregas. A app já bloqueia (DriverFiscalGate); isto fecha o caminho no
  -- servidor. Contas demo ficam de fora (_estafeta_fiscal_bloqueado).
  v_fiscal_bloqueado := public._estafeta_fiscal_bloqueado(v_uid);
  PERFORM set_config('app.order_transition_source', 'driver_accept_offer', true);
  UPDATE public.orders
     SET assigned_driver_id = v_uid::text,
         driver_id = v_uid,
         status = 'driverAccepted',
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL,
         driver_phone = COALESCE(
           driver_phone,
           (SELECT d.phone FROM public.drivers d
             WHERE d.user_id = v_uid LIMIT 1)
         )
   WHERE id = p_order_id
     AND status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id = v_uid::text
     AND NOT v_fiscal_bloqueado;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.orders
      WHERE id = p_order_id
        AND assigned_driver_id = v_uid::text
        AND status IN ('driverAccepted', 'pickedUp', 'onTheWay', 'delivered')
    ) THEN
      RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                                'status', 'driverAccepted',
                                'idempotent', true);
    END IF;
    IF v_fiscal_bloqueado THEN
      RETURN jsonb_build_object('ok', false, 'error', 'estafeta_sem_nif_atividade',
                                'hint', 'Confirme o NIF e a atividade aberta nas Finanças na app');
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'offer_expired_or_taken');
  END IF;
  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id,
                            'status', 'driverAccepted');
END;
$function$;
