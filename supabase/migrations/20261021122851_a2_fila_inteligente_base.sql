-- A2 · FILA INTELIGENTE do Bora Motorista — parte ADITIVA (missão fechar-pendencias-2026-10-20).
-- Decisão do Danilo (15/10/2026): "Fila inteligente ligada: se o 1.º não aceitar em 40 s, passa ao
-- 2.º da mesma fila, sem recalcular." Coberta pelo "vai" de 20/10.
--
-- NADA aqui muda o despacho de hoje. Cria as peças que a tvde_offer_to_next só chama com o
-- interruptor tvde_fila_inteligente_enabled LIGADO (nasce DESLIGADO; liga-se no fim, depois das
-- provas). A tvde_dispatch_sweep não muda (nem uma letra).
--
-- Desenho:
--  * Ao pedir (1.ª chamada da tvde_offer_to_next), calcula-se UMA vez a lista ordenada dos
--    motoristas que podem receber AGORA (os mesmos filtros da prioridade 1 de sempre: livres,
--    online, sinal e GPS frescos, papel TVDE ligado, conformidade, sem reserva a seguir, sem
--    recusa recente) + SÓ quem pode ser avisado (token de push ativo — PADRÃO §1.23).
--  * Ordem por pontos = minutos de estrada até à recolha (linha recta à eta_avg_speed_kmh, o
--    mesmo ETA que o cliente já vê) + peso × (5 − nota) + peso × (1 − taxa de aceitação).
--    Nota e taxa são alisadas (prior 4,8 ★ e 80 %, peso 5) para um motorista novo não ganhar
--    nem perder tudo com 1 avaliação ou 1 oferta.
--  * Oferece ao 1.º; quando a oferta acaba (expirou no varrimento, recusou), passa ao seguinte
--    da MESMA lista, sem recalcular. Quem entretanto deixou de poder receber é saltado (fica
--    registado porquê); quem está nesse instante com oferta viva noutra corrida fica na lista
--    e espera a vez (assim 3 corridas ao mesmo tempo nunca tocam ao mesmo motorista).
--  * Lista esgotada (ou vazia logo à partida) → devolve NULL e a tvde_offer_to_next segue o
--    caminho de sempre (o mais perto, a sobreposição, a pausa de 35 s, etc.).
--  * Corridas de balcão continuam na "fila justa" de 18/09 (não entram aqui).
--  * O tempo de cada oferta é o de sempre: tvde_offer_ttl_seconds (40 s). Não se cria um
--    segundo relógio: a Edge notify-tvde-driver re-ancora a oferta com essa chave, e um
--    "tvde_fila_timeout_s" à parte seria um gémeo que mentia.

-- ─── 0. Backup das duas funções de despacho, tal como estão no ar (texto + md5) ───────────────
CREATE TABLE IF NOT EXISTS public.bkp_fn_fila_20261021 (
  fn          text PRIMARY KEY,
  args        text NOT NULL,
  def         text NOT NULL,
  md5_def     text NOT NULL,
  src         text NOT NULL,
  md5_src     text NOT NULL,
  guardado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.bkp_fn_fila_20261021 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bkp_fn_fila_20261021 FROM PUBLIC, anon, authenticated;

INSERT INTO public.bkp_fn_fila_20261021 (fn, args, def, md5_def, src, md5_src)
SELECT p.proname, pg_get_function_identity_arguments(p.oid),
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)),
       p.prosrc, md5(p.prosrc)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('tvde_offer_to_next', 'tvde_dispatch_sweep')
ON CONFLICT (fn) DO NOTHING;

