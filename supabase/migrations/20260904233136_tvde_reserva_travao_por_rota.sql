-- ============================================================================
-- TVDE — reserva agendada: o travão e o toque passam a seguir a ROTA
-- 2026-09-05 · sessão tudo-05-09-mao · Bloco 4
--
-- PORQUE EXISTE (caso real, medido, não hipótese):
-- Noite de 03→04/09, motorista Valdemir Vasconcelos (user e355fde0-…). Linha do
-- tempo lida de tvde_ride_events:
--   22:39:49  aceita a RESERVA c878dc09 para as 00:00
--   23:39:43  o motor de ofertas oferece-lhe a corrida 4817b161 (reserva a 21 min)
--   23:39:54  ele aceita  → motorista_a_caminho
--   23:40:00  o sweep prende a reserva (fixo, 20 min)  ← 6 SEGUNDOS depois
--   23:48:18  a corrida 4817b161 passa a em_andamento (passageiro no carro)
--   23:50:00  o sweep põe a RESERVA em motorista_a_caminho (fixo, 10 min)
--   ...       ele carrega em finalizar e leva 'invalid_transition'
--   00:13:15  finaliza a reserva
--   00:13:34  só então consegue finalizar a corrida que já trazia
--
-- Três defeitos em cadeia:
--  (1) tvde_offer_to_next NUNCA soube o que é uma reserva. O "travão de 20 min"
--      não travava ofertas nenhumas — só activava a reserva. Por isso lhe caiu
--      uma corrida nova a 21 minutos da reserva.
--  (2) o bloco F fotografava is_queued UMA vez, no instante do lock, e só olhava
--      para 'em_andamento'. Às 23:40 a outra corrida ainda era
--      'motorista_a_caminho' → is_queued=false. Oito minutos depois já era
--      em_andamento, mas ninguém voltou a olhar.
--  (3) o bloco H promovia a reserva a motorista_a_caminho sem verificar se o
--      motorista estava a meio de outra corrida — e roubava-lhe o ecrã.
--
-- REGRA NOVA DO DANILO (04/09, revê a decisão dele próprio da madrugada):
--   O travão deixa de ser fixo e passa a ser o tempo de rota de onde o motorista
--   está até ao cliente da reserva, com margem por cima e um mínimo se a rota
--   falhar. Antes disso ele recebe tudo e decide sozinho. A reserva fica em stand
--   by: a app continua normal, ele apanha, deixa, finaliza, e a reserva continua lá.
--   O toque de aviso segue a mesma conta — a 30 minutos de distância, toca 30 min antes.
--
-- ZONA: toca em tvde_offer_to_next (vizinho do dispatch) por ordem explícita do
-- Danilo no Bloco 4.2. NÃO toca em preços, comissões, tokens, carteira nem Stripe.
--
-- COMO VOLTAR ATRÁS (rollback exacto, sem adivinhar):
--   1. em tvde_offer_to_next, apagar as DUAS linhas
--      `AND NOT public.tvde_driver_reservation_locked(d.user_id)`;
--   2. em tvde_reservations_sweep, nos blocos F, G, G2 e H, trocar
--      `public.tvde_reservation_lock_minutes_for(...)` por `v_lock` (F e H),
--      `v_act` (G) e `v_act` dentro da média (G2);
--   3. em H e I, apagar os `NOT EXISTS (... r2.status IN ('motorista_a_caminho',
--      'motorista_chegou','em_andamento'))` que foram acrescentados;
--   4. em F, repor `is_queued = EXISTS (... r2.status='em_andamento')`.
-- Todas as linhas alteradas estão marcadas com um comentário `NOVO` ou `Fix`.
--
-- NOTA DE DERIVA (achado desta noite): `tvde_reservations_sweep` NÃO existia em
-- ficheiro de migração nenhum — tinha sido criada direto no servidor e o repo
-- não a reproduzia. Este ficheiro é o primeiro a registá-la. A migração foi
-- aplicada em quatro pedaços, gravados na base como 20260904233136 / 233335 /
-- 233443 / 234543; este ficheiro junta os quatro e o nome casa com o primeiro,
-- para o `db push` não a tentar aplicar outra vez.
-- ============================================================================

