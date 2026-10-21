-- A2 · FILA INTELIGENTE — ronda 1 do revisor (REVISAO-A2.md). Missão fechar-pendencias-2026-10-20.
-- Corre DEPOIS de 20261021122851 / 20261021122930 / 20261021123223. A fila continua DESLIGADA.
--
-- R1  Número mal escrito numa chave da fila ('5,5', '40.5', 'abc') já não parte nada: a fila lê as
--     chaves com _tvde_fila_cfg_int/_num (valor por defeito se não for número, limites razoáveis);
--     o interruptor lê-se com _tvde_fila_ligada() (texto estranho = desligado); e QUALQUER erro dentro
--     da fila fica registado em tvde_fila_registo (o painel mostra) e a corrida segue pelo despacho de
--     sempre. Nada de EXCEPTION … THEN NULL calado.
-- R2  A nota vem das avaliações do Bora Motorista pelo user_id (ratings sem order_id), média simples
--     com mínimo de avaliações; senão a nota das entregas; senão 4,8. drivers não é tocada.
-- R3  O cadeado por motorista e a verificação "tem oferta viva noutra corrida" passam a ser DUAS
--     instruções: a verificação lê os dados já com o cadeado na mão.
-- R4  PADRÃO §1.23: quem não pode ser avisado (sem token, ou o push desta oferta falhou) não gasta os
--     40 s — o varrimento, com a fila ligada, encurta-lhe a oferta para tvde_fila_janela_sem_aviso_s.
-- R5  As filas de corridas aceites / canceladas / terminadas fecham-se (no varrimento, com a fila ligada).
--
-- Zona protegida: tvde_offer_to_next troca a SUA linha do interruptor (a do ramo A2) por
-- _tvde_fila_ligada(); tvde_dispatch_sweep ganha um bloco atrás do mesmo interruptor no início.
-- Provado aqui dentro: cada corpo, sem o que o A2 lhe acrescentou, tem o md5 de antes do A2.

-- ─── 1. Registo da fila (erros e ofertas encurtadas) ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tvde_fila_registo (
  id      bigserial PRIMARY KEY,
  em      timestamptz NOT NULL DEFAULT now(),
  ride_id uuid,
  tipo    text NOT NULL CHECK (tipo IN ('erro', 'oferta_encurtada')),
  detalhe jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_tvde_fila_registo_em ON public.tvde_fila_registo (em DESC);
ALTER TABLE public.tvde_fila_registo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.tvde_fila_registo FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.tvde_fila_registo FROM authenticated;
REVOKE ALL ON SEQUENCE public.tvde_fila_registo_id_seq FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS tvde_fila_registo_admin_le ON public.tvde_fila_registo;
CREATE POLICY tvde_fila_registo_admin_le ON public.tvde_fila_registo
  FOR SELECT TO authenticated USING (public.is_admin());

-- Estados novos: a oferta acabou porque a corrida saiu da procura (não foi culpa do motorista) e
-- a fila de uma corrida que terminou sem aceitação na lista.
ALTER TABLE public.tvde_fila_entradas DROP CONSTRAINT IF EXISTS tvde_fila_entradas_estado_check;
ALTER TABLE public.tvde_fila_entradas ADD CONSTRAINT tvde_fila_entradas_estado_check
  CHECK (estado IN ('espera', 'oferta', 'aceitou', 'recusou', 'expirou', 'saltado', 'cancelada'));
ALTER TABLE public.tvde_fila_rondas DROP CONSTRAINT IF EXISTS tvde_fila_rondas_estado_check;
ALTER TABLE public.tvde_fila_rondas ADD CONSTRAINT tvde_fila_rondas_estado_check
  CHECK (estado IN ('ativa', 'esgotada', 'aceite', 'anulada', 'terminada'));

INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_fila_nota_min_avaliacoes', '3'::jsonb,
   'Fila inteligente: avaliações do Bora Motorista precisas para usar a média delas; com menos, usa a nota das entregas ou 4,8.',
   'tvde'),
  ('tvde_fila_janela_sem_aviso_s', '10'::jsonb,
   'Fila inteligente ligada: a oferta a quem não pode ser avisado (sem notificação, ou o envio falhou) dura só estes segundos em vez do tempo inteiro (PADRÃO 1.23).',
   'tvde')
ON CONFLICT (key) DO NOTHING;

