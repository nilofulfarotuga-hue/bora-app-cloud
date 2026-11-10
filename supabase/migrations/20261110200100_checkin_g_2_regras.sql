-- Missão fechar-tudo-2026-11-10, Bloco G — parte 2 de 6: as regras no servidor.
-- R2 todo o prémio espera 1 pedido pago (corrida TVDE só conta com interruptor).
-- R3 "Quero este" recomeça a escada; a semana de tokens só recomeça com interruptor (desligado).
-- R4 o prémio guardado é o mais valioso a que a pessoa chegou; entre iguais, a loja onde mais pediu.
-- R5 perdão: 1 dia falhado por mês, só com pedido pago, aplicado sozinho no check-in seguinte.
-- R6 teto de custo mensal dos prémios.

-- R2 ───────────────────────────────────────────────────────────────────────────
-- Pedido pago nos últimos p_dias. A corrida TVDE deixa de contar (Bora Motorista
-- fechado); volta a contar se o Danilo ligar checkin_pedido_conta_tvde.
CREATE OR REPLACE FUNCTION public._checkin_teve_pedido_pago(p_uid uuid, p_dias integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH j AS (SELECT now() - make_interval(days => GREATEST(COALESCE(p_dias, 30), 1)) AS desde,
                    public.is_demo_user(p_uid) AS demo)
  SELECT EXISTS (
           SELECT 1 FROM public.orders o, j
            WHERE o.user_id = p_uid AND o.status = 'delivered' AND o.payment_status = 'paid'
              AND COALESCE(o.price, 0) > 0
              AND (NOT COALESCE(o.is_test_order, false) OR j.demo)
              AND EXISTS (SELECT 1 FROM public.order_status_events e
                           WHERE e.order_id = o.id
                             AND e.to_status = 'delivered'
                             AND e.actor_uid IS DISTINCT FROM p_uid
                             AND e.occurred_at >= j.desde))
      OR (public._checkin_cfg_bool('checkin_pedido_conta_tvde', false) AND EXISTS (
           SELECT 1 FROM public.tvde_rides r, j
            WHERE r.client_id = p_uid AND r.status = 'finalizada' AND r.created_at >= j.desde))
      OR EXISTS (
           SELECT 1 FROM public.cleaning_bookings b, j
            WHERE b.client_user_id = p_uid AND b.status = 'completed' AND b.cleaner_id IS NOT NULL
              AND ((b.payment_method IN ('card', 'mbway') AND b.payment_status = 'released')
                OR (b.payment_method = 'cash' AND b.payment_status IN ('cash_pending', 'cash_settled')))
              AND COALESCE(b.completed_at, b.scheduled_at) >= j.desde
              AND (NOT COALESCE(b.is_test_order, false) OR j.demo))
$function$;

-- A pessoa ainda precisa de 1 pedido pago para desbloquear prémios?
CREATE OR REPLACE FUNCTION public._checkin_precisa_pedido(p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public._checkin_cfg_bool('checkin_marco_exige_pedido_pago', true)
     AND NOT public._checkin_teve_pedido_pago(p_uid, public._checkin_cfg_int('checkin_marco_pedido_pago_dias', 30))
$function$;

-- Emitir um vale: TODO o prémio do check-in (produto, desconto ou serviço) sem
-- pedido pago fica à espera ("Falta 1 pedido para desbloquear") e desbloqueia
-- sozinho quando a pessoa comprar (checkin_premios_manutencao, de hora a hora).
-- Antes de 10/11/2026 só o serviço do dia 30 esperava.
CREATE OR REPLACE FUNCTION public._checkin_vale_emitir(p_uid uuid, p_marco jsonb, p_ciclo_inicio date, p_origem text DEFAULT 'checkin'::text, p_admin uuid DEFAULT NULL::uuid, p_motivo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id        uuid;
  v_tipo      text := p_marco ->> 'tipo';
  v_exige     boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_exige_pedido_pago', 'true'::jsonb) #>> '{}')::boolean, true);
  v_dias_ped  integer := COALESCE((public._checkin_marco_cfg('checkin_marco_pedido_pago_dias', '30'::jsonb) #>> '{}')::int, 30);
  v_espera    integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_espera_pedido_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_opcoes    text[] := '{}'::text[];
BEGIN
  IF v_tipo NOT IN ('produto','servico','desconto') THEN RETURN NULL; END IF;
  IF jsonb_typeof(p_marco -> 'opcoes') = 'array' THEN
    SELECT COALESCE(array_agg(o), '{}'::text[]) INTO v_opcoes FROM jsonb_array_elements_text(p_marco -> 'opcoes') o;
  END IF;

  INSERT INTO public.checkin_premios_vales (
    user_id, marco, marco_chave, tipo, ciclo_inicio, estado, titulo, loja_id, produto_id,
    quantidade, opcoes, valor_cents, custo_cents, origem, criado_por, motivo, minimo_cents)
  VALUES (
    p_uid, (p_marco ->> 'dia')::int, p_marco ->> 'chave', v_tipo, p_ciclo_inicio, 'por_usar',
    COALESCE(p_marco ->> 'titulo', 'Prémio do check-in'), p_marco ->> 'loja_id', p_marco ->> 'produto_id',
    GREATEST(COALESCE((p_marco ->> 'quantidade')::int, 1), 1), v_opcoes,
    GREATEST(COALESCE((p_marco ->> 'valor_cents')::int, 0), 0), GREATEST(COALESCE((p_marco ->> 'custo_cents')::int, 0), 0),
    p_origem, p_admin, p_motivo,
    CASE WHEN v_tipo = 'desconto' THEN GREATEST(COALESCE((p_marco ->> 'minimo_cents')::int, 0), 0) END)
  ON CONFLICT (user_id, marco_chave, ciclo_inicio) WHERE origem = 'checkin' DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN RETURN NULL; END IF;

  IF p_origem = 'checkin' AND v_exige
     AND NOT public._checkin_teve_pedido_pago(p_uid, v_dias_ped) THEN
    UPDATE public.checkin_premios_vales
       SET estado = 'a_espera_pedido', esperar_ate = now() + make_interval(days => v_espera), atualizado_em = now()
     WHERE id = v_id;
    PERFORM public._checkin_vale_avisar(v_id, 'espera');
    RETURN v_id;
  END IF;

  PERFORM public._checkin_vale_ativar(v_id, true);
  RETURN v_id;
END;
$function$;

-- R6 ───────────────────────────────────────────────────────────────────────────
-- Custo comprometido dos prémios do check-in no mês (Lisboa): vales ativados este
-- mês que ainda valem ou já foram usados. Guardados, à espera, expirados e anulados
-- não contam (não custam nada à Bora).
CREATE OR REPLACE FUNCTION public._checkin_custo_mes_cents(p_excluir uuid DEFAULT NULL)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(sum(x.custo_cents), 0)::integer
    FROM public.checkin_premios_vales x
   WHERE x.origem = 'checkin'
     AND x.estado IN ('por_usar','reservado','usado')
     AND x.ativado_em >= (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon'
     AND x.id IS DISTINCT FROM p_excluir
$function$;

-- Ativar um vale: ao teto de quantidade dos serviços (já existia) junta-se o teto
-- de CUSTO de todos os prémios (R6). Passando o teto, fica 'guardado' até ao mês seguinte.
CREATE OR REPLACE FUNCTION public._checkin_vale_ativar(p_vale_id uuid, p_avisar boolean DEFAULT true)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v           public.checkin_premios_vales;
  v_tecto_on  boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_tecto_ativo', 'true'::jsonb) #>> '{}')::boolean, true);
  v_tecto     integer := GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_tecto_mensal', '10'::jsonb) #>> '{}')::int, 10), 0);
  v_validade  integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_validade_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_mes_ini   timestamptz := (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
  v_custo_on  boolean := public._checkin_cfg_bool('checkin_premios_tecto_custo_ativo', true);
  v_custo_max integer := public._checkin_cfg_int('checkin_premios_tecto_custo_cents', 0);
  v_usados    integer;
  v_cheio     boolean := false;
BEGIN
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id FOR UPDATE;
  IF v.id IS NULL THEN RETURN NULL; END IF;

  IF v.tipo = 'servico' AND v_tecto_on AND v.origem = 'checkin' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('checkin_marco_tecto:' || v.marco_chave, 0));
    SELECT count(*) INTO v_usados
      FROM public.checkin_premios_vales x
     WHERE x.marco_chave = v.marco_chave AND x.origem = 'checkin' AND x.id <> v.id
       AND x.ativado_em >= v_mes_ini
       AND x.estado NOT IN ('guardado','a_espera_pedido','anulado');
    v_cheio := v_usados >= v_tecto;
  END IF;

  IF NOT v_cheio AND v.origem = 'checkin' AND v_custo_on AND v_custo_max > 0 AND COALESCE(v.custo_cents, 0) > 0 THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('checkin_tecto_custo', 0));
    v_cheio := public._checkin_custo_mes_cents(v.id) + v.custo_cents > v_custo_max;
  END IF;

  IF v_cheio THEN
    UPDATE public.checkin_premios_vales
       SET estado = 'guardado', valido_ate = NULL, esperar_ate = NULL,
           ativar_em = ((date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon') + interval '1 month'))::date,
           atualizado_em = now()
     WHERE id = v.id;
    IF p_avisar AND v.estado IS DISTINCT FROM 'guardado' THEN
      PERFORM public._checkin_vale_avisar(v.id, 'guardado');
    END IF;
    RETURN 'guardado';
  END IF;

  UPDATE public.checkin_premios_vales
     SET estado = 'por_usar', ativado_em = now(), ativar_em = NULL, esperar_ate = NULL,
         valido_ate = now() + make_interval(days => v_validade), atualizado_em = now()
   WHERE id = v.id;
  IF p_avisar THEN
    PERFORM public._checkin_vale_avisar(v.id, CASE WHEN v.estado IN ('guardado','a_espera_pedido') THEN 'ativado' ELSE 'novo' END);
  END IF;
  RETURN 'por_usar';
END;
$function$;

-- R4 ───────────────────────────────────────────────────────────────────────────
-- Valor de um degrau para comparar: sem valor no painel conta como o maior (é o
-- prémio grande do fim, a limpeza/lavagem do dia 30).
CREATE OR REPLACE FUNCTION public._checkin_marco_valor(p_marco jsonb)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN COALESCE(p_marco ->> 'valor_cents', '') ~ '^[0-9]{1,9}$' AND (p_marco ->> 'valor_cents')::int > 0
              THEN (p_marco ->> 'valor_cents')::int
              ELSE 2147483647 END
$function$;

-- A melhor sugestão: entre os degraus ligados a que a pessoa já chegou (dia <= p_ate_dia),
-- o mais valioso; entre iguais, o da loja onde ela mais pediu; depois o mais alto.
CREATE OR REPLACE FUNCTION public._checkin_sugestao(p_uid uuid, p_ate_dia integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.x
    FROM jsonb_array_elements(public._checkin_escada_degraus()) d(x)
    LEFT JOIN LATERAL (
      SELECT count(*) AS n FROM public.orders o
       WHERE o.user_id = p_uid AND o.restaurant_id = d.x ->> 'loja_id' AND o.status = 'delivered'
    ) c ON true
   WHERE (d.x ->> 'dia')::int <= COALESCE(p_ate_dia, 0)
   ORDER BY public._checkin_marco_valor(d.x) DESC, c.n DESC, (d.x ->> 'dia')::int DESC
   LIMIT 1
$function$;

-- Chegar a um degrau: guarda a melhor sugestão (R4) em vez do degrau do dia, se
-- o interruptor estiver ligado. O resto é igual a 04/11 (último degrau levanta sozinho).
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
  v_marco    jsonb := p_marco;
BEGIN
  SELECT max((x ->> 'dia')::int) INTO v_ultimo FROM jsonb_array_elements(public._checkin_escada_degraus()) x;
  INSERT INTO public.checkin_escada (user_id) VALUES (p_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_row FROM public.checkin_escada WHERE user_id = p_uid FOR UPDATE;

  IF v_row.guardado_chave IS NOT NULL
     AND (v_row.garantido_ate IS NULL OR v_row.garantido_ate > now())
     AND v_row.guardado_dia > v_dia THEN
    RETURN NULL;
  END IF;

  IF public._checkin_cfg_bool('checkin_sugestao_ativa', true) THEN
    v_marco := COALESCE(public._checkin_sugestao(p_uid, v_dia), p_marco);
  END IF;

  IF v_dia >= COALESCE(v_ultimo, v_dia) AND NOT public._checkin_premio_bloqueado(p_uid) THEN
    RETURN public._checkin_escada_levantar(p_uid, v_marco, p_inicio, p_data, 'escada:ultimo');
  END IF;

  UPDATE public.checkin_escada
     SET guardado_chave = v_marco ->> 'chave', guardado_dia = v_dia,
         guardado_titulo = COALESCE(v_marco ->> 'titulo', 'Prémio do check-in'),
         guardado_tipo = v_marco ->> 'tipo', guardado_marco = v_marco,
         guardado_ciclo_inicio = p_inicio, guardado_em = now(),
         garantido_ate = now() + make_interval(days => v_validade),
         decisao = 'pendente', atualizado_em = now()
   WHERE user_id = p_uid;
  RETURN NULL;
END;
$function$;

-- R3 ───────────────────────────────────────────────────────────────────────────
-- Estado do check-in de hoje (a semana de tokens). Igual a 13/10, mais o interruptor
-- checkin_quero_este_recomeca_semana (desligado): ligado, quem carregou "Quero este"
-- depois do último check-in volta ao Dia 1 da semana.
CREATE OR REPLACE FUNCTION public._checkin_estado(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje      date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_ligado    boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_enabled'), false);
  v_pronto    boolean := to_regprocedure('public.client_daily_checkin()') IS NOT NULL;
  v_exige_tel boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_require_phone'), true);
  v_premios   integer[] := public._checkin_premios();
  v_rec_sem   boolean := public._checkin_cfg_bool('checkin_quero_este_recomeca_semana', false);
  v_ult_data  date;
  v_ult_dia   integer;
  v_ult_tok   integer;
  v_lev       date;
  v_feito     boolean := false;
  v_dia       integer;
  v_prox      integer;
  v_motivo    text := NULL;
BEGIN
  IF p_uid IS NULL THEN
    v_motivo := 'sem_sessao';
  ELSIF NOT (v_ligado AND v_pronto) THEN
    v_motivo := 'desligado';
  ELSIF NOT public._checkin_e_cliente(p_uid) THEN
    v_motivo := 'nao_cliente';
  ELSIF v_exige_tel AND NOT public._checkin_telemovel_confirmado(p_uid) THEN
    v_motivo := 'sem_telemovel';
  END IF;

  IF p_uid IS NOT NULL THEN
    SELECT d.checkin_date, d.streak_day, d.tokens_awarded
      INTO v_ult_data, v_ult_dia, v_ult_tok
      FROM public.daily_checkins d
     WHERE d.user_id = p_uid
     ORDER BY d.checkin_date DESC
     LIMIT 1;
    IF v_rec_sem THEN
      SELECT (e.ultimo_levantado_em AT TIME ZONE 'Europe/Lisbon')::date INTO v_lev
        FROM public.checkin_escada e WHERE e.user_id = p_uid;
    END IF;
  END IF;

  IF v_ult_data = v_hoje THEN
    v_feito := true;
    v_dia   := v_ult_dia;
    v_prox  := CASE WHEN v_ult_dia >= 7 OR (v_lev IS NOT NULL AND v_lev >= v_ult_data) THEN 1 ELSE v_ult_dia + 1 END;
  ELSE
    v_dia := public._checkin_dia_de_hoje(v_ult_data, v_ult_dia, v_hoje);
    IF v_lev IS NOT NULL AND v_ult_data IS NOT NULL AND v_lev >= v_ult_data THEN
      v_dia := 1;
    END IF;
    v_prox := v_dia;
  END IF;

  RETURN jsonb_build_object(
    'enabled',        v_ligado AND v_pronto,
    'eligible',       v_motivo IS NULL,
    'reason',         v_motivo,
    'today',          v_hoje,
    'already_done',   v_feito,
    'streak_day',     v_dia,
    'tokens_today',   CASE WHEN v_feito THEN COALESCE(v_ult_tok, 0) ELSE v_premios[v_dia] END,
    'next_day',       v_prox,
    'next_reward',    v_premios[v_prox],
    'rewards',        to_jsonb(v_premios),
    'streak_running', v_ult_data IS NOT NULL AND v_ult_data >= v_hoje - 1,
    'require_phone',  v_exige_tel
  );
END;
$function$;

-- R5 ───────────────────────────────────────────────────────────────────────────
-- Pode perdoar o dia p_dia (falhado) a esta pessoa? Interruptor ligado, limite do
-- mês por usar, pedido pago nos últimos dias (sem compra não há perdão), não fez o
-- check-in nesse dia e fez no dia anterior (só 1 dia falhado de cada vez).
CREATE OR REPLACE FUNCTION public._checkin_perdao_pode(p_uid uuid, p_dia date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p_uid IS NOT NULL AND p_dia IS NOT NULL
     AND public._checkin_cfg_bool('checkin_perdao_ativo', true)
     AND (SELECT count(*) FROM public.checkin_perdoes p
           WHERE p.user_id = p_uid AND p.mes = date_trunc('month', p_dia)::date)
         < GREATEST(public._checkin_cfg_int('checkin_perdao_por_mes', 1), 0)
     AND NOT EXISTS (SELECT 1 FROM public.daily_checkins d WHERE d.user_id = p_uid AND d.checkin_date = p_dia)
     AND NOT EXISTS (SELECT 1 FROM public.checkin_perdoes p WHERE p.user_id = p_uid AND p.dia = p_dia)
     AND EXISTS (SELECT 1 FROM public.daily_checkins d WHERE d.user_id = p_uid AND d.checkin_date = p_dia - 1)
     AND public._checkin_teve_pedido_pago(p_uid, public._checkin_cfg_int('checkin_marco_pedido_pago_dias', 30))
$function$;

-- Antes de gravar o check-in de hoje: se ontem falhou e pode, perdoa ontem.
-- Nunca deita abaixo o check-in (erro regista-se no e2e_log e segue).
CREATE OR REPLACE FUNCTION public._checkin_perdao_antes_checkin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_falhado date := NEW.checkin_date - 1;
BEGIN
  BEGIN
    IF public._checkin_perdao_pode(NEW.user_id, v_falhado) THEN
      INSERT INTO public.checkin_perdoes (user_id, dia, mes)
      VALUES (NEW.user_id, v_falhado, date_trunc('month', v_falhado)::date)
      ON CONFLICT ON CONSTRAINT checkin_perdoes_um_por_dia DO NOTHING;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_checkin_perdao_antes_checkin: % (user %)', SQLERRM, NEW.user_id;
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
    VALUES ('checkin_perdao', 'aplicar', 'falhou', NEW.user_id::text || ' ' || NEW.checkin_date || ': ' || SQLERRM, 'servidor');
  END;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_checkin_perdao_antes ON public.daily_checkins;
CREATE TRIGGER trg_checkin_perdao_antes BEFORE INSERT ON public.daily_checkins
  FOR EACH ROW EXECUTE FUNCTION public._checkin_perdao_antes_checkin();

-- A sequência contínua conta os dias perdoados como feitos (gelo no calendário).
CREATE OR REPLACE FUNCTION public._checkin_sequencia(p_uid uuid, p_ate date)
 RETURNS TABLE(dias integer, inicio date, ultima date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH d AS (
    SELECT x.checkin_date
      FROM (SELECT c.checkin_date FROM public.daily_checkins c
             WHERE c.user_id = p_uid AND c.checkin_date <= p_ate
            UNION
            SELECT p.dia FROM public.checkin_perdoes p
             WHERE p.user_id = p_uid AND p.dia <= p_ate) x
     ORDER BY x.checkin_date DESC
     LIMIT 800
  ), g AS (
    SELECT d.checkin_date,
           d.checkin_date + (row_number() OVER (ORDER BY d.checkin_date DESC))::int AS grupo
      FROM d
  ), primeiro AS (
    SELECT g.grupo FROM g ORDER BY g.checkin_date DESC LIMIT 1
  )
  SELECT count(*)::int, min(g.checkin_date), max(g.checkin_date)
    FROM g
   WHERE g.grupo = (SELECT p.grupo FROM primeiro p)
$function$;

-- Depois do check-in: os prémios do dia. Com um perdão a ponte salta um dia da
-- escada; o degrau do dia perdoado também conta (nunca se perde um prémio por isso).
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
  v_perd   boolean;
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
    v_perd   := v_dia > 1 AND EXISTS (SELECT 1 FROM public.checkin_perdoes p
                                       WHERE p.user_id = NEW.user_id AND p.dia = NEW.checkin_date - 1);
    FOR m IN SELECT x FROM jsonb_array_elements(public._checkin_marcos_config()) x LOOP
      IF (m ->> 'tipo') IN ('produto','servico')
         AND COALESCE((m ->> 'ativo')::boolean, true)
         AND ((m ->> 'dia')::int = v_dia OR (v_perd AND (m ->> 'dia')::int = v_dia - 1)) THEN
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

-- Funções internas: fechadas a toda a gente (só o servidor as chama).
REVOKE ALL ON FUNCTION public._checkin_teve_pedido_pago(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_precisa_pedido(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_vale_emitir(uuid, jsonb, date, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_custo_mes_cents(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_vale_ativar(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_marco_valor(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_sugestao(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_escada_chegou(uuid, jsonb, date, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_estado(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_perdao_pode(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_perdao_antes_checkin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_sequencia(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_marcos_apos_checkin() FROM PUBLIC, anon, authenticated;