-- ─── 1. Interruptor e parâmetros (categoria tvde → aparecem no painel) ─────────────────────────
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_fila_inteligente_enabled', 'false'::jsonb,
   'Fila inteligente do Bora Motorista: ao pedir, calcula UMA vez a lista ordenada (tempo de estrada, nota, taxa de aceitação) só com quem pode ser avisado; se o 1.º não aceitar no tempo da oferta (tvde_offer_ttl_seconds), passa ao 2.º da MESMA lista. Lista esgotada = despacho de sempre. Desligado = despacho de sempre, sem mudança nenhuma.',
   'tvde'),
  ('tvde_fila_max_motoristas', '5'::jsonb,
   'Fila inteligente: quantos motoristas entram na lista de cada corrida (os melhores). Depois deles, despacho de sempre.',
   'tvde'),
  ('tvde_fila_peso_nota_min', '2'::jsonb,
   'Fila inteligente: minutos de "castigo" por cada estrela abaixo de 5 (nota alisada).',
   'tvde'),
  ('tvde_fila_peso_aceitacao_min', '5'::jsonb,
   'Fila inteligente: minutos de "castigo" para quem aceita 0% das ofertas (proporcional: 50% = metade).',
   'tvde'),
  ('tvde_fila_historico_dias', '30'::jsonb,
   'Fila inteligente: dias de histórico de ofertas usados para a taxa de aceitação.',
   'tvde')
ON CONFLICT (key) DO NOTHING;

-- ─── 2. Onde a lista vive (com a corrida) ──────────────────────────────────────────────────────
-- Uma "ronda" = uma procura. Calcula-se 1 vez; só há ronda nova se a corrida voltar a procurar
-- depois de alguém ter aceitado (motorista desistiu) ou se o admin/varrimento pedir nova roda.
CREATE TABLE IF NOT EXISTS public.tvde_fila_rondas (
  id           bigserial PRIMARY KEY,
  ride_id      uuid NOT NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  ronda        int  NOT NULL,
  calculada_em timestamptz NOT NULL DEFAULT now(),
  estado       text NOT NULL DEFAULT 'ativa'
               CHECK (estado IN ('ativa', 'esgotada', 'aceite', 'anulada')),
  terminou_em  timestamptz,
  motivo_fim   text,
  n_candidatos int  NOT NULL DEFAULT 0,
  criterios    jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (ride_id, ronda)
);

CREATE TABLE IF NOT EXISTS public.tvde_fila_entradas (
  id             bigserial PRIMARY KEY,
  ronda_id       bigint NOT NULL REFERENCES public.tvde_fila_rondas(id) ON DELETE CASCADE,
  ride_id        uuid   NOT NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  pos            int    NOT NULL,
  driver_id      uuid   NOT NULL,           -- user_id do motorista (identidade: PADRÃO)
  dist_km        numeric NOT NULL,
  eta_min        numeric NOT NULL,
  nota           numeric NOT NULL,
  taxa_aceitacao numeric NOT NULL,
  pontos         numeric NOT NULL,
  estado         text NOT NULL DEFAULT 'espera'
                 CHECK (estado IN ('espera', 'oferta', 'aceitou', 'recusou', 'expirou', 'saltado')),
  oferecida_em   timestamptz,
  expira_em      timestamptz,
  terminou_em    timestamptz,
  motivo         text,
  UNIQUE (ronda_id, pos),
  UNIQUE (ronda_id, driver_id)
);
CREATE INDEX IF NOT EXISTS idx_tvde_fila_entradas_ride ON public.tvde_fila_entradas (ride_id);
CREATE INDEX IF NOT EXISTS idx_tvde_fila_entradas_driver_estado ON public.tvde_fila_entradas (driver_id, estado);
CREATE INDEX IF NOT EXISTS idx_tvde_fila_rondas_ride ON public.tvde_fila_rondas (ride_id, ronda DESC);

