-- Bloco D · fechar-pendencias-2026-10-20 — marcos do check-in (Bora Todo Dia).
-- Parte 2/4 (regras, avisos e emissao no check-in). Base: tabela dos vales, sequencia continua, emissao no check-in, leitura do cliente,
-- manutencao horaria e funcoes do painel. Nao mexe nos tokens do check-in (Dia1..Dia7
-- continuam como estao) nem em nenhuma funcao de cobranca.
-- Marcos por sequencia continua: 7 (os tokens do Dia 7, so se mostra), 10, 15 e 30.
-- Falhou um dia -> volta a 1. Depois do dia 30 o ciclo recomeca no 1.

-- 4) Regra do pedido pago (como Uber One / Glovo Prime) ------------------------------
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
              AND COALESCE(o.price, 0) > 0 AND o.delivered_at >= j.desde
              AND (NOT COALESCE(o.is_test_order, false) OR j.demo))
      OR EXISTS (
           SELECT 1 FROM public.tvde_rides r, j
            WHERE r.client_id = p_uid AND r.status = 'finalizada' AND r.created_at >= j.desde)
      OR EXISTS (
           SELECT 1 FROM public.cleaning_bookings b, j
            WHERE b.client_user_id = p_uid AND b.status = 'completed'
              AND b.payment_method IN ('card','mbway','cash')
              AND COALESCE(b.completed_at, b.scheduled_at) >= j.desde
              AND (NOT COALESCE(b.is_test_order, false) OR j.demo))
      OR EXISTS (
           SELECT 1 FROM public.carwash_bookings w, j
            WHERE w.client_user_id = p_uid AND w.status = 'completed'
              AND w.payment_method IN ('card','mbway','cash')
              AND COALESCE(w.completed_at, w.scheduled_at) >= j.desde
              AND (NOT COALESCE(w.is_test_order, false) OR j.demo))
$function$;

-- 5) Avisos (sino da app + notificacao no telemovel) --------------------------------
CREATE OR REPLACE FUNCTION public._checkin_vale_avisar(p_vale_id uuid, p_motivo text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v      public.checkin_premios_vales;
  v_tit  text;
  v_txt  text;
  v_url  text;
  v_key  text;
  v_data text;
  v_mes  text;
BEGIN
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id;
  IF v.id IS NULL THEN RETURN; END IF;
  v_data := to_char(v.valido_ate AT TIME ZONE 'Europe/Lisbon', 'DD/MM');
  v_mes  := CASE extract(month FROM COALESCE(v.ativar_em, current_date))::int
              WHEN 1 THEN 'janeiro' WHEN 2 THEN 'fevereiro' WHEN 3 THEN 'março' WHEN 4 THEN 'abril'
              WHEN 5 THEN 'maio' WHEN 6 THEN 'junho' WHEN 7 THEN 'julho' WHEN 8 THEN 'agosto'
              WHEN 9 THEN 'setembro' WHEN 10 THEN 'outubro' WHEN 11 THEN 'novembro' ELSE 'dezembro' END;

  IF v.estado = 'guardado' THEN
    v_tit := 'Chegaste aos ' || v.marco || ' dias seguidos!';
    v_txt := 'Este mês já não há mais prémios de ' || v.marco || ' dias. O teu fica guardado e fica disponível a 1 de ' || v_mes || '.';
  ELSIF v.estado = 'a_espera_pedido' THEN
    v_tit := 'Chegaste aos ' || v.marco || ' dias seguidos!';
    v_txt := 'Falta 1 pedido para desbloquear o prémio. Faz um pedido nos próximos 30 dias.';
  ELSIF p_motivo = 'ativado' THEN
    v_tit := 'O teu prémio já está disponível';
    v_txt := 'Ganhaste ' || v.titulo || '. Vê em Os meus prémios. Vale até ' || COALESCE(v_data, '') || '.';
  ELSE
    v_tit := 'Ganhaste ' || v.titulo || '!';
    v_txt := CASE WHEN v.origem = 'admin'
                  THEN 'A Bora deu-te um prémio. '
                  ELSE 'Fizeste ' || v.marco || ' dias seguidos de check-in. ' END
             || 'Vê em Os meus prémios. Vale até ' || COALESCE(v_data, '') || '.';
  END IF;

  PERFORM public._push_in_app_notification(v.user_id, 'checkin_premio', v_tit, v_txt, v.id::text);

  BEGIN
    IF EXISTS (SELECT 1 FROM public.client_push_tokens t WHERE t.user_id = v.user_id AND t.active) THEN
      SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
      IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/push-clientes-alvo',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('user_ids', jsonb_build_array(v.user_id), 'title', v_tit, 'body', v_txt,
                                     'type', 'checkin_premio'),
          timeout_milliseconds := 30000);
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_checkin_vale_avisar: push falhou (vale %): %', p_vale_id, SQLERRM;
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
    VALUES ('checkin_marcos', 'aviso_push', 'falhou', p_vale_id::text || ': ' || SQLERRM, 'servidor');
  END;
