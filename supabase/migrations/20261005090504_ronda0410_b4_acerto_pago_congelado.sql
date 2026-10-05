-- Ronda 04/10 Bloco B item 4: recalculos nunca reescrevem semanas ja pagas/recebidas.
-- As funcoes que recalculam (compute_* de estafeta/parceiro/limpeza/lavagem/barbearia,
-- admin_carwash_recalc_settlement, weekly_closeout_compile, run_weekly_closeout) escrevem
-- por INSERT ... ON CONFLICT DO UPDATE. Varias sao protegidas pela Trava (nao se reescrevem),
-- por isso a regra vai num GATILHO ADITIVO (PADRAO_BORA s.6): numa linha ja paga/recebida,
-- qualquer UPDATE que nao mude o estado so pode mexer em notes / payment_reference /
-- payment_method; o resto volta ao que estava e fica registo em admin_audit_log.
-- Reabrir (admin_reabrir_acerto / admin_unmark_settlement, estado -> pending) continua a passar.

CREATE OR REPLACE FUNCTION public._acerto_pago_congelado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_livres text[] := ARRAY['notes', 'payment_reference', 'payment_method'];
  v_old jsonb := to_jsonb(OLD);
  v_new jsonb := to_jsonb(NEW);
BEGIN
  IF OLD.status IN ('paid', 'received') AND NEW.status IN ('paid', 'received')
     AND (v_new - v_livres) IS DISTINCT FROM (v_old - v_livres) THEN
    INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id, entity_id_text, details)
    VALUES (auth.uid(), 'acerto_pago_recalculo_ignorado', TG_TABLE_NAME, OLD.id, OLD.id::text,
            jsonb_build_object('estado', OLD.status, 'antes', v_old - v_livres, 'tentativa', v_new - v_livres));
    NEW := jsonb_populate_record(NEW, v_old - v_livres);
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION public._acerto_pago_congelado() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_acerto_pago_congelado BEFORE UPDATE ON public.driver_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_pago_congelado();
CREATE OR REPLACE TRIGGER trg_acerto_pago_congelado BEFORE UPDATE ON public.partner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_pago_congelado();
CREATE OR REPLACE TRIGGER trg_acerto_pago_congelado BEFORE UPDATE ON public.cleaner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_pago_congelado();
CREATE OR REPLACE TRIGGER trg_acerto_pago_congelado BEFORE UPDATE ON public.washer_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._acerto_pago_congelado();
CREATE OR REPLACE TRIGGER trg_acerto_pago_congelado BEFORE UPDATE ON public.appointment_payouts
  FOR EACH ROW EXECUTE FUNCTION public._acerto_pago_congelado();

-- O resumo semanal (weekly_digest_log) de uma semana ja paga/recebida tambem nao muda de valor.
CREATE OR REPLACE FUNCTION public._acerto_esta_fechado(p_type text, p_id text, p_ws timestamptz)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(CASE p_type
    WHEN 'driver'   THEN EXISTS (SELECT 1 FROM driver_weekly_settlements  s WHERE s.driver_id::text  = p_id AND s.week_start_at = p_ws AND s.status IN ('paid','received'))
    WHEN 'partner'  THEN EXISTS (SELECT 1 FROM partner_weekly_settlements s WHERE s.partner_id::text = p_id AND s.week_start_at = p_ws AND s.status IN ('paid','received'))
    WHEN 'cleaner'  THEN EXISTS (SELECT 1 FROM cleaner_weekly_settlements s WHERE s.cleaner_id::text = p_id AND s.week_start_at = p_ws AND s.status IN ('paid','received'))
    WHEN 'washer'   THEN EXISTS (SELECT 1 FROM washer_weekly_settlements  s WHERE s.washer_id::text  = p_id AND s.week_start_at = p_ws AND s.status IN ('paid','received'))
    WHEN 'provider' THEN EXISTS (SELECT 1 FROM appointment_payouts        s WHERE s.provider_id::text = p_id AND s.week_start_at = p_ws AND s.status IN ('paid','received'))
  END, false)
$function$;
REVOKE ALL ON FUNCTION public._acerto_esta_fechado(text, text, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._digest_pago_congelado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (NEW.net_cents, NEW.direction, NEW.breakdown) IS DISTINCT FROM (OLD.net_cents, OLD.direction, OLD.breakdown)
     AND public._acerto_esta_fechado(OLD.subject_type, OLD.subject_id, OLD.week_start_at) THEN
    INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id, entity_id_text, details)
    VALUES (auth.uid(), 'acerto_pago_recalculo_ignorado', 'weekly_digest_log', OLD.id, OLD.subject_type || ':' || OLD.subject_id,
            jsonb_build_object('semana', OLD.week_start_at, 'antes_cents', OLD.net_cents, 'tentativa_cents', NEW.net_cents));
    NEW.net_cents := OLD.net_cents;
    NEW.direction := OLD.direction;
    NEW.breakdown := OLD.breakdown;
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION public._digest_pago_congelado() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_digest_pago_congelado BEFORE UPDATE ON public.weekly_digest_log
  FOR EACH ROW EXECUTE FUNCTION public._digest_pago_congelado();