ALTER TABLE public.tvde_fila_rondas   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tvde_fila_entradas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.tvde_fila_rondas   FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.tvde_fila_entradas FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.tvde_fila_rondas   FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.tvde_fila_entradas FROM authenticated;
REVOKE ALL ON SEQUENCE public.tvde_fila_rondas_id_seq   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.tvde_fila_entradas_id_seq FROM PUBLIC, anon, authenticated;
-- Só o admin lê (o painel usa as RPCs abaixo; isto é para o editor/exportar). Ninguém escreve
-- a não ser as funções do servidor (SECURITY DEFINER).
DROP POLICY IF EXISTS tvde_fila_rondas_admin_le ON public.tvde_fila_rondas;
CREATE POLICY tvde_fila_rondas_admin_le ON public.tvde_fila_rondas
  FOR SELECT TO authenticated USING (public.is_admin());
DROP POLICY IF EXISTS tvde_fila_entradas_admin_le ON public.tvde_fila_entradas;
CREATE POLICY tvde_fila_entradas_admin_le ON public.tvde_fila_entradas
  FOR SELECT TO authenticated USING (public.is_admin());

-- ─── 3. Pode este motorista receber esta corrida AGORA? (NULL = sim; texto = porque não) ───────
-- Os filtros são os MESMOS da prioridade 1 (livres) da tvde_offer_to_next, um a um, mais o
-- "pode ser avisado". Cada condição é a de lá, embrulhada em COALESCE(…, false) para que um
-- NULL exclua (como num WHERE) em vez de deixar passar.
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
  -- PADRÃO §1.23: só entra quem pode mesmo ser avisado (o mesmo que a Edge notify-tvde-driver
  -- usa para tocar: drivers.fcm_token ou um aparelho ativo em driver_push_tokens).
  IF NOT ((d.fcm_token IS NOT NULL AND length(d.fcm_token) > 0)
          OR EXISTS (SELECT 1 FROM public.driver_push_tokens t
                      WHERE t.user_id = d.user_id AND t.active
                        AND t.fcm_token IS NOT NULL AND length(t.fcm_token) > 0)) THEN
    RETURN 'sem_aviso_no_telemovel';
  END IF;
  RETURN NULL;
END;
$function$;

