-- Missão fechar-tudo-2026-11-10, Bloco G — parte 5 de 6: painel admin (PT-BR) e o aviso dos 80%.
--  admin_checkin_regras_resumo()          → interruptores R2-R8 com a explicação, custo do mês
--                                            contra o teto (aviso aos 80%), quem está em que dia,
--                                            prêmios guardados / à espera / levantados, a escada
--                                            com foto, valor e custo de cada degrau;
--  admin_checkin_regra_definir(key, valor) → muda um interruptor/número das regras (lista fechada);
--  admin_checkin_degrau_editar(chave, campos) → edita um degrau (dia, prêmio, loja, foto, valor, custo);
--  checkin_premios_manutencao()            → além do que já fazia, avisa o Danilo no painel
--                                            (admin_notifications) quando o custo do mês chega aos 80%.
-- Guarda: public.is_admin() (lê auth.uid(); nunca o papel da ligação, que em SECURITY DEFINER é sempre o dono).

CREATE OR REPLACE FUNCTION public._checkin_euros(p_cents integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT replace(to_char(COALESCE(p_cents, 0) / 100.0, 'FM999999990.00'), '.', ',') || ' €'
$function$;

-- Chaves das regras que o painel pode mudar (e o tipo de cada uma).
CREATE OR REPLACE FUNCTION public._checkin_regras_chaves()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'checkin_marco_exige_pedido_pago', 'bool',      -- R2
    'checkin_marco_pedido_pago_dias', 'int',        -- R2
    'checkin_marco_espera_pedido_dias', 'int',      -- R2
    'checkin_pedido_conta_tvde', 'bool',            -- R2
    'checkin_escada_ativa', 'bool',                 -- R3
    'checkin_quero_este_recomeca_semana', 'bool',   -- R3
    'checkin_sugestao_ativa', 'bool',               -- R4
    'checkin_perdao_ativo', 'bool',                 -- R5
    'checkin_perdao_por_mes', 'int',                -- R5
    'checkin_premios_tecto_custo_ativo', 'bool',    -- R6
    'checkin_premios_tecto_custo_cents', 'int',     -- R6
    'checkin_premios_tecto_aviso_pct', 'int',       -- R6
    'checkin_lembrete_hora_habitual', 'bool',       -- R8
    'checkin_lembrete_max_falhas', 'int')           -- R8
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_regras_resumo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje    date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_mes     date := date_trunc('month', (now() AT TIME ZONE 'Europe/Lisbon'))::date;
  v_mes_ini timestamptz := (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
  v_ciclo   integer := LEAST(GREATEST(public._checkin_cfg_int('checkin_marco_ciclo_dias', 30), 1), 365);
  v_custo   integer := public._checkin_custo_mes_cents(NULL);
  v_tecto   integer := GREATEST(public._checkin_cfg_int('checkin_premios_tecto_custo_cents', 0), 0);
  v_t_on    boolean := public._checkin_cfg_bool('checkin_premios_tecto_custo_ativo', true);
  v_aviso   integer := LEAST(GREATEST(public._checkin_cfg_int('checkin_premios_tecto_aviso_pct', 80), 1), 100);
  v_pct     integer;
  v_defs    jsonb;
  v_dias    jsonb;
  v_degraus jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  v_pct := CASE WHEN v_tecto > 0 THEN floor(v_custo * 100.0 / v_tecto)::int END;

  SELECT COALESCE(jsonb_object_agg(s.key, jsonb_build_object('valor', s.value, 'descricao', s.description)), '{}'::jsonb)
    INTO v_defs
    FROM public.platform_settings s
   WHERE public._checkin_regras_chaves() ? s.key;

  -- quem está em que dia: só sequências a correr (fez hoje ou ontem)
  WITH u AS (
    SELECT DISTINCT c.user_id FROM public.daily_checkins c WHERE c.checkin_date >= v_hoje - 1
  ), s AS (
    SELECT q.dias FROM u CROSS JOIN LATERAL public._checkin_seq_marcos(u.user_id, v_hoje) q
     WHERE q.ultima >= v_hoje - 1 AND q.dias > 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('dia', z.dia, 'pessoas', z.n) ORDER BY z.dia), '[]'::jsonb)
    INTO v_dias
    FROM (SELECT ((s.dias - 1) % v_ciclo) + 1 AS dia, count(*) AS n FROM s GROUP BY 1) z;

  SELECT COALESCE(jsonb_agg(public._checkin_marco_publico(x) || jsonb_build_object(
           'ativo', COALESCE((x ->> 'ativo')::boolean, true),
           'custo_cents', CASE WHEN COALESCE(x ->> 'custo_cents', '') ~ '^[0-9]{1,9}$' THEN (x ->> 'custo_cents')::int END,
           'produto_id', x ->> 'produto_id',
           'foto_escolhida', x ->> 'foto_url',
           'minimo_cents', CASE WHEN COALESCE(x ->> 'minimo_cents', '') ~ '^[0-9]{1,9}$' THEN (x ->> 'minimo_cents')::int END)
           ORDER BY (x ->> 'dia')::int), '[]'::jsonb)
    INTO v_degraus
    FROM jsonb_array_elements(public._checkin_marcos_config()) x
   WHERE x ->> 'tipo' IN ('produto','servico','desconto');

  RETURN jsonb_build_object(
    'definicoes', v_defs,
    'mes', to_char(v_mes, 'YYYY-MM'),
    'custo_mes_cents', v_custo,
    'tecto_ativo', v_t_on,
    'tecto_cents', v_tecto,
    'aviso_pct', v_aviso,
    'pct_usado', v_pct,
    'aviso', COALESCE(v_t_on AND v_pct IS NOT NULL AND v_pct >= v_aviso, false),
    'esgotado', COALESCE(v_t_on AND v_tecto > 0 AND v_custo >= v_tecto, false),
    'por_dia', v_dias,
    'premios', jsonb_build_object(
      'guardados_escada', (SELECT count(*) FROM public.checkin_escada e
                            WHERE e.guardado_chave IS NOT NULL AND (e.garantido_ate IS NULL OR e.garantido_ate > now())),
      'a_espera_pedido', (SELECT count(*) FROM public.checkin_premios_vales v WHERE v.estado = 'a_espera_pedido'),
      'guardados_teto', (SELECT count(*) FROM public.checkin_premios_vales v WHERE v.estado = 'guardado'),
      'por_usar', (SELECT count(*) FROM public.checkin_premios_vales v WHERE v.estado IN ('por_usar','reservado')),
      'levantados_mes', (SELECT count(*) FROM public.checkin_premios_vales v
                          WHERE v.origem = 'checkin' AND v.emitido_em >= v_mes_ini AND v.estado <> 'anulado'),
      'usados_mes', (SELECT count(*) FROM public.checkin_premios_vales v WHERE v.estado = 'usado' AND v.usado_em >= v_mes_ini)),
    'perdoes_mes', (SELECT count(*) FROM public.checkin_perdoes p WHERE p.mes = v_mes),
    'lembretes_hoje', (SELECT count(*) FROM public.checkin_lembretes_envios e WHERE e.dia = v_hoje),
    'lembretes_desligados', (SELECT count(*) FROM public.checkin_lembrete_prefs p WHERE p.desligado),
    'degraus', v_degraus,
    'descontos', jsonb_build_object(
      'total', (SELECT count(*) FROM jsonb_array_elements(public._checkin_marcos_config()) x WHERE x ->> 'tipo' = 'desconto'),
      'ligados', (SELECT count(*) FROM jsonb_array_elements(public._checkin_marcos_config()) x
                   WHERE x ->> 'tipo' = 'desconto' AND COALESCE((x ->> 'ativo')::boolean, true)))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_regra_definir(p_key text, p_valor jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tipo text := public._checkin_regras_chaves() ->> p_key;
  v_old  jsonb;
  v_num  integer;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'chave_nao_e_regra_do_checkin: %', p_key USING ERRCODE = '22023';
  END IF;
  IF v_tipo = 'bool' AND jsonb_typeof(p_valor) <> 'boolean' THEN
    RAISE EXCEPTION 'valor_tem_de_ser_ligado_ou_desligado' USING ERRCODE = '22023';
  END IF;
  IF v_tipo = 'int' THEN
    IF jsonb_typeof(p_valor) <> 'number' OR (p_valor #>> '{}') !~ '^[0-9]{1,9}$' THEN
      RAISE EXCEPTION 'valor_tem_de_ser_numero_inteiro' USING ERRCODE = '22023';
    END IF;
    v_num := (p_valor #>> '{}')::int;
    IF p_key = 'checkin_premios_tecto_aviso_pct' AND (v_num < 1 OR v_num > 100) THEN
      RAISE EXCEPTION 'aviso_entre_1_e_100' USING ERRCODE = '22023';
    END IF;
    IF p_key IN ('checkin_marco_pedido_pago_dias', 'checkin_marco_espera_pedido_dias') AND (v_num < 1 OR v_num > 365) THEN
      RAISE EXCEPTION 'dias_entre_1_e_365' USING ERRCODE = '22023';
    END IF;
    IF p_key = 'checkin_lembrete_max_falhas' AND (v_num < 1 OR v_num > 30) THEN
      RAISE EXCEPTION 'falhas_entre_1_e_30' USING ERRCODE = '22023';
    END IF;
    IF p_key = 'checkin_perdao_por_mes' AND v_num > 10 THEN
      RAISE EXCEPTION 'perdao_no_maximo_10_por_mes' USING ERRCODE = '22023';
    END IF;
  END IF;
  SELECT value INTO v_old FROM public.platform_settings WHERE key = p_key;
  INSERT INTO public.platform_settings (key, value, category, updated_at, updated_by)
  VALUES (p_key, p_valor, 'marketing', now(), auth.uid())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = auth.uid();
  PERFORM public.log_admin_action('checkin_regra_mudada', 'platform_setting', NULL,
                                  jsonb_build_object('key', p_key, 'old', v_old, 'new', p_valor));
  RETURN jsonb_build_object('ok', true, 'key', p_key, 'valor', p_valor);
END;
$function$;

-- Editar um degrau da escada. Os degraus de desconto ficam desligados até o desconto
-- entrar no pagamento (R7: proposta em docs/propostas/fechar-tudo-2026-11-10/).
CREATE OR REPLACE FUNCTION public.admin_checkin_degrau_editar(p_chave text, p_campos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key  text := 'checkin_marco_' || lower(trim(COALESCE(p_chave, '')));
  v_old  jsonb;
  v_new  jsonb;
  v_c    text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  SELECT value INTO v_old FROM public.platform_settings WHERE key = v_key;
  IF v_old IS NULL OR jsonb_typeof(v_old) <> 'object' THEN
    RAISE EXCEPTION 'degrau_nao_existe: %', v_key USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(COALESCE(p_campos, 'null'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'campos_invalidos' USING ERRCODE = '22023';
  END IF;
  FOR v_c IN SELECT jsonb_object_keys(p_campos) LOOP
    IF v_c NOT IN ('dia','titulo','descricao','loja_id','produto_id','foto_url','valor_cents','custo_cents','ativo') THEN
      RAISE EXCEPTION 'campo_nao_editavel: %', v_c USING ERRCODE = '22023';
    END IF;
  END LOOP;
  IF p_campos ? 'dia' AND ((p_campos ->> 'dia') !~ '^[0-9]{1,3}$' OR (p_campos ->> 'dia')::int NOT BETWEEN 1 AND 365) THEN
    RAISE EXCEPTION 'dia_invalido' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'valor_cents' AND (p_campos ->> 'valor_cents') !~ '^[0-9]{1,9}$' THEN
    RAISE EXCEPTION 'valor_invalido' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'custo_cents' AND (p_campos ->> 'custo_cents') !~ '^[0-9]{1,9}$' THEN
    RAISE EXCEPTION 'custo_invalido' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'titulo' AND NULLIF(trim(COALESCE(p_campos ->> 'titulo', '')), '') IS NULL THEN
    RAISE EXCEPTION 'titulo_obrigatorio' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'foto_url' AND COALESCE(p_campos ->> 'foto_url', '') <> ''
     AND (p_campos ->> 'foto_url') !~* '^https://' THEN
    RAISE EXCEPTION 'foto_tem_de_ser_https' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'ativo' AND jsonb_typeof(p_campos -> 'ativo') <> 'boolean' THEN
    RAISE EXCEPTION 'ativo_tem_de_ser_ligado_ou_desligado' USING ERRCODE = '22023';
  END IF;
  IF v_old ->> 'tipo' = 'desconto' AND COALESCE((p_campos ->> 'ativo')::boolean, false) THEN
    RAISE EXCEPTION 'desconto_fica_desligado_ate_entrar_no_pagamento' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'loja_id' AND NOT EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id = p_campos ->> 'loja_id') THEN
    RAISE EXCEPTION 'loja_nao_encontrada' USING ERRCODE = '22023';
  END IF;
  IF p_campos ? 'produto_id' AND NOT EXISTS (
       SELECT 1 FROM public.products p
        WHERE p.id = p_campos ->> 'produto_id'
          AND p.restaurant_id = COALESCE(p_campos ->> 'loja_id', v_old ->> 'loja_id')) THEN
    RAISE EXCEPTION 'produto_nao_e_desta_loja' USING ERRCODE = '22023';
  END IF;

  v_new := v_old || (SELECT jsonb_object_agg(k, CASE
                        WHEN k IN ('dia','valor_cents','custo_cents') THEN to_jsonb((p_campos ->> k)::int)
                        WHEN k = 'foto_url' AND COALESCE(p_campos ->> k, '') = '' THEN 'null'::jsonb
                        ELSE p_campos -> k END)
                       FROM jsonb_object_keys(p_campos) k);
  v_new := jsonb_strip_nulls(v_new);
  UPDATE public.platform_settings SET value = v_new, updated_at = now(), updated_by = auth.uid() WHERE key = v_key;
  PERFORM public.log_admin_action('checkin_degrau_editado', 'platform_setting', NULL,
                                  jsonb_build_object('key', v_key, 'old', v_old, 'new', v_new));
  RETURN public._checkin_marco_publico(v_new) || jsonb_build_object('custo_cents', v_new -> 'custo_cents',
                                                                    'ativo', COALESCE((v_new ->> 'ativo')::boolean, true));
END;
$function$;

-- Manutenção de hora a hora: igual a 21/10 + R6 (aviso dos 80% ao Danilo, uma vez por mês).
CREATE OR REPLACE FUNCTION public.checkin_premios_manutencao()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje     date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_dias_ped integer := COALESCE((public._checkin_marco_cfg('checkin_marco_pedido_pago_dias', '30'::jsonb) #>> '{}')::int, 30);
  v_exige    boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_exige_pedido_pago', 'true'::jsonb) #>> '{}')::boolean, true);
  v_exp      integer := 0;
  v_lib      integer := 0;
  v_atv      integer := 0;
  v_esp_exp  integer := 0;
  v_aviso    boolean := false;
  v_custo    integer;
  v_tecto    integer;
  v_pct      integer;
  r          record;
BEGIN
  -- reservas de carrinho esquecidas voltam a "por usar"
  UPDATE public.checkin_premios_vales
     SET estado = 'por_usar', reservado_ate = NULL, atualizado_em = now()
   WHERE estado = 'reservado' AND pedido_id IS NULL AND reservado_ate < now() - interval '30 minutes';
  GET DIAGNOSTICS v_lib = ROW_COUNT;

  -- fora de prazo (2 h de folga a um vale reservado: o pagamento pode estar a meio)
  UPDATE public.checkin_premios_vales
     SET estado = 'expirado', atualizado_em = now()
   WHERE (estado = 'por_usar' AND valido_ate <= now())
      OR (estado = 'reservado' AND valido_ate <= now() - interval '2 hours');
  GET DIAGNOSTICS v_exp = ROW_COUNT;

  -- a espera de um pedido pago (se o interruptor da regra for desligado, saem todos)
  FOR r IN SELECT id, user_id, esperar_ate FROM public.checkin_premios_vales WHERE estado = 'a_espera_pedido' LOOP
    IF NOT v_exige OR public._checkin_teve_pedido_pago(r.user_id, v_dias_ped) THEN
      PERFORM public._checkin_vale_ativar(r.id, true);
      v_atv := v_atv + 1;
    ELSIF r.esperar_ate IS NOT NULL AND r.esperar_ate <= now() THEN
      UPDATE public.checkin_premios_vales
         SET estado = 'expirado', motivo = COALESCE(motivo || ' | ', '') || 'sem pedido pago no prazo', atualizado_em = now()
       WHERE id = r.id;
      v_esp_exp := v_esp_exp + 1;
    END IF;
  END LOOP;

  -- guardados pelo tecto: tentam no mes seguinte
  FOR r IN SELECT id FROM public.checkin_premios_vales WHERE estado = 'guardado' AND ativar_em <= v_hoje LOOP
    IF public._checkin_vale_ativar(r.id, true) = 'por_usar' THEN
      v_atv := v_atv + 1;
    END IF;
  END LOOP;

  -- R6: aviso ao Danilo no painel quando o custo do mês chega à percentagem do teto
  BEGIN
    v_custo := public._checkin_custo_mes_cents(NULL);
    v_tecto := GREATEST(public._checkin_cfg_int('checkin_premios_tecto_custo_cents', 0), 0);
    v_pct   := LEAST(GREATEST(public._checkin_cfg_int('checkin_premios_tecto_aviso_pct', 80), 1), 100);
    IF public._checkin_cfg_bool('checkin_premios_tecto_custo_ativo', true) AND v_tecto > 0
       AND v_custo * 100 >= v_tecto * v_pct
       AND NOT EXISTS (SELECT 1 FROM public.admin_notifications n
                        WHERE n.event_type = 'checkin_tecto_aviso' AND n.entity_id = to_char(v_hoje, 'YYYY-MM')) THEN
      INSERT INTO public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
      VALUES ('checkin_tecto_aviso', 'warning', 'checkin', to_char(v_hoje, 'YYYY-MM'),
              format('Prêmios do check-in: o custo do mês já vai em %s%% do teto (%s de %s). Passando o teto, os prêmios ficam guardados para o mês seguinte.',
                     floor(v_custo * 100.0 / v_tecto)::int, public._checkin_euros(v_custo), public._checkin_euros(v_tecto)),
              jsonb_build_object('custo_cents', v_custo, 'tecto_cents', v_tecto, 'aviso_pct', v_pct));
      v_aviso := true;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'checkin_premios_manutencao (aviso do teto): %', SQLERRM;
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
    VALUES ('checkin_premios', 'aviso_teto', 'falhou', SQLERRM, 'servidor');
  END;

  RETURN jsonb_build_object('ok', true, 'expirados', v_exp, 'reservas_libertadas', v_lib,
                            'ativados', v_atv, 'espera_expirada', v_esp_exp, 'aviso_teto', v_aviso);
END;
$function$;

REVOKE ALL ON FUNCTION public._checkin_euros(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_regras_chaves() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.checkin_premios_manutencao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_checkin_regras_resumo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_regra_definir(text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_degrau_editar(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_checkin_regras_resumo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_regra_definir(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_degrau_editar(text, jsonb) TO authenticated;
