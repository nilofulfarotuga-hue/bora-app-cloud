-- =============================================================================
-- 20261010070000 · Despacho de entregas e Favores — fases e chamada de reforço
-- Missão "a chamada grita sempre" (10/10/2026). Autorizado pelo Danilo nesta
-- sessão ("Aplica já", 10/10). Depende de 20261010063000 (registo de ofertas e
-- consentimento) — aplicar essa primeiro.
--
-- Regra 2 do Danilo (com a decisão 2 do adendo de 10/10, 05:05):
--   1. chama os estafetas ONLINE por rotação;
--   2. volta a chamar os mesmos (N voltas completas);
--   3. ninguém aceitou → CHAMADA DE REFORÇO a um estafeta DESLIGADO que tenha
--      ligado "Aceito chamadas de reforço quando estou desligado", pela ordem
--      configurada (Valdemir primeiro), um de cada vez; só entre as 08:00 e as
--      23:00 de Lisboa, no máximo 3 por pessoa por dia, uma vez por pedido;
--      recusar nunca penaliza;
--   4. ninguém aceitou → chama os online outra vez;
--   5. SÓ DEPOIS o sistema diz "não há estafeta" e cancela (sem taxa, com a
--      devolução do cancelamento pelo sistema).
-- Tudo em platform_settings. A chamada de reforço nasce DESLIGADA
-- (dispatch_forcado_ligado=false): com ela desligada o despacho fica igual
-- ao de hoje (fase sempre 'online1', nenhum cancelamento é adiado).
--
-- Como o motor usa isto: o motor de entregas (Edge dispatch-engine, v62) já lê
-- a lista de candidatos de dispatch_candidatos_entrega(order_id) e roda por
-- ela. Esta função passa a devolver a lista da fase em que o pedido está:
--   online1 / online2 → os online de sempre (corpo anterior, intacto, agora em
--                       _dispatch_candidatos_online);
--   forcado           → só o próximo estafeta do reforço;
--   esgotado          → ninguém (e a varredura cancela pela função de sempre).
-- A fase calcula-se do registo de ofertas (ofertas_prestador_log); a decisão é
-- uma função pura (dispatch_fase_decidir), provada em Postgres local (PGlite).
-- =============================================================================

