-- Escada de prémios do check-in (adendo 9, pedido do Danilo de 29/10/2026 às 22:20).
--
-- Os tokens diários (5,5,10,10,15,15,40) ficam como estão: nada aqui lhes toca.
-- Os prémios de produto/serviço (dia 10 salgados, dia 15 açaí, dia 30 limpeza ou lavagem)
-- passam a ser UMA escada: um prémio por sequência, o mais alto a que o cliente chegar.
--   * Ao chegar a um degrau o prémio fica guardado (substitui o anterior, nunca soma).
--   * Levantar = emite o vale pelo _checkin_vale_emitir de sempre (validade, tecto mensal e
--     pedido pago continuam a valer) e a sequência dos marcos recomeça no dia 1.
--   * Continuar = só marca a decisão; o degrau seguinte troca o prémio por um maior.
--   * No último degrau (dia 30) levanta-se sozinho e o ciclo recomeça.
--   * Falhar um dia recomeça a sequência, mas o prémio guardado fica até garantido_ate
--     (checkin_marco_validade_dias); um degrau mais baixo não o substitui.
-- Interruptor: checkin_escada_ativa (nasce ligado). Desligado = um vale em cada marco, como antes.

-- 0. Cópias das duas funções que mudam, para voltar atrás sem procurar no histórico.
DO $$
BEGIN
  IF to_regprocedure('public.bkp_fn_checkin_marcos_apos_checkin_20261029()') IS NULL THEN
    EXECUTE replace(pg_get_functiondef('public._checkin_marcos_apos_checkin()'::regprocedure),
                    'public._checkin_marcos_apos_checkin()', 'public.bkp_fn_checkin_marcos_apos_checkin_20261029()');
  END IF;
  IF to_regprocedure('public.bkp_fn_checkin_estado_marcos_20261029(uuid)') IS NULL THEN
    EXECUTE replace(pg_get_functiondef('public._checkin_estado_marcos(uuid)'::regprocedure),
                    'public._checkin_estado_marcos(p_uid uuid)', 'public.bkp_fn_checkin_estado_marcos_20261029(p_uid uuid)');
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.bkp_fn_checkin_marcos_apos_checkin_20261029() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bkp_fn_checkin_estado_marcos_20261029(uuid) FROM PUBLIC, anon, authenticated;

