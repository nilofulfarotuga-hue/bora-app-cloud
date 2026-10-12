# Bloco 2 — Mudar o DESTINO de uma reserva de corrida (PROPOSTA, não aplicada)

> Missão `reserva-tvde-robo-2026-10-12` · escrito 12/10/2026 pelo Claude Code (PC do Danilo).
>
> ⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.**
> Até ao "vai" nada disto corre em produção: o interruptor
> `tvde_reservation_dest_change_enabled` não existe (= desligado) e a Edge `tvde-dest-change` v3
> recusa com `reservation_dest_change_disabled` antes de gastar Google (provado: HTTP 403 às
> 17:47 UTC com a conta demo).
>
> A bora-tranca recusou gravar isto como `supabase/migrations/20261012190000_PROPOSTA_…sql`
> ("migration que toca tokens/wallet/pagamentos/ledger"). Não se contornou: a proposta fica aqui,
> como relatório, para o Danilo e a Claude.ai decidirem. Quem aplicar grava o SQL abaixo no repo em
> `supabase/migrations/` com o mesmo nome.

## O que já está no ar e espera isto

- Edge `tvde-dest-change` **v3**: acções `reservation_quote` / `reservation_change`
  (morada escrita → Google Geocoding com país PT e viés Guarda → rota origem→destino → RPC).
- Edge `support-chatbot` **v28**: tools `tvde_reservation_dest_quote` / `tvde_reservation_change_dest`
  (pela Edge acima) e playbook `TVDE_RESERVATION_CHANGE`. Com o interruptor desligado o robô diz
  "mudar o destino pelo chat ainda não está disponível".
- App do cliente e painel admin: botão "Mudar destino" só aparece quando o interruptor estiver ligado
  (`TvdeStore.reservationDestChangeEnabled()`); o fluxo de pagamento da diferença reutiliza
  `chargeDestChange` → PaymentSheet / MB Way → `confirmDestChangePayment` (o mesmo da corrida a meio).

## Regras de dinheiro (sem preço nem comissão novos)

| Caso | O que acontece |
|---|---|
| dinheiro, ou diferença 0 | aplica já: destino, km, preço novo, ganho novo; aviso `dest_changed` ao motorista |
| cartão/MB Way **já pago**, diferença **a mais** | linha em `tvde_destination_changes` (`proposta`, `ride_status='agendada'`); cobrança pelo caminho existente `tvde-payment charge_dest_change` (PI próprio) → `confirm_dest_change_payment` → `tvde_dest_change_confirm_paid` (ganha ramo "reserva") → `_tvde_reservation_dest_apply`. Sem pagamento nada muda; o varrimento `sweep_dest_changes` devolve/fecha como hoje |
| cartão/MB Way **já pago**, diferença **a menos** | aplica já e pede a devolução da diferença por `tvde_reservation_auto_refund(p_ride, motivo, p_valor_cents)` → `tvde-payment auto_refund_reservation` com `valor_cents` |
| diferença a mais entre 0,01 € e 0,49 € online | não se cobra (mínimo Stripe 0,50 €): preço fica o antigo |
| `aguarda_pagamento` | recusa `reservation_awaiting_payment` (o PI em curso tem o valor antigo) |
| pacote ida-e-volta, balcão (`agreed_fare_cents`), plano, promo, tokens aplicados | recusa `reservation_dest_change_not_supported` |

Preço recalculado **exactamente** como `tvde_schedule_ride`: `_tvde_km_seguro` → base + km extra × preço/km;
ganho = base do motorista + km extra × ganho/km; preços fixos do cliente
(`tvde_client_fixed_fare_cents` / `tvde_client_fixed_driver_earn_cents`) mandam quando existem
(Ricardo e Vina não são quebrados). Usa-se o **cliente da reserva**, não `auth.uid()`, para o admin
poder mudar sem perder o preço fixo do cliente.

## ⚠️ Alteração necessária na Edge `tvde-payment` (v19 no ar; o repo está em v18 — achado desta missão)

Acção `auto_refund_reservation`:

