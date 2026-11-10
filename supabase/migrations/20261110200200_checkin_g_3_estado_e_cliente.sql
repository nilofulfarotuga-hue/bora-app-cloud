-- Missão fechar-tudo-2026-11-10, Bloco G — parte 3 de 6: o que a app lê.
-- _checkin_estado_marcos passa a trazer, além do que já trazia (nada sai):
--   marcos[].valor_cents / foto_url / loja_foto_url (foto REAL: a do produto; prémio da
--   loja = foto da loja; nunca se altera), guardado e proximo_maior com foto e valor,
--   sugestao (R4), precisa_pedido (R2), perdao (R5: pendente, aviso, dias com gelo) e
--   lembrete (R8: ligado e hora habitual).
-- Funções novas da app: client_checkin_perdao_visto() e client_checkin_lembrete_definir(bool).

-- Foto de um degrau: a escolhida no painel (foto_url), senão a do produto-prémio,
-- senão a da loja. Só fotos que já existem; nunca se gera nem se altera uma foto.
CREATE OR REPLACE FUNCTION public._checkin_marco_foto(p_marco jsonb)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    NULLIF(trim(COALESCE(p_marco ->> 'foto_url', '')), ''),
    CASE WHEN p_marco ->> 'tipo' = 'produto'
         THEN (SELECT NULLIF(trim(COALESCE(p.photo_url, '')), '') FROM public.products p WHERE p.id = p_marco ->> 'produto_id') END,
    (SELECT COALESCE(NULLIF(trim(COALESCE(r.photo_url, '')), ''), NULLIF(trim(COALESCE(r.cover_url, '')), ''),
                     NULLIF(trim(COALESCE(r.hero_image_url, '')), ''))
       FROM public.restaurants r WHERE r.id = p_marco ->> 'loja_id'))
$function$;

-- Um degrau com o que a app mostra (sem custo: o custo é só do painel).
CREATE OR REPLACE FUNCTION public._checkin_marco_publico(p_marco jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN p_marco IS NULL THEN NULL ELSE jsonb_build_object(
    'chave', p_marco ->> 'chave', 'dia', (p_marco ->> 'dia')::int, 'tipo', p_marco ->> 'tipo',
    'titulo', p_marco ->> 'titulo', 'descricao', p_marco ->> 'descricao',
    'valor_cents', CASE WHEN COALESCE(p_marco ->> 'valor_cents', '') ~ '^[0-9]{1,9}$' THEN (p_marco ->> 'valor_cents')::int END,
    'foto_url', public._checkin_marco_foto(p_marco),
    'loja_id', p_marco ->> 'loja_id',
    'loja_nome', (SELECT r.name FROM public.restaurants r WHERE r.id = p_marco ->> 'loja_id')) END
$function$;

-- R8: hora (Lisboa) a que a pessoa costuma fazer o check-in — a moda dos últimos 14;
-- sem histórico, a hora do lembrete da manhã.
CREATE OR REPLACE FUNCTION public._checkin_hora_habitual(p_uid uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT z.h FROM (SELECT extract(hour FROM (c.created_at AT TIME ZONE 'Europe/Lisbon'))::int AS h
                        FROM public.daily_checkins c
                       WHERE c.user_id = p_uid
                       ORDER BY c.checkin_date DESC
                       LIMIT 14) z
      GROUP BY z.h ORDER BY count(*) DESC, z.h LIMIT 1),
    public._checkin_cfg_int('checkin_push_morning_hour', 11))
$function$;