-- 1. O degrau guardado de cada cliente (uma linha por cliente = nunca mais de um pendente).
CREATE TABLE IF NOT EXISTS public.checkin_escada (
  user_id               uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  guardado_chave        text,
  guardado_dia          smallint,
  guardado_titulo       text,
  guardado_tipo         text,
  guardado_marco        jsonb,
  guardado_ciclo_inicio date,
  guardado_em           timestamptz,
  garantido_ate         timestamptz,
  decisao               text NOT NULL DEFAULT 'pendente' CHECK (decisao IN ('pendente','continuar')),
  reinicio_data         date,
  levantados            integer NOT NULL DEFAULT 0,
  ultimo_vale_id        uuid,
  ultimo_levantado_em   timestamptz,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  atualizado_em         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.checkin_escada IS
  'Escada de prémios do check-in: o prémio guardado (um só) e a data em que a sequência dos marcos recomeçou (reinicio_data). Só por funções SECURITY DEFINER.';
ALTER TABLE public.checkin_escada ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.checkin_escada FROM PUBLIC, anon, authenticated;

-- 2. Definições (categoria marketing, como as checkin_marco_*).
INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('checkin_escada_ativa', 'true'::jsonb,
   'Check-in: escada de prêmios (um prêmio por sequência, "levanta ou continua"). Desligado = um vale em cada marco, como antes.',
   'marketing'),
  ('checkin_escada_texto',
   to_jsonb('Em cada sequência levas UM prémio: o mais alto a que chegares. Se levantares, a sequência volta ao dia 1. Se continuares, trocas por um prémio maior.'::text),
   'Check-in: texto da escada de prêmios (ecrã "Os prémios do mês" e cartão da festa). PT-PT.',
   'marketing')
ON CONFLICT (key) DO NOTHING;

-- 3. Ajudantes.
CREATE OR REPLACE FUNCTION public._checkin_escada_ativa()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((public._checkin_marco_cfg('checkin_escada_ativa', 'true'::jsonb) #>> '{}')::boolean, true)
$function$;

-- Os degraus: marcos de produto/serviço ligados e dentro do ciclo, por ordem de dia.
CREATE OR REPLACE FUNCTION public._checkin_escada_degraus()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(x ORDER BY (x ->> 'dia')::int), '[]'::jsonb)
    FROM jsonb_array_elements(COALESCE(public._checkin_marcos_config(), '[]'::jsonb)) x
   WHERE x ->> 'tipo' IN ('produto','servico')
     AND COALESCE((x ->> 'ativo')::boolean, true)
     AND (x ->> 'dia')::int <= LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_ciclo_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365)
$function$;

-- A sequência dos marcos: a de sempre, mas depois de levantar um prémio só contam os dias
-- a seguir a reinicio_data.
CREATE OR REPLACE FUNCTION public._checkin_seq_marcos(p_uid uuid, p_ate date)
 RETURNS TABLE(dias integer, inicio date, ultima date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_seq  record;
  v_rein date;
BEGIN
  SELECT * INTO v_seq FROM public._checkin_sequencia(p_uid, p_ate);
  SELECT e.reinicio_data INTO v_rein FROM public.checkin_escada e WHERE e.user_id = p_uid;
  dias   := COALESCE(v_seq.dias, 0);
  inicio := v_seq.inicio;
  ultima := v_seq.ultima;
  IF v_rein IS NOT NULL AND ultima IS NOT NULL AND inicio <= v_rein THEN
    IF ultima <= v_rein THEN
      dias   := 0;
      inicio := NULL;
    ELSE
      dias   := ultima - v_rein;
      inicio := v_rein + 1;
    END IF;
  END IF;
  RETURN NEXT;
END;
$function$;

-- Levantar (comum ao botão do cliente e ao último degrau): emite o vale, limpa o guardado e
-- recomeça a sequência a seguir a p_reinicio. Se o vale deste degrau já existia nesta
-- sequência (regra antiga), não emite outro nem recomeça.
CREATE OR REPLACE FUNCTION public._checkin_escada_levantar(p_uid uuid, p_marco jsonb, p_inicio date, p_reinicio date, p_motivo text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vale uuid;
BEGIN
  v_vale := public._checkin_vale_emitir(p_uid, p_marco, p_inicio, 'checkin', NULL, p_motivo);
  UPDATE public.checkin_escada
     SET guardado_chave = NULL, guardado_dia = NULL, guardado_titulo = NULL, guardado_tipo = NULL,
         guardado_marco = NULL, guardado_ciclo_inicio = NULL, guardado_em = NULL, garantido_ate = NULL,
         decisao = 'pendente',
         reinicio_data = CASE WHEN v_vale IS NULL THEN reinicio_data
                              ELSE GREATEST(COALESCE(reinicio_data, p_reinicio), p_reinicio) END,
         levantados = levantados + CASE WHEN v_vale IS NULL THEN 0 ELSE 1 END,
         ultimo_vale_id = COALESCE(v_vale, ultimo_vale_id),
         ultimo_levantado_em = CASE WHEN v_vale IS NULL THEN ultimo_levantado_em ELSE now() END,
         atualizado_em = now()
   WHERE user_id = p_uid;
  RETURN v_vale;
END;
$function$;

-- Chegou a um degrau: guarda (substitui, nunca soma). Um degrau mais baixo não tira o mais
-- alto que ainda está garantido. No último degrau levanta sozinho.
CREATE OR REPLACE FUNCTION public._checkin_escada_chegou(p_uid uuid, p_marco jsonb, p_inicio date, p_data date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row      public.checkin_escada%ROWTYPE;
  v_dia      integer := (p_marco ->> 'dia')::int;
  v_validade integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_validade_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_ultimo   integer;
BEGIN
  SELECT max((x ->> 'dia')::int) INTO v_ultimo FROM jsonb_array_elements(public._checkin_escada_degraus()) x;
  INSERT INTO public.checkin_escada (user_id) VALUES (p_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_row FROM public.checkin_escada WHERE user_id = p_uid FOR UPDATE;

  IF v_row.guardado_chave IS NOT NULL
     AND (v_row.garantido_ate IS NULL OR v_row.garantido_ate > now())
     AND v_row.guardado_dia > v_dia THEN
    RETURN NULL;
  END IF;

  IF v_dia >= COALESCE(v_ultimo, v_dia) THEN
    RETURN public._checkin_escada_levantar(p_uid, p_marco, p_inicio, p_data, 'escada:ultimo');
  END IF;

  UPDATE public.checkin_escada
     SET guardado_chave = p_marco ->> 'chave', guardado_dia = v_dia,
         guardado_titulo = COALESCE(p_marco ->> 'titulo', 'Prémio do check-in'),
         guardado_tipo = p_marco ->> 'tipo', guardado_marco = p_marco,
         guardado_ciclo_inicio = p_inicio, guardado_em = now(),
         garantido_ate = now() + make_interval(days => v_validade),
         decisao = 'pendente', atualizado_em = now()
   WHERE user_id = p_uid;
  RETURN NULL;
END;
$function$;

-- 4. O gatilho depois do check-in: com a escada ligada guarda o degrau em vez de emitir o vale.
CREATE OR REPLACE FUNCTION public._checkin_marcos_apos_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ativo  boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_ativo', 'false'::jsonb) #>> '{}')::boolean, false);
  v_ciclo  integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_ciclo_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_exige_tel boolean := COALESCE((SELECT (s.value #>> '{}')::boolean FROM public.platform_settings s WHERE s.key = 'checkin_require_phone'), true);
  v_escada boolean := public._checkin_escada_ativa();
  v_seq    record;
  v_dia    integer;
  v_inicio date;
  m        jsonb;
BEGIN
  IF NOT v_ativo THEN RETURN NULL; END IF;
  -- o mesmo criterio do check-in: telemovel portugues valido na ficha
  IF v_exige_tel AND NOT public._checkin_telemovel_confirmado(NEW.user_id) THEN RETURN NULL; END IF;

  BEGIN
    SELECT * INTO v_seq FROM public._checkin_seq_marcos(NEW.user_id, NEW.checkin_date);
    IF COALESCE(v_seq.dias, 0) < 1 OR v_seq.ultima IS DISTINCT FROM NEW.checkin_date THEN
      RETURN NULL;
    END IF;
    v_dia    := ((v_seq.dias - 1) % v_ciclo) + 1;
    v_inicio := NEW.checkin_date - (v_dia - 1);
    FOR m IN SELECT x FROM jsonb_array_elements(public._checkin_marcos_config()) x LOOP
      IF (m ->> 'tipo') IN ('produto','servico')
         AND COALESCE((m ->> 'ativo')::boolean, true)
         AND (m ->> 'dia')::int = v_dia THEN
        IF v_escada THEN
          PERFORM public._checkin_escada_chegou(NEW.user_id, m, v_inicio, NEW.checkin_date);
        ELSE
          PERFORM public._checkin_vale_emitir(NEW.user_id, m, v_inicio);
        END IF;
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    -- Um premio falhado nao pode deitar abaixo o check-in do dia: regista-se e segue.
    RAISE WARNING '_checkin_marcos_apos_checkin: % (user %)', SQLERRM, NEW.user_id;
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
    VALUES ('checkin_marcos', 'emitir_vale', 'falhou', NEW.user_id::text || ' ' || NEW.checkin_date || ': ' || SQLERRM, 'servidor');
  END;
  RETURN NULL;
END;
$function$;

-- 5. O estado dos marcos para a app: a sequência já conta o recomeço e traz a escada.
CREATE OR REPLACE FUNCTION public._checkin_estado_marcos(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje     date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_ciclo    integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_ciclo_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_ativo    boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_ativo', 'false'::jsonb) #>> '{}')::boolean, false);
  v_cfg      jsonb := public._checkin_marcos_config();
  v_premios  integer[] := public._checkin_premios();
  v_escada   boolean := public._checkin_escada_ativa();
  v_degraus  jsonb := public._checkin_escada_degraus();
  v_seq      record;
  v_er       public.checkin_escada%ROWTYPE;
  v_dias     integer := 0;
  v_dia      integer := 0;
  v_inicio   date := NULL;
  v_feito    boolean := false;
  v_marcos   jsonb := '[]'::jsonb;
  v_prox     jsonb := NULL;
  v_primeiro jsonb := NULL;
  m          jsonb;
  v_falta    integer;
  v_gval     boolean := false;
  v_base     integer;
  v_maior    jsonb := NULL;
  v_ultimo   integer;
BEGIN
  IF p_uid IS NOT NULL THEN
    SELECT * INTO v_seq FROM public._checkin_seq_marcos(p_uid, v_hoje);
    IF v_seq.ultima IS NOT NULL AND v_seq.ultima >= v_hoje - 1 THEN
      v_dias  := COALESCE(v_seq.dias, 0);
      v_feito := v_seq.ultima = v_hoje;
    END IF;
    SELECT * INTO v_er FROM public.checkin_escada e WHERE e.user_id = p_uid;
  END IF;
  IF v_dias > 0 THEN
    v_dia    := ((v_dias - 1) % v_ciclo) + 1;
    v_inicio := v_seq.ultima - (v_dia - 1);
  END IF;

  FOR m IN SELECT x FROM jsonb_array_elements(COALESCE(v_cfg, '[]'::jsonb)) x LOOP
    CONTINUE WHEN NOT COALESCE((m ->> 'ativo')::boolean, true);
    CONTINUE WHEN (m ->> 'dia')::int > v_ciclo;
    v_falta := GREATEST((m ->> 'dia')::int - v_dia, 0);
    v_marcos := v_marcos || jsonb_build_array(jsonb_build_object(
      'chave', m ->> 'chave', 'dia', (m ->> 'dia')::int, 'tipo', m ->> 'tipo',
      'titulo', m ->> 'titulo', 'descricao', m ->> 'descricao',
      'tokens', CASE WHEN m ->> 'tipo' = 'tokens' THEN v_premios[7] END,
      'atingido', v_dia >= (m ->> 'dia')::int,
      'faltam', v_falta));
    IF v_primeiro IS NULL THEN
      v_primeiro := m;
    END IF;
    IF v_prox IS NULL AND (m ->> 'dia')::int > v_dia THEN
      v_prox := jsonb_build_object('chave', m ->> 'chave', 'dia', (m ->> 'dia')::int,
                                   'titulo', m ->> 'titulo', 'faltam', v_falta);
    END IF;
  END LOOP;
  IF v_prox IS NULL AND v_primeiro IS NOT NULL THEN
    -- passou o ultimo marco do ciclo: o proximo e o primeiro do ciclo seguinte
    v_prox := jsonb_build_object('chave', v_primeiro ->> 'chave', 'dia', (v_primeiro ->> 'dia')::int,
                                 'titulo', v_primeiro ->> 'titulo',
                                 'faltam', (v_ciclo - v_dia) + (v_primeiro ->> 'dia')::int);
  END IF;

  -- a escada: o prémio guardado (se ainda garantido) e o degrau maior a seguir
  v_gval := v_er.guardado_chave IS NOT NULL AND (v_er.garantido_ate IS NULL OR v_er.garantido_ate > now());
  v_base := CASE WHEN v_gval THEN v_er.guardado_dia ELSE v_dia END;
  SELECT x INTO v_maior FROM jsonb_array_elements(v_degraus) x
   WHERE (x ->> 'dia')::int > v_base ORDER BY (x ->> 'dia')::int LIMIT 1;
  SELECT max((x ->> 'dia')::int) INTO v_ultimo FROM jsonb_array_elements(v_degraus) x;

  RETURN jsonb_build_object(
    'marcos_ativos', v_ativo,
    'ciclo_dias', v_ciclo,
    'dias_seguidos', v_dias,
    'dia_marco', v_dia,
    'ciclo_inicio', v_inicio,
    'hoje_feito', v_feito,
    'marcos', v_marcos,
    'proximo', v_prox,
    'escada', jsonb_build_object(
      'ativa', v_escada,
      'texto', COALESCE(public._checkin_marco_cfg('checkin_escada_texto', 'null'::jsonb) #>> '{}',
        'Em cada sequência levas UM prémio: o mais alto a que chegares. Se levantares, a sequência volta ao dia 1. Se continuares, trocas por um prémio maior.'),
      'guardado', CASE WHEN v_gval THEN jsonb_build_object(
          'chave', v_er.guardado_chave, 'dia', v_er.guardado_dia, 'titulo', v_er.guardado_titulo,
          'tipo', v_er.guardado_tipo, 'descricao', v_er.guardado_marco ->> 'descricao',
          'guardado_em', v_er.guardado_em, 'garantido_ate', v_er.garantido_ate) END,
      'decisao', CASE WHEN v_gval THEN v_er.decisao END,
      'pendente_decisao', COALESCE(v_gval AND v_er.decisao = 'pendente' AND v_maior IS NOT NULL, false),
      'pode_continuar', COALESCE(v_gval AND v_maior IS NOT NULL, false),
      'proximo_maior', CASE WHEN v_maior IS NOT NULL THEN jsonb_build_object(
          'chave', v_maior ->> 'chave', 'dia', (v_maior ->> 'dia')::int, 'titulo', v_maior ->> 'titulo',
          'descricao', v_maior ->> 'descricao', 'faltam', GREATEST((v_maior ->> 'dia')::int - v_dia, 0)) END,
      'ultimo_dia', v_ultimo,
      'levantados', COALESCE(v_er.levantados, 0),
      'reinicio_data', v_er.reinicio_data,
      'ultimo_vale_id', v_er.ultimo_vale_id)
  );
END;
$function$;

-- 6. Os dois botões do cliente.
CREATE OR REPLACE FUNCTION public.client_checkin_escada_levantar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_row  public.checkin_escada%ROWTYPE;
  v_ult  date;
  v_vale uuid;
  v_json jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('checkin_escada:' || v_uid::text));
  SELECT * INTO v_row FROM public.checkin_escada WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR v_row.guardado_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_premio');
  END IF;
  IF v_row.garantido_ate IS NOT NULL AND v_row.garantido_ate <= now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expirado');
  END IF;
  -- recomeça a seguir ao último check-in feito: se já o fez hoje, amanhã é o Dia 1;
  -- se ainda não, o check-in de hoje já conta como Dia 1
  SELECT max(c.checkin_date) INTO v_ult FROM public.daily_checkins c
   WHERE c.user_id = v_uid AND c.checkin_date <= v_hoje;
  v_vale := public._checkin_escada_levantar(v_uid, v_row.guardado_marco, v_row.guardado_ciclo_inicio,
                                            COALESCE(v_ult, v_hoje), 'escada:levantar');
  IF v_vale IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ja_levantado', 'estado', public._checkin_estado_marcos(v_uid));
  END IF;
  SELECT public._checkin_vale_json(x) INTO v_json FROM public.checkin_premios_vales x WHERE x.id = v_vale;
  RETURN jsonb_build_object('ok', true, 'vale', v_json, 'estado', public._checkin_estado_marcos(v_uid));
END;
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_escada_continuar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_row   public.checkin_escada%ROWTYPE;
  v_maior integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;
  SELECT * INTO v_row FROM public.checkin_escada WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR v_row.guardado_chave IS NULL
     OR (v_row.garantido_ate IS NOT NULL AND v_row.garantido_ate <= now()) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_premio');
  END IF;
  SELECT min((x ->> 'dia')::int) INTO v_maior FROM jsonb_array_elements(public._checkin_escada_degraus()) x
   WHERE (x ->> 'dia')::int > v_row.guardado_dia;
  IF v_maior IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ultimo_degrau');
  END IF;
  UPDATE public.checkin_escada SET decisao = 'continuar', atualizado_em = now() WHERE user_id = v_uid;
  RETURN jsonb_build_object('ok', true, 'estado', public._checkin_estado_marcos(v_uid));
END;
$function$;

-- 7. Painel admin (PT-BR no ecrã): resumo com o custo do mês e a lista por cliente.
CREATE OR REPLACE FUNCTION public.admin_checkin_escada_resumo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mes_ini timestamptz := (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
  v_r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  WITH g AS (
    SELECT * FROM public.checkin_escada e
     WHERE e.guardado_chave IS NOT NULL AND (e.garantido_ate IS NULL OR e.garantido_ate > now())
  ), l AS (
    SELECT * FROM public.checkin_premios_vales v WHERE v.motivo LIKE 'escada:%'
  )
  SELECT jsonb_build_object(
    'ativa', public._checkin_escada_ativa(),
    'texto', public._checkin_marco_cfg('checkin_escada_texto', 'null'::jsonb) #>> '{}',
    'degraus', public._checkin_escada_degraus(),
    'guardados', (SELECT count(*) FROM g),
    'pendentes_decisao', (SELECT count(*) FROM g WHERE g.decisao = 'pendente'),
    'guardados_por_degrau', (SELECT COALESCE(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
                               FROM (SELECT g.guardado_chave k, count(*) n FROM g GROUP BY 1) z),
    'levantados_total', (SELECT count(*) FROM l),
    'levantados_mes', (SELECT count(*) FROM l WHERE l.emitido_em >= v_mes_ini),
    'custo_levantados_mes_cents', (SELECT COALESCE(sum(l.custo_cents), 0) FROM l
                                    WHERE l.emitido_em >= v_mes_ini AND l.estado <> 'anulado'),
    'valor_levantados_mes_cents', (SELECT COALESCE(sum(l.valor_cents), 0) FROM l
                                    WHERE l.emitido_em >= v_mes_ini AND l.estado <> 'anulado'),
    'levantados_mes_por_degrau', (SELECT COALESCE(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
                                    FROM (SELECT l.marco_chave k, count(*) n FROM l
                                           WHERE l.emitido_em >= v_mes_ini GROUP BY 1) z),
    'clientes_com_mais_de_um_vale', (SELECT count(*) FROM (
        SELECT v.user_id FROM public.checkin_premios_vales v
         WHERE v.estado IN ('por_usar','guardado','a_espera_pedido','reservado')
         GROUP BY v.user_id HAVING count(*) > 1) z)
  ) INTO v_r;
  RETURN v_r;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_escada_clientes(p_limite integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_r    jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  WITH u AS (
    SELECT DISTINCT c.user_id FROM public.daily_checkins c WHERE c.checkin_date >= v_hoje - 1
    UNION
    SELECT e.user_id FROM public.checkin_escada e
  ), linhas AS (
    SELECT u.user_id, us.name, us.email, e.ultimo_levantado_em, e.reinicio_data,
           public._checkin_estado_marcos(u.user_id) st
      FROM u
      LEFT JOIN public.users us ON us.id = u.user_id
      LEFT JOIN public.checkin_escada e ON e.user_id = u.user_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', x.user_id, 'nome', x.name, 'email', x.email,
           'dias_seguidos', (x.st ->> 'dias_seguidos')::int, 'dia_marco', (x.st ->> 'dia_marco')::int,
           'hoje_feito', x.st -> 'hoje_feito',
           'guardado', x.st -> 'escada' -> 'guardado', 'decisao', x.st -> 'escada' -> 'decisao',
           'levantados', (x.st -> 'escada' ->> 'levantados')::int,
           'ultimo_levantado_em', x.ultimo_levantado_em, 'reinicio_data', x.reinicio_data,
           'vales_ativos', (SELECT count(*) FROM public.checkin_premios_vales v
                             WHERE v.user_id = x.user_id
                               AND v.estado IN ('por_usar','guardado','a_espera_pedido','reservado')))
           ORDER BY (x.st ->> 'dia_marco')::int DESC, x.name), '[]'::jsonb)
    INTO v_r
    FROM (SELECT * FROM linhas ORDER BY (linhas.st ->> 'dia_marco')::int DESC
           LIMIT LEAST(GREATEST(COALESCE(p_limite, 100), 1), 500)) x;
  RETURN v_r;
END;
$function$;

-- 8. Permissões: ajudantes fechados; botões e painel só com sessão (o painel verifica o admin).
REVOKE ALL ON FUNCTION public._checkin_escada_ativa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_escada_degraus() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_seq_marcos(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_escada_levantar(uuid, jsonb, date, date, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_escada_chegou(uuid, jsonb, date, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_checkin_escada_levantar() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_escada_continuar() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_escada_resumo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_escada_clientes(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_checkin_escada_levantar() TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_escada_continuar() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_escada_resumo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_escada_clientes(integer) TO authenticated;