1. aceitar `valor_cents` (devolução **parcial** da diferença) e `manter_estado: true`: devolve
   `min(valor_cents, amount_received − já devolvido)` no PI da reserva, **não** mexe em
   `payment_status` (continua `succeeded`, para um cancelamento posterior devolver o resto) e grava
   `tvde_ride_events` `reembolso_feito` com o motivo — igual ao que `auto_refund_ride` já faz com
   `valor_cents` e `jaDevolvido`;
2. guarda "nunca mais do que a Stripe recebeu": `pagoCents = Math.min(pagoCents, recebido − jáDevolvido)`
   (como em `auto_refund_ride`). Hoje, se `est_fare_cents` subiu por uma diferença paga noutro PI, o
   cancelamento pediria à Stripe mais do que o PI original recebeu e a chamada rebentava sem registo.

Sem o ponto 1, a devolução da diferença fica só **pedida** (evento `reserva_reembolso_pedido` +
linha em `tvde_destination_changes` com `refund_cents` e `refunded_at NULL`) e o Danilo devolve à mão
na Stripe. O repo da `tvde-payment` deve primeiro ser posto igual ao ar (v19) antes de se editar.

## Prova

- `deno check` limpo nas Edge `tvde-dest-change` v3 e `support-chatbot` v28 (no ar).
- Interruptor desligado → `reservation_quote` devolve 403 `reservation_dest_change_disabled` (conta demo, 17:47 UTC).
- A prova das RPCs em transação revertida **não foi feita em produção**: a bora-tranca lê
  `UPDATE public.tvde_rides` no corpo das funções e recusa (`apply_migration` e `Write`). Fica para
  quem aplicar: correr este SQL numa transação com `set_config('request.jwt.claims', …)` do cliente
  demo e `RAISE EXCEPTION` no fim, como nas provas de 2026-10-12 da migração da hora.

## SQL da proposta

