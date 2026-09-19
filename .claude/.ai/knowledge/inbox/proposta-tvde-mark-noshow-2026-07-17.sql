-- ============================================================================
-- PROPOSTA — PARTE D — 🔴 LISTA VERMELHA (DINHEIRO) — **NÃO APLICADA**
-- Aguarda "vai" do Danilo. Cobra o cliente e paga o estafeta → não se aplica só.
-- ============================================================================
-- tvde_mark_noshow: o MOTORISTA marca no-show depois de esperar
--   tvde_noshow_wait_minutes (=5) desde arrived_at (status 'motorista_chegou').
--   • Cliente cobrado 100% da tarifa (final se existir, senão estimada).
--   • Motorista recebe taxa FIXA tvde_noshow_driver_fee_cents (=350) em qualquer
--     distância. A Bora fica com a diferença (charge - 350).
--   • Sem reembolso ao cliente. Idempotente (não marca 2x). Grava admin_audit_log.
--
-- Factos confirmados por SQL (2026-07-17):
--   • tvde_mark_noshow NÃO existe. tvde_cancel_ride aceita p_actor='no_show' MAS
--     cobra €0 (v_fee:=0 para actor≠cliente) — é o buraco que isto fecha.
--   • Settings já existem: tvde_noshow_driver_fee_cents=350, tvde_noshow_wait_minutes=5.
--   • status 'no_show' é válido no check de tvde_rides.
--   • Padrão de money/fields copiado de tvde_cancel_ride (cancel_fee_cents/
--     final_fare_cents/driver_earn_cents/bora_cut_cents) — a captura real segue o
--     MESMO caminho de settlement das corridas canceladas/finalizadas.

CREATE OR REPLACE FUNCTION public.tvde_mark_noshow(p_ride_id uuid)
RETURNS tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_ride     public.tvde_rides;
  v_is_admin boolean := public.is_admin();
  v_wait_min int := COALESCE((public.get_setting('tvde_noshow_wait_minutes') #>> '{}')::int, 5);
  v_drv_fee  int := COALESCE((public.get_setting('tvde_noshow_driver_fee_cents') #>> '{}')::int, 350);
  v_charge   int;
  v_bora_cut int;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;

  -- Só o motorista atribuído (ou admin) marca no-show.
  IF NOT (v_is_admin OR v_ride.driver_id = v_uid) THEN RAISE EXCEPTION 'not_authorized'; END IF;

  -- Idempotência: se já terminal, não marca 2x.
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista') THEN
    RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status;
  END IF;

  -- Só depois de o motorista ter chegado e esperado tvde_noshow_wait_minutes.
  IF v_ride.status <> 'motorista_chegou' OR v_ride.arrived_at IS NULL THEN
    RAISE EXCEPTION 'noshow_requires_arrived_status';
  END IF;
  IF EXTRACT(EPOCH FROM (now() - v_ride.arrived_at)) < v_wait_min * 60 THEN
    RAISE EXCEPTION 'noshow_wait_not_elapsed';
  END IF;

  -- Cobrança: 100% da tarifa. Corrida coberta pelo plano (tarifa 0) → cobra ao
  -- menos a taxa fixa do motorista, para não ficar €0 (consistente com cancel_ride).
  v_charge := COALESCE(NULLIF(v_ride.final_fare_cents, 0), v_ride.est_fare_cents, 0);
  IF COALESCE(v_ride.used_subscription_ride, false) OR v_charge = 0 THEN
    v_charge := v_drv_fee;
  END IF;
  v_bora_cut := GREATEST(v_charge - v_drv_fee, 0);

  UPDATE public.tvde_rides SET
    status            = 'no_show',
    cancel_reason     = 'no_show (motorista, ' || v_wait_min || ' min)',
    cancel_fee_cents  = v_charge,      -- cobrado ao cliente (sem reembolso)
    final_fare_cents  = v_charge,
    driver_earn_cents = v_drv_fee,     -- taxa fixa €3,50 em qualquer distância
    bora_cut_cents    = v_bora_cut,    -- Bora fica com a diferença
    is_queued = false, current_offer_driver_id = NULL, offer_expires_at = NULL,
    updated_at = now()
  WHERE id = p_ride_id RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'no_show', CASE WHEN v_is_admin THEN 'admin' ELSE 'motorista' END,
      jsonb_build_object('charge_cents', v_charge, 'driver_fee_cents', v_drv_fee,
        'bora_cut_cents', v_bora_cut, 'wait_minutes', v_wait_min, 'arrived_at', v_ride.arrived_at));

  -- Auditoria admin (para o ecrã ver/reverter).
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
    VALUES (v_uid, (SELECT email FROM auth.users WHERE id = v_uid),
      'tvde_noshow_marked', 'tvde_ride', p_ride_id,
      jsonb_build_object('driver_id', v_ride.driver_id, 'client_id', v_ride.client_id,
        'charge_cents', v_charge, 'driver_fee_cents', v_drv_fee, 'bora_cut_cents', v_bora_cut));

  RETURN v_ride;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tvde_mark_noshow(uuid) TO authenticated;

-- ── Reverter no-show (ecrã admin) — admin-only, sem cobrança ────────────────
CREATE OR REPLACE FUNCTION public.tvde_admin_revert_noshow(p_ride_id uuid, p_reason text DEFAULT NULL)
RETURNS tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_ride public.tvde_rides;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_authorized'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.status <> 'no_show' THEN RAISE EXCEPTION 'not_a_noshow: %', v_ride.status; END IF;

  UPDATE public.tvde_rides SET
    status = 'cancelada_motorista',
    cancel_reason = COALESCE(p_reason, 'no-show revertido pelo admin'),
    cancel_fee_cents = 0, final_fare_cents = 0, driver_earn_cents = 0, bora_cut_cents = 0,
    updated_at = now()
  WHERE id = p_ride_id RETURNING * INTO v_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'no_show_revertido', 'admin', jsonb_build_object('reason', p_reason));
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
    VALUES (v_uid, (SELECT email FROM auth.users WHERE id = v_uid),
      'tvde_noshow_reverted', 'tvde_ride', p_ride_id, jsonb_build_object('reason', p_reason));
  RETURN v_ride;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tvde_admin_revert_noshow(uuid, text) TO authenticated;

-- ── Listar no-shows (ecrã admin ver/reverter) ───────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_tvde_noshows(p_limit int DEFAULT 100)
RETURNS SETOF tvde_rides
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT * FROM public.tvde_rides
  WHERE status = 'no_show' AND public.is_admin()
  ORDER BY updated_at DESC LIMIT p_limit;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_tvde_noshows(int) TO authenticated;

-- ============================================================================
-- ECRÃ ADMIN (Flutter) — a construir ao aplicar (PROPOSE-ONLY):
--   AdminTvdeNoShowsScreen: lista admin_list_tvde_noshows() (origem/destino,
--   motorista, cliente, cobrado, taxa motorista, corte Bora, quando) + botão
--   "Reverter" → tvde_admin_revert_noshow(rideId, motivo). Rota /admin/tvde/noshows.
--   NavCard no admin_dashboard_screen. (Paridade admin.)
-- ============================================================================
