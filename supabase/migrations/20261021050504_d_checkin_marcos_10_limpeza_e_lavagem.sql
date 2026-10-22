-- Bloco D · fechar-pendencias-2026-10-20 — usar o vale dos 30 dias: limpeza de 2 h ou
-- lavagem exterior. Reaproveita as funcoes de marcacao que ja existem (validacoes, orcamento,
-- ganho do prestador, ofertas) e so troca a forma de pagamento para 'premio': o cliente nao
-- paga nada, o prestador recebe o ganho normal no acerto semanal, a Bora absorve.

CREATE OR REPLACE FUNCTION public.client_checkin_premio_marcar_limpeza(
  p_vale_id uuid, p_scheduled_at timestamptz,
  p_address_street text, p_address_city text, p_address_postal text,
  p_lat double precision, p_lng double precision, p_notes text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v       public.checkin_premios_vales;
  m       jsonb;
  v_horas integer;
  v_b     jsonb;
  v_id    uuid;
  v_ganho integer;
  v_total integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = v_uid FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
  IF v.tipo <> 'servico' OR NOT ('limpeza' = ANY (v.opcoes)) THEN RAISE EXCEPTION 'checkin_premio_nao_e_limpeza'; END IF;
  IF v.estado <> 'por_usar' THEN RAISE EXCEPTION 'checkin_premio_estado: %', v.estado; END IF;
  IF v.valido_ate IS NOT NULL AND v.valido_ate <= now() THEN RAISE EXCEPTION 'checkin_premio_expirado'; END IF;

  SELECT x INTO m FROM jsonb_array_elements(public._checkin_marcos_config()) x WHERE x ->> 'chave' = v.marco_chave LIMIT 1;
  v_horas := LEAST(GREATEST(COALESCE((m ->> 'limpeza_horas')::int, 2), 1), 12);

  v_b := public.create_cleaning_booking(
    'standard', 'hourly', NULL, v_horas, p_scheduled_at, 'single', 'client', 'card',
    p_address_street, p_address_city, p_address_postal, p_lat, p_lng,
    btrim(COALESCE(p_notes, '') || ' [Prémio do check-in: ' || v_horas || ' h de limpeza pagas pela Bora]'),
    NULL, 'checkin-premio-' || v.id::text);
  v_id := (v_b ->> 'id')::uuid;

  -- 'card' + 'unpaid' nao chama ninguem; a passagem a 'held' dispara a 1.a oferta (gatilho que ja existe)
  UPDATE public.cleaning_bookings
     SET payment_method = 'premio', payment_status = 'held'
   WHERE id = v_id AND payment_method = 'card' AND payment_status = 'unpaid';

  SELECT b.cleaner_earnings_cents, b.total_cents INTO v_ganho, v_total FROM public.cleaning_bookings b WHERE b.id = v_id;
  UPDATE public.checkin_premios_vales
     SET estado = 'usado', usado_em = now(), opcao = 'limpeza', marcacao_tipo = 'limpeza', marcacao_id = v_id,
         custo_cents = COALESCE(v_ganho, 0), valor_cents = COALESCE(v_total, 0), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v),
                            'marcacao', (SELECT to_jsonb(b) FROM public.cleaning_bookings b WHERE b.id = v_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_premio_marcar_lavagem(
  p_vale_id uuid, p_plate text, p_client_phone text, p_when_mode text, p_scheduled_at timestamptz,
  p_address_street text, p_address_city text, p_address_postal text,
  p_lat double precision, p_lng double precision,
  p_car_make_model text DEFAULT '', p_car_color text DEFAULT '', p_pickup_notes text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v       public.checkin_premios_vales;
  v_b     jsonb;
  v_id    uuid;
  v_ganho integer;
  v_total integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = v_uid FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
  IF v.tipo <> 'servico' OR NOT ('lavagem' = ANY (v.opcoes)) THEN RAISE EXCEPTION 'checkin_premio_nao_e_lavagem'; END IF;
  IF v.estado <> 'por_usar' THEN RAISE EXCEPTION 'checkin_premio_estado: %', v.estado; END IF;
  IF v.valido_ate IS NOT NULL AND v.valido_ate <= now() THEN RAISE EXCEPTION 'checkin_premio_expirado'; END IF;

  v_b := public.create_carwash_booking(
    'exterior', p_plate, p_client_phone, p_when_mode, p_scheduled_at,
    p_address_street, p_address_city, p_address_postal, p_lat, p_lng, 'card',
    p_car_make_model, p_car_color, p_pickup_notes,
    '[Prémio do check-in: lavagem exterior paga pela Bora]', '[]'::jsonb, NULL);
  v_id := (v_b ->> 'id')::uuid;

  UPDATE public.carwash_bookings
     SET payment_method = 'premio', payment_status = 'held'
   WHERE id = v_id AND payment_method = 'card' AND payment_status = 'unpaid';
  PERFORM public._carwash_next_offer(v_id);

  SELECT w.washer_earnings_cents, w.total_cents INTO v_ganho, v_total FROM public.carwash_bookings w WHERE w.id = v_id;
  UPDATE public.checkin_premios_vales
     SET estado = 'usado', usado_em = now(), opcao = 'lavagem', marcacao_tipo = 'lavagem', marcacao_id = v_id,
         custo_cents = COALESCE(v_ganho, 0), valor_cents = COALESCE(v_total, 0), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v),
                            'marcacao', (SELECT to_jsonb(w) FROM public.carwash_bookings w WHERE w.id = v_id));
END;
$function$;

-- Marcacao cancelada: o vale volta a "por usar" (ou expira, se ja passou o prazo).
CREATE OR REPLACE FUNCTION public._checkin_premio_marcacao_cancelada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.checkin_premios_vales
     SET estado = CASE WHEN valido_ate IS NULL OR valido_ate > now() THEN 'por_usar' ELSE 'expirado' END,
         usado_em = NULL, marcacao_tipo = NULL, marcacao_id = NULL,
         motivo = COALESCE(motivo || ' | ', '') || 'marcação ' || NEW.id || ' ' || NEW.status,
         atualizado_em = now()
   WHERE marcacao_id = NEW.id AND estado = 'usado';
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_checkin_premio_limpeza_cancelada
  AFTER UPDATE OF status ON public.cleaning_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio' AND NEW.status LIKE 'cancelled%' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public._checkin_premio_marcacao_cancelada();

CREATE OR REPLACE TRIGGER trg_checkin_premio_lavagem_cancelada
  AFTER UPDATE OF status ON public.carwash_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio' AND NEW.status LIKE 'cancelled%' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public._checkin_premio_marcacao_cancelada();

REVOKE ALL ON FUNCTION public.client_checkin_premio_marcar_limpeza(uuid, timestamptz, text, text, text, double precision, double precision, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_premio_marcar_lavagem(uuid, text, text, text, timestamptz, text, text, text, double precision, double precision, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._checkin_premio_marcacao_cancelada() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_marcar_limpeza(uuid, timestamptz, text, text, text, double precision, double precision, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_marcar_lavagem(uuid, text, text, text, timestamptz, text, text, text, double precision, double precision, text, text, text) TO authenticated;