```sql
-- =============================================================================
-- RESERVA DE CORRIDA (TVDE): mudar o DESTINO (e o preço) de uma corrida marcada
-- Missão reserva-tvde-robo-2026-10-12, Bloco 2. Nome sugerido:
-- supabase/migrations/20261012190000_tvde_reserva_mudar_destino.sql
-- =============================================================================

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_reservation_dest_change_enabled', 'false'::jsonb,
        'Reserva de corrida: cliente/robô/admin pode mudar o destino (recalcula preço; cartão/MB Way cobra ou devolve a diferença). Nasce desligado.',
        'tvde')
ON CONFLICT (key) DO NOTHING;

-- 1. Contas — igual a tvde_schedule_ride, com o cliente DA RESERVA.
CREATE OR REPLACE FUNCTION public._tvde_reservation_dest_calc(
  p_ride public.tvde_rides, p_dest_lat double precision, p_dest_lng double precision, p_km numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_km numeric; v_base_km int; v_perkm int; v_extra_km int;
  v_fare int; v_d_base int; v_d_perkm int; v_drv int;
  v_fixed int; v_fixed_drv int;
BEGIN
  v_km := public._tvde_km_seguro(p_ride.origin_lat, p_ride.origin_lng, p_dest_lat, p_dest_lng, p_km);
  v_base_km := (public.get_setting('tvde_base_distance_km') #>> '{}')::int;
  v_perkm   := (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(v_km - v_base_km))::int;
  v_fare := (public.get_setting('tvde_base_fare_cents') #>> '{}')::int + v_extra_km * v_perkm;
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_drv := v_d_base + v_extra_km * v_d_perkm;
  v_fixed := public.tvde_client_fixed_fare_cents(p_ride.client_id, v_km);
  IF v_fixed IS NOT NULL THEN v_fare := v_fixed; END IF;
  v_fixed_drv := public.tvde_client_fixed_driver_earn_cents(p_ride.client_id, v_km);
  IF v_fixed_drv IS NOT NULL THEN v_drv := v_fixed_drv; END IF;

  RETURN jsonb_build_object(
    'km_before', COALESCE(p_ride.est_distance_km, 0), 'km_new', v_km,
    'price_before_cents', COALESCE(p_ride.est_fare_cents, 0), 'price_new_cents', v_fare,
    'client_diff_cents', v_fare - COALESCE(p_ride.est_fare_cents, 0),
    'driver_before_cents', COALESCE(p_ride.driver_earn_cents, 0), 'driver_new_cents', v_drv,
    'driver_diff_cents', v_drv - COALESCE(p_ride.driver_earn_cents, 0),
    'fixed_fare_override_cents', v_fixed, 'fixed_driver_earn_override_cents', v_fixed_drv,
    'formula', jsonb_build_object(
       'tarifa_base_cents', (public.get_setting('tvde_base_fare_cents') #>> '{}')::int,
       'km_incluidos', v_base_km, 'preco_km_extra_cents', v_perkm));
END $function$;
REVOKE ALL ON FUNCTION public._tvde_reservation_dest_calc(public.tvde_rides, double precision, double precision, numeric) FROM PUBLIC, anon, authenticated;

-- 2. Guardas (cotação e mudança)
CREATE OR REPLACE FUNCTION public._tvde_reservation_dest_check(p_ride public.tvde_rides)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT COALESCE((public.get_setting('tvde_reservation_dest_change_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'reservation_dest_change_disabled'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_ride.client_id <> auth.uid() AND NOT public.is_admin() THEN RAISE EXCEPTION 'reservation_not_yours'; END IF;
  IF p_ride.scheduled_at IS NULL OR p_ride.status <> 'agendada' THEN RAISE EXCEPTION 'too_late_to_change'; END IF;
  IF p_ride.reservation_status = 'aguarda_pagamento' THEN RAISE EXCEPTION 'reservation_awaiting_payment'; END IF;
  IF p_ride.roundtrip_credit_id IS NOT NULL OR p_ride.agreed_fare_cents IS NOT NULL
     OR COALESCE(p_ride.used_subscription_ride, false) OR p_ride.promo_credit_id IS NOT NULL
     OR COALESCE(p_ride.tokens_applied_count, 0) > 0 THEN
    RAISE EXCEPTION 'reservation_dest_change_not_supported'; END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_destination_changes
              WHERE ride_id = p_ride.id AND estado = 'proposta' AND payment_intent_id IS NOT NULL) THEN
    RAISE EXCEPTION 'dest_change_payment_in_progress'; END IF;
END $function$;
REVOKE ALL ON FUNCTION public._tvde_reservation_dest_check(public.tvde_rides) FROM PUBLIC, anon, authenticated;

-- 3. Cotação (não grava nada)
CREATE OR REPLACE FUNCTION public.tvde_reservation_dest_quote(
  p_ride uuid, p_dest_lat double precision, p_dest_lng double precision,
  p_dest_label text DEFAULT NULL, p_est_distance_km numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_r public.tvde_rides; v_calc jsonb; v_diff int; v_online boolean;
BEGIN
  SELECT * INTO v_r FROM public.tvde_rides WHERE id = p_ride;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  PERFORM public._tvde_reservation_dest_check(v_r);
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  v_calc := public._tvde_reservation_dest_calc(v_r, p_dest_lat, p_dest_lng, p_est_distance_km);
  IF (v_calc->>'km_new')::numeric > 300 THEN RAISE EXCEPTION 'dest_too_far'; END IF;
  v_diff := (v_calc->>'client_diff_cents')::int;
  v_online := v_r.payment_method IN ('card','mbway') AND v_r.payment_status = 'succeeded';
  IF v_online AND v_diff > 0 AND v_diff < 50 THEN
    v_calc := v_calc || jsonb_build_object('price_new_cents', v_r.est_fare_cents, 'client_diff_cents', 0,
      'driver_new_cents', v_r.driver_earn_cents, 'driver_diff_cents', 0, 'abaixo_minimo_stripe', true);
    v_diff := 0;
  END IF;
  RETURN v_calc || jsonb_build_object('ride_id', v_r.id, 'dest_label', p_dest_label,
    'payment_method', COALESCE(v_r.payment_method, 'cash'), 'paid_online', v_online,
    'needs_payment', (v_online AND v_diff > 0),
    'refund_cents', CASE WHEN v_online AND v_diff < 0 THEN -v_diff ELSE 0 END);
END $function$;
REVOKE ALL ON FUNCTION public.tvde_reservation_dest_quote(uuid, double precision, double precision, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_reservation_dest_quote(uuid, double precision, double precision, text, numeric) TO authenticated, service_role;

-- 4. Aplicar (destino, km, preço, ganho, evento, aviso ao motorista)
CREATE OR REPLACE FUNCTION public._tvde_reservation_dest_apply(
  p_ride uuid, p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_calc jsonb, p_actor text, p_change_id uuid DEFAULT NULL, p_method text DEFAULT 'nenhum')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE v_r public.tvde_rides; v_old_label text; v_diff int; v_drv_diff int; v_jwt text; v_online boolean;
BEGIN
  SELECT * INTO v_r FROM public.tvde_rides WHERE id = p_ride FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  v_old_label := v_r.dest_label;
  v_diff := (p_calc->>'client_diff_cents')::int;
  v_drv_diff := (p_calc->>'driver_diff_cents')::int;
  v_online := p_method IN ('card','mbway') AND v_diff > 0;

  UPDATE public.tvde_rides SET
    dest_lat = p_dest_lat, dest_lng = p_dest_lng, dest_label = p_dest_label,
    est_distance_km = (p_calc->>'km_new')::numeric,
    est_fare_cents = (p_calc->>'price_new_cents')::int,
    driver_earn_cents = (p_calc->>'driver_new_cents')::int,
    bora_cut_cents = (p_calc->>'price_new_cents')::int - (p_calc->>'driver_new_cents')::int,
    dest_change_count = COALESCE(dest_change_count, 0) + 1,
    dest_change_fee_cents = COALESCE(dest_change_fee_cents, 0) + CASE WHEN v_online THEN v_diff ELSE 0 END,
    dest_change_driver_cents = COALESCE(dest_change_driver_cents, 0) + CASE WHEN v_online THEN v_drv_diff ELSE 0 END,
    updated_at = now()
  WHERE id = p_ride RETURNING * INTO v_r;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (p_ride, 'reserva_destino_alterado', p_actor, jsonb_build_object(
    'old_dest_label', v_old_label, 'new_dest_label', p_dest_label,
    'km_before', p_calc->'km_before', 'km_new', p_calc->'km_new',
    'price_before_cents', p_calc->'price_before_cents', 'price_new_cents', p_calc->'price_new_cents',
    'client_diff_cents', v_diff, 'driver_diff_cents', v_drv_diff,
    'fixed_fare_override_cents', p_calc->'fixed_fare_override_cents',
    'method', p_method, 'change_id', p_change_id, 'motorista', v_r.reservation_driver_id));

  IF v_r.reservation_driver_id IS NOT NULL THEN
    BEGIN
      v_jwt := public._dispatch_jwt();
      PERFORM net.http_post(
        url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-driver',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_jwt),
        body    := jsonb_build_object('kind','dest_changed',
                     'driverId', v_r.reservation_driver_id::text, 'rideId', v_r.id::text,
                     'destLabel', p_dest_label, 'driverDiffCents', v_drv_diff, 'paidOnline', v_online));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride, 'push_falhou', 'system', jsonb_build_object('kind', 'dest_changed', 'erro', SQLERRM));
    END;
  END IF;

  RETURN jsonb_build_object('estado', 'aplicada', 'applied', true,
    'est_fare_cents', v_r.est_fare_cents, 'est_distance_km', v_r.est_distance_km,
    'driver_earn_cents', v_r.driver_earn_cents, 'client_diff_cents', v_diff, 'driver_diff_cents', v_drv_diff);
END $function$;
REVOKE ALL ON FUNCTION public._tvde_reservation_dest_apply(uuid, double precision, double precision, text, jsonb, text, uuid, text) FROM PUBLIC, anon, authenticated;

-- 5. Devolução parcial pelo caminho das reservas (assinatura nova, 3 argumentos;
--    a de 2 argumentos, do cancelamento, fica intacta)
CREATE OR REPLACE FUNCTION public.tvde_reservation_auto_refund(p_ride_id uuid, p_motivo text, p_valor_cents integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'net', 'extensions'
AS $function$
DECLARE v_key text; v_url text; v_ride public.tvde_rides;
BEGIN
  IF p_valor_cents IS NULL OR p_valor_cents <= 0 THEN RETURN false; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND OR v_ride.payment_intent_id IS NULL THEN RETURN false; END IF;
  IF v_ride.payment_status <> 'succeeded' THEN RETURN false; END IF;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  IF v_key IS NULL THEN RETURN false; END IF;
  v_url := COALESCE(v_url,'https://ojykpzwqrtusfeakzrna.supabase.co');
  PERFORM net.http_post(
    url := v_url || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action', 'auto_refund_reservation', 'ride_id', p_ride_id::text,
                               'motivo', p_motivo, 'valor_cents', p_valor_cents, 'manter_estado', true));
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'reserva_reembolso_pedido', 'system',
            jsonb_build_object('motivo', p_motivo, 'accao', 'auto_refund_reservation', 'valor_cents', p_valor_cents, 'parcial', true));
  RETURN true;
END; $function$;
REVOKE ALL ON FUNCTION public.tvde_reservation_auto_refund(uuid, text, integer) FROM PUBLIC, anon, authenticated;

-- 6. Mudar o destino
CREATE OR REPLACE FUNCTION public.tvde_reservation_change_dest(
  p_ride uuid, p_dest_lat double precision, p_dest_lng double precision,
  p_dest_label text DEFAULT NULL, p_est_distance_km numeric DEFAULT 0,
  p_expected_client_diff_cents integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_r public.tvde_rides; v_calc jsonb; v_diff int; v_online boolean; v_actor text;
  v_ch public.tvde_destination_changes; v_res jsonb;
BEGIN
  SELECT * INTO v_r FROM public.tvde_rides WHERE id = p_ride FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  PERFORM public._tvde_reservation_dest_check(v_r);
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  v_calc := public._tvde_reservation_dest_calc(v_r, p_dest_lat, p_dest_lng, p_est_distance_km);
  IF (v_calc->>'km_new')::numeric > 300 THEN RAISE EXCEPTION 'dest_too_far'; END IF;
  v_online := v_r.payment_method IN ('card','mbway') AND v_r.payment_status = 'succeeded';
  v_diff := (v_calc->>'client_diff_cents')::int;
  IF v_online AND v_diff > 0 AND v_diff < 50 THEN
    v_calc := v_calc || jsonb_build_object('price_new_cents', v_r.est_fare_cents, 'client_diff_cents', 0,
      'driver_new_cents', v_r.driver_earn_cents, 'driver_diff_cents', 0, 'abaixo_minimo_stripe', true);
    v_diff := 0;
  END IF;
  IF p_expected_client_diff_cents IS NOT NULL AND p_expected_client_diff_cents <> v_diff THEN
    RAISE EXCEPTION 'dest_change_price_changed: %', v_diff; END IF;
  v_actor := CASE WHEN v_r.client_id = auth.uid() THEN 'client' ELSE 'admin' END;

  -- (a) cartão/MB Way já pago, diferença A MAIS: proposta; cobra-se pelo caminho existente
  IF v_online AND v_diff > 0 THEN
    UPDATE public.tvde_destination_changes SET estado = 'recusada', motivo = 'substituida', updated_at = now()
     WHERE ride_id = v_r.id AND estado = 'proposta' AND payment_intent_id IS NULL;
    INSERT INTO public.tvde_destination_changes (ride_id, client_id, driver_id, ride_status,
      old_dest_lat, old_dest_lng, old_dest_label, new_dest_lat, new_dest_lng, new_dest_label,
      km_done, km_remaining, km_new_total, km_before, price_before_cents, price_new_cents, table_diff_cents,
      client_diff_cents, driver_before_cents, driver_new_cents, driver_table_diff_cents, driver_diff_cents,
      min_applied, driver_min_applied, method, estado, created_by, created_by_role)
    VALUES (v_r.id, v_r.client_id, v_r.reservation_driver_id, 'agendada',
      v_r.dest_lat, v_r.dest_lng, v_r.dest_label, p_dest_lat, p_dest_lng, p_dest_label,
      0, (v_calc->>'km_new')::numeric, (v_calc->>'km_new')::numeric, (v_calc->>'km_before')::numeric,
      (v_calc->>'price_before_cents')::int, (v_calc->>'price_new_cents')::int, v_diff, v_diff,
      (v_calc->>'driver_before_cents')::int, (v_calc->>'driver_new_cents')::int,
      (v_calc->>'driver_diff_cents')::int, (v_calc->>'driver_diff_cents')::int,
      false, false, v_r.payment_method, 'proposta', auth.uid(),
      CASE v_actor WHEN 'client' THEN 'cliente' ELSE 'admin' END)
    RETURNING * INTO v_ch;
    RETURN v_calc || jsonb_build_object('change_id', v_ch.id, 'estado', 'proposta',
      'needs_payment', true, 'paid_online', true, 'method', v_r.payment_method);
  END IF;

  -- (b) cartão/MB Way já pago, diferença A MENOS: aplica já e pede a devolução da diferença
  IF v_online AND v_diff < 0 THEN
    v_res := public._tvde_reservation_dest_apply(p_ride, p_dest_lat, p_dest_lng, p_dest_label, v_calc, v_actor, NULL, v_r.payment_method);
    INSERT INTO public.tvde_destination_changes (ride_id, client_id, driver_id, ride_status,
      old_dest_lat, old_dest_lng, old_dest_label, new_dest_lat, new_dest_lng, new_dest_label,
      km_done, km_remaining, km_new_total, km_before, price_before_cents, price_new_cents, table_diff_cents,
      client_diff_cents, driver_before_cents, driver_new_cents, driver_table_diff_cents, driver_diff_cents,
      min_applied, driver_min_applied, method, estado, created_by, created_by_role, applied_at,
      refund_cents, refund_motivo)
    VALUES (v_r.id, v_r.client_id, v_r.reservation_driver_id, 'agendada',
      v_r.dest_lat, v_r.dest_lng, v_r.dest_label, p_dest_lat, p_dest_lng, p_dest_label,
      0, (v_calc->>'km_new')::numeric, (v_calc->>'km_new')::numeric, (v_calc->>'km_before')::numeric,
      (v_calc->>'price_before_cents')::int, (v_calc->>'price_new_cents')::int, v_diff, v_diff,
      (v_calc->>'driver_before_cents')::int, (v_calc->>'driver_new_cents')::int,
      (v_calc->>'driver_diff_cents')::int, (v_calc->>'driver_diff_cents')::int,
      false, false, v_r.payment_method, 'aplicada', auth.uid(),
      CASE v_actor WHEN 'client' THEN 'cliente' ELSE 'admin' END, now(),
      -v_diff, 'reserva: destino mais perto, devolucao da diferenca')
    RETURNING * INTO v_ch;
    PERFORM public.tvde_reservation_auto_refund(p_ride,
      'destino mais perto: devolucao da diferenca (' || (-v_diff) || ' centimos)', -v_diff);
    RETURN v_calc || v_res || jsonb_build_object('change_id', v_ch.id, 'needs_payment', false,
      'paid_online', true, 'refund_cents', -v_diff, 'refund_requested', true, 'method', v_r.payment_method);
  END IF;

  -- (c) dinheiro, ou diferença 0: aplica já
  v_res := public._tvde_reservation_dest_apply(p_ride, p_dest_lat, p_dest_lng, p_dest_label, v_calc, v_actor, NULL,
             CASE WHEN v_diff = 0 THEN 'nenhum' ELSE COALESCE(v_r.payment_method, 'cash') END);
  RETURN v_calc || v_res || jsonb_build_object('needs_payment', false, 'paid_online', v_online,
    'method', CASE WHEN v_diff = 0 THEN 'nenhum' ELSE COALESCE(v_r.payment_method, 'cash') END);
END $function$;
REVOKE ALL ON FUNCTION public.tvde_reservation_change_dest(uuid, double precision, double precision, text, numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_reservation_change_dest(uuid, double precision, double precision, text, numeric, integer) TO authenticated, service_role;

-- 7. tvde_dest_change_confirm_paid — ganha o ramo RESERVA (mesma assinatura). Para
--    corridas a meio NADA muda (continua a chamar _tvde_dest_change_apply).
CREATE OR REPLACE FUNCTION public.tvde_dest_change_confirm_paid(p_change_id uuid, p_payment_intent_id text, p_amount_cents integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ch public.tvde_destination_changes; v_r public.tvde_rides; v_calc jsonb; v_res jsonb;
BEGIN
  SELECT * INTO v_ch FROM public.tvde_destination_changes WHERE id = p_change_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'dest_change_not_found'; END IF;
  IF v_ch.estado = 'aplicada' THEN
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'aplicada', 'already', true); END IF;
  IF v_ch.estado <> 'proposta' THEN
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', v_ch.estado, 'refund', true); END IF;
  IF v_ch.payment_intent_id IS DISTINCT FROM p_payment_intent_id THEN RAISE EXCEPTION 'pi_mismatch'; END IF;
  IF p_amount_cents <> v_ch.client_diff_cents THEN RAISE EXCEPTION 'amount_mismatch'; END IF;
  UPDATE public.tvde_destination_changes SET estado = 'paga', paid_at = now(), updated_at = now()
   WHERE id = v_ch.id;

  IF v_ch.ride_status = 'agendada' THEN
    SELECT * INTO v_r FROM public.tvde_rides WHERE id = v_ch.ride_id FOR UPDATE;
    IF v_r.status <> 'agendada' OR v_r.scheduled_at IS NULL THEN
      UPDATE public.tvde_destination_changes SET estado = 'falhada', motivo = 'reserva_' || v_r.status, updated_at = now()
       WHERE id = v_ch.id;
      RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'falhada', 'motivo', 'reserva_' || v_r.status);
    END IF;
    IF COALESCE(v_r.est_fare_cents, 0) <> v_ch.price_before_cents THEN
      UPDATE public.tvde_destination_changes SET estado = 'falhada', motivo = 'reserva_mudou', updated_at = now()
       WHERE id = v_ch.id;
      RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'falhada', 'motivo', 'reserva_mudou');
    END IF;
    v_calc := jsonb_build_object('km_before', v_ch.km_before, 'km_new', v_ch.km_new_total,
      'price_before_cents', v_ch.price_before_cents, 'price_new_cents', v_ch.price_new_cents,
      'client_diff_cents', v_ch.client_diff_cents, 'driver_before_cents', v_ch.driver_before_cents,
      'driver_new_cents', v_ch.driver_new_cents, 'driver_diff_cents', v_ch.driver_diff_cents);
    v_res := public._tvde_reservation_dest_apply(v_ch.ride_id, v_ch.new_dest_lat, v_ch.new_dest_lng, v_ch.new_dest_label,
               v_calc, COALESCE(v_ch.created_by_role, 'cliente'), v_ch.id, v_ch.method);
    UPDATE public.tvde_destination_changes SET estado = 'aplicada', applied_at = now(), updated_at = now(), pricing_branch = 'reserva'
     WHERE id = v_ch.id;
    RETURN jsonb_build_object('change_id', v_ch.id, 'estado', 'aplicada') || v_res;
  END IF;

  RETURN public._tvde_dest_change_apply(v_ch.id);
END $function$;
```

## PARA O DANILO (decisões que só ele dá)

1. **"Vai" para aplicar o SQL acima** (liga só depois `tvde_reservation_dest_change_enabled = true`).
2. **"Vai" para a alteração na `tvde-payment`** (devolução parcial com `valor_cents` + guarda do
   `amount_received`). Sem ela, a devolução de "destino mais perto" fica pedida e faz-se à mão.
3. Se preferir **não devolver** quando o destino novo é mais perto (regra da corrida a meio: "mais
   perto não devolve"), basta trocar o ramo (b) por "aplica com diferença 0" — diz, e eu mudo.
