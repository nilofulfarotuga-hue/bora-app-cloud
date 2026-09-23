-- 2026-09-23 · Painel admin TVDE (só leitura, sem dinheiro)
--
-- 1. admin_tvde_rides_list: + offer_delay_s (segundos do pedido até à 1.ª
--    oferta) e push_delay_s (da 1.ª oferta ao 1.º push_enviado). Nasce da
--    corrida real 1e13a6ea (oferta aos 33 s, push aos 41 s, cliente cancelou
--    aos 37 s): o painel não mostrava este atraso em lado nenhum.
--    Só para corridas NA HORA (scheduled_at IS NULL) — numa reserva o pedido
--    é feito dias antes e o número não quer dizer nada.
-- 2. admin_tvde_reservations_list: + dados do pacote ida-e-volta (se é ida ou
--    volta, a perna ligada, "volta marcada" ou "cliente chama", estado do
--    vale). Lê o vale por to_jsonb(), por isso funciona antes e depois da
--    PROPOSTA_20260923_tvde_ida_e_volta_com_reserva (colunas novas aparecem
--    quando existirem, sem partir nada antes).

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
        -- 2026-09-23 atraso da oferta e do push (so corridas na hora)
        'offer_delay_s',           CASE WHEN ride.scheduled_at IS NULL AND ev.first_offer_at IS NOT NULL
                                        THEN round(extract(epoch FROM (ev.first_offer_at - ride.created_at)))::int
                                   END,
        'push_delay_s',            CASE WHEN ride.scheduled_at IS NULL AND ev.first_offer_at IS NOT NULL
                                         AND ev.first_push_at IS NOT NULL AND ev.first_push_at >= ev.first_offer_at
                                        THEN round(extract(epoch FROM (ev.first_push_at - ev.first_offer_at)))::int
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
    LEFT JOIN LATERAL (
      SELECT min(e.at) FILTER (WHERE e.status = 'oferta')       AS first_offer_at,
             min(e.at) FILTER (WHERE e.status = 'push_enviado') AS first_push_at
        FROM public.tvde_ride_events e
       WHERE e.ride_id = ride.id AND e.status IN ('oferta','push_enviado')
    ) ev ON true
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

CREATE OR REPLACE FUNCTION public.admin_tvde_reservations_list(p_scope text DEFAULT 'futuras'::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'scheduled_at'), '[]'::jsonb) INTO v_out
  FROM (
    SELECT jsonb_build_object(
      'id', r.id,
      'scheduled_at', r.scheduled_at,
      'status', r.status,
      'reservation_status', r.reservation_status,
      'origin_label', r.origin_label,
      'dest_label', r.dest_label,
      'origin_lat', r.origin_lat, 'origin_lng', r.origin_lng,
      'dest_lat', r.dest_lat,     'dest_lng', r.dest_lng,
      'est_distance_km', r.est_distance_km,
      'est_fare_cents', r.est_fare_cents,
      'payment_method', r.payment_method,
      'payment_status', r.payment_status,
      'cancel_reason', r.cancel_reason,
      'client_id', r.client_id,
      'client_name', COALESCE(u.name, '(sem nome)'),
      'reservation_driver_id', r.reservation_driver_id,
      'driver_name', d.name,
      'reservation_offer_driver_id', r.reservation_offer_driver_id,
      'offer_driver_name', od.name,
      'reservation_offer_expires_at', r.reservation_offer_expires_at,
      'reservation_driver_ready_at', r.reservation_driver_ready_at,
      'reservation_tried_driver_ids', r.reservation_tried_driver_ids,
      -- NOVO 2026-09-05: o travao por rota, em minutos e em hora do relogio
      'lock_minutes', public.tvde_reservation_lock_minutes_for(r.id),
      'lock_at', r.scheduled_at - make_interval(mins => public.tvde_reservation_lock_minutes_for(r.id)),
      -- idade da ultima posicao conhecida do motorista, em minutos: diz se a
      -- conta acima e rota a serio ou se caiu no valor fixo por falta de sinal
      'driver_position_age_min', (
        SELECT round(extract(epoch from (now() - max(l.last_updated)))/60)::int
          FROM public.driver_locations l
          JOIN public.drivers dd ON l.driver_id IN (dd.user_id, dd.id)
         WHERE dd.user_id = COALESCE(r.reservation_driver_id, r.driver_id)
      ),
      -- NOVO 2026-09-23: pacote ida-e-volta
      'driver_earn_cents', r.driver_earn_cents,
      'roundtrip_credit_id', r.roundtrip_credit_id,
      'is_return_leg', COALESCE(r.is_return_leg, false),
      'pacote', CASE WHEN c.id IS NULL THEN NULL ELSE jsonb_build_object(
          'credit_id',                c.id,
          'status',                   c.status,
          'paid_cents',               c.paid_cents,
          'pago_online',              c.payment_intent_id IS NOT NULL,
          'expires_at',               c.expires_at,
          'outbound_ride_id',         c.outbound_ride_id,
          'return_ride_id',           c.return_ride_id,
          'return_mode',              to_jsonb(c)->>'return_mode',
          'return_scheduled_at',      to_jsonb(c)->>'return_scheduled_at',
          'scheduled_return_ride_id', to_jsonb(c)->>'scheduled_return_ride_id')
        END,
      'perna_ligada', CASE WHEN lg.id IS NULL THEN NULL ELSE jsonb_build_object(
          'id', lg.id, 'status', lg.status, 'reservation_status', lg.reservation_status,
          'scheduled_at', lg.scheduled_at, 'is_return_leg', COALESCE(lg.is_return_leg, false),
          'driver_name', ld.name)
        END
    ) AS x
    FROM public.tvde_rides r
    LEFT JOIN public.users   u  ON u.id      = r.client_id
    LEFT JOIN public.drivers d  ON d.user_id = r.reservation_driver_id
    LEFT JOIN public.drivers od ON od.user_id = r.reservation_offer_driver_id
    LEFT JOIN public.tvde_roundtrip_credits c ON c.id = r.roundtrip_credit_id
    -- a OUTRA perna do mesmo pacote (ida <-> volta)
    LEFT JOIN public.tvde_rides lg ON lg.id = CASE
         WHEN COALESCE(r.is_return_leg, false) THEN c.outbound_ride_id
         ELSE COALESCE((to_jsonb(c)->>'scheduled_return_ride_id')::uuid, c.return_ride_id)
       END
    LEFT JOIN public.drivers ld ON ld.user_id = COALESCE(lg.reservation_driver_id, lg.driver_id)
    WHERE r.scheduled_at IS NOT NULL
      AND (
        p_scope = 'todas'
        OR (p_scope = 'futuras' AND r.scheduled_at >= now() - interval '2 hours')
        OR (p_scope = 'problemas' AND r.reservation_status IN ('sem_motorista','aguarda_pagamento'))
      )
    ORDER BY r.scheduled_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 500))
  ) s;
  RETURN v_out;
END; $function$;