-- ─── 1. Definições novas (nenhuma é de dinheiro) ────────────────────────────
INSERT INTO public.platform_settings (key, value) VALUES
  ('tvde_reservation_eta_kmh',              '28'::jsonb),
  ('tvde_reservation_road_factor_x100',     '135'::jsonb),
  ('tvde_reservation_lock_margin_minutes',  '8'::jsonb),
  ('tvde_reservation_lock_min_minutes',     '10'::jsonb),
  ('tvde_reservation_lock_max_minutes',     '60'::jsonb),
  ('tvde_reservation_position_max_age_min', '30'::jsonb)
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE public.platform_settings IS
  'Definições da plataforma. tvde_reservation_eta_kmh = velocidade média urbana usada '
  'para converter distância em minutos no travão da reserva. road_factor_x100 = quanto '
  'a estrada é mais longa do que a linha recta (135 = +35%). lock_margin_minutes = '
  'folga por cima do tempo de rota. lock_min/max_minutes = chão e tecto do travão.';

-- ─── 2. Quantos minutos antes é que ESTA reserva prende o motorista ─────────
-- Devolve o tempo de rota estimado (linha recta × factor de estrada ÷ velocidade)
-- mais a margem, preso entre um mínimo e um máximo. Se não houver posição fresca
-- do motorista, cai no valor fixo antigo (tvde_reservation_lock_minutes) — nunca
-- devolve menos do que isso por não saber, para não prender tarde de mais.
CREATE OR REPLACE FUNCTION public.tvde_reservation_lock_minutes_for(p_ride_id uuid)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride  public.tvde_rides;
  v_lat   numeric; v_lng numeric; v_seen timestamptz;
  v_km    numeric; v_min int;
  v_kmh   numeric := COALESCE((public.get_setting('tvde_reservation_eta_kmh') #>> '{}')::numeric, 28);
  v_road  numeric := COALESCE((public.get_setting('tvde_reservation_road_factor_x100') #>> '{}')::numeric, 135) / 100.0;
  v_marg  int     := COALESCE((public.get_setting('tvde_reservation_lock_margin_minutes') #>> '{}')::int, 8);
  v_minm  int     := COALESCE((public.get_setting('tvde_reservation_lock_min_minutes') #>> '{}')::int, 10);
  v_maxm  int     := COALESCE((public.get_setting('tvde_reservation_lock_max_minutes') #>> '{}')::int, 60);
  v_fall  int     := COALESCE((public.get_setting('tvde_reservation_lock_minutes') #>> '{}')::int, 20);
  v_age   int     := COALESCE((public.get_setting('tvde_reservation_position_max_age_min') #>> '{}')::int, 30);
  v_drv   uuid;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN v_fall; END IF;

  -- o dono da reserva é reservation_driver_id antes do lock e driver_id depois
  v_drv := COALESCE(v_ride.reservation_driver_id, v_ride.driver_id);
  IF v_drv IS NULL OR v_ride.origin_lat IS NULL OR v_ride.origin_lng IS NULL THEN
    RETURN v_fall;
  END IF;

  -- driver_locations grava umas vezes por drivers.user_id e outras por drivers.id
  SELECT l.latitude, l.longitude, l.last_updated
    INTO v_lat, v_lng, v_seen
    FROM public.driver_locations l
    JOIN public.drivers d ON l.driver_id IN (d.user_id, d.id)
   WHERE d.user_id = v_drv
   ORDER BY l.last_updated DESC NULLS LAST
   LIMIT 1;

  IF v_lat IS NULL OR v_lng IS NULL OR v_seen IS NULL
     OR v_seen < now() - make_interval(mins => v_age)
     OR v_kmh <= 0 THEN
    RETURN v_fall;                      -- rota falhou → fica o fixo de sempre
  END IF;

  v_km  := public._haversine_km(v_lat, v_lng,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) * v_road;
  v_min := CEIL(v_km / v_kmh * 60.0)::int + v_marg;

  RETURN GREATEST(v_minm, LEAST(v_maxm, v_min));
END;
$function$;

COMMENT ON FUNCTION public.tvde_reservation_lock_minutes_for(uuid) IS
  'Minutos antes da hora marcada em que esta reserva prende o motorista, calculados '
  'pela rota de onde ele está até ao cliente. Cai no fixo tvde_reservation_lock_minutes '
  'se não houver posição fresca. 2026-09-05, caso do Valdemir.';

-- ─── 3. Este motorista está dentro do travão de alguma reserva dele? ────────
CREATE OR REPLACE FUNCTION public.tvde_driver_reservation_locked(p_driver uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.tvde_rides t
     WHERE p_driver IS NOT NULL
       AND COALESCE(t.reservation_driver_id, t.driver_id) = p_driver
       AND t.scheduled_at IS NOT NULL
       AND COALESCE(t.reservation_status,'') IN ('atribuida','ativada')
       AND t.status IN ('agendada','motorista_atribuido','motorista_a_caminho')
       AND t.scheduled_at <= now() + make_interval(mins => public.tvde_reservation_lock_minutes_for(t.id))
  );
$function$;

COMMENT ON FUNCTION public.tvde_driver_reservation_locked(uuid) IS
  'true quando o motorista já entrou na janela de travão de uma reserva sua e por isso '
  'não deve receber ofertas novas. Fora da janela recebe tudo e decide ele.';

-- ─── 4. O motor de ofertas passa a conhecer reservas ───────────────────────
-- ÚNICA alteração: mais um NOT no WHERE dos dois níveis. Tudo o resto é igual,
-- byte a byte, ao que já estava — ordem, raio, heartbeat, fila, nada mexeu.
CREATE OR REPLACE FUNCTION public.tvde_offer_to_next(p_ride_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride   public.tvde_rides;
  v_driver UUID;
  v_ttl    INT := (public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int;
  v_hb     INT := (public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int;
  v_radius NUMERIC := COALESCE((public.get_setting('tvde_queue_pickup_radius_km') #>> '{}')::numeric, 3);
  v_window INT := COALESCE((public.get_setting('tvde_retry_window_seconds') #>> '{}')::int, 120);
  v_queued BOOLEAN := false;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_ride.status <> 'solicitada' THEN RETURN false; END IF;

  SELECT d.user_id INTO v_driver
  FROM public.drivers d
  JOIN LATERAL (
    SELECT * FROM public.driver_locations l
    WHERE l.driver_id IN (d.user_id, d.id)
    ORDER BY l.last_updated DESC NULLS LAST
    LIMIT 1
  ) dl ON true
  WHERE d.vehicle_type = 'carro_passageiros'
    AND d.approval_status = 'approved'
    AND d.user_id IS NOT NULL
    AND (dl.is_online = true OR d.is_online = true)
    AND GREATEST(COALESCE(dl.last_updated,       '-infinity'::timestamptz),
                 COALESCE(d.last_heartbeat_at,   '-infinity'::timestamptz))
        > now() - make_interval(secs => v_hb)
    AND dl.latitude IS NOT NULL AND dl.longitude IS NOT NULL
    AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.tvde_rides r2
      WHERE r2.driver_id = d.user_id
        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
    AND NOT EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.assigned_driver_id = d.id::text
        AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
    -- NOVO 2026-09-05: dentro do travão da própria reserva não se oferece nada.
    AND NOT public.tvde_driver_reservation_locked(d.user_id)
  ORDER BY public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) ASC
  LIMIT 1;

  IF v_driver IS NULL AND v_radius > 0 THEN
    SELECT d.user_id INTO v_driver
    FROM public.drivers d
    JOIN public.tvde_rides cur ON cur.driver_id = d.user_id AND cur.status = 'em_andamento'
    WHERE d.vehicle_type = 'carro_passageiros'
      AND d.approval_status = 'approved'
      AND d.user_id IS NOT NULL
      AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))
      AND NOT EXISTS (
        SELECT 1 FROM public.tvde_rides r3
        WHERE r3.driver_id = d.user_id
          AND r3.is_queued = true AND r3.status = 'motorista_atribuido')
      AND NOT EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.assigned_driver_id = d.id::text
          AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
      -- NOVO 2026-09-05: idem para o empilhamento.
      AND NOT public.tvde_driver_reservation_locked(d.user_id)
      AND public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                               v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) <= v_radius
    ORDER BY public._haversine_km(cur.dest_lat::numeric, cur.dest_lng::numeric,
                                  v_ride.origin_lat::numeric, v_ride.origin_lng::numeric) ASC
    LIMIT 1;
    v_queued := v_driver IS NOT NULL;
  END IF;

  IF v_driver IS NULL THEN
    IF v_ride.no_driver_since IS NOT NULL
       AND now() - v_ride.no_driver_since > make_interval(secs => v_window) THEN
      UPDATE public.tvde_rides
         SET status='sem_motorista', current_offer_driver_id=NULL,
             offer_expires_at=NULL, updated_at=now()
       WHERE id = p_ride_id;
      INSERT INTO public.tvde_ride_events(ride_id,status,actor)
        VALUES (p_ride_id,'sem_motorista','system');
      RETURN false;
    END IF;
    UPDATE public.tvde_rides
       SET no_driver_since = COALESCE(v_ride.no_driver_since, now()),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id;
    RETURN false;
  END IF;

  UPDATE public.tvde_rides
     SET current_offer_driver_id = v_driver,
         offer_expires_at = now() + make_interval(secs => v_ttl),
         no_driver_since = NULL, updated_at = now()
   WHERE id = p_ride_id;
  INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
    VALUES (p_ride_id,'oferta','system',
            jsonb_build_object('driver_id', v_driver, 'expires_in_s', v_ttl, 'queued_candidate', v_queued));
  RETURN true;
END; $function$;

-- ─── 5. O relógio da reserva ────────────────────────────────────────────────
-- Mudam só os blocos F, G, G2, H e I. Os blocos 0, A, B, C, D, E, J e K ficam
-- exactamente como estavam.
CREATE OR REPLACE FUNCTION public.tvde_reservations_sweep()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE
  r record;
  v_retry int := COALESCE((public.get_setting('tvde_reservation_retry_minutes') #>> '{}')::int, 60);
  v_stop  int := COALESCE((public.get_setting('tvde_reservation_stop_search_minutes') #>> '{}')::int, 45);
  v_lock  int := COALESCE((public.get_setting('tvde_reservation_lock_minutes') #>> '{}')::int, 20);
  v_act   int := COALESCE((public.get_setting('tvde_reservation_activate_minutes') #>> '{}')::int, 10);
  v_force int := COALESCE((public.get_setting('tvde_reservation_force_redispatch_minutes') #>> '{}')::int, 5);
  v_rem   int := COALESCE((public.get_setting('tvde_reservation_reminder_minutes') #>> '{}')::int, 60);
  v_askh  int := COALESCE((public.get_setting('tvde_reservation_client_ask_hours') #>> '{}')::int, 2);
  v_ptmo  int := COALESCE((public.get_setting('tvde_reservation_payment_timeout_minutes') #>> '{}')::int, 15);
BEGIN
  -- 0) reserva online por pagar -> cancela sozinha
  FOR r IN SELECT id FROM public.tvde_rides
            WHERE status='agendada' AND reservation_status='aguarda_pagamento'
              AND created_at < now() - make_interval(mins => v_ptmo)
  LOOP
    UPDATE public.tvde_rides SET status='cancelada_cliente', reservation_status='cancelada',
           cancel_reason='payment_timeout', updated_at=now() WHERE id=r.id;
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'cancelada_cliente','system', jsonb_build_object('motivo','pagamento nao concluido'));
  END LOOP;

  -- A) oferta antecipada expirou -> seguinte da rotacao
  FOR r IN SELECT id, reservation_offer_driver_id AS drv FROM public.tvde_rides
            WHERE status='agendada' AND reservation_status='a_procurar'
              AND reservation_offer_expires_at IS NOT NULL AND reservation_offer_expires_at < now()
  LOOP
    UPDATE public.tvde_rides
       SET reservation_tried_driver_ids = array_append(reservation_tried_driver_ids, r.drv),
           reservation_offer_driver_id=NULL, reservation_offer_expires_at=NULL, updated_at=now()
     WHERE id=r.id;
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'reserva_oferta_expirada','system', jsonb_build_object('driver_id', r.drv));
    PERFORM public.tvde_reservation_offer_to_next(r.id);
  END LOOP;

  -- B) nova ronda de procura de tempos a tempos
  FOR r IN SELECT id FROM public.tvde_rides
            WHERE status='agendada' AND reservation_status='a_procurar'
              AND reservation_offer_driver_id IS NULL
              AND scheduled_at > now() + make_interval(mins => v_stop)
              AND (reservation_last_search_at IS NULL
                   OR reservation_last_search_at < now() - make_interval(mins => v_retry))
  LOOP
    UPDATE public.tvde_rides SET reservation_tried_driver_ids='{}' WHERE id=r.id;
    PERFORM public.tvde_reservation_offer_to_next(r.id);
  END LOOP;

  -- C) sem motorista perto da hora -> avisa o admin (uma vez)
  FOR r IN SELECT id, scheduled_at, origin_label, dest_label FROM public.tvde_rides
            WHERE status='agendada' AND reservation_status='a_procurar'
              AND reservation_driver_id IS NULL AND reservation_admin_alert_at IS NULL
              AND scheduled_at <= now() + make_interval(mins => v_stop)
  LOOP
    UPDATE public.tvde_rides SET reservation_admin_alert_at=now() WHERE id=r.id;
    PERFORM public.notify_admin_urgent_push('tvde_reservation_no_driver',
      'RESERVA SEM MOTORISTA para ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon','DD/MM HH24:MI')
        || ' - ' || COALESCE(r.origin_label,'?') || ' -> ' || COALESCE(r.dest_label,'?'),
      'tvde_ride', r.id::text, jsonb_build_object('scheduled_at', r.scheduled_at), '/admin/tvde/reservas');
  END LOOP;

  -- D) pergunta ao cliente v_askh horas antes
  FOR r IN SELECT id FROM public.tvde_rides
            WHERE status='agendada' AND reservation_driver_id IS NOT NULL
              AND reservation_client_ask_at IS NULL
              AND scheduled_at <= now() + make_interval(hours => v_askh)
  LOOP
    UPDATE public.tvde_rides SET reservation_client_ask_at=now() WHERE id=r.id;
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'reserva_pergunta_cliente','system','{}'::jsonb);
    PERFORM net.http_post(
      url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-client',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||public._dispatch_jwt()),
      body := jsonb_build_object('rideId', r.id::text, 'status','reserva_confirmar'));
  END LOOP;

  -- E) lembrete 1 ao motorista
  FOR r IN SELECT id, reservation_driver_id AS drv FROM public.tvde_rides
            WHERE status='agendada' AND reservation_driver_id IS NOT NULL
              AND reservation_reminder_60_at IS NULL
              AND scheduled_at <= now() + make_interval(mins => v_rem)
  LOOP
    UPDATE public.tvde_rides SET reservation_reminder_60_at=now() WHERE id=r.id;
    PERFORM public.tvde_reservation_push(r.drv, r.id, 'reservation_reminder_early');
  END LOOP;

  -- F) TRAVÃO POR ROTA (era fixo em v_lock): prende o motorista quando ele fica
  --    à distância de condução da hora marcada. is_queued passa a olhar para
  --    TODOS os estados em que ele já está comprometido com outro cliente — não
  --    só em_andamento, que foi o que falhou no caso do Valdemir às 23:40.
  FOR r IN SELECT id, reservation_driver_id AS drv FROM public.tvde_rides
            WHERE status='agendada' AND reservation_driver_id IS NOT NULL
              AND reservation_status='atribuida'
              AND scheduled_at <= now() + make_interval(mins => public.tvde_reservation_lock_minutes_for(id))
  LOOP
    UPDATE public.tvde_rides
       SET status='motorista_atribuido', driver_id=r.drv, reservation_status='ativada',
           is_queued = EXISTS (SELECT 1 FROM public.tvde_rides r2
                                WHERE r2.driver_id=r.drv
                                  AND r2.status IN ('motorista_a_caminho','motorista_chegou','em_andamento')),
           updated_at=now()
     WHERE id=r.id;
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'motorista_atribuido','system',
              jsonb_build_object('from_reservation', true,
                                 'lock_minutes', public.tvde_reservation_lock_minutes_for(r.id)));
  END LOOP;

  -- G) TOQUE POR ROTA (era fixo em v_act): a 30 minutos de distância toca 30 min
  --    antes. Não se tira a reserva a ninguém aqui.
  FOR r IN SELECT id, driver_id AS drv FROM public.tvde_rides
            WHERE reservation_status='ativada' AND status='motorista_atribuido'
              AND reservation_reminder_15_at IS NULL
              AND scheduled_at <= now() + make_interval(mins => public.tvde_reservation_lock_minutes_for(id))
  LOOP
    UPDATE public.tvde_rides SET reservation_reminder_15_at=now() WHERE id=r.id;
    PERFORM public.tvde_reservation_push(r.drv, r.id, 'reservation_start_now');
  END LOOP;

  -- G2) último aviso a meio caminho entre o toque e o corte (mantido)
  FOR r IN SELECT t.id, t.driver_id AS drv FROM public.tvde_rides t
            WHERE t.reservation_status='ativada' AND t.status='motorista_atribuido'
              AND t.reservation_driver_ready_at IS NULL
              AND t.scheduled_at <= now() + make_interval(mins => ((public.tvde_reservation_lock_minutes_for(t.id) + v_force) / 2))
              AND NOT EXISTS (SELECT 1 FROM public.tvde_ride_events e
                               WHERE e.ride_id = t.id AND e.status='reserva_ultimo_aviso')
  LOOP
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'reserva_ultimo_aviso','system','{}'::jsonb);
    PERFORM public.tvde_reservation_push(r.drv, r.id, 'reservation_start_now');
  END LOOP;

  -- H) quem ESTÁ vivo passa a 'motorista_a_caminho'.
  --    NOVO: se ele estiver a meio de outra corrida, a reserva NÃO lhe rouba o
  --    ecrã — fica em stand by e ele acaba o que tem em mãos primeiro. Era isto
  --    que fazia o botão de finalizar devolver 'invalid_transition'.
  FOR r IN SELECT t.id, t.driver_id AS drv,
                  GREATEST(COALESCE((SELECT max(l.last_updated) FROM public.driver_locations l
                                      WHERE l.driver_id = t.driver_id),'-infinity'::timestamptz),
                           COALESCE((SELECT d.last_heartbeat_at FROM public.drivers d
                                      WHERE d.user_id = t.driver_id),'-infinity'::timestamptz)) AS seen
             FROM public.tvde_rides t
            WHERE t.reservation_status='ativada' AND t.status='motorista_atribuido'
              AND t.scheduled_at <= now() + make_interval(mins => public.tvde_reservation_lock_minutes_for(t.id))
  LOOP
    IF r.seen > now() - interval '5 minutes'
       AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r2
                        WHERE r2.driver_id = r.drv AND r2.id <> r.id
                          AND r2.status IN ('motorista_a_caminho','motorista_chegou','em_andamento'))
    THEN
      PERFORM public.tvde_reservation_activate_alive(r.id);
    END IF;
  END LOOP;

  -- I) SÓ aqui se tira a reserva: v_force minutos e continua sem confirmar.
  --    NOVO: quem está a meio de outra corrida não é "quem não confirmou" — está
  --    a trabalhar. Não se lhe tira a reserva enquanto tiver cliente no carro.
  FOR r IN SELECT id, driver_id AS drv FROM public.tvde_rides
            WHERE reservation_status='ativada' AND status='motorista_atribuido'
              AND reservation_driver_ready_at IS NULL
              AND scheduled_at <= now() + make_interval(mins => v_force)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.tvde_rides r2
                    WHERE r2.driver_id = r.drv AND r2.id <> r.id
                      AND r2.status IN ('motorista_a_caminho','motorista_chegou','em_andamento'))
    THEN
      PERFORM public.tvde_reservation_redispatch(r.id, 'motorista nao confirmou a tempo');
    END IF;
  END LOOP;

  -- J) sem dono a v_act minutos -> roda normal
  FOR r IN SELECT id FROM public.tvde_rides
            WHERE status='agendada' AND reservation_status='a_procurar'
              AND reservation_driver_id IS NULL
              AND scheduled_at <= now() + make_interval(mins => v_act)
  LOOP
    UPDATE public.tvde_rides
       SET status='solicitada', tried_driver_ids='{}', no_driver_since=now(), updated_at=now()
     WHERE id=r.id;
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'reserva_para_roda_normal','system','{}'::jsonb);
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;

  -- K) passou a hora e ninguem pegou -> fecha e devolve o dinheiro se foi pago online
  FOR r IN SELECT id, payment_intent_id FROM public.tvde_rides
            WHERE status IN ('agendada','solicitada') AND scheduled_at IS NOT NULL
              AND COALESCE(reservation_status,'') NOT IN ('aguarda_pagamento','cancelada')
              AND scheduled_at < now() - interval '15 minutes' AND driver_id IS NULL
  LOOP
    UPDATE public.tvde_rides SET status='sem_motorista', reservation_status='sem_motorista', updated_at=now()
     WHERE id=r.id;
    INSERT INTO public.tvde_ride_events (ride_id,status,actor,meta)
      VALUES (r.id,'sem_motorista','system', jsonb_build_object('reservation', true));
    IF r.payment_intent_id IS NOT NULL THEN
      PERFORM public.tvde_reservation_auto_refund(r.id, 'reserva sem motorista');
    END IF;
  END LOOP;
END; $function$;

-- ─── 6. Bloco 4.6: o painel admin passa a ver o travão ─────────────────────
-- Três campos novos na lista de reservas. Sem eles o Danilo olha para uma
-- reserva presa e não consegue dizer se o travão já entrou nem em que conta
-- assentou. O gate `is_admin()` fica exactamente como estava.
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
      'lock_minutes', public.tvde_reservation_lock_minutes_for(r.id),
      'lock_at', r.scheduled_at - make_interval(mins => public.tvde_reservation_lock_minutes_for(r.id)),
      'driver_position_age_min', (
        SELECT round(extract(epoch from (now() - max(l.last_updated)))/60)::int
          FROM public.driver_locations l
          JOIN public.drivers dd ON l.driver_id IN (dd.user_id, dd.id)
         WHERE dd.user_id = COALESCE(r.reservation_driver_id, r.driver_id)
      )
    ) AS x
    FROM public.tvde_rides r
    LEFT JOIN public.users   u  ON u.id      = r.client_id
    LEFT JOIN public.drivers d  ON d.user_id = r.reservation_driver_id
    LEFT JOIN public.drivers od ON od.user_id = r.reservation_offer_driver_id
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