-- ─── 2. Leituras seguras ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_cfg_int(p_key text, p_def int, p_min int, p_max int)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v text := btrim(COALESCE(public.get_setting(p_key) #>> '{}', ''));
BEGIN
  IF v !~ '^-?[0-9]{1,9}$' THEN RETURN p_def; END IF;  -- '5,5', '40.5', 'abc', vazio → por defeito
  RETURN LEAST(GREATEST(v::int, p_min), p_max);
END;
$function$;

CREATE OR REPLACE FUNCTION public._tvde_fila_cfg_num(p_key text, p_def numeric, p_min numeric, p_max numeric)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v text := btrim(COALESCE(public.get_setting(p_key) #>> '{}', ''));
BEGIN
  IF v !~ '^-?[0-9]{1,9}([.,][0-9]{1,6})?$' THEN RETURN p_def; END IF;
  RETURN LEAST(GREATEST(replace(v, ',', '.')::numeric, p_min), p_max);
END;
$function$;

CREATE OR REPLACE FUNCTION public._tvde_fila_ligada()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(lower(btrim(public.get_setting('tvde_fila_inteligente_enabled') #>> '{}'))
                  IN ('true', 't', '1', 'on', 'sim'), false);
$function$;

-- O mesmo que a Edge notify-tvde-driver usa para tocar (drivers.fcm_token ou aparelho ativo).
CREATE OR REPLACE FUNCTION public._tvde_fila_pode_avisar(p_driver uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.drivers d
                  WHERE d.user_id = p_driver AND d.fcm_token IS NOT NULL AND length(d.fcm_token) > 0)
      OR EXISTS (SELECT 1 FROM public.driver_push_tokens t
                  WHERE t.user_id = p_driver AND t.active
                    AND t.fcm_token IS NOT NULL AND length(t.fcm_token) > 0);
$function$;

CREATE OR REPLACE FUNCTION public._tvde_fila_registar(p_ride uuid, p_tipo text, p_detalhe jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- O mesmo erro da mesma corrida no último minuto não se repete (o varrimento chama de 15 em 15 s).
  IF p_tipo = 'erro' AND EXISTS (
       SELECT 1 FROM public.tvde_fila_registo g
        WHERE g.tipo = 'erro' AND g.ride_id IS NOT DISTINCT FROM p_ride
          AND g.detalhe->>'mensagem' IS NOT DISTINCT FROM p_detalhe->>'mensagem'
          AND g.em > now() - interval '1 minute') THEN
    RETURN;
  END IF;
  INSERT INTO public.tvde_fila_registo (ride_id, tipo, detalhe) VALUES (p_ride, p_tipo, p_detalhe);
END;
$function$;

-- ─── 3. "Pode receber agora?" com a verificação de aviso partilhada ────────────────────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_motivo_fora(p_ride_id uuid, p_driver uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride public.tvde_rides;
  d      public.drivers;
  dl     public.driver_locations;
  v_hb   INT := (public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int;
  v_gps  INT := COALESCE((public.get_setting('dispatch_gps_fresh_seconds') #>> '{}')::int, 180);
  v_cool INT := COALESCE((public.get_setting('tvde_reject_cooldown_seconds') #>> '{}')::int, 600);
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN 'corrida_inexistente'; END IF;

  SELECT * INTO d FROM public.drivers x
   WHERE x.user_id = p_driver
   ORDER BY (x.vehicle_type = 'carro_passageiros' AND x.approval_status = 'approved') DESC NULLS LAST
   LIMIT 1;
  IF NOT FOUND THEN RETURN 'sem_ficha_de_motorista'; END IF;
  IF NOT COALESCE(d.vehicle_type = 'carro_passageiros' AND d.approval_status = 'approved'
                  AND d.user_id IS NOT NULL, false) THEN
    RETURN 'nao_e_motorista_aprovado';
  END IF;

  SELECT * INTO dl FROM public.driver_locations l
   WHERE l.driver_id IN (d.user_id, d.id)
   ORDER BY l.last_updated DESC NULLS LAST
   LIMIT 1;
  IF NOT FOUND THEN RETURN 'sem_posicao'; END IF;

  IF NOT COALESCE(dl.is_online = true OR d.is_online = true, false) THEN
    RETURN 'desligado';
  END IF;
  IF NOT COALESCE(GREATEST(COALESCE(dl.last_updated,     '-infinity'::timestamptz),
                           COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz))
                  > now() - make_interval(secs => v_hb), false) THEN
    RETURN 'sem_sinal_recente';
  END IF;
  IF NOT COALESCE(COALESCE(dl.last_updated, '-infinity'::timestamptz)
                  > now() - make_interval(secs => v_gps), false) THEN
    RETURN 'gps_velho';
  END IF;
  IF dl.latitude IS NULL OR dl.longitude IS NULL THEN RETURN 'sem_posicao'; END IF;
  IF NOT COALESCE(NOT (d.user_id = ANY(v_ride.tried_driver_ids)), false) THEN
    RETURN 'ja_tentado_nesta_procura';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.tvde_ride_events e
     WHERE e.ride_id = p_ride_id
       AND e.actor = 'driver'
       AND e.meta->>'rejected_by' = d.user_id::text
       AND e.at > now() - make_interval(secs => v_cool)) THEN
    RETURN 'recusou_ha_pouco';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.tvde_rides r2
     WHERE r2.driver_id = d.user_id
       AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RETURN 'ocupado_com_corrida';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.orders o
     WHERE o.assigned_driver_id IN (d.user_id::text, d.id::text)
       AND o.status IN ('driverAccepted','pickedUp','onTheWay')) THEN
    RETURN 'ocupado_com_entrega';
  END IF;
  IF NOT COALESCE(NOT public.tvde_driver_reservation_locked(d.user_id), false) THEN
    RETURN 'reserva_a_seguir';
  END IF;
  IF NOT COALESCE(public.tvde_driver_offer_allowed(d.user_id, p_ride_id), false) THEN
    RETURN 'papel_desligado_ou_conformidade';
  END IF;
  IF NOT public._tvde_fila_pode_avisar(d.user_id) THEN
    RETURN 'sem_aviso_no_telemovel';
  END IF;
  RETURN NULL;
END;
$function$;

-- ─── 4. A lista: leituras seguras e a nota do Bora Motorista pelo user_id (R1, R2) ─────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_nota(p_driver uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  -- 1.º: média simples das avaliações do Bora Motorista (tvde_rate grava subject_id = user_id e
  --      order_id vazio), com o mínimo de tvde_fila_nota_min_avaliacoes;
  -- 2.º: a nota das entregas (drivers.avg_rating) com o mesmo mínimo;
  -- 3.º: 4,8.
  SELECT COALESCE(
    (SELECT round(avg(r.stars)::numeric, 3) FROM public.ratings r
      WHERE r.subject_type = 'driver' AND r.subject_id = p_driver::text AND r.order_id IS NULL
        AND r.stars BETWEEN 1 AND 5
        AND r.is_private IS NOT TRUE AND r.flagged_inappropriate IS NOT TRUE
     HAVING count(*) >= public._tvde_fila_cfg_int('tvde_fila_nota_min_avaliacoes', 3, 1, 1000)),
    (SELECT round(d.avg_rating, 3) FROM public.drivers d
      WHERE d.user_id = p_driver AND d.avg_rating IS NOT NULL
        AND COALESCE(d.ratings_count, 0) >= public._tvde_fila_cfg_int('tvde_fila_nota_min_avaliacoes', 3, 1, 1000)
      ORDER BY d.ratings_count DESC NULLS LAST LIMIT 1),
    4.8);
$function$;

CREATE OR REPLACE FUNCTION public._tvde_fila_candidatos(p_ride_id uuid)
RETURNS TABLE (driver_id uuid, dist_km numeric, eta_min numeric, nota numeric,
               taxa_aceitacao numeric, pontos numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride   public.tvde_rides;
  -- "minutos de estrada" = LINHA RECTA à velocidade média (o banco não sabe a distância de estrada
  -- do motorista à recolha; é a mesma conta do ETA que o cliente já vê).
  v_speed  numeric := public._tvde_fila_cfg_num('eta_avg_speed_kmh', 28, 5, 120);
  v_pnota  numeric := public._tvde_fila_cfg_num('tvde_fila_peso_nota_min', 2, 0, 60);
  v_paceit numeric := public._tvde_fila_cfg_num('tvde_fila_peso_aceitacao_min', 5, 0, 60);
  v_dias   int     := public._tvde_fila_cfg_int('tvde_fila_historico_dias', 30, 1, 365);
  v_max    int     := public._tvde_fila_cfg_int('tvde_fila_max_motoristas', 5, 1, 20);
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT x.uid, x.dist, x.eta, x.nota_a, x.taxa_a,
         round(x.eta + v_pnota * (5 - x.nota_a) + v_paceit * (1 - x.taxa_a), 3) AS pts
    FROM (
      SELECT d.user_id AS uid,
             round(public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                        v_ride.origin_lat::numeric, v_ride.origin_lng::numeric), 3) AS dist,
             round(public._haversine_km(dl.latitude::numeric, dl.longitude::numeric,
                                        v_ride.origin_lat::numeric, v_ride.origin_lng::numeric)
                   / v_speed * 60, 2) AS eta,
             public._tvde_fila_nota(d.user_id) AS nota_a,
             (SELECT round((count(DISTINCT e.ride_id) FILTER (WHERE r.driver_id = d.user_id) + 0.8 * 5)
                           / (count(DISTINCT e.ride_id) + 5.0), 3)
                FROM public.tvde_ride_events e
                JOIN public.tvde_rides r ON r.id = e.ride_id
               WHERE e.status = 'oferta'
                 AND e.meta->>'driver_id' = d.user_id::text
                 AND e.ride_id <> p_ride_id
                 AND e.at > now() - make_interval(days => v_dias)) AS taxa_a
        FROM (SELECT DISTINCT ON (dd.user_id) dd.*
                FROM public.drivers dd
               WHERE dd.vehicle_type = 'carro_passageiros'
                 AND dd.approval_status = 'approved'
                 AND dd.user_id IS NOT NULL
               ORDER BY dd.user_id, dd.id) d
        JOIN LATERAL (
          SELECT * FROM public.driver_locations l
           WHERE l.driver_id IN (d.user_id, d.id)
           ORDER BY l.last_updated DESC NULLS LAST
           LIMIT 1
        ) dl ON true
       WHERE public._tvde_fila_motivo_fora(p_ride_id, d.user_id) IS NULL
    ) x
   ORDER BY pts ASC, x.dist ASC, x.uid ASC
   LIMIT v_max;
END;
$function$;

-- ─── 5. O núcleo da fila (era o corpo da _tvde_fila_oferecer) — R1 e R3 ────────────────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_oferecer_nucleo(p_ride_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride      public.tvde_rides;
  v_ronda     public.tvde_fila_rondas;
  v_tem_ronda boolean := false;
  v_e         public.tvde_fila_entradas;
  v_fim       text;
  v_motivo    text;
  -- o mesmo relógio que a oferta de sempre e a Edge usam; lido sem rebentar
  v_ttl       INT := public._tvde_fila_cfg_int('tvde_offer_ttl_seconds', 40, 1, 600);
  v_espera    boolean := false;
  v_n         int;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND OR v_ride.status <> 'solicitada' OR v_ride.dispatch_hold_reason IS NOT NULL THEN
    RETURN NULL;
  END IF;
  IF COALESCE(v_ride.source, 'app') = 'balcao' THEN RETURN NULL; END IF;

  SELECT * INTO v_ronda FROM public.tvde_fila_rondas
   WHERE ride_id = p_ride_id ORDER BY ronda DESC LIMIT 1 FOR UPDATE;
  v_tem_ronda := FOUND;

  -- (a) fechar a entrada que estava com a oferta, se a oferta já acabou
  IF v_tem_ronda AND v_ronda.estado = 'ativa' THEN
    SELECT * INTO v_e FROM public.tvde_fila_entradas
     WHERE ronda_id = v_ronda.id AND estado = 'oferta' LIMIT 1;
    IF FOUND THEN
      IF v_ride.current_offer_driver_id = v_e.driver_id
         AND v_ride.offer_expires_at IS NOT NULL AND v_ride.offer_expires_at > now() THEN
        RETURN true;
      END IF;
      v_fim := CASE
        WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events e
                      WHERE e.ride_id = p_ride_id AND e.actor = 'driver'
                        AND e.status = 'motorista_atribuido'
                        AND e.at >= v_e.oferecida_em) THEN 'aceitou'
        WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events e
                      WHERE e.ride_id = p_ride_id AND e.actor = 'driver'
                        AND e.meta->>'rejected_by' = v_e.driver_id::text
                        AND COALESCE(e.meta->>'stale', 'false') <> 'true'
                        AND e.at >= v_e.oferecida_em) THEN 'recusou'
        ELSE 'expirou' END;
      UPDATE public.tvde_fila_entradas SET estado = v_fim, terminou_em = now() WHERE id = v_e.id;
      IF v_fim = 'aceitou' THEN
        UPDATE public.tvde_fila_rondas
           SET estado = 'aceite', terminou_em = now(), motivo_fim = 'aceite; a corrida voltou a procurar'
         WHERE id = v_ronda.id;
        v_ronda.estado := 'aceite';
      END IF;
    END IF;
  END IF;

  -- (b) nova roda pedida depois do cálculo → lista nova
  IF v_tem_ronda AND v_ronda.estado IN ('ativa', 'esgotada')
     AND EXISTS (SELECT 1 FROM public.tvde_ride_events e
                  WHERE e.ride_id = p_ride_id
                    AND e.status IN ('nova_roda', 'reserva_redespachada')
                    AND e.at > v_ronda.calculada_em) THEN
    UPDATE public.tvde_fila_entradas
       SET estado = 'saltado', terminou_em = now(), motivo = 'nova roda pedida'
     WHERE ronda_id = v_ronda.id AND estado = 'espera';
    UPDATE public.tvde_fila_rondas
       SET estado = 'anulada', terminou_em = now(), motivo_fim = 'nova roda pedida'
     WHERE id = v_ronda.id;
    v_ronda.estado := 'anulada';
  END IF;

  -- (c) calcular a lista — UMA vez por procura
  IF NOT v_tem_ronda OR v_ronda.estado IN ('aceite', 'anulada', 'terminada') THEN
    INSERT INTO public.tvde_fila_rondas (ride_id, ronda, criterios)
    VALUES (p_ride_id,
            COALESCE((SELECT max(ronda) FROM public.tvde_fila_rondas WHERE ride_id = p_ride_id), 0) + 1,
            jsonb_build_object(
              'velocidade_kmh', public._tvde_fila_cfg_num('eta_avg_speed_kmh', 28, 5, 120),
              'distancia', 'linha recta',
              'peso_nota_min', public._tvde_fila_cfg_num('tvde_fila_peso_nota_min', 2, 0, 60),
              'peso_aceitacao_min', public._tvde_fila_cfg_num('tvde_fila_peso_aceitacao_min', 5, 0, 60),
              'historico_dias', public._tvde_fila_cfg_int('tvde_fila_historico_dias', 30, 1, 365),
              'max_motoristas', public._tvde_fila_cfg_int('tvde_fila_max_motoristas', 5, 1, 20),
              'nota_min_avaliacoes', public._tvde_fila_cfg_int('tvde_fila_nota_min_avaliacoes', 3, 1, 1000),
              'oferta_s', v_ttl))
    RETURNING * INTO v_ronda;

    INSERT INTO public.tvde_fila_entradas
      (ronda_id, ride_id, pos, driver_id, dist_km, eta_min, nota, taxa_aceitacao, pontos)
    SELECT v_ronda.id, p_ride_id,
           row_number() OVER (ORDER BY c.pontos ASC, c.dist_km ASC, c.driver_id ASC),
           c.driver_id, c.dist_km, c.eta_min, c.nota, c.taxa_aceitacao, c.pontos
      FROM public._tvde_fila_candidatos(p_ride_id) c;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE public.tvde_fila_rondas SET n_candidatos = v_n WHERE id = v_ronda.id;
    IF v_n = 0 THEN
      UPDATE public.tvde_fila_rondas
         SET estado = 'esgotada', terminou_em = now(),
             motivo_fim = 'ninguém disponível e com aviso no telemóvel ao pedir'
       WHERE id = v_ronda.id;
      v_ronda.estado := 'esgotada';
    END IF;
  END IF;

  IF v_ronda.estado <> 'ativa' THEN
    RETURN NULL;
  END IF;

  -- (d) o primeiro da lista, pela ordem, que pode receber AGORA
  FOR v_e IN
    SELECT * FROM public.tvde_fila_entradas
     WHERE ronda_id = v_ronda.id AND estado = 'espera'
     ORDER BY pos
  LOOP
    v_motivo := public._tvde_fila_motivo_fora(p_ride_id, v_e.driver_id);
    IF v_motivo IS NOT NULL THEN
      UPDATE public.tvde_fila_entradas
         SET estado = 'saltado', terminou_em = now(), motivo = v_motivo
       WHERE id = v_e.id;
      CONTINUE;
    END IF;
    -- R3: primeiro o cadeado; só DEPOIS (outra instrução, dados lidos já com o cadeado na mão)
    -- a verificação "tem agora outra oferta a tocar?".
    IF NOT pg_try_advisory_xact_lock(hashtextextended('tvde_fila_motorista:' || v_e.driver_id::text, 0)) THEN
      v_espera := true;
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM public.tvde_rides o
                WHERE o.id <> p_ride_id
                  AND ((o.status = 'solicitada' AND o.current_offer_driver_id = v_e.driver_id
                        AND o.offer_expires_at > now())
                    OR (o.reservation_offer_driver_id = v_e.driver_id
                        AND o.reservation_offer_expires_at > now()))) THEN
      v_espera := true;
      CONTINUE;
    END IF;

    UPDATE public.tvde_rides
       SET current_offer_driver_id = v_e.driver_id,
           offer_expires_at = now() + make_interval(secs => v_ttl),
           no_driver_since = NULL, updated_at = now()
     WHERE id = p_ride_id;
    INSERT INTO public.tvde_ride_events(ride_id, status, actor, meta)
      VALUES (p_ride_id, 'oferta', 'system',
              jsonb_build_object('driver_id', v_e.driver_id, 'expires_in_s', v_ttl,
                                 'queued_candidate', false, 'fila_justa', false,
                                 'fila_inteligente', true, 'fila_pos', v_e.pos,
                                 'fila_ronda', v_ronda.ronda));
    UPDATE public.tvde_fila_entradas
       SET estado = 'oferta', oferecida_em = now(),
           expira_em = now() + make_interval(secs => v_ttl)
     WHERE id = v_e.id;
    RETURN true;
  END LOOP;

  IF v_espera THEN
    UPDATE public.tvde_rides
       SET no_driver_since = COALESCE(v_ride.no_driver_since, now()),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id;
    RETURN false;
  END IF;

  UPDATE public.tvde_fila_rondas
     SET estado = 'esgotada', terminou_em = now(), motivo_fim = 'lista percorrida até ao fim'
   WHERE id = v_ronda.id;
  RETURN NULL;
END;
$function$;

-- A porta de entrada que a tvde_offer_to_next chama: QUALQUER erro da fila → regista e devolve
-- NULL (= despacho de sempre). O que a fila escreveu antes do erro volta atrás (sub-transacção).
CREATE OR REPLACE FUNCTION public._tvde_fila_oferecer(p_ride_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_estado text; v_msg text; v_ctx text;
BEGIN
  RETURN public._tvde_fila_oferecer_nucleo(p_ride_id);
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_ctx = PG_EXCEPTION_CONTEXT;
  BEGIN
    PERFORM public._tvde_fila_registar(p_ride_id, 'erro',
      jsonb_build_object('onde', 'oferecer', 'sqlstate', v_estado, 'mensagem', v_msg,
                         'contexto', left(v_ctx, 1500), 'seguiu', 'despacho de sempre'));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tvde_fila: não consegui registar o erro "%" (%)', v_msg, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

-- ─── 6. O passo do varrimento (só com a fila ligada) — R4 e R5 ─────────────────────────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_varrimento_nucleo()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r       record;
  v_jan   int := public._tvde_fila_cfg_int('tvde_fila_janela_sem_aviso_s', 10, 5, 40);
  v_falhou boolean;
BEGIN
  -- R5: a corrida saiu da procura → a fila dela fecha (aceite / terminada).
  FOR r IN
    SELECT fr.id AS ronda_id, t.status, t.driver_id
      FROM public.tvde_fila_rondas fr
      JOIN public.tvde_rides t ON t.id = fr.ride_id
     WHERE fr.estado = 'ativa' AND t.status <> 'solicitada'
  LOOP
    UPDATE public.tvde_fila_entradas e
       SET estado = CASE
             WHEN e.driver_id = r.driver_id THEN 'aceitou'
             WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events x
                           WHERE x.ride_id = e.ride_id AND x.actor = 'driver'
                             AND x.meta->>'rejected_by' = e.driver_id::text
                             AND COALESCE(x.meta->>'stale', 'false') <> 'true'
                             AND x.at >= e.oferecida_em) THEN 'recusou'
             WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events x
                           WHERE x.ride_id = e.ride_id AND x.status = 'oferta_expirada'
                             AND x.meta->>'driver_id' = e.driver_id::text
                             AND x.at >= e.oferecida_em) THEN 'expirou'
             ELSE 'cancelada' END,
           terminou_em = now()
     WHERE e.ronda_id = r.ronda_id AND e.estado = 'oferta';
    UPDATE public.tvde_fila_entradas e
       SET motivo = 'corrida ' || r.status
     WHERE e.ronda_id = r.ronda_id AND e.estado = 'cancelada' AND e.motivo IS NULL;
    UPDATE public.tvde_fila_rondas
       SET estado = CASE WHEN EXISTS (SELECT 1 FROM public.tvde_fila_entradas e
                                       WHERE e.ronda_id = r.ronda_id AND e.estado = 'aceitou')
                         THEN 'aceite' ELSE 'terminada' END,
           terminou_em = now(),
           motivo_fim = 'corrida ' || r.status
     WHERE id = r.ronda_id;
  END LOOP;

  -- R4 (PADRÃO §1.23): oferta viva a quem não pode ser avisado (sem token, ou o push desta oferta
  -- falhou) dura só v_jan segundos desde que foi feita — não os 40 s inteiros. Balcão fica como está.
  FOR r IN
    SELECT t.id, t.current_offer_driver_id AS drv, t.offer_expires_at,
           (SELECT max(e.at) FROM public.tvde_ride_events e
             WHERE e.ride_id = t.id AND e.status = 'oferta'
               AND e.meta->>'driver_id' = t.current_offer_driver_id::text) AS ofertada_em
      FROM public.tvde_rides t
     WHERE t.status = 'solicitada'
       AND t.current_offer_driver_id IS NOT NULL
       AND t.offer_expires_at > now()
       AND COALESCE(t.source, 'app') <> 'balcao'
  LOOP
    CONTINUE WHEN r.ofertada_em IS NULL
               OR r.offer_expires_at <= r.ofertada_em + make_interval(secs => v_jan);
    v_falhou := EXISTS (SELECT 1 FROM public.tvde_ride_events e
                         WHERE e.ride_id = r.id AND e.status = 'push_falhou'
                           AND e.meta->>'driver_id' = r.drv::text
                           AND e.at >= r.ofertada_em);
    CONTINUE WHEN public._tvde_fila_pode_avisar(r.drv) AND NOT v_falhou;
    UPDATE public.tvde_rides
       SET offer_expires_at = r.ofertada_em + make_interval(secs => v_jan), updated_at = now()
     WHERE id = r.id AND status = 'solicitada' AND current_offer_driver_id = r.drv;
    PERFORM public._tvde_fila_registar(r.id, 'oferta_encurtada',
      jsonb_build_object('driver_id', r.drv, 'janela_s', v_jan, 'era_ate', r.offer_expires_at,
                         'motivo', CASE WHEN v_falhou THEN 'push_falhou' ELSE 'sem_aviso_no_telemovel' END));
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public._tvde_fila_varrimento()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_estado text; v_msg text; v_ctx text;
BEGIN
  PERFORM public._tvde_fila_varrimento_nucleo();
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_ctx = PG_EXCEPTION_CONTEXT;
  BEGIN
    PERFORM public._tvde_fila_registar(NULL, 'erro',
      jsonb_build_object('onde', 'varrimento', 'sqlstate', v_estado, 'mensagem', v_msg,
                         'contexto', left(v_ctx, 1500), 'seguiu', 'varrimento de sempre'));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tvde_fila: não consegui registar o erro "%" (%)', v_msg, SQLERRM;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public._tvde_fila_cfg_int(text, int, int, int)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_cfg_num(text, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_ligada()                          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_pode_avisar(uuid)                 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_registar(uuid, text, jsonb)       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_motivo_fora(uuid, uuid)           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_nota(uuid)                        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_candidatos(uuid)                  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_oferecer_nucleo(uuid)             FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_oferecer(uuid)                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_varrimento_nucleo()               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_varrimento()                      FROM PUBLIC, anon, authenticated;

-- ─── 7. Painel: estado efetivo com "cancelada" e o registo de erros/encurtadas ─────────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_estado_efetivo(p_e public.tvde_fila_entradas,
                                                          p_r public.tvde_rides)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_e.estado <> 'oferta' THEN p_e.estado
    WHEN p_r.driver_id = p_e.driver_id THEN 'aceitou'
    WHEN p_r.status = 'solicitada' AND p_r.current_offer_driver_id = p_e.driver_id
         AND p_r.offer_expires_at > now() THEN 'oferta'
    WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events e
                  WHERE e.ride_id = p_e.ride_id AND e.actor = 'driver'
                    AND e.meta->>'rejected_by' = p_e.driver_id::text
                    AND COALESCE(e.meta->>'stale', 'false') <> 'true'
                    AND e.at >= p_e.oferecida_em) THEN 'recusou'
    WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events e
                  WHERE e.ride_id = p_e.ride_id AND e.status = 'oferta_expirada'
                    AND e.meta->>'driver_id' = p_e.driver_id::text
                    AND e.at >= p_e.oferecida_em) THEN 'expirou'
    WHEN p_r.status <> 'solicitada' THEN 'cancelada'
    ELSE 'expirou' END;
$function$;
REVOKE ALL ON FUNCTION public._tvde_fila_estado_efetivo(public.tvde_fila_entradas, public.tvde_rides)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_tvde_fila_registo(p_horas int DEFAULT 24, p_limite int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin uuid;
  v_out   jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'em', g.em, 'ride_id', g.ride_id, 'tipo', g.tipo, 'detalhe', g.detalhe,
           'motorista', (SELECT d.name FROM public.drivers d
                          WHERE d.user_id::text = g.detalhe->>'driver_id' LIMIT 1))
         ORDER BY g.em DESC), '[]'::jsonb)
    INTO v_out
    FROM (SELECT * FROM public.tvde_fila_registo
           WHERE em > now() - make_interval(hours => GREATEST(1, LEAST(COALESCE(p_horas, 24), 24 * 31)))
           ORDER BY em DESC
           LIMIT GREATEST(1, LEAST(COALESCE(p_limite, 100), 1000))) g;
  RETURN v_out;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_tvde_fila_registo(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_fila_registo(int, int) TO authenticated, service_role;

-- ─── 8. Zona protegida: as duas funções de despacho (por âncora, com prova) ────────────────────
DO $patch$
DECLARE
  c_md5_offer_a2   constant text := '5771881b98cf452db9e41ef7cd2e28b3';  -- no ar depois do A2
  c_md5_offer_orig constant text := '40dd523a5b9c6dc9dbbbb5848abfef4f';  -- antes do A2
  c_md5_sweep_orig constant text := '6218c0a368cb0d3601e165fa2cfb4d8d';
  c_if_velho  constant text := E'  IF COALESCE((public.get_setting(''tvde_fila_inteligente_enabled'') #>> ''{}'')::boolean, false) THEN\n    v_fila_ia := public._tvde_fila_oferecer(p_ride_id);\n';
  c_if_novo   constant text := E'  IF public._tvde_fila_ligada() THEN\n    v_fila_ia := public._tvde_fila_oferecer(p_ride_id);\n';
  c_a2_decl   constant text := E'  v_fila_ia BOOLEAN;  -- 2026-10-21 (A2) fila inteligente\n';
  c_a2_corpo  constant text := $blk$
  -- 2026-10-21 (A2) FILA INTELIGENTE, atrás do interruptor tvde_fila_inteligente_enabled.
  -- Desligado: nada disto corre e segue o caminho de sempre, linha a linha. Ligado: a lista
  -- calculada uma vez manda; NULL = não se aplica (balcão) ou lista esgotada -> caminho de sempre.
  IF public._tvde_fila_ligada() THEN
    v_fila_ia := public._tvde_fila_oferecer(p_ride_id);
    IF v_fila_ia IS NOT NULL THEN RETURN v_fila_ia; END IF;
  END IF;
$blk$;
  c_ancora_sweep constant text := E'BEGIN\n  IF v_max_min > 0 THEN\n';
  c_sweep_bloco  constant text := $blk$
  -- 2026-10-21 (A2) FILA INTELIGENTE: arrumação atrás do interruptor (desligado = nada disto corre).
  -- Fecha a fila das corridas que saíram da procura e encurta a oferta a quem não pode ser avisado
  -- (PADRÃO 1.23). Um erro aqui fica registado e o varrimento de sempre segue igual.
  IF public._tvde_fila_ligada() THEN
    PERFORM public._tvde_fila_varrimento();
  END IF;

$blk$;
  v_o   oid := 'public.tvde_offer_to_next(uuid)'::regprocedure;
  v_s   oid := 'public.tvde_dispatch_sweep()'::regprocedure;
  v_src text; v_def text; v_acl text; v_n int;
BEGIN
  -- tvde_offer_to_next: a linha do interruptor do A2 passa a ler-se sem rebentar
  SELECT prosrc, pg_get_functiondef(oid), proacl::text INTO v_src, v_def, v_acl FROM pg_proc WHERE oid = v_o;
  IF md5(v_src) <> c_md5_offer_a2 THEN
    RAISE EXCEPTION 'A2r1: tvde_offer_to_next não é a do A2 (md5 %)', md5(v_src);
  END IF;
  v_n := (length(v_def) - length(replace(v_def, c_if_velho, ''))) / length(c_if_velho);
  IF v_n <> 1 THEN RAISE EXCEPTION 'A2r1: âncora do interruptor aparece % vezes', v_n; END IF;
  EXECUTE replace(v_def, c_if_velho, c_if_novo);
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_o;
  IF md5(replace(replace(v_src, c_a2_decl, ''), c_a2_corpo, '')) <> c_md5_offer_orig THEN
    RAISE EXCEPTION 'A2r1: tvde_offer_to_next sem o ramo NÃO é a de antes do A2';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = v_o) IS DISTINCT FROM v_acl THEN
    RAISE EXCEPTION 'A2r1: permissões da tvde_offer_to_next mudaram';
  END IF;

  -- tvde_dispatch_sweep: bloco no início, atrás do interruptor
  SELECT prosrc, pg_get_functiondef(oid), proacl::text INTO v_src, v_def, v_acl FROM pg_proc WHERE oid = v_s;
  IF md5(v_src) <> c_md5_sweep_orig THEN
    RAISE EXCEPTION 'A2r1: tvde_dispatch_sweep mudou no ar (md5 %)', md5(v_src);
  END IF;
  v_n := (length(v_def) - length(replace(v_def, c_ancora_sweep, ''))) / length(c_ancora_sweep);
  IF v_n <> 1 THEN RAISE EXCEPTION 'A2r1: âncora do varrimento aparece % vezes', v_n; END IF;
  EXECUTE replace(v_def, c_ancora_sweep, E'BEGIN\n' || c_sweep_bloco || E'  IF v_max_min > 0 THEN\n');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_s;
  IF md5(replace(v_src, c_sweep_bloco, '')) <> c_md5_sweep_orig THEN
    RAISE EXCEPTION 'A2r1: tvde_dispatch_sweep sem o bloco NÃO é a de antes';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = v_s) IS DISTINCT FROM v_acl
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_s)
     OR (SELECT proconfig::text FROM pg_proc WHERE oid = v_s) IS DISTINCT FROM '{search_path=public}' THEN
    RAISE EXCEPTION 'A2r1: cabeçalho ou permissões da tvde_dispatch_sweep mudaram';
  END IF;
  RAISE NOTICE 'A2r1 aplicado: offer %, sweep %',
    (SELECT md5(prosrc) FROM pg_proc WHERE oid = v_o), (SELECT md5(prosrc) FROM pg_proc WHERE oid = v_s);
END
$patch$;
