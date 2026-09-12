-- =====================================================================================
-- PROPOSTA (NÃO APLICADA) — TVDE: pagamento CARD + MB WAY nas corridas
-- =====================================================================================
-- ⚠️⚠️⚠️  ATENÇÃO — ISTO É UMA PROPOSTA. NÃO FOI APLICADA NA BASE DE DADOS.  ⚠️⚠️⚠️
-- ⚠️  MEXE EM DINHEIRO REAL (liquidação motorista / receita Bora / Stripe / MB WAY).
-- ⚠️  Está na LISTA VERMELHA do Validation Gate. Só aplicar depois do Danilo dizer "vai".
-- ⚠️  Rever cêntimo a cêntimo antes de correr. NADA aqui deve ser executado às cegas.
--
-- Projeto Supabase: ojykpzwqrtusfeakzrna
-- Autor: plano gerado por agente (fase de desenho) — 2026-07-07
--
-- FONTE DA VERDADE lida via MCP (pg_get_functiondef) antes de escrever isto:
--   • tvde_request_ride(7 args)  -> UMA assinatura (sem overload)
--   • tvde_finish_ride           -> DUAS assinaturas (2 args -> delega em 3 args). NÃO criar 3.ª.
--   • tvde_calculate_fare(numeric), tvde_cancel_ride(uuid,text,text)
--   • tvde_rides.payment_method  -> JÁ EXISTE (text NOT NULL DEFAULT 'cash'). Só é preciso GRAVAR.
--   • tvde_driver_balances(driver_id uuid, balance numeric DEFAULT 0, updated_at)
--
-- CONVENÇÃO DE SINAL em tvde_driver_balances.balance (EUR) — DEFINIDA AQUI:
--   balance > 0  => O MOTORISTA DEVE À BORA.  (cash: o motorista recebeu a tarifa toda
--                   em numerário; deve à Bora o corte da plataforma / paragens.)
--   balance < 0  => A BORA DEVE AO MOTORISTA. (card/mbway: a Bora recebeu o dinheiro
--                   online; deve ao motorista os ganhos dele.)
--   balance = 0  => quites.
--   Um mesmo motorista com corridas cash e card faz NETTING nesta única coluna
--   (dívida cash abate ao crédito card). O admin liquida/paga e volta a 0.
-- =====================================================================================


-- =====================================================================================
-- (OPCIONAL, ADITIVO) — colunas de rastreio Stripe/MB WAY na corrida.
-- Puramente aditivo e não-financeiro (apenas rastreio). Necessário para auth/capture.
-- =====================================================================================
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS payment_intent_id text,      -- PaymentIntent do Stripe (card manual capture / mbway)
  ADD COLUMN IF NOT EXISTS payment_status    text;      -- ex: 'requires_capture','captured','refunded','failed', NULL=cash


-- =====================================================================================
-- 1) tvde_request_ride  — ganha p_payment_method (DEFAULT 'cash'), validado.
--    Assinatura actual tem 7 args e NÃO tem overload. Para adicionar o 8.º arg SEM
--    duplicar (senão ficam duas funções = overload), fazemos DROP da 7-args + CREATE
--    da 8-args com DEFAULT (chamadas com 7 args continuam a resolver via default).
-- =====================================================================================
DROP FUNCTION IF EXISTS public.tvde_request_ride(
  double precision, double precision, text, double precision, double precision, text, numeric);

CREATE OR REPLACE FUNCTION public.tvde_request_ride(
  p_origin_lat double precision, p_origin_lng double precision, p_origin_label text,
  p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_est_distance_km numeric,
  p_payment_method text DEFAULT 'cash')          -- <<< NOVO
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_acc BOOLEAN; v_fare INTEGER; v_ride public.tvde_rides;
  v_cov JSONB; v_covered BOOLEAN; v_sub_id UUID; v_is_member BOOLEAN;
  v_d_base INT; v_d_perkm INT; v_extra_km INT;
  v_driver_normal INT; v_driver_earn INT; v_client_fare INT; v_bora_cut INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  -- <<< NOVO: validar método de pagamento
  IF p_payment_method NOT IN ('cash','card','mbway') THEN
    RAISE EXCEPTION 'invalid_payment_method: %', p_payment_method;
  END IF;
  SELECT tvde_access INTO v_acc FROM public.users WHERE id = v_uid;
  IF v_acc IS NOT TRUE THEN RAISE EXCEPTION 'no_tvde_access'; END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_rides WHERE client_id = v_uid
             AND status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RAISE EXCEPTION 'ride_in_progress'; END IF;
  v_fare := public.tvde_calculate_fare(p_est_distance_km);
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_est_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_normal := v_d_base + v_extra_km * v_d_perkm;
  v_cov := public.tvde_preview_coverage(v_uid);
  v_covered := COALESCE((v_cov->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_cov->>'subscription_id','')::uuid;
  SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
    WHERE client_id = v_uid AND active = true AND now() BETWEEN starts_at AND ends_at)
    INTO v_is_member;
  IF v_covered THEN
    v_client_fare := 0;
    v_driver_earn := ROUND(v_driver_normal * 0.85)::int;
    v_bora_cut    := v_driver_normal - v_driver_earn;
  ELSIF v_is_member THEN
    v_client_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_client_fare - v_driver_normal;
  ELSE
    v_client_fare := v_fare;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_fare - v_driver_normal;
  END IF;
  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    used_subscription_ride, subscription_id, status,
    payment_method)                              -- <<< NOVO
  VALUES (v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_client_fare, v_driver_earn, v_bora_cut, v_covered, v_sub_id, 'solicitada',
    p_payment_method)                            -- <<< NOVO
  RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
      jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_client_fare,
        'covered', v_covered, 'is_member', v_is_member, 'driver_earn_cents', v_driver_earn,
        'payment_method', p_payment_method));    -- <<< NOVO (auditoria)
  RETURN v_ride;
