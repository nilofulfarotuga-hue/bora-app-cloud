-- 04/10/2026 (agente cliente-app) — "Reportar um problema" no pedido do cliente.
-- Aplicada em produção (versão 20261004194440).
-- A RPC file_complaint existia mas tinha perdido o EXECUTE para authenticated
-- (só postgres/service_role), e aceitava qualquer pedido. Passa a validar que
-- quem se queixa está ligado ao pedido (cliente dono, estafeta atribuído ou dono
-- da loja). Assinatura igual — nada mais muda.
CREATE OR REPLACE FUNCTION public.file_complaint(p_role text, p_category text, p_subject text, p_body text, p_related_order_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_id UUID; v_ok boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_related_order_id IS NOT NULL THEN
    SELECT CASE p_role
             WHEN 'client' THEN o.user_id = v_uid
             WHEN 'driver' THEN o.assigned_driver_id = v_uid::text
             WHEN 'partner' THEN EXISTS (
               SELECT 1 FROM public.restaurants r
                WHERE r.id::text = o.restaurant_id
                  AND (r.user_id = v_uid OR r.user_ = v_uid))
             ELSE false
           END
      INTO v_ok
      FROM public.orders o
     WHERE o.id = p_related_order_id;
    IF coalesce(v_ok, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'order_not_yours';
    END IF;
  END IF;
  INSERT INTO public.complaints (reporter_id, reporter_role, category, subject, body, related_order_id)
  VALUES (v_uid, p_role, p_category, trim(p_subject), trim(p_body), p_related_order_id)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'complaint_id', v_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.file_complaint(text, text, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.file_complaint(text, text, text, text, text) TO authenticated;
