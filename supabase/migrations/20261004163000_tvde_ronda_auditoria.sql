-- =============================================================================
-- TVDE — ronda de correcao da auditoria (04/10/2026, agente tvde)
-- Parte das definicoes que estao NO AR (producao a frente do repo): cada funcao
-- e alterada com replace() sobre pg_get_functiondef e uma verificacao de que o
-- texto antigo existe (se nao existir, a migration falha e nada muda).
--
--  C1  tvde_request_ride (e reservas / volta / pacote) nao confia nos km do
--      telemovel: km = max(declarados, linha reta x tvde_km_fator_minimo).
--  C3  tvde_finish_ride: socio e plano ja nao perdem os km extra fechados ao
--      pedir; % do motorista no plano le tvde_plan_driver_pct; corrida de plano
--      paga em dinheiro (km acima do plano) entra no acerto do motorista.
--      _tvde_finish_km_part acompanha (mudanca de destino coerente).
--  A2  tvde_offer_to_next / admin_tvde_drivers_list: "a meio de uma entrega"
--      compara orders.assigned_driver_id com user_id (regra) e com id (legado).
--  M   tempo maximo a procurar motorista (tvde_procura_max_minutos = 6).
--  M   tempo de graca do cancelamento conta desde a ACEITACAO.
--  S   viagens do plano de outro cliente: tvde_consume_subscription_ride e
--      tvde_preview_coverage validam auth.uid() e deixam de estar abertas.
--  N   partilhar viagem em tempo real: tvde_partilhas + RPCs.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Definicoes novas (nascem com o comportamento de hoje / valor pedido)
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('tvde_km_fator_minimo', '1.25'::jsonb,
   'TVDE: km minimos cobrados = distancia em linha reta x este fator (o telemovel nunca pode declarar menos).', 'tvde'),
  ('tvde_procura_max_minutos', '6'::jsonb,
   'TVDE: minutos maximos a procurar motorista; depois a corrida fecha como sem_motorista (reembolso automatico se paga).', 'tvde'),
  ('tvde_partilha_base_url', '"https://app.boraguarda.com/viagem.html?t="'::jsonb,
   'TVDE: endereco da pagina publica de partilha de viagem.', 'tvde')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1. C1 — km seguros
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._tvde_km_seguro(
  p_olat double precision, p_olng double precision,
  p_dlat double precision, p_dlng double precision, p_km numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_reta double precision; v_fator numeric;
BEGIN
  v_reta := public._haversine_km(p_olat, p_olng, p_dlat, p_dlng);
  IF v_reta IS NULL THEN RETURN p_km; END IF;
  v_fator := COALESCE((public.get_setting('tvde_km_fator_minimo') #>> '{}')::numeric, 1.25);
  RETURN GREATEST(COALESCE(p_km, 0), ROUND((v_reta * v_fator)::numeric, 2));
END $fn$;
REVOKE ALL ON FUNCTION public._tvde_km_seguro(double precision,double precision,double precision,double precision,numeric) FROM PUBLIC, anon, authenticated;

DO $mig$
DECLARE d text; o text; n text;
BEGIN
  -- tvde_request_ride
  d := pg_get_functiondef('public.tvde_request_ride(double precision,double precision,text,double precision,double precision,text,numeric,text,integer)'::regprocedure);
  o := E'  v_stale_ride UUID;\nBEGIN';
  n := E'  v_stale_ride UUID;\n  v_km_declarado NUMERIC;\nBEGIN';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'request_ride: declare nao encontrado'; END IF;
  d := replace(d, o, n);
  o := E'    RAISE EXCEPTION ''ride_in_progress''; END IF;\n';
  n := o || E'\n  -- 2026-10-04 (auditoria C1): os km vem do telemovel; o servidor nunca\n  -- aceita menos do que a linha reta x tvde_km_fator_minimo. O preco fixo\n  -- continua fechado aqui, ao pedir, sobre estes km.\n  v_km_declarado := p_est_distance_km;\n  p_est_distance_km := public._tvde_km_seguro(p_origin_lat, p_origin_lng, p_dest_lat, p_dest_lng, p_est_distance_km);\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'request_ride: ancora nao encontrada'; END IF;
  d := replace(d, o, n);
  o := E'jsonb_build_object(''est_distance_km'', p_est_distance_km, ''est_fare_cents'', v_client_fare,';
  n := E'jsonb_build_object(''est_distance_km'', p_est_distance_km, ''km_declarado'', v_km_declarado, ''est_fare_cents'', v_client_fare,';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'request_ride: meta nao encontrada'; END IF;
  d := replace(d, o, n);
  EXECUTE d;

  -- tvde_schedule_ride
  d := pg_get_functiondef('public.tvde_schedule_ride(double precision,double precision,text,double precision,double precision,text,numeric,timestamp with time zone,text,text)'::regprocedure);
  o := E'  IF p_scheduled_at > now() + make_interval(days => v_max) THEN RAISE EXCEPTION ''too_far''; END IF;\n';
  n := o || E'  -- 2026-10-04 (auditoria C1): km nunca abaixo da linha reta x fator.\n  p_est_distance_km := public._tvde_km_seguro(p_origin_lat, p_origin_lng, p_dest_lat, p_dest_lng, p_est_distance_km);\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'schedule_ride: ancora nao encontrada'; END IF;
  EXECUTE replace(d, o, n);

  -- tvde_schedule_roundtrip
  d := pg_get_functiondef('public.tvde_schedule_roundtrip(double precision,double precision,text,double precision,double precision,text,numeric,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure);
  o := E'  IF v_uid IS NULL THEN RAISE EXCEPTION ''not_authenticated''; END IF;\n';
  n := o || E'  -- 2026-10-04 (auditoria C1): km nunca abaixo da linha reta x fator.\n  p_est_distance_km := public._tvde_km_seguro(p_origin_lat, p_origin_lng, p_dest_lat, p_dest_lng, p_est_distance_km);\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'schedule_roundtrip: ancora nao encontrada'; END IF;
  EXECUTE replace(d, o, n);

  -- tvde_request_return_ride
  d := pg_get_functiondef('public.tvde_request_return_ride(uuid,double precision,double precision,text,double precision,double precision,text,numeric)'::regprocedure);
  o := E'    RAISE EXCEPTION ''credit_expired'';\n  END IF;\n';
  n := o || E'  -- 2026-10-04 (auditoria C1): km nunca abaixo da linha reta x fator.\n  p_est_distance_km := public._tvde_km_seguro(p_origin_lat, p_origin_lng, p_dest_lat, p_dest_lng, p_est_distance_km);\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'return_ride: ancora nao encontrada'; END IF;
  EXECUTE replace(d, o, n);
END $mig$;

-- ---------------------------------------------------------------------------
-- 2. C3 — fim da corrida mantem o preco fechado ao pedir
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public.tvde_finish_ride(uuid,numeric,text,integer)'::regprocedure);

  o := E'  v_dest_cash INT;\nBEGIN';
  n := E'  v_dest_cash INT;\n  v_plan_km NUMERIC; v_plan_extra_km INT := 0; v_plan_fare INT := 0; v_plan_pct INT; v_driver_normal INT;\nBEGIN';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'finish: declare'; END IF;
  d := replace(d, o, n);

  o := E'  ELSIF v_covered THEN\n    -- Plano com ganho FIXO acordado manda sobre a percentagem (2026-09-04).\n    SELECT driver_earn_cents INTO v_plan_fixed_earn\n      FROM public.tvde_subscriptions WHERE id = v_sub_id;\n    IF v_plan_fixed_earn IS NOT NULL THEN\n      v_driver_earn := v_plan_fixed_earn + v_stops_drv;\n      v_fare        := v_stops_fee;\n      v_bora_cut    := v_stops_fee - v_driver_earn;\n    ELSE\n      v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);\n      v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;\n      v_fare        := v_stops_fee;\n    END IF;\n';
  n := E'  ELSIF v_covered THEN\n    -- Plano com ganho FIXO acordado manda sobre a percentagem (2026-09-04).\n    -- 2026-10-04 (auditoria C3): os km acima do incluido no plano, cobrados ao\n    -- pedir (tvde_request_ride), ja nao se perdem no fim; e a % do motorista\n    -- le tvde_plan_driver_pct (era 0.85 cravado).\n    SELECT driver_earn_cents, km_included INTO v_plan_fixed_earn, v_plan_km\n      FROM public.tvde_subscriptions WHERE id = v_sub_id;\n    v_plan_extra_km := GREATEST(0, CEIL(v_price_km - COALESCE(v_plan_km, (public.get_setting(''tvde_base_distance_km'') #>> ''{}'')::int)))::int;\n    v_plan_fare := v_plan_extra_km * (public.get_setting(''tvde_extra_per_km_cents'') #>> ''{}'')::int;\n    v_plan_pct := COALESCE((public.get_setting(''tvde_plan_driver_pct'') #>> ''{}'')::int, 85);\n    IF v_plan_fixed_earn IS NOT NULL THEN\n      v_driver_earn := v_plan_fixed_earn + v_stops_drv;\n      v_fare        := v_plan_fare + v_stops_fee;\n      v_bora_cut    := v_fare - v_driver_earn;\n    ELSE\n      v_driver_normal := v_driver_earn;\n      v_bora_cut    := (v_driver_normal - ROUND(v_driver_normal * v_plan_pct / 100.0)::int) + (v_stops_fee - v_stops_drv) + v_plan_fare;\n      v_driver_earn := ROUND(v_driver_normal * v_plan_pct / 100.0)::int + v_stops_drv;\n      v_fare        := v_plan_fare + v_stops_fee;\n    END IF;\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'finish: ramo plano'; END IF;
  d := replace(d, o, n);

  o := E'    IF v_is_member THEN\n      v_fare := (public.get_setting(''tvde_extra_ride_cents'') #>> ''{}'')::int;\n    END IF;\n';
  n := E'    IF v_is_member THEN\n      -- 2026-10-04 (auditoria C3): socio paga o extra + os km acima da base,\n      -- exactamente como foi fechado ao pedir (antes perdia os km extra).\n      v_fare := (public.get_setting(''tvde_extra_ride_cents'') #>> ''{}'')::int\n              + v_extra_km * (public.get_setting(''tvde_extra_per_km_cents'') #>> ''{}'')::int;\n    END IF;\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'finish: ramo socio'; END IF;
  d := replace(d, o, n);

  o := E'  ELSE\n    v_settle := v_stops_cash + v_dest_cash + v_extra_fare - v_driver_earn;\n  END IF;\n';
  n := E'  ELSIF v_covered AND v_pm = ''cash'' THEN\n    -- 2026-10-04 (auditoria C3): corrida de plano em dinheiro — o motorista\n    -- recolhe os km acima do plano (descontados promo/tokens); entra no acerto.\n    v_settle := GREATEST(0, v_plan_fare - COALESCE(v_promo, 0) - COALESCE(v_tokens_discount_cents, 0))\n                + v_stops_cash + v_dest_cash - v_driver_earn;\n  ELSE\n    v_settle := v_stops_cash + v_dest_cash + v_extra_fare - v_driver_earn;\n  END IF;\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'finish: acerto'; END IF;
  d := replace(d, o, n);

  o := E'''plan_fixed_driver_earn_cents'', v_plan_fixed_earn,\n      ''promo_credit_cents''';
  n := E'''plan_fixed_driver_earn_cents'', v_plan_fixed_earn,\n      ''plan_extra_km'', v_plan_extra_km, ''plan_fare_cents'', v_plan_fare, ''plan_driver_pct'', v_plan_pct,\n      ''promo_credit_cents''';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'finish: meta'; END IF;
  d := replace(d, o, n);
  EXECUTE d;

  -- _tvde_finish_km_part (usada pela mudanca de destino) — mesma regra
  d := pg_get_functiondef('public._tvde_finish_km_part(tvde_rides,numeric)'::regprocedure);
  o := E'  v_member boolean; v_fixed int; v_fixed_drv int; v_branch text;\n';
  n := E'  v_member boolean; v_fixed int; v_fixed_drv int; v_branch text; v_plan_km numeric;\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'km_part: declare'; END IF;
  d := replace(d, o, n);
  o := E'    SELECT driver_earn_cents INTO v_plan_fixed FROM public.tvde_subscriptions WHERE id = p_ride.subscription_id;\n    IF v_plan_fixed IS NOT NULL THEN\n      RETURN jsonb_build_object(''fare'', 0, ''driver'', v_plan_fixed, ''branch'', ''plano_ganho_fixo'');\n    END IF;\n    RETURN jsonb_build_object(''fare'', 0, ''driver'', ROUND(public._tvde_table_driver_cents(p_km) * 0.85)::int, ''branch'', ''plano'');\n';
  n := E'    SELECT driver_earn_cents, km_included INTO v_plan_fixed, v_plan_km FROM public.tvde_subscriptions WHERE id = p_ride.subscription_id;\n    -- 2026-10-04 (auditoria C3): km acima do plano pagos pelo cliente; % do setting.\n    v_fare := GREATEST(0, CEIL(COALESCE(p_km,0) - COALESCE(v_plan_km, (public.get_setting(''tvde_base_distance_km'') #>> ''{}'')::int)))::int\n              * (public.get_setting(''tvde_extra_per_km_cents'') #>> ''{}'')::int;\n    IF v_plan_fixed IS NOT NULL THEN\n      RETURN jsonb_build_object(''fare'', v_fare, ''driver'', v_plan_fixed, ''branch'', ''plano_ganho_fixo'');\n    END IF;\n    RETURN jsonb_build_object(''fare'', v_fare, ''driver'', ROUND(public._tvde_table_driver_cents(p_km) * COALESCE((public.get_setting(''tvde_plan_driver_pct'') #>> ''{}'')::int, 85) / 100.0)::int, ''branch'', ''plano'');\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'km_part: plano'; END IF;
  d := replace(d, o, n);
  o := E'    v_fare := (public.get_setting(''tvde_extra_ride_cents'') #>> ''{}'')::int;\n    v_branch := ''socio'';';
  n := E'    v_fare := (public.get_setting(''tvde_extra_ride_cents'') #>> ''{}'')::int + v_extra_km * (public.get_setting(''tvde_extra_per_km_cents'') #>> ''{}'')::int;\n    v_branch := ''socio'';';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'km_part: socio'; END IF;
  d := replace(d, o, n);
  EXECUTE d;
END $mig$;

-- ---------------------------------------------------------------------------
-- 3. A2 — filtro "a meio de uma entrega" com o id certo (user_id manda)
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public.tvde_offer_to_next(uuid)'::regprocedure);
  o := E'WHERE o.assigned_driver_id = d.id::text\n';
  n := E'WHERE o.assigned_driver_id IN (d.user_id::text, d.id::text)\n';
  IF (length(d) - length(replace(d, o, ''))) / length(o) <> 2 THEN RAISE EXCEPTION 'offer_to_next: esperava 2 ocorrencias'; END IF;
  EXECUTE replace(d, o, n);

  d := pg_get_functiondef('public.admin_tvde_drivers_list()'::regprocedure);
  o := 'WHERE o.assigned_driver_id = d.id::text AND';
  n := 'WHERE o.assigned_driver_id IN (d.user_id::text, d.id::text) AND';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'drivers_list: ancora'; END IF;
  EXECUTE replace(d, o, n);
END $mig$;

-- ---------------------------------------------------------------------------
-- 4. Tempo maximo a procurar motorista
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tvde_dispatch_sweep()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_pause INT := COALESCE((public.get_setting('tvde_reoffer_pause_seconds') #>> '{}')::int, 35);
  -- 2026-10-04 (auditoria): a procura tem fim. Conta desde a 1.a oferta (ou
  -- desde que ficou sem candidatos) — corrida por pagar ainda nao procura.
  v_max_min INT := COALESCE((public.get_setting('tvde_procura_max_minutos') #>> '{}')::int, 6);
BEGIN
  IF v_max_min > 0 THEN
    FOR r IN
      SELECT t.id FROM public.tvde_rides t
       WHERE t.status = 'solicitada'
         AND t.reservation_status IS NULL
         AND t.dispatch_hold_reason IS NULL
         AND COALESCE(t.source, 'app') <> 'balcao'
         AND (t.current_offer_driver_id IS NULL OR t.offer_expires_at < now())
         AND LEAST(t.no_driver_since,
                   (SELECT min(e.at) FROM public.tvde_ride_events e
                     WHERE e.ride_id = t.id AND e.status = 'oferta'))
             < now() - make_interval(mins => v_max_min)
    LOOP
      UPDATE public.tvde_rides
         SET status = 'sem_motorista', cancel_reason = 'procura_esgotada',
             current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
       WHERE id = r.id AND status = 'solicitada';
      IF FOUND THEN
        INSERT INTO public.tvde_ride_events(ride_id, status, actor, meta)
          VALUES (r.id, 'sem_motorista', 'system',
                  jsonb_build_object('motivo', 'procura_esgotada', 'max_minutos', v_max_min));
      END IF;
    END LOOP;
  END IF;

  FOR r IN
    SELECT id, current_offer_driver_id FROM public.tvde_rides
    WHERE status='solicitada' AND offer_expires_at IS NOT NULL AND offer_expires_at < now()
      AND current_offer_driver_id IS NOT NULL
  LOOP
    UPDATE public.tvde_rides
       SET tried_driver_ids = array_append(tried_driver_ids, r.current_offer_driver_id),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = r.id;
    INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
      VALUES (r.id,'oferta_expirada','system', jsonb_build_object('driver_id', r.current_offer_driver_id));
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;

  FOR r IN
    SELECT id, no_driver_since FROM public.tvde_rides
    WHERE status='solicitada' AND current_offer_driver_id IS NULL
      AND no_driver_since IS NOT NULL
  LOOP
    IF now() - r.no_driver_since >= make_interval(secs => v_pause) THEN
      UPDATE public.tvde_rides SET tried_driver_ids = '{}' WHERE id = r.id;
    END IF;
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;
END; $function$;

-- ---------------------------------------------------------------------------
-- 5. Graca do cancelamento desde a aceitacao (como a Uber)
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public.tvde_cancel_ride(uuid,text,text)'::regprocedure);
  o := E'  v_was_queued BOOLEAN := false;\nBEGIN';
  n := E'  v_was_queued BOOLEAN := false;\n  v_accepted_at TIMESTAMPTZ;\nBEGIN';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'cancel: declare'; END IF;
  d := replace(d, o, n);
  o := E'  v_had_driver := v_ride.driver_id IS NOT NULL;\n';
  n := o || E'  -- 2026-10-04 (auditoria): a graca conta desde a ACEITACAO do motorista\n  -- (como a Uber), nao desde o pedido.\n  SELECT max(e.at) INTO v_accepted_at FROM public.tvde_ride_events e\n   WHERE e.ride_id = p_ride_id AND e.status = ''motorista_atribuido'';\n  v_accepted_at := COALESCE(v_accepted_at, v_ride.created_at);\n';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'cancel: ancora'; END IF;
  d := replace(d, o, n);
  o := E'AND EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int > v_grace THEN';
  n := E'AND EXTRACT(EPOCH FROM (now() - v_accepted_at))::int > v_grace THEN';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'cancel: graca'; END IF;
  d := replace(d, o, n);
  o := E'''elapsed_seconds'', EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int));';
  n := E'''elapsed_seconds'', EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int,\n              ''seconds_since_accept'', EXTRACT(EPOCH FROM (now() - v_accepted_at))::int));';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'cancel: meta'; END IF;
  d := replace(d, o, n);
  EXECUTE d;
END $mig$;

-- ---------------------------------------------------------------------------
-- 6. Viagens do plano de outro cliente
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public.tvde_consume_subscription_ride(uuid)'::regprocedure);
  o := E'BEGIN\n  v_fds := EXTRACT(DOW';
  n := E'BEGIN\n  -- 2026-10-04 (auditoria): so o proprio cliente, o motorista da corrida em\n  -- curso desse cliente (fim da corrida) ou o admin. Chamadas internas sem\n  -- sessao (auth.uid() nulo) continuam.\n  IF auth.uid() IS NOT NULL AND auth.uid() <> p_client_id AND NOT public.is_admin()\n     AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r\n                      WHERE r.client_id = p_client_id AND r.driver_id = auth.uid()\n                        AND r.status = ''em_andamento'') THEN\n    RAISE EXCEPTION ''not_authorized'';\n  END IF;\n  v_fds := EXTRACT(DOW';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'consume: ancora'; END IF;
  EXECUTE replace(d, o, n);

  d := pg_get_functiondef('public.tvde_preview_coverage(uuid)'::regprocedure);
  o := E'BEGIN\n  v_fds := EXTRACT(DOW';
  n := E'BEGIN\n  -- 2026-10-04 (auditoria): ninguem le o plano de outro cliente.\n  IF auth.uid() IS NOT NULL AND auth.uid() <> p_client_id AND NOT public.is_admin() THEN\n    RETURN jsonb_build_object(''covered'', false, ''reason'', ''not_authorized'');\n  END IF;\n  v_fds := EXTRACT(DOW';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'preview: ancora'; END IF;
  EXECUTE replace(d, o, n);
END $mig$;
REVOKE ALL ON FUNCTION public.tvde_consume_subscription_ride(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_consume_subscription_ride(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.tvde_preview_coverage(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_preview_coverage(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Partilhar viagem em tempo real (Uber/Bolt)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tvde_partilhas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token       text NOT NULL UNIQUE,
  ride_id     uuid NOT NULL REFERENCES public.tvde_rides(id),
  criado_por  uuid NOT NULL,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  -- NULL enquanto a corrida decorre; ao terminar fica fim + 30 min.
  expira_em   timestamptz,
  origem      text NOT NULL DEFAULT 'corrida'   -- 'corrida' | 'sos'
);
CREATE INDEX IF NOT EXISTS tvde_partilhas_ride_idx ON public.tvde_partilhas(ride_id);
ALTER TABLE public.tvde_partilhas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tvde_partilhas FROM anon;
REVOKE ALL ON public.tvde_partilhas FROM authenticated;
GRANT SELECT ON public.tvde_partilhas TO authenticated;
DO $pol$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tvde_partilhas' AND policyname='tvde_partilhas_ler_dono_ou_admin') THEN
    CREATE POLICY tvde_partilhas_ler_dono_ou_admin ON public.tvde_partilhas
      FOR SELECT TO authenticated USING (criado_por = auth.uid() OR public.is_admin());
  END IF;
END $pol$;

CREATE OR REPLACE FUNCTION public.fn_tvde_partilha_expira()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista') THEN
    UPDATE public.tvde_partilhas SET expira_em = now() + interval '30 minutes'
     WHERE ride_id = NEW.id AND expira_em IS NULL;
  END IF;
  RETURN NEW;
END $fn$;
CREATE OR REPLACE TRIGGER trg_tvde_partilha_expira
  AFTER UPDATE OF status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_tvde_partilha_expira();

CREATE OR REPLACE FUNCTION public.tvde_criar_partilha(p_ride uuid, p_origem text DEFAULT 'corrida')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid(); v_ride public.tvde_rides; v_p public.tvde_partilhas; v_base text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.client_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'not_ride_client'; END IF;
  IF v_ride.status NOT IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento') THEN
    RAISE EXCEPTION 'ride_not_active: %', v_ride.status;
  END IF;
  SELECT * INTO v_p FROM public.tvde_partilhas
   WHERE ride_id = p_ride AND criado_por = v_uid AND expira_em IS NULL
   ORDER BY criado_em DESC LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.tvde_partilhas (token, ride_id, criado_por, origem)
    VALUES (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
            p_ride, v_uid, CASE WHEN p_origem = 'sos' THEN 'sos' ELSE 'corrida' END)
    RETURNING * INTO v_p;
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride, v_ride.status, 'cliente', jsonb_build_object('event', 'viagem_partilhada', 'origem', v_p.origem));
  END IF;
  v_base := COALESCE(public.get_setting('tvde_partilha_base_url') #>> '{}', 'https://app.boraguarda.com/viagem.html?t=');
  RETURN jsonb_build_object('token', v_p.token, 'url', v_base || v_p.token);
END $fn$;
REVOKE ALL ON FUNCTION public.tvde_criar_partilha(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_criar_partilha(uuid, text) TO authenticated, service_role;

-- Publica (anon): so o que um familiar precisa. Nada de telefones, nada da
-- morada exata de recolha; destino arredondado (~1 km).
CREATE OR REPLACE FUNCTION public.tvde_ver_partilha(p_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_p public.tvde_partilhas; v_r public.tvde_rides;
  v_nome text; v_carro text; v_cor text; v_mat text;
  v_lat double precision; v_lng double precision; v_pos_at timestamptz;
  v_km double precision; v_eta int; v_estado text; v_zona text;
BEGIN
  IF p_token IS NULL OR length(p_token) < 32 THEN RETURN jsonb_build_object('ok', false, 'motivo', 'invalida'); END IF;
  SELECT * INTO v_p FROM public.tvde_partilhas WHERE token = p_token;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'invalida'); END IF;
  IF (v_p.expira_em IS NOT NULL AND v_p.expira_em < now())
     OR v_p.criado_em < now() - interval '24 hours' THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'expirada');
  END IF;
  SELECT * INTO v_r FROM public.tvde_rides WHERE id = v_p.ride_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'invalida'); END IF;

  IF v_r.driver_id IS NOT NULL THEN
    SELECT split_part(trim(COALESCE(d.name, '')), ' ', 1),
           COALESCE(NULLIF(trim(concat_ws(' ', v.marca, v.modelo)), ''), NULLIF(trim(d.vehicle_make_model), '')),
           COALESCE(NULLIF(trim(v.cor), ''), NULLIF(trim(d.vehicle_color), '')),
           COALESCE(NULLIF(trim(v.matricula), ''), NULLIF(trim(d.license_plate), '')),
           COALESCE(l.latitude, d.lat)::double precision, COALESCE(l.longitude, d.lng)::double precision,
           l.last_updated
      INTO v_nome, v_carro, v_cor, v_mat, v_lat, v_lng, v_pos_at
      FROM public.drivers d
      LEFT JOIN LATERAL (SELECT dl.latitude, dl.longitude, dl.last_updated FROM public.driver_locations dl
                          WHERE dl.driver_id IN (d.user_id, d.id) ORDER BY dl.last_updated DESC NULLS LAST LIMIT 1) l ON true
      LEFT JOIN LATERAL (SELECT vv.* FROM public.tvde_driver_vehicle dv JOIN public.tvde_vehicles vv ON vv.id = dv.vehicle_id
                          WHERE dv.driver_user_id = d.user_id AND dv.ativo AND vv.estado = 'aprovado'
                          ORDER BY dv.desde DESC LIMIT 1) v ON true
     WHERE d.user_id = v_r.driver_id OR d.id = v_r.driver_id
     LIMIT 1;
  END IF;

  v_estado := CASE v_r.status
    WHEN 'solicitada' THEN 'A procurar motorista'
    WHEN 'motorista_atribuido' THEN 'Motorista a caminho'
    WHEN 'motorista_a_caminho' THEN 'Motorista a caminho da recolha'
    WHEN 'motorista_chegou' THEN 'Motorista no local de recolha'
    WHEN 'em_andamento' THEN 'Em viagem'
    WHEN 'finalizada' THEN 'Viagem concluída'
    ELSE 'Viagem terminada' END;

  -- ETA so em viagem: posicao do carro -> destino, 28 km/h x fator estrada 1,35.
  IF v_r.status = 'em_andamento' AND v_lat IS NOT NULL AND v_r.dest_lat IS NOT NULL THEN
    v_km := public._haversine_km(v_lat, v_lng, v_r.dest_lat, v_r.dest_lng) * 1.35;
    v_eta := GREATEST(1, CEIL(v_km / 28.0 * 60))::int;
  END IF;

  v_zona := NULLIF(trim(regexp_replace(split_part(COALESCE(v_r.dest_label, ''), ',',
              GREATEST(1, array_length(string_to_array(COALESCE(v_r.dest_label, ''), ','), 1))), '[0-9]{4}-[0-9]{3}', '')), '');

  RETURN jsonb_build_object(
    'ok', true,
    'estado', v_r.status,
    'estado_texto', v_estado,
    'terminada', v_r.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista'),
    'motorista', NULLIF(v_nome, ''),
    'carro', v_carro, 'cor', v_cor, 'matricula', v_mat,
    'lat', CASE WHEN v_r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento') THEN v_lat END,
    'lng', CASE WHEN v_r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento') THEN v_lng END,
    'posicao_em', v_pos_at,
    'destino_lat', round(v_r.dest_lat::numeric, 2),
    'destino_lng', round(v_r.dest_lng::numeric, 2),
    'destino_zona', v_zona,
    'eta_min', v_eta,
    'atualizado_em', now());
END $fn$;
REVOKE ALL ON FUNCTION public.tvde_ver_partilha(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tvde_ver_partilha(text) TO anon, authenticated, service_role;

-- Painel admin: indicar se a viagem foi partilhada
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public.admin_tvde_rides_list_v2(text,integer)'::regprocedure);
  o := E'''cancel_fee_cents'', r.cancel_fee_cents,\n             ''pacote_cents'', c.paid_cents,';
  n := E'''cancel_fee_cents'', r.cancel_fee_cents,\n             ''partilhada'', EXISTS (SELECT 1 FROM public.tvde_partilhas p WHERE p.ride_id = r.id),\n             ''pacote_cents'', c.paid_cents,';
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'rides_list_v2: ancora'; END IF;
  EXECUTE replace(d, o, n);
END $mig$;
