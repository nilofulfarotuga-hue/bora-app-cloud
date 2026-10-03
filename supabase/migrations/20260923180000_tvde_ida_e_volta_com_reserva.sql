-- ════════════════════════════════════════════════════════════════════════════
-- Ida-e-volta com reserva (TVDE) · 2026-09-23 · APLICADA com o "vai" do Danilo
-- ════════════════════════════════════════════════════════════════════════════
-- ⚠️ Mexe em pagamento (pacote pago por cartão/MB Way na marcação, reembolso do
-- pacote, ganho do motorista em cada perna). Aplicada a 23/09 depois do "vai" do
-- Danilo, junto com a tvde-payment v11 (charge_roundtrip_reservation,
-- confirm_roundtrip_reservation_payment, auto_refund_roundtrip_reservation).
-- Nenhum valor muda: preço do pacote e €3,75 por perna lidos das chaves de hoje.
--
-- Provado em transação REVERTIDA a 2026-09-23 (ver relatório da missão).
--
-- O que faz (tudo ADITIVO — nada do caminho de hoje muda de comportamento):
--   1. tvde_roundtrip_credits ganha: outbound_scheduled_at, return_mode
--      ('cliente_chama' | 'marcada'), return_scheduled_at,
--      scheduled_return_ride_id; estados novos 'reservado' (ida ainda por
--      fazer) e 'anulado' (ida cancelada / sem motorista → reembolsado).
--   2. tvde_schedule_roundtrip(...) — marca a IDA pelo fluxo de reserva que já
--      existe (tvde_schedule_ride: antecedência, sobreposição, rotação justa,
--      lembretes, travão pela rota) e liga-lhe o vale do pacote. Se a cliente
--      marcar a hora da VOLTA, cria a segunda reserva ligada ao mesmo pacote.
--      Preço = o do pacote ida-e-volta de hoje (tvde_roundtrip_price_for_km),
--      SEM taxa de reserva. Motorista: €3,75 + km em CADA perna, pelas chaves
--      próprias do pacote (tvde_roundtrip_outbound_driver_cents /
--      tvde_roundtrip_return_driver_cents) — nenhum valor alterado.
--   3. tvde_roundtrip_reservation_mark_paid(...) — só service_role (Edge Fn):
--      grava o PaymentIntent no vale e põe as duas pernas a procurar motorista.
--   4. Trigger do ciclo do vale:
--        ida finalizada  → volta marcada: vale 'usado' (a volta é a marcada)
--                        → "chamo quando terminar": vale 'ativo' (12 h a contar
--                          do fim da ida) — carrega em "Pedir volta" como hoje
--        ida cancelada / sem motorista / no-show → vale 'anulado' e a volta
--                          marcada é cancelada (o reembolso total da ida sai
--                          pelo caminho de sempre: tvde_reservation_auto_refund)
--        volta marcada falha (sem motorista / cancelada) depois da ida feita
--                        → o vale volta a 'ativo' para pedir na hora.
--   5. tvde_expire_roundtrip_credits nunca expira um vale ligado a uma volta
--      marcada ainda viva.
--   6. Interruptor tvde_roundtrip_reservation_enabled passa a true no fim —
--      é o que faz aparecer o "Marcar para depois" no ida-e-volta da app.
-- ════════════════════════════════════════════════════════════════════════════


-- 1. Colunas + estados novos do vale ------------------------------------------
ALTER TABLE public.tvde_roundtrip_credits
  ADD COLUMN IF NOT EXISTS outbound_scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS return_mode text,
  ADD COLUMN IF NOT EXISTS return_scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS scheduled_return_ride_id uuid
    REFERENCES public.tvde_rides(id) ON DELETE SET NULL;

ALTER TABLE public.tvde_roundtrip_credits
  DROP CONSTRAINT IF EXISTS tvde_roundtrip_credits_return_mode_check;
ALTER TABLE public.tvde_roundtrip_credits
  ADD CONSTRAINT tvde_roundtrip_credits_return_mode_check
  CHECK (return_mode IS NULL OR return_mode IN ('cliente_chama','marcada'));

ALTER TABLE public.tvde_roundtrip_credits
  DROP CONSTRAINT IF EXISTS tvde_roundtrip_credits_status_check;
ALTER TABLE public.tvde_roundtrip_credits
  ADD CONSTRAINT tvde_roundtrip_credits_status_check
  CHECK (status IN ('ativo','usado','expirado','reservado','anulado'));