CREATE OR REPLACE FUNCTION public._checkin_estado_marcos(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje     date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_mes      date := date_trunc('month', (now() AT TIME ZONE 'Europe/Lisbon'))::date;
  v_ciclo    integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_ciclo_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_ativo    boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_ativo', 'false'::jsonb) #>> '{}')::boolean, false);
  v_cfg      jsonb := public._checkin_marcos_config();
  v_premios  integer[] := public._checkin_premios();
  v_escada   boolean := public._checkin_escada_ativa();
  v_degraus  jsonb := public._checkin_escada_degraus();
  v_perd_on  boolean := public._checkin_cfg_bool('checkin_perdao_ativo', true);
  v_perd_max integer := GREATEST(public._checkin_cfg_int('checkin_perdao_por_mes', 1), 0);
  v_exige    boolean := public._checkin_cfg_bool('checkin_marco_exige_pedido_pago', true);
  v_seq      record;
  v_er       public.checkin_escada%ROWTYPE;
  v_dias     integer := 0;
  v_dia      integer := 0;
  v_inicio   date := NULL;
  v_ult      date := NULL;
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
  v_tem_ped  boolean := false;
  v_perd_pend boolean := false;
  v_perd_usados integer := 0;
  v_perd_dias jsonb := '[]'::jsonb;
  v_perd_aviso date := NULL;
  v_sug      jsonb := NULL;
  v_lemb_off boolean := false;
BEGIN
  IF p_uid IS NOT NULL THEN
    v_tem_ped := public._checkin_teve_pedido_pago(p_uid, public._checkin_cfg_int('checkin_marco_pedido_pago_dias', 30));
    SELECT * INTO v_seq FROM public._checkin_seq_marcos(p_uid, v_hoje);
    IF v_seq.ultima IS NOT NULL AND v_seq.ultima >= v_hoje - 1 THEN
      v_dias  := COALESCE(v_seq.dias, 0);
      v_feito := v_seq.ultima = v_hoje;
      v_ult   := v_seq.ultima;
    ELSIF v_seq.ultima = v_hoje - 2 AND COALESCE(v_seq.dias, 0) > 0
          AND public._checkin_perdao_pode(p_uid, v_hoje - 1) THEN
      -- R5: falhou ontem, mas o perdão deste mês segura a sequência quando fizer o
      -- check-in de hoje (o dia de ontem passa a contar, com gelo).
      v_perd_pend := true;
      v_dias := v_seq.dias + 1;
      v_ult  := v_hoje - 1;
    END IF;
    SELECT * INTO v_er FROM public.checkin_escada e WHERE e.user_id = p_uid;
    SELECT count(*) INTO v_perd_usados FROM public.checkin_perdoes p WHERE p.user_id = p_uid AND p.mes = v_mes;
    SELECT max(p.dia) INTO v_perd_aviso FROM public.checkin_perdoes p WHERE p.user_id = p_uid AND p.visto_em IS NULL;
    SELECT COALESCE(p.desligado, false) INTO v_lemb_off FROM public.checkin_lembrete_prefs p WHERE p.user_id = p_uid;
  END IF;
  IF v_dias > 0 THEN
    v_dia    := ((v_dias - 1) % v_ciclo) + 1;
    v_inicio := v_ult - (v_dia - 1);
    SELECT COALESCE(jsonb_agg((p.dia - v_inicio) + 1 ORDER BY p.dia), '[]'::jsonb) INTO v_perd_dias
      FROM public.checkin_perdoes p
     WHERE p.user_id = p_uid AND p.dia BETWEEN v_inicio AND v_ult;
    IF v_perd_pend THEN
      v_perd_dias := v_perd_dias || to_jsonb(v_dia);
    END IF;
  END IF;

  FOR m IN SELECT x FROM jsonb_array_elements(COALESCE(v_cfg, '[]'::jsonb)) x LOOP
    CONTINUE WHEN NOT COALESCE((m ->> 'ativo')::boolean, true);
    CONTINUE WHEN (m ->> 'dia')::int > v_ciclo;
    v_falta := GREATEST((m ->> 'dia')::int - v_dia, 0);
    v_marcos := v_marcos || jsonb_build_array(
      public._checkin_marco_publico(m) || jsonb_build_object(
        'tokens', CASE WHEN m ->> 'tipo' = 'tokens' THEN v_premios[7] END,
        'atingido', v_dia >= (m ->> 'dia')::int,
        'faltam', v_falta,
        'loja_foto_url', (SELECT COALESCE(NULLIF(trim(COALESCE(r.photo_url, '')), ''), NULLIF(trim(COALESCE(r.cover_url, '')), ''))
                            FROM public.restaurants r WHERE r.id = m ->> 'loja_id')));
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

  -- R4: a melhor sugestão (uma só): o guardado, ou o mais valioso a que já chegou
  IF v_gval THEN
    v_sug := public._checkin_marco_publico(v_er.guardado_marco);
  ELSIF p_uid IS NOT NULL AND v_dia > 0 THEN
    v_sug := public._checkin_marco_publico(public._checkin_sugestao(p_uid, v_dia));
  END IF;

  RETURN jsonb_build_object(
    'marcos_ativos', v_ativo,
    'ciclo_dias', v_ciclo,
    'dias_seguidos', v_dias,
    'dia_marco', v_dia,
    'ciclo_inicio', v_inicio,
    'hoje_feito', v_feito,
    'marcos', v_marcos,
    'tokens_por_dia', to_jsonb(v_premios),
    'proximo', v_prox,
    'sugestao', v_sug,
    'precisa_pedido', COALESCE(p_uid IS NOT NULL AND v_exige AND NOT v_tem_ped, false),
    'perdao', jsonb_build_object(
      'ativo', v_perd_on,
      'por_mes', v_perd_max,
      'usados_mes', v_perd_usados,
      'disponivel', COALESCE(v_perd_on AND v_perd_usados < v_perd_max AND v_tem_ped, false),
      'pendente', v_perd_pend,
      'aviso_dia', v_perd_aviso,
      'dias', v_perd_dias),
    'lembrete', jsonb_build_object(
      'ligado', NOT COALESCE(v_lemb_off, false),
      'hora', CASE WHEN p_uid IS NOT NULL THEN public._checkin_hora_habitual(p_uid) END),
    'escada', jsonb_build_object(
      'ativa', v_escada,
      'texto', COALESCE(public._checkin_marco_cfg('checkin_escada_texto', 'null'::jsonb) #>> '{}',
        'Em cada sequência levas UM prémio: o mais valioso a que chegares. «Quero este» leva o prémio e a escada dos prémios volta ao dia 1 (os tokens de cada dia continuam). «Continuar» troca por um prémio maior.'),
      'guardado', CASE WHEN v_gval THEN jsonb_build_object(
          'chave', v_er.guardado_chave, 'dia', v_er.guardado_dia, 'titulo', v_er.guardado_titulo,
          'tipo', v_er.guardado_tipo, 'descricao', v_er.guardado_marco ->> 'descricao',
          'guardado_em', v_er.guardado_em, 'garantido_ate', v_er.garantido_ate,
          'valor_cents', (public._checkin_marco_publico(v_er.guardado_marco) ->> 'valor_cents')::int,
          'foto_url', public._checkin_marco_foto(v_er.guardado_marco),
          'loja_nome', (SELECT r.name FROM public.restaurants r WHERE r.id = v_er.guardado_marco ->> 'loja_id')) END,
      'decisao', CASE WHEN v_gval THEN v_er.decisao END,
      'pendente_decisao', COALESCE(v_gval AND v_er.decisao = 'pendente' AND v_maior IS NOT NULL, false),
      'pode_continuar', COALESCE(v_gval AND v_maior IS NOT NULL, false),
      'proximo_maior', CASE WHEN v_maior IS NOT NULL THEN jsonb_build_object(
          'chave', v_maior ->> 'chave', 'dia', (v_maior ->> 'dia')::int, 'titulo', v_maior ->> 'titulo',
          'descricao', v_maior ->> 'descricao', 'faltam', GREATEST((v_maior ->> 'dia')::int - v_dia, 0),
          'tipo', v_maior ->> 'tipo',
          'valor_cents', (public._checkin_marco_publico(v_maior) ->> 'valor_cents')::int,
          'foto_url', public._checkin_marco_foto(v_maior),
          'loja_nome', (SELECT r.name FROM public.restaurants r WHERE r.id = v_maior ->> 'loja_id')) END,
      'ultimo_dia', v_ultimo,
      'levantados', COALESCE(v_er.levantados, 0),
      'reinicio_data', v_er.reinicio_data,
      'ultimo_vale_id', v_er.ultimo_vale_id,
      'proximo_premio_em', CASE WHEN p_uid IS NOT NULL THEN public._checkin_premio_proximo_em(p_uid) END,
      'intervalo_dias', LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_premio_intervalo_dias', '30'::jsonb) #>> '{}')::int, 30), 0), 365))
  );
END;
$function$;

-- R5: a app já mostrou "Usámos o teu perdão deste mês".
CREATE OR REPLACE FUNCTION public.client_checkin_perdao_visto()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_n   integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;
  UPDATE public.checkin_perdoes SET visto_em = now() WHERE user_id = v_uid AND visto_em IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'vistos', v_n);
END;
$function$;

-- R8: botão "Lembrete diário" na app (ligar/desligar só o lembrete do check-in).
CREATE OR REPLACE FUNCTION public.client_checkin_lembrete_definir(p_ligado boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;
  INSERT INTO public.checkin_lembrete_prefs (user_id, desligado, atualizado_em)
  VALUES (v_uid, NOT COALESCE(p_ligado, true), now())
  ON CONFLICT (user_id) DO UPDATE SET desligado = EXCLUDED.desligado, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'ligado', COALESCE(p_ligado, true));
END;
$function$;

REVOKE ALL ON FUNCTION public._checkin_marco_foto(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_marco_publico(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_hora_habitual(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_estado_marcos(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_checkin_perdao_visto() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_lembrete_definir(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_checkin_perdao_visto() TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_lembrete_definir(boolean) TO authenticated;
