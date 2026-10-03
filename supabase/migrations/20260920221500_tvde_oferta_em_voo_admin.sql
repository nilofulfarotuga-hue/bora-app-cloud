-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — oferta em voo no painel admin + "forçar nova roda"
-- Missão `tvde-oferta-sobreposta-2026-09-20` (Bloco 5, paridade do painel).
--
-- Contexto: a 20/09 uma oferta de reserva tocou no telemóvel do Danilo a meio
-- de uma corrida e não havia cartão para aceitar (a app foi corrigida nessa
-- missão). No painel, as corridas ao vivo não diziam A QUEM a oferta estava a
-- tocar nem quanto faltava para expirar — só "à procura de motorista…".
--
-- 1) admin_tvde_rides_list: ganha `current_offer_driver_id`, `offer_driver_name`,
--    `offer_seconds_left`, `tried_count` e `no_driver_since`. Tudo o resto fica
--    byte a byte igual à definição viva (2026-09-18, corridas de balcão).
-- 2) admin_tvde_force_redispatch(p_ride_id, p_motivo): o admin manda a corrida
--    (ainda em 'solicitada') a uma RODA NOVA — limpa a oferta em curso, os
--    tentados e a pausa, e chama a função de despacho de sempre
--    (tvde_offer_to_next, que NÃO é tocada). Evento com actor 'admin' e
--    registo em admin_audit_log. Uma corrida 'sem_motorista' não passa por
--    aqui: para essa já existe "Reatribuir" (admin_tvde_reassign_ride).
--
-- Só leitura + orquestração. Nada de dinheiro: sem preço, comissão, tokens
-- ou carteira.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_tvde_rides_list(p_scope text DEFAULT 'all'::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 1000 THEN RAISE EXCEPTION 'limit 1..1000'; END IF;

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.created_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      ride.created_at AS created_at,
      jsonb_build_object(
        'id',                     ride.id,
        'status',                 ride.status,
        'is_queued',              ride.is_queued,
        -- sobreposicao: atras de que corrida esta esta em fila / quem leva atras
        'queued_behind_ride_id',  CASE WHEN ride.is_queued THEN
                                    (SELECT r2.id FROM public.tvde_rides r2
                                      WHERE r2.driver_id = ride.driver_id AND r2.id <> ride.id AND r2.is_queued = false
                                        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
                                      ORDER BY r2.updated_at DESC LIMIT 1)
                                  END,
        'queue_next_ride_id',     CASE WHEN NOT ride.is_queued AND ride.driver_id IS NOT NULL
                                        AND ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento') THEN
                                    (SELECT r3.id FROM public.tvde_rides r3
                                      WHERE r3.driver_id = ride.driver_id AND r3.is_queued = true AND r3.status = 'motorista_atribuido'
                                      ORDER BY r3.created_at ASC LIMIT 1)
                                  END,
        -- 2026-09-20 oferta EM VOO: a quem esta a tocar agora e quanto falta
        'current_offer_driver_id', ride.current_offer_driver_id,
        'offer_driver_name',       od.name,
        'offer_seconds_left',      CASE WHEN ride.current_offer_driver_id IS NOT NULL AND ride.offer_expires_at IS NOT NULL
                                        THEN GREATEST(0, floor(extract(epoch FROM (ride.offer_expires_at - now())))::int)
                                   END,
        'tried_count',             COALESCE(array_length(ride.tried_driver_ids, 1), 0),
        'no_driver_since',         ride.no_driver_since,
        'arrived_at',             ride.arrived_at,
        'created_at',             ride.created_at,
        'updated_at',             ride.updated_at,
        'origin_label',           ride.origin_label,
        'dest_label',             ride.dest_label,
        'est_distance_km',        ride.est_distance_km,
        'est_fare_cents',         ride.est_fare_cents,
        'final_distance_km',      ride.final_distance_km,
        'final_fare_cents',       ride.final_fare_cents,
        'driver_earn_cents',      ride.driver_earn_cents,
        'bora_cut_cents',         ride.bora_cut_cents,
        'cancel_fee_cents',       ride.cancel_fee_cents,
        'cancel_reason',          ride.cancel_reason,
        'payment_method',         ride.payment_method,
        'used_subscription_ride', ride.used_subscription_ride,
        'offer_expires_at',       ride.offer_expires_at,
        -- 2026-09-18 corrida de balcao
        'source',                 COALESCE(ride.source, 'app'),
        'agreed_fare_cents',      ride.agreed_fare_cents,
        'agreed_driver_earn_cents', ride.agreed_driver_earn_cents,
        'client_id',              ride.client_id,
        -- cliente de balcao nao tem linha em auth.users: public.users manda.
        'client_name',            COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data->>'bora_name', ''),
        'client_phone',           COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone', ''),
        'client_is_counter',      COALESCE(u.is_counter_client, false),
        'driver_id',              ride.driver_id,
        'driver_name',            d.name,
        'driver_phone',           d.phone,
        'driver_is_online',       d.is_online,
        'driver_lat',             dl.latitude,
        'driver_lng',             dl.longitude,
        'driver_loc_updated_at',  dl.last_updated
      ) AS row
    FROM public.tvde_rides ride
    LEFT JOIN auth.users au           ON au.id = ride.client_id
    LEFT JOIN public.users u          ON u.id = ride.client_id
    LEFT JOIN public.drivers d        ON d.user_id = ride.driver_id
    LEFT JOIN public.drivers od       ON od.user_id = ride.current_offer_driver_id
    LEFT JOIN public.driver_locations dl ON dl.driver_id = ride.driver_id
    WHERE CASE
      WHEN p_scope = 'live' THEN ride.status IN
        ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
      WHEN p_scope = 'history' THEN ride.status IN
        ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista')
      WHEN p_scope = 'balcao' THEN COALESCE(ride.source,'app') = 'balcao'
      WHEN p_scope = 'balcao_live' THEN COALESCE(ride.source,'app') = 'balcao' AND ride.status IN
        ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
      ELSE true
    END
    ORDER BY ride.created_at DESC
    LIMIT p_limit
  ) s;

  RETURN v_out;