-- 0) Cópia das definições que esta migração substitui (RLS ligada).
CREATE TABLE IF NOT EXISTS public.bkp_fn_despacho_20261010 (
  nome        text PRIMARY KEY,
  definicao   text NOT NULL,
  guardado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.bkp_fn_despacho_20261010 ENABLE ROW LEVEL SECURITY;
INSERT INTO public.bkp_fn_despacho_20261010 (nome, definicao)
SELECT p.proname, pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('dispatch_candidatos_entrega', '_registar_oferta_entrega')
ON CONFLICT (nome) DO NOTHING;

-- 1) Os candidatos ONLINE de sempre — corpo anterior copiado sem mudar uma linha.
CREATE OR REPLACE FUNCTION public._dispatch_candidatos_online(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision, vehicle_type text, dist_km double precision, mesma_loja boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o          record;
  v_fresh    int     := COALESCE((public.get_setting('dispatch_gps_fresh_seconds_entregas') #>> '{}')::int, 900);
  v_raio     numeric := COALESCE((public.get_setting('dispatch_raio_max_oferta_km') #>> '{}')::numeric, 20);
  v_req_car  boolean;
  v_favor    boolean;
BEGIN
  SELECT x.id, x.service_type, x.requires_car, x.pickup_lat, x.pickup_lng, x.restaurant_id
    INTO o FROM public.orders x WHERE x.id = p_order_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_req_car := COALESCE(o.requires_car, false) OR o.service_type = 'carryGroceries';
  v_favor   := o.service_type = 'errand';

  RETURN QUERY
  WITH base AS (
    SELECT d.id AS d_id, d.user_id AS d_uid, d.lat AS d_lat, d.lng AS d_lng, d.vehicle_type AS d_veh,
           ARRAY[d.id::text, COALESCE(d.user_id, d.id)::text] AS chaves
      FROM public.drivers d
     WHERE d.is_online
       AND d.approval_status = 'approved'
       AND (COALESCE(d.is_banned, false) = false
            OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
       AND d.deleted_at IS NULL
       AND (d.work_mode IS NULL OR d.work_mode <> 'rides_only')
       AND d.last_heartbeat_at > now() - make_interval(secs => v_fresh)
       AND public.driver_gps_last_at(d.user_id, d.id) > now() - make_interval(secs => v_fresh)
       AND (NOT v_req_car OR d.vehicle_type IN ('car', 'carro_passageiros'))
       AND public.aceita_papel(COALESCE(d.user_id, d.id), 'delivery')
       AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r
                        WHERE r.driver_id = d.user_id
                          AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
  ), carga AS (
    SELECT b.*,
           (SELECT count(*) FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')) AS ativos,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND a.service_type = 'errand') AS tem_favor,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND o.restaurant_id IS NOT NULL AND a.restaurant_id = o.restaurant_id) AS leva_mesma_loja,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.id <> o.id
               AND a.status = 'callingDriver'
               AND a.current_driver_offer_id = ANY(b.chaves)
               AND a.driver_offer_expires_at > now()
               AND (v_favor OR a.service_type = 'errand'
                    OR o.restaurant_id IS NULL OR a.restaurant_id IS DISTINCT FROM o.restaurant_id)) AS oferta_ocupada
      FROM base b
  ), dist AS (
    SELECT c.*,
           CASE WHEN o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR c.d_lat IS NULL OR c.d_lng IS NULL THEN NULL
                ELSE 6371 * 2 * asin(sqrt(
                       power(sin(radians(o.pickup_lat::double precision - c.d_lat) / 2), 2)
                     + cos(radians(c.d_lat)) * cos(radians(o.pickup_lat::double precision))
                       * power(sin(radians(o.pickup_lng::double precision - c.d_lng) / 2), 2)))
           END AS km
      FROM carga c
  )
  SELECT x.d_id, x.d_uid, x.d_lat, x.d_lng, x.d_veh, x.km, x.leva_mesma_loja
    FROM dist x
   WHERE NOT x.oferta_ocupada
     AND x.ativos < 3
     AND NOT x.tem_favor
     AND (NOT v_favor OR x.ativos = 0)
     AND (o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR (x.km IS NOT NULL AND x.km <= v_raio))
   ORDER BY x.leva_mesma_loja DESC, x.km ASC NULLS LAST;
END;
$function$;

-- 2) Quem pode receber a chamada de reforço agora, já por ordem.
--    Desligado (fora dos online), aprovado, consentiu, aparelho que acorda
--    (app, não só navegador), visto nas últimas N horas, livre, dentro do
--    horário e abaixo do máximo diário. A lista de prioridade vem primeiro.
CREATE OR REPLACE FUNCTION public._dispatch_forcados_entrega(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision, vehicle_type text,
               dist_km double precision, mesma_loja boolean, ordem integer, visto_em timestamptz)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o         record;
  v_horas   int   := COALESCE((public.get_setting('dispatch_forcado_visto_horas') #>> '{}')::int, 168);
  v_max_dia int   := COALESCE((public.get_setting('dispatch_forcado_max_por_dia') #>> '{}')::int, 3);
  v_ini     time  := COALESCE((public.get_setting('dispatch_forcado_horario_inicio') #>> '{}')::time, '08:00');
  v_fim     time  := COALESCE((public.get_setting('dispatch_forcado_horario_fim') #>> '{}')::time, '23:00');
  v_prio    jsonb := public.get_setting('dispatch_forcado_prioridade');
  v_agora   time  := (now() AT TIME ZONE 'Europe/Lisbon')::time;
  v_dia0    timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_req_car boolean;
  v_favor   boolean;
BEGIN
  -- Fora do horário não há chamada de reforço.
  IF v_ini <= v_fim THEN
    IF NOT (v_agora >= v_ini AND v_agora < v_fim) THEN RETURN; END IF;
  ELSE
    IF NOT (v_agora >= v_ini OR v_agora < v_fim) THEN RETURN; END IF;
  END IF;

  SELECT x.id, x.service_type, x.requires_car, x.pickup_lat, x.pickup_lng, x.restaurant_id
    INTO o FROM public.orders x WHERE x.id = p_order_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_req_car := COALESCE(o.requires_car, false) OR o.service_type = 'carryGroceries';
  v_favor   := o.service_type = 'errand';
  IF v_prio IS NULL OR jsonb_typeof(v_prio) <> 'array' THEN v_prio := '[]'::jsonb; END IF;

  RETURN QUERY
  WITH online AS (
    SELECT COALESCE(c.user_id, c.driver_id) AS uid FROM public._dispatch_candidatos_online(p_order_id) c
  ), base AS (
    SELECT d.id AS d_id, COALESCE(d.user_id, d.id) AS d_uid, d.lat AS d_lat, d.lng AS d_lng, d.vehicle_type AS d_veh,
           ARRAY[d.id::text, COALESCE(d.user_id, d.id)::text] AS chaves,
           GREATEST(COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz),
                    COALESCE((SELECT max(t.last_used_at) FROM public.driver_push_tokens t
                               WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active),
                             '-infinity'::timestamptz)) AS visto
      FROM public.drivers d
      JOIN public.chamada_reforco_consentimento cons
        ON cons.user_id = COALESCE(d.user_id, d.id) AND cons.ligado
     WHERE d.approval_status = 'approved'
       AND (COALESCE(d.is_banned, false) = false
            OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
       AND d.deleted_at IS NULL
       AND (d.work_mode IS NULL OR d.work_mode <> 'rides_only')
       AND (NOT v_req_car OR d.vehicle_type IN ('car', 'carro_passageiros'))
       AND public.aceita_papel(COALESCE(d.user_id, d.id), 'delivery')
       AND NOT EXISTS (SELECT 1 FROM online x WHERE x.uid = COALESCE(d.user_id, d.id))
       AND (COALESCE(d.fcm_token, '') <> ''
            OR EXISTS (SELECT 1 FROM public.driver_push_tokens t
                        WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active
                          AND COALESCE(t.platform, '') NOT ILIKE 'web%'))
       AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r
                        WHERE r.driver_id = d.user_id
                          AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
       AND (SELECT count(*) FROM public.ofertas_prestador_log l
             WHERE l.user_id = COALESCE(d.user_id, d.id) AND l.fase = 'forcado'
               AND l.oferecida_em >= v_dia0) < v_max_dia
  ), carga AS (
    SELECT b.*,
           (SELECT count(*) FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')) AS ativos,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND a.service_type = 'errand') AS tem_favor,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.id <> o.id
               AND a.status = 'callingDriver'
               AND a.current_driver_offer_id = ANY(b.chaves)
               AND a.driver_offer_expires_at > now()) AS oferta_ocupada,
           (SELECT e.ord::int FROM jsonb_array_elements_text(v_prio) WITH ORDINALITY e(val, ord)
             WHERE e.val = b.d_uid::text OR e.val = b.d_id::text
             ORDER BY e.ord LIMIT 1) AS prio
      FROM base b
     WHERE b.visto > now() - make_interval(hours => v_horas)
  )
  SELECT c.d_id, c.d_uid, c.d_lat, c.d_lng, c.d_veh,
         CASE WHEN o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR c.d_lat IS NULL OR c.d_lng IS NULL THEN NULL
              ELSE 6371 * 2 * asin(sqrt(
                     power(sin(radians(o.pickup_lat::double precision - c.d_lat) / 2), 2)
                   + cos(radians(c.d_lat)) * cos(radians(o.pickup_lat::double precision))
                     * power(sin(radians(o.pickup_lng::double precision - c.d_lng) / 2), 2)))
         END,
         false,
         COALESCE(c.prio, 1000000),
         c.visto
    FROM carga c
   WHERE NOT c.oferta_ocupada
     AND c.ativos < 3
     AND NOT c.tem_favor
     AND (NOT v_favor OR c.ativos = 0)
   ORDER BY COALESCE(c.prio, 1000000), c.visto DESC;
END;
$function$;

-- 3) A DECISÃO, função pura (sem tabelas): em que fase está o pedido.
--    p_online   : quem está online e elegível agora (user_id)
--    p_ofertas  : ofertas já feitas, por ordem: [{"user_id":..,"fase":"online1|forcado|online2"}]
--    p_forcados : quem pode receber a chamada de reforço agora, já por ordem
CREATE OR REPLACE FUNCTION public.dispatch_fase_decidir(
  p_online        uuid[],
  p_ofertas       jsonb,
  p_forcados      uuid[],
  p_ligado        boolean,
  p_voltas_antes  integer,
  p_tentativas    integer,
  p_voltas_depois integer
) RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ofertas  jsonb  := COALESCE(p_ofertas, '[]'::jsonb);
  v_online   uuid[] := COALESCE(p_online, '{}'::uuid[]);
  v_feitos   uuid[];
  v_online2  boolean;
  v_u        uuid;
  v_n        integer;
  v_prox     uuid;
  v_falta    boolean;
BEGIN
  IF NOT COALESCE(p_ligado, false) THEN
    RETURN jsonb_build_object('fase', 'online1', 'motivo', 'chamada_de_reforco_desligada');
  END IF;

  SELECT COALESCE(array_agg(DISTINCT (e->>'user_id')::uuid) FILTER (WHERE e->>'fase' = 'forcado'), '{}'::uuid[]),
         COALESCE(bool_or(e->>'fase' = 'online2'), false)
    INTO v_feitos, v_online2
    FROM jsonb_array_elements(v_ofertas) e;

  -- Fase 1: N voltas completas aos online.
  IF cardinality(v_feitos) = 0 AND NOT v_online2 THEN
    v_falta := false;
    FOREACH v_u IN ARRAY v_online LOOP
      SELECT count(*) INTO v_n FROM jsonb_array_elements(v_ofertas) e
       WHERE e->>'fase' = 'online1' AND e->>'user_id' = v_u::text;
      IF v_n < GREATEST(COALESCE(p_voltas_antes, 1), 1) THEN v_falta := true; EXIT; END IF;
    END LOOP;
    IF v_falta THEN
      RETURN jsonb_build_object('fase', 'online1', 'forcados_feitos', 0);
    END IF;
  END IF;

  -- Fase 2: chamada de reforço, um de cada vez, uma vez por pessoa por pedido.
  IF NOT v_online2 AND cardinality(v_feitos) < GREATEST(COALESCE(p_tentativas, 0), 0) THEN
    SELECT f INTO v_prox
      FROM unnest(COALESCE(p_forcados, '{}'::uuid[])) WITH ORDINALITY t(f, i)
     WHERE NOT (f = ANY(v_feitos)) AND NOT (f = ANY(v_online))
     ORDER BY i LIMIT 1;
    IF v_prox IS NOT NULL THEN
      RETURN jsonb_build_object('fase', 'forcado', 'user_id', v_prox, 'forcados_feitos', cardinality(v_feitos));
    END IF;
  END IF;

  -- Fase 3: online outra vez.
  v_falta := false;
  FOREACH v_u IN ARRAY v_online LOOP
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_ofertas) e
     WHERE e->>'fase' = 'online2' AND e->>'user_id' = v_u::text;
    IF v_n < GREATEST(COALESCE(p_voltas_depois, 0), 0) THEN v_falta := true; EXIT; END IF;
  END LOOP;
  IF v_falta THEN
    RETURN jsonb_build_object('fase', 'online2', 'forcados_feitos', cardinality(v_feitos));
  END IF;

  -- Fase 4: acabou tudo.
  RETURN jsonb_build_object('fase', 'esgotado', 'forcados_feitos', cardinality(v_feitos));
END;
$function$;

-- 4) A fase de um pedido real (junta as entradas e chama a decisão pura).
CREATE OR REPLACE FUNCTION public.dispatch_fase_entrega(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_online   uuid[];
  v_ofertas  jsonb;
  v_forcados uuid[];
  v_dec      jsonb;
  v_ext      timestamptz;
BEGIN
  SELECT COALESCE(array_agg(COALESCE(c.user_id, c.driver_id)), '{}'::uuid[])
    INTO v_online FROM public._dispatch_candidatos_online(p_order_id) c;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('user_id', l.user_id, 'fase', l.fase) ORDER BY l.oferecida_em), '[]'::jsonb)
    INTO v_ofertas
    FROM public.ofertas_prestador_log l
   WHERE l.pedido_ref = p_order_id AND l.categoria IN ('entrega', 'favor')
     AND l.fase IN ('online1', 'forcado', 'online2');
  SELECT COALESCE(array_agg(f.user_id ORDER BY f.ordem, f.visto_em DESC), '{}'::uuid[])
    INTO v_forcados FROM public._dispatch_forcados_entrega(p_order_id) f;

  v_dec := public.dispatch_fase_decidir(
    v_online, v_ofertas, v_forcados,
    COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false),
    COALESCE((public.get_setting('dispatch_voltas_online_antes_forcado') #>> '{}')::int, 2),
    COALESCE((public.get_setting('dispatch_forcado_tentativas') #>> '{}')::int, 2),
    COALESCE((public.get_setting('dispatch_voltas_online_depois_forcado') #>> '{}')::int, 1));

  -- O parceiro pediu mais tempo ("Continuar"): enquanto durar, continua a
  -- chamar os online em vez de ficar parado.
  SELECT x.dispatch_extended_until INTO v_ext FROM public.orders x WHERE x.id = p_order_id;
  IF v_dec->>'fase' = 'esgotado' AND v_ext IS NOT NULL AND v_ext > now() THEN
    v_dec := v_dec || jsonb_build_object('fase', 'online2', 'motivo', 'prolongado_pelo_parceiro');
  END IF;

  RETURN v_dec || jsonb_build_object(
    'online_n', cardinality(v_online),
    'ofertas_n', jsonb_array_length(v_ofertas),
    'forcados_disponiveis_n', cardinality(v_forcados));
END;
$function$;

-- 5) O que o motor lê: a lista certa para a fase.
CREATE OR REPLACE FUNCTION public.dispatch_candidatos_entrega(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision, vehicle_type text, dist_km double precision, mesma_loja boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_fase jsonb := public.dispatch_fase_entrega(p_order_id);
BEGIN
  IF v_fase->>'fase' IN ('online1', 'online2') THEN
    RETURN QUERY SELECT * FROM public._dispatch_candidatos_online(p_order_id);
  ELSIF v_fase->>'fase' = 'forcado' THEN
    RETURN QUERY
      SELECT f.driver_id, f.user_id, f.lat, f.lng, f.vehicle_type, f.dist_km, f.mesma_loja
        FROM public._dispatch_forcados_entrega(p_order_id) f
       WHERE f.user_id = (v_fase->>'user_id')::uuid
       LIMIT 1;
  END IF;
  -- esgotado: ninguém
  RETURN;
END;
$function$;

-- 6) O registo de ofertas passa a marcar a FASE (online1 / forcado / online2).
CREATE OR REPLACE FUNCTION public._registar_oferta_entrega()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mudou    boolean;
  v_desfecho text;
  v_d        record;
  v_janela   integer;
  v_online   boolean;
  v_fase     jsonb;
  v_label    text;
BEGIN
  v_mudou := NEW.current_driver_offer_id IS DISTINCT FROM OLD.current_driver_offer_id
          OR NEW.driver_offer_expires_at IS DISTINCT FROM OLD.driver_offer_expires_at;

  IF OLD.current_driver_offer_id IS NOT NULL
     AND (v_mudou OR NEW.status IS DISTINCT FROM OLD.status
          OR NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id) THEN
    v_desfecho := CASE
      WHEN NEW.assigned_driver_id IS NOT NULL
           AND (NEW.assigned_driver_id = OLD.current_driver_offer_id
                OR EXISTS (SELECT 1 FROM public.drivers d
                            WHERE (d.user_id::text = OLD.current_driver_offer_id OR d.id::text = OLD.current_driver_offer_id)
                              AND NEW.assigned_driver_id IN (d.id::text, COALESCE(d.user_id, d.id)::text)))
        THEN 'aceite'
      WHEN NEW.status = 'cancelled' THEN 'pedido_cancelado'
      WHEN NEW.status IS DISTINCT FROM 'callingDriver' THEN 'pedido_mudou'
      WHEN OLD.driver_offer_expires_at IS NOT NULL
           AND OLD.driver_offer_expires_at > now() + interval '2 seconds' THEN 'recusou'
      ELSE 'expirou' END;
    UPDATE public.ofertas_prestador_log
       SET desfecho = v_desfecho, fechada_em = now()
     WHERE pedido_ref = NEW.id AND categoria IN ('entrega', 'favor') AND desfecho IS NULL;
  END IF;

  IF v_mudou AND NEW.current_driver_offer_id IS NOT NULL AND NEW.driver_offer_expires_at IS NOT NULL
     AND NEW.status = 'callingDriver' AND NEW.assigned_driver_id IS NULL THEN
    SELECT d.id, COALESCE(d.user_id, d.id) AS uid, d.name, d.is_online, d.last_heartbeat_at, d.fcm_token
      INTO v_d
      FROM public.drivers d
     WHERE d.user_id::text = NEW.current_driver_offer_id OR d.id::text = NEW.current_driver_offer_id
     LIMIT 1;
    v_janela := GREATEST(1, EXTRACT(EPOCH FROM (NEW.driver_offer_expires_at - now()))::int);
    v_online := COALESCE(v_d.is_online, false) AND v_d.last_heartbeat_at > now() - interval '90 seconds';

    -- A fase em que o pedido estava quando esta oferta foi escolhida.
    v_fase  := public.dispatch_fase_entrega(NEW.id);
    v_label := v_fase->>'fase';
    IF v_label = 'forcado' AND (v_fase->>'user_id') IS DISTINCT FROM v_d.uid::text THEN
      v_label := CASE WHEN COALESCE((v_fase->>'forcados_feitos')::int, 0) > 0 THEN 'online2' ELSE 'online1' END;
    ELSIF v_label = 'esgotado' THEN
      v_label := 'online2';
    END IF;

    INSERT INTO public.ofertas_prestador_log
      (categoria, booking_id, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
       janela_min, janela_s, fase, estava_online)
    VALUES
      (CASE WHEN NEW.service_type = 'errand' THEN 'favor' ELSE 'entrega' END,
       CASE WHEN NEW.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN NEW.id::uuid END,
       NEW.id, v_d.id, v_d.uid, v_d.name,
       COALESCE(v_d.fcm_token, '') <> ''
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = v_d.uid AND t.active),
       CEIL(v_janela / 60.0)::int, v_janela, v_label, v_online);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO public.notification_failures (kind, source, erro)
    VALUES ('registo_oferta', '_registar_oferta_entrega', left(NEW.id || ': ' || SQLERRM, 500));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_registar_oferta_entrega] % (registo da falha também falhou: %)', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

-- 7) "Nunca antes": o cancelamento automático por TEMPO espera pelo fim das
--    fases (só com a chamada de reforço ligada). Corre antes dos outros
--    gatilhos BEFORE de status (nome "_aa"); devolver NULL salta a mudança
--    desta linha e os gatilhos seguintes — a função de cancelamento vê 0
--    linhas e devolve false, sem avisos nem devoluções.
CREATE OR REPLACE FUNCTION public._dispatch_nao_cancelar_cedo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lim  integer;
  v_fase text;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status = 'callingDriver'
     AND COALESCE(NEW.cancellation_initiator, '') = 'system'
     AND NEW.cancel_reason IN ('dispatch_safety_timeout', 'dispatch_max_total_with_drivers_exceeded') THEN
    BEGIN
      IF COALESCE((public.get_setting('dispatch_cancelar_so_no_fim') #>> '{}')::boolean, false)
         AND COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false) THEN
        v_lim := COALESCE((public.get_setting('dispatch_cancelar_limite_absoluto_segundos') #>> '{}')::int, 3600);
        IF OLD.dispatch_calling_since IS NULL
           OR now() - OLD.dispatch_calling_since < make_interval(secs => v_lim) THEN
          v_fase := public.dispatch_fase_entrega(OLD.id)->>'fase';
          IF v_fase IS DISTINCT FROM 'esgotado' THEN
            RAISE NOTICE '[despacho] cancelamento por tempo adiado: pedido % ainda na fase %', OLD.id, v_fase;
            RETURN NULL;
          END IF;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Na dúvida, deixa seguir o cancelamento de sempre.
      RAISE WARNING '[_dispatch_nao_cancelar_cedo] %: %', OLD.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS _aa_dispatch_nao_cancelar_cedo ON public.orders;
CREATE TRIGGER _aa_dispatch_nao_cancelar_cedo
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._dispatch_nao_cancelar_cedo();

-- 8) Varredura das fases (cron 15 s): no fim de todas as fases, cancela pela
--    função de sempre (aviso ao cliente e ao admin, devolução do sistema);
--    a meio das fases e depois do tempo normal, mantém o motor a andar.
CREATE OR REPLACE FUNCTION public.dispatch_fases_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r          record;
  v_fase     jsonb;
  v_safety   integer;
  v_max      integer;
  v_cancel   integer := 0;
  v_relancar integer := 0;
BEGIN
  IF NOT COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false) THEN
    RETURN jsonb_build_object('ok', true, 'desligado', true);
  END IF;
  v_safety := COALESCE((public.get_setting('dispatch_auto_cancel_safety_seconds') #>> '{}')::int, 1800);
  v_max    := COALESCE((public.get_setting('dispatch_max_total_seconds_with_drivers_online') #>> '{}')::int, 1200);

  FOR r IN
    SELECT o.id, o.dispatch_calling_since, o.dispatch_online_attempt_seconds, o.dispatch_next_retry_at
      FROM public.orders o
     WHERE o.status = 'callingDriver'
       AND o.assigned_driver_id IS NULL
       AND (o.current_driver_offer_id IS NULL OR o.driver_offer_expires_at IS NULL
            OR o.driver_offer_expires_at < now())
  LOOP
    BEGIN
      v_fase := public.dispatch_fase_entrega(r.id);
      IF v_fase->>'fase' = 'esgotado' AND COALESCE((v_fase->>'ofertas_n')::int, 0) > 0 THEN
        IF public.dispatch_cancel_expired_order(r.id, 'dispatch_sem_estafeta_apos_todas_as_fases') THEN
          v_cancel := v_cancel + 1;
        END IF;
      ELSIF v_fase->>'fase' <> 'esgotado'
        AND ((r.dispatch_calling_since IS NOT NULL
              AND r.dispatch_calling_since < now() - make_interval(secs => v_safety))
             OR COALESCE(r.dispatch_online_attempt_seconds, 0) >= v_max)
        AND (r.dispatch_next_retry_at IS NULL OR r.dispatch_next_retry_at < now() - interval '20 seconds') THEN
        PERFORM public.invoke_dispatch_engine(r.id::text);
        v_relancar := v_relancar + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[dispatch_fases_sweep] pedido %: %', r.id, SQLERRM;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'cancelados', v_cancel, 'relancados', v_relancar);
END;
$function$;

-- 9) TVDE: antes de "sem motorista", chamada de reforço a um motorista
--    desligado que consentiu (mesmo horário e máximo diário das entregas).
--    Gatilho BEFORE na passagem solicitada → sem_motorista: em vez de fechar,
--    oferece ao próximo do reforço. Esgotadas as tentativas, deixa fechar.
CREATE OR REPLACE FUNCTION public._tvde_forcados(p_ride_id uuid)
 RETURNS TABLE(user_id uuid, nome text, ordem integer, visto_em timestamptz)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_horas   int   := COALESCE((public.get_setting('dispatch_forcado_visto_horas') #>> '{}')::int, 168);
  v_max_dia int   := COALESCE((public.get_setting('dispatch_forcado_max_por_dia') #>> '{}')::int, 3);
  v_ini     time  := COALESCE((public.get_setting('dispatch_forcado_horario_inicio') #>> '{}')::time, '08:00');
  v_fim     time  := COALESCE((public.get_setting('dispatch_forcado_horario_fim') #>> '{}')::time, '23:00');
  v_hb      int   := COALESCE((public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int, 90);
  v_prio    jsonb := public.get_setting('tvde_forcado_prioridade');
  v_agora   time  := (now() AT TIME ZONE 'Europe/Lisbon')::time;
  v_dia0    timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
BEGIN
  IF v_ini <= v_fim THEN
    IF NOT (v_agora >= v_ini AND v_agora < v_fim) THEN RETURN; END IF;
  ELSE
    IF NOT (v_agora >= v_ini OR v_agora < v_fim) THEN RETURN; END IF;
  END IF;
  IF v_prio IS NULL OR jsonb_typeof(v_prio) <> 'array' THEN v_prio := '[]'::jsonb; END IF;

  RETURN QUERY
  SELECT d.user_id, d.name,
         COALESCE((SELECT e.ord::int FROM jsonb_array_elements_text(v_prio) WITH ORDINALITY e(val, ord)
                    WHERE e.val = d.user_id::text ORDER BY e.ord LIMIT 1), 1000000),
         GREATEST(COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz),
                  COALESCE((SELECT max(t.last_used_at) FROM public.driver_push_tokens t
                             WHERE t.user_id = d.user_id AND t.active), '-infinity'::timestamptz)) AS visto
    FROM public.drivers d
    JOIN public.chamada_reforco_consentimento cons ON cons.user_id = d.user_id AND cons.ligado
   WHERE d.vehicle_type = 'carro_passageiros'
     AND d.approval_status = 'approved'
     AND d.user_id IS NOT NULL
     AND d.deleted_at IS NULL
     AND (COALESCE(d.is_banned, false) = false OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
     AND NOT (COALESCE(d.is_online, false) AND d.last_heartbeat_at > now() - make_interval(secs => v_hb))
     AND (COALESCE(d.fcm_token, '') <> ''
          OR EXISTS (SELECT 1 FROM public.driver_push_tokens t
                      WHERE t.user_id = d.user_id AND t.active AND COALESCE(t.platform, '') NOT ILIKE 'web%'))
     AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r2
                      WHERE r2.driver_id = d.user_id
                        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
     AND NOT EXISTS (SELECT 1 FROM public.orders o
                      WHERE o.assigned_driver_id IN (d.user_id::text, d.id::text)
                        AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
     AND NOT public.tvde_driver_reservation_locked(d.user_id)
     AND public.tvde_driver_offer_allowed(d.user_id, p_ride_id)
     AND (SELECT count(*) FROM public.ofertas_prestador_log l
           WHERE l.user_id = d.user_id AND l.fase = 'forcado' AND l.oferecida_em >= v_dia0) < v_max_dia
     AND GREATEST(COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz),
                  COALESCE((SELECT max(t.last_used_at) FROM public.driver_push_tokens t
                             WHERE t.user_id = d.user_id AND t.active), '-infinity'::timestamptz))
         > now() - make_interval(hours => v_horas)
   ORDER BY 3, 4 DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public._tvde_chamada_de_reforco()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t      integer;
  v_feitos uuid[];
  v_prox   uuid;
  v_ttl    integer;
BEGIN
  IF NOT (OLD.status = 'solicitada' AND NEW.status = 'sem_motorista') THEN RETURN NEW; END IF;
  BEGIN
    IF NOT COALESCE((public.get_setting('tvde_forcado_ligado') #>> '{}')::boolean, false) THEN RETURN NEW; END IF;
    v_t := COALESCE((public.get_setting('tvde_forcado_tentativas') #>> '{}')::int, 2);
    SELECT COALESCE(array_agg(DISTINCT l.user_id), '{}'::uuid[]) INTO v_feitos
      FROM public.ofertas_prestador_log l
     WHERE l.categoria = 'tvde' AND l.booking_id = NEW.id AND l.fase = 'forcado';
    IF cardinality(v_feitos) >= v_t THEN RETURN NEW; END IF;
    SELECT f.user_id INTO v_prox FROM public._tvde_forcados(NEW.id) f
     WHERE NOT (f.user_id = ANY(v_feitos)) ORDER BY f.ordem, f.visto_em DESC LIMIT 1;
    IF v_prox IS NULL THEN RETURN NEW; END IF;
    v_ttl := COALESCE((public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int, 40);
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (NEW.id, 'oferta', 'system',
              jsonb_build_object('driver_id', v_prox, 'expires_in_s', v_ttl, 'forcado', true,
                                 'motivo', 'chamada_de_reforco'));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_tvde_chamada_de_reforco] %: %', NEW.id, SQLERRM;
    RETURN NEW;
  END;
  -- Em vez de fechar "sem motorista", fica a procurar com a oferta de reforço.
  NEW.status := 'solicitada';
  NEW.cancel_reason := OLD.cancel_reason;
  NEW.current_offer_driver_id := v_prox;
  NEW.offer_expires_at := now() + make_interval(secs => v_ttl);
  NEW.no_driver_since := NULL;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS _aa_tvde_chamada_de_reforco ON public.tvde_rides;
CREATE TRIGGER _aa_tvde_chamada_de_reforco
  BEFORE UPDATE OF status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public._tvde_chamada_de_reforco();

-- O registo TVDE marca a oferta de reforço como 'forcado'.
CREATE OR REPLACE FUNCTION public._registar_oferta_tvde()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_d        record;
  v_online   boolean;
  v_janela   integer;
  v_desfecho text;
  v_reforco  boolean;
BEGIN
  IF OLD.current_offer_driver_id IS NOT NULL
     AND (NEW.current_offer_driver_id IS DISTINCT FROM OLD.current_offer_driver_id
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    v_desfecho := CASE
      WHEN NEW.driver_id IS NOT NULL AND NEW.driver_id = OLD.current_offer_driver_id THEN 'aceite'
      WHEN NEW.status LIKE 'cancelada%' THEN 'pedido_cancelado'
      WHEN NEW.status = 'sem_motorista' THEN 'sem_motorista'
      WHEN OLD.offer_expires_at IS NOT NULL AND OLD.offer_expires_at > now() + interval '2 seconds' THEN 'recusou'
      ELSE 'expirou' END;
    UPDATE public.ofertas_prestador_log
       SET desfecho = v_desfecho, fechada_em = now()
     WHERE booking_id = NEW.id AND categoria = 'tvde' AND desfecho IS NULL;
  END IF;

  IF NEW.current_offer_driver_id IS NOT NULL
     AND NEW.current_offer_driver_id IS DISTINCT FROM OLD.current_offer_driver_id
     AND NEW.status = 'solicitada' THEN
    SELECT d.id, d.user_id AS uid, d.name, d.is_online, d.last_heartbeat_at, d.fcm_token
      INTO v_d FROM public.drivers d WHERE d.user_id = NEW.current_offer_driver_id LIMIT 1;
    v_online := COALESCE(v_d.is_online, false) AND v_d.last_heartbeat_at > now() - interval '90 seconds';
    v_janela := CASE WHEN NEW.offer_expires_at IS NULL THEN NULL
                     ELSE GREATEST(1, EXTRACT(EPOCH FROM (NEW.offer_expires_at - now()))::int) END;
    v_reforco := EXISTS (SELECT 1 FROM public.tvde_ride_events e
                          WHERE e.ride_id = NEW.id AND e.status = 'oferta'
                            AND e.meta->>'driver_id' = NEW.current_offer_driver_id::text
                            AND COALESCE((e.meta->>'forcado')::boolean, false)
                            AND e.at > now() - interval '30 seconds');
    INSERT INTO public.ofertas_prestador_log
      (categoria, booking_id, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
       janela_min, janela_s, fase, estava_online)
    VALUES
      ('tvde', NEW.id, NEW.id::text, v_d.id, NEW.current_offer_driver_id, v_d.name,
       COALESCE(v_d.fcm_token, '') <> ''
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = NEW.current_offer_driver_id AND t.active),
       CASE WHEN v_janela IS NULL THEN NULL ELSE CEIL(v_janela / 60.0)::int END, v_janela,
       CASE WHEN v_reforco THEN 'forcado' WHEN v_online THEN 'online' ELSE 'desligado' END,
       v_online);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO public.notification_failures (kind, source, erro)
    VALUES ('registo_oferta', '_registar_oferta_tvde', left(NEW.id::text || ': ' || SQLERRM, 500));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_registar_oferta_tvde] % (registo da falha também falhou: %)', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

-- 10) Quem pode chamar o quê. Internas: só o serviço (o motor).
REVOKE ALL ON FUNCTION public._dispatch_candidatos_online(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._dispatch_forcados_entrega(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_fase_entrega(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_candidatos_entrega(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_fases_sweep() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._dispatch_nao_cancelar_cedo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_forcados(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_chamada_de_reforco() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._dispatch_candidatos_online(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._dispatch_forcados_entrega(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_fase_entrega(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_candidatos_entrega(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_fases_sweep() TO service_role;
REVOKE ALL ON FUNCTION public.dispatch_fase_decidir(uuid[], jsonb, uuid[], boolean, integer, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dispatch_fase_decidir(uuid[], jsonb, uuid[], boolean, integer, integer, integer) TO authenticated, service_role;

-- 11) A varredura agendada (15 s, como a manutenção). Com a chamada de reforço
--     desligada, devolve logo {"desligado":true} e não faz nada.
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'dispatch_fases_sweep';
SELECT cron.schedule('dispatch_fases_sweep', '15 seconds', $$SELECT public.dispatch_fases_sweep();$$);