-- ─── 4. A lista ordenada (calculada uma vez por procura) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public._tvde_fila_candidatos(p_ride_id uuid)
RETURNS TABLE (driver_id uuid, dist_km numeric, eta_min numeric, nota numeric,
               taxa_aceitacao numeric, pontos numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride   public.tvde_rides;
  v_speed  numeric := COALESCE((public.get_setting('eta_avg_speed_kmh') #>> '{}')::numeric, 28);
  v_pnota  numeric := COALESCE((public.get_setting('tvde_fila_peso_nota_min') #>> '{}')::numeric, 2);
  v_paceit numeric := COALESCE((public.get_setting('tvde_fila_peso_aceitacao_min') #>> '{}')::numeric, 5);
  v_dias   int     := COALESCE((public.get_setting('tvde_fila_historico_dias') #>> '{}')::int, 30);
  v_max    int     := COALESCE((public.get_setting('tvde_fila_max_motoristas') #>> '{}')::int, 5);
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_speed IS NULL OR v_speed <= 0 THEN v_speed := 28; END IF;
  IF v_max IS NULL OR v_max < 1 THEN v_max := 1; END IF;

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
             -- nota alisada: (soma das estrelas + 4,8 × 5) / (n + 5)
             round((CASE WHEN d.avg_rating IS NULL THEN 0
                         ELSE d.avg_rating * COALESCE(d.ratings_count, 0) END + 4.8 * 5)
                   / (CASE WHEN d.avg_rating IS NULL THEN 0 ELSE COALESCE(d.ratings_count, 0) END + 5), 3) AS nota_a,
             -- taxa de aceitação alisada nas ofertas dos últimos N dias: (aceites + 0,8 × 5) / (ofertas + 5)
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

-- ─── 5. Oferecer ao próximo da lista ───────────────────────────────────────────────────────────
-- Devolve: true  = oferta feita (ou a oferta da lista ainda está viva);
--          false = a lista ainda tem gente, mas todos os que faltam estão AGORA com oferta viva
--                  noutra corrida → fica à espera da próxima volta do varrimento (15 s);
--          NULL  = não se aplica (balcão) ou lista esgotada/vazia → caminho de sempre.
-- Chamada SÓ pela tvde_offer_to_next, depois de esta ter trancado a corrida (FOR UPDATE).
CREATE OR REPLACE FUNCTION public._tvde_fila_oferecer(p_ride_id uuid)
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
  v_ttl       INT := (public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int;
  v_espera    boolean := false;
  v_n         int;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND OR v_ride.status <> 'solicitada' OR v_ride.dispatch_hold_reason IS NOT NULL THEN
    RETURN NULL;
  END IF;
  -- Balcão: fica na fila justa de 18/09 (quem está há mais tempo sem corrida).
  IF COALESCE(v_ride.source, 'app') = 'balcao' THEN RETURN NULL; END IF;

  SELECT * INTO v_ronda FROM public.tvde_fila_rondas
   WHERE ride_id = p_ride_id ORDER BY ronda DESC LIMIT 1 FOR UPDATE;
  v_tem_ronda := FOUND;

  -- (a) Fechar a entrada que estava com a oferta, se a oferta já acabou.
  IF v_tem_ronda AND v_ronda.estado = 'ativa' THEN
    SELECT * INTO v_e FROM public.tvde_fila_entradas
     WHERE ronda_id = v_ronda.id AND estado = 'oferta' LIMIT 1;
    IF FOUND THEN
      IF v_ride.current_offer_driver_id = v_e.driver_id
         AND v_ride.offer_expires_at IS NOT NULL AND v_ride.offer_expires_at > now() THEN
        RETURN true;  -- a oferta da lista ainda está viva: não se toca (idempotente)
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
      UPDATE public.tvde_fila_entradas
         SET estado = v_fim, terminou_em = now()
       WHERE id = v_e.id;
      IF v_fim = 'aceitou' THEN
        -- Aceitou e a corrida voltou a procurar (desistiu depois): procura nova, lista nova.
        UPDATE public.tvde_fila_rondas
           SET estado = 'aceite', terminou_em = now(),
               motivo_fim = 'aceite; a corrida voltou a procurar'
         WHERE id = v_ronda.id;
        v_ronda.estado := 'aceite';
      END IF;
    END IF;
  END IF;

  -- (b) O admin pediu nova roda / a reserva foi re-despachada depois do cálculo → lista nova.
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

  -- (c) Calcular a lista — UMA vez por procura.
  IF NOT v_tem_ronda OR v_ronda.estado IN ('aceite', 'anulada') THEN
    INSERT INTO public.tvde_fila_rondas (ride_id, ronda, criterios)
    VALUES (p_ride_id,
            COALESCE((SELECT max(ronda) FROM public.tvde_fila_rondas WHERE ride_id = p_ride_id), 0) + 1,
            jsonb_build_object(
              'velocidade_kmh', COALESCE((public.get_setting('eta_avg_speed_kmh') #>> '{}')::numeric, 28),
              'peso_nota_min', COALESCE((public.get_setting('tvde_fila_peso_nota_min') #>> '{}')::numeric, 2),
              'peso_aceitacao_min', COALESCE((public.get_setting('tvde_fila_peso_aceitacao_min') #>> '{}')::numeric, 5),
              'historico_dias', COALESCE((public.get_setting('tvde_fila_historico_dias') #>> '{}')::int, 30),
              'max_motoristas', COALESCE((public.get_setting('tvde_fila_max_motoristas') #>> '{}')::int, 5),
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
    v_ronda.n_candidatos := v_n;
    IF v_n = 0 THEN
      UPDATE public.tvde_fila_rondas
         SET estado = 'esgotada', terminou_em = now(),
             motivo_fim = 'ninguém disponível e com aviso no telemóvel ao pedir'
       WHERE id = v_ronda.id;
      v_ronda.estado := 'esgotada';
    END IF;
  END IF;

  IF v_ronda.estado <> 'ativa' THEN
    RETURN NULL;  -- esgotada → caminho de sempre
  END IF;

  -- (d) O primeiro da lista, pela ordem, que pode receber AGORA. Sem recalcular a ordem.
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
    -- Está agora com outra oferta a tocar (corrida ou reserva)? Fica na lista, espera a vez.
    -- O cadeado por motorista impede duas corridas de lhe tocarem no mesmo instante.
    IF NOT pg_try_advisory_xact_lock(hashtextextended('tvde_fila_motorista:' || v_e.driver_id::text, 0))
       OR EXISTS (SELECT 1 FROM public.tvde_rides o
                   WHERE o.id <> p_ride_id
                     AND ((o.status = 'solicitada' AND o.current_offer_driver_id = v_e.driver_id
                           AND o.offer_expires_at > now())
                       OR (o.reservation_offer_driver_id = v_e.driver_id
                           AND o.reservation_offer_expires_at > now()))) THEN
      v_espera := true;
      CONTINUE;
    END IF;

    -- A oferta: as mesmas colunas e o mesmo evento que o caminho de sempre escreve.
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
    -- Quem falta está a receber outra oferta neste instante: sem oferta agora; o varrimento
    -- (de 15 em 15 s) volta a chamar porque no_driver_since fica posto.
    UPDATE public.tvde_rides
       SET no_driver_since = COALESCE(v_ride.no_driver_since, now()),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = p_ride_id;
    RETURN false;
  END IF;

  UPDATE public.tvde_fila_rondas
     SET estado = 'esgotada', terminou_em = now(), motivo_fim = 'lista percorrida até ao fim'
   WHERE id = v_ronda.id;
  RETURN NULL;  -- lista esgotada → caminho de sempre
END;
$function$;

REVOKE ALL ON FUNCTION public._tvde_fila_motivo_fora(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_candidatos(uuid)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_fila_oferecer(uuid)          FROM PUBLIC, anon, authenticated;

-- ─── 6. Painel (PT-BR): a fila ao vivo e o histórico ───────────────────────────────────────────
-- Estado "efetivo" de uma entrada: a que tem a oferta e já não a tem é mostrada como acabou
-- (aceitou / recusou / expirou) mesmo antes de a próxima volta a fechar na tabela.
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
    ELSE 'expirou' END;
$function$;
REVOKE ALL ON FUNCTION public._tvde_fila_estado_efetivo(public.tvde_fila_entradas, public.tvde_rides)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_tvde_fila_ao_vivo()
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
  SELECT jsonb_build_object(
    'agora', now(),
    'ligada', COALESCE((public.get_setting('tvde_fila_inteligente_enabled') #>> '{}')::boolean, false),
    'oferta_s', (public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int,
    'max_motoristas', COALESCE((public.get_setting('tvde_fila_max_motoristas') #>> '{}')::int, 5),
    'peso_nota_min', COALESCE((public.get_setting('tvde_fila_peso_nota_min') #>> '{}')::numeric, 2),
    'peso_aceitacao_min', COALESCE((public.get_setting('tvde_fila_peso_aceitacao_min') #>> '{}')::numeric, 5),
    'historico_dias', COALESCE((public.get_setting('tvde_fila_historico_dias') #>> '{}')::int, 30),
    'corridas', COALESCE((
      SELECT jsonb_agg(c ORDER BY c->>'criada_em' DESC)
        FROM (
          SELECT jsonb_build_object(
                   'ride_id', r.id,
                   'status', r.status,
                   'ride_kind', to_jsonb(r)->>'ride_kind',
                   'origem', r.origin_label,
                   'destino', r.dest_label,
                   'criada_em', r.created_at,
                   'reserva', r.reservation_status IS NOT NULL,
                   'balcao', COALESCE(r.source, 'app') = 'balcao',
                   'oferta_motorista_id', r.current_offer_driver_id,
                   'oferta_motorista', (SELECT d.name FROM public.drivers d
                                         WHERE d.user_id = r.current_offer_driver_id LIMIT 1),
                   'oferta_expira_em', r.offer_expires_at,
                   'segundos_restantes', CASE WHEN r.offer_expires_at IS NULL THEN NULL
                     ELSE GREATEST(0, ceil(extract(epoch FROM r.offer_expires_at - now())))::int END,
                   'motorista_id', r.driver_id,
                   'ronda', fr.ronda,
                   'ronda_estado', fr.estado,
                   'ronda_calculada_em', fr.calculada_em,
                   'ronda_motivo_fim', fr.motivo_fim,
                   'entradas', COALESCE((
                     SELECT jsonb_agg(jsonb_build_object(
                              'pos', e.pos,
                              'motorista_id', e.driver_id,
                              'motorista', (SELECT d.name FROM public.drivers d
                                             WHERE d.user_id = e.driver_id LIMIT 1),
                              'eta_min', e.eta_min, 'dist_km', e.dist_km,
                              'nota', e.nota, 'taxa_aceitacao', e.taxa_aceitacao,
                              'pontos', e.pontos,
                              'estado', public._tvde_fila_estado_efetivo(e, r),
                              'oferecida_em', e.oferecida_em, 'expira_em', e.expira_em,
                              'terminou_em', e.terminou_em, 'motivo', e.motivo)
                            ORDER BY e.pos)
                       FROM public.tvde_fila_entradas e WHERE e.ronda_id = fr.id), '[]'::jsonb)
                 ) AS c
            FROM public.tvde_rides r
            LEFT JOIN LATERAL (
              SELECT * FROM public.tvde_fila_rondas x
               WHERE x.ride_id = r.id ORDER BY x.ronda DESC LIMIT 1
            ) fr ON true
           WHERE r.status = 'solicitada'
              OR (fr.id IS NOT NULL AND fr.calculada_em > now() - interval '30 minutes')
           ORDER BY r.created_at DESC
           LIMIT 50
        ) s
    ), '[]'::jsonb)
  ) INTO v_out;
  RETURN v_out;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_tvde_fila_historico(p_horas int DEFAULT 48, p_limite int DEFAULT 200)
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
  SELECT COALESCE(jsonb_agg(h ORDER BY h->>'quando' DESC), '[]'::jsonb) INTO v_out
    FROM (
      SELECT jsonb_build_object(
               'ride_id', e.ride_id,
               'ronda', fr.ronda,
               'pos', e.pos,
               'motorista_id', e.driver_id,
               'motorista', (SELECT d.name FROM public.drivers d WHERE d.user_id = e.driver_id LIMIT 1),
               'estado', public._tvde_fila_estado_efetivo(e, r),
               'motivo', e.motivo,
               'eta_min', e.eta_min, 'nota', e.nota, 'taxa_aceitacao', e.taxa_aceitacao,
               'oferecida_em', e.oferecida_em,
               'quando', COALESCE(e.terminou_em, e.expira_em, e.oferecida_em, fr.calculada_em),
               'origem', r.origin_label
             ) AS h
        FROM public.tvde_fila_entradas e
        JOIN public.tvde_fila_rondas fr ON fr.id = e.ronda_id
        JOIN public.tvde_rides r ON r.id = e.ride_id
       WHERE fr.calculada_em > now() - make_interval(hours => GREATEST(1, LEAST(COALESCE(p_horas, 48), 24 * 31)))
         AND e.estado <> 'espera'
       ORDER BY COALESCE(e.terminou_em, e.expira_em, e.oferecida_em, fr.calculada_em) DESC
       LIMIT GREATEST(1, LEAST(COALESCE(p_limite, 200), 1000))
    ) s;
  RETURN v_out;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_tvde_fila_ao_vivo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_tvde_fila_historico(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_fila_ao_vivo() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_tvde_fila_historico(int, int) TO authenticated, service_role;
