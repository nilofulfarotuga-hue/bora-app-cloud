-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE-CAMPO-02 · FEATURE 2 — CANCELAMENTO com TAXA POR TEMPO
-- ═══════════════════════════════════════════════════════════════════════════
-- ⚠️ GATE DINHEIRO — NÃO aplicar sem "vai" do Danilo (Lista Vermelha).
--
-- Regras (confirmadas pelo Danilo, TVDE-CAMPO-02):
--   • Cliente cancela ATÉ 3 min (cancel_grace_seconds=180, reusado do delivery) → GRÁTIS.
--   • Cliente cancela APÓS 3 min (antes do pickup) → paga o VALOR TOTAL da corrida
--     (est_fare_cents, já calculado por rota — NÃO recalcular). Mais rígido que Uber/Bolt
--     de propósito (decisão do Danilo).
--   • Kill-switch reversível: tvde_cancel_full_after_grace (default true). Off = comportamento
--     antigo (grátis / tvde_cancel_fee_cents).
--   • Cancelamento do MOTORISTA antes do pickup → requeue/re-oferta (LOTE 01, PRESERVADO).
--     Depois do pickup → mantém cancelada, cliente não paga (LOTE 01, PRESERVADO).
--   • no-show do cliente → motorista não ganha nada (config atual). ⚠️ EM ABERTO: Uber/Bolt
--     COMPENSAM o motorista no no-show — confirmar com o Danilo se fica a 0.
--
-- NOTA CASH: as corridas TVDE são payment_method='cash' → nada foi pré-pago. A taxa fica
--   REGISTADA em cancel_fee_cents (dívida do cliente). O motor de refund do delivery
--   (client-cancel-order/reprocess-refund, Stripe/wallet 80-20) só se aplica a corridas
--   PRÉ-PAGAS — hoje não existem no TVDE. ⚠️ EM ABERTO: mecanismo de cobrança da dívida
--   cash (cobrar na próxima corrida? manual?) + compensação do motorista no cancel tardio.
--   Esta migration só REGISTA o valor devido — não move dinheiro por si.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) SETTING kill-switch (reversível) ────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_cancel_full_after_grace', 'true',
   'TVDE: cliente que cancela após a janela de graça paga o valor total da corrida', 'tvde')
ON CONFLICT (key) DO NOTHING;

-- 2) tvde_cancel_ride — taxa por tempo no cancelamento do CLIENTE ─────────────
--    Baseado na definição ATUAL em produção (preserva o requeue do lote 01).
--    ÚNICA mudança de lógica: o cálculo de v_fee para p_actor='cliente' antes do pickup.
CREATE OR REPLACE FUNCTION public.tvde_cancel_ride(p_ride_id uuid, p_actor text, p_reason text DEFAULT NULL::text)
RETURNS public.tvde_rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.tvde_rides;
  v_new_status TEXT;
  v_fee INT := 0;
  v_is_admin BOOLEAN := public.is_admin();
  v_was_active_of_driver BOOLEAN := false;
  v_next UUID;
  v_quit_driver UUID;
  v_grace INT;
  v_before_pickup BOOLEAN;
