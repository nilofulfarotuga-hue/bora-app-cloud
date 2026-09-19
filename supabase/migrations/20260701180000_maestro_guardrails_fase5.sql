-- ═══════════════════════════════════════════════════════════════════════════
-- FASE 5 — Guardrails do Maestro (corrige 2 defeitos observados no 1º ciclo)
-- ═══════════════════════════════════════════════════════════════════════════
-- Contexto: no item "Visualizador de auditoria" (ordem=10, goal 'paridade-admin-360')
-- o ciclo do maestro:
--   (1) moveu o item para `aguarda_ti` com uma robot_suggestion de payload VAZIO/NULL
--       → sem diff/evidência para o Danilo rever na Central; e
--   (2) NÃO detetou que o ecrã JÁ EXISTIA e estava wired
--       (lib/screens/admin/admin_audit_log_screen.dart, rota admin_dashboard_screen.dart:669),
--       simulando uma "construção" em vez de reconhecer a paridade já satisfeita.
--
-- Esta migration é 🟡 TRAVA-SAFE (zero tabelas/funções financeiras). Fortalece dois
-- pontos determinísticos que o maestro NÃO pode contornar:
--   (a) maestro_link_suggestion recusa `aguarda_ti` sem conteúdo revisável; e
--   (b) maestro_mark_preexisting: caminho canónico p/ "já existe no código?" —
--       marca a paridade satisfeita (feito) COM evidência de ficheiros, sem fabricar
--       uma suggestion nem executar payload.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── (a) GUARD: nunca `aguarda_ti` sem evidência revisável ───────────────────
-- Revisável = payload_execucao concreto (N1/N2 — 1 toque executável ou nota de
-- paridade) OU proposta substancial (N3 propõe-only: o PLANO é a evidência).
-- Bloqueia exatamente o bug observado (payload vazio + proposta vazia/curta),
-- sem partir os N3 legítimos (payload null + proposta real).
CREATE OR REPLACE FUNCTION public.maestro_link_suggestion(
  p_item_id uuid, p_suggestion_id uuid,
  p_juiz_veredito text, p_juiz_detalhe jsonb DEFAULT '{}'::jsonb,
  p_novo_estado text DEFAULT 'aguarda_ti'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sug_id      uuid;
  v_payload     jsonb;
  v_proposta    text;
  v_revisavel   boolean;
BEGIN
  IF p_juiz_veredito NOT IN ('pendente','aprovado','rejeitado') THEN
    RAISE EXCEPTION 'JUIZ_VEREDITO_INVALIDO';
  END IF;
  IF p_novo_estado NOT IN ('a_correr','aguarda_ti','aprovado','feito','rejeitado','bloqueado_trava') THEN
    RAISE EXCEPTION 'ESTADO_INVALIDO';
  END IF;

  -- GUARD (defeito 1): um item só entra em `aguarda_ti` (fila da Central) se houver
  -- algo concreto para o Danilo rever. Sem isto, a entrada da Central é uma casca vazia.
  IF p_novo_estado = 'aguarda_ti' THEN
    v_sug_id := COALESCE(
      p_suggestion_id,
      (SELECT suggestion_id FROM public.autonomy_backlog_items WHERE id = p_item_id)
    );
    IF v_sug_id IS NULL THEN
      RAISE EXCEPTION 'AGUARDA_TI_SEM_SUGGESTION: item % nao tem suggestion ligada', p_item_id;
    END IF;
    SELECT payload_execucao, proposta INTO v_payload, v_proposta
      FROM public.robot_suggestions WHERE id = v_sug_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'AGUARDA_TI_SUGGESTION_INEXISTENTE: %', v_sug_id;
    END IF;
    v_revisavel := (v_payload IS NOT NULL AND v_payload <> '{}'::jsonb)
                   OR (char_length(COALESCE(v_proposta,'')) >= 40);
    IF NOT v_revisavel THEN
      RAISE EXCEPTION 'AGUARDA_TI_SEM_EVIDENCIA: payload_execucao vazio E proposta insuficiente '
                      '(item %, suggestion %). Anexa payload/nota ou um PLANO na proposta antes de enfileirar.',
                      p_item_id, v_sug_id;
    END IF;
  END IF;

  UPDATE public.autonomy_backlog_items
     SET suggestion_id = COALESCE(p_suggestion_id, suggestion_id),
         juiz_veredito = p_juiz_veredito,
         juiz_detalhe  = COALESCE(p_juiz_detalhe, '{}'::jsonb),
         estado        = p_novo_estado,
         updated_at    = now()
   WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ITEM_NAO_ENCONTRADO');
  END IF;
  -- recalcula o placar do goal (itens feitos)
  UPDATE public.autonomy_goals g
     SET metrica_atual = (SELECT count(*) FROM public.autonomy_backlog_items b
                           WHERE b.goal_id = g.id AND b.estado = 'feito'),
         updated_at = now()
   WHERE g.id = (SELECT goal_id FROM public.autonomy_backlog_items WHERE id = p_item_id);
  RETURN jsonb_build_object('ok', true, 'item_id', p_item_id, 'estado', p_novo_estado);
END;
$$;

-- ─── (b) DETEÇÃO "já existe no código?" — caminho canónico de paridade ────────
-- Quando o maestro deteta que o domínio JÁ está implementado e wired, chama isto em
-- vez de fabricar uma suggestion/construção. Marca a paridade satisfeita (feito) com
-- a evidência dos ficheiros existentes. NÃO executa payload, NÃO cria robot_suggestion.
-- Exige evidência real (lista de ficheiros) — não deixa "marcar feito" sem prova.
CREATE OR REPLACE FUNCTION public.maestro_mark_preexisting(
  p_item_id   uuid,
  p_evidencia jsonb,          -- { "ficheiros": [...], "rota": "...", "rpcs": [...] }
  p_nota      text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_goal_id uuid;
BEGIN
  IF p_evidencia IS NULL
     OR jsonb_typeof(p_evidencia->'ficheiros') <> 'array'
     OR jsonb_array_length(p_evidencia->'ficheiros') < 1 THEN
    RAISE EXCEPTION 'PREEXISTENTE_SEM_FICHEIROS: p_evidencia precisa de "ficheiros":[...] com >=1 ficheiro';
  END IF;

  UPDATE public.autonomy_backlog_items
     SET estado        = 'feito',
         juiz_veredito = 'aprovado',
         juiz_detalhe  = COALESCE(juiz_detalhe,'{}'::jsonb)
                         || jsonb_build_object(
                              'preexistente', true,
                              'evidencia', p_evidencia,
                              'nota', p_nota,
                              'marcado_em', now()
                            ),
         updated_at    = now()
   WHERE id = p_item_id
  RETURNING goal_id INTO v_goal_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ITEM_NAO_ENCONTRADO');
  END IF;

  UPDATE public.autonomy_goals g
     SET metrica_atual = (SELECT count(*) FROM public.autonomy_backlog_items b
                           WHERE b.goal_id = g.id AND b.estado = 'feito'),
         updated_at = now()
   WHERE g.id = v_goal_id;

  RETURN jsonb_build_object('ok', true, 'item_id', p_item_id, 'estado', 'feito', 'preexistente', true);
END;
$$;

-- ─── Grants (mesmo padrão de robot_* / maestro_*) ────────────────────────────
REVOKE ALL ON FUNCTION public.maestro_link_suggestion(uuid, uuid, text, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maestro_mark_preexisting(uuid, jsonb, text)             FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.maestro_link_suggestion(uuid, uuid, text, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.maestro_mark_preexisting(uuid, jsonb, text)             TO service_role;
