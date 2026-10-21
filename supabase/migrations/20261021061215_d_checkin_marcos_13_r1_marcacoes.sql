-- Bloco D · ronda 1 do revisor (21/10/2026) — vale dos 30 dias nas marcacoes de limpeza e lavagem.
-- F5: cancelada com taxa ou "cliente nao apareceu" -> o vale NAO volta (como o dinheiro num
--     pedido normal: o cliente perderia a taxa). Sem taxa (cancelou a tempo, a profissional
--     cancelou, ninguem aceitou) -> o vale volta. A profissional recebe o mesmo que numa
--     marcacao normal cancelada (o acerto semanal so paga marcacoes concluidas).
-- F6: o pagamento 'premio' so existe com um vale valido do proprio cliente ligado a marcacao,
--     venha de onde vier a escrita; e numa marcacao 'premio' ninguem muda o dinheiro por escrita
--     direta na tabela (so pelas funcoes do servidor).

CREATE OR REPLACE FUNCTION public._checkin_premio_marcacao_cancelada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(NEW.cancel_fee_cents, 0) > 0 OR COALESCE(NEW.no_show_client, false) THEN
    UPDATE public.checkin_premios_vales
       SET motivo = COALESCE(motivo || ' | ', '') || 'marcação ' || NEW.id || ' ' || NEW.status
                    || CASE WHEN COALESCE(NEW.no_show_client, false) THEN ' (cliente não apareceu)'
                            ELSE ' (cancelada com taxa)' END || ': o vale não volta',
           atualizado_em = now()
     WHERE marcacao_id = NEW.id AND estado = 'usado';
    RETURN NULL;
  END IF;
  UPDATE public.checkin_premios_vales
     SET estado = CASE WHEN valido_ate IS NOT NULL AND valido_ate > now() THEN 'por_usar' ELSE 'expirado' END,
         usado_em = NULL, marcacao_tipo = NULL, marcacao_id = NULL,
         motivo = COALESCE(motivo || ' | ', '') || 'marcação ' || NEW.id || ' ' || NEW.status,
         atualizado_em = now()
   WHERE marcacao_id = NEW.id AND estado = 'usado';
  RETURN NULL;
END;
$function$;

-- Guarda do pagamento 'premio'. SECURITY INVOKER de proposito: current_user diz quem escreve
-- (authenticated = escrita direta pela API; o dono das funcoes = as funcoes do servidor).
CREATE OR REPLACE FUNCTION public._checkin_premio_guarda_pagamento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_tipo  text := CASE TG_TABLE_NAME WHEN 'cleaning_bookings' THEN 'limpeza' ELSE 'lavagem' END;
  v_passa boolean := false;
  v_novo  jsonb;
  v_velho jsonb;
  k       text;
BEGIN
  -- passar a 'premio' (ao criar ou ao mudar) so com o vale do proprio cliente ja ligado a marcacao
  IF TG_OP = 'INSERT' THEN
    v_passa := NEW.payment_method = 'premio';
  ELSE
    v_passa := NEW.payment_method = 'premio' AND OLD.payment_method IS DISTINCT FROM 'premio';
  END IF;
  IF v_passa AND NOT EXISTS (
       SELECT 1 FROM public.checkin_premios_vales v
        WHERE v.marcacao_id = NEW.id
          AND v.user_id = NEW.client_user_id
          AND v.tipo = 'servico'
          AND v.estado = 'usado'
          AND v.marcacao_tipo = v_tipo) THEN
    RAISE EXCEPTION 'checkin_premio_pagamento_sem_vale' USING ERRCODE = '42501';
  END IF;
  -- numa marcacao 'premio' a Bora paga: o dinheiro nao se muda por escrita direta na tabela
  IF TG_OP = 'UPDATE' THEN
    IF OLD.payment_method = 'premio' AND current_user IN ('authenticated', 'anon') THEN
      v_novo  := to_jsonb(NEW);
      v_velho := to_jsonb(OLD);
      FOREACH k IN ARRAY ARRAY['payment_method', 'payment_status', 'total_cents', 'base_cents', 'bora_fee_cents',
                               'cleaner_earnings_cents', 'washer_earnings_cents', 'cancel_fee_cents',
                               'client_user_id', 'hours', 'service_type'] LOOP
        IF (v_novo -> k) IS DISTINCT FROM (v_velho -> k) THEN
          RAISE EXCEPTION 'checkin_premio_marcacao_so_pelo_servidor (%)', k USING ERRCODE = '42501';
        END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._checkin_premio_marcacao_cancelada() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_premio_guarda_pagamento() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_checkin_premio_guarda_pagamento
  BEFORE INSERT ON public.cleaning_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio')
  EXECUTE FUNCTION public._checkin_premio_guarda_pagamento();