COMMENT ON COLUMN public.tvde_roundtrip_credits.return_mode IS
  'Ida-e-volta marcada: cliente_chama = a cliente pede a volta quando terminar (vale); marcada = volta reservada a uma hora (scheduled_return_ride_id).';

-- Setting da folga mínima entre a hora da ida e a da volta (não é dinheiro).
INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_roundtrip_return_min_gap_minutes', '30'::jsonb,
        'Ida-e-volta marcada: minutos mínimos entre a hora da ida e a hora da volta.',
        'tvde')
ON CONFLICT (key) DO NOTHING;

-- 2. Marcar o pacote ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tvde_schedule_roundtrip(
  p_origin_lat double precision, p_origin_lng double precision, p_origin_label text,
  p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_est_distance_km numeric,
  p_outbound_at timestamptz,
  p_return_at timestamptz DEFAULT NULL,
  p_payment_method text DEFAULT 'cash',
  p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_online boolean := COALESCE(p_payment_method, 'cash') <> 'cash';
  v_hours  int := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 12);
  v_gap    int := COALESCE((public.get_setting('tvde_roundtrip_return_min_gap_minutes') #>> '{}')::int, 30);
  v_price  int;
  v_ida    public.tvde_rides;
  v_volta  public.tvde_rides;
  v_credit public.tvde_roundtrip_credits;
  v_extra_km int;
  v_out_earn int;
  v_ret_earn int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT COALESCE((public.get_setting('tvde_roundtrip_reservation_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'roundtrip_reservations_disabled';
  END IF;
  IF p_return_at IS NOT NULL THEN
    IF p_return_at < p_outbound_at + make_interval(mins => v_gap) THEN
      RAISE EXCEPTION 'return_too_soon';
    END IF;
    IF p_return_at > p_outbound_at + make_interval(hours => v_hours) THEN
      RAISE EXCEPTION 'return_too_far';
    END IF;
  END IF;

  -- A IDA pelo caminho de reserva de sempre (valida antecedência, sobreposição,
  -- máximo de reservas, forma de pagamento, interruptores). Em dinheiro já sai
  -- a primeira oferta — o push lê a linha DEPOIS do commit, com o ganho certo.
  v_ida := public.tvde_schedule_ride(
    p_origin_lat, p_origin_lng, p_origin_label,
    p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, p_outbound_at, p_payment_method, p_note);

  v_price := public.tvde_roundtrip_price_for_km(COALESCE(p_est_distance_km, 0));
  v_extra_km := GREATEST(0, CEIL(COALESCE(p_est_distance_km, 0)
                  - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_out_earn := COALESCE((public.get_setting('tvde_roundtrip_outbound_driver_cents') #>> '{}')::int,
                         (public.get_setting('tvde_driver_base_cents') #>> '{}')::int)
                + v_extra_km * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_ret_earn := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int
                + v_extra_km * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;

  INSERT INTO public.tvde_roundtrip_credits
    (client_id, outbound_ride_id, paid_cents, payment_intent_id, status, expires_at,
     outbound_scheduled_at, return_mode, return_scheduled_at)
  VALUES
    (v_uid, v_ida.id, v_price, NULL, 'reservado',
     COALESCE(p_return_at, p_outbound_at) + make_interval(hours => v_hours),
     p_outbound_at,
     CASE WHEN p_return_at IS NULL THEN 'cliente_chama' ELSE 'marcada' END,
     p_return_at)
  RETURNING * INTO v_credit;

  UPDATE public.tvde_rides
     SET roundtrip_credit_id = v_credit.id,
         driver_earn_cents   = v_out_earn,
         updated_at          = now()
   WHERE id = v_ida.id
  RETURNING * INTO v_ida;

  IF p_return_at IS NOT NULL THEN
    -- A VOLTA: mesma forma da volta pedida na hora (tvde_request_return_ride):
    -- tarifa 0 (já paga no pacote), 'cash' = nada a cobrar, is_return_leg.
    INSERT INTO public.tvde_rides (
      client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
      est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
      payment_method, status, scheduled_at, reservation_status,
      roundtrip_credit_id, is_return_leg, customer_note)
    VALUES (
      v_uid, p_dest_lat, p_dest_lng, p_dest_label, p_origin_lat, p_origin_lng, p_origin_label,
      p_est_distance_km, 0, v_ret_earn, 0,
      'cash', 'agendada', p_return_at,
      CASE WHEN v_online THEN 'aguarda_pagamento' ELSE 'a_procurar' END,
      v_credit.id, true, p_note)
    RETURNING * INTO v_volta;

    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_volta.id, 'agendada', 'client',
      jsonb_build_object('scheduled_at', p_return_at, 'volta_do_pacote', true,
                         'credit_id', v_credit.id, 'ida_ride_id', v_ida.id,
                         'driver_earn_cents', v_ret_earn));

    UPDATE public.tvde_roundtrip_credits
       SET scheduled_return_ride_id = v_volta.id
     WHERE id = v_credit.id
    RETURNING * INTO v_credit;

    IF NOT v_online THEN
      PERFORM public.tvde_reservation_offer_to_next(v_volta.id);
    END IF;
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (v_ida.id, 'agendada', 'client',
    jsonb_build_object('pacote_ida_e_volta', true, 'credit_id', v_credit.id,
                       'price_cents', v_price, 'return_mode', v_credit.return_mode,
                       'return_at', p_return_at, 'volta_ride_id', v_volta.id,
                       'driver_earn_cents', v_out_earn));

  RETURN jsonb_build_object(
    'ida',         to_jsonb(v_ida),
    'volta',       CASE WHEN v_volta.id IS NULL THEN NULL ELSE to_jsonb(v_volta) END,
    'credit',      to_jsonb(v_credit),
    'price_cents', v_price);
END;
$function$;

REVOKE ALL ON FUNCTION public.tvde_schedule_roundtrip(double precision, double precision, text, double precision, double precision, text, numeric, timestamptz, timestamptz, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tvde_schedule_roundtrip(double precision, double precision, text, double precision, double precision, text, numeric, timestamptz, timestamptz, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.tvde_schedule_roundtrip(double precision, double precision, text, double precision, double precision, text, numeric, timestamptz, timestamptz, text, text) TO authenticated;

-- 3. Pagamento confirmado (Edge Fn, service_role) --------------------------------
CREATE OR REPLACE FUNCTION public.tvde_roundtrip_reservation_mark_paid(
  p_ride_id uuid, p_payment_intent_id text, p_amount_cents integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_ida public.tvde_rides; v_credit public.tvde_roundtrip_credits; v_volta public.tvde_rides;
BEGIN
  SELECT * INTO v_ida FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND OR v_ida.roundtrip_credit_id IS NULL OR COALESCE(v_ida.is_return_leg, false) THEN
    RETURN false;
  END IF;
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
   WHERE id = v_ida.roundtrip_credit_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;

  -- Idempotente: o mesmo PaymentIntent outra vez não faz nada.
  IF v_credit.payment_intent_id IS NOT DISTINCT FROM p_payment_intent_id
     AND v_ida.reservation_status <> 'aguarda_pagamento' THEN
    RETURN true;
  END IF;

  UPDATE public.tvde_roundtrip_credits
     SET payment_intent_id = p_payment_intent_id,
         paid_cents = COALESCE(p_amount_cents, paid_cents)
   WHERE id = v_credit.id;

  -- A IDA: o caminho de reserva paga de sempre (a_procurar + oferta + aviso admin).
  PERFORM public.tvde_reservation_mark_paid(p_ride_id);

  -- A VOLTA marcada, se existir, passa também a procurar motorista.
  IF v_credit.scheduled_return_ride_id IS NOT NULL THEN
    UPDATE public.tvde_rides
       SET reservation_status = 'a_procurar', updated_at = now()
     WHERE id = v_credit.scheduled_return_ride_id
       AND status = 'agendada' AND reservation_status = 'aguarda_pagamento'
    RETURNING * INTO v_volta;
    IF v_volta.id IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_volta.id, 'reserva_paga', 'system',
              jsonb_build_object('volta_do_pacote', true, 'payment_intent_id', p_payment_intent_id));
      PERFORM public.tvde_reservation_offer_to_next(v_volta.id);
    END IF;
  END IF;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.tvde_roundtrip_reservation_mark_paid(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tvde_roundtrip_reservation_mark_paid(uuid, text, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_roundtrip_reservation_mark_paid(uuid, text, integer) TO service_role;

-- 4. Ciclo do vale ao mudar o estado de uma perna --------------------------------
CREATE OR REPLACE FUNCTION public.fn_tvde_roundtrip_reserva_ciclo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_credit public.tvde_roundtrip_credits;
  v_hours  int := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 12);
  v_ida_feita boolean;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.roundtrip_credit_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
   WHERE id = NEW.roundtrip_credit_id FOR UPDATE;
  -- Só vales de pacote MARCADO (return_mode preenchido). O pacote comprado na
  -- hora segue exactamente como hoje.
  IF NOT FOUND OR v_credit.return_mode IS NULL THEN RETURN NEW; END IF;

  IF NOT COALESCE(NEW.is_return_leg, false) THEN
    -- ── IDA ──
    IF v_credit.status <> 'reservado' THEN RETURN NEW; END IF;
    IF NEW.status = 'finalizada' THEN
      IF v_credit.scheduled_return_ride_id IS NOT NULL
         AND EXISTS (SELECT 1 FROM public.tvde_rides v
                      WHERE v.id = v_credit.scheduled_return_ride_id
                        AND v.status IN ('agendada','solicitada','motorista_atribuido',
                                         'motorista_a_caminho','motorista_chegou','em_andamento')) THEN
        UPDATE public.tvde_roundtrip_credits
           SET status = 'usado', return_ride_id = scheduled_return_ride_id
         WHERE id = v_credit.id;
      ELSE
        UPDATE public.tvde_roundtrip_credits
           SET status = 'ativo', return_mode = 'cliente_chama',
               scheduled_return_ride_id = NULL,
               expires_at = GREATEST(expires_at, now() + make_interval(hours => v_hours))
         WHERE id = v_credit.id;
      END IF;
    ELSIF NEW.status IN ('cancelada_cliente','cancelada_motorista','sem_motorista','no_show') THEN
      UPDATE public.tvde_roundtrip_credits SET status = 'anulado' WHERE id = v_credit.id;
      -- A volta marcada deixa de fazer sentido: cancela-se (sem taxa).
      IF v_credit.scheduled_return_ride_id IS NOT NULL THEN
        UPDATE public.tvde_rides
           SET status = 'cancelada_cliente', reservation_status = 'cancelada',
               cancel_reason = 'ida_do_pacote_cancelada', cancel_fee_cents = 0,
               reservation_offer_driver_id = NULL, reservation_offer_expires_at = NULL,
               current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
         WHERE id = v_credit.scheduled_return_ride_id
           AND status IN ('agendada','solicitada','motorista_atribuido','motorista_a_caminho');
        INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_credit.scheduled_return_ride_id, 'cancelada_cliente', 'system',
                jsonb_build_object('motivo', 'ida do pacote ' || NEW.status, 'ida_ride_id', NEW.id));
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- ── VOLTA marcada ──
  IF v_credit.scheduled_return_ride_id IS DISTINCT FROM NEW.id THEN RETURN NEW; END IF;
  IF NEW.status IN ('cancelada_cliente','cancelada_motorista','sem_motorista','no_show') THEN
    IF v_credit.status = 'anulado' THEN RETURN NEW; END IF;  -- foi a ida que caiu
    SELECT (r.status = 'finalizada') INTO v_ida_feita
      FROM public.tvde_rides r WHERE r.id = v_credit.outbound_ride_id;
    IF COALESCE(v_ida_feita, false) THEN
      -- Ida feita, volta falhou → o vale volta a ficar activo para pedir na hora.
      UPDATE public.tvde_roundtrip_credits
         SET status = 'ativo', return_mode = 'cliente_chama',
             return_ride_id = NULL, scheduled_return_ride_id = NULL,
             expires_at = GREATEST(expires_at, now() + make_interval(hours => v_hours))
       WHERE id = v_credit.id;
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (NEW.id, 'vale_reativado', 'system',
              jsonb_build_object('credit_id', v_credit.id, 'motivo', NEW.status));
    ELSE
      -- Ida ainda por fazer: a volta passa a "chamo quando terminar".
      UPDATE public.tvde_roundtrip_credits
         SET return_mode = 'cliente_chama', scheduled_return_ride_id = NULL,
             return_scheduled_at = NULL
       WHERE id = v_credit.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_tvde_roundtrip_reserva_ciclo ON public.tvde_rides;
CREATE TRIGGER tr_tvde_roundtrip_reserva_ciclo
  AFTER UPDATE OF status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_tvde_roundtrip_reserva_ciclo();

-- 5. Expirar vales: nunca um ligado a uma volta marcada viva ---------------------
CREATE OR REPLACE FUNCTION public.tvde_expire_roundtrip_credits()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_count integer;
BEGIN
  WITH expired AS (
    UPDATE public.tvde_roundtrip_credits c
       SET status = 'expirado'
     WHERE c.status = 'ativo'
       AND now() > c.expires_at
       -- 2026-09-23: vale com volta MARCADA e ainda viva não se mata.
       AND NOT EXISTS (
         SELECT 1 FROM public.tvde_rides v
          WHERE v.id = c.scheduled_return_ride_id
            AND v.status IN ('agendada','solicitada','motorista_atribuido',
                             'motorista_a_caminho','motorista_chegou','em_andamento'))
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$function$;

-- 8. Reembolso automático da IDA de um pacote marcado --------------------------
-- Igual à de sempre, mais UMA escolha: se a corrida é a ida de um pacote
-- MARCADO (vale com return_mode), a Edge Fn recebe a acção nova
-- auto_refund_roundtrip_reservation, que devolve o PACOTE inteiro. Tudo o resto
-- (reservas normais) segue exactamente pela auto_refund_reservation de sempre.
CREATE OR REPLACE FUNCTION public.tvde_reservation_auto_refund(p_ride_id uuid, p_motivo text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'net', 'extensions'
AS $function$
DECLARE v_key text; v_url text; v_ride public.tvde_rides;
        v_action text := 'auto_refund_reservation';
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.payment_intent_id IS NULL THEN RETURN false; END IF;
  IF v_ride.payment_status IN ('refunded','partial_refund','kept_cancel_fee') THEN RETURN true; END IF;

  IF v_ride.roundtrip_credit_id IS NOT NULL
     AND NOT COALESCE(v_ride.is_return_leg, false)
     AND EXISTS (SELECT 1 FROM public.tvde_roundtrip_credits c
                  WHERE c.id = v_ride.roundtrip_credit_id AND c.return_mode IS NOT NULL) THEN
    v_action := 'auto_refund_roundtrip_reservation';
  END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  IF v_key IS NULL THEN RETURN false; END IF;
  v_url := COALESCE(v_url,'https://ojykpzwqrtusfeakzrna.supabase.co');

  PERFORM net.http_post(
    url := v_url || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action', v_action,'ride_id', p_ride_id::text, 'motivo', p_motivo));

  INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
    VALUES (p_ride_id,'reserva_reembolso_pedido','system',
            jsonb_build_object('motivo', p_motivo, 'accao', v_action));
  RETURN true;
END; $function$;

-- 7. Reserva paga com a app FECHADA (achado 23/09) --------------------------------
-- Hoje só o polling do cliente (confirm_reservation_payment) activa uma reserva
-- paga. O stripe-webhook marca payment_status='succeeded' mas deixa a reserva em
-- 'aguarda_pagamento' — e aos 15 min o sweep cancela-a (payment_timeout) COM o
-- dinheiro já cobrado e sem reembolso. Quem paga MB Way e fecha a app perde a
-- reserva e o dinheiro. Rede de segurança na base (sem tocar no webhook, que é
-- zona protegida): pagamento confirmado numa reserva à espera → activa-a pelo
-- caminho de sempre. Idempotente com o polling (as duas mark_paid são).
CREATE OR REPLACE FUNCTION public.fn_tvde_reserva_paga_ativa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.payment_status = 'succeeded'
     AND OLD.payment_status IS DISTINCT FROM 'succeeded'
     AND NEW.status = 'agendada'
     AND NEW.reservation_status = 'aguarda_pagamento'
     AND NOT COALESCE(NEW.is_return_leg, false) THEN
    IF NEW.roundtrip_credit_id IS NOT NULL AND NEW.payment_intent_id IS NOT NULL THEN
      PERFORM public.tvde_roundtrip_reservation_mark_paid(NEW.id, NEW.payment_intent_id, NULL);
    ELSE
      PERFORM public.tvde_reservation_mark_paid(NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_tvde_reserva_paga_ativa ON public.tvde_rides;
CREATE TRIGGER tr_tvde_reserva_paga_ativa
  AFTER UPDATE OF payment_status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_tvde_reserva_paga_ativa();
REVOKE ALL ON FUNCTION public.fn_tvde_reserva_paga_ativa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_tvde_roundtrip_reserva_ciclo() FROM PUBLIC, anon, authenticated;

-- 6. Liga o "Marcar para depois" no ida-e-volta da app ---------------------------
INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_roundtrip_reservation_enabled', 'true'::jsonb,
        'Ida-e-volta: mostra "Marcar para depois" no pacote (reserva da ida + volta marcada ou "chamo quando terminar").',
        'tvde')
ON CONFLICT (key) DO UPDATE SET value = 'true'::jsonb;