END; $function$;


-- =====================================================================================
-- 2) tvde_finish_ride  — ramo de liquidação POR MÉTODO, SEM criar overload.
--    Editamos APENAS o corpo de 3 args (CREATE OR REPLACE, mesma assinatura).
--    A versão de 2 args (wrapper que delega na de 3) NÃO é tocada.
--    Só muda o bloco de cálculo de v_settle + o INSERT em tvde_driver_balances.
--    Tudo o resto é idêntico ao actual (lido via pg_get_functiondef).
-- =====================================================================================
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(
  p_ride_id uuid, p_final_distance_km numeric, p_distance_source text DEFAULT NULL::text)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
  v_stops_fee INT; v_stops_drv INT; v_prepaid BOOLEAN; v_settle INT;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;

  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  IF v_prepaid THEN
    v_covered     := false;
    v_sub         := jsonb_build_object('covered', false, 'prepaid_roundtrip', true);
    v_sub_id      := NULL;
    v_fare        := v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  ELSE
    v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
    v_covered := COALESCE((v_sub->>'covered')::boolean, false);
    v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;
    IF v_covered THEN
      v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);
      v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;
      v_fare        := v_stops_fee;
    ELSE
      SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
        WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
        INTO v_is_member;
      IF v_is_member THEN
        v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
      END IF;
      v_fare        := v_fare + v_stops_fee;
      v_driver_earn := v_driver_earn + v_stops_drv;
      v_bora_cut    := v_fare - v_driver_earn;
    END IF;
  END IF;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source), updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- ================= LIQUIDAÇÃO POR MÉTODO DE PAGAMENTO (o que MUDA) =================
  -- v_settle em CÊNTIMOS, COM SINAL (ver convenção no cabeçalho do ficheiro):
  --   v_settle > 0  => soma à DÍVIDA do motorista para com a Bora (caso CASH).
  --   v_settle < 0  => CREDITA o motorista (a Bora recebeu online e DEVE-lhe) (card/mbway).
  IF v_ride.payment_method = 'cash' THEN
    -- Comportamento ACTUAL preservado: o motorista cobrou em numerário, deve o corte à Bora.
    IF v_covered OR v_prepaid THEN
      v_settle := v_stops_fee - v_stops_drv;   -- só as paragens em cash geram dívida
    ELSE
      v_settle := v_bora_cut;                  -- tarifa toda cobrada em cash -> deve o corte
    END IF;
  ELSE
    -- 'card' ou 'mbway': o cliente pagou ONLINE -> a Bora recebeu o dinheiro.
    -- INVERTE a semântica: a Bora passa a DEVER ao motorista os ganhos dele.
    IF v_covered OR v_prepaid THEN
      -- base é €0 (coberta) ou já pré-paga (roundtrip); só as paragens foram cobradas online.
      -- A Bora recebeu stops_fee online e deve ao motorista a fatia dele (stops_drv).
      v_settle := -v_stops_drv;
    ELSE
      -- A Bora recebeu a tarifa final (v_fare) online e deve ao motorista o earn integral.
      -- Nota: v_fare - v_driver_earn = v_bora_cut fica na Bora (a sua margem).
      v_settle := -v_driver_earn;
    END IF;
  END IF;

  -- Aplica com sinal (antes só somava quando > 0; agora aceita crédito negativo).
  IF v_settle <> 0 THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_settle / 100.0, 2), updated_at = now();
  END IF;
  -- =================================================================================

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
      'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
      'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid,
      'payment_method', v_ride.payment_method, 'settle_cents_signed', v_settle,  -- <<< NOVO (auditoria)
      'distance_source', p_distance_source, 'subscription', v_sub));

  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true
               AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;

  RETURN v_ride;
END; $function$;


-- =====================================================================================
-- 3) EDGE FUNCTION NOVA (referência de stub — NÃO mexer na stripe-webhook existente)
-- =====================================================================================
--   Nome:  supabase/functions/tvde-ride-payment/index.ts   (A CRIAR, não incluída aqui)
--   Espelha o padrão de create-payment-intent / create-mbway-payment-intent, MAS valida
--   o montante contra tvde_rides (est_fare_cents / final_fare_cents) em vez de
--   orders.payment_buffer_total. NÃO tocar em stripe-webhook / create-payment-intent /
--   refund / charge-extra (zonas protegidas).
--
--   Ações (query param ?action= ou corpo):
--     • authorize  (CARD)   -> PaymentIntent capture_method='manual', amount=est_fare, confirm.
--                              Guarda payment_intent_id + payment_status='requires_capture' na ride.
--     • capture    (CARD)   -> no finish: captura o final (partial capture se final<auth;
--                              se final>auth, capturar o auth + PI extra estilo charge-extra).
--                              payment_status='captured'.
--     • charge     (MBWAY)  -> cria PI mb_way, confirma server-side com telefone E.164 (>>> como
--                              create-mbway-payment-intent). Recomendado: cobrar no PEDIDO
--                              (estimado); acertar diferença no finish (refund/charge-extra).
--     • void       (CARD)   -> cancelamento sem taxa: anula a autorização (liberta o hold).
--     • refund     (MBWAY)  -> cancelamento/no-show: devolve total ou total-menos-taxa.
--
--   verify_jwt: seguir o padrão da entrega. authorize/charge com o cliente autenticado.
--   A ride paga NÃO é marcada pela stripe-webhook: card=captura síncrona no finish;
--   mbway=confirmação server-side síncrona. (Se se quiser webhook async no futuro, criar
--   uma função webhook SEPARADA — nunca alterar a stripe-webhook das encomendas.)
-- =====================================================================================