END;
$function$;

-- 6) Ativar um vale (tecto mensal dos vales de servico) -----------------------------
-- Devolve o estado em que o vale ficou: 'por_usar' ou 'guardado'.
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
  v_usados    integer;
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
    IF v_usados >= v_tecto THEN
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

-- 7) Emitir um vale de um marco ----------------------------------------------------
CREATE OR REPLACE FUNCTION public._checkin_vale_emitir(p_uid uuid, p_marco jsonb, p_ciclo_inicio date,
                                                       p_origem text DEFAULT 'checkin', p_admin uuid DEFAULT NULL,
                                                       p_motivo text DEFAULT NULL)
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
  IF v_tipo NOT IN ('produto','servico') THEN RETURN NULL; END IF;
  IF jsonb_typeof(p_marco -> 'opcoes') = 'array' THEN
    SELECT COALESCE(array_agg(o), '{}'::text[]) INTO v_opcoes FROM jsonb_array_elements_text(p_marco -> 'opcoes') o;
  END IF;

  INSERT INTO public.checkin_premios_vales (
    user_id, marco, marco_chave, tipo, ciclo_inicio, estado, titulo, loja_id, produto_id,
    quantidade, opcoes, valor_cents, custo_cents, origem, criado_por, motivo)
  VALUES (
    p_uid, (p_marco ->> 'dia')::int, p_marco ->> 'chave', v_tipo, p_ciclo_inicio, 'por_usar',
    COALESCE(p_marco ->> 'titulo', 'Prémio do check-in'), p_marco ->> 'loja_id', p_marco ->> 'produto_id',
    GREATEST(COALESCE((p_marco ->> 'quantidade')::int, 1), 1), v_opcoes,
    GREATEST(COALESCE((p_marco ->> 'valor_cents')::int, 0), 0), GREATEST(COALESCE((p_marco ->> 'custo_cents')::int, 0), 0),
    p_origem, p_admin, p_motivo)
  ON CONFLICT (user_id, marco_chave, ciclo_inicio) WHERE origem = 'checkin' DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN RETURN NULL; END IF;

  IF v_tipo = 'servico' AND p_origem = 'checkin' AND v_exige
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

-- 8) Gatilho no check-in: emite o vale do marco do dia -------------------------------
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
  v_seq    record;
  v_dia    integer;
  v_inicio date;
  m        jsonb;
BEGIN
  IF NOT v_ativo THEN RETURN NULL; END IF;
  -- o mesmo criterio do check-in: telemovel portugues valido na ficha
  IF v_exige_tel AND NOT public._checkin_telemovel_confirmado(NEW.user_id) THEN RETURN NULL; END IF;

  BEGIN
    SELECT * INTO v_seq FROM public._checkin_sequencia(NEW.user_id, NEW.checkin_date);
    IF COALESCE(v_seq.dias, 0) < 1 OR v_seq.ultima IS DISTINCT FROM NEW.checkin_date THEN
      RETURN NULL;
    END IF;
    v_dia    := ((v_seq.dias - 1) % v_ciclo) + 1;
    v_inicio := NEW.checkin_date - (v_dia - 1);
    FOR m IN SELECT x FROM jsonb_array_elements(public._checkin_marcos_config()) x LOOP
      IF (m ->> 'tipo') IN ('produto','servico')
         AND COALESCE((m ->> 'ativo')::boolean, true)
         AND (m ->> 'dia')::int = v_dia THEN
        PERFORM public._checkin_vale_emitir(NEW.user_id, m, v_inicio);
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

CREATE OR REPLACE TRIGGER trg_checkin_marcos_apos_checkin
  AFTER INSERT ON public.daily_checkins
  FOR EACH ROW EXECUTE FUNCTION public._checkin_marcos_apos_checkin();

-- Permissoes: fechado a quem nao tem sessao
REVOKE ALL ON FUNCTION public._checkin_teve_pedido_pago(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_vale_avisar(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_vale_ativar(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_vale_emitir(uuid, jsonb, date, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_marcos_apos_checkin() FROM PUBLIC, anon, authenticated;