BEGIN
  IF p_actor NOT IN ('cliente','motorista','no_show') THEN RAISE EXCEPTION 'invalid_actor: %', p_actor; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF NOT (v_is_admin OR v_ride.client_id = v_uid OR v_ride.driver_id = v_uid) THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status; END IF;

  -- ── LOTE 01 (PRESERVADO): motorista desiste antes do pickup → requeue + re-oferta ──
  IF p_actor = 'motorista'
     AND v_ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou')
  THEN
    v_quit_driver := v_ride.driver_id;
    UPDATE public.tvde_rides
       SET status = 'solicitada',
           driver_id = NULL,
           is_queued = false,
           current_offer_driver_id = NULL,
           offer_expires_at = NULL,
           no_driver_since = NULL,
           tried_driver_ids = CASE WHEN v_quit_driver IS NOT NULL
             THEN array_append(COALESCE(tried_driver_ids, '{}'::uuid[]), v_quit_driver)
             ELSE tried_driver_ids END,
           updated_at = now()
     WHERE id = p_ride_id
     RETURNING * INTO v_ride;

    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, 'motorista_desistiu', 'motorista',
        jsonb_build_object('reason', p_reason, 'released_driver', v_quit_driver, 'requeued', true));

    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_quit_driver AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
          jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_driver_giveup', true));
    END IF;

    PERFORM public.tvde_offer_to_next(p_ride_id);
    RETURN v_ride;
  END IF;

  v_was_active_of_driver := v_ride.driver_id IS NOT NULL AND v_ride.is_queued = false
    AND v_ride.status IN ('motorista_a_caminho','motorista_chegou','em_andamento');
  v_new_status := CASE p_actor WHEN 'cliente' THEN 'cancelada_cliente' WHEN 'motorista' THEN 'cancelada_motorista' ELSE 'no_show' END;

  -- ── [CAMPO-02 F2] TAXA POR TEMPO (única mudança de lógica) ──────────────────
  -- Cliente cancela antes do pickup: <= grace → grátis; > grace → valor TOTAL
  -- (est_fare_cents, por rota, sem recalcular). Motorista pós-pickup / no_show → 0.
  v_before_pickup := v_ride.status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou');
  IF p_actor = 'cliente' AND v_before_pickup THEN
    v_grace := (public.get_setting('cancel_grace_seconds') #>> '{}')::int;
    IF COALESCE((public.get_setting('tvde_cancel_full_after_grace') #>> '{}')::boolean, false)
       AND EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int > v_grace THEN
      v_fee := v_ride.est_fare_cents;   -- valor total da corrida (dívida cash — ver nota)
    ELSE
      v_fee := 0;
    END IF;
  ELSE
    v_fee := 0;  -- no_show (motorista não ganha — EM ABERTO) / motorista pós-pickup
  END IF;

  UPDATE public.tvde_rides SET status = v_new_status, cancel_reason = p_reason, cancel_fee_cents = v_fee,
    is_queued = false, current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_new_status, CASE WHEN v_is_admin THEN 'admin' ELSE p_actor END,
            jsonb_build_object('reason', p_reason, 'cancel_fee_cents', v_fee,
              'grace_seconds', v_grace, 'elapsed_seconds', EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int));

  -- ── LOTE 01 (PRESERVADO): ativa a corrida em fila do motorista cancelado ──
  IF v_was_active_of_driver THEN
    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_ride.driver_id AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
                jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_cancel', true));
    END IF;
  END IF;

  RETURN v_ride;
END; $function$;
REVOKE ALL ON FUNCTION public.tvde_cancel_ride(UUID, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_cancel_ride(UUID, TEXT, TEXT) TO authenticated;

-- 3) ADMIN — histórico de cancelamentos TVDE (tempo, taxa, motivo, status) ────
CREATE OR REPLACE FUNCTION public.admin_tvde_cancellations(p_limit INT DEFAULT 100)
RETURNS TABLE (
  id UUID, client_id UUID, driver_id UUID, status TEXT,
  cancel_reason TEXT, cancel_fee_cents INT, est_fare_cents INT,
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id, r.client_id, r.driver_id, r.status, r.cancel_reason,
         r.cancel_fee_cents, r.est_fare_cents, r.created_at, r.updated_at
    FROM public.tvde_rides r
   WHERE r.status IN ('cancelada_cliente','cancelada_motorista','no_show')
     AND public.is_admin()
   ORDER BY r.updated_at DESC
   LIMIT COALESCE(p_limit, 100);
$$;
REVOKE ALL ON FUNCTION public.admin_tvde_cancellations(INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_cancellations(INT) TO authenticated;
