-- ═══════════════════════════════════════════════════════════════════════════
-- FASE 5 — Camada de Goals da Autonomia (Híbrido)
-- ═══════════════════════════════════════════════════════════════════════════
-- Decisão do Danilo (2026-07-01): NÃO duplicar a fila. `robot_suggestions`
-- continua a FILA de itens; esta migration acrescenta só a camada de GOALS:
--   • autonomy_goals          → o /goal + placar de paridade + tetos.
--   • autonomy_backlog_items  → os ~19 domínios admin em falta (a auditoria),
--                               cada um aponta para uma robot_suggestions quando
--                               o loop o pega, e guarda o veredito do Juiz.
--
-- 🔒 TRAVA-SAFE: zero tabelas/funções financeiras. Kill switch (PARAR TUDO) e o
--    DIAL DE CONFIANÇA são REUTILIZADOS de platform_settings.robot_b_enabled /
--    robot_b_auto_level1_enabled (não financeiros → a Trava não os bloqueia).
--    RLS fechado (sem policies) — acesso só via RPC SECURITY DEFINER / service_role,
--    exatamente como robot_suggestions.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Tabelas ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.autonomy_goals (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                  text NOT NULL UNIQUE,
  titulo                text NOT NULL,
  descricao             text NOT NULL DEFAULT '',
  metrica_alvo          numeric NOT NULL,                 -- meta (ex.: 20 domínios)
  metrica_atual         numeric NOT NULL DEFAULT 0,       -- placar ao vivo
  unidade               text NOT NULL DEFAULT 'dominios',
  estado                text NOT NULL DEFAULT 'ativo'
                          CHECK (estado IN ('ativo','pausado','concluido','cancelado')),
  -- TETOS (o envelope de segurança) — o maestro NUNCA os ultrapassa
  teto_max_turns        integer NOT NULL DEFAULT 40,
  teto_orcamento_tokens bigint  NOT NULL DEFAULT 2000000,
  cadencia_min          integer NOT NULL DEFAULT 60,      -- min entre itens (lento p/ começar)
  itens_por_ciclo       integer NOT NULL DEFAULT 1,       -- TETO BAIXO p/ o 1º run
  gastos_turns          integer NOT NULL DEFAULT 0,       -- consumido (o maestro incrementa)
  gastos_tokens         bigint  NOT NULL DEFAULT 0,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.autonomy_backlog_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id       uuid NOT NULL REFERENCES public.autonomy_goals(id) ON DELETE CASCADE,
  dominio       text NOT NULL,
  descricao     text NOT NULL DEFAULT '',
  nivel         smallint NOT NULL DEFAULT 2 CHECK (nivel IN (1,2,3)),
  zona          text NOT NULL DEFAULT 'verde'
                  CHECK (zona IN ('verde','amarela','vermelha')),
  prioridade    text NOT NULL DEFAULT 'P1'
                  CHECK (prioridade IN ('P0','P1','P2')),
  estado        text NOT NULL DEFAULT 'pendente'
                  CHECK (estado IN ('pendente','a_correr','aguarda_ti','aprovado',
                                    'feito','rejeitado','bloqueado_trava')),
  suggestion_id uuid REFERENCES public.robot_suggestions(id),  -- ponte p/ a fila
  juiz_veredito text CHECK (juiz_veredito IN ('pendente','aprovado','rejeitado')),
  juiz_detalhe  jsonb NOT NULL DEFAULT '{}'::jsonb,
  ordem         integer NOT NULL DEFAULT 100,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_autonomy_backlog_goal
  ON public.autonomy_backlog_items (goal_id, ordem);
CREATE INDEX IF NOT EXISTS idx_autonomy_backlog_estado
  ON public.autonomy_backlog_items (estado);
CREATE UNIQUE INDEX IF NOT EXISTS uq_autonomy_backlog_goal_dominio
  ON public.autonomy_backlog_items (goal_id, dominio);

-- RLS fechado (sem policies) — igual a robot_suggestions.
ALTER TABLE public.autonomy_goals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.autonomy_backlog_items  ENABLE ROW LEVEL SECURITY;

-- ─── RPCs de leitura (admin — a Central) ────────────────────────────────────
-- Painel completo: goals + placar + estado do kill switch + do dial + contagens.
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
    'kill_switch_parado', (COALESCE(v_kill, true) = false),  -- true = loop PARADO
    'dial_auto_l1',       COALESCE(v_dial, false),           -- true = 🟢 automático
    'goals', COALESCE((
      SELECT jsonb_agg(to_jsonb(g) ORDER BY g.created_at DESC) FROM (
        SELECT g.*,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id)               AS itens_total,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='feito')       AS itens_feitos,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='aguarda_ti')  AS itens_aguarda,
          (SELECT count(*) FROM public.autonomy_backlog_items b WHERE b.goal_id = g.id AND b.estado='a_correr')    AS itens_correndo
          FROM public.autonomy_goals g
      ) g
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_autonomy_backlog(
  p_goal_slug text DEFAULT NULL, p_estado text DEFAULT NULL,
  p_limit integer DEFAULT 200, p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(b) ORDER BY b.ordem, b.created_at) FROM (
      SELECT b.*, s.status AS suggestion_status, s.proposta AS suggestion_proposta
        FROM public.autonomy_backlog_items b
        LEFT JOIN public.robot_suggestions s ON s.id = b.suggestion_id
        LEFT JOIN public.autonomy_goals g   ON g.id = b.goal_id
       WHERE (p_goal_slug IS NULL OR g.slug = p_goal_slug)
         AND (p_estado    IS NULL OR b.estado = p_estado)
       ORDER BY b.ordem, b.created_at
       LIMIT LEAST(GREATEST(COALESCE(p_limit,200),1),500)
      OFFSET GREATEST(COALESCE(p_offset,0),0)
    ) b
  ), '[]'::jsonb);
