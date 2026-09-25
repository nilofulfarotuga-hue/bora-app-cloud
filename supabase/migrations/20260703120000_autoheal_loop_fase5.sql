-- ═══════════════════════════════════════════════════════════════════════════
-- FASE 5 — O FIO DA AUTO-CURA (maestro ↔ Juiz até nota >= 9)
-- ═══════════════════════════════════════════════════════════════════════════
-- Contexto: as 7 colunas de nota/olhos/histórico já existem em
-- autonomy_backlog_items (aplicadas via MCP pelo Claude.ai). O que FALTAVA para o
-- loop fechar sozinho — e esta migration acrescenta — é:
--   (1) os 2 estados intermédios do ciclo no CHECK de `estado`:
--         • em_correcao          → o Juiz reprovou (<9) e o maestro vai corrigir
--         • travado_pediu_ajuda  → esgotou max_tentativas sem chegar a 9 → Central
--   (2) a RPC determinística que REGISTA a avaliação do Juiz (nota + olhos),
--       incrementa `tentativas`, empilha em `historico_avaliacoes` e DECIDE o
--       próximo estado pelo gate `nota >= nota_minima_aceite`. O gate vive na RPC
--       (não no agente) — o robô nunca o afrouxa, como os outros tetos do Robot B.
--   (3) a RPC que grava a pesquisa de referência (`referencia_benchmark`).
--   (4) o dashboard passa a contar em_correcao / travado_pediu_ajuda (a prova).
--
-- 🔒 TRAVA-SAFE: zero tabelas/funções financeiras. Só mexe nas tabelas da
--    autonomia (autonomy_*), RLS fechado, acesso só via RPC SECURITY DEFINER /
--    service_role — exatamente como as RPCs Fase 5 existentes.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── (1) Novos estados do ciclo de auto-cura ────────────────────────────────
ALTER TABLE public.autonomy_backlog_items
  DROP CONSTRAINT IF EXISTS autonomy_backlog_items_estado_check;
ALTER TABLE public.autonomy_backlog_items
  ADD CONSTRAINT autonomy_backlog_items_estado_check
  CHECK (estado IN ('pendente','a_correr','em_correcao','aguarda_ti','aprovado',
                    'feito','rejeitado','travado_pediu_ajuda','bloqueado_trava'));

