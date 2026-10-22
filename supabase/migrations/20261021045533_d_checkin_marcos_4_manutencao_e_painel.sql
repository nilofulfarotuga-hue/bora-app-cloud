-- Bloco D · fechar-pendencias-2026-10-20 — marcos do check-in (Bora Todo Dia).
-- Parte 4/4 (manutencao, painel admin e tarefa horaria). Base: tabela dos vales, sequencia continua, emissao no check-in, leitura do cliente,
-- manutencao horaria e funcoes do painel. Nao mexe nos tokens do check-in (Dia1..Dia7
-- continuam como estao) nem em nenhuma funcao de cobranca.
-- Marcos por sequencia continua: 7 (os tokens do Dia 7, so se mostra), 10, 15 e 30.
-- Falhou um dia -> volta a 1. Depois do dia 30 o ciclo recomeca no 1.

-- 10) Manutencao (de hora a hora) -----------------------------------------------------
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

  RETURN jsonb_build_object('ok', true, 'expirados', v_exp, 'reservas_libertadas', v_lib,
                            'ativados', v_atv, 'espera_expirada', v_esp_exp);
END;
$function$;

-- 11) Painel admin ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_checkin_premios_lista(p_estado text DEFAULT NULL, p_busca text DEFAULT NULL,
                                                               p_limite integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
  v_b text := NULLIF(lower(btrim(COALESCE(p_busca, ''))), '');
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.emitido_em DESC), '[]'::jsonb) INTO v
    FROM (
      SELECT x.emitido_em,
             public._checkin_vale_json(x) || jsonb_build_object(
               'user_id', x.user_id, 'cliente_nome', u.name, 'cliente_email', u.email,
               'custo_cents', x.custo_cents, 'pago_loja_em', x.pago_loja_em, 'pago_loja_nota', x.pago_loja_nota,
               'anulado_em', x.anulado_em, 'motivo', x.motivo, 'ciclo_inicio', x.ciclo_inicio,
               'ativado_em', x.ativado_em) AS j
        FROM public.checkin_premios_vales x
        LEFT JOIN public.users u ON u.id = x.user_id
       WHERE (p_estado IS NULL OR p_estado = '' OR x.estado = p_estado
              OR (p_estado = 'a_pagar_loja' AND x.estado = 'usado' AND x.tipo = 'produto' AND x.pago_loja_em IS NULL))
         AND (v_b IS NULL OR lower(COALESCE(u.name, '')) LIKE '%' || v_b || '%'
              OR lower(COALESCE(u.email, '')) LIKE '%' || v_b || '%'
              OR x.id::text = v_b OR x.pedido_id = v_b)
       ORDER BY x.emitido_em DESC
       LIMIT LEAST(GREATEST(COALESCE(p_limite, 200), 1), 1000)
    ) z;
  RETURN v;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_premios_resumo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mes_ini timestamptz := (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
  v_estados jsonb;
  v_marcos  jsonb;
  v_lojas   jsonb;
  v_tecto   integer := COALESCE((public._checkin_marco_cfg('checkin_marco_tecto_mensal', '10'::jsonb) #>> '{}')::int, 10);
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_object_agg(e.estado, e.n), '{}'::jsonb) INTO v_estados
    FROM (SELECT estado, count(*) n FROM public.checkin_premios_vales GROUP BY estado) e;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'chave', m.marco_chave, 'marco', m.marco, 'emitidos', m.emitidos, 'usados', m.usados,
           'custo_usados_cents', m.custo, 'emitidos_mes', m.emitidos_mes, 'ativados_mes', m.ativados_mes)
           ORDER BY m.marco), '[]'::jsonb)
    INTO v_marcos
    FROM (SELECT marco_chave, min(marco) marco, count(*) emitidos,
                 count(*) FILTER (WHERE estado = 'usado') usados,
                 COALESCE(sum(custo_cents) FILTER (WHERE estado = 'usado'), 0) custo,
                 count(*) FILTER (WHERE emitido_em >= v_mes_ini) emitidos_mes,
                 count(*) FILTER (WHERE ativado_em >= v_mes_ini AND estado NOT IN ('guardado','a_espera_pedido','anulado')) ativados_mes
            FROM public.checkin_premios_vales GROUP BY marco_chave) m;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('loja_id', l.loja_id, 'loja_nome', r.name, 'vales', l.n,
                                               'custo_cents', l.custo, 'ids', l.ids)), '[]'::jsonb)
    INTO v_lojas
    FROM (SELECT loja_id, count(*) n, sum(custo_cents) custo, jsonb_agg(id) ids
            FROM public.checkin_premios_vales
           WHERE estado = 'usado' AND tipo = 'produto' AND pago_loja_em IS NULL
           GROUP BY loja_id) l
    LEFT JOIN public.restaurants r ON r.id = l.loja_id;
  RETURN jsonb_build_object(
    'por_estado', v_estados,
    'por_marco', v_marcos,
    'a_pagar_lojas', v_lojas,
    'custo_mes_cents', (SELECT COALESCE(sum(custo_cents), 0) FROM public.checkin_premios_vales
                         WHERE estado = 'usado' AND usado_em >= v_mes_ini),
    'custo_total_cents', (SELECT COALESCE(sum(custo_cents), 0) FROM public.checkin_premios_vales WHERE estado = 'usado'),
    'tecto_mensal', v_tecto,
    'mes_inicio', v_mes_ini);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_premio_anular(p_vale_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin record;
  v public.checkin_premios_vales;
BEGIN
  SELECT * INTO v_admin FROM public._admin_op_guard();
  IF NULLIF(btrim(COALESCE(p_motivo, '')), '') IS NULL THEN RAISE EXCEPTION 'motivo_obrigatorio'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'vale_nao_encontrado'; END IF;
  IF v.estado NOT IN ('por_usar','reservado','guardado','a_espera_pedido') THEN
    RAISE EXCEPTION 'vale_nao_pode_ser_anulado (estado %)', v.estado;
  END IF;
  UPDATE public.checkin_premios_vales
     SET estado = 'anulado', anulado_em = now(), anulado_por = v_admin.admin_id,
         motivo = btrim(p_motivo), reservado_ate = NULL, atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;
  PERFORM public.log_admin_action('checkin_premio_anulado', 'checkin_premio', v.id::text,
    jsonb_build_object('user_id', v.user_id, 'marco', v.marco, 'motivo', btrim(p_motivo)));
  RETURN public._checkin_vale_json(v);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_premio_dar(p_user_id uuid, p_chave text, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin record;
  m jsonb;
  v_id uuid;
  v public.checkin_premios_vales;
BEGIN
  SELECT * INTO v_admin FROM public._admin_op_guard();
  IF NULLIF(btrim(COALESCE(p_motivo, '')), '') IS NULL THEN RAISE EXCEPTION 'motivo_obrigatorio'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p_user_id) THEN RAISE EXCEPTION 'cliente_nao_encontrado'; END IF;
  SELECT x INTO m FROM jsonb_array_elements(public._checkin_marcos_config()) x
   WHERE x ->> 'chave' = p_chave AND x ->> 'tipo' IN ('produto','servico') LIMIT 1;
  IF m IS NULL THEN RAISE EXCEPTION 'marco_desconhecido: %', p_chave; END IF;
  -- dado a mao: sem tecto nem regra do pedido (o admin decide)
  v_id := public._checkin_vale_emitir(p_user_id, m, NULL, 'admin', v_admin.admin_id, btrim(p_motivo));
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = v_id;
  PERFORM public.log_admin_action('checkin_premio_dado', 'checkin_premio', v_id::text,
    jsonb_build_object('user_id', p_user_id, 'chave', p_chave, 'motivo', btrim(p_motivo)));
  RETURN public._checkin_vale_json(v);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_premio_marcar_usado(p_vale_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin record;
  v public.checkin_premios_vales;
BEGIN
  SELECT * INTO v_admin FROM public._admin_op_guard();
  IF NULLIF(btrim(COALESCE(p_motivo, '')), '') IS NULL THEN RAISE EXCEPTION 'motivo_obrigatorio'; END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'vale_nao_encontrado'; END IF;
  IF v.estado NOT IN ('por_usar','reservado') THEN
    RAISE EXCEPTION 'vale_nao_pode_ser_usado (estado %)', v.estado;
  END IF;
  UPDATE public.checkin_premios_vales
     SET estado = 'usado', usado_em = now(), reservado_ate = NULL,
         motivo = 'entregue à mão: ' || btrim(p_motivo), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;
  PERFORM public.log_admin_action('checkin_premio_entregue_mao', 'checkin_premio', v.id::text,
    jsonb_build_object('user_id', v.user_id, 'marco', v.marco, 'motivo', btrim(p_motivo)));
  RETURN public._checkin_vale_json(v);
END;
$function$;

-- Enquanto o acerto semanal da loja nao inclui os premios sozinho, o painel marca aqui o que ja se pagou a loja.
CREATE OR REPLACE FUNCTION public.admin_checkin_premios_pagar_loja(p_vale_ids uuid[], p_nota text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin record;
  v_n integer;
  v_soma integer;
BEGIN
  SELECT * INTO v_admin FROM public._admin_op_guard();
  WITH u AS (
    UPDATE public.checkin_premios_vales
       SET pago_loja_em = now(), pago_loja_por = v_admin.admin_id,
           pago_loja_nota = NULLIF(btrim(COALESCE(p_nota, '')), ''), atualizado_em = now()
     WHERE id = ANY (COALESCE(p_vale_ids, '{}'::uuid[]))
       AND estado = 'usado' AND tipo = 'produto' AND pago_loja_em IS NULL
    RETURNING custo_cents)
  SELECT count(*), COALESCE(sum(custo_cents), 0) INTO v_n, v_soma FROM u;
  PERFORM public.log_admin_action('checkin_premios_pagos_loja', 'checkin_premio', NULL::text,
    jsonb_build_object('vales', to_jsonb(p_vale_ids), 'n', v_n, 'custo_cents', v_soma, 'nota', p_nota));
  RETURN jsonb_build_object('ok', true, 'n', v_n, 'custo_cents', v_soma);
END;
$function$;

-- Permissoes: fechado a quem nao tem sessao
REVOKE ALL ON FUNCTION public.checkin_premios_manutencao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_checkin_premios_lista(text, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_premios_resumo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_premio_anular(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_premio_dar(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_premio_marcar_usado(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_premios_pagar_loja(uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_checkin_premios_lista(text, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_premios_resumo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_premio_anular(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_premio_dar(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_premio_marcar_usado(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_premios_pagar_loja(uuid[], text) TO authenticated;

-- 13) Tarefa de hora a hora (aos :17) ---------------------------------------------------
SELECT cron.schedule('checkin-premios-manutencao', '17 * * * *', 'SELECT public.checkin_premios_manutencao();');