END;
$$;

-- ─── Kill switch + Dial (admin escreve — só as 2 chaves não-financeiras) ─────
CREATE OR REPLACE FUNCTION public.admin_autonomy_set_switch(
  p_key text, p_enabled boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  IF p_key NOT IN ('robot_b_enabled','robot_b_auto_level1_enabled') THEN
    RAISE EXCEPTION 'CHAVE_NAO_PERMITIDA: apenas kill switch / dial da autonomia';
  END IF;
  INSERT INTO public.platform_settings(key, value, updated_at)
    VALUES (p_key, to_jsonb(p_enabled), now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
  RETURN jsonb_build_object('ok', true, 'key', p_key, 'enabled', p_enabled);
END;
$$;

-- ─── RPCs do maestro (service_role — o loop) ────────────────────────────────
-- Pega o próximo item pendente do goal (respeita o kill switch). Marca a_correr.
CREATE OR REPLACE FUNCTION public.maestro_next_backlog_item(p_goal_slug text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enabled boolean;
  v_item public.autonomy_backlog_items%ROWTYPE;
BEGIN
  SELECT COALESCE((value = 'true'::jsonb), true) INTO v_enabled
    FROM public.platform_settings WHERE key = 'robot_b_enabled';
  IF COALESCE(v_enabled, true) = false THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'KILL_SWITCH_ATIVO');
  END IF;
  SELECT b.* INTO v_item
    FROM public.autonomy_backlog_items b
    JOIN public.autonomy_goals g ON g.id = b.goal_id
   WHERE g.slug = p_goal_slug AND g.estado = 'ativo' AND b.estado = 'pendente'
   ORDER BY b.ordem, b.created_at
   LIMIT 1
   FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'SEM_ITENS_PENDENTES');
  END IF;
  UPDATE public.autonomy_backlog_items
     SET estado = 'a_correr', updated_at = now()
   WHERE id = v_item.id;
  v_item.estado := 'a_correr';  -- reflete o estado real no JSON devolvido
  RETURN jsonb_build_object('ok', true, 'item', to_jsonb(v_item));
END;
$$;

-- Liga o item a uma suggestion + regista o veredito do Juiz + move o estado.
CREATE OR REPLACE FUNCTION public.maestro_link_suggestion(
  p_item_id uuid, p_suggestion_id uuid,
  p_juiz_veredito text, p_juiz_detalhe jsonb DEFAULT '{}'::jsonb,
  p_novo_estado text DEFAULT 'aguarda_ti'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_juiz_veredito NOT IN ('pendente','aprovado','rejeitado') THEN
    RAISE EXCEPTION 'JUIZ_VEREDITO_INVALIDO';
  END IF;
  IF p_novo_estado NOT IN ('a_correr','aguarda_ti','aprovado','feito','rejeitado','bloqueado_trava') THEN
    RAISE EXCEPTION 'ESTADO_INVALIDO';
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

-- ─── Grants (mesmo padrão de robot_*) ───────────────────────────────────────
REVOKE ALL ON FUNCTION public.admin_autonomy_dashboard()                              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_autonomy_backlog(text, text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_autonomy_set_switch(text, boolean)                FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maestro_next_backlog_item(text)                         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.maestro_link_suggestion(uuid, uuid, text, jsonb, text)  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_autonomy_dashboard()                              TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_autonomy_backlog(text, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_autonomy_set_switch(text, boolean)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.maestro_next_backlog_item(text)                         TO service_role;
GRANT EXECUTE ON FUNCTION public.maestro_link_suggestion(uuid, uuid, text, jsonb, text)  TO service_role;