-- ─── (2) Pesquisa de referência (Parte B do maestro) ────────────────────────
-- Grava os "melhores" que o maestro escolheu para o domínio do item, antes de
-- construir e a cada reprovação. Só escreve a coluna referencia_benchmark.
CREATE OR REPLACE FUNCTION public.maestro_set_benchmark(
  p_item_id uuid, p_referencia jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_referencia IS NULL OR jsonb_typeof(p_referencia) <> 'object' THEN
    RAISE EXCEPTION 'BENCHMARK_INVALIDO: p_referencia precisa de um objeto jsonb';
  END IF;
  UPDATE public.autonomy_backlog_items
     SET referencia_benchmark = p_referencia, updated_at = now()
   WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ITEM_NAO_ENCONTRADO');
  END IF;
  RETURN jsonb_build_object('ok', true, 'item_id', p_item_id);
END;
$$;

-- ─── (2) O gate determinístico da auto-cura ─────────────────────────────────
-- O Juiz chama isto no fim de CADA avaliação. A RPC:
--   • valida a nota (0-10) e o teto-sem-olhos (sem screenshot da própria app,
--     tem_visual=false → a nota é limitada a 8, forçando o sistema a resolver a
--     captura em vez de "chutar 10");
--   • incrementa tentativas e empilha {tentativa,nota,faltou,visual,ts} no histórico;
--   • grava juiz_nota / tem_visual / juiz_detalhe;
--   • DECIDE o próximo estado pelo gate nota >= nota_minima_aceite:
--       nota>=min                         → veredito 'aprovado', decisao 'aprovado_juiz'
--                                           (o maestro liga a suggestion → aguarda_ti)
--       nota<min E tentativas<max         → estado 'em_correcao'   (volta ao maestro)
--       nota<min E tentativas>=max        → estado 'travado_pediu_ajuda' (cai na Central)
-- Devolve a decisão + o histórico para o maestro/registo.
CREATE OR REPLACE FUNCTION public.maestro_record_juiz_evaluation(
  p_item_id    uuid,
  p_nota       numeric,
  p_detalhe    jsonb    DEFAULT '{}'::jsonb,   -- rubrica: {criterios, nota_por_criterio, o_que_falta_pra_10}
  p_tem_visual boolean  DEFAULT false,
  p_faltou     jsonb    DEFAULT '[]'::jsonb    -- o que faltou p/ 10 (resumo curto)
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_item     public.autonomy_backlog_items%ROWTYPE;
  v_nota     numeric;
  v_teto8    boolean := false;
  v_tent     integer;
  v_decisao  text;
  v_estado   text;
  v_veredito text;
BEGIN
  SELECT * INTO v_item FROM public.autonomy_backlog_items WHERE id = p_item_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ITEM_NAO_ENCONTRADO');
  END IF;

  v_nota := GREATEST(0, LEAST(10, COALESCE(p_nota, 0)));
  -- TETO SEM OLHOS: sem screenshot da própria app, nunca acima de 8.
  IF COALESCE(p_tem_visual, false) = false AND v_nota > 8 THEN
    v_nota  := 8;
    v_teto8 := true;
  END IF;

  v_tent := COALESCE(v_item.tentativas, 0) + 1;

  IF v_nota >= COALESCE(v_item.nota_minima_aceite, 9) THEN
    v_decisao  := 'aprovado_juiz';
    v_estado   := v_item.estado;          -- não muda aqui; o maestro liga a suggestion → aguarda_ti
    v_veredito := 'aprovado';
  ELSIF v_tent < COALESCE(v_item.max_tentativas, 5) THEN
    v_decisao  := 'em_correcao';
    v_estado   := 'em_correcao';
    v_veredito := 'rejeitado';
  ELSE
    v_decisao  := 'travado_pediu_ajuda';
    v_estado   := 'travado_pediu_ajuda';
    v_veredito := 'rejeitado';
  END IF;

  UPDATE public.autonomy_backlog_items
     SET juiz_nota     = v_nota,
         tem_visual    = COALESCE(p_tem_visual, false),
         tentativas    = v_tent,
         juiz_veredito = v_veredito,
         juiz_detalhe  = COALESCE(p_detalhe, '{}'::jsonb)
                         || jsonb_build_object('teto_sem_olhos_aplicado', v_teto8),
         historico_avaliacoes = COALESCE(historico_avaliacoes, '[]'::jsonb)
                         || jsonb_build_array(jsonb_build_object(
                              'tentativa', v_tent,
                              'nota',      v_nota,
                              'faltou',    COALESCE(p_faltou, '[]'::jsonb),
                              'visual',    COALESCE(p_tem_visual, false),
                              'ts',        now()
                            )),
         estado        = v_estado,
         updated_at    = now()
   WHERE id = p_item_id;

  RETURN jsonb_build_object(
    'ok', true, 'item_id', p_item_id,
    'decisao', v_decisao, 'estado', v_estado,
    'nota', v_nota, 'tentativa', v_tent,
    'teto_sem_olhos_aplicado', v_teto8,
    'nota_minima', COALESCE(v_item.nota_minima_aceite, 9),
    'max_tentativas', COALESCE(v_item.max_tentativas, 5)
  );
END;
$$;

-- ─── (4) Dashboard: contar os estados do ciclo (a prova na Central) ──────────
CREATE OR REPLACE FUNCTION public.admin_autonomy_dashboard()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_kill boolean;
  v_dial boolean;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE((value = 'true'::jsonb), true)  INTO v_kill
    FROM public.platform_settings WHERE key = 'robot_b_enabled';
  SELECT COALESCE((value = 'true'::jsonb), false) INTO v_dial
    FROM public.platform_settings WHERE key = 'robot_b_auto_level1_enabled';
  RETURN jsonb_build_object(
    'kill_switch_parado', (COALESCE(v_kill, true) = false),
    'dial_auto_l1',       COALESCE(v_dial, false),
    'goals', COALESCE((
      SELECT jsonb_agg(to_jsonb(g) ORDER BY g.created_at DESC) FROM (
        SELECT g.*,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id)                                AS itens_total,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='feito')           AS itens_feitos,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='aguarda_ti')      AS itens_aguarda,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='a_correr')        AS itens_correndo,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='em_correcao')     AS itens_em_correcao,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='travado_pediu_ajuda') AS itens_travados
          FROM public.autonomy_goals g
      ) g
    ), '[]'::jsonb)
  );
END;
$$;

-- ─── Grants (mesmo padrão das RPCs Fase 5) ──────────────────────────────────
REVOKE ALL ON FUNCTION public.maestro_set_benchmark(uuid, jsonb)                              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maestro_record_juiz_evaluation(uuid, numeric, jsonb, boolean, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.maestro_set_benchmark(uuid, jsonb)                              TO service_role;
GRANT EXECUTE ON FUNCTION public.maestro_record_juiz_evaluation(uuid, numeric, jsonb, boolean, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_autonomy_dashboard()                                      TO authenticated;
