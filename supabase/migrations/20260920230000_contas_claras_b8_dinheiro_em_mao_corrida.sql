-- 2026-09-20 — CONTAS CLARAS · Bloco 8 — O DINHEIRO EM MÃO DE CADA CORRIDA FICA GRAVADO NA CORRIDA.
--
-- CAUSA PROVADA (Bloco 7, lido em pg_proc e nos registos a 20/09 22h20):
--   `final_fare_cents` nunca foi "o que o passageiro pagou". Em tvde_finish_ride:
--     · ida de pacote pré-pago (linha 71):  v_fare := v_stops_fee            → 0 sem paragens;
--     · volta de pacote (linha 66):        v_fare := v_stops_fee + extra_km  → 0 normalmente;
--     · corrida coberta por plano (80/85): v_fare := v_stops_fee            → 0.
--   O preço do pacote vive em tvde_roundtrip_credits.paid_cents e o do plano em
--   tvde_subscriptions. Só a corrida normal grava a tarifa na própria linha.
--   Das 17 corridas "sem tarifa": 10 são VOLTAS de pacote (não há dinheiro a mudar de mão —
--   0 é o valor certo), 1 é coberta por plano (idem), e as restantes são IDAS de pacote pagas
--   a dinheiro — aí o motorista recebeu os 8,00 € do pacote e a corrida diz 0.
--   Consequência da regra "tarifa em falta = ganho + corte" (aplicada às 21h): em 13 corridas
--   o acerto passa a cobrar dinheiro que nunca foi recebido (3,50 € por cada volta; 4,00 € num
--   plano) e a cobrar 4,50 € em vez de 8,00 € nas idas a dinheiro. Danilo: +68,00 € a mais.
--   Regra "tarifa = ganho + corte" só vale para corridas normais: nos pacotes falta a reserva
--   da volta (3,50 €) e nos planos o ganho vem do plano, não da tarifa (as 5 corridas antigas
--   do Bloco 10 são exactamente isso — nada a corrigir).
--
-- DECISÃO (Bloco 8): não se recusa fechar a corrida — o passageiro está a sair do carro e
-- recusar o fecho pára o motorista sem lhe dar nada em troca. Em vez disso, ao ficar
-- 'finalizada' a corrida passa a levar gravado `cash_in_hand_cents` — o dinheiro que o
-- motorista recebeu em mão nessa corrida, pela MESMA regra que o servidor já usa para o
-- saldo (pacote pago a dinheiro na ida, 0 na volta, 0 no plano, tarifa na corrida normal,
-- só as paragens/extras em dinheiro nas corridas pagas na app) — e, no único caso em que
-- não há como saber (corrida normal a dinheiro com tarifa a zero), deduz-se ganho + corte,
-- marca-se `fare_deduced = true` e escreve-se um achado para o vigia gritar.
-- Gatilho DIFERIDO ao commit, para correr depois de tvde_finish_ride ter escrito o evento.
--
-- Quem lê `cash_in_hand_cents`: o extrato (_prestador_trabalhos) e — depois do "vai", porque a
-- Trava recusa DDL na função do acerto — o próprio acerto semanal (PROPOSTA em
-- staged_contas_claras_20260920_b8).

ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS cash_in_hand_cents integer,
  ADD COLUMN IF NOT EXISTS fare_deduced boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tvde_rides.cash_in_hand_cents IS
  'Contas claras (20/09/2026): dinheiro que o motorista recebeu EM MÃO nesta corrida. Pacote pago a dinheiro: os cêntimos do pacote na ida, 0 na volta; plano: 0; corrida normal a dinheiro: a tarifa; paga na app: só paragens/extras em dinheiro. Gravado pelo gatilho ao ficar finalizada.';
COMMENT ON COLUMN public.tvde_rides.fare_deduced IS
  'true quando a corrida ficou finalizada a dinheiro sem tarifa gravada e o valor em mão foi deduzido (ganho + corte). O vigia grita por cada uma.';