END; $function$;

-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tvde_force_redispatch(p_ride_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_ride  public.tvde_rides;
  v_prev  uuid;
  v_ok    boolean;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.status <> 'solicitada' THEN
    RAISE EXCEPTION 'ride_not_redispatchable: %', v_ride.status;
  END IF;

  v_prev := v_ride.current_offer_driver_id;

  -- Roda nova: sem oferta em curso, sem tentados, sem pausa.
  UPDATE public.tvde_rides
     SET current_offer_driver_id = NULL,
         offer_expires_at        = NULL,
         tried_driver_ids        = '{}',
         no_driver_since         = NULL,
         updated_at              = now()
   WHERE id = p_ride_id;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (p_ride_id, 'nova_roda', 'admin',
          jsonb_build_object('admin_id', v_admin.admin_id,
                             'motivo', COALESCE(p_motivo, 'admin forcou nova roda'),
                             'oferta_anterior_driver_id', v_prev));

  -- A funcao de despacho de sempre decide a quem tocar (nao e alterada).
  v_ok := public.tvde_offer_to_next(p_ride_id);

  -- overload (text, text, uuid, jsonb): e o que escreve em admin_audit_log
  -- (o de entity_id text vai para admin_logs e engole erros).
  PERFORM public.log_admin_action(
    'tvde_force_redispatch', 'tvde_ride', p_ride_id,
    jsonb_build_object('motivo', p_motivo, 'oferta_anterior_driver_id', v_prev, 'ofereceu', v_ok));

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  RETURN jsonb_build_object(
    'ok', true,
    'offered', v_ok,
    'status', v_ride.status,
    'current_offer_driver_id', v_ride.current_offer_driver_id,
    'offer_expires_at', v_ride.offer_expires_at);
END; $function$;

REVOKE ALL ON FUNCTION public.admin_tvde_force_redispatch(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_force_redispatch(uuid, text) TO authenticated;
