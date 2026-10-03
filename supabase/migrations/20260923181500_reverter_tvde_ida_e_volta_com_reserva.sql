-- 2026-09-23 · REVERTE 20260923180000_tvde_ida_e_volta_com_reserva (aplicada e revertida no mesmo dia).
-- Motivo: a prova no ar mostrou que o reembolso automático é recusado pela Edge
-- (403 not_service_role — a chave do cofre não é igual, letra a letra, à do ambiente
-- da Edge). Sem reembolso automático não se liga um pacote cobrado na marcação.
-- Ficam (aditivos e vazios): as 4 colunas novas do vale, os estados novos no CHECK
-- e a setting tvde_roundtrip_return_min_gap_minutes.
DROP TRIGGER IF EXISTS tr_tvde_roundtrip_reserva_ciclo ON public.tvde_rides;
DROP TRIGGER IF EXISTS tr_tvde_reserva_paga_ativa ON public.tvde_rides;
DROP FUNCTION IF EXISTS public.fn_tvde_roundtrip_reserva_ciclo();
DROP FUNCTION IF EXISTS public.fn_tvde_reserva_paga_ativa();
DROP FUNCTION IF EXISTS public.tvde_schedule_roundtrip(double precision, double precision, text, double precision, double precision, text, numeric, timestamptz, timestamptz, text, text);
DROP FUNCTION IF EXISTS public.tvde_roundtrip_reservation_mark_paid(uuid, text, integer);
CREATE OR REPLACE FUNCTION public.tvde_expire_roundtrip_credits()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_count integer;
BEGIN
  WITH expired AS (
    UPDATE public.tvde_roundtrip_credits
       SET status = 'expirado'
     WHERE status = 'ativo'
       AND now() > expires_at
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$function$;
CREATE OR REPLACE FUNCTION public.tvde_reservation_auto_refund(p_ride_id uuid, p_motivo text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'vault', 'net', 'extensions'
AS $function$
DECLARE v_key text; v_url text; v_ride public.tvde_rides;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.payment_intent_id IS NULL THEN RETURN false; END IF;
  IF v_ride.payment_status IN ('refunded','partial_refund','kept_cancel_fee') THEN RETURN true; END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  IF v_key IS NULL THEN RETURN false; END IF;
  v_url := COALESCE(v_url,'https://ojykpzwqrtusfeakzrna.supabase.co');

  PERFORM net.http_post(
    url := v_url || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action','auto_refund_reservation','ride_id', p_ride_id::text, 'motivo', p_motivo));

  INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
    VALUES (p_ride_id,'reserva_reembolso_pedido','system', jsonb_build_object('motivo', p_motivo));
  RETURN true;
END; $function$;
UPDATE public.platform_settings SET value='false'::jsonb WHERE key='tvde_roundtrip_reservation_enabled';
-- colunas/estados novos ficam (aditivos e vazios) para não perder vales já criados