-- 1) a regra, num sítio só -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tvde_ride_cash_in_hand(p_ride_id uuid)
RETURNS TABLE (cash_in_hand_cents integer, deduced boolean, regra text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r        public.tvde_rides%ROWTYPE;
  v_meta   jsonb;
  v_pm     text;
  v_stops  integer := 0;
  v_extra  integer := 0;
  v_credit record;
BEGIN
  SELECT * INTO r FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_pm := COALESCE(r.payment_method, 'cash');
  SELECT e.meta INTO v_meta FROM public.tvde_ride_events e
   WHERE e.ride_id = p_ride_id AND e.status = 'finalizada' ORDER BY e.at DESC LIMIT 1;
  v_stops := COALESCE((v_meta->>'stops_cash_cents')::int, 0);
  v_extra := COALESCE((v_meta->>'return_extra_fare_cents')::int, 0);

  IF r.roundtrip_credit_id IS NOT NULL THEN
    SELECT c.paid_cents, (c.payment_intent_id IS NULL) AS pago_a_dinheiro INTO v_credit
      FROM public.tvde_roundtrip_credits c WHERE c.id = r.roundtrip_credit_id;
    IF COALESCE(r.is_return_leg, false) THEN
      RETURN QUERY SELECT (CASE WHEN v_pm = 'cash' THEN v_stops + v_extra ELSE v_stops END), false, 'pacote_volta';
    ELSE
      RETURN QUERY SELECT (CASE WHEN COALESCE(v_credit.pago_a_dinheiro, v_pm = 'cash') THEN COALESCE(v_credit.paid_cents, 0) ELSE 0 END) + v_stops, false, 'pacote_ida';
    END IF;
    RETURN;
  END IF;

  IF COALESCE(r.used_subscription_ride, false) THEN
    RETURN QUERY SELECT v_stops, false, 'plano';
    RETURN;
  END IF;

  IF v_pm = 'cash' THEN
    IF COALESCE(r.final_fare_cents, 0) > 0 THEN
      RETURN QUERY SELECT r.final_fare_cents, false, 'normal_dinheiro';
    ELSE
      RETURN QUERY SELECT COALESCE(r.driver_earn_cents, 0) + COALESCE(r.bora_cut_cents, 0), true, 'normal_dinheiro_sem_tarifa_deduzida';
    END IF;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_stops, false, 'paga_na_app';
END;
$$;

REVOKE ALL ON FUNCTION public.tvde_ride_cash_in_hand(uuid) FROM PUBLIC, anon, authenticated;  -- só o servidor (gatilho, extrato, acerto)

-- 2) o gatilho: ao ficar finalizada, grava o dinheiro em mão (diferido ao commit) ----------
CREATE OR REPLACE FUNCTION public._tvde_ride_zz_dinheiro_em_mao()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v record;
  v_novo uuid;
  v_nome text;
BEGIN
  IF NEW.status <> 'finalizada' THEN RETURN NULL; END IF;
  SELECT * INTO v FROM public.tvde_ride_cash_in_hand(NEW.id);
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE public.tvde_rides
     SET cash_in_hand_cents = v.cash_in_hand_cents,
         fare_deduced       = v.deduced
   WHERE id = NEW.id
     AND (cash_in_hand_cents IS DISTINCT FROM v.cash_in_hand_cents OR fare_deduced IS DISTINCT FROM v.deduced);
  IF v.deduced THEN
    INSERT INTO public.payment_reconciliation_findings (kind, severity, entity_type, entity_id, pi_id, amount_cents, details)
    VALUES ('vigia_corrida_tarifa_deduzida', 'warning', 'tvde_ride', NEW.id::text, 'tvde_ride:' || NEW.id::text,
            v.cash_in_hand_cents,
            jsonb_build_object('quem', NEW.driver_id, 'pedido', NEW.id, 'regra', v.regra,
                               'nota', 'corrida a dinheiro finalizada sem tarifa gravada; dinheiro em mão deduzido = ganho + corte'))
    ON CONFLICT (kind, pi_id, entity_id) DO NOTHING
    RETURNING id INTO v_novo;
    IF v_novo IS NOT NULL THEN
      SELECT d.name INTO v_nome FROM public.drivers d WHERE d.user_id = NEW.driver_id OR d.id = NEW.driver_id LIMIT 1;
      BEGIN
        PERFORM public._telegram_admin(
          '🔎 VIGIA DO DINHEIRO — corrida a dinheiro fechada SEM tarifa gravada: ' || COALESCE(v_nome, NEW.driver_id::text)
          || ', corrida ' || left(NEW.id::text, 8) || '. Valor em mão deduzido (ganho + parte da Bora): '
          || replace((v.cash_in_hand_cents / 100.0)::numeric(12,2)::text, '.', ',') || ' €. Confirma com o motorista quanto recebeu.');
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tvde_ride_zz_dinheiro_em_mao' AND tgrelid = 'public.tvde_rides'::regclass) THEN
    EXECUTE 'CREATE CONSTRAINT TRIGGER trg_tvde_ride_zz_dinheiro_em_mao AFTER INSERT OR UPDATE OF status ON public.tvde_rides DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._tvde_ride_zz_dinheiro_em_mao()';
  END IF;
END
$do$;