CREATE OR REPLACE TRIGGER trg_checkin_premio_guarda_pagamento_upd
  BEFORE UPDATE ON public.cleaning_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio' OR OLD.payment_method = 'premio')
  EXECUTE FUNCTION public._checkin_premio_guarda_pagamento();

CREATE OR REPLACE TRIGGER trg_checkin_premio_guarda_pagamento
  BEFORE INSERT ON public.carwash_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio')
  EXECUTE FUNCTION public._checkin_premio_guarda_pagamento();

CREATE OR REPLACE TRIGGER trg_checkin_premio_guarda_pagamento_upd
  BEFORE UPDATE ON public.carwash_bookings
  FOR EACH ROW
  WHEN (NEW.payment_method = 'premio' OR OLD.payment_method = 'premio')
  EXECUTE FUNCTION public._checkin_premio_guarda_pagamento();

-- As funcoes de marcar com o vale: o vale fica ligado a marcacao ANTES de o pagamento passar a 'premio'.
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
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = v_uid FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
  IF v.tipo <> 'servico' OR NOT ('limpeza' = ANY (v.opcoes)) THEN RAISE EXCEPTION 'checkin_premio_nao_e_limpeza'; END IF;
  IF v.estado <> 'por_usar' THEN RAISE EXCEPTION 'checkin_premio_estado: %', v.estado; END IF;
  IF v.valido_ate IS NULL OR v.valido_ate <= now() THEN RAISE EXCEPTION 'checkin_premio_expirado'; END IF;

  SELECT x INTO m FROM jsonb_array_elements(public._checkin_marcos_config()) x WHERE x ->> 'chave' = v.marco_chave LIMIT 1;
  v_horas := LEAST(GREATEST(COALESCE((m ->> 'limpeza_horas')::int, 2), 1), 12);

  v_b := public.create_cleaning_booking(
    'standard', 'hourly', NULL, v_horas, p_scheduled_at, 'single', 'client', 'card',
    p_address_street, p_address_city, p_address_postal, p_lat, p_lng,
    btrim(COALESCE(p_notes, '') || ' [Prémio do check-in: ' || v_horas || ' h de limpeza pagas pela Bora]'),
    NULL, 'checkin-premio-' || v.id::text);
  v_id := (v_b ->> 'id')::uuid;

  UPDATE public.checkin_premios_vales
     SET estado = 'usado', usado_em = now(), opcao = 'limpeza', marcacao_tipo = 'limpeza', marcacao_id = v_id,
         custo_cents = COALESCE((v_b ->> 'cleaner_earnings_cents')::int, 0),
         valor_cents = COALESCE((v_b ->> 'total_cents')::int, 0), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  -- 'card' + 'unpaid' nao chama ninguem; a passagem a 'held' dispara a 1.a oferta (gatilho que ja existe)
  UPDATE public.cleaning_bookings
     SET payment_method = 'premio', payment_status = 'held'
   WHERE id = v_id AND payment_method = 'card' AND payment_status = 'unpaid';

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
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = v_uid FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'checkin_premio_nao_encontrado'; END IF;
  IF v.tipo <> 'servico' OR NOT ('lavagem' = ANY (v.opcoes)) THEN RAISE EXCEPTION 'checkin_premio_nao_e_lavagem'; END IF;
  IF v.estado <> 'por_usar' THEN RAISE EXCEPTION 'checkin_premio_estado: %', v.estado; END IF;
  IF v.valido_ate IS NULL OR v.valido_ate <= now() THEN RAISE EXCEPTION 'checkin_premio_expirado'; END IF;

  v_b := public.create_carwash_booking(
    'exterior', p_plate, p_client_phone, p_when_mode, p_scheduled_at,
    p_address_street, p_address_city, p_address_postal, p_lat, p_lng, 'card',
    p_car_make_model, p_car_color, p_pickup_notes,
    '[Prémio do check-in: lavagem exterior paga pela Bora]', '[]'::jsonb, NULL);
  v_id := (v_b ->> 'id')::uuid;

  UPDATE public.checkin_premios_vales
     SET estado = 'usado', usado_em = now(), opcao = 'lavagem', marcacao_tipo = 'lavagem', marcacao_id = v_id,
         custo_cents = COALESCE((v_b ->> 'washer_earnings_cents')::int, 0),
         valor_cents = COALESCE((v_b ->> 'total_cents')::int, 0), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  UPDATE public.carwash_bookings
     SET payment_method = 'premio', payment_status = 'held'
   WHERE id = v_id AND payment_method = 'card' AND payment_status = 'unpaid';
  PERFORM public._carwash_next_offer(v_id);

  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v),
                            'marcacao', (SELECT to_jsonb(w) FROM public.carwash_bookings w WHERE w.id = v_id));
END;
$function$;