-- 3) backfill das corridas já finalizadas (colunas derivadas; tarifa/ganho/corte intocados) --
DO $do$
DECLARE r record; v record; n int := 0; nd int := 0;
BEGIN
  FOR r IN SELECT id FROM public.tvde_rides WHERE status = 'finalizada' LOOP
    SELECT * INTO v FROM public.tvde_ride_cash_in_hand(r.id);
    UPDATE public.tvde_rides SET cash_in_hand_cents = v.cash_in_hand_cents, fare_deduced = v.deduced WHERE id = r.id;
    n := n + 1; IF v.deduced THEN nd := nd + 1; END IF;
  END LOOP;
  RAISE NOTICE 'backfill: % corridas, % deduzidas', n, nd;
END
$do$;

-- 4) o extrato passa a ler o dinheiro em mão da corrida ---------------------------------
CREATE OR REPLACE FUNCTION public._prestador_trabalhos(p_uid uuid, p_de timestamptz)
RETURNS TABLE (
  tipo text, ref_id text, quando timestamptz, descricao text, de text, para text,
  pagamento text, cliente_pagou_cents integer, ganhou_cents integer, parte_bora_cents integer,
  pagou_na_loja_cents integer, recebeu_em_mao_cents integer, fica_para_a_bora_cents integer,
  acerto_cents integer, distancia_km numeric, tokens integer, parcelas jsonb,
  entra_no_acerto boolean, nota text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT 'entrega'::text,
         o.id::text,
         COALESCE(o.delivered_at, o.status_updated_at, o.created_at),
         (CASE WHEN o.service_type IN ('storeShopping','carryGroceries','sendPackage') THEN 'Favor · ' ELSE 'Entrega · ' END)
           || COALESCE(NULLIF(o.vendor_name,''), NULLIF(o.pickup_address,''), 'Pedido'),
         COALESCE(NULLIF(o.pickup_address,''), o.vendor_name, ''),
         COALESCE(o.dropoff_address, ''),
         o.payment_method,
         ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int,
         ROUND(COALESCE(o.driver_earnings, 0) * 100)::int,
         ROUND(COALESCE(o.platform_commission, 0) * 100)::int,
         ROUND(public.order_driver_reimbursement(o.id) * 100)::int,
         CASE WHEN o.payment_method = 'cash' THEN ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int ELSE 0 END,
         CASE WHEN o.payment_method = 'cash'
              THEN COALESCE(
                     (SELECT ROUND(dt.amount * 100)::int FROM public.driver_transactions dt
                       WHERE dt.order_id::text = o.id AND dt.type = 'cash_adjustment' LIMIT 1),
                     ROUND((COALESCE(o.final_total, o.price, 0) - COALESCE(o.driver_earnings, 0)
                            - public.order_driver_reimbursement(o.id)) * 100)::int)
              ELSE 0 END,
         CASE WHEN o.payment_method = 'cash'
              THEN COALESCE(
                     (SELECT ROUND(dt.amount * 100)::int FROM public.driver_transactions dt
                       WHERE dt.order_id::text = o.id AND dt.type = 'cash_adjustment' LIMIT 1),
                     ROUND((COALESCE(o.final_total, o.price, 0) - COALESCE(o.driver_earnings, 0)
                            - public.order_driver_reimbursement(o.id)) * 100)::int)
              ELSE -(ROUND(COALESCE(o.driver_earnings, 0) * 100)::int) END,
         o.distance_km,
         COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                    WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id), 0)::int,
         (SELECT jsonb_agg(p) FROM (
            SELECT jsonb_build_object('nome', 'Ganho da entrega' ||
                     CASE WHEN o.distance_km IS NOT NULL THEN ' (' || replace(ROUND(o.distance_km, 1)::text, '.', ',') || ' km)' ELSE '' END,
                     'valor_cents', ROUND(COALESCE(o.driver_earnings, 0) * 100)::int) AS p
            UNION ALL
            SELECT jsonb_build_object('nome', 'Gorjeta do cliente', 'valor_cents', o.tip_amount_cents, 'informativo', true)
             WHERE COALESCE(o.tip_amount_cents, 0) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Adiantou na loja (talão)', 'valor_cents', ROUND(public.order_driver_reimbursement(o.id) * 100)::int)
             WHERE public.order_driver_reimbursement(o.id) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Tokens ganhos', 'valor_cents', NULL, 'tokens',
                     COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                                WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id), 0)::int)
             WHERE EXISTS (SELECT 1 FROM public.bora_tokens t WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id)
         ) s),
         true,
         NULL::text
    FROM public.orders o
   WHERE o.assigned_driver_id = p_uid::text
     AND o.status = 'delivered'
     AND COALESCE(o.delivered_at, o.status_updated_at, o.created_at) >= p_de
     AND COALESCE(o.is_test_order, false) = false

  UNION ALL

  SELECT 'compensacao'::text,
         l.order_id::text,
         l.created_at,
         'Compensação · pedido cancelado depois de aceite' || COALESCE(' · ' || NULLIF(o.vendor_name, ''), ''),
         COALESCE(o.pickup_address, o.vendor_name, ''),
         COALESCE(o.dropoff_address, ''),
         NULL::text,
         0, ROUND(l.amount * 100)::int, 0, 0, 0, 0,
         -(ROUND(l.amount * 100)::int),
         NULL::numeric, 0,
         jsonb_build_array(jsonb_build_object('nome', 'Compensação de cancelamento', 'valor_cents', ROUND(l.amount * 100)::int)),
         false,
         'Está no livro-razão e aqui; ainda não entra no acerto semanal (achado contas-claras 20/09/2026).'
    FROM public.ledger_entries l
    LEFT JOIN public.orders o ON o.id = l.order_id::text
   WHERE l.user_type = 'driver' AND l.type = 'earning'
     AND l.user_id = p_uid::text
     AND l.created_at >= p_de
     AND (o.id IS NULL OR o.status <> 'delivered')

  UNION ALL

  SELECT 'corrida'::text,
         r.id::text,
         r.updated_at,
         'Corrida · ' || COALESCE(NULLIF(r.origin_label, ''), 'Origem') || ' → ' || COALESCE(NULLIF(r.dest_label, ''), 'Destino')
           || CASE WHEN r.roundtrip_credit_id IS NOT NULL THEN (CASE WHEN COALESCE(r.is_return_leg, false) THEN ' · volta do pacote' ELSE ' · ida do pacote' END)
                   WHEN COALESCE(r.used_subscription_ride, false) THEN ' · plano' ELSE '' END,
         COALESCE(r.origin_label, ''),
         COALESCE(r.dest_label, ''),
         COALESCE(r.payment_method, 'cash'),
         CASE WHEN r.roundtrip_credit_id IS NOT NULL AND NOT COALESCE(r.is_return_leg, false)
              THEN COALESCE((SELECT c.paid_cents FROM public.tvde_roundtrip_credits c WHERE c.id = r.roundtrip_credit_id), 0) + COALESCE(r.extra_stops_fee_cents, 0)
              ELSE COALESCE(r.final_fare_cents, 0) END,
         COALESCE(r.driver_earn_cents, 0),
         COALESCE(r.bora_cut_cents, 0),
         0,
         COALESCE(r.cash_in_hand_cents, (SELECT h.cash_in_hand_cents FROM public.tvde_ride_cash_in_hand(r.id) h), 0),
         GREATEST(COALESCE(r.cash_in_hand_cents, (SELECT h.cash_in_hand_cents FROM public.tvde_ride_cash_in_hand(r.id) h), 0) - COALESCE(r.driver_earn_cents, 0), 0),
         COALESCE(r.cash_in_hand_cents, (SELECT h.cash_in_hand_cents FROM public.tvde_ride_cash_in_hand(r.id) h), 0) - COALESCE(r.driver_earn_cents, 0),
         r.final_distance_km,
         COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                    WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text), 0)::int,
         (SELECT jsonb_agg(p) FROM (
            SELECT jsonb_build_object('nome', 'Ganho da corrida' ||
                     CASE WHEN r.final_distance_km IS NOT NULL THEN ' (' || replace(ROUND(r.final_distance_km, 1)::text, '.', ',') || ' km)' ELSE '' END,
                     'valor_cents', COALESCE(r.driver_earn_cents, 0) - COALESCE(r.extra_stops_driver_cents, 0)) AS p
            UNION ALL
            SELECT jsonb_build_object('nome', 'Paragens extra', 'valor_cents', r.extra_stops_driver_cents)
             WHERE COALESCE(r.extra_stops_driver_cents, 0) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Tokens ganhos', 'valor_cents', NULL, 'tokens',
                     COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                                WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text), 0)::int)
             WHERE EXISTS (SELECT 1 FROM public.bora_tokens t WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text)
         ) s),
         true,
         CASE WHEN r.fare_deduced THEN 'Corrida a dinheiro sem tarifa gravada: o valor em mão foi deduzido (ganho + parte da Bora).'
              WHEN r.roundtrip_credit_id IS NOT NULL AND COALESCE(r.is_return_leg, false) THEN 'Volta do pacote: o passageiro pagou tudo na ida; nesta perna não há dinheiro a receber.'
              ELSE NULL END
    FROM public.tvde_rides r
   WHERE (r.driver_id = p_uid OR r.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = p_uid))
     AND r.status = 'finalizada'
     AND r.updated_at >= p_de
$$;

REVOKE ALL ON FUNCTION public._prestador_trabalhos(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
